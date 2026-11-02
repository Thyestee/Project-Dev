extends Node3D
# The voxel world: small cubes of ground under your room, edits, ray casts, lights and the
# chunk meshes.
#
# Blocks live in one flat array, stored column by column, with a one-block border of bedrock
# all around, so neighbour lookups never need bounds checks. Positions are in metres; a cell is
# one block, VOXEL metres on a side, and cell coordinates are named as such.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Mesher := preload("res://scripts/chunk_mesher.gd")
const Room := preload("res://scripts/room.gd")

const VOXEL := 0.25
const SX := 256
const SY := 192
const SZ := 256
const FLOOR_Y := 172       # cell height of the room floor; the ground below it can be dug
const CHUNK := 16
const CHUNK_SHIFT := 4
const CX := SX >> CHUNK_SHIFT
const CY := SY >> CHUNK_SHIFT
const CZ := SZ >> CHUNK_SHIFT
const PX := SX + 2
const PY := SY + 2
const STRIDE_X := PY
const STRIDE_Z := PY * PX
const MAX_LIGHTS := 16

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 lamp_pos = vec3(0.0);
uniform float lamp_range = 8.0;
uniform vec4 light_pos[16];   // xyz, range (0 = off)
uniform vec4 light_col[16];   // rgb, lowest height it reaches
uniform float ambient = 0.035;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec2 info;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.103, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = NORMAL;
	info = UV2;
}

