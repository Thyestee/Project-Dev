extends Node3D
# The voxel world: block data, terrain generation, edits, ray casts and the chunk meshes.
#
# Blocks live in one flat array with a one-block border on every side (air around and above,
# bedrock below), so neighbour lookups never need bounds checks.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Textures := preload("res://scripts/textures.gd")
const Mesher := preload("res://scripts/chunk_mesher.gd")

const SX := 96
const SY := 64
const SZ := 96
const CHUNK := 16
const CHUNK_SHIFT := 4
const PX := SX + 2
const PZ := SZ + 2
const LAYER := PX * PZ

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2DArray tiles : source_color, filter_nearest_mipmap_anisotropic, repeat_disable;
uniform vec3 lamp_pos = vec3(0.0);
uniform float lamp_range = 8.0;
uniform float daylight = 1.0;

varying vec3 world_pos;
varying vec2 info;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	info = UV2;
}

void fragment() {
	vec4 tex = texture(tiles, vec3(UV, info.x));
	// Your head lamp lights whatever is close, sky light does the rest.
	float lamp = 1.0 - clamp(distance(world_pos, lamp_pos) / lamp_range, 0.0, 1.0);
	lamp = lamp * lamp * (3.0 - 2.0 * lamp);
	vec3 light = vec3(COLOR.g * daylight) + vec3(1.0, 0.86, 0.66) * lamp;
	light = clamp(light, vec3(0.02), vec3(1.0));
	vec3 col = tex.rgb * COLOR.r * light;
	// Treasure blocks shimmer.
	float shimmer = 0.5 + 0.5 * sin(TIME * 3.0 + world_pos.x * 1.7 + world_pos.y * 2.3 + world_pos.z * 1.3);
	col += tex.rgb * info.y * (0.25 + 0.35 * shimmer);
	ALBEDO = col;
}
"""

var blocks := PackedByteArray()
var top := PackedInt32Array()      # highest sky-blocking block of each column (border-padded index)
var ground := PackedInt32Array()   # generated ground height of each column
var treasures := {}                # block index -> {"cell": Vector3i, "type": int}
var edits := {}                    # block index -> block id, for everything changed since generation
var world_seed := 0
var material: ShaderMaterial
var _meshes := {}                  # chunk Vector3i -> MeshInstance3D
var _dirty := {}
var _build_queue: Array[Vector3i] = []
var _build_total := 0


func _ready() -> void:
	Textures.build()
	var shader := Shader.new()
	shader.code = SHADER
	material = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tiles", Textures.array)


func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	while not _build_queue.is_empty() and Time.get_ticks_usec() - start < 12000:
		_build_chunk(_build_queue.pop_back())
	for key: Vector3i in _dirty:
		_build_chunk(key)
	_dirty.clear()


# --- Lookups -----------------------------------------------------------------

static func index(x: int, y: int, z: int) -> int:
	return (x + 1) + (z + 1) * PX + (y + 1) * LAYER


static func column(x: int, z: int) -> int:
	return (x + 1) + (z + 1) * PX


static func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < SX and c.y < SY and c.z < SZ


func block(x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if x < 0 or z < 0 or x >= SX or z >= SZ or y >= SY:
		return Blocks.AIR
	return blocks[index(x, y, z)]


# For movement: the world's sides are walls, its floor is bedrock and its top is open.
func is_solid(x: int, y: int, z: int) -> bool:
	if x < 0 or z < 0 or x >= SX or z >= SZ or y < 0:
		return true
	if y >= SY:
		return false
	return blocks[index(x, y, z)] != Blocks.AIR


func box_hits_solid(lo: Vector3, hi: Vector3) -> bool:
	for y in range(floori(lo.y), floori(hi.y - 0.0001) + 1):
		for z in range(floori(lo.z), floori(hi.z - 0.0001) + 1):
			for x in range(floori(lo.x), floori(hi.x - 0.0001) + 1):
				if is_solid(x, y, z):
					return true
	return false


func treasure_at(c: Vector3i) -> Dictionary:
	return treasures.get(index(c.x, c.y, c.z), {})


func nearest_treasure_distance(p: Vector3) -> float:
	var best := INF
	for t: Dictionary in treasures.values():
		var c: Vector3i = t["cell"]
		best = minf(best, p.distance_to(Vector3(c) + Vector3(0.5, 0.5, 0.5)))
	return best


func sky_at(p: Vector3) -> float:
	var x := floori(p.x)
	var y := floori(p.y)
	var z := floori(p.z)
	if x < 0 or z < 0 or x >= SX or z >= SZ or y >= SY:
		return 1.0
	return Mesher.sky_light(top, ground, column(x, z), y, PX)


# Metres below the original ground for feet at p.
func depth_at(p: Vector3) -> int:
	var x := clampi(floori(p.x), 0, SX - 1)
	var z := clampi(floori(p.z), 0, SZ - 1)
	return maxi(0, ground[column(x, z)] + 1 - floori(p.y))


func spawn_point() -> Vector3:
	return surface_point(Vector3(SX * 0.5, 0.0, SZ * 0.5))


func surface_point(p: Vector3) -> Vector3:
	var x := clampi(floori(p.x), 0, SX - 1)
	var z := clampi(floori(p.z), 0, SZ - 1)
	return Vector3(x + 0.5, top[column(x, z)] + 1.0, z + 0.5)


# Walks the ray through the grid one cell at a time. Returns the first non-air cell, the empty
# cell just before it (where a placed block would go) and the block, or {} if nothing is in reach.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var cell := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3(_cell_span(dir.x), _cell_span(dir.y), _cell_span(dir.z))
	var t_max := Vector3(_first_crossing(origin.x, dir.x, cell.x), _first_crossing(origin.y, dir.y, cell.y), _first_crossing(origin.z, dir.z, cell.z))
	var prev := cell
	var t := 0.0
	while t <= max_dist:
		var b := block(cell.x, cell.y, cell.z)
		if b != Blocks.AIR:
			return {"cell": cell, "prev": prev, "block": b}
		prev = cell
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t = t_max.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			cell.y += step.y
			t = t_max.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			t = t_max.z
			t_max.z += t_delta.z
	return {}


static func _cell_span(d: float) -> float:
	return absf(1.0 / d) if d != 0.0 else INF


static func _first_crossing(o: float, d: float, c: int) -> float:
	if d > 0.0:
		return (c + 1 - o) / d
	if d < 0.0:
		return (o - c) / -d
	return INF


# --- Edits -------------------------------------------------------------------

func set_block(c: Vector3i, b: int) -> void:
	var i := index(c.x, c.y, c.z)
	var old := blocks[i]
	if old == b:
		return
	blocks[i] = b
	edits[i] = b
	if Blocks.is_treasure(old):
		treasures.erase(i)
	var col := column(c.x, c.z)
	var old_top := top[col]
	_update_top(c.x, c.z)
	_mark_box(c - Vector3i.ONE, c + Vector3i.ONE)
	# Opening or closing a column to the sky relights everything around it.
	if top[col] != old_top:
		var lo := mini(old_top, top[col])
		var hi := maxi(old_top, top[col])
		_mark_box(Vector3i(c.x - 2, lo - 1, c.z - 2), Vector3i(c.x + 2, hi + 2, c.z + 2))


func apply_edits(list: Array) -> void:
	for k in range(0, list.size() - 1, 2):
		var i := int(list[k])
		var b := int(list[k + 1])
		if i >= 0 and i < blocks.size():
			blocks[i] = b
			edits[i] = b
	for i: int in treasures.keys():
		if not Blocks.is_treasure(blocks[i]):
			treasures.erase(i)
	for z in SZ:
		for x in SX:
			_update_top(x, z)


func edits_list() -> Array:
	var out := []
	for i: int in edits:
		out.append(i)
		out.append(edits[i])
	return out


func _update_top(x: int, z: int) -> void:
	var col := column(x, z)
	var y := SY - 1
	var i := index(x, y, z)
	while y >= 0 and not Blocks.BLOCKS_SKY[blocks[i]]:
		y -= 1
		i -= LAYER
	top[col] = y


# --- Chunk meshes --------------------------------------------------------------

func queue_all_chunks(center: Vector3) -> void:
	_build_queue.clear()
	for cy in SY >> CHUNK_SHIFT:
		for cz in SZ >> CHUNK_SHIFT:
			for cx in SX >> CHUNK_SHIFT:
				_build_queue.append(Vector3i(cx, cy, cz))
	# Nearest chunks last, since the queue is built from the back.
	var c := center / CHUNK - Vector3(0.5, 0.5, 0.5)
	_build_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return Vector3(a).distance_squared_to(c) > Vector3(b).distance_squared_to(c))
	_build_total = _build_queue.size()


func build_progress() -> float:
	if _build_total == 0:
		return 0.0
	return 1.0 - float(_build_queue.size()) / _build_total


func _mark_box(lo: Vector3i, hi: Vector3i) -> void:
	var c0 := Vector3i(clampi(lo.x, 0, SX - 1), clampi(lo.y, 0, SY - 1), clampi(lo.z, 0, SZ - 1))
	var c1 := Vector3i(clampi(hi.x, 0, SX - 1), clampi(hi.y, 0, SY - 1), clampi(hi.z, 0, SZ - 1))
	for cy in range(c0.y >> CHUNK_SHIFT, (c1.y >> CHUNK_SHIFT) + 1):
		for cz in range(c0.z >> CHUNK_SHIFT, (c1.z >> CHUNK_SHIFT) + 1):
			for cx in range(c0.x >> CHUNK_SHIFT, (c1.x >> CHUNK_SHIFT) + 1):
				_dirty[Vector3i(cx, cy, cz)] = true


func _build_chunk(key: Vector3i) -> void:
	var mesh := Mesher.build(blocks, top, ground, PX, LAYER, key.x * CHUNK, key.y * CHUNK, key.z * CHUNK, CHUNK)
	var mi: MeshInstance3D = _meshes.get(key)
	if mesh == null:
		if mi:
			mi.queue_free()
			_meshes.erase(key)
		return
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes[key] = mi
	mi.mesh = mesh


# --- Generation ----------------------------------------------------------------

func generate(new_seed: int) -> void:
	world_seed = new_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	blocks = PackedByteArray()
	blocks.resize(LAYER * (SY + 2))
	top = PackedInt32Array()
	top.resize(LAYER)
	top.fill(-1)
	ground = PackedInt32Array()
	ground.resize(LAYER)
	treasures.clear()
	edits.clear()
	for i in LAYER:
		blocks[i] = Blocks.BEDROCK
	var height := _noise(new_seed, 0.016, 4)
	var soil := _noise(new_seed + 1, 0.07, 1)
	var clay := _noise(new_seed + 2, 0.035, 2)
	var slate := _noise(new_seed + 3, 0.05, 2)
	for z in SZ:
		for x in SX:
			var col := column(x, z)
			var h := clampi(int(round(42.0 + height.get_noise_2d(x, z) * 14.0)), 30, SY - 12)
			ground[col] = h
			top[col] = h
			var soil_depth := 3 + int(round(soil.get_noise_2d(x, z) * 1.6))
			var clay_depth := soil_depth + (3 if clay.get_noise_2d(x, z) > 0.2 else 0)
			var slate_y := 15 + int(round(slate.get_noise_2d(x, z) * 5.0))
			var beach := h <= 36
			var i := index(x, 0, z)
			for y in h + 1:
				var d := h - y
				var b := Blocks.STONE
				if y == 0 or (y == 1 and rng.randf() < 0.5):
					b = Blocks.BEDROCK
				elif d == 0:
					b = Blocks.SAND if beach else Blocks.GRASS
				elif d < soil_depth:
					b = Blocks.SAND if beach else Blocks.DIRT
				elif d < clay_depth:
					b = Blocks.CLAY
				elif y < slate_y:
					b = Blocks.SLATE
				blocks[i] = b
				i += LAYER
	_add_pockets(rng)
	_carve_caves(rng)
	_plant_trees(rng)
	_place_treasures(rng)


static func _noise(s: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


# Blobs of gravel, clay and dirt scattered through the rock.
func _add_pockets(rng: RandomNumberGenerator) -> void:
	for n in 60:
		var c := Vector3i(rng.randi_range(0, SX - 1), 0, rng.randi_range(0, SZ - 1))
		c.y = rng.randi_range(3, ground[column(c.x, c.z)] - 5)
		var roll := rng.randf()
		var kind := Blocks.GRAVEL
		if roll < 0.3:
			kind = Blocks.CLAY
		elif roll < 0.45:
			kind = Blocks.DIRT
		var r := Vector3(rng.randf_range(1.2, 3.0), rng.randf_range(1.0, 2.2), rng.randf_range(1.2, 3.0))
		for dy in range(-3, 4):
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					if Vector3(dx / r.x, dy / r.y, dz / r.z).length_squared() > 1.0:
						continue
					var p := c + Vector3i(dx, dy, dz)
					if not in_bounds(p):
						continue
					var i := index(p.x, p.y, p.z)
					if blocks[i] == Blocks.STONE or blocks[i] == Blocks.SLATE:
						blocks[i] = kind


# A few winding caves, always with a few blocks of roof under the ground.
func _carve_caves(rng: RandomNumberGenerator) -> void:
	for n in 7:
		var p := Vector3(rng.randf_range(8.0, SX - 8.0), 0.0, rng.randf_range(8.0, SZ - 8.0))
		p.y = rng.randf_range(6.0, ground[column(int(p.x), int(p.z))] - 12.0)
		var yaw := rng.randf() * TAU
		var pitch := 0.0
		for s in rng.randi_range(40, 90):
			_carve_sphere(p, clampf(1.6 + 0.6 * sin(s * 0.3 + n) + rng.randf_range(-0.2, 0.2), 1.1, 2.4))
			p += Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
			yaw += rng.randf_range(-0.4, 0.4)
			pitch = clampf(pitch + rng.randf_range(-0.2, 0.2), -0.5, 0.5) * 0.9
			if p.x < 3.0 or p.x > SX - 4.0 or p.z < 3.0 or p.z > SZ - 4.0 or p.y < 3.0:
				break


func _carve_sphere(center: Vector3, radius: float) -> void:
	var r := ceili(radius)
	var c := Vector3i(floori(center.x), floori(center.y), floori(center.z))
	for dy in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := c + Vector3i(dx, dy, dz)
				if not in_bounds(p) or p.y <= 1:
					continue
				if (Vector3(p) + Vector3(0.5, 0.5, 0.5)).distance_to(center) > radius:
					continue
				if p.y >= ground[column(p.x, p.z)] - 4:
					continue
				var i := index(p.x, p.y, p.z)
				if blocks[i] != Blocks.BEDROCK:
					blocks[i] = Blocks.AIR


func _plant_trees(rng: RandomNumberGenerator) -> void:
	var planted: Array[Vector2i] = []
	var middle := Vector2(SX * 0.5, SZ * 0.5)
	for attempt in 240:
		if planted.size() >= 45:
			break
		var x := rng.randi_range(3, SX - 4)
		var z := rng.randi_range(3, SZ - 4)
		if Vector2(x, z).distance_to(middle) < 7.0:
			continue
		var h := ground[column(x, z)]
		if blocks[index(x, h, z)] != Blocks.GRASS:
			continue
		var crowded := false
		for p in planted:
			if p.distance_squared_to(Vector2i(x, z)) < 16:
				crowded = true
				break
		if crowded:
			continue
		planted.append(Vector2i(x, z))
		var trunk := rng.randi_range(4, 6)
		for y in range(h + 1, h + trunk + 1):
			blocks[index(x, y, z)] = Blocks.LOG
		var crown := h + trunk
		for dy in range(-2, 2):
			var r := 2 if dy < 0 else 1
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if absi(dx) == r and absi(dz) == r and (dy >= 0 or rng.randf() < 0.5):
						continue
					var p := Vector3i(x + dx, crown + dy, z + dz)
					if in_bounds(p) and blocks[index(p.x, p.y, p.z)] == Blocks.AIR:
						blocks[index(p.x, p.y, p.z)] = Blocks.LEAVES


func _place_treasures(rng: RandomNumberGenerator) -> void:
	var types: Array[int] = [Treasures.CROWN]
	for n in Treasures.PER_WORLD - 1:
		types.append(Treasures.pick(rng))
	for t in types:
		var info: Dictionary = Treasures.LIST[t]
		var depth: Array = info["depth"]
		for attempt in 40:
			var x := rng.randi_range(2, SX - 3)
			var z := rng.randi_range(2, SZ - 3)
			var y := ground[column(x, z)] - rng.randi_range(depth[0], depth[1])
			if y < 2:
				continue
			var i := index(x, y, z)
			var b := blocks[i]
			if b == Blocks.AIR or b == Blocks.BEDROCK or b == Blocks.LOG or b == Blocks.LEAVES or Blocks.is_treasure(b):
				continue
			blocks[i] = Blocks.CHEST if info["chest"] else Blocks.RELIC
			treasures[i] = {"cell": Vector3i(x, y, z), "type": t}
			break
