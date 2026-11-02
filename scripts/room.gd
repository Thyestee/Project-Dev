extends RefCounted
# Your room at the top of the world, the brick staircase down to the dig site, and every room
# upgrade, all built out of blocks. Coordinates are cells; `w` is the world.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")

const FLOOR := 172             # the room floor's top surface (World.FLOOR_Y)
const X0 := 112                # room inside: x in [X0, X1), y in [FLOOR, CEIL), z in [Z0, Z1)
const X1 := 144
const Z0 := 120
const Z1 := 152
const CEIL := 186
const DOOR_X0 := 126           # the stairs run down from a doorway in the north wall
const DOOR_X1 := 131
const STEPS := 28
const STAIRS_END_Z := 58
const SPAWN := Vector3(128.5, 172.0, 141.0)
const BENCH_LO := Vector3i(114, 172, 119)
const BENCH_HI := Vector3i(122, 180, 122)
const WINDOWS := [124, 133]    # each 6 cells wide, in the west wall
const SHELF_SLOTS := 12        # one per kind of treasure

const WARM := Color(1.0, 0.78, 0.5)


static func contains(c: Vector3i) -> bool:
	return c.x >= X0 and c.x < X1 and c.y >= FLOOR and c.y < CEIL and c.z >= Z0 and c.z < Z1


static func in_stairs(c: Vector3i) -> bool:
	return c.x >= DOOR_X0 - 1 and c.x <= DOOR_X1 and c.z >= STAIRS_END_Z and c.z < Z0 and c.y >= FLOOR - STEPS - 2


static func is_workbench(c: Vector3i) -> bool:
	return c.x >= BENCH_LO.x and c.x <= BENCH_HI.x and c.y >= BENCH_LO.y and c.y <= BENCH_HI.y and c.z >= BENCH_LO.z and c.z <= BENCH_HI.z


# --- The base room -------------------------------------------------------------------------

static func build_base(w) -> void:
	_dig_site(w)
	# Shell, hollowed out, with floorboards, beams along the walls and across the ceiling.
	w.fill(Vector3i(X0 - 1, FLOOR - 1, Z0 - 1), Vector3i(X1, CEIL, Z1), Blocks.WALL)
	w.fill(Vector3i(X0, FLOOR, Z0), Vector3i(X1 - 1, CEIL - 1, Z1 - 1), Blocks.AIR)
	w.fill(Vector3i(X0, FLOOR - 1, Z0), Vector3i(X1 - 1, FLOOR - 1, Z1 - 1), Blocks.PLANK)
	w.fill(Vector3i(X0, CEIL, Z0), Vector3i(X1 - 1, CEIL, Z1 - 1), Blocks.PLANK)
	for y: int in [FLOOR, CEIL - 1]:
		w.fill(Vector3i(X0 - 1, y, Z0 - 1), Vector3i(X1, y, Z0 - 1), Blocks.BEAM)
		w.fill(Vector3i(X0 - 1, y, Z1), Vector3i(X1, y, Z1), Blocks.BEAM)
		w.fill(Vector3i(X0 - 1, y, Z0 - 1), Vector3i(X0 - 1, y, Z1), Blocks.BEAM)
		w.fill(Vector3i(X1, y, Z0 - 1), Vector3i(X1, y, Z1), Blocks.BEAM)
	for corner: Vector2i in [Vector2i(X0 - 1, Z0 - 1), Vector2i(X1, Z0 - 1), Vector2i(X0 - 1, Z1), Vector2i(X1, Z1)]:
		w.fill(Vector3i(corner.x, FLOOR, corner.y), Vector3i(corner.x, CEIL - 1, corner.y), Blocks.BEAM)
	for z in range(Z0 + 3, Z1 - 1, 8):
		w.fill(Vector3i(X0, CEIL - 1, z), Vector3i(X1 - 1, CEIL - 1, z + 1), Blocks.BEAM)
	for z0: int in WINDOWS:
		w.fill(Vector3i(X0 - 1, 175, z0 - 1), Vector3i(X0 - 1, 182, z0 + 6), Blocks.BEAM)
		w.fill(Vector3i(X0 - 1, 176, z0), Vector3i(X0 - 1, 181, z0 + 5), Blocks.WINDOW)
	_stairs(w)
	_workbench(w)
	_hanging_lantern(w, Blocks.LANTERN)


