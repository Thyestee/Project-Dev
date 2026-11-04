extends RefCounted
# How the ground is made, a chunk (16 cells a side) at a time and the same every time for the same
# seed: bands of rock that wander up and down, pockets of softer ground, veins of ore and gems,
# winding caves and now and then a great cavern, buried treasure, and the hidden rooms (see Rooms).
# Small things are worked out a region (8 m a side) at a time and caves 32 m at a time, so that
# whatever crosses a chunk's edge carries on into the next. Coordinates are cells.

const Blocks := preload("res://scripts/blocks.gd")
const Goods := preload("res://scripts/goods.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Rooms := preload("res://scripts/rooms.gd")
const House := preload("res://scripts/house.gd")

const VOXEL := 0.125
const FLOOR_Y := 344
const BOTTOM_Y := FLOOR_Y - 80000
const CHUNK := 16
const CELLS := 4096
const GROUND := 254
const SMALL := 64               # cells on a side of the regions ore, pockets and treasure go in
const SMALL_SHIFT := 6
const CAVE_SHIFT := 8           # caves are worked out 256 cells (32 m) at a time
const CAVE_REACH := 2           # how many cave regions away a cave can wander
const VEINS := 62
const TREASURE_CHANCE := 0.035  # per small region, below the first 18 m
const LUMP_REACH := 8           # how far a lump of ore can stand out of its region
const POCKET_REACH := 18

# Every band boundary, top down: the block below it, how deep it lies (metres) and how far it
# wanders up and down. Above the first is dirt; above the floor of your house, bedrock.
const LAYERS := [
	[Blocks.CLAY, 8.5, 1.2],
	[Blocks.DIRT, 11.0, 1.2],
	[Blocks.STONE, 13.0, 1.5],
	[Blocks.SLATE, 40.0, 3.0],
	[Blocks.DEEPROCK, 110.0, 5.0],
	[Blocks.BASALT, 280.0, 8.0],
	[Blocks.OBSIDIAN, 700.0, 12.0],
	[Blocks.MAGMAROCK, 1800.0, 20.0],
	[Blocks.VOIDSTONE, 4500.0, 30.0],
	[Blocks.BEDROCK, 9998.0, 1.0],
]
# The block of each layer, from the top one (between the floor and the first boundary) down.
const LAYER_BLOCK := [Blocks.DIRT, Blocks.CLAY, Blocks.DIRT, Blocks.STONE, Blocks.SLATE, Blocks.DEEPROCK, Blocks.BASALT,
	Blocks.OBSIDIAN, Blocks.MAGMAROCK, Blocks.VOIDSTONE, Blocks.BEDROCK]
const NB := 11                  # the floor plus the ten boundaries

var world_seed := 0
var _noises: Array[FastNoiseLite] = []
var _columns := {}              # chunk column -> [tops per column (PackedInt32Array), lowest and highest of each]
var _small := {}                # small region -> {"lumps", "pockets", "treasures"}
var _cave_done := {}            # cave region -> true once its caves are in _caves
var _caves := {}                # chunk key -> PackedFloat32Array of hollows: centre and radii, in cells
var _cave_checked := Vector3i(1 << 30, 0, 0)
var _room_layouts := {}         # room region -> its room, or {}
var _check_layouts := {}        # checkpoint region -> its checkpoint, or {}
var _canvases := {}             # room id -> its blocks (see Rooms.Canvas)
var _canvas_order: Array[String] = []
var _runs := []                 # block -> {length: PackedByteArray of that block}


func _init(new_seed: int) -> void:
	world_seed = new_seed
	var freq := [0.02, 0.03, 0.015, 0.012, 0.01, 0.008, 0.006, 0.005, 0.004, 0.05]
	for k in LAYERS.size():
		var n := FastNoiseLite.new()
		n.seed = new_seed + 11 + k
		n.frequency = freq[k]
		n.fractal_octaves = 3 if k >= 2 else 2
		_noises.append(n)
	for b in Blocks.DEFS.size():
		_runs.append({})


static func ckey(cx: int, cy: int, cz: int) -> int:
	return ((cx + 2097152) << 36) | ((cz + 2097152) << 14) | (cy + 8192)


func _rng(a: int, b: int, c: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, a, b, c, salt])
	return rng


