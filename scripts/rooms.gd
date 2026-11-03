extends RefCounted
# Hidden rooms, sealed in the ground everywhere below the first few metres, about one every 16 m:
# guard rooms full of guards who wake when you break in, treasure rooms with up to five chests and
# the traps that keep them, and trials: jump courses behind walls nothing digs through, with a
# single way in. The deeper a room, the bigger and meaner it is and the better its loot.
# Everything here is worked out from the world's seed, so a room is the same whenever its part of
# the world is made again. Coordinates are cells.

const Blocks := preload("res://scripts/blocks.gd")
const House := preload("res://scripts/house.gd")

const VOXEL := 0.125
const FLOOR := 344
const BOTTOM := FLOOR - 80000
const REGION := Vector3i(128, 80, 128)    # every region this size holds at most one room
const MARGIN := 5                          # cells between a room and its region's edge
const MIN_DEPTH := 14.0
const CHANCE := 0.7
const UNTOUCHED := 255
const PORCH := 8                           # how far the alcove in front of a trial's door reaches out
const TORCH_COLOR := Color(1.0, 0.6, 0.28)
const TRIAL_COLOR := Color(0.45, 0.8, 1.0)
const TYPE_NAMES := {"fight": "Guard room", "treasure": "Treasure room", "trial": "Trial"}

# How fast you run and jump (see Player): a trial's gaps are never wider than you can clear.
const RUN := 6.4
const JUMP := 7.6
const GRAVITY := 24.0


# A room's blocks over the box it takes up, x fastest, then y, then z, with UNTOUCHED wherever
# the ground is left as it is. Built on an Image, whose rectangle fills are quick.
class Canvas:
	extends RefCounted
	var origin := Vector3i.ZERO
	var size := Vector3i.ZERO
	var data := PackedByteArray()
	var _img: Image

	func _init(lo: Vector3i, hi: Vector3i) -> void:
		origin = lo
		size = hi - lo + Vector3i.ONE
		_img = Image.create_empty(size.x, size.y * size.z, false, Image.FORMAT_R8)
		_img.fill(Color(1.0, 0.0, 0.0))

	static func _color(b: int) -> Color:
		return Color((b + 0.5) / 255.0, 0.0, 0.0)

	func fill(lo: Vector3i, hi: Vector3i, b: int) -> void:
		var a := (lo - origin).max(Vector3i.ZERO)
		var e := (hi - origin).min(size - Vector3i.ONE)
		if a.x > e.x or a.y > e.y or a.z > e.z:
			return
		var c := _color(b)
		for z in range(a.z, e.z + 1):
			_img.fill_rect(Rect2i(a.x, a.y + z * size.y, e.x - a.x + 1, e.y - a.y + 1), c)

	func put(x: int, y: int, z: int, b: int) -> void:
		var p := Vector3i(x, y, z) - origin
		if p.x >= 0 and p.y >= 0 and p.z >= 0 and p.x < size.x and p.y < size.y and p.z < size.z:
			_img.set_pixel(p.x, p.y + p.z * size.y, _color(b))

	func block(x: int, y: int, z: int) -> int:
		var p := Vector3i(x, y, z) - origin
		if p.x < 0 or p.y < 0 or p.z < 0 or p.x >= size.x or p.y >= size.y or p.z >= size.z:
			return UNTOUCHED
		return int(_img.get_pixel(p.x, p.y + p.z * size.y).r * 255.0 + 0.5)

	func finish() -> void:
		data = _img.get_data()
		_img = null


static func region_of(c: Vector3i) -> Vector3i:
	return Vector3i(floori(c.x / float(REGION.x)), floori(c.y / float(REGION.y)), floori(c.z / float(REGION.z)))


static func _rng(world_seed: int, r: Vector3i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, r.x, r.y, r.z, salt])
	return rng


# --- Where the rooms are ------------------------------------------------------------------------