# A doorway, a short brick landing and 28 steps down to the dig site, 7 m under the floor.
static func _stairs(w) -> void:
	_tunnel(w, Z0 - 6, Z0 - 1, FLOOR)
	for k in STEPS:
		_tunnel(w, Z0 - 8 - 2 * k, Z0 - 7 - 2 * k, FLOOR - 1 - k)
	for k: int in [5, 13, 21]:
		w.put(DOOR_X0 - 1, FLOOR - 1 - k + 6, Z0 - 7 - 2 * k, Blocks.LANTERN)
	# A timber frame where the stairs open into the dig site.
	var s := FLOOR - STEPS
	w.fill(Vector3i(DOOR_X0 - 1, s, STAIRS_END_Z - 1), Vector3i(DOOR_X0 - 1, s + 9, STAIRS_END_Z - 1), Blocks.BEAM)
	w.fill(Vector3i(DOOR_X1, s, STAIRS_END_Z - 1), Vector3i(DOOR_X1, s + 9, STAIRS_END_Z - 1), Blocks.BEAM)
	w.fill(Vector3i(DOOR_X0 - 1, s + 10, STAIRS_END_Z - 1), Vector3i(DOOR_X1, s + 10, STAIRS_END_Z - 1), Blocks.BEAM)


# A slice of brick-lined tunnel from z_lo to z_hi with its floor surface at height s.
static func _tunnel(w, z_lo: int, z_hi: int, s: int) -> void:
	w.fill(Vector3i(DOOR_X0 - 1, s - 2, z_lo), Vector3i(DOOR_X1, s + 10, z_hi), Blocks.BRICK)
	w.fill(Vector3i(DOOR_X0, s, z_lo), Vector3i(DOOR_X1 - 1, s + 9, z_hi), Blocks.AIR)


# A domed chamber at the foot of the stairs, with two lanterns on posts. Its walls are plain
# ground: this is where the digging starts.
static func _dig_site(w) -> void:
	var s := FLOOR - STEPS
	var center := Vector2(128.5, 46.5)
	var radius := Vector2(12.5, 11.5)
	for z in range(int(center.y - radius.y) - 1, int(center.y + radius.y) + 2):
		for x in range(int(center.x - radius.x) - 1, int(center.x + radius.x) + 2):
			var e := pow((x + 0.5 - center.x) / radius.x, 2.0) + pow((z + 0.5 - center.y) / radius.y, 2.0)
			if e <= 1.0:
				w.fill(Vector3i(x, s, z), Vector3i(x, s + 8 + int(4.0 * (1.0 - e)), z), Blocks.AIR)
	w.fill(Vector3i(DOOR_X0, s, 50), Vector3i(DOOR_X1 - 1, s + 9, STAIRS_END_Z - 1), Blocks.AIR)
	for x: int in [119, 138]:
		w.fill(Vector3i(x, s, 46), Vector3i(x, s + 6, 46), Blocks.BEAM)
		w.put(x, s + 7, 46, Blocks.LANTERN)


static func _workbench(w) -> void:
	w.fill(Vector3i(114, 175, 120), Vector3i(122, 175, 122), Blocks.WORKBENCH)
	for x: int in [114, 122]:
		for z: int in [120, 122]:
			w.fill(Vector3i(x, 172, z), Vector3i(x, 174, z), Blocks.WORKBENCH)
	w.fill(Vector3i(115, 176, 121), Vector3i(116, 176, 121), Blocks.IRON)
	# A tool rack on the wall behind it.
	w.fill(Vector3i(114, 179, Z0 - 1), Vector3i(122, 179, Z0 - 1), Blocks.BEAM)
	for x: int in [115, 117, 120]:
		w.fill(Vector3i(x, 177, Z0), Vector3i(x, 178, Z0), Blocks.IRON)


static func _hanging_lantern(w, b: int) -> void:
	w.put(127, 185, 135, Blocks.BEAM if b != Blocks.AIR else Blocks.AIR)
	w.fill(Vector3i(127, 183, 135), Vector3i(128, 184, 136), b)


# --- Lights ----------------------------------------------------------------------------------

static func _light(cell: Vector3, color: Color, strength: float, light_range: float, in_room := true, flicker := false) -> Dictionary:
	var v := 0.25
	return {"pos": cell * v, "color": color * strength, "range": light_range, "min_y": (FLOOR - 1) * v if in_room else -100.0, "flicker": flicker}


