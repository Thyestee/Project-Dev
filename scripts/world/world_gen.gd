extends RefCounted
## Fills areas: the house (always the same room plus what you built), and the forest and
## mine, which are generated fresh for every trip.

const Data := preload("res://scripts/game_data.gd")
const TILE := Data.TILE
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

const HOUSE_SIZE := Vector2i(18, 12)
const DOOR_CELL := Vector2i(8, 11)


# --- House -------------------------------------------------------------------

static func build_house(area, placed: Array) -> void:
	area.setup("house", HOUSE_SIZE.x, HOUSE_SIZE.y, Data.T_HOUSE_WALL)
	for y in range(2, HOUSE_SIZE.y - 1):
		for x in range(1, HOUSE_SIZE.x - 1):
			area.set_tile(Vector2i(x, y), Data.T_PLANKS)
	area.windows = [4, 13]
	area.add_entity("door", DOOR_CELL)
	area.add_entity("bed", Vector2i(1, 2))
	area.add_entity("workbench", Vector2i(14, 2))
	for p in placed:
		var cell := Vector2i(int(p["x"]), int(p["y"]))
		if area.can_place(cell, Data.entity_size(p["kind"])):
			area.add_entity(p["kind"], cell)
	area.spawn = Vector2((DOOR_CELL.x + 1) * TILE, DOOR_CELL.y * TILE - 6)


# --- Forest ------------------------------------------------------------------

static func build_forest(area, rng: RandomNumberGenerator) -> void:
	var w := 72
	var h := 54
	area.setup("forest", w, h, Data.T_GRASS)

	# Impassable thicket with a ragged edge all around.
	var edge_noise := FastNoiseLite.new()
	edge_noise.seed = rng.randi()
	edge_noise.frequency = 0.15
	for y in h:
		for x in w:
			var edge := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			if edge < 3 + int(round((edge_noise.get_noise_2d(x, y) + 1.0) * 1.5)):
				area.set_tile(Vector2i(x, y), Data.T_THICKET)

	# Winding dirt paths from the entrance (south) out into the woods.
	var start := Vector2i(int(w * 0.5), h - 8)
	var junction := Vector2i(int(w * 0.5) + rng.randi_range(-6, 6), int(h * 0.5))
	_carve_path(area, start, junction, rng)
	_carve_path(area, junction, Vector2i(rng.randi_range(9, 20), rng.randi_range(9, 16)), rng)
	_carve_path(area, junction, Vector2i(rng.randi_range(w - 21, w - 10), rng.randi_range(9, 16)), rng)
	_carve_path(area, junction, Vector2i(int(w * 0.5) + rng.randi_range(-4, 4), 8), rng)

	for i in rng.randi_range(1, 3):
		var c := Vector2i(rng.randi_range(10, w - 11), rng.randi_range(9, h - 15))
		var r := rng.randf_range(2.0, 4.0)
		for y in range(c.y - 5, c.y + 6):
			for x in range(c.x - 5, c.x + 6):
				var p := Vector2i(x, y)
				if Vector2(p - c).length() <= r + rng.randf_range(-0.6, 0.6) and area.tile_at(p) == Data.T_GRASS:
					area.set_tile(p, Data.T_WATER)

	area.add_entity("exit_sign", start + Vector2i(-2, 0))
	area.spawn = area.cell_center(start) + Vector2(0, 10)

	# Trees grow in clumps; old oaks (need a copper axe) grow deeper in the woods.
	var density := FastNoiseLite.new()
	density.seed = rng.randi()
	density.frequency = 0.07
	for y in h:
		for x in w:
			var c := Vector2i(x, y)
			if area.tile_at(c) != Data.T_GRASS or Vector2(c - start).length() < 5.0 or _near_entity(area, c):
				continue
			var n := (density.get_noise_2d(x, y) + 1.0) * 0.5
			if rng.randf() > 0.04 + n * n * 0.65:
				continue
			var depth := 1.0 - float(y) / h
			if depth > 0.4 and rng.randf() < 0.1 + depth * 0.35:
				area.add_entity("old_tree", c)
			else:
				area.add_entity("tree", c)

	_scatter(area, "boulder", rng.randi_range(14, 20), [Data.T_GRASS], start, rng)