# The room in a region, or {}: its kind, where its inside (lo..hi) and its walls (shell_lo..
# shell_hi) are, and how deep. Cheap: the blocks come later (see build).
static func layout(world_seed: int, r: Vector3i) -> Dictionary:
	var rlo := r * REGION
	var rhi := rlo + REGION - Vector3i.ONE
	if rlo.y > FLOOR - int(MIN_DEPTH / VOXEL) - 40 or rlo.y < BOTTOM + 120:
		return {}
	if rhi.x >= House.EXCLUDE_LO.x - 16 and rlo.x <= House.EXCLUDE_HI.x + 16 and rhi.y >= House.EXCLUDE_LO.y - 16 \
			and rhi.z >= House.EXCLUDE_LO.z - 16 and rlo.z <= House.EXCLUDE_HI.z + 16:
		return {}
	var rng := _rng(world_seed, r, 7)
	if rng.randf() >= CHANCE:
		return {}
	var depth := (FLOOR - (rlo.y + REGION.y / 2)) * VOXEL
	var level := Blocks.level(depth)
	var roll := rng.randf()
	var trials := 0.0 if depth < 22.0 else 0.22
	var type := "trial" if roll < trials else ("treasure" if roll < trials + 0.38 else "fight")
	var size := Vector3i.ZERO
	var shell := 2
	var axis := 0
	var flip := false
	match type:
		"fight":
			var grow := int(level * 3.0)
			size = Vector3i(mini(rng.randi_range(44, 52) + grow, 84), mini(rng.randi_range(26, 30) + int(level), 40), mini(rng.randi_range(40, 52) + grow, 84))
		"treasure":
			var grow := int(level * 2.0)
			size = Vector3i(mini(rng.randi_range(32, 44) + grow, 60), rng.randi_range(24, 28), mini(rng.randi_range(32, 44) + grow, 60))
		"trial":
			shell = 3
			axis = 0 if rng.randf() < 0.5 else 2
			flip = rng.randf() < 0.5
			var along := rng.randi_range(92, 100)
			var across := rng.randi_range(40, 48)
			size = Vector3i(along, 60, across) if axis == 0 else Vector3i(across, 60, along)
	# Room enough in the region for its walls (and a trial's porch) and a gap to the next.
	var reach := Vector3i(shell, shell, shell)
	var porch := Vector3i.ZERO
	if type == "trial":
		porch[axis] = PORCH
	var space := REGION - size - reach * 2 - porch - Vector3i(MARGIN, MARGIN, MARGIN) * 2
	if space.x < 0 or space.y < 0 or space.z < 0:
		return {}
	var lo := rlo + Vector3i(MARGIN, MARGIN, MARGIN) + reach + Vector3i(rng.randi_range(0, space.x), rng.randi_range(0, space.y), rng.randi_range(0, space.z))
	if type == "trial" and not flip:
		lo[axis] += PORCH
	var hi := lo + size - Vector3i.ONE
	var shell_lo := lo - reach
	var shell_hi := hi + reach
	if type == "trial":
		if flip:
			shell_hi[axis] += PORCH
		else:
			shell_lo[axis] -= PORCH
	if shell_hi.y > FLOOR - int(MIN_DEPTH / VOXEL):
		return {}
	return {"id": "r%d_%d_%d" % [r.x, r.y, r.z], "type": type, "name": TYPE_NAMES[type], "lo": lo, "hi": hi, "shell_lo": shell_lo, "shell_hi": shell_hi,
		"depth": (FLOOR - lo.y) * VOXEL, "level": Blocks.level((FLOOR - lo.y) * VOXEL), "seed": hash([world_seed, r.x, r.y, r.z, 8]),
		"axis": axis, "flip": flip, "center": (Vector3(lo) + Vector3(size) * 0.5) * VOXEL}


# --- Building one -------------------------------------------------------------------------------

# The room's blocks, and everything about it that isn't blocks: its chests, guards, lights and
# traps, and for a trial its door and course.
static func build(room: Dictionary) -> Canvas:
	var c := Canvas.new(room["shell_lo"], room["shell_hi"])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room["seed"])
	room["chests"] = []
	room["spawns"] = []
	room["lights"] = []
	room["plates"] = []
	match room["type"]:
		"fight":
			_build_fight(c, room, rng)
		"treasure":
			_build_treasure(c, room, rng)
		"trial":
			_build_trial(c, room, rng)
	c.finish()
	return c


