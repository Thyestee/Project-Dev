extends RefCounted
# Hidden rooms: old brick vaults sealed in the ground. Each holds a loot chest, a treasure on a
# pedestal and guards who wake up when you break in. Deeper rooms are bigger, better guarded and
# better stocked; the deepest is the Warden's throne room. Coordinates are cells; `w` is the world.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const House := preload("res://scripts/house.gd")

const VOXEL := 0.125
const FLOOR := 344
const WORLD_SIZE := 384        # World.SX and World.SZ

# Inside size in cubes, floor depth in metres below the house floor, the guards, and for each
# loot chest the odds of it being uncommon, rare, epic or legendary.
const SPECS := [
	{"name": "Crypt", "size": Vector3i(44, 26, 40), "depth": [6.0, 12.0], "guards": ["skeleton", "skeleton", "spider"], "chests": [[70, 27, 3, 0]]},
	{"name": "Crypt", "size": Vector3i(40, 26, 44), "depth": [7.0, 14.0], "guards": ["skeleton", "skeleton", "skeleton"], "chests": [[70, 27, 3, 0]]},
	{"name": "Old hall", "size": Vector3i(60, 30, 52), "depth": [14.0, 22.0], "guards": ["skeleton", "skeleton", "archer", "spider"], "chests": [[35, 45, 17, 3]]},
	{"name": "Old hall", "size": Vector3i(52, 30, 60), "depth": [15.0, 24.0], "guards": ["skeleton", "archer", "archer", "spider", "spider"], "chests": [[35, 45, 17, 3]]},
	{"name": "Sanctum", "size": Vector3i(68, 34, 60), "depth": [23.0, 30.0], "guards": ["skeleton", "skeleton", "archer", "golem"], "chests": [[0, 45, 42, 13]]},
	{"name": "Sanctum", "size": Vector3i(60, 34, 68), "depth": [25.0, 32.0], "guards": ["archer", "archer", "spider", "golem"], "chests": [[0, 45, 42, 13]]},
	{"name": "Throne room", "size": Vector3i(88, 40, 80), "depth": [33.0, 37.0], "guards": ["warden", "skeleton", "skeleton", "archer", "archer"], "chests": [[0, 0, 40, 60], [0, 30, 55, 15]], "throne": true},
]

const TORCH_COLOR := Color(1.0, 0.6, 0.28)