# The usual rock at a depth in metres, ignoring how the bands wander.
static func nominal_rock(depth: float) -> int:
	if depth < 0.0:
		return Blocks.BEDROCK
	var b := Blocks.DIRT
	for layer: Array in LAYERS:
		if depth >= float(layer[1]):
			b = layer[0]
	return b


static func in_house_area(lo: Vector3i, hi: Vector3i) -> bool:
	return hi.x >= House.EXCLUDE_LO.x and lo.x <= House.EXCLUDE_HI.x and hi.y >= House.EXCLUDE_LO.y and lo.y <= House.EXCLUDE_HI.y \
		and hi.z >= House.EXCLUDE_LO.z and lo.z <= House.EXCLUDE_HI.z


# --- A chunk ----------------------------------------------------------------------------------

# The chunk at chunk coordinates (cx, cy, cz): [blocks, densities, has air, has built blocks,
# the rooms it touches, the treasure it holds]. Cells run y fastest, then x, then z.
func chunk(cx: int, cy: int, cz: int, found: Dictionary) -> Array:
	var ox := cx * CHUNK
	var oy := cy * CHUNK
	var oz := cz * CHUNK
	var b := _base(cx, cy, cz)
	var d := PackedByteArray()
	d.resize(CELLS)
	d.fill(GROUND)
	var natural := oy < FLOOR_Y and oy + CHUNK > BOTTOM_Y
	var built := false
	if natural:
		_pockets(b, ox, oy, oz)
		_ores(b, ox, oy, oz)
		_carve_caves(b, d, cx, cy, cz)
	var rooms := rooms_for_chunk(cx, cy, cz)
	for room: Dictionary in rooms:
		_stamp_room(b, d, ox, oy, oz, room)
		built = true
	var treasures := treasures_for_chunk(cx, cy, cz, found)
	for t: Dictionary in treasures:
		_stamp_treasure(b, d, ox, oy, oz, t)
		built = true
	return [b, d, b.count(Blocks.AIR) > 0, built, rooms, treasures]


# Rooms and treasure a chunk touches, without making the chunk (for one you changed, read back
# from the save).
func features_for_chunk(cx: int, cy: int, cz: int, found: Dictionary) -> Array:
	return [rooms_for_chunk(cx, cy, cz), treasures_for_chunk(cx, cy, cz, found)]


# --- Bands of rock -----------------------------------------------------------------------------

# Where every boundary lies under each of the chunk column's 16 x 16 columns, worked out once for
# the whole height of the world: tops[column * NB + j] is the lowest cell of layer j - 1, so
# layer j runs from tops[j + 1] up to tops[j].
func _column_data(cx: int, cz: int) -> Array:
	var k := ckey(cx, 0, cz)
	if _columns.has(k):
		return _columns[k]
	if _columns.size() > 3000:
		_columns.clear()
	var tops := PackedInt32Array()
	tops.resize(256 * NB)
	var lo := PackedInt32Array()
	var hi := PackedInt32Array()
	lo.resize(NB)
	hi.resize(NB)
	lo.fill(1 << 30)
	hi.fill(-(1 << 30))
	for lz in CHUNK:
		for lx in CHUNK:
			var x := cx * CHUNK + lx
			var z := cz * CHUNK + lz
			var col := (lx + lz * CHUNK) * NB
			var above := FLOOR_Y
			tops[col] = FLOOR_Y
			for j in LAYERS.size():
				var layer: Array = LAYERS[j]
				var depth: float = float(layer[1]) + float(layer[2]) * _noises[j].get_noise_2d(x * 0.5, z * 0.5)
				var y := mini(FLOOR_Y - int(depth / VOXEL), above)
				above = y
				tops[col + j + 1] = y
	for c in 256:
		for j in NB:
			var y := tops[c * NB + j]
			lo[j] = mini(lo[j], y)
			hi[j] = maxi(hi[j], y)
	var data := [tops, lo, hi]
	_columns[k] = data
	return data