# Old brick, two cubes thick, with moss here and there, a chequered floor of big tiles, cobwebs in
# the top corners and torches on the walls.
static func _masonry(c: Canvas, room: Dictionary, rng: RandomNumberGenerator) -> void:
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	var size := hi - lo + Vector3i.ONE
	c.fill(lo - Vector3i(2, 2, 2), hi + Vector3i(2, 2, 2), Blocks.VAULT_BRICK)
	c.fill(lo, hi, Blocks.AIR)
	for n in size.x * size.z / 40:
		var c0 := Vector3i(rng.randi_range(lo.x, hi.x), rng.randi_range(lo.y, hi.y), rng.randi_range(lo.z, hi.z))
		match rng.randi_range(0, 4):
			0:
				c0.x = lo.x - 1
			1:
				c0.x = hi.x + 1
			2:
				c0.z = lo.z - 1
			3:
				c0.z = hi.z + 1
			4:
				c0.y = hi.y + 1
		for o: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(1, 1, 0), Vector3i(0, 1, 1)]:
			var p := c0 + o
			if c.block(p.x, p.y, p.z) == Blocks.VAULT_BRICK and rng.randf() < 0.7:
				c.put(p.x, p.y, p.z, Blocks.VAULT_MOSS)
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var tile := ((x - lo.x) / 4 + (z - lo.z) / 4) % 2 == 0
			c.put(x, lo.y - 1, z, Blocks.VAULT_TILE if tile else Blocks.VAULT_FLOOR)
	for corner: Vector2i in [Vector2i(lo.x, lo.z), Vector2i(hi.x, lo.z), Vector2i(lo.x, hi.z), Vector2i(hi.x, hi.z)]:
		for dz in 5:
			for dx in 5:
				for dy in 5:
					if dx + dy + dz < 6 and rng.randf() < 0.55:
						var p := Vector3i(corner.x + (dx if corner.x == lo.x else -dx), hi.y - dy, corner.y + (dz if corner.y == lo.z else -dz))
						if c.block(p.x, p.y, p.z) == Blocks.AIR:
							c.put(p.x, p.y, p.z, Blocks.WEB)


static func _torch(c: Canvas, room: Dictionary, p: Vector3i) -> void:
	c.fill(p, p + Vector3i(0, 1, 0), Blocks.TORCH)
	c.put(p.x, p.y - 1, p.z, Blocks.IRON)
	var lo: Vector3i = room["lo"]
	room["lights"].append({"pos": (Vector3(p) + Vector3(0.5, 1.0, 0.5)) * VOXEL, "color": TORCH_COLOR * 0.85, "range": 6.5,
		"min_y": (lo.y - 1) * VOXEL, "flicker": true, "room": room["id"]})


# Pillars along two walls with torches between them, and a torch in the middle of the others.
static func _pillars(c: Canvas, room: Dictionary) -> void:
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	var columns: Array[int] = []
	var x := lo.x
	while x + 3 <= hi.x + 1:
		columns.append(x)
		x += 16
	if columns[-1] != hi.x - 2:
		columns.append(hi.x - 2)
	for px in columns:
		for pz: int in [lo.z, hi.z - 2]:
			c.fill(Vector3i(px, lo.y, pz), Vector3i(px + 2, hi.y, pz + 2), Blocks.VAULT_PILLAR)
	for k in range(columns.size() - 1):
		var tx := (columns[k] + columns[k + 1] + 2) / 2
		for z: int in [lo.z, hi.z]:
			_torch(c, room, Vector3i(tx, lo.y + 14, z))
	for tx: int in [lo.x, hi.x]:
		_torch(c, room, Vector3i(tx, lo.y + 14, (lo.z + hi.z) / 2))