static func generate(w, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for spec: Dictionary in SPECS:
		var size: Vector3i = spec["size"]
		var depth: Array = spec["depth"]
		for attempt in 80:
			var d := rng.randf_range(float(depth[0]), float(depth[1]))
			var lo := Vector3i(rng.randi_range(24, WORLD_SIZE - 24 - size.x), FLOOR - int(d / VOXEL), rng.randi_range(24, WORLD_SIZE - 24 - size.z))
			var hi := lo + size - Vector3i.ONE
			if _fits(w, list, lo, hi):
				var v := {"index": list.size(), "name": spec["name"], "lo": lo, "hi": hi, "depth": d, "throne": spec.get("throne", false),
					"chests": [], "spawns": [], "lights": [], "treasure": -1,
					"center": (Vector3(lo) + Vector3(size) * 0.5) * VOXEL}
				_build(w, v, spec, rng)
				list.append(v)
				break
	return list


# Clear of the stairs and the dig site, of the other rooms and of the caves.
static func _fits(w, others: Array, lo: Vector3i, hi: Vector3i) -> bool:
	var top := hi.y + 3
	if top > House.SITE_FLOOR - 64 and hi.x + 16 > House.DOOR_X - 40 and lo.x - 16 < House.DOOR_X + 40 and hi.z + 16 > 60 and lo.z - 16 < House.Z0 + 8:
		return false
	for o: Dictionary in others:
		var olo: Vector3i = o["lo"] - Vector3i(26, 26, 26)
		var ohi: Vector3i = o["hi"] + Vector3i(26, 26, 26)
		if lo.x <= ohi.x and hi.x >= olo.x and lo.y <= ohi.y and hi.y >= olo.y and lo.z <= ohi.z and hi.z >= olo.z:
			return false
	var air := 0
	for k in 6:
		for j in 6:
			for i in 6:
				var p := Vector3(lerpf(lo.x - 2, hi.x + 2, i / 5.0), lerpf(lo.y - 2, hi.y + 2, j / 5.0), lerpf(lo.z - 2, hi.z + 2, k / 5.0))
				if not Blocks.is_natural(w.block(int(p.x), int(p.y), int(p.z))):
					air += 1
	return air <= 2


static func _build(w, v: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var lo: Vector3i = v["lo"]
	var hi: Vector3i = v["hi"]
	var size := hi - lo + Vector3i.ONE
	var throne: bool = v["throne"]
	# A shell of old brick two cubes thick, with patches of moss.
	w.fill(lo - Vector3i(2, 2, 2), hi + Vector3i(2, 2, 2), Blocks.VAULT_BRICK)
	w.fill(lo, hi, Blocks.AIR)
	for n in size.x * size.z / 40:
		var face := rng.randi_range(0, 4)
		var c := Vector3i(rng.randi_range(lo.x, hi.x), rng.randi_range(lo.y, hi.y), rng.randi_range(lo.z, hi.z))
		match face:
			0:
				c.x = lo.x - 1
			1:
				c.x = hi.x + 1
			2:
				c.z = lo.z - 1
			3:
				c.z = hi.z + 1
			4:
				c.y = hi.y + 1
		for o: Vector3i in [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(1, 1, 0), Vector3i(0, 1, 1)]:
			var p := c + o
			if w.block(p.x, p.y, p.z) == Blocks.VAULT_BRICK and rng.randf() < 0.7:
				w.put(p.x, p.y, p.z, Blocks.VAULT_MOSS)
	# A chequered floor of big tiles.
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			var tile := ((x - lo.x) / 4 + (z - lo.z) / 4) % 2 == 0
			w.put(x, lo.y - 1, z, Blocks.VAULT_TILE if tile else Blocks.VAULT_FLOOR)
	# Pillars along the north and south walls, torches between them.
	var columns: Array[int] = []
	var x := lo.x
	while x + 3 <= hi.x + 1:
		columns.append(x)
		x += 16
	if columns[-1] != hi.x - 2:
		columns.append(hi.x - 2)
	for px in columns:
		for pz: int in [lo.z, hi.z - 2]:
			w.fill(Vector3i(px, lo.y, pz), Vector3i(px + 2, hi.y, pz + 2), Blocks.VAULT_PILLAR)
	for k in range(columns.size() - 1):
		var tx := (columns[k] + columns[k + 1] + 2) / 2
		for side: int in [0, 1]:
			var z := lo.z if side == 0 else hi.z
			_torch(w, v, Vector3i(tx, lo.y + 14, z))
	for side: int in [0, 1]:
		var tx := lo.x if side == 0 else hi.x
		_torch(w, v, Vector3i(tx, lo.y + 14, (lo.z + hi.z) / 2))
	# Cobwebs in the top corners, bones, urns.
	for corner: Vector2i in [Vector2i(lo.x, lo.z), Vector2i(hi.x, lo.z), Vector2i(lo.x, hi.z), Vector2i(hi.x, hi.z)]:
		for dz in 5:
			for dx in 5:
				for dy in 5:
					if dx + dy + dz < 6 and rng.randf() < 0.55:
						var p := Vector3i(corner.x + (dx if corner.x == lo.x else -dx), hi.y - dy, corner.y + (dz if corner.y == lo.z else -dz))
						if w.block(p.x, p.y, p.z) == Blocks.AIR:
							w.put(p.x, p.y, p.z, Blocks.WEB)
	for n in 6:
		var p := Vector3i(rng.randi_range(lo.x + 4, hi.x - 4), lo.y, rng.randi_range(lo.z + 4, hi.z - 4))
		for k in rng.randi_range(2, 5):
			var q := p + Vector3i(rng.randi_range(-2, 2), 0, rng.randi_range(-2, 2))
			if w.block(q.x, q.y, q.z) == Blocks.AIR:
				w.put(q.x, q.y, q.z, Blocks.BONE)
	for n in 4:
		var along := rng.randi_range(lo.x + 4, hi.x - 6)
		var uz := lo.z + 3 if rng.randf() < 0.5 else hi.z - 4
		if w.block(along, lo.y, uz) == Blocks.AIR and w.block(along + 1, lo.y, uz + 1) == Blocks.AIR:
			w.fill(Vector3i(along, lo.y, uz), Vector3i(along + 1, lo.y + 2, uz + 1), Blocks.URN)
	# Banners on the back wall.
	for bx: int in [lo.x + size.x / 4 - 2, hi.x - size.x / 4 - 1]:
		w.fill(Vector3i(bx, hi.y - 12, hi.z), Vector3i(bx + 3, hi.y - 2, hi.z), Blocks.BANNER)
		w.fill(Vector3i(bx, hi.y - 13, hi.z), Vector3i(bx + 3, hi.y - 13, hi.z), Blocks.GOLD)
	var cx := (lo.x + hi.x + 1) / 2
	# The throne room has a throne against the back wall.
	if throne:
		w.fill(Vector3i(cx - 6, lo.y, hi.z - 9), Vector3i(cx + 5, lo.y + 5, hi.z - 2), Blocks.VAULT_PILLAR)
		w.fill(Vector3i(cx - 6, lo.y + 6, hi.z - 3), Vector3i(cx + 5, lo.y + 20, hi.z - 2), Blocks.VAULT_PILLAR)
		w.fill(Vector3i(cx - 4, lo.y + 6, hi.z - 8), Vector3i(cx + 3, lo.y + 6, hi.z - 4), Blocks.BANNER)
		w.fill(Vector3i(cx - 4, lo.y + 7, hi.z - 4), Vector3i(cx + 3, lo.y + 18, hi.z - 4), Blocks.BANNER)
		w.fill(Vector3i(cx - 6, lo.y + 21, hi.z - 3), Vector3i(cx + 5, lo.y + 21, hi.z - 2), Blocks.GOLD)
	# Loot chests against the back wall.
	var chests: Array = spec["chests"]
	var chest_x := [cx - 4]
	if chests.size() > 1:
		chest_x = [cx - 20, cx + 12]
	for k in chests.size():
		var rarity := _roll_rarity(chests[k], rng)
		var clo := Vector3i(chest_x[k], lo.y, hi.z - 5 - (0 if not throne else 4))
		_loot_chest(w, clo, rarity)
		v["chests"].append({"lo": clo, "hi": clo + Vector3i(7, 5, 5), "rarity": rarity})
	# A treasure on a pedestal in the middle.
	var t := Treasures.CROWN if throne else _treasure_for(float(v["depth"]), rng)
	var chest: bool = Treasures.LIST[t]["chest"]
	var tsize: Vector3i = w.treasure_size(chest)
	var pz := (lo.z + hi.z + 1) / 2 - (6 if throne else 0)
	var plo := Vector3i(cx - tsize.x / 2 - 1, lo.y, pz - tsize.z / 2 - 1)
	w.fill(plo, plo + Vector3i(tsize.x + 1, 4, tsize.z + 1), Blocks.VAULT_PILLAR)
	v["treasure"] = w.treasure_list.size()
	w.bury(t, plo + Vector3i(1, 5, 1), tsize, chest, v["index"])
	# The guards, spread over the floor away from the walls.
	var guards: Array = spec["guards"]
	for k in guards.size():
		var type: String = guards[k]
		var p: Vector3
		if type == "warden":
			p = Vector3(cx, lo.y, hi.z - 18)
		else:
			p = Vector3(rng.randf_range(lo.x + 8, hi.x - 8), lo.y, rng.randf_range(lo.z + 8, hi.z - 12))
			if absf(p.x - cx) < 9.0 and absf(p.z - pz) < 9.0:
				p.x += 14.0 if p.x > cx else -14.0
		v["spawns"].append({"type": type, "pos": p * VOXEL})


static func _torch(w, v: Dictionary, c: Vector3i) -> void:
	w.fill(c, c + Vector3i(0, 1, 0), Blocks.TORCH)
	w.put(c.x, c.y - 1, c.z, Blocks.IRON)
	var lo: Vector3i = v["lo"]
	v["lights"].append({"pos": (Vector3(c) + Vector3(0.5, 1.0, 0.5)) * VOXEL, "color": TORCH_COLOR * 0.85, "range": 6.5,
		"min_y": (lo.y - 1) * VOXEL, "flicker": true, "vault": v["index"]})


# An old chest 8 cubes wide whose trim glows in the colour of what's inside.
static func _loot_chest(w, lo: Vector3i, rarity: int) -> void:
	var hi := lo + Vector3i(7, 5, 5)
	var trim := Blocks.LOOT_TRIM + rarity - 1
	w.fill(lo, hi, Blocks.LOOT_CHEST)
	w.fill(Vector3i(lo.x, lo.y + 3, lo.z), Vector3i(hi.x, lo.y + 3, hi.z), trim)
	for x: int in [lo.x, hi.x]:
		w.fill(Vector3i(x, lo.y, lo.z), Vector3i(x, hi.y, lo.z), trim)
		w.fill(Vector3i(x, lo.y, hi.z), Vector3i(x, hi.y, hi.z), trim)
	w.fill(Vector3i(lo.x + 3, lo.y + 2, lo.z), Vector3i(lo.x + 4, lo.y + 3, lo.z), Blocks.LOOT_LOCK)


# Recolours an emptied chest's trim.
static func mark_chest_empty(w, chest: Dictionary) -> void:
	var lo: Vector3i = chest["lo"]
	var hi: Vector3i = chest["hi"]
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var b: int = w.block(x, y, z)
				if b >= Blocks.LOOT_TRIM and b < Blocks.LOOT_TRIM + 4:
					w.put(x, y, z, Blocks.LOOT_EMPTY)


static func chest_at(v: Dictionary, c: Vector3i) -> int:
	var chests: Array = v["chests"]
	for k in chests.size():
		var lo: Vector3i = chests[k]["lo"]
		var hi: Vector3i = chests[k]["hi"]
		if c.x >= lo.x and c.x <= hi.x and c.y >= lo.y and c.y <= hi.y and c.z >= lo.z and c.z <= hi.z:
			return k
	return -1


static func _roll_rarity(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for x in weights:
		total += float(x)
	var roll := rng.randf() * total
	for k in weights.size():
		roll -= float(weights[k])
		if roll < 0.0:
			return k + 1
	return 1


# A treasure that belongs at this depth.
static func _treasure_for(depth: float, rng: RandomNumberGenerator) -> int:
	var options: Array[int] = []
	var total := 0.0
	for t in Treasures.LIST.size():
		var range_: Array = Treasures.LIST[t]["depth"]
		if t != Treasures.CROWN and depth >= float(range_[0]) - 2.0 and depth <= float(range_[1]) + 4.0:
			options.append(t)
			total += float(Treasures.LIST[t]["weight"])
	if options.is_empty():
		return Treasures.pick(rng)
	var roll := rng.randf() * total
	for t in options:
		roll -= float(Treasures.LIST[t]["weight"])
		if roll < 0.0:
			return t
	return options[-1]