func _base(cx: int, cy: int, cz: int) -> PackedByteArray:
	var b := PackedByteArray()
	var ya := cy * CHUNK
	var yb := ya + CHUNK
	if ya >= FLOOR_Y or yb <= BOTTOM_Y:
		b.resize(CELLS)
		b.fill(Blocks.BEDROCK)
		return b
	var data := _column_data(cx, cz)
	var tops: PackedInt32Array = data[0]
	var lo: PackedInt32Array = data[1]
	var hi: PackedInt32Array = data[2]
	var crossing := false
	for j in NB:
		if hi[j] > ya and lo[j] < yb:
			crossing = true
			break
	if not crossing:
		# All of it in one layer.
		var j := NB - 1
		while j > 0 and ya >= tops[j]:
			j -= 1
		if ya >= tops[0]:
			b.resize(CELLS)
			b.fill(Blocks.BEDROCK)
			return b
		b.resize(CELLS)
		b.fill(LAYER_BLOCK[j] if ya < tops[j] else Blocks.BEDROCK)
		return b
	for lz in CHUNK:
		for lx in CHUNK:
			var col := (lx + lz * CHUNK) * NB
			var y := ya
			# The layer the bottom cell is in: the deepest boundary above it.
			var j := NB - 1
			while j >= 0 and not (y < tops[col + j]):
				j -= 1
			while y < yb:
				if j < 0:
					_run(b, Blocks.BEDROCK, yb - y)
					break
				var top := mini(tops[col + j], yb)
				_run(b, LAYER_BLOCK[j], top - y)
				y = top
				j -= 1
	return b


# Adds `length` cells of block b to the end of `to`.
func _run(to: PackedByteArray, b: int, length: int) -> void:
	if length <= 0:
		return
	var cache: Dictionary = _runs[b]
	if not cache.has(length):
		var run := PackedByteArray()
		run.resize(length)
		run.fill(b)
		cache[length] = run
	to.append_array(cache[length])


# The rock you'd usually find at cell height y.
func rock_at(x: int, y: int, z: int) -> int:
	if y >= FLOOR_Y or y < BOTTOM_Y:
		return Blocks.BEDROCK
	var data := _column_data(x >> 4, z >> 4)
	var tops: PackedInt32Array = data[0]
	var col := ((x & 15) + (z & 15) * CHUNK) * NB
	var j := NB - 1
	while j >= 0 and not (y < tops[col + j]):
		j -= 1
	return LAYER_BLOCK[j] if j >= 0 else Blocks.BEDROCK


# --- Small things: pockets, ore, treasure -------------------------------------------------------

