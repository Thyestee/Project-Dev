extends Node3D
# The world: endless ground under your house, down to the bedrock 10 km below, made a chunk at a
# time as you go and let go again once you're far away (see WorldGen). Your house and the stairs
# down are built into it, and everything you change in it is kept and saved.
#
# Every cell holds a block and a density. Built things (the house, the hidden rooms, treasure,
# furniture) are crisp cubes, VOXEL metres on a side, with density 255. The ground is smooth:
# its density runs from 254 deep inside down to 128 at its surface, and air goes from 127 down to
# 0, so the surface can sit anywhere in a cell and each pickaxe blow wears it away a little.
#
# Chunks are 16 cells a side, their cells stored y fastest, then x, then z. A chunk that isn't in
# memory counts as bedrock. Triangles are worked out a brick (8 cells a side) at a time, from a
# copy of the chunk with a one-cell border taken from its neighbours, and drawn a chunk at a time.
# Positions are in metres; cell coordinates are named as such.

const Blocks := preload("res://scripts/blocks.gd")
const Mesher := preload("res://scripts/chunk_mesher.gd")
const House := preload("res://scripts/house.gd")
const Gen := preload("res://scripts/worldgen.gd")
const Rooms := preload("res://scripts/rooms.gd")

const VOXEL := 0.125
const FLOOR_Y := 344             # cell height of the house floor; the ground below it can be dug
const TOP_Y := 384               # nothing above this but bedrock
const BOTTOM_Y := FLOOR_Y - 80000  # 10 km down: the bottom of the world
const BOTTOM_CY := -4979         # the chunks the world runs between, bottom and (one past the) top
const TOP_CY := 24
const CHUNK := 16
const CELLS := 4096
const PAD := 18                  # a chunk with its border
const BRICK := 8
const SOLID := 128               # densities from here up are solid
const GROUND := 254              # untouched ground
const BUILT := 255               # every built block
const MAX_LIGHTS := 16
const VIEW := 6                  # chunks out from you that are drawn, sideways
const VIEW_Y := 4                # and up and down
const KEEP := 9.5                # further than this sideways (or KEEP_Y up or down), a chunk is let go
const KEEP_Y := 7
const HAS_AIR := 1
const HAS_BUILT := 2
const EDITED := 4
const PINNED := 8

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

var world_seed := 0
var house_tier := 0
var gen: Gen
var material: ShaderMaterial
var lights: Array = []           # your house's lights: {"pos", "color", "range", "min_y", "flicker"}
var lit_rooms := {}              # hidden rooms whose torches burn (they light up when you break in)
var rooms := {}                  # room id -> room (see Rooms), for every room near you
var _pending := {}               # room id -> room: rooms not all made yet
var treasures := {}              # treasure id -> its place in the ground, for buried treasure near you
var found_ids := {}              # treasure id -> true, for every treasure ever dug out
var furniture := {}              # cell key -> id of the furniture standing there
var loading := false
var focus := Vector3.ZERO        # where you are: the world is made and drawn around it
var pinning := false             # chunks touched while this is on stay in memory for good (your house)
var on_room_loaded := Callable()
var on_room_unloaded := Callable()
var _cb := {}                    # chunk key -> its blocks
var _cd := {}                    # chunk key -> its densities
var _flags := {}                 # chunk key -> HAS_AIR, HAS_BUILT, EDITED and PINNED
var _blobs := {}                 # chunk key -> blocks, densities and flags, compressed, for every chunk you've changed
var _stale := {}                 # chunk key -> true: changed since its blob was made
var _meshes := {}                # chunk key -> MeshInstance3D
var _bricks := {}                # chunk key * 8 + brick -> its triangles (see Mesher.build)
var _drawn := {}                 # chunk key -> true once its bricks have been worked out
var _dirty := {}                 # chunk key -> bit mask of its bricks to work out again
var _center := Vector3i(1 << 28, 0, 0)
var _gen_list: Array[int] = []   # chunks to make, nearest first
var _gen_at := 0
var _mesh_list: Array[int] = []  # chunks to draw, nearest first
var _mesh_at := 0
var _flashes: Array = []         # brief lights from explosions and lightning
var _wear := {}                  # cell key -> how worn a built block is (it breaks at SOLID)
var _empty := PackedByteArray()
var _solid := PackedByteArray()  # a chunk of bedrock: what isn't in memory
var _thick := PackedByteArray()  # and its densities

static var _gen_offsets: Array[Vector3i] = []
static var _view_offsets: Array[Vector3i] = []


static func _static_init() -> void:
	# Every chunk around you that gets made, and every one that gets drawn, nearest first.
	var all: Array[Vector3i] = []
	var r := ceili(VIEW + 2.0)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for dy in range(-VIEW_Y - 1, VIEW_Y + 2):
				if dx * dx + dz * dz <= (VIEW + 2.0) * (VIEW + 2.0):
					all.append(Vector3i(dx, dy, dz))
	all.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _rank(a) < _rank(b))
	for o in all:
		_gen_offsets.append(o)
		if o.x * o.x + o.z * o.z <= (VIEW + 0.5) * (VIEW + 0.5) and absi(o.y) <= VIEW_Y:
			_view_offsets.append(o)


static func _rank(o: Vector3i) -> float:
	return o.x * o.x + o.z * o.z + 1.7 * o.y * o.y


func _ready() -> void:
	var shader := Shader.new()
	shader.code = SHADER
	material = ShaderMaterial.new()
	material.shader = shader
	_solid.resize(CELLS)
	_solid.fill(Blocks.BEDROCK)
	_thick.resize(CELLS)
	_thick.fill(GROUND)


# --- Keys and lookups ---------------------------------------------------------------------------

static func ckey(cx: int, cy: int, cz: int) -> int:
	return ((cx + 2097152) << 36) | ((cz + 2097152) << 14) | (cy + 8192)