static func _carve_path(area, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var cur := a
	var guard := 0
	while cur != b and guard < 3000:
		guard += 1
		for o in [Vector2i.ZERO, Vector2i.RIGHT]:
			var c: Vector2i = cur + o
			if area.tile_at(c) == Data.T_GRASS:
				area.set_tile(c, Data.T_PATH)
		var d := b - cur
		var step := Vector2i.ZERO
		if rng.randf() < 0.2:
			step = DIRS[rng.randi() % 4]
		elif absi(d.x) > absi(d.y) or (d.x != 0 and rng.randf() < 0.3):
			step = Vector2i(signi(d.x), 0)
		else:
			step = Vector2i(0, signi(d.y))
		if area.tile_at(cur + step) != Data.T_THICKET:
			cur += step


static func _near_entity(area, c: Vector2i) -> bool:
	for y in range(-1, 2):
		for x in range(-1, 2):
			if area.occupants.has(c + Vector2i(x, y)):
				return true
	return false


static func _scatter(area, entity_kind: String, count: int, on_tiles: Array, avoid: Vector2i, rng: RandomNumberGenerator) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 40:
		tries += 1
		var c := Vector2i(rng.randi_range(1, area.width - 2), rng.randi_range(1, area.height - 2))
		if not (area.tile_at(c) in on_tiles) or Vector2(c - avoid).length() < 4.0 or _near_entity(area, c):
			continue
		area.add_entity(entity_kind, c)
		placed += 1


# --- Mine --------------------------------------------------------------------

static func build_mine(area, depth: int, rng: RandomNumberGenerator) -> void:
	var w := 60
	var h := 44
	area.setup("mine", w, h, Data.T_CAVE_WALL)

	# Caverns joined by winding corridors, plus a few dead-end side tunnels.
	var rooms: Array = []
	var tries := 0
	while rooms.size() < 9 + mini(depth, 4) and tries < 500:
		tries += 1
		var r := rng.randi_range(2, 4)
		var c := Vector2i(rng.randi_range(r + 3, w - r - 4), rng.randi_range(r + 3, h - r - 4))
		var ok := true
		for other in rooms:
			if Vector2(c - other["c"]).length() < r + int(other["r"]) + 5:
				ok = false
				break
		if ok:
			rooms.append({"c": c, "r": r})
	for room in rooms:
		_carve_blob(area, room["c"], room["r"], rng)
	for i in range(1, rooms.size()):
		var nearest := 0
		for j in i:
			if Vector2(rooms[j]["c"] - rooms[i]["c"]).length() < Vector2(rooms[nearest]["c"] - rooms[i]["c"]).length():
				nearest = j
		_carve_tunnel(area, rooms[i]["c"], rooms[nearest]["c"], rng)
	for i in 2:
		_carve_tunnel(area, rooms[rng.randi() % rooms.size()]["c"], rooms[rng.randi() % rooms.size()]["c"], rng)
	for i in 4 + depth:
		_carve_dead_end(area, rooms[rng.randi() % rooms.size()]["c"], rng)

	# The ladder you came down is in the first cavern; the way deeper is in the farthest one.
	var start: Vector2i = rooms[0]["c"]
	var far: Vector2i = start
	for room in rooms:
		if Vector2(room["c"] - start).length() > Vector2(far - start).length():
			far = room["c"]
	area.add_entity("ladder_up", start)
	area.add_entity("ladder_down", far)
	area.spawn = area.cell_center(start + Vector2i.DOWN)

	# Veins start on a wall you can see and snake back into the rock.
	var weights: Dictionary = Data.mine_floor_weights(depth)
	var exposed: Array = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var c := Vector2i(x, y)
			if area.tile_at(c) != Data.T_CAVE_WALL:
				continue
			for o in DIRS:
				if area.tile_at(c + o) == Data.T_CAVE_FLOOR:
					exposed.append(c)
					break
	for i in 24 + depth * 4:
		if exposed.is_empty():
			break
		var c: Vector2i = exposed[rng.randi() % exposed.size()]
		var ore: String = Data.pick_weighted(weights, rng)
		for k in rng.randi_range(3, 7):
			area.set_vein(c, ore)
			var options: Array = []
			for o in DIRS:
				var n: Vector2i = c + o
				if n.x >= 1 and n.y >= 1 and n.x < w - 1 and n.y < h - 1 and area.tile_at(n) == Data.T_CAVE_WALL:
					options.append(n)
			if options.is_empty():
				break
			c = options[rng.randi() % options.size()]

	_scatter(area, "boulder", 12 + depth * 2, [Data.T_CAVE_FLOOR], start, rng)


static func _carve_floor(area, c: Vector2i) -> void:
	if c.x >= 1 and c.y >= 1 and c.x < area.width - 1 and c.y < area.height - 1:
		area.set_tile(c, Data.T_CAVE_FLOOR)


static func _carve_blob(area, center: Vector2i, r: int, rng: RandomNumberGenerator) -> void:
	for y in range(center.y - r - 1, center.y + r + 2):
		for x in range(center.x - r - 1, center.x + r + 2):
			var c := Vector2i(x, y)
			if Vector2(c - center).length() <= r + rng.randf_range(-0.7, 0.8):
				_carve_floor(area, c)


static func _carve_tunnel(area, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var wide := rng.randf() < 0.5
	var cur := a
	var guard := 0
	while cur != b and guard < 3000:
		guard += 1
		_carve_floor(area, cur)
		if wide:
			_carve_floor(area, cur + Vector2i.RIGHT)
			_carve_floor(area, cur + Vector2i.DOWN)
		var d := b - cur
		if rng.randf() < 0.18:
			cur += DIRS[rng.randi() % 4]
		elif absi(d.x) > absi(d.y) or (d.x != 0 and rng.randf() < 0.35):
			cur += Vector2i(signi(d.x), 0)
		else:
			cur += Vector2i(0, signi(d.y))
		cur = Vector2i(clampi(cur.x, 1, area.width - 2), clampi(cur.y, 1, area.height - 2))


static func _carve_dead_end(area, from: Vector2i, rng: RandomNumberGenerator) -> void:
	var cur := from
	var dir: Vector2i = DIRS[rng.randi() % 4]
	for i in rng.randi_range(6, 14):
		if rng.randf() < 0.3:
			dir = DIRS[rng.randi() % 4]
		cur = Vector2i(clampi(cur.x + dir.x, 1, area.width - 2), clampi(cur.y + dir.y, 1, area.height - 2))
		_carve_floor(area, cur)