func _small_region(rx: int, ry: int, rz: int) -> Dictionary:
	var k := ckey(rx, ry, rz)
	if _small.has(k):
		return _small[k]
	if _small.size() > 6000:
		_small.clear()
	var region := {"lumps": PackedFloat32Array(), "pockets": PackedFloat32Array(), "treasures": []}
	_small[k] = region
	var x0 := rx * SMALL
	var y0 := ry * SMALL
	var z0 := rz * SMALL
	if y0 >= FLOOR_Y or y0 + SMALL <= BOTTOM_Y:
		return region
	var rng := _rng(rx, ry, rz, 1)
	# Depths this region spans, in metres.
	var d_top := maxf(0.0, (FLOOR_Y - (y0 + SMALL)) * VOXEL)
	var d_bot := (FLOOR_Y - y0) * VOXEL
	# Pockets of softer ground: about one a region.
	var pockets: PackedFloat32Array = region["pockets"]
	for n in (1 if rng.randf() < 0.5 else 0) + (1 if rng.randf() < 0.5 else 0):
		var c := Vector3(rng.randf_range(x0, x0 + SMALL), rng.randf_range(y0, y0 + SMALL), rng.randf_range(z0, z0 + SMALL))
		var depth := (FLOOR_Y - c.y) * VOXEL
		var host := nominal_rock(depth)
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
			Blocks.BASALT:
				kind = Blocks.DEEPROCK
			Blocks.OBSIDIAN:
				kind = Blocks.BASALT
			Blocks.MAGMAROCK:
				kind = Blocks.OBSIDIAN
			Blocks.VOIDSTONE:
				kind = Blocks.MAGMAROCK
		if kind != Blocks.AIR and depth > 0.5:
			var r := Vector3(rng.randf_range(0.75, 2.0), rng.randf_range(0.5, 1.25), rng.randf_range(0.75, 2.0)) / VOXEL
			pockets.append_array([c.x, c.y, c.z, r.x, r.y, r.z, host, kind])
	# Veins of ore, the better ones deeper down. Each is a short row of lumps.
	var lumps: PackedFloat32Array = region["lumps"]
	var veins: Array = Goods.VEINS
	for n in VEINS:
		var depth := rng.randf_range(d_top, d_bot)
		var total := 0.0
		for v: Dictionary in veins:
			if depth >= float(v["depth"][0]) and depth <= float(v["depth"][1]):
				total += float(v["weight"])
		if total <= 0.0:
			continue
		var roll := rng.randf() * total
		var vein: Dictionary = {}
		for v: Dictionary in veins:
			if depth >= float(v["depth"][0]) and depth <= float(v["depth"][1]):
				roll -= float(v["weight"])
				if roll < 0.0:
					vein = v
					break
		if vein.is_empty():
			continue
		var kind: int = Goods.LIST[vein["good"]]["block"]
		var p := Vector3(rng.randf_range(x0, x0 + SMALL), FLOOR_Y - depth / VOXEL, rng.randf_range(z0, z0 + SMALL))
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.4, 0.4), rng.randf_range(-1.0, 1.0)).normalized()
		for k2 in rng.randi_range(int(vein["lumps"][0]), int(vein["lumps"][1])):
			var r := rng.randf_range(float(vein["size"][0]), float(vein["size"][1])) * 0.5 / VOXEL
			lumps.append_array([p.x, p.y, p.z, r * rng.randf_range(0.8, 1.2), r * rng.randf_range(0.55, 0.85), r * rng.randf_range(0.8, 1.2), kind])
			p += dir * r * 1.3
	# Now and then, a lost treasure, well clear of the region's edges.
	var mid_depth := (d_top + d_bot) * 0.5
	if mid_depth >= 18.0 and rng.randf() < TREASURE_CHANCE:
		var t := Treasures.pick(rng, mid_depth)
		if t >= 0:
			var chest: bool = Treasures.LIST[t]["chest"]
			var size := Vector3i(8, 6, 6) if chest else Vector3i(4, 4, 4)
			if rng.randf() < 0.5:
				size = Vector3i(size.z, size.y, size.x)
			var lo := Vector3i(rng.randi_range(x0 + 4, x0 + SMALL - 4 - size.x), rng.randi_range(y0 + 4, mini(y0 + SMALL, FLOOR_Y - 150) - 4 - size.y), rng.randi_range(z0 + 4, z0 + SMALL - 4 - size.z))
			var hi := lo + size - Vector3i.ONE
			if lo.y > y0 and not in_house_area(lo - Vector3i(8, 8, 8), hi + Vector3i(8, 8, 8)) and not _touches_room(lo, hi):
				var depth := (FLOOR_Y - lo.y) * VOXEL
				region["treasures"].append({"id": "t%d_%d_%d" % [rx, ry, rz], "type": t, "lo": lo, "hi": hi, "chest": chest, "depth": depth,
					"center": (Vector3(lo) + Vector3(size) * 0.5) * VOXEL})
	return region


func _touches_room(lo: Vector3i, hi: Vector3i) -> bool:
	return not rooms_in_box(lo - Vector3i(4, 4, 4), hi + Vector3i(4, 4, 4)).is_empty()


# Small regions whose things can reach into the box lo..hi (cells).
func _small_regions_near(lo: Vector3i, hi: Vector3i, reach: int) -> Array:
	var out := []
	for rz in range((lo.z - reach) >> SMALL_SHIFT, ((hi.z + reach) >> SMALL_SHIFT) + 1):
		for rx in range((lo.x - reach) >> SMALL_SHIFT, ((hi.x + reach) >> SMALL_SHIFT) + 1):
			for ry in range((lo.y - reach) >> SMALL_SHIFT, ((hi.y + reach) >> SMALL_SHIFT) + 1):
				out.append(_small_region(rx, ry, rz))
	return out