static func lights(owned: Array) -> Array:
	var list := []
	if not owned.has("chandelier"):
		list.append(_light(Vector3(128.0, 183.0, 136.0), WARM, 0.75, 8.5))
	for z0: int in WINDOWS:
		list.append(_light(Vector3(X0 + 1.5, 179.0, z0 + 3.0), Color(0.6, 0.72, 0.9), 0.4, 6.0))
	for k: int in [5, 13, 21]:
		list.append(_light(Vector3(DOOR_X0 + 0.6, FLOOR - 1 - k + 6.5, Z0 - 6.5 - 2 * k), WARM, 0.7, 5.5, false))
	for x: int in [119, 138]:
		list.append(_light(Vector3(x + 0.5, FLOOR - STEPS + 7.5, 46.5), WARM, 0.85, 7.5, false))
	if owned.has("lanterns"):
		for p: Vector3 in _wall_lanterns():
			list.append(_light(p + Vector3(0.5, 0.0, 0.5), WARM, 0.45, 6.0))
	if owned.has("fireplace"):
		list.append(_light(Vector3(139.0, 173.5, 149.0), Color(1.0, 0.55, 0.25), 1.0, 7.0, true, true))
	if owned.has("chandelier"):
		list.append(_light(Vector3(128.0, 182.5, 136.0), Color(1.0, 0.85, 0.6), 1.0, 11.0))
	return list


static func _wall_lanterns() -> Array[Vector3]:
	return [Vector3(X0, 178, 131), Vector3(X1 - 1, 178, 124), Vector3(X1 - 1, 178, 148), Vector3(137, 178, Z0)]


# --- Upgrades --------------------------------------------------------------------------------

static func apply(w, id: String) -> void:
	match id:
		"plants":
			for p: Vector2i in [Vector2i(X1 - 3, Z0), Vector2i(X0, Z0), Vector2i(133, Z1 - 2)]:
				_plant(w, p.x, p.y)
		"lanterns":
			for p: Vector3 in _wall_lanterns():
				var c := Vector3i(p)
				w.fill(c, c + Vector3i(0, 1, 0), Blocks.LANTERN)
				w.put(c.x, c.y + 2, c.z, Blocks.BEAM)
		"rug":
			for z in range(127, 146):
				for x in range(119, 138):
					var border := x == 119 or x == 137 or z == 127 or z == 145
					var stripe := (z - 127) % 6 == 3 and x > 120 and x < 136
					w.put(x, FLOOR - 1, z, Blocks.RUG_TRIM if border or stripe else Blocks.RUG)
		"shelves":
			for y: int in [175, 180]:
				w.fill(Vector3i(X1 - 2, y, 126), Vector3i(X1 - 1, y, 145), Blocks.BEAM)
			for z: int in [126, 145]:
				w.fill(Vector3i(X1 - 2, FLOOR, z), Vector3i(X1 - 1, 180, z), Blocks.BEAM)
		"bed":
			w.fill(Vector3i(X0, FLOOR, 140), Vector3i(X0 + 5, FLOOR, Z1 - 1), Blocks.BEAM)
			w.fill(Vector3i(X0, FLOOR + 1, 141), Vector3i(X0 + 5, FLOOR + 2, 147), Blocks.BLANKET)
			w.fill(Vector3i(X0, FLOOR + 1, 148), Vector3i(X0 + 5, FLOOR + 1, Z1 - 2), Blocks.PILLOW)
			w.fill(Vector3i(X0 + 1, FLOOR + 2, 149), Vector3i(X0 + 4, FLOOR + 2, Z1 - 2), Blocks.PILLOW)
			w.fill(Vector3i(X0, FLOOR, Z1 - 1), Vector3i(X0 + 5, FLOOR + 4, Z1 - 1), Blocks.BEAM)
			w.fill(Vector3i(X0, FLOOR, 140), Vector3i(X0 + 5, FLOOR + 2, 140), Blocks.BEAM)
		"books":
			var rng := RandomNumberGenerator.new()
			rng.seed = 77
			w.fill(Vector3i(120, FLOOR, Z1 - 2), Vector3i(131, 183, Z1 - 1), Blocks.BEAM)
			w.fill(Vector3i(121, FLOOR, Z1 - 2), Vector3i(130, 182, Z1 - 2), Blocks.AIR)
			for base: int in [FLOOR, 176, 180]:
				w.fill(Vector3i(121, base, Z1 - 2), Vector3i(130, base, Z1 - 2), Blocks.BEAM)
				for x in range(121, 131):
					if rng.randf() < 0.15:
						continue
					var book: int = [Blocks.BOOK_RED, Blocks.BOOK_GREEN, Blocks.BOOK_BLUE][rng.randi_range(0, 2)]
					w.fill(Vector3i(x, base + 1, Z1 - 2), Vector3i(x, base + rng.randi_range(1, 3), Z1 - 2), book)
		"fireplace":
			w.fill(Vector3i(135, FLOOR, Z1 - 3), Vector3i(142, 179, Z1 - 1), Blocks.COBBLE)
			w.fill(Vector3i(137, FLOOR, Z1 - 3), Vector3i(140, 175, Z1 - 2), Blocks.AIR)
			w.fill(Vector3i(137, FLOOR, Z1 - 2), Vector3i(140, FLOOR, Z1 - 2), Blocks.FIRE)
			w.fill(Vector3i(138, FLOOR + 1, Z1 - 2), Vector3i(139, FLOOR + 1, Z1 - 2), Blocks.FIRE)
			w.fill(Vector3i(134, 180, Z1 - 4), Vector3i(143, 180, Z1 - 1), Blocks.BEAM)
			w.fill(Vector3i(136, 181, Z1 - 2), Vector3i(141, CEIL - 1, Z1 - 1), Blocks.COBBLE)
			w.fill(Vector3i(135, FLOOR - 1, Z1 - 4), Vector3i(142, FLOOR - 1, Z1 - 4), Blocks.COBBLE)
		"panelling":
			for y in range(FLOOR, CEIL):
				var b := Blocks.PANEL if y <= 176 else (Blocks.BEAM if y == 177 else Blocks.WALLPAPER)
				for x in range(X0 - 1, X1 + 1):
					_repaint(w, x, y, Z0 - 1, b)
					_repaint(w, x, y, Z1, b)
				for z in range(Z0 - 1, Z1 + 1):
					_repaint(w, X0 - 1, y, z, b)
					_repaint(w, X1, y, z, b)
		"chandelier":
			_hanging_lantern(w, Blocks.AIR)
			w.fill(Vector3i(128, 184, 136), Vector3i(128, CEIL - 1, 136), Blocks.GOLD)
			for z in range(131, 142):
				for x in range(123, 134):
					var d := Vector2(x - 128, z - 136).length()
					if absf(d - 3.5) < 0.6:
						w.put(x, 183, z, Blocks.GOLD)
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for r in range(1, 3):
					w.put(128 + dir.x * r, 184, 136 + dir.y * r, Blocks.GOLD)
			for a in 8:
				var p := Vector2(128, 136) + Vector2.from_angle(a * TAU / 8.0) * 3.5
				w.put(roundi(p.x), 184, roundi(p.y), Blocks.LANTERN)


