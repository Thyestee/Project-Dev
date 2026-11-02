extends Node3D
# The voxel world: small cubes of ground under your house, the hidden rooms, edits, ray casts,
# lights and the chunk meshes.
#
# Blocks live in one flat array, stored column by column, with a one-block border of bedrock
# all around, so neighbour lookups never need bounds checks. Positions are in metres; a cell is
# one block, VOXEL metres on a side, and cell coordinates are named as such.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Mesher := preload("res://scripts/chunk_mesher.gd")
const House := preload("res://scripts/house.gd")
const Vaults := preload("res://scripts/vaults.gd")

const VOXEL := 0.125
const SX := 384
const SY := 384
const SZ := 384
const FLOOR_Y := 344       # cell height of the house floor; the ground below it can be dug
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
instance uniform vec4 tint = vec4(0.0);   // a flash of colour when something is hit

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
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	info = UV2;
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	// World cubes get their own shade and a thin dark line along their edges; models (info.y < 0)
	// keep their plain colours.
	if (info.y >= 0.0) {
		vec3 g = world_pos * 8.0;
		float jitter = 1.0 + (hash(floor(g - world_normal * 0.5)) - 0.5) * 2.0 * info.y;
		vec3 e = min(fract(g), 1.0 - fract(g));
		vec3 an = abs(world_normal);
		float d = an.x > 0.5 ? min(e.y, e.z) : (an.y > 0.5 ? min(e.x, e.z) : min(e.x, e.y));
		float aa = fwidth(d);
		float line = (1.0 - smoothstep(0.06 - aa, 0.06 + aa, d)) * clamp(1.0 - aa * 3.0, 0.0, 1.0);
		albedo *= jitter * (1.0 - 0.25 * line);
	}

	// Your head lamp, then the lanterns, windows and torches nearby.
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
	vec3 lit = albedo * min(light, vec3(1.25)) + albedo * info.x * shimmer;
	ALBEDO = mix(lit, tint.rgb, tint.a);
}
"""

var blocks := PackedByteArray()
var treasures := {}                       # cell index -> treasure number in treasure_list
var treasure_list: Array[Dictionary] = [] # {"type", "center" (metres), "cells", "lo", "hi", "found", "vault"}
var vaults: Array[Dictionary] = []        # the hidden rooms (see Vaults)
var furniture := {}                       # cell index -> id of the furniture standing there
var world_seed := 0
var house_tier := 0
var material: ShaderMaterial
var lights: Array = []                    # {"pos", "color", "range", "min_y", "flicker", "vault"}
var lit_vaults := {}                      # hidden rooms whose torches burn (they light up when you break in)
var loading := false
var focus := Vector3.ZERO                 # where you are: nearby chunks are rebuilt first
var _flashes: Array = []                  # brief lights from explosions and lightning
var _edited := {}                         # chunk number -> true for every chunk you've changed
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
	if not _dirty.is_empty():
		# Changed chunks first, nearest first. Whatever doesn't fit in the time waits a frame.
		var keys: Array = _dirty.keys()
		var c := focus / (CHUNK * VOXEL) - Vector3(0.5, 0.5, 0.5)
		keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return Vector3(a).distance_squared_to(c) < Vector3(b).distance_squared_to(c))
		for key: Vector3i in keys:
			_build_chunk(key)
			_dirty.erase(key)
			if Time.get_ticks_usec() - start > 6000:
				break
	var budget := 40000 if loading else 8000
	while not _build_queue.is_empty() and Time.get_ticks_usec() - start < budget:
		_build_chunk(_build_queue.pop_back())


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


# Metres below the house floor for feet at p.
func depth_at(p: Vector3) -> float:
	return FLOOR_Y * VOXEL - p.y


func spawn_point() -> Vector3:
	return House.spawn_point()


func can_place(c: Vector3i) -> bool:
	return in_bounds(c) and c.y < FLOOR_Y and blocks[index(c.x, c.y, c.z)] == Blocks.AIR and not House.in_stairs(c)


# The hidden room whose inside holds point p (metres), or -1.
func vault_containing(p: Vector3) -> int:
	var c := p / VOXEL
	for v in vaults.size():
		var lo: Vector3i = vaults[v]["lo"]
		var hi: Vector3i = vaults[v]["hi"]
		if c.x >= lo.x and c.y >= lo.y - 1 and c.z >= lo.z and c.x < hi.x + 1 and c.y < hi.y + 1 and c.z < hi.z + 1:
			return v
	return -1


# Hidden rooms whose walls come within `radius` cells of `center` (cells).
func vaults_near(center: Vector3, radius: float) -> Array[int]:
	var out: Array[int] = []
	for v in vaults.size():
		var lo: Vector3 = Vector3(vaults[v]["lo"]) - Vector3(3, 3, 3) - Vector3.ONE * radius
		var hi: Vector3 = Vector3(vaults[v]["hi"]) + Vector3(4, 4, 4) + Vector3.ONE * radius
		if center.x >= lo.x and center.y >= lo.y and center.z >= lo.z and center.x <= hi.x and center.y <= hi.y and center.z <= hi.z:
			out.append(v)
	return out


# Walks the ray through the grid one cell at a time. Returns the first non-air cell, the empty
# cell just before it (where a placed block would go), the block, how far along the ray it is
# and the normal of the face it went in through, or {} if nothing is in reach. `dir` must be
# normalized.
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
			return {"cell": cell, "prev": prev, "block": b, "dist": t * VOXEL, "normal": Vector3i(prev - cell)}
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


func line_of_sight(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return true
	return raycast(a, d / length, length).is_empty()


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
	_mark_edited(c, c)
	_touch(c, c, b == Blocks.AIR)


# Building the house, its furniture and the hidden rooms; rebuilt from scratch on every load,
# so not saved (unless you also changed the chunk yourself).
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


# Clears every block within `radius` cells of `center` (in cells) that `tier` can break: one
# pickaxe swing, or a blast. Any treasure it touches comes out whole.
func carve(center: Vector3, radius: float, tier: int) -> Dictionary:
	var tiers := Blocks.TIER
	var drop_table := Blocks.DROP
	var r2 := radius * radius
	var x0 := maxi(floori(center.x - radius), 0)
	var x1 := mini(floori(center.x + radius), SX - 1)
	var z0 := maxi(floori(center.z - radius), 0)
	var z1 := mini(floori(center.z + radius), SZ - 1)
	var drops := {}
	var found: Array[int] = []
	var removed := 0
	var vault_hit := false
	for z in range(z0, z1 + 1):
		var dz := z + 0.5 - center.z
		for x in range(x0, x1 + 1):
			var dx := x + 0.5 - center.x
			var h2 := r2 - dx * dx - dz * dz
			if h2 < 0.0:
				continue
			var hy := sqrt(h2)
			var y0 := maxi(ceili(center.y - hy - 0.5), 0)
			var y1 := mini(floori(center.y + hy - 0.5), SY - 1)
			var i := index(x, y0, z)
			for y in range(y0, y1 + 1):
				var b := blocks[i]
				if b != 0:
					if b == Blocks.RELIC or b == Blocks.CHEST or b == Blocks.CHEST_TRIM:
						var t: int = treasures.get(i, -1)
						if t >= 0 and not found.has(t):
							found.append(t)
					else:
						var bt := tiers[b]
						if bt >= 0 and bt <= tier:
							blocks[i] = 0
							if b >= Blocks.VAULT_BRICK and b <= Blocks.BANNER or b == Blocks.URN:
								vault_hit = true
							var d := drop_table[b]
							if d != 0:
								drops[d] = int(drops.get(d, 0)) + 1
							removed += 1
				i += 1
	if removed > 0:
		var lo := Vector3i(x0, maxi(floori(center.y - radius), 0), z0)
		var hi := Vector3i(x1, mini(floori(center.y + radius), SY - 1), z1)
		_mark_edited(lo, hi)
		_touch(lo, hi, true)
	for t in found:
		_collect(t)
	return {"drops": drops, "treasures": found, "removed": removed, "vault": vault_hit}


# The leveller: makes the surface you're looking at flat. `cell` is the block you hit and
# `normal` points out of the face you hit. Within `half` cubes of that spot, cubes standing up
# to `cut` cubes proud of the face are cut away (as far as `tier` allows), and holes up to
# `fill_depth` cubes deep are filled with `material`, as long as `available` lasts. Nothing is
# filled inside the box keep_lo..keep_hi (metres): that's you.
func flatten(cell: Vector3i, normal: Vector3i, half: int, cut: int, fill_depth: int, tier: int, material_block: int, available: int, keep_lo: Vector3, keep_hi: Vector3) -> Dictionary:
	var a := 0 if normal.x != 0 else (1 if normal.y != 0 else 2)
	var s: int = normal[a]
	var u := (a + 1) % 3
	var v := (a + 2) % 3
	var drops := {}
	var found: Array[int] = []
	var removed := 0
	var placed := 0
	var vault_hit := false
	var keep_c0 := Vector3i((keep_lo / VOXEL).floor())
	var keep_c1 := Vector3i((keep_hi / VOXEL - Vector3(0.0001, 0.0001, 0.0001)).floor())
	for du in range(-half, half):
		for dv in range(-half, half):
			var c := cell
			c[u] += du
			c[v] += dv
			# Cut away whatever stands proud of the surface.
			for k in range(1, cut + 1):
				var p := c
				p[a] += s * k
				if not in_bounds(p):
					break
				var i := index(p.x, p.y, p.z)
				var b := blocks[i]
				if b == 0:
					continue
				if Blocks.is_treasure(b):
					var t: int = treasures.get(i, -1)
					if t >= 0 and not found.has(t):
						found.append(t)
				elif Blocks.diggable(b, tier):
					blocks[i] = 0
					removed += 1
					vault_hit = vault_hit or Blocks.is_vault(b)
					var d := Blocks.DROP[b]
					if d != 0:
						drops[d] = int(drops.get(d, 0)) + 1
			# Fill in the holes below it.
			for k in fill_depth:
				if placed >= available:
					break
				var p := c
				p[a] -= s * k
				if not can_place(p):
					continue
				if p.x >= keep_c0.x and p.x <= keep_c1.x and p.y >= keep_c0.y and p.y <= keep_c1.y and p.z >= keep_c0.z and p.z <= keep_c1.z:
					continue
				blocks[index(p.x, p.y, p.z)] = material_block
				placed += 1
	if removed > 0 or placed > 0:
		var lo := cell
		var hi := cell
		lo[u] -= half
		hi[u] += half - 1
		lo[v] -= half
		hi[v] += half - 1
		if s > 0:
			lo[a] -= fill_depth
			hi[a] += cut
		else:
			lo[a] -= cut
			hi[a] += fill_depth
		lo = lo.clamp(Vector3i.ZERO, Vector3i(SX - 1, SY - 1, SZ - 1))
		hi = hi.clamp(Vector3i.ZERO, Vector3i(SX - 1, SY - 1, SZ - 1))
		_mark_edited(lo, hi)
		_touch(lo, hi, removed > 0)
	for t in found:
		_collect(t)
	return {"drops": drops, "treasures": found, "removed": removed, "placed": placed, "vault": vault_hit}


func _collect(t: int) -> void:
	var info := treasure_list[t]
	info["found"] = true
	for i: int in info["cells"]:
		blocks[i] = Blocks.AIR
		treasures.erase(i)
	_mark_edited(info["lo"], info["hi"])
	_touch(info["lo"], info["hi"], true)


static func _chunk_number(cx: int, cy: int, cz: int) -> int:
	return cx + cz * CX + cy * CX * CZ


func _mark_edited(lo: Vector3i, hi: Vector3i) -> void:
	for cy in range(lo.y >> CHUNK_SHIFT, (hi.y >> CHUNK_SHIFT) + 1):
		for cz in range(lo.z >> CHUNK_SHIFT, (hi.z >> CHUNK_SHIFT) + 1):
			for cx in range(lo.x >> CHUNK_SHIFT, (hi.x >> CHUNK_SHIFT) + 1):
				_edited[_chunk_number(cx, cy, cz)] = true


# The save keeps every chunk you've changed as it is now, packed and compressed.
func edits_data() -> Dictionary:
	if _edited.is_empty():
		return {}
	var ids := PackedInt32Array(_edited.keys())
	var raw := PackedByteArray()
	for n: int in ids:
		var cx := n % CX
		var cz := (n / CX) % CZ
		var cy := n / (CX * CZ)
		for z in range(cz * CHUNK, cz * CHUNK + CHUNK):
			for x in range(cx * CHUNK, cx * CHUNK + CHUNK):
				var i := index(x, cy * CHUNK, z)
				raw.append_array(blocks.slice(i, i + CHUNK))
	return {"chunks": Marshalls.raw_to_base64(ids.to_byte_array()), "size": raw.size(),
		"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD))}


func apply_edits_data(data: Dictionary) -> void:
	if str(data.get("data", "")).is_empty():
		return
	var ids := Marshalls.base64_to_raw(str(data.get("chunks", ""))).to_int32_array()
	var raw := Marshalls.base64_to_raw(str(data["data"])).decompress(int(data.get("size", 0)), FileAccess.COMPRESSION_ZSTD)
	if raw.size() != ids.size() * CHUNK * CHUNK * CHUNK:
		return
	var k := 0
	for n: int in ids:
		if n < 0 or n >= CX * CY * CZ:
			k += CHUNK * CHUNK * CHUNK
			continue
		var cx := n % CX
		var cz := (n / CX) % CZ
		var cy := n / (CX * CZ)
		for z in range(cz * CHUNK, cz * CHUNK + CHUNK):
			for x in range(cx * CHUNK, cx * CHUNK + CHUNK):
				var i := index(x, cy * CHUNK, z)
				for y in CHUNK:
					blocks[i + y] = raw[k]
					k += 1
		_edited[n] = true
		_air[n] = 1
	# Treasure that was dug into has been found.
	for t in treasure_list.size():
		var info := treasure_list[t]
		var first: int = info["cells"][0]
		if not info["found"] and not Blocks.is_treasure(blocks[first]):
			_collect(t)


func edited_chunk_count() -> int:
	return _edited.size()


# --- Lights ------------------------------------------------------------------

func set_lights(list: Array) -> void:
	lights = list


# A short burst of light: explosions, lightning.
func flash(pos: Vector3, color: Color, light_range: float, life: float) -> void:
	_flashes.append({"pos": pos, "color": color, "range": light_range, "time": life, "life": life})


# Sends the shader the lights nearest to `eye`: those that are on, plus any flashes.
func update_lights(time: float, delta: float, eye: Vector3) -> void:
	var on: Array = []
	for l: Dictionary in lights:
		var v: int = l.get("vault", -1)
		if v < 0 or lit_vaults.has(v):
			on.append(l)
	var k := _flashes.size() - 1
	while k >= 0:
		var f: Dictionary = _flashes[k]
		f["time"] = float(f["time"]) - delta
		if float(f["time"]) <= 0.0:
			_flashes.remove_at(k)
		k -= 1
	on.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return eye.distance_to(a["pos"]) - float(a["range"]) < eye.distance_to(b["pos"]) - float(b["range"]))
	var pos := PackedVector4Array()
	var col := PackedVector4Array()
	for f: Dictionary in _flashes:
		if pos.size() >= 4:
			break
		var p: Vector3 = f["pos"]
		var c: Color = f["color"] * (float(f["time"]) / float(f["life"]))
		pos.append(Vector4(p.x, p.y, p.z, f["range"]))
		col.append(Vector4(c.r, c.g, c.b, -100.0))
	for l: Dictionary in on:
		if pos.size() >= MAX_LIGHTS:
			break
		var p: Vector3 = l["pos"]
		var c: Color = l["color"]
		var f := 1.0
		if l.get("flicker", false):
			var phase := p.x * 1.7 + p.z * 2.3
			f = 0.84 + 0.1 * sin(time * 11.0 + phase) + 0.06 * sin(time * 23.7 + 1.3 + phase)
		pos.append(Vector4(p.x, p.y, p.z, l["range"]))
		col.append(Vector4(c.r * f, c.g * f, c.b * f, l.get("min_y", -100.0)))
	while pos.size() < MAX_LIGHTS:
		pos.append(Vector4.ZERO)
		col.append(Vector4.ZERO)
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


func pending_chunks() -> int:
	return _dirty.size() + _build_queue.size()


func _near_air(cx: int, cy: int, cz: int) -> bool:
	for o: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var x := cx + o.x
		var y := cy + o.y
		var z := cz + o.z
		if x >= 0 and y >= 0 and z >= 0 and x < CX and y < CY and z < CZ and _air[x + z * CX + y * CX * CZ] == 1:
			return true
	return false


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

func generate(new_seed: int, tier: int) -> void:
	world_seed = new_seed
	house_tier = tier
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	treasures.clear()
	treasure_list.clear()
	furniture.clear()
	lit_vaults.clear()
	_edited.clear()
	_air = PackedByteArray()
	_air.resize(CX * CY * CZ)
	_fill_columns(new_seed)
	_add_pockets(rng)
	_carve_caves(rng)
	House.build_base(self, tier)
	vaults = Vaults.generate(self, rng)
	_place_treasures(rng)
	_dirty.clear()


static func _noise(s: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = s
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


# Lays down the ground in layers, one whole column at a time: bedrock at the bottom, then
# deeprock, slate, stone, dirt with a band of clay, and solid bedrock above the ground. The
# layer heights are worked out once per 2x2 columns; that is plenty for gentle waves.
func _fill_columns(s: int) -> void:
	_runs = []
	for b in Blocks.DEFS.size():
		_runs.append({})
	var n_dirt := _noise(s, 0.02, 2)
	var n_clay := _noise(s + 1, 0.03, 2)
	var n_soft := _noise(s + 2, 0.015, 2)
	var n_stone := _noise(s + 3, 0.012, 3)
	var n_slate := _noise(s + 4, 0.012, 3)
	var n_bed := _noise(s + 5, 0.08, 1)
	var hw := SX >> 1
	var hd := SZ >> 1
	var heights: Array[PackedInt32Array] = []
	for layer in 6:
		var h := PackedInt32Array()
		h.resize(hw * hd)
		heights.append(h)
	for hz in hd:
		for hx in hw:
			# Layer boundaries as depths in metres below the house floor, turned into cell heights.
			var y_dirt := FLOOR_Y - int((8.5 + n_dirt.get_noise_2d(hx, hz) * 1.2) / VOXEL)
			var y_clay := y_dirt - int((2.5 + n_clay.get_noise_2d(hx, hz) * 1.2) / VOXEL)
			var y_soft := mini(y_clay, FLOOR_Y - int((13.0 + n_soft.get_noise_2d(hx, hz) * 1.5) / VOXEL))
			var y_stone := mini(y_soft, FLOOR_Y - int((22.0 + n_stone.get_noise_2d(hx, hz) * 2.5) / VOXEL))
			var y_slate := mini(y_stone, FLOOR_Y - int((32.0 + n_slate.get_noise_2d(hx, hz) * 2.5) / VOXEL))
			var bed := mini(y_slate, 4 + int((n_bed.get_noise_2d(hx, hz) + 1.0) * 3.0))
			var k := hx + hz * hw
			heights[0][k] = bed
			heights[1][k] = y_slate
			heights[2][k] = y_stone
			heights[3][k] = y_soft
			heights[4][k] = y_clay
			heights[5][k] = y_dirt
	blocks = PackedByteArray()
	for z in range(-1, SZ + 1):
		for x in range(-1, SX + 1):
			if x < 0 or z < 0 or x >= SX or z >= SZ:
				_run(Blocks.BEDROCK, PY)
				continue
			var k := (x >> 1) + (z >> 1) * hw
			var bed := heights[0][k]
			var y_slate := heights[1][k]
			var y_stone := heights[2][k]
			var y_soft := heights[3][k]
			var y_clay := heights[4][k]
			var y_dirt := heights[5][k]
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
	for n in 190:
		var c := Vector3i(rng.randi_range(12, SX - 13), rng.randi_range(16, FLOOR_Y - 8), rng.randi_range(12, SZ - 13))
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
			var r := Vector3(rng.randf_range(0.75, 2.0), rng.randf_range(0.5, 1.25), rng.randf_range(0.75, 2.0)) / VOXEL
			_blob(c, r, host, kind)


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
				if b == host or (made_air and b >= Blocks.DIRT and b <= Blocks.DEEPROCK):
					blocks[i] = kind
				i += 1
	if made_air:
		_touch(c - Vector3i(r.ceil()), c + Vector3i(r.ceil()), true)


# A few winding caves, all well below the house.
func _carve_caves(rng: RandomNumberGenerator) -> void:
	for n in 4:
		var p := Vector3(rng.randf_range(48.0, SX - 48.0), rng.randf_range(40.0, FLOOR_Y - 80.0), rng.randf_range(48.0, SZ - 48.0))
		var yaw := rng.randf() * TAU
		var pitch := 0.0
		for s in rng.randi_range(40, 90):
			var radius := clampf(1.1 + 0.4 * sin(s * 0.25 + n) + rng.randf_range(-0.12, 0.12), 0.75, 1.6) / VOXEL
			_blob(Vector3i(p.round()), Vector3(radius, radius * 0.8, radius), Blocks.AIR, Blocks.AIR)
			p += Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * (0.75 / VOXEL)
			yaw += rng.randf_range(-0.35, 0.35)
			pitch = clampf(pitch + rng.randf_range(-0.15, 0.15), -0.45, 0.45) * 0.9
			if p.x < 24.0 or p.x > SX - 24.0 or p.z < 24.0 or p.z > SZ - 24.0 or p.y < 28.0 or p.y > FLOOR_Y - 60.0:
				break


# The rest of the dig site's treasure, buried in the soil. Relics are half-metre cubes of
# glinting soil; rarer treasure comes in buried chests with a gold band.
func _place_treasures(rng: RandomNumberGenerator) -> void:
	var types: Array[int] = []
	var has_crown := false
	for t: Dictionary in treasure_list:
		has_crown = has_crown or t["type"] == Treasures.CROWN
	if not has_crown:
		types.append(Treasures.CROWN)
	while treasure_list.size() + types.size() < Treasures.PER_WORLD:
		types.append(Treasures.pick(rng))
	for t in types:
		var info: Dictionary = Treasures.LIST[t]
		var depth: Array = info["depth"]
		var chest: bool = info["chest"]
		var size := treasure_size(chest)
		if rng.randf() < 0.5:
			size = Vector3i(size.z, size.y, size.x)
		for attempt in 80:
			var d := rng.randf_range(float(depth[0]), minf(float(depth[1]), 41.0))
			var lo := Vector3i(rng.randi_range(16, SX - 16 - size.x), FLOOR_Y - int(d / VOXEL), rng.randi_range(16, SZ - 16 - size.z))
			if _all_natural(lo, lo + size - Vector3i.ONE):
				bury(t, lo, size, chest)
				break


static func treasure_size(chest: bool) -> Vector3i:
	return Vector3i(8, 6, 6) if chest else Vector3i(4, 4, 4)


func _all_natural(lo: Vector3i, hi: Vector3i) -> bool:
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				if not Blocks.is_natural(blocks[index(x, y, z)]):
					return false
	return true


func bury(t: int, lo: Vector3i, size: Vector3i, chest: bool, vault := -1) -> void:
	var number := treasure_list.size()
	var cells := PackedInt32Array()
	var hi := lo + size - Vector3i.ONE
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var i := index(x, y, z)
				var b := Blocks.RELIC
				if chest:
					var edge := (x == lo.x or x == hi.x) and (z == lo.z or z == hi.z)
					b = Blocks.CHEST_TRIM if y == lo.y + 3 or edge else Blocks.CHEST
				blocks[i] = b
				treasures[i] = number
				cells.append(i)
	treasure_list.append({"type": t, "center": (Vector3(lo) + Vector3(size) * 0.5) * VOXEL, "cells": cells, "lo": lo, "hi": hi, "found": false, "vault": vault})
	_touch(lo, hi, false)