# Ellipsoids of host rock turned into something softer.
func _pockets(b: PackedByteArray, ox: int, oy: int, oz: int) -> void:
	var lo := Vector3i(ox, oy, oz)
	var hi := lo + Vector3i(15, 15, 15)
	for region: Dictionary in _small_regions_near(lo, hi, POCKET_REACH):
		var p: PackedFloat32Array = region["pockets"]
		var n := 0
		while n < p.size():
			var cx := p[n]
			var cy := p[n + 1]
			var cz := p[n + 2]
			var rx := p[n + 3]
			var ry := p[n + 4]
			var rz := p[n + 5]
			var host := int(p[n + 6])
			var kind := int(p[n + 7])
			n += 8
			if cx + rx < ox or cx - rx > ox + 16 or cz + rz < oz or cz - rz > oz + 16 or cy + ry < oy or cy - ry > oy + 16:
				continue
			for z in range(maxi(ceili(cz - rz), oz), mini(floori(cz + rz), oz + 15) + 1):
				var dz := (z - cz) / rz
				for x in range(maxi(ceili(cx - rx), ox), mini(floori(cx + rx), ox + 15) + 1):
					var dx := (x - cx) / rx
					var q := 1.0 - dx * dx - dz * dz
					if q < 0.0:
						continue
					var hy := ry * sqrt(q)
					var y0 := maxi(floori(cy - hy), oy)
					var y1 := mini(floori(cy + hy), oy + 15)
					var i := (y0 - oy) | ((x - ox) << 4) | ((z - oz) << 8)
					for y in range(y0, y1 + 1):
						if b[i] == host:
							b[i] = kind
						i += 1


# Lumps of ore and gems: each turns the ground inside it into ore (bedrock stays).
func _ores(b: PackedByteArray, ox: int, oy: int, oz: int) -> void:
	var lo := Vector3i(ox, oy, oz)
	var hi := lo + Vector3i(15, 15, 15)
	var fx := float(ox)
	var fy := float(oy)
	var fz := float(oz)
	for region: Dictionary in _small_regions_near(lo, hi, LUMP_REACH):
		var p: PackedFloat32Array = region["lumps"]
		var n := 0
		var size := p.size()
		while n < size:
			var cx := p[n]
			var cy := p[n + 1]
			var cz := p[n + 2]
			var rx := p[n + 3]
			var ry := p[n + 4]
			var rz := p[n + 5]
			if cx + rx < fx or cx - rx > fx + 16.0 or cz + rz < fz or cz - rz > fz + 16.0 or cy + ry < fy or cy - ry > fy + 16.0:
				n += 7
				continue
			var kind := int(p[n + 6])
			n += 7
			var z0 := maxi(ceili(cz - rz - 0.5), oz)
			var z1 := mini(floori(cz + rz - 0.5), oz + 15)
			for z in range(z0, z1 + 1):
				var dz := (z + 0.5 - cz) / rz
				var qz := 1.0 - dz * dz
				if qz <= 0.0:
					continue
				var hx := rx * sqrt(qz)
				var x0 := maxi(ceili(cx - hx - 0.5), ox)
				var x1 := mini(floori(cx + hx - 0.5), ox + 15)
				for x in range(x0, x1 + 1):
					var dx := (x + 0.5 - cx) / rx
					var q := qz - dx * dx
					if q <= 0.0:
						continue
					var hy := ry * sqrt(q)
					var y0 := maxi(ceili(cy - hy - 0.5), oy)
					var y1 := mini(floori(cy + hy - 0.5), oy + 15)
					var i := (y0 - oy) | ((x - ox) << 4) | ((z - oz) << 8)
					for y in range(y0, y1 + 1):
						if b[i] < Blocks.BEDROCK:
							b[i] = kind
						i += 1


