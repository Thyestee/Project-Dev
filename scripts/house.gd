extends RefCounted
# Your house at the top of the world, the brick staircase down to the dig site, the workbench, the
# forge and the rope lift, the decorations and the furniture you place yourself, all built out of
# blocks.
# Coordinates are cells; `w` is the world.

const Blocks := preload("res://scripts/blocks.gd")
const Catalog := preload("res://scripts/catalog.gd")
const Treasures := preload("res://scripts/treasures.gd")

const VOXEL := 0.125
const FLOOR := 344             # the floor's top surface (World.FLOOR_Y)
const CEIL := FLOOR + 28       # the underside of the ceiling: 3.5 m of headroom
const DOOR_X := 192            # the doorway in the north wall spans x in [DOOR_X - 5, DOOR_X + 5)
const Z0 := 240                # inside face of the north wall; bigger houses grow south, east and west
const LANDING := 12            # flat tunnel behind the door
const STEPS := 56              # each one cube down and two along
const STAIRS_END_Z := Z0 - LANDING - 2 * STEPS
const SITE_FLOOR := FLOOR - STEPS
const SITE := Vector2(192.0, 92.0)
const SITE_RADIUS := Vector2(25.0, 23.0)
const TORCH_STEPS := [10, 26, 42]
const BENCH_LO := Vector3i(DOOR_X - 27, FLOOR, Z0 - 1)
const BENCH_HI := Vector3i(DOOR_X - 10, FLOOR + 16, Z0 + 5)
const FORGE_LO := Vector3i(DOOR_X + 9, FLOOR, Z0)
const FORGE_HI := Vector3i(DOOR_X + 24, CEIL - 1, Z0 + 6)
const LIFT_LO := Vector3i(DOOR_X + 7, FLOOR, Z0)        # the rope lift between the door and the forge
const LIFT_HI := Vector3i(DOOR_X + 8, FLOOR + 16, Z0 + 1)
# The house, the stairs and the dig site, and the ground round them: no caves or hidden rooms here.
const EXCLUDE_LO := Vector3i(100, FLOOR - 136, 48)
const EXCLUDE_HI := Vector3i(284, FLOOR + 40, 372)
const SPAWN := Vector3(192.0, 344.0, 262.0)
const SHELF_SLOTS := 12        # one per kind of treasure

const WARM := Color(1.0, 0.78, 0.5)


# The inside of the house: x in [position.x, end.x), z in [position.y, end.y).
static func bounds(tier: int) -> Rect2i:
	var size: Vector2i = Catalog.HOUSE_TIERS[tier]["size"]
	return Rect2i(DOOR_X - size.x / 2, Z0, size.x, size.y)


static func center(tier: int) -> Vector2i:
	var r := bounds(tier)
	return Vector2i(DOOR_X, (r.position.y + r.end.y) / 2)


static func contains(c: Vector3i, tier: int) -> bool:
	var r := bounds(tier)
	return c.x >= r.position.x and c.x < r.end.x and c.y >= FLOOR and c.y < CEIL and c.z >= r.position.y and c.z < r.end.y


static func in_stairs(c: Vector3i) -> bool:
	return c.x >= DOOR_X - 7 and c.x <= DOOR_X + 6 and c.z >= STAIRS_END_Z and c.z < Z0 and c.y >= SITE_FLOOR - 4


static func is_workbench(c: Vector3i) -> bool:
	return c.x >= BENCH_LO.x and c.x <= BENCH_HI.x and c.y >= BENCH_LO.y and c.y <= BENCH_HI.y and c.z >= BENCH_LO.z and c.z <= BENCH_HI.z


static func is_forge(c: Vector3i) -> bool:
	return c.x >= FORGE_LO.x and c.x <= FORGE_HI.x and c.y >= FORGE_LO.y and c.y <= FORGE_HI.y and c.z >= FORGE_LO.z and c.z <= FORGE_HI.z


static func is_lift(c: Vector3i) -> bool:
	return c.x >= LIFT_LO.x and c.x <= LIFT_HI.x and c.y >= LIFT_LO.y and c.y <= LIFT_HI.y and c.z >= LIFT_LO.z and c.z <= LIFT_HI.z


static func spawn_point() -> Vector3:
	return SPAWN * VOXEL


static func windows(tier: int) -> Array[int]:
	var r := bounds(tier)
	var n := 2 if tier < 2 else 3
	var out: Array[int] = []
	for k in n:
		out.append(Z0 + r.size.y * (k + 1) / (n + 1))
	return out


# --- The house and the stairs ------------------------------------------------------------------

static func build_base(w, tier: int) -> void:
	_dig_site(w)
	build_shell(w, tier)