# An old chest 8 cubes wide (6 deep), its lock on the side facing the room, whose trim glows in
# the colour of what's inside. `side` is the wall it stands against: 0 north (low z), 1 south,
# 2 west (low x), 3 east.
static func _loot_chest(c: Canvas, room: Dictionary, lo: Vector3i, side: int, rarity: int, extra := {}) -> void:
	var turned := side >= 2
	var hi := lo + (Vector3i(5, 5, 7) if turned else Vector3i(7, 5, 5))
	var trim := Blocks.LOOT_TRIM + rarity - 1
	c.fill(lo, hi, Blocks.LOOT_CHEST)
	c.fill(Vector3i(lo.x, lo.y + 3, lo.z), Vector3i(hi.x, lo.y + 3, hi.z), trim)
	for x: int in [lo.x, hi.x]:
		for z: int in [lo.z, hi.z]:
			c.fill(Vector3i(x, lo.y, z), Vector3i(x, hi.y, z), trim)
	match side:
		0:
			c.fill(Vector3i(lo.x + 3, lo.y + 2, hi.z), Vector3i(lo.x + 4, lo.y + 3, hi.z), Blocks.LOOT_LOCK)
		1:
			c.fill(Vector3i(lo.x + 3, lo.y + 2, lo.z), Vector3i(lo.x + 4, lo.y + 3, lo.z), Blocks.LOOT_LOCK)
		2:
			c.fill(Vector3i(hi.x, lo.y + 2, lo.z + 3), Vector3i(hi.x, lo.y + 3, lo.z + 4), Blocks.LOOT_LOCK)
		3:
			c.fill(Vector3i(lo.x, lo.y + 2, lo.z + 3), Vector3i(lo.x, lo.y + 3, lo.z + 4), Blocks.LOOT_LOCK)
	var chest := {"lo": lo, "hi": hi, "rarity": rarity}
	chest.merge(extra)
	room["chests"].append(chest)


# How rare a chest's loot is at this depth: deeper rooms (and harder ones) hold better things.
static func chest_rarity(level: float, bonus: float, rng: RandomNumberGenerator) -> int:
	var l := level + bonus
	var weights := [maxf(70.0 - 9.0 * l, 5.0), 27.0 + 3.0 * l, 3.0 + 4.5 * l, maxf(0.0, 1.5 * l - 1.0)]
	var total := 0.0
	for w: float in weights:
		total += w
	var roll := rng.randf() * total
	for k in weights.size():
		roll -= weights[k]
		if roll < 0.0:
			return k + 1
	return 1


# A guard room: an old hall with pillars, bones and urns, its chest sealed until every guard in it
# is down.
static func _build_fight(c: Canvas, room: Dictionary, rng: RandomNumberGenerator) -> void:
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	var size := hi - lo + Vector3i.ONE
	var level: float = room["level"]
	_masonry(c, room, rng)
	_pillars(c, room)
	for n in 6:
		var p := Vector3i(rng.randi_range(lo.x + 4, hi.x - 4), lo.y, rng.randi_range(lo.z + 4, hi.z - 4))
		for k in rng.randi_range(2, 5):
			var q := p + Vector3i(rng.randi_range(-2, 2), 0, rng.randi_range(-2, 2))
			if c.block(q.x, q.y, q.z) == Blocks.AIR:
				c.put(q.x, q.y, q.z, Blocks.BONE)
	for n in 4:
		var along := rng.randi_range(lo.x + 4, hi.x - 6)
		var uz := lo.z + 3 if rng.randf() < 0.5 else hi.z - 4
		if c.block(along, lo.y, uz) == Blocks.AIR and c.block(along + 1, lo.y, uz + 1) == Blocks.AIR:
			c.fill(Vector3i(along, lo.y, uz), Vector3i(along + 1, lo.y + 2, uz + 1), Blocks.URN)
	for bx: int in [lo.x + size.x / 4 - 2, hi.x - size.x / 4 - 1]:
		c.fill(Vector3i(bx, hi.y - 12, hi.z), Vector3i(bx + 3, hi.y - 2, hi.z), Blocks.BANNER)
		c.fill(Vector3i(bx, hi.y - 13, hi.z), Vector3i(bx + 3, hi.y - 13, hi.z), Blocks.GOLD)
	var cx := (lo.x + hi.x + 1) / 2
	var boss := level >= 3.0 and size.x >= 56 and rng.randf() < 0.14
	if boss:
		c.fill(Vector3i(cx - 6, lo.y, hi.z - 9), Vector3i(cx + 5, lo.y + 5, hi.z - 2), Blocks.VAULT_PILLAR)
		c.fill(Vector3i(cx - 6, lo.y + 6, hi.z - 3), Vector3i(cx + 5, lo.y + 20, hi.z - 2), Blocks.VAULT_PILLAR)
		c.fill(Vector3i(cx - 4, lo.y + 6, hi.z - 8), Vector3i(cx + 3, lo.y + 6, hi.z - 4), Blocks.BANNER)
		c.fill(Vector3i(cx - 4, lo.y + 7, hi.z - 4), Vector3i(cx + 3, lo.y + 18, hi.z - 4), Blocks.BANNER)
		c.fill(Vector3i(cx - 6, lo.y + 21, hi.z - 3), Vector3i(cx + 5, lo.y + 21, hi.z - 2), Blocks.GOLD)
	room["boss"] = boss
	var chest_x := [cx - 4]
	if boss or (size.x >= 60 and rng.randf() < 0.5):
		chest_x = [cx - 20, cx + 12]
	for x: int in chest_x:
		_loot_chest(c, room, Vector3i(x, lo.y, hi.z - 5 - (4 if boss else 0)), 1, chest_rarity(level, 0.75 + (0.75 if boss else 0.0), rng), {"sealed": true})
	# The guards, spread over the floor away from the walls: more of them, and tougher kinds, the
	# deeper the room.
	var count := clampi(5 + int(level * 0.9) + rng.randi_range(0, 3), 5, 12)
	var kinds := {"skeleton": 40.0, "archer": 25.0, "spider": 25.0, "golem": 10.0 if level >= 1.8 else 0.0}
	if boss:
		room["spawns"].append({"type": "warden", "pos": Vector3(cx, lo.y, hi.z - 18) * VOXEL})
		count -= 2
	for k in count:
		var type := _pick(kinds, rng)
		var p := Vector3(rng.randf_range(lo.x + 8, hi.x - 8), lo.y, rng.randf_range(lo.z + 8, hi.z - 12))
		room["spawns"].append({"type": type, "pos": p * VOXEL})


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k: String in weights:
		roll -= float(weights[k])
		if roll < 0.0:
			return k
	return weights.keys()[0]