# Treasure in the small regions that can reach this chunk, not yet found, that it overlaps.
func treasures_for_chunk(cx: int, cy: int, cz: int, found: Dictionary) -> Array:
	var lo := Vector3i(cx, cy, cz) * CHUNK
	var hi := lo + Vector3i(15, 15, 15)
	var out := []
	for region: Dictionary in _small_regions_near(lo, hi, 8):
		for t: Dictionary in region["treasures"]:
			var tlo: Vector3i = t["lo"]
			var thi: Vector3i = t["hi"]
			if not found.has(t["id"]) and thi.x >= lo.x and tlo.x <= hi.x and thi.y >= lo.y and tlo.y <= hi.y and thi.z >= lo.z and tlo.z <= hi.z:
				out.append(t)
	return out


# Relics are half-metre cubes of glinting soil; rarer treasure comes in buried chests with a gold
# band.
func _stamp_treasure(b: PackedByteArray, d: PackedByteArray, ox: int, oy: int, oz: int, t: Dictionary) -> void:
	var lo: Vector3i = t["lo"]
	var hi: Vector3i = t["hi"]
	var chest: bool = t["chest"]
	for z in range(maxi(lo.z, oz), mini(hi.z, oz + 15) + 1):
		for x in range(maxi(lo.x, ox), mini(hi.x, ox + 15) + 1):
			for y in range(maxi(lo.y, oy), mini(hi.y, oy + 15) + 1):
				var block := Blocks.RELIC
				if chest:
					var edge := (x == lo.x or x == hi.x) and (z == lo.z or z == hi.z)
					block = Blocks.CHEST_TRIM if y == lo.y + 3 or edge else Blocks.CHEST
				var i := (y - oy) | ((x - ox) << 4) | ((z - oz) << 8)
				b[i] = block
				d[i] = 255


# --- Caves ---------------------------------------------------------------------------------------

func _carve_caves(b: PackedByteArray, d: PackedByteArray, cx: int, cy: int, cz: int) -> void:
	_ensure_caves(Vector3i(cx >> 4, cy >> 4, cz >> 4))
	var list: PackedFloat32Array = _caves.get(ckey(cx, cy, cz), PackedFloat32Array())
	var n := 0
	while n < list.size():
		_hollow(b, d, cx * CHUNK, cy * CHUNK, cz * CHUNK, Vector3(list[n], list[n + 1], list[n + 2]), Vector3(list[n + 3], list[n + 4], list[n + 5]))
		n += 6


# Works out the caves of every cave region close enough to reach this one.
func _ensure_caves(r: Vector3i) -> void:
	if r == _cave_checked:
		return
	_cave_checked = r
	# Far behind you, they're forgotten: worked out again if you ever go back.
	if _cave_done.size() > 1500:
		_cave_done.clear()
		_caves.clear()
	for dz in range(-CAVE_REACH, CAVE_REACH + 1):
		for dx in range(-CAVE_REACH, CAVE_REACH + 1):
			for dy in range(-CAVE_REACH, CAVE_REACH + 1):
				var k := ckey(r.x + dx, r.y + dy, r.z + dz)
				if not _cave_done.has(k):
					_cave_done[k] = true
					_make_caves(r.x + dx, r.y + dy, r.z + dz)


# A cave region's worms: tunnels that wander a few dozen metres, more or less level, now and then
# opening into a great cavern. Each step of a worm is a hollow, noted down in every chunk it
# reaches.
func _make_caves(rx: int, ry: int, rz: int) -> void:
	var size := 1 << CAVE_SHIFT
	var x0 := rx * size
	var y0 := ry * size
	var z0 := rz * size
	if y0 >= FLOOR_Y - 64 or y0 + size <= BOTTOM_Y + 64:
		return
	var rng := _rng(rx, ry, rz, 3)
	var home := Vector3(x0 + size * 0.5, y0 + size * 0.5, z0 + size * 0.5)
	var worms := (1 if rng.randf() < 0.9 else 0) + (1 if rng.randf() < 0.55 else 0) + (1 if rng.randf() < 0.2 else 0)
	for w in worms:
		var p := Vector3(rng.randf_range(x0, x0 + size), rng.randf_range(y0, y0 + size), rng.randf_range(z0, z0 + size))
		p.y = minf(p.y, FLOOR_Y - 96.0)
		var depth := (FLOOR_Y - p.y) * VOXEL
		var wide := 1.0 + 0.08 * minf(float(Blocks.band(depth)), 5.0)
		var yaw := rng.randf() * TAU
		var pitch := 0.0
		if rng.randf() < 0.2:
			var big := rng.randf_range(3.0, 6.5) * wide / VOXEL
			_add_hollow(p, Vector3(big, big * rng.randf_range(0.45, 0.7), big * rng.randf_range(0.8, 1.2)))
		for s in rng.randi_range(40, 100):
			var radius := clampf(1.1 + 0.4 * sin(s * 0.25 + w) + rng.randf_range(-0.12, 0.12), 0.75, 1.6) * wide / VOXEL
			_add_hollow(p, Vector3(radius, radius * 0.8, radius))
			p += Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * (0.75 / VOXEL)
			yaw += rng.randf_range(-0.35, 0.35)
			pitch = clampf(pitch + rng.randf_range(-0.15, 0.15), -0.45, 0.45) * 0.9
			var off := (p - home).abs()
			if maxf(off.x, maxf(off.y, off.z)) > size * (CAVE_REACH + 0.5) - 64.0:
				break
			if p.y > FLOOR_Y - 64.0 or p.y < BOTTOM_Y + 80.0:
				break