# Walls, floor and ceiling for the house's size, with the doorway, the stairs, the workbench and
# the forge. Building it again wipes out the decorations and furniture, which go back after.
static func build_shell(w, tier: int) -> void:
	var r := bounds(tier)
	var x0 := r.position.x
	var x1 := r.end.x
	var z1 := r.end.y
	w.fill(Vector3i(x0 - 2, FLOOR - 3, Z0 - 2), Vector3i(x1 + 1, CEIL + 2, z1 + 1), Blocks.WALL)
	w.fill(Vector3i(x0, FLOOR, Z0), Vector3i(x1 - 1, CEIL - 1, z1 - 1), Blocks.AIR)
	# Floorboards in rows, with a darker seam every third row; planks across the ceiling.
	for z in range(Z0, z1):
		w.fill(Vector3i(x0, FLOOR - 1, z), Vector3i(x1 - 1, FLOOR - 1, z), Blocks.PLANK_DARK if (z - Z0) % 3 == 2 else Blocks.PLANK)
	w.fill(Vector3i(x0, CEIL, Z0), Vector3i(x1 - 1, CEIL, z1 - 1), Blocks.PLANK)
	# A skirting board and a beam along the top of every wall, posts in the corners and every
	# 4 m, and beams across the ceiling every 2 m.
	for y: int in [FLOOR, CEIL - 1]:
		w.fill(Vector3i(x0 - 1, y, Z0 - 1), Vector3i(x1, y, Z0 - 1), Blocks.BEAM)
		w.fill(Vector3i(x0 - 1, y, z1), Vector3i(x1, y, z1), Blocks.BEAM)
		w.fill(Vector3i(x0 - 1, y, Z0 - 1), Vector3i(x0 - 1, y, z1), Blocks.BEAM)
		w.fill(Vector3i(x1, y, Z0 - 1), Vector3i(x1, y, z1), Blocks.BEAM)
	for corner: Vector2i in [Vector2i(x0 - 1, Z0 - 1), Vector2i(x1, Z0 - 1), Vector2i(x0 - 1, z1), Vector2i(x1, z1)]:
		_post(w, corner.x, corner.y)
	for z in range(Z0 + 31, z1, 32):
		_post(w, x0 - 1, z)
		_post(w, x1, z)
	for x in range(x0 + 31, x1, 32):
		_post(w, x, z1)
	for z in range(Z0 + 7, z1 - 4, 16):
		w.fill(Vector3i(x0, CEIL - 2, z), Vector3i(x1 - 1, CEIL - 1, z + 1), Blocks.BEAM)
	# Windows in the west wall, each with a cross of beams.
	for zc in windows(tier):
		w.fill(Vector3i(x0 - 1, FLOOR + 7, zc - 5), Vector3i(x0 - 1, FLOOR + 18, zc + 4), Blocks.BEAM)
		w.fill(Vector3i(x0 - 2, FLOOR + 8, zc - 4), Vector3i(x0 - 1, FLOOR + 17, zc + 3), Blocks.WINDOW)
		w.fill(Vector3i(x0 - 1, FLOOR + 12, zc - 4), Vector3i(x0 - 1, FLOOR + 12, zc + 3), Blocks.BEAM)
		w.fill(Vector3i(x0 - 1, FLOOR + 8, zc), Vector3i(x0 - 1, FLOOR + 17, zc), Blocks.BEAM)
	_stairs(w)
	_doorframe(w)
	_workbench(w)
	_forge(w)
	_lift(w)
	hanging_lantern(w, tier, Blocks.LANTERN)


static func _post(w, x: int, z: int) -> void:
	w.fill(Vector3i(x, FLOOR, z), Vector3i(x, CEIL - 1, z), Blocks.BEAM)


# A short brick landing behind the door, then 56 steps down to the dig site, 7 m under the floor.
static func _stairs(w) -> void:
	_tunnel(w, Z0 - LANDING, Z0 - 1, FLOOR)
	for k in STEPS:
		_tunnel(w, Z0 - LANDING - 2 * k - 2, Z0 - LANDING - 2 * k - 1, FLOOR - 1 - k)
	for k: int in TORCH_STEPS:
		var z := Z0 - LANDING - 2 * k - 2
		var y := FLOOR - 1 - k + 12
		w.fill(Vector3i(DOOR_X - 6, y, z - 1), Vector3i(DOOR_X - 6, y + 1, z), Blocks.LANTERN)
	# A timber frame where the stairs open into the dig site.
	var s := SITE_FLOOR
	var z := STAIRS_END_Z - 1
	w.fill(Vector3i(DOOR_X - 7, s, z - 1), Vector3i(DOOR_X - 6, s + 19, z), Blocks.BEAM)
	w.fill(Vector3i(DOOR_X + 5, s, z - 1), Vector3i(DOOR_X + 6, s + 19, z), Blocks.BEAM)
	w.fill(Vector3i(DOOR_X - 7, s + 20, z - 1), Vector3i(DOOR_X + 6, s + 21, z), Blocks.BEAM)


# A slice of brick-lined tunnel from z_lo to z_hi with its floor surface at height s.
static func _tunnel(w, z_lo: int, z_hi: int, s: int) -> void:
	w.fill(Vector3i(DOOR_X - 7, s - 4, z_lo), Vector3i(DOOR_X + 6, s + 21, z_hi), Blocks.BRICK)
	w.fill(Vector3i(DOOR_X - 5, s, z_lo), Vector3i(DOOR_X + 4, s + 19, z_hi), Blocks.AIR)


static func _doorframe(w) -> void:
	w.fill(Vector3i(DOOR_X - 7, FLOOR, Z0 - 1), Vector3i(DOOR_X - 6, FLOOR + 19, Z0 - 1), Blocks.BEAM)
	w.fill(Vector3i(DOOR_X + 5, FLOOR, Z0 - 1), Vector3i(DOOR_X + 6, FLOOR + 19, Z0 - 1), Blocks.BEAM)
	w.fill(Vector3i(DOOR_X - 7, FLOOR + 20, Z0 - 1), Vector3i(DOOR_X + 6, FLOOR + 21, Z0 - 1), Blocks.BEAM)