# A treasure room: one to five chests round the walls, and the floor in front of them laid with
# pressure plates. Some fire spikes up through the floor; some set off darts from slits in the
# wall; and now and then a chest itself is trapped.
static func _build_treasure(c: Canvas, room: Dictionary, rng: RandomNumberGenerator) -> void:
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	var level: float = room["level"]
	_masonry(c, room, rng)
	for corner: Vector2i in [Vector2i(lo.x, lo.z), Vector2i(hi.x - 2, lo.z), Vector2i(lo.x, hi.z - 2), Vector2i(hi.x - 2, hi.z - 2)]:
		c.fill(Vector3i(corner.x, lo.y, corner.y), Vector3i(corner.x + 2, hi.y, corner.y + 2), Blocks.VAULT_PILLAR)
	var mx := (lo.x + hi.x) / 2
	var mz := (lo.z + hi.z) / 2
	for p: Vector3i in [Vector3i(mx, lo.y + 12, lo.z), Vector3i(mx, lo.y + 12, hi.z), Vector3i(lo.x, lo.y + 12, mz), Vector3i(hi.x, lo.y + 12, mz)]:
		_torch(c, room, p)
	# Chests: the back wall first, then the sides, then the front.
	var n := clampi(1 + int(rng.randf() * (2.0 + level * 0.6)), 1, 5)
	var spots: Array = [
		[Vector3i(mx - 4, lo.y, hi.z - 5), 1], [Vector3i(lo.x, lo.y, mz - 4), 2], [Vector3i(hi.x - 5, lo.y, mz - 4), 3],
		[Vector3i(mx - 4, lo.y, lo.z), 0], [Vector3i(hi.x - 12, lo.y, hi.z - 5), 1],
	]
	var trap_chance := 0.2 + 0.03 * level
	var plates: Array = room["plates"]
	for k in n:
		var spot: Array = spots[k]
		var p: Vector3i = spot[0]
		var side: int = spot[1]
		_loot_chest(c, room, p, side, chest_rarity(level, 0.0, rng), {"trapped": rng.randf() < trap_chance})
		# A plate right in front of it.
		var front := p
		match side:
			0:
				front = Vector3i(p.x + 1, lo.y - 1, p.z + 7)
			1:
				front = Vector3i(p.x + 1, lo.y - 1, p.z - 7)
			2:
				front = Vector3i(p.x + 7, lo.y - 1, p.z + 1)
			3:
				front = Vector3i(p.x - 7, lo.y - 1, p.z + 1)
		plates.append(_plate(c, room, front, "spikes" if rng.randf() < 0.6 else "darts", rng))
	# More plates scattered over the floor, more of them deeper down.
	for k in clampi(1 + int(level * 0.7), 1, 6):
		var p := Vector3i(rng.randi_range(lo.x + 5, hi.x - 11), lo.y - 1, rng.randi_range(lo.z + 5, hi.z - 11))
		if c.block(p.x, lo.y, p.z) == Blocks.AIR and c.block(p.x + 5, lo.y, p.z + 5) == Blocks.AIR:
			plates.append(_plate(c, room, p, "spikes" if rng.randf() < 0.55 else "darts", rng))