static func chunk_of_key(k: int) -> Vector3i:
	return Vector3i((k >> 36) - 2097152, (k & 16383) - 8192, ((k >> 14) & 4194303) - 2097152)


# A number for every cell, for keeping track of things by cell.
static func key(x: int, y: int, z: int) -> int:
	return ((x + 2097152) << 40) | ((z + 2097152) << 18) | (y + 131072)


static func cell_of(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x / VOXEL), floori(p.y / VOXEL), floori(p.z / VOXEL))


static func center_of(c: Vector3i) -> Vector3:
	return (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * VOXEL


static func _at(x: int, y: int, z: int) -> int:
	return (y & 15) | ((x & 15) << 4) | ((z & 15) << 8)


func block(x: int, y: int, z: int) -> int:
	var b: PackedByteArray = _cb.get(ckey(x >> 4, y >> 4, z >> 4), _solid)
	return b[(y & 15) | ((x & 15) << 4) | ((z & 15) << 8)]


func density(x: int, y: int, z: int) -> int:
	var d: PackedByteArray = _cd.get(ckey(x >> 4, y >> 4, z >> 4), _thick)
	return d[(y & 15) | ((x & 15) << 4) | ((z & 15) << 8)]


func is_loaded(c: Vector3i) -> bool:
	return _cb.has(ckey(c.x >> 4, c.y >> 4, c.z >> 4))


func box_hits_solid(lo: Vector3, hi: Vector3) -> bool:
	var x0 := floori(lo.x / VOXEL)
	var y0 := floori(lo.y / VOXEL)
	var z0 := floori(lo.z / VOXEL)
	var x1 := floori(hi.x / VOXEL - 0.0001)
	var y1 := floori(hi.y / VOXEL - 0.0001)
	var z1 := floori(hi.z / VOXEL - 0.0001)
	if y0 < BOTTOM_Y or y1 >= TOP_Y:
		return true
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var y := y0
			while y <= y1:
				var b: PackedByteArray = _cb.get(ckey(x >> 4, y >> 4, z >> 4), _solid)
				var top := mini(y1, y | 15)
				var i := (y & 15) | ((x & 15) << 4) | ((z & 15) << 8)
				for n in top - y + 1:
					if b[i + n] != Blocks.AIR:
						return true
				y = top + 1
	return false


# How tall a box standing at lo.y, over lo..hi in x and z, can be before it meets something
# solid, up to `limit` metres. Zero if its feet are already in something.
func headroom(lo: Vector3, hi: Vector3, limit: float) -> float:
	var x0 := floori(lo.x / VOXEL)
	var z0 := floori(lo.z / VOXEL)
	var x1 := floori(hi.x / VOXEL - 0.0001)
	var z1 := floori(hi.z / VOXEL - 0.0001)
	var y := floori(lo.y / VOXEL)
	if y < BOTTOM_Y:
		return 0.0
	while y < TOP_Y and y * VOXEL < lo.y + limit:
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				if block(x, y, z) != Blocks.AIR:
					return maxf(y * VOXEL - lo.y, 0.0)
		y += 1
	return limit


# What a box would hold on to, climbing: 0 nothing solid, 1 something you can climb, 2 only stone
# too smooth to climb (the walls of trials and checkpoints).
func grip(lo: Vector3, hi: Vector3) -> int:
	var x0 := floori(lo.x / VOXEL)
	var y0 := floori(lo.y / VOXEL)
	var z0 := floori(lo.z / VOXEL)
	var x1 := floori(hi.x / VOXEL - 0.0001)
	var y1 := floori(hi.y / VOXEL - 0.0001)
	var z1 := floori(hi.z / VOXEL - 0.0001)
	var smooth := false
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				var b := block(x, y, z)
				if b != Blocks.AIR:
					if not Blocks.is_smooth(b):
						return 1
					smooth = true
	return 2 if smooth else 0


# The buried treasure a cell belongs to, or "".
func treasure_at(c: Vector3i) -> String:
	for id: String in treasures:
		var t: Dictionary = treasures[id]
		var lo: Vector3i = t["lo"]
		var hi: Vector3i = t["hi"]
		if c.x >= lo.x and c.x <= hi.x and c.y >= lo.y and c.y <= hi.y and c.z >= lo.z and c.z <= hi.z:
			return id
	return ""


func nearest_treasure_distance(p: Vector3) -> float:
	var best := INF
	for id: String in treasures:
		best = minf(best, p.distance_to(treasures[id]["center"]))
	return best


# Metres below the house floor for feet at p.
func depth_at(p: Vector3) -> float:
	return FLOOR_Y * VOXEL - p.y


func spawn_point() -> Vector3:
	return House.spawn_point()


# Whether flattening may fill this cell with ground: below the house, off the stairs and above
# the bedrock at the bottom.
func can_fill(c: Vector3i) -> bool:
	return c.y < FLOOR_Y and c.y > BOTTOM_Y + 16 and not House.in_stairs(c)


# The plain rock that's usually found at a cell.
func rock_at(c: Vector3i) -> int:
	return gen.rock_at(c.x, c.y, c.z)


# The hidden room whose inside holds point p (metres), or "".
func room_containing(p: Vector3) -> String:
	for id: String in rooms:
		if Rooms.contains(rooms[id], p):
			return id
	return ""


# Hidden rooms whose walls come within `radius` cells of `center` (cells).
func rooms_near(center: Vector3, radius: float) -> Array[String]:
	var out: Array[String] = []
	for id: String in rooms:
		var room: Dictionary = rooms[id]
		var lo: Vector3 = Vector3(room["shell_lo"]) - Vector3.ONE * (radius + 1.0)
		var hi: Vector3 = Vector3(room["shell_hi"]) + Vector3.ONE * (radius + 2.0)
		if center.x >= lo.x and center.y >= lo.y and center.z >= lo.z and center.x <= hi.x and center.y <= hi.y and center.z <= hi.z:
			out.append(id)
	return out


# --- Ray casts -----------------------------------------------------------------------------------

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
	if b <= Blocks.BEDROCK:
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
	var last_key := -1
	var b: PackedByteArray = _solid
	while t <= limit:
		var k := ckey(cell.x >> 4, cell.y >> 4, cell.z >> 4)
		if k != last_key:
			last_key = k
			b = _cb.get(k, _solid)
		if b[(cell.y & 15) | ((cell.x & 15) << 4) | ((cell.z & 15) << 8)] != Blocks.AIR:
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
	var fx := q.x - x
	var fy := q.y - y
	var fz := q.z - z
	var v0: float
	var v1: float
	var v2: float
	var v3: float
	var v4: float
	var v5: float
	var v6: float
	var v7: float
	if (x & 15) < 15 and (y & 15) < 15 and (z & 15) < 15:
		# All eight in one chunk.
		var d: PackedByteArray = _cd.get(ckey(x >> 4, y >> 4, z >> 4), _thick)
		var i := (y & 15) | ((x & 15) << 4) | ((z & 15) << 8)
		v0 = d[i]
		v1 = d[i + 1]
		v2 = d[i + 16]
		v3 = d[i + 17]
		v4 = d[i + 256]
		v5 = d[i + 257]
		v6 = d[i + 272]
		v7 = d[i + 273]
	else:
		v0 = density(x, y, z)
		v1 = density(x, y + 1, z)
		v2 = density(x + 1, y, z)
		v3 = density(x + 1, y + 1, z)
		v4 = density(x, y, z + 1)
		v5 = density(x, y + 1, z + 1)
		v6 = density(x + 1, y, z + 1)
		v7 = density(x + 1, y + 1, z + 1)
	var a := lerpf(v0, v1, fy)
	var b := lerpf(v2, v3, fy)
	var c := lerpf(v4, v5, fy)
	var e := lerpf(v6, v7, fy)
	return lerpf(lerpf(a, b, fx), lerpf(c, e, fx), fz) - 127.5


# Which way the density rises fastest at p: into the ground.
func _gradient(p: Vector3) -> Vector3:
	var h := VOXEL * 0.4
	return Vector3(_field(p + Vector3(h, 0.0, 0.0)) - _field(p - Vector3(h, 0.0, 0.0)),
		_field(p + Vector3(0.0, h, 0.0)) - _field(p - Vector3(0.0, h, 0.0)),
		_field(p + Vector3(0.0, 0.0, h)) - _field(p - Vector3(0.0, 0.0, h)))


# --- Changing the world ---------------------------------------------------------------------------

static func _dens_for(b: int) -> int:
	if b == Blocks.AIR:
		return 0
	return GROUND if b <= Blocks.BEDROCK else BUILT


# Makes sure a chunk is in memory, making it now if need be. False if it's outside the world.
func _ensure(k: int) -> bool:
	if _cb.has(k):
		if pinning:
			_flags[k] = int(_flags[k]) | PINNED
		return true
	var c := chunk_of_key(k)
	if c.y < BOTTOM_CY or c.y >= TOP_CY:
		return false
	_make(k)
	return true


# The chunks a box of cells touches, made if need be.
func _chunks_in(lo: Vector3i, hi: Vector3i, make: bool) -> Array[int]:
	var out: Array[int] = []
	for cz in range(lo.z >> 4, (hi.z >> 4) + 1):
		for cx in range(lo.x >> 4, (hi.x >> 4) + 1):
			for cy in range(lo.y >> 4, (hi.y >> 4) + 1):
				var k := ckey(cx, cy, cz)
				if make:
					if _ensure(k):
						out.append(k)
				elif _cb.has(k):
					out.append(k)
	return out


# After writing into a chunk: what it now holds, and if it's one you've changed before, that it
# needs saving again.
func _wrote(k: int, b: int) -> void:
	var f: int = _flags[k]
	if b == Blocks.AIR:
		f |= HAS_AIR
	elif b > Blocks.BEDROCK:
		f |= HAS_BUILT
	_flags[k] = f
	if f & EDITED:
		_stale[k] = true


# Building the house, its furniture and decorations. A chunk you've changed yourself is saved as
# it is, these included; the rest are built afresh every time the game starts.
func put(x: int, y: int, z: int, b: int) -> void:
	var k := ckey(x >> 4, y >> 4, z >> 4)
	if not _ensure(k):
		return
	var blocks: PackedByteArray = _cb[k]
	var dens: PackedByteArray = _cd[k]
	_cb[k] = _empty
	_cd[k] = _empty
	var i := _at(x, y, z)
	blocks[i] = b
	dens[i] = _dens_for(b)
	_cb[k] = blocks
	_cd[k] = dens
	_wrote(k, b)
	_touch(Vector3i(x, y, z), Vector3i(x, y, z), b == Blocks.AIR)


# Like put, but you did it: the chunk is saved from now on.
func repaint(x: int, y: int, z: int, b: int) -> void:
	put(x, y, z, b)
	_mark_edited(Vector3i(x, y, z), Vector3i(x, y, z))


func fill(lo: Vector3i, hi: Vector3i, b: int) -> void:
	var d := _dens_for(b)
	for k in _chunks_in(lo, hi, true):
		var o := chunk_of_key(k) * CHUNK
		var x0 := maxi(lo.x, o.x)
		var x1 := mini(hi.x, o.x + 15)
		var y0 := maxi(lo.y, o.y)
		var y1 := mini(hi.y, o.y + 15)
		var z0 := maxi(lo.z, o.z)
		var z1 := mini(hi.z, o.z + 15)
		var blocks: PackedByteArray = _cb[k]
		var dens: PackedByteArray = _cd[k]
		_cb[k] = _empty
		_cd[k] = _empty
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var i := _at(x, y0, z)
				for n in y1 - y0 + 1:
					blocks[i + n] = b
					dens[i + n] = d
		_cb[k] = blocks
		_cd[k] = dens
		_wrote(k, b)
	_touch(lo, hi, b == Blocks.AIR)


# Lowers the ground's density at a cell to `target` if that's lower, opening the cell up once it
# drops below SOLID. Built blocks stay as they are. For shaping the ground round your house.
func soften(x: int, y: int, z: int, target: int) -> void:
	var k := ckey(x >> 4, y >> 4, z >> 4)
	if not _ensure(k):
		return
	var i := _at(x, y, z)
	var blocks: PackedByteArray = _cb[k]
	if blocks[i] > Blocks.BEDROCK or target >= int(_cd[k][i]):
		return
	var dens: PackedByteArray = _cd[k]
	_cd[k] = _empty
	dens[i] = target
	_cd[k] = dens
	if target < SOLID:
		_cb[k] = _empty
		blocks[i] = Blocks.AIR
		_cb[k] = blocks
		_wrote(k, Blocks.AIR)
	_dirty[k] = int(_dirty.get(k, 0)) | 255


# One pickaxe blow at `point` (metres): the ground within `radius` cells of it wears away, most
# of all in the middle, by up to `power` of density; built blocks that can be dug wear down until
# they break. Only what a pickaxe of `tier` can dig is touched, and treasure never is. Returns how
# many cells broke open, the block that wore away the most, whether a hidden room's wall came
# down, and how many cells of each ore broke out ("ore": block -> cells).
func dent(point: Vector3, radius: float, power: float, tier: int) -> Dictionary:
	var c := point / VOXEL
	var r2 := radius * radius
	var lo := Vector3i(floori(c.x - radius), maxi(floori(c.y - radius), BOTTOM_Y), floori(c.z - radius))
	var hi := Vector3i(floori(c.x + radius), mini(floori(c.y + radius), TOP_Y - 1), floori(c.z + radius))
	var tiers := Blocks.TIER
	var worn := {}
	var ore := {}
	var removed := 0
	var vault_hit := false
	for k in _chunks_in(lo, hi, false):
		var o := chunk_of_key(k) * CHUNK
		var blocks: PackedByteArray = _cb[k]
		var dens: PackedByteArray = _cd[k]
		_cb[k] = _empty
		_cd[k] = _empty
		var changed := false
		var opened := false
		for z in range(maxi(lo.z, o.z), mini(hi.z, o.z + 15) + 1):
			var dz := z + 0.5 - c.z
			for x in range(maxi(lo.x, o.x), mini(hi.x, o.x + 15) + 1):
				var dx := x + 0.5 - c.x
				var h2 := r2 - dx * dx - dz * dz
				if h2 <= 0.0:
					continue
				var hy := sqrt(h2)
				var ya := maxi(maxi(ceili(c.y - hy - 0.5), lo.y), o.y)
				var yb := mini(mini(floori(c.y + hy - 0.5), hi.y), o.y + 15)
				var i := _at(x, ya, z)
				for y in range(ya, yb + 1):
					var dy := y + 0.5 - c.y
					var f := 1.0 - (dx * dx + dy * dy + dz * dz) / r2
					var amount := int(power * f * f)
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
									opened = true
									if Blocks.is_ore(b):
										ore[b] = int(ore.get(b, 0)) + 1
								dens[i] = d
								worn[b] = int(worn.get(b, 0)) + amount
								changed = true
						elif tiers[b] >= 0 and tiers[b] <= tier and not Blocks.is_treasure(b):
							var wk := key(x, y, z)
							var w: int = int(_wear.get(wk, 0)) + amount
							worn[b] = int(worn.get(b, 0)) + amount
							if w >= SOLID:
								_wear.erase(wk)
								blocks[i] = Blocks.AIR
								dens[i] = 0
								removed += 1
								opened = true
								vault_hit = vault_hit or Blocks.is_vault(b)
								changed = true
							else:
								_wear[wk] = w
					i += 1
		_cb[k] = blocks
		_cd[k] = dens
		if changed:
			_edited(k, opened)
	if removed > 0 or not worn.is_empty():
		_touch(lo, hi, removed > 0)
	return {"removed": removed, "block": _most(worn), "vault": vault_hit, "ore": ore}


static func _most(worn: Dictionary) -> int:
	var most := Blocks.AIR
	for b: int in worn:
		if most == Blocks.AIR or int(worn[b]) > int(worn[most]):
			most = b
	return most


# Blows a ball of ground away: everything within `radius` cells of `center` (cells) that `tier`
# can break. The ground at its edge is left smooth, and treasure stays where it was. Returns the
# same as dent().
func blast(center: Vector3, radius: float, tier: int) -> Dictionary:
	var reach := radius + 1.0
	var lo := Vector3i(floori(center.x - reach), maxi(floori(center.y - reach), BOTTOM_Y), floori(center.z - reach))
	var hi := Vector3i(floori(center.x + reach), mini(floori(center.y + reach), TOP_Y - 1), floori(center.z + reach))
	var tiers := Blocks.TIER
	var worn := {}
	var ore := {}
	var removed := 0
	var vault_hit := false
	for k in _chunks_in(lo, hi, false):
		var o := chunk_of_key(k) * CHUNK
		var blocks: PackedByteArray = _cb[k]
		var dens: PackedByteArray = _cd[k]
		_cb[k] = _empty
		_cd[k] = _empty
		var changed := false
		var opened := false
		for z in range(maxi(lo.z, o.z), mini(hi.z, o.z + 15) + 1):
			for x in range(maxi(lo.x, o.x), mini(hi.x, o.x + 15) + 1):
				var y0 := maxi(lo.y, o.y)
				var i := _at(x, y0, z)
				for y in range(y0, mini(hi.y, o.y + 15) + 1):
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
									opened = true
									worn[b] = int(worn.get(b, 0)) + 1
									if Blocks.is_ore(b):
										ore[b] = int(ore.get(b, 0)) + 1
								changed = true
						elif dist < radius and tiers[b] >= 0 and tiers[b] <= tier and not Blocks.is_treasure(b):
							blocks[i] = Blocks.AIR
							dens[i] = 0
							_wear.erase(key(x, y, z))
							removed += 1
							opened = true
							vault_hit = vault_hit or Blocks.is_vault(b)
							changed = true
					i += 1
		_cb[k] = blocks
		_cd[k] = dens
		if changed:
			_edited(k, opened)
	if removed > 0:
		_touch(lo, hi, true)
	return {"removed": removed, "block": _most(worn), "vault": vault_hit, "ore": ore}


# The pickaxe's flattening blow: makes the ground you're looking at flat over a disc as wide as
# the pickaxe's dent. The plane runs through `point` (metres), square to `axis` and lined up
# with the nearest cell boundary, with open air on its `side` (+1 or -1). Within `radius` cells
# of the point along the plane, ground standing up to `cut` cells proud of it is cut away (as far
# as `tier` allows), and holes up to `fill_depth` cells deep are filled with `fill_block`.
# Nothing is filled inside keep_lo..keep_hi (metres): that's you. Treasure stays put. Returns
# how many cells were cut away and filled in, whether a hidden room's wall came down, whether
# anything changed, and the ore that was cut (block -> cells).
func flatten(point: Vector3, axis: int, side: int, radius: float, cut: int, fill_depth: int, tier: int, fill_block: int, keep_lo: Vector3, keep_hi: Vector3) -> Dictionary:
	var p := point / VOXEL
	var plane := roundi(p[axis])
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var cu := floori(p[u])
	var cv := floori(p[v])
	var half := ceili(radius)
	var r2 := radius * radius
	var keep_c0 := Vector3i((keep_lo / VOXEL).floor())
	var keep_c1 := Vector3i((keep_hi / VOXEL - Vector3(0.0001, 0.0001, 0.0001)).floor())
	var lo := Vector3i.ZERO
	var hi := Vector3i.ZERO
	lo[u] = cu - half
	hi[u] = cu + half - 1
	lo[v] = cv - half
	hi[v] = cv + half - 1
	lo[axis] = plane - (fill_depth if side > 0 else cut)
	hi[axis] = plane + (cut if side > 0 else fill_depth) - 1
	lo.y = maxi(lo.y, BOTTOM_Y)
	hi.y = mini(hi.y, TOP_Y - 1)
	var ore := {}
	var removed := 0
	var placed := 0
	var any := false
	var vault_hit := false
	for k in _chunks_in(lo, hi, false):
		var o := chunk_of_key(k) * CHUNK
		var blocks: PackedByteArray = _cb[k]
		var dens: PackedByteArray = _cd[k]
		_cb[k] = _empty
		_cd[k] = _empty
		var changed := false
		var opened := false
		for z in range(maxi(lo.z, o.z), mini(hi.z, o.z + 15) + 1):
			for x in range(maxi(lo.x, o.x), mini(hi.x, o.x + 15) + 1):
				for y in range(maxi(lo.y, o.y), mini(hi.y, o.y + 15) + 1):
					var c := Vector3i(x, y, z)
					var du := c[u] - cu
					var dv := c[v] - cv
					if (du + 0.5) * (du + 0.5) + (dv + 0.5) * (dv + 0.5) > r2:
						continue
					# k counts cells out from the plane into the open air: 0 is the first one in front.
					var kk: int = c[axis] - plane if side > 0 else plane - 1 - c[axis]
					var i := _at(x, y, z)
					var b := blocks[i]
					var d := dens[i]
					var want := int(clampf(127.5 - (kk + 0.5) * 127.5, 0.0, float(GROUND)))
					if kk >= 0:
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
									opened = true
									if Blocks.is_ore(b):
										ore[b] = int(ore.get(b, 0)) + 1
								changed = true
						elif Blocks.diggable(b, tier):
							blocks[i] = Blocks.AIR
							dens[i] = want
							_wear.erase(key(x, y, z))
							removed += 1
							opened = true
							vault_hit = vault_hit or Blocks.is_vault(b)
							changed = true
					elif b == Blocks.AIR:
						# Behind it: fill it in.
						if d >= want or not can_fill(c):
							continue
						if x >= keep_c0.x and x <= keep_c1.x and y >= keep_c0.y and y <= keep_c1.y and z >= keep_c0.z and z <= keep_c1.z:
							continue
						dens[i] = want
						if want >= SOLID:
							blocks[i] = fill_block
							placed += 1
						changed = true
					elif b <= Blocks.BEDROCK and d < want:
						dens[i] = want
						changed = true
		_cb[k] = blocks
		_cd[k] = dens
		if changed:
			any = true
			_edited(k, opened)
	if any:
		_touch(lo, hi, removed > 0)
	return {"removed": removed, "placed": placed, "vault": vault_hit, "changed": any, "ore": ore}


# Takes a treasure out of the ground: it's been found.
func collect(id: String) -> void:
	var t: Dictionary = treasures.get(id, {})
	if t.is_empty():
		return
	found_ids[id] = true
	treasures.erase(id)
	var lo: Vector3i = t["lo"]
	var hi: Vector3i = t["hi"]
	for k in _chunks_in(lo, hi, false):
		var o := chunk_of_key(k) * CHUNK
		var blocks: PackedByteArray = _cb[k]
		var dens: PackedByteArray = _cd[k]
		_cb[k] = _empty
		_cd[k] = _empty
		for z in range(maxi(lo.z, o.z), mini(hi.z, o.z + 15) + 1):
			for x in range(maxi(lo.x, o.x), mini(hi.x, o.x + 15) + 1):
				for y in range(maxi(lo.y, o.y), mini(hi.y, o.y + 15) + 1):
					var i := _at(x, y, z)
					if Blocks.is_treasure(blocks[i]):
						blocks[i] = Blocks.AIR
						dens[i] = 0
		_cb[k] = blocks
		_cd[k] = dens
		_edited(k, true)
	_touch(lo, hi, true)


# A chunk you've changed: saved from now on.
func _edited(k: int, opened: bool) -> void:
	var f: int = int(_flags[k]) | EDITED
	if opened:
		f |= HAS_AIR
	_flags[k] = f
	_stale[k] = true


func _mark_edited(lo: Vector3i, hi: Vector3i) -> void:
	for k in _chunks_in(lo, hi, false):
		_edited(k, false)


func edited_chunk_count() -> int:
	return _blobs.size() + _stale.size()


# --- Making and letting go of chunks --------------------------------------------------------------

# A fresh world for a seed. Call load_edits next if there's a save, then build the house.
func begin(new_seed: int, tier: int, found: Dictionary) -> void:
	for k: int in _meshes:
		(_meshes[k] as Node).queue_free()
	world_seed = new_seed
	house_tier = tier
	gen = Gen.new(new_seed)
	found_ids = found.duplicate()
	_cb.clear()
	_cd.clear()
	_flags.clear()
	_blobs.clear()
	_stale.clear()
	_meshes.clear()
	_bricks.clear()
	_drawn.clear()
	_dirty.clear()
	_wear.clear()
	rooms.clear()
	_pending.clear()
	treasures.clear()
	furniture.clear()
	lit_rooms.clear()
	_center = Vector3i(1 << 28, 0, 0)
	_gen_list.clear()
	_mesh_list.clear()


func _make(k: int) -> void:
	var c := chunk_of_key(k)
	var features: Array
	var blob: PackedByteArray = _blobs.get(k, _empty)
	var flags := 0
	if not blob.is_empty() and not pinning:
		var raw := blob.decompress(CELLS * 2 + 1, FileAccess.COMPRESSION_ZSTD)
		if raw.size() == CELLS * 2 + 1:
			_cb[k] = raw.slice(0, CELLS)
			_cd[k] = raw.slice(CELLS, CELLS * 2)
			flags = (raw[CELLS * 2] & (HAS_AIR | HAS_BUILT)) | EDITED
			features = gen.features_for_chunk(c.x, c.y, c.z, found_ids)
	if not _cb.has(k):
		var data := gen.chunk(c.x, c.y, c.z, found_ids)
		_cb[k] = data[0]
		_cd[k] = data[1]
		flags = (HAS_AIR if data[2] else 0) | (HAS_BUILT if data[3] else 0)
		features = [data[4], data[5]]
	if pinning:
		flags |= PINNED
	_flags[k] = flags
	for room: Dictionary in features[0]:
		if not rooms.has(room["id"]):
			_pending[room["id"]] = room
	for t: Dictionary in features[1]:
		if not found_ids.has(t["id"]):
			treasures[t["id"]] = t


# Rooms come into the world once all of them is there, so their guards have a floor to stand on.
func _settle_rooms() -> void:
	for id: String in _pending.keys():
		var room: Dictionary = _pending[id]
		var whole := true
		var lo: Vector3i = room["shell_lo"]
		var hi: Vector3i = room["shell_hi"]
		for cz in range(lo.z >> 4, (hi.z >> 4) + 1):
			for cx in range(lo.x >> 4, (hi.x >> 4) + 1):
				for cy in range(lo.y >> 4, (hi.y >> 4) + 1):
					if not _cb.has(ckey(cx, cy, cz)):
						whole = false
		if whole:
			_pending.erase(id)
			_register_room(room)


func _register_room(room: Dictionary) -> void:
	var id: String = room["id"]
	if rooms.has(id):
		return
	gen.canvas(room)
	rooms[id] = room
	if room["type"] in ["trial", "checkpoint"]:
		lit_rooms[id] = true
	if on_room_loaded.is_valid():
		on_room_loaded.call(room)


# The saved copy of the chunks you changed in your house, laid over the house as it's just been
# built (so your digging in the dig site by the stairs comes back too).
func restore_house_edits() -> void:
	for k: int in _flags.keys():
		if int(_flags[k]) & PINNED and _blobs.has(k):
			var raw: PackedByteArray = (_blobs[k] as PackedByteArray).decompress(CELLS * 2 + 1, FileAccess.COMPRESSION_ZSTD)
			if raw.size() == CELLS * 2 + 1:
				_cb[k] = raw.slice(0, CELLS)
				_cd[k] = raw.slice(CELLS, CELLS * 2)
				_flags[k] = (raw[CELLS * 2] & (HAS_AIR | HAS_BUILT)) | EDITED | PINNED


func _unload(k: int) -> void:
	var f: int = _flags.get(k, 0)
	if f & PINNED:
		return
	_free_mesh(k)
	if f & EDITED and _stale.has(k):
		_blobs[k] = _pack(k)
		_stale.erase(k)
	_cb.erase(k)
	_cd.erase(k)
	_flags.erase(k)


func _free_mesh(k: int) -> void:
	var mi: MeshInstance3D = _meshes.get(k)
	if mi:
		mi.queue_free()
		_meshes.erase(k)
	for n in 8:
		_bricks.erase(k * 8 + n)
	_drawn.erase(k)
	_dirty.erase(k)


func _pack(k: int) -> PackedByteArray:
	var raw: PackedByteArray = (_cb[k] as PackedByteArray) + (_cd[k] as PackedByteArray)
	raw.append(int(_flags[k]) & (HAS_AIR | HAS_BUILT))
	return raw.compress(FileAccess.COMPRESSION_ZSTD)


# Works out which chunks to make and draw now that you're in a new one, and lets go of those far
# behind you, and of the rooms and treasure with them.
func _plan() -> void:
	var c := _center
	_gen_list.clear()
	_gen_at = 0
	for o in _gen_offsets:
		var cy := c.y + o.y
		if cy < BOTTOM_CY or cy >= TOP_CY:
			continue
		var k := ckey(c.x + o.x, cy, c.z + o.z)
		if not _cb.has(k):
			_gen_list.append(k)
	_mesh_list.clear()
	_mesh_at = 0
	for o in _view_offsets:
		var cy := c.y + o.y
		if cy >= BOTTOM_CY and cy < TOP_CY:
			_mesh_list.append(ckey(c.x + o.x, cy, c.z + o.z))
	var far := []
	for k: int in _cb:
		var p := chunk_of_key(k) - c
		if p.x * p.x + p.z * p.z > KEEP * KEEP or absi(p.y) > KEEP_Y:
			far.append(k)
	for k: int in far:
		_unload(k)
	var reach := Vector3(KEEP + 1.0, KEEP_Y + 1.0, KEEP + 1.0) * (CHUNK * VOXEL)
	var here := (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * (CHUNK * VOXEL)
	for id: String in rooms.keys():
		var room: Dictionary = rooms[id]
		var d: Vector3 = (room["center"] - here).abs()
		if d.x > reach.x + 8.0 or d.y > reach.y + 6.0 or d.z > reach.z + 8.0:
			rooms.erase(id)
			if room["type"] in ["trial", "checkpoint"]:
				lit_rooms.erase(id)
			if on_room_unloaded.is_valid():
				on_room_unloaded.call(room)
	for id: String in _pending.keys():
		var d: Vector3 = (_pending[id]["center"] - here).abs()
		if d.x > reach.x + 8.0 or d.y > reach.y + 6.0 or d.z > reach.z + 8.0:
			_pending.erase(id)
	for id: String in treasures.keys():
		var d: Vector3 = (treasures[id]["center"] - here).abs()
		if d.x > reach.x or d.y > reach.y or d.z > reach.z:
			treasures.erase(id)


# Whether a chunk should be drawn now: 0 no (or it already is), 1 yes, 2 not until its
# neighbours are made.
func _draw_state(k: int) -> int:
	if _drawn.has(k):
		return 0
	if not _cb.has(k):
		return 2
	var c := chunk_of_key(k)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var cy := c.y + dy
				if cy >= BOTTOM_CY and cy < TOP_CY and not _cb.has(ckey(c.x + dx, cy, c.z + dz)):
					return 2
	for o: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if int(_flags.get(ckey(c.x + o.x, c.y + o.y, c.z + o.z), 0)) & HAS_AIR:
			return 1
	return 0


func _process(_delta: float) -> void:
	if gen == null:
		return
	var start := Time.get_ticks_usec()
	var here := Vector3i(floori(focus.x / VOXEL) >> 4, floori(focus.y / VOXEL) >> 4, floori(focus.z / VOXEL) >> 4)
	if here != _center:
		_center = here
		_plan()
	# Whatever you're standing in has to be there, however fast you got there.
	for dy in range(-1, 2):
		var k := ckey(here.x, here.y + dy, here.z)
		if not _cb.has(k) and here.y + dy >= BOTTOM_CY and here.y + dy < TOP_CY:
			_make(k)
	if not _dirty.is_empty():
		# Changed bricks first, nearest first. A small change is finished in one go, so it never
		# shows half done; a big one carries on next frame.
		var keys: Array = _dirty.keys()
		var f := focus / (CHUNK * VOXEL) - Vector3(0.5, 0.5, 0.5)
		keys.sort_custom(func(a: int, b: int) -> bool: return Vector3(chunk_of_key(a)).distance_squared_to(f) < Vector3(chunk_of_key(b)).distance_squared_to(f))
		for k: int in keys:
			var mask: int = _dirty[k]
			_dirty.erase(k)
			if _cb.has(k):
				_build(k, mask)
			if keys.size() > 6 and Time.get_ticks_usec() - start > 8000:
				break
	var budget := 40000 if loading else 7000
	while _gen_at < _gen_list.size() and Time.get_ticks_usec() - start < budget * 0.6:
		var k := _gen_list[_gen_at]
		_gen_at += 1
		if not _cb.has(k):
			_make(k)
	if not _pending.is_empty():
		_settle_rooms()
	var first_wait := -1
	var i := _mesh_at
	while i < _mesh_list.size() and Time.get_ticks_usec() - start < budget:
		var k := _mesh_list[i]
		match _draw_state(k):
			1:
				_build(k, 255)
			2:
				if first_wait < 0:
					first_wait = i
		i += 1
	_mesh_at = first_wait if first_wait >= 0 else i


# How much of the world around you is made and drawn, 0 to 1.
func build_progress() -> float:
	var total := _gen_list.size() + _mesh_list.size()
	if total == 0:
		return 1.0
	var done := _gen_at + _mesh_at
	if _gen_at >= _gen_list.size() and _mesh_at >= _mesh_list.size():
		return 1.0
	return clampf(float(done) / total, 0.0, 0.999)


# Starts making the world around a point straight away, as if you'd just walked there.
func look_around(p: Vector3) -> void:
	focus = p
	_center = Vector3i(floori(p.x / VOXEL) >> 4, floori(p.y / VOXEL) >> 4, floori(p.z / VOXEL) >> 4)
	_plan()


func ready_around() -> bool:
	return _gen_at >= _gen_list.size() and _mesh_at >= _mesh_list.size()


func mesh_count() -> int:
	return _meshes.size()


func chunk_count() -> int:
	return _cb.size()


func pending_chunks() -> int:
	return _dirty.size() + (_gen_list.size() - _gen_at) + (_mesh_list.size() - _mesh_at)


# --- Drawing --------------------------------------------------------------------------------------

# Marks the bricks around a changed box for drawing again.
func _touch(lo: Vector3i, hi: Vector3i, _made_air: bool) -> void:
	var c0 := lo - Vector3i.ONE
	var c1 := hi + Vector3i.ONE
	for bz in range(c0.z >> 3, (c1.z >> 3) + 1):
		for bx in range(c0.x >> 3, (c1.x >> 3) + 1):
			for by in range(c0.y >> 3, (c1.y >> 3) + 1):
				var k := ckey(bx >> 1, by >> 1, bz >> 1)
				if _cb.has(k):
					_dirty[k] = int(_dirty.get(k, 0)) | (1 << ((bx & 1) | ((by & 1) << 1) | ((bz & 1) << 2)))


# A chunk with a one-cell border from its neighbours, blocks then densities, for the mesher.
func _padded(k: int) -> Array:
	var c := chunk_of_key(k)
	var bs := []
	var ds := []
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n := ckey(c.x + dx, c.y + dy, c.z + dz)
				bs.append(_cb.get(n, _solid))
				ds.append(_cd.get(n, _thick))
	var pb := PackedByteArray()
	var pd := PackedByteArray()
	for pz in PAD:
		var lz := pz - 1
		var nz := 0 if lz < 0 else (2 if lz > 15 else 1)
		for px in PAD:
			var lx := px - 1
			var nx := 0 if lx < 0 else (2 if lx > 15 else 1)
			var col := ((lx & 15) << 4) | ((lz & 15) << 8)
			var n := nx + nz * 3
			var below: PackedByteArray = bs[n]
			var mid: PackedByteArray = bs[n + 9]
			var above: PackedByteArray = bs[n + 18]
			pb.append(below[col | 15])
			pb.append_array(mid.slice(col, col + 16))
			pb.append(above[col])
			below = ds[n]
			mid = ds[n + 9]
			above = ds[n + 18]
			pd.append(below[col | 15])
			pd.append_array(mid.slice(col, col + 16))
			pd.append(above[col])
	return [pb, pd]


# Works out the bricks in `mask` again and puts the chunk's mesh back together.
func _build(k: int, mask: int) -> void:
	var pad := _padded(k)
	var origin := chunk_of_key(k) * CHUNK
	var has_built := (int(_flags.get(k, 0)) & HAS_BUILT) != 0
	for n in 8:
		if mask & (1 << n):
			var data: Array = Mesher.build(pad[0], pad[1], PAD, PAD * PAD, (n & 1) * BRICK, ((n >> 1) & 1) * BRICK, (n >> 2) * BRICK, has_built, VOXEL, origin)
			if data.is_empty():
				_bricks.erase(k * 8 + n)
			else:
				_bricks[k * 8 + n] = data
	_drawn[k] = true
	_assemble(k)


# Puts a chunk's mesh together from its eight bricks.
func _assemble(k: int) -> void:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var infos := PackedVector2Array()
	for n in 8:
		var data: Array = _bricks.get(k * 8 + n, [])
		if not data.is_empty():
			verts.append_array(data[0])
			normals.append_array(data[1])
			colors.append_array(data[2])
			infos.append_array(data[3])
	var mi: MeshInstance3D = _meshes.get(k)
	if verts.is_empty():
		if mi:
			mi.queue_free()
			_meshes.erase(k)
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
		mi.position = Vector3(chunk_of_key(k) * CHUNK) * VOXEL
		add_child(mi)
		_meshes[k] = mi
	mi.mesh = mesh


# --- Lights --------------------------------------------------------------------------------------

func set_lights(list: Array) -> void:
	lights = list


# A short burst of light: explosions, lightning.
func flash(pos: Vector3, color: Color, light_range: float, life: float) -> void:
	_flashes.append({"pos": pos, "color": color, "range": light_range, "time": life, "life": life})


# Sends the shader the lights nearest to `eye`: your house's, those of the rooms around you that
# burn, and any flashes.
func update_lights(time: float, delta: float, eye: Vector3) -> void:
	var on: Array = lights.duplicate()
	for id: String in lit_rooms:
		if rooms.has(id):
			on.append_array(rooms[id].get("lights", []))
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
		col.append(Vector4(c.r, c.g, c.b, -100000.0))
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
		col.append(Vector4(c.r * f, c.g * f, c.b * f, l.get("min_y", -100000.0)))
	while pos.size() < MAX_LIGHTS:
		pos.append(Vector4.ZERO)
		col.append(Vector4.ZERO)
	material.set_shader_parameter("light_pos", pos)
	material.set_shader_parameter("light_col", col)


# --- Saving ----------------------------------------------------------------------------------------

# Writes every chunk you've changed to the world file next to the save.
func save_edits(path: String) -> void:
	for k: int in _stale.keys():
		if _cb.has(k):
			_blobs[k] = _pack(k)
	_stale.clear()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer("DFW1".to_ascii_buffer())
	f.store_64(world_seed)
	f.store_32(_blobs.size())
	for k: int in _blobs:
		var blob: PackedByteArray = _blobs[k]
		f.store_64(k)
		f.store_32(blob.size())
		f.store_buffer(blob)


# Reads back the chunks you changed, if the world file belongs to this world.
func load_edits(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 16 or f.get_buffer(4).get_string_from_ascii() != "DFW1":
		return
	if f.get_64() != world_seed:
		return
	var n := f.get_32()
	for i in n:
		if f.get_position() + 12 > f.get_length():
			break
		var k := f.get_64()
		var size := f.get_32()
		if size <= 0 or f.get_position() + size > f.get_length():
			break
		_blobs[k] = f.get_buffer(size)