# A domed chamber at the foot of the stairs, with two lanterns on posts. Its walls are plain
# ground, smooth and flat-floored: this is where the digging starts.
static func _dig_site(w) -> void:
	var s := SITE_FLOOR
	var r := minf(SITE_RADIUS.x, SITE_RADIUS.y)
	for z in range(int(SITE.y - SITE_RADIUS.y) - 3, int(SITE.y + SITE_RADIUS.y) + 4):
		for x in range(int(SITE.x - SITE_RADIUS.x) - 3, int(SITE.x + SITE_RADIUS.x) + 4):
			var e := pow((x + 0.5 - SITE.x) / SITE_RADIUS.x, 2.0) + pow((z + 0.5 - SITE.y) / SITE_RADIUS.y, 2.0)
			var wall := (1.0 - sqrt(e)) * r
			var roof := 17.0 + 8.0 * (1.0 - e)
			for y in range(s - 1, s + 27):
				# How far inside the chamber the cell's centre is, in cells: from the floor, the
				# wall or the roof, whichever is nearest.
				var up := y + 0.5 - s
				var inside := minf(wall, minf(up, roof - up))
				w.soften(x, y, z, int(clampf(127.5 - inside * 127.5, 0.0, 254.0)))
	w.fill(Vector3i(DOOR_X - 5, s, int(SITE.y)), Vector3i(DOOR_X + 4, s + 19, STAIRS_END_Z - 1), Blocks.AIR)
	for x: int in [int(SITE.x) - 19, int(SITE.x) + 17]:
		w.fill(Vector3i(x, s, int(SITE.y) - 1), Vector3i(x + 1, s + 13, int(SITE.y)), Blocks.BEAM)
		w.fill(Vector3i(x, s + 14, int(SITE.y) - 1), Vector3i(x + 1, s + 15, int(SITE.y)), Blocks.LANTERN)


static func _workbench(w) -> void:
	var x0 := BENCH_LO.x
	var x1 := BENCH_HI.x
	var z1 := Z0 + 5
	var top := FLOOR + 7
	for x: int in [x0, x1 - 1]:
		for z: int in [Z0, z1 - 1]:
			w.fill(Vector3i(x, FLOOR, z), Vector3i(x + 1, top - 1, z + 1), Blocks.WORKBENCH)
	w.fill(Vector3i(x0 + 2, FLOOR + 2, Z0 + 1), Vector3i(x1 - 2, FLOOR + 2, z1 - 1), Blocks.WORKBENCH)
	w.fill(Vector3i(x0, top, Z0), Vector3i(x1, top, z1), Blocks.WORKBENCH)
	w.fill(Vector3i(x0 + 2, top + 1, Z0 + 1), Vector3i(x0 + 4, top + 2, Z0 + 3), Blocks.IRON)
	w.fill(Vector3i(x1 - 6, top + 1, Z0 + 2), Vector3i(x1 - 2, top + 1, Z0 + 3), Blocks.PLANK)
	# Tools hanging on a rack on the wall behind it.
	w.fill(Vector3i(x0, FLOOR + 15, Z0 - 1), Vector3i(x1, FLOOR + 15, Z0 - 1), Blocks.BEAM)
	for x: int in [x0 + 3, x0 + 8, x0 + 13]:
		w.fill(Vector3i(x, FLOOR + 11, Z0 - 1), Vector3i(x, FLOOR + 14, Z0 - 1), Blocks.BEAM)
		w.fill(Vector3i(x - 1, FLOOR + 10, Z0 - 1), Vector3i(x + 1, FLOOR + 10, Z0 - 1), Blocks.IRON)


# A stone hearth against the wall east of the door, with glowing coals, a bellows, a brick hood
# and a chimney up through the ceiling.
static func _forge(w) -> void:
	var o := FORGE_LO
	var top := CEIL - 1 - FLOOR
	_box(w, o, Vector3i(0, 0, 0), Vector3i(15, 4, 6), Blocks.COBBLE)
	_box(w, o, Vector3i(6, 1, 6), Vector3i(9, 2, 6), Blocks.EMBER)
	_box(w, o, Vector3i(0, 5, 0), Vector3i(15, 11, 1), Blocks.BRICK)
	_box(w, o, Vector3i(3, 5, 2), Vector3i(11, 5, 5), Blocks.EMBER)
	_box(w, o, Vector3i(5, 6, 3), Vector3i(9, 6, 4), Blocks.FIRE)
	_box(w, o, Vector3i(6, 7, 3), Vector3i(8, 7, 3), Blocks.FIRE)
	# The bellows, and a few bars cooling at the other end.
	_box(w, o, Vector3i(13, 5, 2), Vector3i(14, 6, 5), Blocks.SACK)
	_box(w, o, Vector3i(12, 5, 3), Vector3i(12, 5, 4), Blocks.BEAM)
	_box(w, o, Vector3i(13, 7, 5), Vector3i(14, 7, 6), Blocks.BEAM)
	_box(w, o, Vector3i(0, 5, 4), Vector3i(1, 5, 5), Blocks.STEEL)
	_box(w, o, Vector3i(0, 6, 4), Vector3i(1, 6, 4), Blocks.GOLD)
	# Iron posts at the front corners hold up the hood; the chimney runs up from it.
	for x: int in [0, 15]:
		_box(w, o, Vector3i(x, 5, 6), Vector3i(x, 11, 6), Blocks.DARK_IRON)
	_box(w, o, Vector3i(0, 12, 0), Vector3i(15, 14, 6), Blocks.BRICK)
	_box(w, o, Vector3i(0, 12, 6), Vector3i(15, 12, 6), Blocks.DARK_IRON)
	_box(w, o, Vector3i(4, 15, 0), Vector3i(11, top, 3), Blocks.BRICK)
	# Tongs and a hammer hanging from the hood.
	for x: int in [3, 5]:
		_box(w, o, Vector3i(x, 9, 6), Vector3i(x, 11, 6), Blocks.IRON)