static func _repaint(w, x: int, y: int, z: int, b: int) -> void:
	if w.block(x, y, z) == Blocks.WALL:
		w.put(x, y, z, b)


static func _plant(w, x: int, z: int) -> void:
	w.fill(Vector3i(x, FLOOR, z), Vector3i(x + 1, FLOOR + 1, z + 1), Blocks.POT)
	w.fill(Vector3i(x, FLOOR + 2, z), Vector3i(x + 1, FLOOR + 5, z + 1), Blocks.LEAF)
	for leaf: Vector3i in [Vector3i(x - 1, FLOOR + 4, z), Vector3i(x + 2, FLOOR + 4, z), Vector3i(x - 1, FLOOR + 4, z + 1), Vector3i(x + 2, FLOOR + 4, z + 1),
			Vector3i(x, FLOOR + 3, z - 1), Vector3i(x + 1, FLOOR + 3, z - 1), Vector3i(x, FLOOR + 3, z + 2), Vector3i(x + 1, FLOOR + 3, z + 2)]:
		if w.block(leaf.x, leaf.y, leaf.z) == Blocks.AIR:
			w.put(leaf.x, leaf.y, leaf.z, Blocks.LEAF)


# One trophy on the shelves for every kind of treasure found so far.
static func show_trophies(w, owned: Array, found: Dictionary) -> void:
	if not owned.has("shelves"):
		return
	for t in SHELF_SLOTS:
		var y := 176 if t < 6 else 181
		var z := 128 + (t % 6) * 3
		var info: Dictionary = Treasures.LIST[t]
		var have := int(found.get(t, 0)) > 0
		w.fill(Vector3i(X1 - 2, y, z), Vector3i(X1 - 1, y, z + 1), Blocks.GOLD if have else Blocks.AIR)
		w.fill(Vector3i(X1 - 2, y + 1, z), Vector3i(X1 - 1, y + 2, z + 1), Blocks.TROPHY + int(info["rarity"]) if have else Blocks.AIR)
