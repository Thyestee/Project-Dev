extends Node3D
# The world: the ground under your house, the hidden rooms, edits, ray casts, lights and the
# meshes.
#
# Every cell holds a block and a density. Built things (the house, the hidden rooms, treasure,
# furniture) are crisp cubes, VOXEL metres on a side, with density 255. The ground is smooth:
# its density runs from 254 deep inside down to 128 at its surface, and air goes from 127 down
# to 0, so the surface can sit anywhere in a cell and each pickaxe blow wears it away a little.
#
# Blocks and densities live in flat arrays, stored column by column, with a one-cell border of
# bedrock all around, so neighbour lookups never need bounds checks. Positions are in metres;
# cell coordinates are named as such. Triangles are worked out a brick (8 cells a side) at a
# time and drawn a chunk (16 cells a side) at a time.

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
const BRICK := 8
const BRICK_SHIFT := 3
const BX := SX >> BRICK_SHIFT
const BY := SY >> BRICK_SHIFT
const BZ := SZ >> BRICK_SHIFT
const PX := SX + 2
const PY := SY + 2
const STRIDE_X := PY
const STRIDE_Z := PY * PX
const MAX_LIGHTS := 16
const SOLID := 128         # densities from here up are solid
const GROUND := 254        # untouched ground
const BUILT := 255         # every built block

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
varying vec2 corner;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.103, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	info = UV2;
	// Every triangle has its own three vertices, so its corners come round in order.
	int k = VERTEX_ID % 3;
	corner = k == 0 ? vec2(1.0, 0.0) : (k == 1 ? vec2(0.0, 1.0) : vec2(0.0));
}