static func _box(w, o: Vector3i, lo: Vector3i, hi: Vector3i, b: int) -> void:
	w.fill(o + lo, o + hi, b)


# A coil of rope on a winch beside the door: it lowers you straight back to wherever you were
# when you last went home.
static func _lift(w) -> void:
	var o := LIFT_LO
	_box(w, o, Vector3i(0, 15, 0), Vector3i(1, 16, 1), Blocks.BEAM)
	_box(w, o, Vector3i(0, 3, 0), Vector3i(1, 14, 0), Blocks.ROPE)
	_box(w, o, Vector3i(0, 8, 1), Vector3i(1, 9, 1), Blocks.IRON)
	_box(w, o, Vector3i(0, 0, 0), Vector3i(1, 2, 1), Blocks.CRATE)


static func hanging_lantern(w, tier: int, b: int) -> void:
	var c := center(tier)
	var frame := Blocks.BEAM if b != Blocks.AIR else Blocks.AIR
	w.fill(Vector3i(c.x, CEIL - 3, c.y), Vector3i(c.x, CEIL - 1, c.y), frame)
	w.fill(Vector3i(c.x - 2, CEIL - 4, c.y - 2), Vector3i(c.x + 1, CEIL - 4, c.y + 1), frame)
	w.fill(Vector3i(c.x - 2, CEIL - 7, c.y - 2), Vector3i(c.x + 1, CEIL - 5, c.y + 1), b)
	w.fill(Vector3i(c.x - 1, CEIL - 8, c.y - 1), Vector3i(c.x, CEIL - 8, c.y), frame)


# --- Lights ------------------------------------------------------------------------------------

static func _light(cell: Vector3, color: Color, strength: float, light_range: float, in_house := true, flicker := false) -> Dictionary:
	return {"pos": cell * VOXEL, "color": color * strength, "range": light_range, "min_y": (FLOOR - 1) * VOXEL if in_house else -100.0, "flicker": flicker, "vault": -1}


static func lights(owned: Array, tier: int) -> Array:
	var list := []
	var c := center(tier)
	var r := bounds(tier)
	if owned.has("chandelier"):
		list.append(_light(Vector3(c.x, CEIL - 7, c.y), Color(1.0, 0.85, 0.6), 1.0, 12.0 + tier * 1.5))
	else:
		list.append(_light(Vector3(c.x, CEIL - 6, c.y), WARM, 0.75, 9.0 + tier * 1.5))
	for zc in windows(tier):
		list.append(_light(Vector3(r.position.x + 1.5, FLOOR + 13, zc), Color(0.6, 0.72, 0.9), 0.4, 6.0))
	list.append(_light(Vector3(FORGE_LO.x + 8.0, FLOOR + 8, FORGE_LO.z + 4.5), Color(1.0, 0.5, 0.2), 1.0, 6.0, true, true))
	for k: int in TORCH_STEPS:
		list.append(_light(Vector3(DOOR_X - 4.8, FLOOR - 1 - k + 13, Z0 - LANDING - 2 * k - 2), WARM, 0.7, 5.5, false))
	for x: int in [int(SITE.x) - 19, int(SITE.x) + 17]:
		list.append(_light(Vector3(x + 1.0, SITE_FLOOR + 15, SITE.y), WARM, 0.85, 7.5, false))
	if owned.has("lanterns"):
		for entry: Array in _wall_lanterns(tier):
			var box := _lantern_box(entry)
			list.append(_light((Vector3(box[0]) + Vector3(box[1]) + Vector3.ONE) * 0.5, WARM, 0.45, 6.0))
	if owned.has("fireplace"):
		list.append(_light(Vector3(c.x + 13.0, FLOOR + 2, r.end.y - 3), Color(1.0, 0.55, 0.25), 1.0, 7.0, true, true))
	return list


# --- Decorations -------------------------------------------------------------------------------

# Like put, but never over furniture you've placed.
static func _dput(w, x: int, y: int, z: int, b: int) -> void:
	if not w.furniture.has(w.key(x, y, z)):
		w.put(x, y, z, b)


static func _dfill(w, lo: Vector3i, hi: Vector3i, b: int) -> void:
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				_dput(w, x, y, z, b)