func _add_hollow(c: Vector3, r: Vector3) -> void:
	var smallest := minf(r.x, minf(r.y, r.z))
	var outer := 1.0 + 1.5 / smallest
	var lo := Vector3i((c - r * outer).floor())
	var hi := Vector3i((c + r * outer).ceil())
	if in_house_area(lo - Vector3i(24, 24, 24), hi + Vector3i(24, 24, 24)):
		return
	for cz in range(lo.z >> 4, (hi.z >> 4) + 1):
		for cx in range(lo.x >> 4, (hi.x >> 4) + 1):
			for cy in range(lo.y >> 4, (hi.y >> 4) + 1):
				var k := ckey(cx, cy, cz)
				var list: PackedFloat32Array = _caves.get(k, PackedFloat32Array())
				list.append_array([c.x, c.y, c.z, r.x, r.y, r.z])
				_caves[k] = list


# Opens up an ellipsoid of ground around c with radii r (cells), its surface smooth, as far as it
# reaches into this chunk.
func _hollow(b: PackedByteArray, d: PackedByteArray, ox: int, oy: int, oz: int, c: Vector3, r: Vector3) -> void:
	var smallest := minf(r.x, minf(r.y, r.z))
	var outer := 1.0 + 1.5 / smallest
	var x0 := maxi(floori(c.x - r.x * outer), ox)
	var x1 := mini(ceili(c.x + r.x * outer), ox + 15)
	var z0 := maxi(floori(c.z - r.z * outer), oz)
	var z1 := mini(ceili(c.z + r.z * outer), oz + 15)
	for z in range(z0, z1 + 1):
		var dz := (z + 0.5 - c.z) / r.z
		for x in range(x0, x1 + 1):
			var dx := (x + 0.5 - c.x) / r.x
			var q := dx * dx + dz * dz
			if q >= outer * outer:
				continue
			var hy := sqrt(outer * outer - q) * r.y
			var y0 := maxi(floori(c.y - hy), oy)
			var y1 := mini(ceili(c.y + hy), oy + 15)
			var i := (y0 - oy) | ((x - ox) << 4) | ((z - oz) << 8)
			for y in range(y0, y1 + 1):
				var dy := (y + 0.5 - c.y) / r.y
				# Roughly how many cells outside the ellipsoid the cell's centre is.
				var out := (sqrt(q + dy * dy) - 1.0) * smallest
				var want := int(clampf(127.5 + out * 127.5, 0.0, float(GROUND)))
				if want < d[i] and b[i] < Blocks.BEDROCK:
					d[i] = want
					if want < 128:
						b[i] = Blocks.AIR
				i += 1


# --- Hidden rooms ----------------------------------------------------------------------------------

# The room of a room region, or {} (see Rooms.layout).
func room_layout(r: Vector3i) -> Dictionary:
	var k := ckey(r.x, r.y, r.z)
	if not _room_layouts.has(k):
		if _room_layouts.size() > 20000:
			_room_layouts.clear()
		_room_layouts[k] = Rooms.layout(world_seed, r)
	return _room_layouts[k]