void fragment() {
	// Each cube gets its own shade and a thin dark line along its edges.
	vec3 g = world_pos * 4.0;
	float jitter = 1.0 + (hash(floor(g - world_normal * 0.5)) - 0.5) * 2.0 * info.y;
	vec3 e = min(fract(g), 1.0 - fract(g));
	vec3 an = abs(world_normal);
	float d = an.x > 0.5 ? min(e.y, e.z) : (an.y > 0.5 ? min(e.x, e.z) : min(e.x, e.y));
	float aa = fwidth(d);
	float line = (1.0 - smoothstep(0.05 - aa, 0.05 + aa, d)) * clamp(1.0 - aa * 3.0, 0.0, 1.0);
	vec3 albedo = COLOR.rgb * jitter * (1.0 - 0.25 * line);

	// Your head lamp, then the room's lanterns and windows.
	float lamp = 1.0 - clamp(distance(world_pos, lamp_pos) / lamp_range, 0.0, 1.0);
	vec3 light = vec3(ambient) + vec3(1.0, 0.86, 0.66) * lamp * lamp * (3.0 - 2.0 * lamp);
	for (int k = 0; k < 16; k++) {
		vec4 lp = light_pos[k];
		if (lp.w > 0.0 && world_pos.y > light_col[k].a) {
			float a = 1.0 - clamp(distance(world_pos, lp.xyz) / lp.w, 0.0, 1.0);
			light += light_col[k].rgb * a * a;
		}
	}
	float shimmer = 0.75 + 0.25 * sin(TIME * 3.0 + world_pos.x * 3.1 + world_pos.y * 4.3 + world_pos.z * 2.7);
	ALBEDO = albedo * min(light, vec3(1.25)) + albedo * info.x * shimmer;
}
"""

var blocks := PackedByteArray()
var treasures := {}                       # cell index -> treasure number in treasure_list
var treasure_list: Array[Dictionary] = [] # {"type", "center" (metres), "cells", "lo", "hi", "found"}
var edits := {}                           # cell index -> block, for all digging and placing
var world_seed := 0
var material: ShaderMaterial
var lights: Array = []                    # {"pos", "color", "range", "min_y", "flicker"}
var _meshes := {}                         # chunk Vector3i -> MeshInstance3D
var _dirty := {}
var _air := PackedByteArray()             # per chunk: 1 once it has any air in it
var _build_queue: Array[Vector3i] = []
var _build_total := 0
var _runs := []                           # block -> {length: PackedByteArray of that block}


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	material = ShaderMaterial.new()
	material.shader = shader


func _process(_delta: float) -> void:
	var start := Time.get_ticks_usec()
	while not _build_queue.is_empty() and Time.get_ticks_usec() - start < 12000:
		_build_chunk(_build_queue.pop_back())
	for key: Vector3i in _dirty:
		_build_chunk(key)
	_dirty.clear()


# --- Lookups -----------------------------------------------------------------

static func index(x: int, y: int, z: int) -> int:
	return (y + 1) + (x + 1) * STRIDE_X + (z + 1) * STRIDE_Z


static func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.z >= 0 and c.x < SX and c.y < SY and c.z < SZ


static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / VOXEL), floori(p.y / VOXEL), floori(p.z / VOXEL))


static func center_of(c: Vector3i) -> Vector3:
	return (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * VOXEL


func block(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= SX or y >= SY or z >= SZ:
		return Blocks.BEDROCK
	return blocks[index(x, y, z)]


func box_hits_solid(lo: Vector3, hi: Vector3) -> bool:
	var x0 := floori(lo.x / VOXEL)
	var y0 := floori(lo.y / VOXEL)
	var z0 := floori(lo.z / VOXEL)
	var x1 := floori(hi.x / VOXEL - 0.0001)
	var y1 := floori(hi.y / VOXEL - 0.0001)
	var z1 := floori(hi.z / VOXEL - 0.0001)
	if x0 < 0 or y0 < 0 or z0 < 0 or x1 >= SX or y1 >= SY or z1 >= SZ:
		return true
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := index(x, y0, z)
			for y in range(y0, y1 + 1):
				if blocks[i] != Blocks.AIR:
					return true
				i += 1
	return false


func nearest_treasure_distance(p: Vector3) -> float:
	var best := INF
	for t: Dictionary in treasure_list:
		if not t["found"]:
			best = minf(best, p.distance_to(t["center"]))
	return best


func remaining_treasures() -> int:
	var n := 0
	for t: Dictionary in treasure_list:
		if not t["found"]:
			n += 1
	return n


# Metres below the room floor for feet at p.
func depth_at(p: Vector3) -> float:
	return FLOOR_Y * VOXEL - p.y


func spawn_point() -> Vector3:
	return Room.SPAWN * VOXEL


func can_place(c: Vector3i) -> bool:
	return in_bounds(c) and c.y < FLOOR_Y and blocks[index(c.x, c.y, c.z)] == Blocks.AIR and not Room.in_stairs(c)


# Walks the ray through the grid one cell at a time. Returns the first non-air cell, the empty
# cell just before it (where a placed block would go) and the block, or {} if nothing is in reach.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var o := origin / VOXEL
	var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3(_cell_span(dir.x), _cell_span(dir.y), _cell_span(dir.z))
	var t_max := Vector3(_first_crossing(o.x, dir.x, cell.x), _first_crossing(o.y, dir.y, cell.y), _first_crossing(o.z, dir.z, cell.z))
	var prev := cell
	var t := 0.0
	var limit := max_dist / VOXEL
	while t <= limit:
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

# A change made by the player; it goes in the save.
func set_block(c: Vector3i, b: int) -> void:
	var i := index(c.x, c.y, c.z)
	if blocks[i] == b:
		return
	blocks[i] = b
	edits[i] = b
	_touch(c, c, b == Blocks.AIR)


# Building the room and its upgrades; rebuilt from scratch on every load, so not saved.
func put(x: int, y: int, z: int, b: int) -> void:
	blocks[index(x, y, z)] = b
	_touch(Vector3i(x, y, z), Vector3i(x, y, z), b == Blocks.AIR)


func fill(lo: Vector3i, hi: Vector3i, b: int) -> void:
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var i := index(x, lo.y, z)
			for y in range(lo.y, hi.y + 1):
				blocks[i] = b
				i += 1
	_touch(lo, hi, b == Blocks.AIR)


# One pickaxe swing: clears the ground within `radius` cells of the cell that was hit, as far as
# the pick head's tier allows. Any treasure it touches comes out whole.
func carve(center: Vector3i, radius: float, tier: int) -> Dictionary:
	var r := ceili(radius)
	var r2 := radius * radius
	var drops := {}
	var found: Array[int] = []
	var removed := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var h2 := r2 - dx * dx - dz * dz
			var x := center.x + dx
			var z := center.z + dz
			if h2 < 0.0 or x < 0 or z < 0 or x >= SX or z >= SZ:
				continue
			var hy := int(sqrt(h2))
			var y0 := maxi(center.y - hy, 0)
			var y1 := mini(center.y + hy, SY - 1)
			var i := index(x, y0, z)
			for y in range(y0, y1 + 1):
				var b := blocks[i]
				if Blocks.is_treasure(b):
					var t: int = treasures.get(i, -1)
					if t >= 0 and not found.has(t):
						found.append(t)
				elif Blocks.is_natural(b) and Blocks.TIER[b] <= tier:
					blocks[i] = Blocks.AIR
					edits[i] = Blocks.AIR
					drops[b] = int(drops.get(b, 0)) + 1
					removed += 1
				i += 1
	if removed > 0:
		_touch(center - Vector3i(r, r, r), center + Vector3i(r, r, r), true)
	for t in found:
		_collect(t)
	return {"drops": drops, "treasures": found, "removed": removed}


func _collect(t: int) -> void:
	var info := treasure_list[t]
	info["found"] = true
	for i: int in info["cells"]:
		blocks[i] = Blocks.AIR
		edits[i] = Blocks.AIR
		treasures.erase(i)
	_touch(info["lo"], info["hi"], true)


func edits_data() -> Dictionary:
	if edits.is_empty():
		return {}
	var cells := PackedInt32Array(edits.keys())
	var values := PackedByteArray()
	values.resize(cells.size())
	for k in cells.size():
		values[k] = edits[cells[k]]
	return {"cells": Marshalls.raw_to_base64(cells.to_byte_array()), "blocks": Marshalls.raw_to_base64(values)}


func apply_edits_data(data: Dictionary) -> void:
	if str(data.get("cells", "")).is_empty():
		return
	var cells := Marshalls.base64_to_raw(str(data.get("cells", ""))).to_int32_array()
	var values := Marshalls.base64_to_raw(str(data.get("blocks", "")))
	if cells.size() != values.size():
		return
	for k in cells.size():
		var i := cells[k]
		if i < 0 or i >= blocks.size():
			continue
		blocks[i] = values[k]
		edits[i] = values[k]
		if values[k] == Blocks.AIR:
			_air[_chunk_of_index(i)] = 1
	# Treasure that was dug into has been found.
	for t in treasure_list.size():
		var info := treasure_list[t]
		var first: int = info["cells"][0]
		if not info["found"] and not Blocks.is_treasure(blocks[first]):
			_collect(t)


# --- Lights ------------------------------------------------------------------

func set_lights(list: Array) -> void:
	lights = list
	update_lights(0.0)


func update_lights(time: float) -> void:
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	for k in MAX_LIGHTS:
		if k >= lights.size():
			pos.append(Vector4.ZERO)
			col.append(Vector4.ZERO)
			continue
		var l: Dictionary = lights[k]
		var p: Vector3 = l["pos"]
		var c: Color = l["color"]
		var f := 1.0
		if l.get("flicker", false):
			f = 0.84 + 0.1 * sin(time * 11.0) + 0.06 * sin(time * 23.7 + 1.3)
		pos.append(Vector4(p.x, p.y, p.z, l["range"]))
		col.append(Vector4(c.r * f, c.g * f, c.b * f, l.get("min_y", -100.0)))
	material.set_shader_parameter("light_pos", pos)
	material.set_shader_parameter("light_col", col)


# --- Chunk meshes --------------------------------------------------------------

# Queues every chunk that can have visible faces (it or a neighbour has air), nearest first.
func queue_all_chunks(center: Vector3) -> void:
	_dirty.clear()
	_build_queue.clear()
	for cy in CY:
		for cz in CZ:
			for cx in CX:
				if _near_air(cx, cy, cz):
					_build_queue.append(Vector3i(cx, cy, cz))
	# Nearest chunks last, since the queue is built from the back.
	var c := center / (CHUNK * VOXEL) - Vector3(0.5, 0.5, 0.5)
	_build_queue.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return Vector3(a).distance_squared_to(c) > Vector3(b).distance_squared_to(c))
	_build_total = _build_queue.size()


func build_progress() -> float:
	if _build_total == 0:
		return 1.0
	return 1.0 - float(_build_queue.size()) / _build_total


func mesh_count() -> int:
	return _meshes.size()


func _near_air(cx: int, cy: int, cz: int) -> bool:
	for o: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var x := cx + o.x
		var y := cy + o.y
		var z := cz + o.z
		if x >= 0 and y >= 0 and z >= 0 and x < CX and y < CY and z < CZ and _air[x + z * CX + y * CX * CZ] == 1:
			return true
	return false


static func _chunk_of_index(i: int) -> int:
	var y := clampi(i % PY - 1, 0, SY - 1)
	var x := clampi((i / PY) % PX - 1, 0, SX - 1)
	var z := clampi(i / STRIDE_Z - 1, 0, SZ - 1)
	return (x >> CHUNK_SHIFT) + (z >> CHUNK_SHIFT) * CX + (y >> CHUNK_SHIFT) * CX * CZ


# Marks the chunks around a changed box for rebuilding (and as having air, if it does now).
func _touch(lo: Vector3i, hi: Vector3i, made_air: bool) -> void:
	var c0 := Vector3i(clampi(lo.x - 1, 0, SX - 1), clampi(lo.y - 1, 0, SY - 1), clampi(lo.z - 1, 0, SZ - 1))
	var c1 := Vector3i(clampi(hi.x + 1, 0, SX - 1), clampi(hi.y + 1, 0, SY - 1), clampi(hi.z + 1, 0, SZ - 1))
	for cy in range(c0.y >> CHUNK_SHIFT, (c1.y >> CHUNK_SHIFT) + 1):
		for cz in range(c0.z >> CHUNK_SHIFT, (c1.z >> CHUNK_SHIFT) + 1):
			for cx in range(c0.x >> CHUNK_SHIFT, (c1.x >> CHUNK_SHIFT) + 1):
				_dirty[Vector3i(cx, cy, cz)] = true
	if made_air:
		for cy in range(clampi(lo.y, 0, SY - 1) >> CHUNK_SHIFT, (clampi(hi.y, 0, SY - 1) >> CHUNK_SHIFT) + 1):
			for cz in range(clampi(lo.z, 0, SZ - 1) >> CHUNK_SHIFT, (clampi(hi.z, 0, SZ - 1) >> CHUNK_SHIFT) + 1):
				for cx in range(clampi(lo.x, 0, SX - 1) >> CHUNK_SHIFT, (clampi(hi.x, 0, SX - 1) >> CHUNK_SHIFT) + 1):
					_air[cx + cz * CX + cy * CX * CZ] = 1


func _build_chunk(key: Vector3i) -> void:
	var mesh := Mesher.build(blocks, STRIDE_X, STRIDE_Z, key.x * CHUNK, key.y * CHUNK, key.z * CHUNK, CHUNK, VOXEL)
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
	treasures.clear()
	treasure_list.clear()
	edits.clear()
	_air = PackedByteArray()
	_air.resize(CX * CY * CZ)
	_fill_columns(new_seed)
	_add_pockets(rng)
	_carve_caves(rng)
	Room.build_base(self)
	_place_treasures(rng)
	_dirty.clear()


static func _noise(s: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


# Lays down the ground in layers, one whole column at a time: bedrock at the bottom, then
# deeprock, slate, stone, dirt with a band of clay, and solid bedrock above the ground.
func _fill_columns(s: int) -> void:
	_runs = []
	for b in Blocks.COLORS.size():
		_runs.append({})
	var n_dirt := _noise(s, 0.02, 2)
	var n_clay := _noise(s + 1, 0.03, 2)
	var n_soft := _noise(s + 2, 0.015, 2)
	var n_stone := _noise(s + 3, 0.012, 3)
	var n_slate := _noise(s + 4, 0.012, 3)
	var n_bed := _noise(s + 5, 0.08, 1)
	blocks = PackedByteArray()
	for z in range(-1, SZ + 1):
		for x in range(-1, SX + 1):
			if x < 0 or z < 0 or x >= SX or z >= SZ:
				_run(Blocks.BEDROCK, PY)
				continue
			# Layer boundaries as depths in metres below the room floor, turned into cell heights.
			var y_dirt := FLOOR_Y - int((8.5 + n_dirt.get_noise_2d(x, z) * 1.2) / VOXEL)
			var y_clay := y_dirt - int((2.5 + n_clay.get_noise_2d(x, z) * 1.2) / VOXEL)
			var y_soft := mini(y_clay, FLOOR_Y - int((13.0 + n_soft.get_noise_2d(x, z) * 1.5) / VOXEL))
			var y_stone := mini(y_soft, FLOOR_Y - int((22.0 + n_stone.get_noise_2d(x, z) * 2.5) / VOXEL))
			var y_slate := mini(y_stone, FLOOR_Y - int((32.0 + n_slate.get_noise_2d(x, z) * 2.5) / VOXEL))
			var bed := mini(y_slate, 2 + int((n_bed.get_noise_2d(x, z) + 1.0) * 1.5))
			_run(Blocks.BEDROCK, bed + 1)
			_run(Blocks.DEEPROCK, y_slate - bed)
			_run(Blocks.SLATE, y_stone - y_slate)
			_run(Blocks.STONE, y_soft - y_stone)
			_run(Blocks.DIRT, y_clay - y_soft)
			_run(Blocks.CLAY, y_dirt - y_clay)
			_run(Blocks.DIRT, FLOOR_Y - y_dirt)
			_run(Blocks.BEDROCK, SY - FLOOR_Y + 1)


func _run(b: int, length: int) -> void:
	if length <= 0:
		return
	var cache: Dictionary = _runs[b]
	if not cache.has(length):
		var run := PackedByteArray()
		run.resize(length)
		run.fill(b)
		cache[length] = run
	blocks.append_array(cache[length])


# Pockets of sand and gravel in the dirt, softer veins in the rock.
func _add_pockets(rng: RandomNumberGenerator) -> void:
	for n in 340:
		var c := Vector3i(rng.randi_range(6, SX - 7), rng.randi_range(8, FLOOR_Y - 4), rng.randi_range(6, SZ - 7))
		var host := blocks[index(c.x, c.y, c.z)]
		var kind := Blocks.AIR
		match host:
			Blocks.DIRT:
				kind = Blocks.SAND if rng.randf() < 0.5 else Blocks.GRAVEL
			Blocks.CLAY:
				kind = Blocks.DIRT
			Blocks.STONE:
				kind = Blocks.GRAVEL
			Blocks.SLATE:
				kind = Blocks.STONE
			Blocks.DEEPROCK:
				kind = Blocks.SLATE
		if kind != Blocks.AIR:
			_blob(c, Vector3(rng.randf_range(3.0, 8.0), rng.randf_range(2.0, 5.0), rng.randf_range(3.0, 8.0)), host, kind)


# Fills an ellipsoid of cells, replacing only `host` blocks (or every natural block, for air).
func _blob(c: Vector3i, r: Vector3, host: int, kind: int) -> void:
	var made_air := kind == Blocks.AIR
	for dz in range(-ceili(r.z), ceili(r.z) + 1):
		for dx in range(-ceili(r.x), ceili(r.x) + 1):
			var q := 1.0 - (dx / r.x) * (dx / r.x) - (dz / r.z) * (dz / r.z)
			var x := c.x + dx
			var z := c.z + dz
			if q < 0.0 or x < 0 or z < 0 or x >= SX or z >= SZ:
				continue
			var hy := int(r.y * sqrt(q))
			var y0 := maxi(c.y - hy, 0)
			var y1 := mini(c.y + hy, FLOOR_Y - 1)
			var i := index(x, y0, z)
			for y in range(y0, y1 + 1):
				var b := blocks[i]
				if b == host or (made_air and Blocks.is_natural(b)):
					blocks[i] = kind
				i += 1
	if made_air:
		_touch(c - Vector3i(r.ceil()), c + Vector3i(r.ceil()), true)


# A few winding caves, all well below the room.
func _carve_caves(rng: RandomNumberGenerator) -> void:
	for n in 6:
		var p := Vector3(rng.randf_range(24.0, SX - 24.0), rng.randf_range(20.0, FLOOR_Y - 40.0), rng.randf_range(24.0, SZ - 24.0))
		var yaw := rng.randf() * TAU
		var pitch := 0.0
		for s in rng.randi_range(50, 110):
			var radius := clampf(4.5 + 1.5 * sin(s * 0.25 + n) + rng.randf_range(-0.5, 0.5), 3.0, 6.5)
			_blob(Vector3i(p.round()), Vector3(radius, radius * 0.8, radius), Blocks.AIR, Blocks.AIR)
			p += Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * 2.5
			yaw += rng.randf_range(-0.35, 0.35)
			pitch = clampf(pitch + rng.randf_range(-0.15, 0.15), -0.45, 0.45) * 0.9
			if p.x < 12.0 or p.x > SX - 12.0 or p.z < 12.0 or p.z > SZ - 12.0 or p.y < 14.0 or p.y > FLOOR_Y - 30.0:
				break


# Relics are 2x2x2 cubes of glinting soil; rarer treasure comes in 4x3x3 chests with a gold band.
func _place_treasures(rng: RandomNumberGenerator) -> void:
	var types: Array[int] = [Treasures.CROWN]
	for n in Treasures.PER_WORLD - 1:
		types.append(Treasures.pick(rng))
	for t in types:
		var info: Dictionary = Treasures.LIST[t]
		var depth: Array = info["depth"]
		var chest: bool = info["chest"]
		var size := Vector3i(4, 3, 3) if chest else Vector3i(2, 2, 2)
		if rng.randf() < 0.5:
			size = Vector3i(size.z, size.y, size.x)
		for attempt in 80:
			var d := rng.randf_range(float(depth[0]), minf(float(depth[1]), 41.0))
			var lo := Vector3i(rng.randi_range(8, SX - 8 - size.x), FLOOR_Y - int(d / VOXEL), rng.randi_range(8, SZ - 8 - size.z))
			if _all_natural(lo, lo + size - Vector3i.ONE):
				_bury(t, lo, size, chest)
				break


func _all_natural(lo: Vector3i, hi: Vector3i) -> bool:
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				if not Blocks.is_natural(blocks[index(x, y, z)]):
					return false
	return true


func _bury(t: int, lo: Vector3i, size: Vector3i, chest: bool) -> void:
	var number := treasure_list.size()
	var cells := PackedInt32Array()
	for z in range(lo.z, lo.z + size.z):
		for x in range(lo.x, lo.x + size.x):
			for y in range(lo.y, lo.y + size.y):
				var i := index(x, y, z)
				var b := Blocks.RELIC
				if chest:
					b = Blocks.CHEST_TRIM if y == lo.y + 1 else Blocks.CHEST
				blocks[i] = b
				treasures[i] = number
				cells.append(i)
	var hi := lo + size - Vector3i.ONE
	treasure_list.append({"type": t, "center": (Vector3(lo) + Vector3(size) * 0.5) * VOXEL, "cells": cells, "lo": lo, "hi": hi, "found": false})