static func apply_decor(w, id: String, tier: int) -> void:
	var r := bounds(tier)
	var c := center(tier)
	var x0 := r.position.x
	var x1 := r.end.x
	var z1 := r.end.y
	match id:
		"plants":
			if x0 + 6 < BENCH_LO.x:
				_plant(w, x0 + 1, Z0 + 1)
			_plant(w, x1 - 5, Z0 + 1)
			_plant(w, x0 + 1, z1 - 5)
			_plant(w, x1 - 5, z1 - 5)
		"lanterns":
			for entry: Array in _wall_lanterns(tier):
				var box := _lantern_box(entry)
				_dfill(w, box[0], box[1], Blocks.LANTERN)
				_dfill(w, Vector3i(box[0].x, FLOOR + 18, box[0].z), Vector3i(box[1].x, FLOOR + 18, box[1].z), Blocks.BEAM)
		"rug":
			var hw := int(r.size.x * 0.28)
			var hd := int(r.size.y * 0.28)
			for z in range(c.y - hd, c.y + hd):
				for x in range(c.x - hw, c.x + hw):
					var border := x < c.x - hw + 2 or x >= c.x + hw - 2 or z < c.y - hd + 2 or z >= c.y + hd - 2
					var stripe := (z - (c.y - hd)) % 8 == 5 and x > c.x - hw + 3 and x < c.x + hw - 4
					w.put(x, FLOOR - 1, z, Blocks.RUG_TRIM if border or stripe else Blocks.RUG)
		"shelves":
			var zs := c.y - 21
			for y: int in [FLOOR + 9, FLOOR + 18]:
				_dfill(w, Vector3i(x1 - 3, y, zs), Vector3i(x1 - 1, y, zs + 41), Blocks.BEAM)
			for z: int in [zs - 1, zs + 42]:
				_dfill(w, Vector3i(x1 - 3, FLOOR, z), Vector3i(x1 - 1, FLOOR + 19, z), Blocks.BEAM)
		"books":
			var rng := RandomNumberGenerator.new()
			rng.seed = 77
			var xa := c.x - 26
			var xb := c.x - 5
			_dfill(w, Vector3i(xa, FLOOR, z1 - 3), Vector3i(xb, FLOOR + 22, z1 - 1), Blocks.BEAM)
			_dfill(w, Vector3i(xa + 1, FLOOR + 1, z1 - 3), Vector3i(xb - 1, FLOOR + 21, z1 - 2), Blocks.AIR)
			for base: int in [FLOOR, FLOOR + 7, FLOOR + 14]:
				_dfill(w, Vector3i(xa + 1, base, z1 - 3), Vector3i(xb - 1, base, z1 - 2), Blocks.BEAM)
				for x in range(xa + 1, xb):
					if rng.randf() < 0.12:
						continue
					var book: int = [Blocks.BOOK_RED, Blocks.BOOK_GREEN, Blocks.BOOK_BLUE][rng.randi_range(0, 2)]
					_dfill(w, Vector3i(x, base + 1, z1 - 3), Vector3i(x, base + rng.randi_range(3, 5), z1 - 2), book)
		"fireplace":
			var xa := c.x + 5
			var xb := c.x + 20
			_dfill(w, Vector3i(xa, FLOOR, z1 - 4), Vector3i(xb, FLOOR + 13, z1 - 1), Blocks.COBBLE)
			_dfill(w, Vector3i(xa + 3, FLOOR, z1 - 4), Vector3i(xb - 3, FLOOR + 8, z1 - 2), Blocks.AIR)
			_dfill(w, Vector3i(xa + 4, FLOOR, z1 - 3), Vector3i(xb - 4, FLOOR, z1 - 2), Blocks.BEAM)
			_dfill(w, Vector3i(xa + 5, FLOOR + 1, z1 - 3), Vector3i(xb - 5, FLOOR + 2, z1 - 3), Blocks.FIRE)
			_dfill(w, Vector3i(xa + 6, FLOOR + 3, z1 - 3), Vector3i(xb - 6, FLOOR + 3, z1 - 3), Blocks.FIRE)
			_dfill(w, Vector3i(xa - 1, FLOOR + 14, z1 - 5), Vector3i(xb + 1, FLOOR + 14, z1 - 1), Blocks.BEAM)
			_dfill(w, Vector3i(xa + 2, FLOOR + 15, z1 - 3), Vector3i(xb - 2, CEIL - 1, z1 - 1), Blocks.COBBLE)
			for z in range(z1 - 7, z1 - 4):
				for x in range(xa - 1, xb + 2):
					w.put(x, FLOOR - 1, z, Blocks.COBBLE)
		"panelling":
			for y in range(FLOOR, CEIL):
				var b := Blocks.PANEL if y < FLOOR + 9 else (Blocks.BEAM if y == FLOOR + 9 else Blocks.WALLPAPER)
				for x in range(x0 - 1, x1 + 1):
					_repaint(w, x, y, Z0 - 1, b)
					_repaint(w, x, y, z1, b)
				for z in range(Z0 - 1, z1 + 1):
					_repaint(w, x0 - 1, y, z, b)
					_repaint(w, x1, y, z, b)
		"chandelier":
			hanging_lantern(w, tier, Blocks.AIR)
			w.fill(Vector3i(c.x, CEIL - 6, c.y), Vector3i(c.x, CEIL - 1, c.y), Blocks.GOLD)
			for z in range(c.y - 10, c.y + 11):
				for x in range(c.x - 10, c.x + 11):
					var d := Vector2(x + 0.5 - c.x, z + 0.5 - c.y).length()
					if absf(d - 8.0) < 0.7:
						w.put(x, CEIL - 8, z, Blocks.GOLD)
			for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for k in range(1, 8):
					w.put(c.x + dir.x * k, CEIL - 7, c.y + dir.y * k, Blocks.GOLD)
			for a in 8:
				var p := Vector2(c.x, c.y) + Vector2.from_angle(a * TAU / 8.0) * 8.0
				w.put(floori(p.x), CEIL - 7, floori(p.y), Blocks.LANTERN)
				w.put(floori(p.x), CEIL - 6, floori(p.y), Blocks.LANTERN)