void fragment() {
	vec3 albedo = COLOR.rgb;
	// Cubes get their own shade and a thin dark line along their edges, the ground's triangles
	// (info.y = -2) a fainter line along theirs, and models (info.y = -1) keep their plain colours.
	bool ground = info.y < -1.5;
	if (info.y >= 0.0) {
		vec3 g = world_pos * 8.0;
		float jitter = 1.0 + (hash(floor(g - world_normal * 0.5)) - 0.5) * 2.0 * info.y;
		vec3 e = min(fract(g), 1.0 - fract(g));
		vec3 an = abs(world_normal);
		float d = an.x > 0.5 ? min(e.y, e.z) : (an.y > 0.5 ? min(e.x, e.z) : min(e.x, e.y));
		float aa = fwidth(d);
		float line = (1.0 - smoothstep(0.06 - aa, 0.06 + aa, d)) * clamp(1.0 - aa * 3.0, 0.0, 1.0);
		albedo *= jitter * (1.0 - 0.25 * line);
	} else if (ground) {
		float d = min(min(corner.x, corner.y), 1.0 - corner.x - corner.y);
		float aa = fwidth(d);
		float line = (1.0 - smoothstep(0.035 - aa, 0.035 + aa, d)) * clamp(1.0 - aa * 4.0, 0.0, 1.0);
		albedo *= 1.0 - 0.2 * line;
	}

	// Your head lamp, then the lanterns, windows and torches nearby. Slopes of the ground that
	// face a light catch more of it.
	vec3 to_lamp = lamp_pos - world_pos;
	float lamp = 1.0 - clamp(length(to_lamp) / lamp_range, 0.0, 1.0);
	float facing = ground ? 0.5 + 0.5 * max(dot(world_normal, to_lamp / max(length(to_lamp), 0.001)), 0.0) : 1.0;
	vec3 light = vec3(ambient) + vec3(1.0, 0.86, 0.66) * lamp * lamp * (3.0 - 2.0 * lamp) * facing;
	for (int k = 0; k < 16; k++) {
		vec4 lp = light_pos[k];
		if (lp.w > 0.0 && world_pos.y > light_col[k].a) {
			vec3 to = lp.xyz - world_pos;
			float dist = length(to);
			float a = 1.0 - clamp(dist / lp.w, 0.0, 1.0);
			float f = ground ? 0.45 + 0.55 * max(dot(world_normal, to / max(dist, 0.001)), 0.0) : 1.0;
			light += light_col[k].rgb * a * a * f;
		}
	}
	float shimmer = 0.75 + 0.25 * sin(TIME * 3.0 + world_pos.x * 3.1 + world_pos.y * 4.3 + world_pos.z * 2.7);
	vec3 lit = albedo * min(light, vec3(1.25)) + albedo * info.x * shimmer;
	ALBEDO = mix(lit, tint.rgb, tint.a);
}
"""

var blocks := PackedByteArray()
var dens := PackedByteArray()
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
var focus := Vector3.ZERO                 # where you are: nearby bricks are rebuilt first
var _flashes: Array = []                  # brief lights from explosions and lightning
var _wear := {}                           # cell index -> how worn a built block is (it breaks at SOLID)
var _edited := {}                         # chunk number -> true for every chunk you've changed
var _meshes := {}                         # chunk number -> MeshInstance3D
var _bricks := {}                         # brick number -> its triangles (see Mesher.build)
var _built := PackedByteArray()           # per brick: 1 once anything built has been put in it
var _dirty := {}                          # brick number -> true, to be rebuilt
var _air := PackedByteArray()             # per chunk: 1 once it has any air in it
var _build_queue: Array[int] = []         # chunks to build while loading, nearest last
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
		# Changed bricks first, nearest first. A small change is finished in one go, so it never
		# shows half done; a big one carries on next frame.
		var keys: Array = _dirty.keys()
		var c := focus / (BRICK * VOXEL) - Vector3(0.5, 0.5, 0.5)
		keys.sort_custom(func(a: int, b: int) -> bool: return _brick_pos(a).distance_squared_to(c) < _brick_pos(b).distance_squared_to(c))
		var chunks := {}
		for key: int in keys:
			_build_brick(key)
			_dirty.erase(key)
			chunks[_chunk_of_brick(key)] = true
			if keys.size() > 32 and Time.get_ticks_usec() - start > 8000:
				break
		for n: int in chunks:
			_assemble(n)
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


# How tall a box standing at lo.y, over lo..hi in x and z, can be before it meets something
# solid, up to `limit` metres. Zero if its feet are already in something.
func headroom(lo: Vector3, hi: Vector3, limit: float) -> float:
	var x0 := floori(lo.x / VOXEL)
	var z0 := floori(lo.z / VOXEL)
	var x1 := floori(hi.x / VOXEL - 0.0001)
	var z1 := floori(hi.z / VOXEL - 0.0001)
	var y := floori(lo.y / VOXEL)
	if x0 < 0 or z0 < 0 or y < 0 or x1 >= SX or z1 >= SZ:
		return 0.0
	while y < SY and y * VOXEL < lo.y + limit:
		for z in range(z0, z1 + 1):
			var i := index(x0, y, z)
			for x in range(x0, x1 + 1):
				if blocks[i] != Blocks.AIR:
					return maxf(y * VOXEL - lo.y, 0.0)
				i += STRIDE_X
		y += 1
	return limit


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


# The buried treasure a cell belongs to, or -1.
func treasure_at(c: Vector3i) -> int:
	if not in_bounds(c):
		return -1
	return treasures.get(index(c.x, c.y, c.z), -1)


# Metres below the house floor for feet at p.
func depth_at(p: Vector3) -> float:
	return FLOOR_Y * VOXEL - p.y


func spawn_point() -> Vector3:
	return House.spawn_point()


# Whether the leveller may fill this cell with ground: below the house and off the stairs.
func can_fill(c: Vector3i) -> bool:
	return c.x > 0 and c.y > 0 and c.z > 0 and c.x < SX - 1 and c.y < FLOOR_Y and c.z < SZ - 1 and not House.in_stairs(c)


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


# --- Ray casts -----------------------------------------------------------------

# What's under a ray: the first solid cell along it (`cell`), the empty cell just before it
# (`prev`), the block, how far along the ray the surface is in metres (`dist`), the point where
# it meets the surface, the surface's normal, and `face`, the side of the cell facing the ray
# (for the ground, the side the surface mostly faces). Built blocks are hit on their faces; the
# ground where its smooth surface really is. {} if nothing is in reach. `dir` must be normalized.
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	# A little further than asked: the ground's surface can stand out of its cell.
	var hit := _cast(origin, dir, max_dist + VOXEL)
	if hit.is_empty():
		return {}
	var cell: Vector3i = hit["cell"]
	var b := block(cell.x, cell.y, cell.z)
	var t: float = hit["dist"]
	var face: Vector3i = hit["face"]
	var normal := Vector3(face)
	if b <= Blocks.BEDROCK and in_bounds(cell):
		# Look for the surface along the ray, from a cell before where it met the cell to a cell
		# after, then narrow it down.
		var start := maxf(t - VOXEL, 0.0)
		var open := start
		var s := start
		var found := -1.0
		while s <= t + VOXEL:
			if _field(origin + dir * s) >= 0.0:
				found = s
				break
			open = s
			s += VOXEL * 0.25
		if found >= 0.0:
			if found > start:
				for k in 6:
					var mid := (open + found) * 0.5
					if _field(origin + dir * mid) >= 0.0:
						found = mid
					else:
						open = mid
			t = found
			var g := _gradient(origin + dir * t)
			if g.length_squared() > 0.0001:
				normal = -g.normalized()
		face = _main_axis(normal)
	if t > max_dist:
		return {}
	if normal == Vector3.ZERO:
		normal = -dir
	return {"cell": cell, "prev": hit["prev"], "block": b, "dist": t, "point": origin + dir * t, "normal": normal, "face": face}


func line_of_sight(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return true
	return _cast(a, d / length, length).is_empty()


# Walks the ray through the grid one cell at a time. Returns the first solid cell, the empty
# cell just before it, how far along the ray it starts (metres) and the side it went in through,
# or {} if there's nothing within max_dist.
func _cast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var o := origin / VOXEL
	var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3(_cell_span(dir.x), _cell_span(dir.y), _cell_span(dir.z))
	var t_max := Vector3(_first_crossing(o.x, dir.x, cell.x), _first_crossing(o.y, dir.y, cell.y), _first_crossing(o.z, dir.z, cell.z))
	var prev := cell
	var t := 0.0
	var limit := max_dist / VOXEL
	while t <= limit:
		if block(cell.x, cell.y, cell.z) != Blocks.AIR:
			return {"cell": cell, "prev": prev, "dist": t * VOXEL, "face": prev - cell}
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


static func _main_axis(n: Vector3) -> Vector3i:
	var a := n.abs()
	if a.x >= a.y and a.x >= a.z:
		return Vector3i(int(signf(n.x)), 0, 0)
	if a.y >= a.z:
		return Vector3i(0, int(signf(n.y)), 0)
	return Vector3i(0, 0, int(signf(n.z)))


# The density at p (metres), blended smoothly between cell centres, less the middle: positive
# inside the ground.
func _field(p: Vector3) -> float:
	var q := p / VOXEL - Vector3(0.5, 0.5, 0.5)
	var x := floori(q.x)
	var y := floori(q.y)
	var z := floori(q.z)
	if x < -1 or y < -1 or z < -1 or x >= SX or y >= SY or z >= SZ:
		return 127.0
	var fx := q.x - x
	var fy := q.y - y
	var fz := q.z - z
	var i := index(x, y, z)
	var a := lerpf(dens[i], dens[i + 1], fy)
	var b := lerpf(dens[i + STRIDE_X], dens[i + STRIDE_X + 1], fy)
	var c := lerpf(dens[i + STRIDE_Z], dens[i + STRIDE_Z + 1], fy)
	var d := lerpf(dens[i + STRIDE_X + STRIDE_Z], dens[i + STRIDE_X + STRIDE_Z + 1], fy)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz) - 127.5


# Which way the density rises fastest at p: into the ground.
func _gradient(p: Vector3) -> Vector3:
	var h := VOXEL * 0.4
	return Vector3(_field(p + Vector3(h, 0.0, 0.0)) - _field(p - Vector3(h, 0.0, 0.0)),
		_field(p + Vector3(0.0, h, 0.0)) - _field(p - Vector3(0.0, h, 0.0)),
		_field(p + Vector3(0.0, 0.0, h)) - _field(p - Vector3(0.0, 0.0, h)))


# --- Edits -------------------------------------------------------------------

static func _dens_for(b: int) -> int:
	if b == Blocks.AIR:
		return 0
	return GROUND if b <= Blocks.BEDROCK else BUILT


# Building the house, its furniture and the hidden rooms; rebuilt from scratch on every load,
# so not saved (unless you also changed the chunk yourself).
func put(x: int, y: int, z: int, b: int) -> void:
	var i := index(x, y, z)
	blocks[i] = b
	dens[i] = _dens_for(b)
	if b > Blocks.BEDROCK:
		_built[_brick_number(x >> BRICK_SHIFT, y >> BRICK_SHIFT, z >> BRICK_SHIFT)] = 1
	_touch(Vector3i(x, y, z), Vector3i(x, y, z), b == Blocks.AIR)


func fill(lo: Vector3i, hi: Vector3i, b: int) -> void:
	var d := _dens_for(b)
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var i := index(x, lo.y, z)
			for y in range(lo.y, hi.y + 1):
				blocks[i] = b
				dens[i] = d
				i += 1
	if b > Blocks.BEDROCK:
		for by in range(lo.y >> BRICK_SHIFT, (hi.y >> BRICK_SHIFT) + 1):
			for bz in range(lo.z >> BRICK_SHIFT, (hi.z >> BRICK_SHIFT) + 1):
				for bx in range(lo.x >> BRICK_SHIFT, (hi.x >> BRICK_SHIFT) + 1):
					_built[_brick_number(bx, by, bz)] = 1
	_touch(lo, hi, b == Blocks.AIR)


# Lowers the ground's density at a cell to `target` if that's lower, opening the cell up once it
# drops below SOLID. Built blocks stay as they are. For shaping the world as it's made.
func soften(x: int, y: int, z: int, target: int) -> void:
	var i := index(x, y, z)
	if blocks[i] > Blocks.BEDROCK or target >= dens[i]:
		return
	dens[i] = target
	if target < SOLID:
		blocks[i] = Blocks.AIR
		_air[_chunk_number(x >> CHUNK_SHIFT, y >> CHUNK_SHIFT, z >> CHUNK_SHIFT)] = 1


# One pickaxe blow at `point` (metres): the ground within `radius` cells of it wears away, most
# of all in the middle, by up to `power` of density; built blocks that can be dug wear down until
# they break. Only what a pickaxe of `tier` can dig is touched, and treasure never is. Returns how
# many cells broke open, the block that wore away the most and whether a hidden room's wall came
# down.
func dent(point: Vector3, radius: float, power: float, tier: int) -> Dictionary:
	var c := point / VOXEL
	var r2 := radius * radius
	var x0 := clampi(floori(c.x - radius), 1, SX - 2)
	var x1 := clampi(floori(c.x + radius), 1, SX - 2)
	var y0 := clampi(floori(c.y - radius), 1, SY - 2)
	var y1 := clampi(floori(c.y + radius), 1, SY - 2)
	var z0 := clampi(floori(c.z - radius), 1, SZ - 2)
	var z1 := clampi(floori(c.z + radius), 1, SZ - 2)
	var tiers := Blocks.TIER
	var worn := {}
	var removed := 0
	var changed := false
	var vault_hit := false
	for z in range(z0, z1 + 1):
		var dz := z + 0.5 - c.z
		for x in range(x0, x1 + 1):
			var dx := x + 0.5 - c.x
			var h2 := r2 - dx * dx - dz * dz
			if h2 <= 0.0:
				continue
			var hy := sqrt(h2)
			var ya := maxi(ceili(c.y - hy - 0.5), y0)
			var yb := mini(floori(c.y + hy - 0.5), y1)
			var i := index(x, ya, z)
			for y in range(ya, yb + 1):
				var dy := y + 0.5 - c.y
				var k := 1.0 - (dx * dx + dy * dy + dz * dz) / r2
				var amount := int(power * k * k)
				if amount > 0:
					var b := blocks[i]
					var d := dens[i]
					if b == Blocks.AIR:
						if d > 0:
							dens[i] = maxi(d - amount, 0)
							changed = true
					elif b <= Blocks.BEDROCK:
						if tiers[b] >= 0 and tiers[b] <= tier:
							d -= amount
							if d < SOLID:
								blocks[i] = Blocks.AIR
								d = maxi(d, 0)
								removed += 1
							dens[i] = d
							worn[b] = int(worn.get(b, 0)) + amount
							changed = true
					elif tiers[b] >= 0 and tiers[b] <= tier and not Blocks.is_treasure(b):
						var w: int = int(_wear.get(i, 0)) + amount
						worn[b] = int(worn.get(b, 0)) + amount
						if w >= SOLID:
							_wear.erase(i)
							blocks[i] = Blocks.AIR
							dens[i] = 0
							removed += 1
							vault_hit = vault_hit or Blocks.is_vault(b)
							changed = true
						else:
							_wear[i] = w
				i += 1
	if changed:
		var lo := Vector3i(x0, y0, z0)
		var hi := Vector3i(x1, y1, z1)
		_mark_edited(lo, hi)
		_touch(lo, hi, removed > 0)
	var most := Blocks.AIR
	for b: int in worn:
		if most == Blocks.AIR or int(worn[b]) > int(worn[most]):
			most = b
	return {"removed": removed, "block": most, "vault": vault_hit}


# Blows a ball of ground away: everything within `radius` cells of `center` (cells) that `tier`
# can break. The ground at its edge is left smooth, and treasure stays where it was. Returns the
# same as dent().
func blast(center: Vector3, radius: float, tier: int) -> Dictionary:
	var reach := radius + 1.0
	var x0 := clampi(floori(center.x - reach), 1, SX - 2)
	var x1 := clampi(floori(center.x + reach), 1, SX - 2)
	var y0 := clampi(floori(center.y - reach), 1, SY - 2)
	var y1 := clampi(floori(center.y + reach), 1, SY - 2)
	var z0 := clampi(floori(center.z - reach), 1, SZ - 2)
	var z1 := clampi(floori(center.z + reach), 1, SZ - 2)
	var tiers := Blocks.TIER
	var worn := {}
	var removed := 0
	var changed := false
	var vault_hit := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var i := index(x, y0, z)
			for y in range(y0, y1 + 1):
				var dist := Vector3(x + 0.5, y + 0.5, z + 0.5).distance_to(center)
				if dist < reach:
					var want := int(clampf(127.5 + (dist - radius) * 127.5, 0.0, float(GROUND)))
					var b := blocks[i]
					var d := dens[i]
					if b == Blocks.AIR:
						if want < d:
							dens[i] = want
							changed = true
					elif b <= Blocks.BEDROCK:
						if tiers[b] >= 0 and tiers[b] <= tier and want < d:
							dens[i] = want
							if want < SOLID:
								blocks[i] = Blocks.AIR
								removed += 1
								worn[b] = int(worn.get(b, 0)) + 1
							changed = true
					elif dist < radius and tiers[b] >= 0 and tiers[b] <= tier and not Blocks.is_treasure(b):
						blocks[i] = Blocks.AIR
						dens[i] = 0
						_wear.erase(i)
						removed += 1
						vault_hit = vault_hit or Blocks.is_vault(b)
						changed = true
				i += 1
	if changed:
		var lo := Vector3i(x0, y0, z0)
		var hi := Vector3i(x1, y1, z1)
		_mark_edited(lo, hi)
		_touch(lo, hi, removed > 0)
	var most := Blocks.AIR
	for b: int in worn:
		if most == Blocks.AIR or int(worn[b]) > int(worn[most]):
			most = b
	return {"removed": removed, "block": most, "vault": vault_hit}


# The leveller: makes the ground you're looking at flat. The plane runs through `point` (metres),
# square to `axis` and lined up with the nearest cell boundary, with open air on its `side` (+1
# or -1). Within `half` cells of the point along the plane, ground standing up to `cut` cells
# proud of it is cut away (as far as `tier` allows), and holes up to `fill_depth` cells deep are
# filled with `fill_block`. Nothing is filled inside keep_lo..keep_hi (metres): that's you.
# Treasure stays put.
func flatten(point: Vector3, axis: int, side: int, half: int, cut: int, fill_depth: int, tier: int, fill_block: int, keep_lo: Vector3, keep_hi: Vector3) -> Dictionary:
	var p := point / VOXEL
	var plane := roundi(p[axis])
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var cu := floori(p[u])
	var cv := floori(p[v])
	var keep_c0 := Vector3i((keep_lo / VOXEL).floor())
	var keep_c1 := Vector3i((keep_hi / VOXEL - Vector3(0.0001, 0.0001, 0.0001)).floor())
	var removed := 0
	var placed := 0
	var changed := false
	var vault_hit := false
	for du in range(-half, half):
		for dv in range(-half, half):
			for k in range(-fill_depth, cut):
				# k counts cells out from the plane into the open air: 0 is the first one in front.
				var c := Vector3i.ZERO
				c[u] = cu + du
				c[v] = cv + dv
				c[axis] = plane + k if side > 0 else plane - 1 - k
				if c.x < 1 or c.y < 1 or c.z < 1 or c.x > SX - 2 or c.y > SY - 2 or c.z > SZ - 2:
					continue
				var i := index(c.x, c.y, c.z)
				var b := blocks[i]
				var d := dens[i]
				var want := int(clampf(127.5 - (k + 0.5) * 127.5, 0.0, float(GROUND)))
				if k >= 0:
					# In front of the plane: cut it down.
					if b == Blocks.AIR:
						if d > want:
							dens[i] = want
							changed = true
					elif b <= Blocks.BEDROCK:
						if Blocks.diggable(b, tier) and d > want:
							dens[i] = want
							if want < SOLID:
								blocks[i] = Blocks.AIR
								removed += 1
							changed = true
					elif Blocks.diggable(b, tier):
						blocks[i] = Blocks.AIR
						dens[i] = want
						_wear.erase(i)
						removed += 1
						vault_hit = vault_hit or Blocks.is_vault(b)
						changed = true
				elif b == Blocks.AIR:
					# Behind it: fill it in.
					if d >= want or not can_fill(c):
						continue
					if c.x >= keep_c0.x and c.x <= keep_c1.x and c.y >= keep_c0.y and c.y <= keep_c1.y and c.z >= keep_c0.z and c.z <= keep_c1.z:
						continue
					dens[i] = want
					if want >= SOLID:
						blocks[i] = fill_block
						placed += 1
					changed = true
				elif b <= Blocks.BEDROCK and d < want:
					dens[i] = want
					changed = true
	if changed:
		var lo := Vector3i.ZERO
		var hi := Vector3i.ZERO
		lo[u] = cu - half
		hi[u] = cu + half - 1
		lo[v] = cv - half
		hi[v] = cv + half - 1
		lo[axis] = plane - (fill_depth if side > 0 else cut) - 1
		hi[axis] = plane + (cut if side > 0 else fill_depth)
		lo = lo.clamp(Vector3i.ZERO, Vector3i(SX - 1, SY - 1, SZ - 1))
		hi = hi.clamp(Vector3i.ZERO, Vector3i(SX - 1, SY - 1, SZ - 1))
		_mark_edited(lo, hi)
		_touch(lo, hi, removed > 0)
	return {"removed": removed, "placed": placed, "vault": vault_hit, "changed": changed}


# Takes a treasure out of the ground: it's been found.
func collect(t: int) -> void:
	var info := treasure_list[t]
	info["found"] = true
	for i: int in info["cells"]:
		blocks[i] = Blocks.AIR
		dens[i] = 0
		treasures.erase(i)
	_mark_edited(info["lo"], info["hi"])
	_touch(info["lo"], info["hi"], true)


static func _chunk_number(cx: int, cy: int, cz: int) -> int:
	return cx + cz * CX + cy * CX * CZ


static func _brick_number(bx: int, by: int, bz: int) -> int:
	return bx + bz * BX + by * BX * BZ


static func _brick_pos(n: int) -> Vector3:
	return Vector3(n % BX, n / (BX * BZ), (n / BX) % BZ)


static func _chunk_of_brick(n: int) -> int:
	return _chunk_number((n % BX) >> 1, (n / (BX * BZ)) >> 1, ((n / BX) % BZ) >> 1)


func _mark_edited(lo: Vector3i, hi: Vector3i) -> void:
	for cy in range(lo.y >> CHUNK_SHIFT, (hi.y >> CHUNK_SHIFT) + 1):
		for cz in range(lo.z >> CHUNK_SHIFT, (hi.z >> CHUNK_SHIFT) + 1):
			for cx in range(lo.x >> CHUNK_SHIFT, (hi.x >> CHUNK_SHIFT) + 1):
				_edited[_chunk_number(cx, cy, cz)] = true


# The save keeps every chunk you've changed as it is now, blocks then densities, packed and
# compressed.
func edits_data() -> Dictionary:
	if _edited.is_empty():
		return {}
	var ids := PackedInt32Array(_edited.keys())
	var raw := PackedByteArray()
	var raw_dens := PackedByteArray()
	for n: int in ids:
		var cx := n % CX
		var cz := (n / CX) % CZ
		var cy := n / (CX * CZ)
		for z in range(cz * CHUNK, cz * CHUNK + CHUNK):
			for x in range(cx * CHUNK, cx * CHUNK + CHUNK):
				var i := index(x, cy * CHUNK, z)
				raw.append_array(blocks.slice(i, i + CHUNK))
				raw_dens.append_array(dens.slice(i, i + CHUNK))
	raw.append_array(raw_dens)
	return {"format": 2, "chunks": Marshalls.raw_to_base64(ids.to_byte_array()), "size": raw.size(),
		"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_ZSTD))}


func apply_edits_data(data: Dictionary) -> void:
	if str(data.get("data", "")).is_empty() or int(data.get("format", 1)) != 2:
		return
	var ids := Marshalls.base64_to_raw(str(data.get("chunks", ""))).to_int32_array()
	var raw := Marshalls.base64_to_raw(str(data["data"])).decompress(int(data.get("size", 0)), FileAccess.COMPRESSION_ZSTD)
	var per := CHUNK * CHUNK * CHUNK
	if raw.size() != ids.size() * per * 2:
		return
	var k := 0
	var kd := ids.size() * per
	for n: int in ids:
		if n < 0 or n >= CX * CY * CZ:
			k += per
			kd += per
			continue
		var cx := n % CX
		var cz := (n / CX) % CZ
		var cy := n / (CX * CZ)
		for z in range(cz * CHUNK, cz * CHUNK + CHUNK):
			for x in range(cx * CHUNK, cx * CHUNK + CHUNK):
				var i := index(x, cy * CHUNK, z)
				for y in CHUNK:
					var b := raw[k]
					blocks[i + y] = b
					dens[i + y] = raw[kd]
					if b > Blocks.BEDROCK:
						_built[_brick_number(x >> BRICK_SHIFT, (cy * CHUNK + y) >> BRICK_SHIFT, z >> BRICK_SHIFT)] = 1
					k += 1
					kd += 1
		_edited[n] = true
		_air[n] = 1
	# Treasure that's no longer in the ground has been found.
	for t in treasure_list.size():
		var info := treasure_list[t]
		var first: int = info["cells"][0]
		if not info["found"] and not Blocks.is_treasure(blocks[first]):
			collect(t)


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


# --- Meshes --------------------------------------------------------------------

# Queues every chunk that can have something to draw (it or a neighbour has air), nearest first.
func queue_all_chunks(center: Vector3) -> void:
	_dirty.clear()
	_build_queue.clear()
	for cy in CY:
		for cz in CZ:
			for cx in CX:
				if _near_air(cx, cy, cz):
					_build_queue.append(_chunk_number(cx, cy, cz))
	# Nearest chunks last, since the queue is built from the back.
	var c := center / (CHUNK * VOXEL) - Vector3(0.5, 0.5, 0.5)
	_build_queue.sort_custom(func(a: int, b: int) -> bool: return _chunk_pos(a).distance_squared_to(c) > _chunk_pos(b).distance_squared_to(c))
	_build_total = _build_queue.size()


static func _chunk_pos(n: int) -> Vector3:
	return Vector3(n % CX, n / (CX * CZ), (n / CX) % CZ)


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
		if x >= 0 and y >= 0 and z >= 0 and x < CX and y < CY and z < CZ and _air[_chunk_number(x, y, z)] == 1:
			return true
	return false


# Marks the bricks around a changed box for rebuilding (and its chunks as having air, if they do
# now).
func _touch(lo: Vector3i, hi: Vector3i, made_air: bool) -> void:
	var c0 := Vector3i(clampi(lo.x - 1, 0, SX - 1), clampi(lo.y - 1, 0, SY - 1), clampi(lo.z - 1, 0, SZ - 1))
	var c1 := Vector3i(clampi(hi.x + 1, 0, SX - 1), clampi(hi.y + 1, 0, SY - 1), clampi(hi.z + 1, 0, SZ - 1))
	for by in range(c0.y >> BRICK_SHIFT, (c1.y >> BRICK_SHIFT) + 1):
		for bz in range(c0.z >> BRICK_SHIFT, (c1.z >> BRICK_SHIFT) + 1):
			for bx in range(c0.x >> BRICK_SHIFT, (c1.x >> BRICK_SHIFT) + 1):
				_dirty[_brick_number(bx, by, bz)] = true
	if made_air:
		for cy in range(clampi(lo.y, 0, SY - 1) >> CHUNK_SHIFT, (clampi(hi.y, 0, SY - 1) >> CHUNK_SHIFT) + 1):
			for cz in range(clampi(lo.z, 0, SZ - 1) >> CHUNK_SHIFT, (clampi(hi.z, 0, SZ - 1) >> CHUNK_SHIFT) + 1):
				for cx in range(clampi(lo.x, 0, SX - 1) >> CHUNK_SHIFT, (clampi(hi.x, 0, SX - 1) >> CHUNK_SHIFT) + 1):
					_air[_chunk_number(cx, cy, cz)] = 1


func _build_brick(n: int) -> void:
	var bx := n % BX
	var bz := (n / BX) % BZ
	var by := n / (BX * BZ)
	var data: Array = Mesher.build(blocks, dens, STRIDE_X, STRIDE_Z, bx * BRICK, by * BRICK, bz * BRICK, _built[n] == 1, VOXEL)
	if data.is_empty():
		_bricks.erase(n)
	else:
		_bricks[n] = data


func _build_chunk(n: int) -> void:
	var cx := n % CX
	var cz := (n / CX) % CZ
	var cy := n / (CX * CZ)
	for k in 8:
		_build_brick(_brick_number(cx * 2 + (k & 1), cy * 2 + ((k >> 1) & 1), cz * 2 + (k >> 2)))
	_assemble(n)


# Puts a chunk's mesh together from its eight bricks.
func _assemble(n: int) -> void:
	var cx := n % CX
	var cz := (n / CX) % CZ
	var cy := n / (CX * CZ)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var infos := PackedVector2Array()
	for k in 8:
		var data: Array = _bricks.get(_brick_number(cx * 2 + (k & 1), cy * 2 + ((k >> 1) & 1), cz * 2 + (k >> 2)), [])
		if not data.is_empty():
			verts.append_array(data[0])
			normals.append_array(data[1])
			colors.append_array(data[2])
			infos.append_array(data[3])
	var mi: MeshInstance3D = _meshes.get(n)
	if verts.is_empty():
		if mi:
			mi.queue_free()
			_meshes.erase(n)
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = infos
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_meshes[n] = mi
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
	_wear.clear()
	_bricks.clear()
	_air = PackedByteArray()
	_air.resize(CX * CY * CZ)
	_built = PackedByteArray()
	_built.resize(BX * BY * BZ)
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
	# All of it solid ground to begin with.
	dens = PackedByteArray()
	dens.resize(blocks.size())
	dens.fill(GROUND)


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


# Turns the `host` blocks in an ellipsoid of cells into `kind`.
func _blob(c: Vector3i, r: Vector3, host: int, kind: int) -> void:
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
				if blocks[i] == host:
					blocks[i] = kind
				i += 1


# A few winding caves, all well below the house, with smooth walls.
func _carve_caves(rng: RandomNumberGenerator) -> void:
	for n in 4:
		var p := Vector3(rng.randf_range(48.0, SX - 48.0), rng.randf_range(40.0, FLOOR_Y - 80.0), rng.randf_range(48.0, SZ - 48.0))
		var yaw := rng.randf() * TAU
		var pitch := 0.0
		for s in rng.randi_range(40, 90):
			var radius := clampf(1.1 + 0.4 * sin(s * 0.25 + n) + rng.randf_range(-0.12, 0.12), 0.75, 1.6) / VOXEL
			_hollow(p, Vector3(radius, radius * 0.8, radius))
			p += Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * (0.75 / VOXEL)
			yaw += rng.randf_range(-0.35, 0.35)
			pitch = clampf(pitch + rng.randf_range(-0.15, 0.15), -0.45, 0.45) * 0.9
			if p.x < 24.0 or p.x > SX - 24.0 or p.z < 24.0 or p.z > SZ - 24.0 or p.y < 28.0 or p.y > FLOOR_Y - 60.0:
				break


# Opens up an ellipsoid of ground around c (cells) with radii r, its surface smooth.
func _hollow(c: Vector3, r: Vector3) -> void:
	var smallest := minf(r.x, minf(r.y, r.z))
	var outer := 1.0 + 1.5 / smallest
	var x0 := maxi(floori(c.x - r.x * outer), 1)
	var x1 := mini(ceili(c.x + r.x * outer), SX - 2)
	var z0 := maxi(floori(c.z - r.z * outer), 1)
	var z1 := mini(ceili(c.z + r.z * outer), SZ - 2)
	for z in range(z0, z1 + 1):
		var dz := (z + 0.5 - c.z) / r.z
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5 - c.x) / r.x
			var q := dx * dx + dz * dz
			if q >= outer * outer:
				continue
			var hy := sqrt(outer * outer - q) * r.y
			var y0 := maxi(floori(c.y - hy), 1)
			var y1 := mini(ceili(c.y + hy), FLOOR_Y - 2)
			var i := index(x, y0, z)
			for y in range(y0, y1 + 1):
				var dy := (y + 0.5 - c.y) / r.y
				# Roughly how many cells outside the ellipsoid the cell's centre is.
				var out := (sqrt(q + dy * dy) - 1.0) * smallest
				var want := int(clampf(127.5 + out * 127.5, 0.0, float(GROUND)))
				if want < dens[i] and blocks[i] <= Blocks.BEDROCK:
					dens[i] = want
					if want < SOLID:
						blocks[i] = Blocks.AIR
				i += 1
	_touch(Vector3i(x0, maxi(floori(c.y - r.y * outer), 1), z0), Vector3i(x1, mini(ceili(c.y + r.y * outer), SY - 2), z1), true)


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
				dens[i] = BUILT
				treasures[i] = number
				cells.append(i)
	for by in range(lo.y >> BRICK_SHIFT, (hi.y >> BRICK_SHIFT) + 1):
		for bz in range(lo.z >> BRICK_SHIFT, (hi.z >> BRICK_SHIFT) + 1):
			for bx in range(lo.x >> BRICK_SHIFT, (hi.x >> BRICK_SHIFT) + 1):
				_built[_brick_number(bx, by, bz)] = 1
	treasure_list.append({"type": t, "center": (Vector3(lo) + Vector3(size) * 0.5) * VOXEL, "cells": cells, "lo": lo, "hi": hi, "found": false, "vault": vault})
	_touch(lo, hi, false)