# A 6 by 6 pressure plate with its corner at p (in the floor). Darts come from a slit in the wall
# nearest to it, at knee height, aimed across the plate.
static func _plate(c: Canvas, room: Dictionary, p: Vector3i, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	var plo := p
	var phi := p + Vector3i(5, 0, 5)
	c.fill(plo, phi, Blocks.TRAP_PLATE)
	var plate := {"lo": plo, "hi": phi, "kind": kind}
	if kind == "darts":
		var mid := Vector3(plo.x + 3.0, 0.0, plo.z + 3.0)
		var walls := [mid.x - lo.x, hi.x - mid.x, mid.z - lo.z, hi.z - mid.z]
		var best := 0
		for k in 4:
			if walls[k] < walls[best]:
				best = k
		var slits: Array = []
		var dir := Vector3.ZERO
		for h: int in [5, 9]:
			var s := Vector3i.ZERO
			match best:
				0:
					s = Vector3i(lo.x - 1, lo.y + h, plo.z + 2 + (h % 2))
					dir = Vector3.RIGHT
				1:
					s = Vector3i(hi.x + 1, lo.y + h, plo.z + 2 + (h % 2))
					dir = Vector3.LEFT
				2:
					s = Vector3i(plo.x + 2 + (h % 2), lo.y + h, lo.z - 1)
					dir = Vector3.BACK
				3:
					s = Vector3i(plo.x + 2 + (h % 2), lo.y + h, hi.z + 1)
					dir = Vector3.FORWARD
			c.put(s.x, s.y, s.z, Blocks.DART_SLIT)
			slits.append((Vector3(s) + Vector3(0.5, 0.5, 0.5) + dir * 0.7) * VOXEL)
		plate["slits"] = slits
		plate["dir"] = dir
	return plate


# --- Trials ---------------------------------------------------------------------------------------

# A trial is built in its own frame: u along it from the door, v across it, y up from its floor.
static func _cell(room: Dictionary, u: int, y: int, v: int) -> Vector3i:
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	var axis: int = room["axis"]
	var along := (hi - lo)[axis]
	var uu := along - u if room["flip"] else u
	if axis == 0:
		return Vector3i(lo.x + uu, lo.y + y, lo.z + v)
	return Vector3i(lo.x + v, lo.y + y, lo.z + uu)


static func _tfill(c: Canvas, room: Dictionary, u0: int, y0: int, v0: int, u1: int, y1: int, v1: int, b: int) -> void:
	var a := _cell(room, u0, y0, v0)
	var e := _cell(room, u1, y1, v1)
	c.fill(a.min(e), a.max(e), b)


# How far you clear, running and jumping, to land `rise` metres higher (or lower): the time until
# you come down to that height, times your running speed.
static func reach(rise: float) -> float:
	var under := JUMP * JUMP - 2.0 * GRAVITY * rise
	if under < 0.0:
		return 0.0
	return RUN * (JUMP + sqrt(under)) / GRAVITY


# Walls, floor and ceiling of trial stone, three cubes thick, that nothing digs or blasts. You
# come in through the one door onto a ledge, and the reward waits on a ledge at the far end. In
# between: pillars to jump along, smaller, further apart and more up and down the deeper the
# trial. Fall, and stairs in the corner take you back up to the start.
static func _build_trial(c: Canvas, room: Dictionary, rng: RandomNumberGenerator) -> void:
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	var axis: int = room["axis"]
	var along := (hi - lo)[axis] + 1
	var across := (hi - lo)[2 - axis] + 1
	var height := hi.y - lo.y + 1
	var level: float = room["level"]
	var hard := clampf(level / 6.0 + rng.randf_range(-0.1, 0.1), 0.0, 1.0)
	c.fill(lo - Vector3i(3, 3, 3), hi + Vector3i(3, 3, 3), Blocks.TRIAL_STONE)
	c.fill(lo, hi, Blocks.AIR)
	# A band of gold trim round the walls, and glowing lamps along both sides.
	_tfill(c, room, 0, height - 6, -1, along - 1, height - 6, -1, Blocks.TRIAL_TRIM)
	_tfill(c, room, 0, height - 6, across, along - 1, height - 6, across, Blocks.TRIAL_TRIM)
	var u := 10
	while u < along - 6:
		for v: int in [-1, across]:
			var p := _cell(room, u, 40, v)
			c.fill(p, p + Vector3i(0, 1, 0), Blocks.TRIAL_GLOW)
			room["lights"].append({"pos": (Vector3(p) + Vector3(0.5, 1.0, 0.5)) * VOXEL, "color": TRIAL_COLOR * 0.7, "range": 7.5,
				"min_y": (lo.y - 1) * VOXEL, "flicker": false, "room": room["id"]})
		u += 22
	# The start ledge, the door behind it and the alcove in front of the door.
	var start_h := 24
	var ledge := 10
	_tfill(c, room, 0, 0, 0, ledge - 1, start_h - 1, across - 1, Blocks.TRIAL_STONE)
	var mid := across / 2
	_tfill(c, room, -3, start_h, mid - 4, -1, start_h + 15, mid + 3, Blocks.AIR)
	_tfill(c, room, -3 - PORCH, start_h - 1, mid - 6, -4, start_h - 1, mid + 5, Blocks.TRIAL_STONE)
	_tfill(c, room, -3 - PORCH, start_h, mid - 6, -4, start_h + 17, mid + 5, Blocks.AIR)
	_tfill(c, room, -4, start_h, mid - 5, -4, start_h + 16, mid - 5, Blocks.TRIAL_TRIM)
	_tfill(c, room, -4, start_h, mid + 4, -4, start_h + 16, mid + 4, Blocks.TRIAL_TRIM)
	_tfill(c, room, -4, start_h + 16, mid - 5, -4, start_h + 16, mid + 4, Blocks.TRIAL_TRIM)
	room["door"] = (Vector3(_cell(room, -3 - PORCH / 2, start_h, mid)) + Vector3(0.5, 0.0, 0.5)) * VOXEL
	room["start"] = (Vector3(_cell(room, ledge / 2, start_h, mid)) + Vector3(0.5, 0.0, 0.5)) * VOXEL
	# The stairs back up from the floor, in the corner beside the ledge.
	for k in 7:
		var top := start_h - 3 * (k + 1)
		_tfill(c, room, ledge + 2 * k, 0, across - 8, ledge + 2 * k + 1, top - 1, across - 1, Blocks.TRIAL_STONE)
	# The course. Each jump is no wider than you can clear running, with some room to spare.
	var size := roundi(lerpf(12.0, 6.0, hard))
	var gap_lo := lerpf(6.0, 11.0, hard)
	var gap_hi := lerpf(10.0, 17.0, hard)
	var rise_up := roundi(lerpf(3.0, 6.0, hard))
	var rise_down := roundi(lerpf(4.0, 8.0, hard))
	var side := roundi(lerpf(4.0, 12.0, hard))
	var goal := 14
	var course: Array = []
	var at_u := ledge
	var at_h := start_h
	var at_v0 := mid - size / 2
	var last_size := across
	var last_v0 := 0
	while true:
		var rise := rng.randi_range(-rise_down, rise_up)
		var h := clampi(at_h + rise, 16, 32)
		var gap := roundi(rng.randf_range(gap_lo, gap_hi))
		var v0 := clampi(at_v0 + rng.randi_range(-side, side), 2, across - size - 2)
		if at_u < ledge + 18:
			v0 = mini(v0, across - size - 11)
		gap = _fair_gap(gap, h - at_h, v0, size, last_v0, last_size)
		if at_u + gap + size + 6 > along - goal:
			break
		_platform(c, room, at_u + gap, h, v0, size)
		course.append({"u": at_u + gap, "v": v0, "size": size, "h": h})
		at_u += gap + size
		at_h = h
		last_v0 = v0
		last_size = size
		at_v0 = v0
	# The goal ledge fills the rest, its edge no further than a fair jump.
	var goal_h := clampi(at_h + rng.randi_range(-2, 2), 16, 32)
	var goal_u := at_u + _fair_gap(roundi(gap_lo), goal_h - at_h, 0, across, last_v0, last_size)
	goal_u = mini(goal_u, along - goal)
	_tfill(c, room, goal_u, 0, 0, along - 1, goal_h - 1, across - 1, Blocks.TRIAL_STONE)
	for v: int in [0, across - 1]:
		_tfill(c, room, goal_u, goal_h - 1, v, goal_u, goal_h - 1, v, Blocks.TRIAL_GLOW)
	room["course"] = course
	room["goal"] = (Vector3(_cell(room, (goal_u + along) / 2, goal_h, mid)) + Vector3(0.5, 0.0, 0.5)) * VOXEL
	# The reward, against the far wall.
	var chest_u := along - 8
	var p0 := _cell(room, chest_u, goal_h, mid - 4)
	var p1 := _cell(room, chest_u + 5, goal_h, mid + 3)
	var side_wall := 0
	if axis == 0:
		side_wall = 2 if room["flip"] else 3
	else:
		side_wall = 0 if room["flip"] else 1
	_loot_chest(c, room, p0.min(p1), side_wall, chest_rarity(level, 1.5, rng), {"reward": true})


# The gap shrunk, if need be, to one you can clear with room to spare: the run along the course,
# plus any step sideways between the two platforms, for a landing `rise` cells higher.
static func _fair_gap(gap: int, rise: int, v0: int, size: int, last_v0: int, last_size: int) -> int:
	var sideways := maxi(0, maxi(last_v0 - (v0 + size), v0 - (last_v0 + last_size)))
	var limit := (reach(rise * VOXEL) * 0.72 + 0.3) / VOXEL
	var g := gap
	while g > 4 and sqrt(float(g * g + sideways * sideways)) > limit:
		g -= 1
	return g


# A pillar from the floor to `h`, `size` wide, with glowing corners on top.
static func _platform(c: Canvas, room: Dictionary, u0: int, h: int, v0: int, size: int) -> void:
	_tfill(c, room, u0, 0, v0, u0 + size - 1, h - 1, v0 + size - 1, Blocks.TRIAL_STONE)
	for du: int in [0, size - 1]:
		for dv: int in [0, size - 1]:
			_tfill(c, room, u0 + du, h - 1, v0 + dv, u0 + du, h - 1, v0 + dv, Blocks.TRIAL_GLOW)


# --- Finding them --------------------------------------------------------------------------------

static func chest_at(room: Dictionary, c: Vector3i) -> int:
	var chests: Array = room.get("chests", [])
	for k in chests.size():
		var lo: Vector3i = chests[k]["lo"]
		var hi: Vector3i = chests[k]["hi"]
		if c.x >= lo.x and c.x <= hi.x and c.y >= lo.y and c.y <= hi.y and c.z >= lo.z and c.z <= hi.z:
			return k
	return -1


# Whether point p (metres) is inside the room, standing on its floor counting.
static func contains(room: Dictionary, p: Vector3) -> bool:
	var c := p / VOXEL
	var lo: Vector3i = room["lo"]
	var hi: Vector3i = room["hi"]
	return c.x >= lo.x and c.y >= lo.y - 1 and c.z >= lo.z and c.x < hi.x + 1 and c.y < hi.y + 1 and c.z < hi.z + 1


# How far point p (metres) is from the room's walls, in metres (0 inside).
static func distance(room: Dictionary, p: Vector3) -> float:
	var lo := Vector3(room["shell_lo"]) * VOXEL
	var hi := (Vector3(room["shell_hi"]) + Vector3.ONE) * VOXEL
	var q := p.clamp(lo, hi)
	return q.distance_to(p)