static func _repaint(w, x: int, y: int, z: int, b: int) -> void:
	if w.block(x, y, z) == Blocks.WALL:
		w.put(x, y, z, b)


static func _hash(x: int, y: int, z: int) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453, 1.0)


# A pot with a round bush of leaves in it.
static func _plant(w, x: int, z: int) -> void:
	_dfill(w, Vector3i(x, FLOOR, z), Vector3i(x + 3, FLOOR + 3, z + 3), Blocks.POT)
	_dfill(w, Vector3i(x + 1, FLOOR + 4, z + 1), Vector3i(x + 2, FLOOR + 5, z + 2), Blocks.BEAM)
	for dz in range(-4, 4):
		for dy in range(-4, 4):
			for dx in range(-4, 4):
				var p := Vector3i(x + 2 + dx, FLOOR + 9 + dy, z + 2 + dz)
				var e := pow((dx + 0.5) / 3.6, 2.0) + pow((dy + 0.5) / 3.3, 2.0) + pow((dz + 0.5) / 3.6, 2.0)
				if e <= 1.0 and not (e > 0.55 and _hash(p.x, p.y, p.z) < 0.25) and w.block(p.x, p.y, p.z) == Blocks.AIR:
					_dput(w, p.x, p.y, p.z, Blocks.LEAF)


# Wall lanterns as [x, z, way into the room]: between the windows, near the east corners,
# beside the door (between it and the workbench) and over the middle of the south wall.
static func _wall_lanterns(tier: int) -> Array:
	var r := bounds(tier)
	var list := []
	var ws := windows(tier)
	for k in ws.size() - 1:
		list.append([r.position.x, (ws[k] + ws[k + 1]) / 2, Vector2i(1, 0)])
	list.append([r.end.x - 1, Z0 + 6, Vector2i(-1, 0)])
	list.append([r.end.x - 1, r.end.y - 7, Vector2i(-1, 0)])
	list.append([DOOR_X - 8, Z0, Vector2i(0, 1)])
	list.append([DOOR_X, r.end.y - 1, Vector2i(0, -1)])
	return list


static func _lantern_box(entry: Array) -> Array:
	var x: int = entry[0]
	var z: int = entry[1]
	var d: Vector2i = entry[2]
	if d.x != 0:
		return [Vector3i(mini(x, x + d.x), FLOOR + 15, z - 1), Vector3i(maxi(x, x + d.x), FLOOR + 17, z)]
	return [Vector3i(x - 1, FLOOR + 15, mini(z, z + d.y)), Vector3i(x, FLOOR + 17, maxi(z, z + d.y))]


# One trophy on the shelves for every kind of treasure found so far.
static func show_trophies(w, owned: Array, found: Dictionary, tier: int) -> void:
	if not owned.has("shelves"):
		return
	var x1 := bounds(tier).end.x
	var zs := center(tier).y - 21
	for t in SHELF_SLOTS:
		var y := FLOOR + 10 if t < 6 else FLOOR + 19
		var z := zs + 1 + (t % 6) * 7
		var info: Dictionary = Treasures.LIST[t]
		var have := int(found.get(t, 0)) > 0
		var trophy := Blocks.TROPHY + int(info["rarity"])
		_dfill(w, Vector3i(x1 - 3, y, z), Vector3i(x1 - 1, y, z + 2), Blocks.GOLD if have else Blocks.AIR)
		_dfill(w, Vector3i(x1 - 3, y + 1, z), Vector3i(x1 - 1, y + 3, z + 2), trophy if have else Blocks.AIR)
		_dput(w, x1 - 2, y + 4, z + 1, trophy if have else Blocks.AIR)


# --- Furniture ---------------------------------------------------------------------------------

# A record of placed furniture: {"id", "type", "x", "z", "rot"}, where (x, z) is the corner of
# its footprint and rot counts quarter turns.
static func furniture_size(type: String, rot: int) -> Vector3i:
	var s: Vector3i = Catalog.FURNITURE[type]["size"]
	return Vector3i(s.z, s.y, s.x) if rot % 2 == 1 else s


# The turn that has a piece of furniture face you when you look along `yaw`.
static func rotation_facing(yaw: float) -> int:
	return posmod(roundi((PI - yaw) / (PI * 0.5)), 4)


# Where a piece of furniture's own cell `l` ends up inside its footprint once turned.
static func _turn(size: Vector3i, rot: int, l: Vector3i) -> Vector3i:
	match rot:
		1:
			return Vector3i(size.z - 1 - l.z, l.y, l.x)
		2:
			return Vector3i(size.x - 1 - l.x, l.y, size.z - 1 - l.z)
		3:
			return Vector3i(l.z, l.y, size.x - 1 - l.x)
	return l