# Rooms whose shell comes into the box lo..hi (cells), checkpoints included.
func rooms_in_box(lo: Vector3i, hi: Vector3i) -> Array:
	var out := _regular_rooms_in_box(lo, hi)
	var clo := Rooms.checkpoint_region_of(lo)
	var chi := Rooms.checkpoint_region_of(hi)
	for rz in range(clo.z, chi.z + 1):
		for rx in range(clo.x, chi.x + 1):
			for ry in range(clo.y, chi.y + 1):
				var room := checkpoint_layout(Vector3i(rx, ry, rz))
				if room.is_empty():
					continue
				var slo: Vector3i = room["shell_lo"]
				var shi: Vector3i = room["shell_hi"]
				if shi.x >= lo.x and slo.x <= hi.x and shi.y >= lo.y and slo.y <= hi.y and shi.z >= lo.z and slo.z <= hi.z:
					out.append(room)
	return out


# The checkpoint of a checkpoint region, or {}: somewhere in it clear of the other rooms.
func checkpoint_layout(r: Vector3i) -> Dictionary:
	var k := ckey(r.x, r.y, r.z)
	if _check_layouts.has(k):
		return _check_layouts[k]
	if _check_layouts.size() > 20000:
		_check_layouts.clear()
	var room := {}
	if Rooms.has_checkpoint(world_seed, r):
		for attempt in 8:
			var spot := Rooms.checkpoint_candidate(world_seed, r, attempt)
			if not spot.is_empty() and _regular_rooms_in_box(spot["shell_lo"] - Vector3i(6, 6, 6), spot["shell_hi"] + Vector3i(6, 6, 6)).is_empty():
				room = spot
				break
	_check_layouts[k] = room
	return room


func _regular_rooms_in_box(lo: Vector3i, hi: Vector3i) -> Array:
	var out := []
	var rlo := Rooms.region_of(lo)
	var rhi := Rooms.region_of(hi)
	for rz in range(rlo.z, rhi.z + 1):
		for rx in range(rlo.x, rhi.x + 1):
			for ry in range(rlo.y, rhi.y + 1):
				var room := room_layout(Vector3i(rx, ry, rz))
				if room.is_empty():
					continue
				var slo: Vector3i = room["shell_lo"]
				var shi: Vector3i = room["shell_hi"]
				if shi.x >= lo.x and slo.x <= hi.x and shi.y >= lo.y and slo.y <= hi.y and shi.z >= lo.z and slo.z <= hi.z:
					out.append(room)
	return out


func rooms_for_chunk(cx: int, cy: int, cz: int) -> Array:
	var lo := Vector3i(cx, cy, cz) * CHUNK
	return rooms_in_box(lo, lo + Vector3i(15, 15, 15))


# The room's blocks, built once and kept for a while.
func canvas(room: Dictionary) -> Rooms.Canvas:
	var id: String = room["id"]
	if _canvases.has(id) and room.has("chests"):
		return _canvases[id]
	var c := Rooms.build(room)
	_canvases[id] = c
	_canvas_order.append(id)
	while _canvas_order.size() > 40:
		_canvases.erase(_canvas_order.pop_front())
	return c


func _stamp_room(b: PackedByteArray, d: PackedByteArray, ox: int, oy: int, oz: int, room: Dictionary) -> void:
	var c := canvas(room)
	var data := c.data
	var lo := c.origin
	var w := c.size.x
	var h := c.size.y
	var x0 := maxi(lo.x, ox)
	var x1 := mini(lo.x + c.size.x - 1, ox + 15)
	var y0 := maxi(lo.y, oy)
	var y1 := mini(lo.y + c.size.y - 1, oy + 15)
	var z0 := maxi(lo.z, oz)
	var z1 := mini(lo.z + c.size.z - 1, oz + 15)
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			var row := (y - lo.y + (z - lo.z) * h) * w - lo.x
			for x in range(x0, x1 + 1):
				var v := data[row + x]
				if v == Rooms.UNTOUCHED:
					continue
				var i := (y - oy) | ((x - ox) << 4) | ((z - oz) << 8)
				b[i] = v
				d[i] = 0 if v == Blocks.AIR else 255