static func can_place_furniture(w, type: String, x: int, z: int, rot: int, tier: int) -> bool:
	var size := furniture_size(type, rot)
	var r := bounds(tier)
	if x < r.position.x or z < r.position.y or x + size.x > r.end.x or z + size.z > r.end.y:
		return false
	# Keep the way in from the stairs clear.
	if z < Z0 + 14 and x + size.x > DOOR_X - 8 and x < DOOR_X + 8:
		return false
	for zz in range(z, z + size.z):
		for xx in range(x, x + size.x):
			for yy in range(FLOOR, FLOOR + size.y):
				if w.block(xx, yy, zz) != Blocks.AIR:
					return false
	return true


# Whether a piece of furniture stands where the workbench, the forge or the rope lift is. Only
# furniture placed before they were built can.
static func blocks_fixture(rec: Dictionary) -> bool:
	var size := furniture_size(rec["type"], rec["rot"])
	var x0: int = rec["x"]
	var z0: int = rec["z"]
	for box: Array in [[BENCH_LO, BENCH_HI], [FORGE_LO, FORGE_HI], [LIFT_LO, LIFT_HI]]:
		var lo: Vector3i = box[0]
		var hi: Vector3i = box[1]
		if x0 <= hi.x and x0 + size.x - 1 >= lo.x and z0 <= hi.z and z0 + size.z - 1 >= lo.z:
			return true
	return false


# The first free place on the floor for a piece of furniture, or (-1, -1).
static func free_spot(w, type: String, rot: int, tier: int) -> Vector2i:
	var r := bounds(tier)
	for z in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			if can_place_furniture(w, type, x, z, rot, tier):
				return Vector2i(x, z)
	return Vector2i(-1, -1)


# The middle of the footprint at floor height, in metres.
static func furniture_center(rec: Dictionary) -> Vector3:
	var size := furniture_size(rec["type"], rec["rot"])
	return Vector3(rec["x"] + size.x * 0.5, FLOOR, rec["z"] + size.z * 0.5) * VOXEL


# Where you stand to use it: just in front, in metres.
static func front_spot(rec: Dictionary) -> Vector3:
	var s: Vector3i = Catalog.FURNITURE[rec["type"]]["size"]
	var l := _turn(s, rec["rot"], Vector3i(s.x / 2, 0, -5))
	return (Vector3(rec["x"] + l.x + 0.5, FLOOR, rec["z"] + l.z + 0.5)) * VOXEL


static func build_furniture(w, rec: Dictionary) -> void:
	var f := {"base": Vector3i(rec["x"], FLOOR, rec["z"]), "size": Catalog.FURNITURE[rec["type"]]["size"], "rot": rec["rot"], "id": rec["id"]}
	match rec["type"]:
		"bed":
			for p: Vector3i in [Vector3i(0, 0, 0), Vector3i(9, 0, 0)]:
				_fbox(w, f, p, p + Vector3i(0, 4, 0), Blocks.BEAM)
			for p: Vector3i in [Vector3i(0, 0, 17), Vector3i(9, 0, 17)]:
				_fbox(w, f, p, p + Vector3i(0, 7, 0), Blocks.BEAM)
			_fbox(w, f, Vector3i(0, 1, 1), Vector3i(0, 2, 16), Blocks.BEAM)
			_fbox(w, f, Vector3i(9, 1, 1), Vector3i(9, 2, 16), Blocks.BEAM)
			_fbox(w, f, Vector3i(1, 1, 0), Vector3i(8, 3, 0), Blocks.BEAM)
			_fbox(w, f, Vector3i(1, 1, 17), Vector3i(8, 6, 17), Blocks.PLANK_DARK)
			_fbox(w, f, Vector3i(0, 7, 17), Vector3i(9, 7, 17), Blocks.BEAM)
			_fbox(w, f, Vector3i(1, 1, 1), Vector3i(8, 1, 16), Blocks.PLANK)
			_fbox(w, f, Vector3i(1, 2, 1), Vector3i(8, 3, 16), Blocks.PILLOW)
			_fbox(w, f, Vector3i(1, 4, 1), Vector3i(8, 4, 11), Blocks.BLANKET)
			_fbox(w, f, Vector3i(1, 3, 1), Vector3i(1, 3, 11), Blocks.BLANKET)
			_fbox(w, f, Vector3i(8, 3, 1), Vector3i(8, 3, 11), Blocks.BLANKET)
			_fbox(w, f, Vector3i(2, 4, 13), Vector3i(7, 5, 15), Blocks.PILLOW)
		"chest":
			_fbox(w, f, Vector3i(0, 0, 0), Vector3i(9, 3, 5), Blocks.CRATE)
			_fbox(w, f, Vector3i(0, 4, 0), Vector3i(9, 4, 5), Blocks.CRATE_BAND)
			_fbox(w, f, Vector3i(0, 5, 0), Vector3i(9, 6, 5), Blocks.CRATE)
			_fbox(w, f, Vector3i(1, 0, 0), Vector3i(1, 6, 5), Blocks.CRATE_BAND)
			_fbox(w, f, Vector3i(8, 0, 0), Vector3i(8, 6, 5), Blocks.CRATE_BAND)
			_fbox(w, f, Vector3i(4, 3, 0), Vector3i(5, 4, 0), Blocks.GOLD)
		"wardrobe":
			_fbox(w, f, Vector3i(0, 0, 0), Vector3i(11, 17, 5), Blocks.PLANK_DARK)
			_fbox(w, f, Vector3i(0, 0, 0), Vector3i(0, 17, 5), Blocks.BEAM)
			_fbox(w, f, Vector3i(11, 0, 0), Vector3i(11, 17, 5), Blocks.BEAM)
			_fbox(w, f, Vector3i(0, 17, 0), Vector3i(11, 17, 5), Blocks.BEAM)
			_fbox(w, f, Vector3i(0, 0, 0), Vector3i(11, 0, 5), Blocks.BEAM)
			_fbox(w, f, Vector3i(1, 1, 0), Vector3i(5, 16, 0), Blocks.PANEL)
			_fbox(w, f, Vector3i(6, 1, 0), Vector3i(10, 16, 0), Blocks.PANEL)
			_fbox(w, f, Vector3i(5, 8, 0), Vector3i(6, 9, 0), Blocks.GOLD)
		"anvil":
			_fbox(w, f, Vector3i(1, 0, 0), Vector3i(6, 2, 4), Blocks.STUMP)
			_fbox(w, f, Vector3i(1, 3, 1), Vector3i(6, 3, 3), Blocks.DARK_IRON)
			_fbox(w, f, Vector3i(2, 4, 1), Vector3i(5, 4, 3), Blocks.DARK_IRON)
			_fbox(w, f, Vector3i(0, 5, 1), Vector3i(6, 5, 3), Blocks.DARK_IRON)
			_fbox(w, f, Vector3i(7, 5, 2), Vector3i(7, 5, 2), Blocks.DARK_IRON)
			_fbox(w, f, Vector3i(0, 6, 1), Vector3i(6, 6, 3), Blocks.STEEL)
		"dummy":
			_fbox(w, f, Vector3i(2, 0, 1), Vector3i(5, 0, 4), Blocks.STUMP)
			_fbox(w, f, Vector3i(3, 1, 2), Vector3i(4, 5, 3), Blocks.BEAM)
			_fbox(w, f, Vector3i(2, 6, 1), Vector3i(5, 10, 4), Blocks.SACK)
			_fbox(w, f, Vector3i(2, 7, 1), Vector3i(5, 7, 4), Blocks.STRAW)
			_fbox(w, f, Vector3i(0, 9, 2), Vector3i(1, 10, 3), Blocks.STRAW)
			_fbox(w, f, Vector3i(6, 9, 2), Vector3i(7, 10, 3), Blocks.STRAW)
			_fbox(w, f, Vector3i(2, 11, 1), Vector3i(5, 14, 4), Blocks.SACK)
			_fbox(w, f, Vector3i(3, 13, 1), Vector3i(3, 13, 1), Blocks.BEAM)
			_fbox(w, f, Vector3i(4, 13, 1), Vector3i(4, 13, 1), Blocks.BEAM)
			_fbox(w, f, Vector3i(3, 9, 1), Vector3i(4, 9, 1), Blocks.BOOK_RED)
			_fbox(w, f, Vector3i(3, 14, 2), Vector3i(4, 14, 3), Blocks.STRAW)
		"map":
			for p: Vector3i in [Vector3i(0, 0, 0), Vector3i(10, 0, 0), Vector3i(0, 0, 6), Vector3i(10, 0, 6)]:
				_fbox(w, f, p, p + Vector3i(1, 5, 1), Blocks.BEAM)
			_fbox(w, f, Vector3i(0, 6, 0), Vector3i(11, 6, 7), Blocks.PLANK_DARK)
			_fbox(w, f, Vector3i(1, 7, 1), Vector3i(10, 7, 6), Blocks.PARCHMENT)
			for p: Vector3i in [Vector3i(2, 7, 5), Vector3i(3, 7, 4), Vector3i(4, 7, 4), Vector3i(5, 7, 3), Vector3i(6, 7, 3), Vector3i(7, 7, 2)]:
				_fbox(w, f, p, p, Blocks.BOOK_BLUE)
			for p: Vector3i in [Vector3i(8, 7, 5), Vector3i(3, 7, 2), Vector3i(9, 7, 4)]:
				_fbox(w, f, p, p, Blocks.LEAF)
			_fbox(w, f, Vector3i(7, 7, 5), Vector3i(7, 7, 5), Blocks.BOOK_RED)
			_fbox(w, f, Vector3i(0, 7, 0), Vector3i(0, 7, 0), Blocks.LANTERN)


# Fills a box of the furniture's own cells and remembers they belong to it.
static func _fbox(w, f: Dictionary, lo: Vector3i, hi: Vector3i, b: int) -> void:
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var c: Vector3i = f["base"] + _turn(f["size"], f["rot"], Vector3i(x, y, z))
				w.put(c.x, c.y, c.z, b)
				w.furniture[w.key(c.x, c.y, c.z)] = f["id"]


static func remove_furniture(w, rec: Dictionary) -> void:
	var size := furniture_size(rec["type"], rec["rot"])
	var lo := Vector3i(rec["x"], FLOOR, rec["z"])
	var hi := lo + size - Vector3i.ONE
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var i: int = w.key(x, y, z)
				if w.furniture.get(i, -1) == rec["id"]:
					w.furniture.erase(i)
					w.put(x, y, z, Blocks.AIR)
