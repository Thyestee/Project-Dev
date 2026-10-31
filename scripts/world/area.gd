extends Node2D
## A place you can walk around: tile ground drawn in chunks, y-sorted objects (trees,
## furniture, the player...), hit effects and lighting. Filled in by world_gen.gd.

const Data := preload("res://scripts/game_data.gd")
const EntityScript := preload("res://scripts/world/entity.gd")
const TILE := Data.TILE
const CHUNK := 16
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var kind := ""
var width := 0
var height := 0
var tiles := PackedByteArray()
var vein_ore := {}      # Vector2i -> vein id ("coal", "copper"...)
var tile_hp := {}       # Vector2i -> remaining hp of a vein being dug
var occupants := {}     # Vector2i -> entity covering that tile
var windows: Array = [] # house only: wall columns with a window
var spawn := Vector2.ZERO
var game
var entities: Node2D

var _chunks := {}
var _fx: Node2D
var _modulate: CanvasModulate
var _particles: Array = []
var _floaters: Array = []
var _rng := RandomNumberGenerator.new()


func setup(area_kind: String, w: int, h: int, fill: int) -> void:
	kind = area_kind
	width = w
	height = h
	tiles.resize(w * h)
	tiles.fill(fill)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)


func _ready() -> void:
	_rng.randomize()
	_modulate = CanvasModulate.new()
	add_child(_modulate)
	for cy in ceili(height / float(CHUNK)):
		for cx in ceili(width / float(CHUNK)):
			var chunk := Node2D.new()
			chunk.z_index = -10
			chunk.draw.connect(_draw_chunk.bind(chunk, Vector2i(cx, cy)))
			add_child(chunk)
			_chunks[Vector2i(cx, cy)] = chunk
	_fx = Node2D.new()
	_fx.z_index = 20
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


func set_ambient(color: Color) -> void:
	_modulate.color = color


# --- Tiles -------------------------------------------------------------------

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func tile_at(c: Vector2i) -> int:
	if not in_bounds(c):
		return Data.T_VOID
	return tiles[c.y * width + c.x]


func set_tile(c: Vector2i, t: int) -> void:
	if not in_bounds(c):
		return
	tiles[c.y * width + c.x] = t
	if is_inside_tree():
		_redraw_around(c)


func set_vein(c: Vector2i, ore: String) -> void:
	set_tile(c, Data.T_VEIN)
	vein_ore[c] = ore


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE)


func is_solid(c: Vector2i) -> bool:
	if tile_at(c) in Data.SOLID_TILES:
		return true
	var e = occupants.get(c)
	return e != null and e.solid


func _redraw_around(c: Vector2i) -> void:
	# Wall faces depend on the tile below, so neighbours' chunks may change too.
	for o in [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN]:
		var cc: Vector2i = (c + o) / CHUNK
		if _chunks.has(cc):
			_chunks[cc].queue_redraw()


# --- Entities ----------------------------------------------------------------

func add_entity(entity_kind: String, cell: Vector2i) -> Node2D:
	var e = EntityScript.new()
	e.kind = entity_kind
	e.cell = cell
	e.size = Data.entity_size(entity_kind)
	e.area = self
	e.solid = not (entity_kind in Data.NON_SOLID)
	if Data.OBJECTS.has(entity_kind):
		e.hp = float(Data.OBJECTS[entity_kind]["hp"])
		e.max_hp = e.hp
	e.position = Vector2((cell.x + e.size.x * 0.5) * TILE, (cell.y + e.size.y) * TILE - 1)
	for y in e.size.y:
		for x in e.size.x:
			occupants[cell + Vector2i(x, y)] = e
	entities.add_child(e)
	return e


func remove_entity(e) -> void:
	for y in e.size.y:
		for x in e.size.x:
			var c: Vector2i = e.cell + Vector2i(x, y)
			if occupants.get(c) == e:
				occupants.erase(c)
	entities.remove_child(e)
	e.queue_free()


func entity_at(c: Vector2i):
	return occupants.get(c)


func footprint(e) -> Rect2:
	return Rect2(Vector2(e.cell) * TILE, Vector2(e.size) * TILE)


## True when every tile under the footprint is free floor and it doesn't overlap `avoid`.
func can_place(cell: Vector2i, size: Vector2i, avoid := Rect2()) -> bool:
	for y in size.y:
		for x in size.x:
			var c := cell + Vector2i(x, y)
			if tile_at(c) != Data.T_PLANKS or occupants.has(c):
				return false
	if avoid.has_area() and Rect2(Vector2(cell) * TILE, Vector2(size) * TILE).intersects(avoid):
		return false
	return true


func nearest_interactable(p: Vector2, max_dist: float):
	var best = null
	var best_d := max_dist
	for e in entities.get_children():
		var k = e.get("kind")
		if k == null or not Data.INTERACTIONS.has(k):
			continue
		var r := footprint(e)
		var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var d := p.distance_to(q)
		if d <= best_d:
			best_d = d
			best = e
	return best


# --- Movement ----------------------------------------------------------------

## Moves a square body of half-size `r` by `motion`, sliding along solid tiles.
func move_body(pos: Vector2, motion: Vector2, r: float) -> Vector2:
	var p := pos
	if motion.x != 0.0:
		var nx := p + Vector2(motion.x, 0)
		if not _blocked(nx, r):
			p = nx
		else:
			if motion.x > 0.0:
				p.x = floorf((p.x + r + motion.x) / TILE) * TILE - r
			else:
				p.x = (floorf((p.x - r + motion.x) / TILE) + 1.0) * TILE + r + 0.01
			if _blocked(p, r):
				p.x = pos.x
	if motion.y != 0.0:
		var ny := p + Vector2(0, motion.y)
		if not _blocked(ny, r):
			p = ny
		else:
			var before := p.y
			if motion.y > 0.0:
				p.y = floorf((p.y + r + motion.y) / TILE) * TILE - r
			else:
				p.y = (floorf((p.y - r + motion.y) / TILE) + 1.0) * TILE + r + 0.01
			if _blocked(p, r):
				p.y = before
	return p


func _blocked(p: Vector2, r: float) -> bool:
	var x0 := floori((p.x - r) / TILE)
	var x1 := floori((p.x + r - 0.01) / TILE)
	var y0 := floori((p.y - r) / TILE)
	var y1 := floori((p.y + r - 0.01) / TILE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if is_solid(Vector2i(x, y)):
				return true
	return false


# --- Hitting -----------------------------------------------------------------

## What could be hit at this tile: {name, tool, tier, rect, hp, max_hp}, or {} for nothing.
func hit_info(c: Vector2i) -> Dictionary:
	var e = occupants.get(c)
	if e != null and Data.OBJECTS.has(e.kind):
		var o: Dictionary = Data.OBJECTS[e.kind]
		return {"name": o["name"], "tool": o["tool"], "tier": o["tier"], "rect": footprint(e),
			"hp": e.hp, "max_hp": e.max_hp}
	if tile_at(c) == Data.T_VEIN:
		var v: Dictionary = Data.VEINS[vein_ore[c]]
		var max_hp := float(v["hp"])
		return {"name": v["name"], "tool": "pickaxe", "tier": v["tier"],
			"rect": Rect2(Vector2(c) * TILE, Vector2(TILE, TILE)), "hp": float(tile_hp.get(c, max_hp)), "max_hp": max_hp}
	return {}


## Hits the tile with a tool. Returns {"drops": {item: n}, "at": pos}, {"problem": text},
## {"hit": true} when it took damage, or {} when there was nothing there.
func hit(c: Vector2i, tool: Dictionary) -> Dictionary:
	var info := hit_info(c)
	if info.is_empty():
		if tile_at(c) == Data.T_CAVE_WALL and tool["kind"] == "pickaxe":
			_spawn_particles(cell_center(c), Color(0.6, 0.58, 0.55), 3, 70.0)
			return {"problem": "This rock is too hard to dig. Follow the ore veins and break boulders."}
		return {}
	var problem := Data.tool_problem(info, tool)
	if problem != "":
		_spawn_particles(info["rect"].get_center(), Color(0.8, 0.8, 0.8), 3, 60.0)
		return {"problem": problem}
	var power := float(tool["power"])
	var e = occupants.get(c)
	if e != null and Data.OBJECTS.has(e.kind):
		var o: Dictionary = Data.OBJECTS[e.kind]
		var where: Vector2 = e.position + Vector2(0, -14)
		e.hp -= power
		e.shake()
		_spawn_particles(where, e.particle_color(), 6, 110.0)
		if e.hp > 0.0:
			return {"hit": true}
		_spawn_particles(where, e.particle_color(), 16, 170.0)
		if e.kind != "boulder":
			_spawn_particles(where + Vector2(0, -20), Color(0.3, 0.55, 0.25), 14, 150.0)
		remove_entity(e)
		return {"drops": _roll_drops(o["drops"]), "at": where}

	var ore: String = vein_ore[c]
	var v: Dictionary = Data.VEINS[ore]
	var ore_color: Color = Data.ITEMS[v["item"]]["color"]
	var hp: float = float(tile_hp.get(c, v["hp"])) - power
	_spawn_particles(cell_center(c), ore_color, 4, 100.0)
	if hp > 0.0:
		tile_hp[c] = hp
		return {"hit": true}
	tile_hp.erase(c)
	vein_ore.erase(c)
	set_tile(c, Data.T_CAVE_FLOOR)
	_spawn_particles(cell_center(c), ore_color, 10, 160.0)
	_spawn_particles(cell_center(c), Color(0.45, 0.42, 0.4), 10, 160.0)
	return {"drops": _roll_drops({v["item"]: v["drop"]}), "at": cell_center(c)}


func _roll_drops(drops: Dictionary) -> Dictionary:
	var result := {}
	for id in drops:
		var r: Array = drops[id]
		result[id] = _rng.randi_range(int(r[0]), int(r[1]))
	return result


# --- Effects -----------------------------------------------------------------

func add_floater(pos: Vector2, text: String, color: Color) -> void:
	_floaters.append({"pos": pos, "text": text, "color": color, "life": 1.4})


func _spawn_particles(at: Vector2, color: Color, count: int, speed: float) -> void:
	for i in count:
		_particles.append({
			"pos": at + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)),
			"vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, 1.0) * speed + Vector2(0, -50),
			"life": _rng.randf_range(0.35, 0.7),
			"size": _rng.randf_range(2.0, 4.0),
			"color": color,
		})


func _process(delta: float) -> void:
	for p in _particles:
		p["vel"] += Vector2(0, 420) * delta
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
	_particles = _particles.filter(func(p): return p["life"] > 0.0)
	for f in _floaters:
		f["pos"] += Vector2(0, -24) * delta
		f["life"] -= delta
	_floaters = _floaters.filter(func(f): return f["life"] > 0.0)
	_fx.queue_redraw()


func _draw_fx() -> void:
	if game != null:
		game.draw_world_overlay(_fx)
	# Cracks on veins that are being dug.
	for c in tile_hp:
		var v: Dictionary = Data.VEINS[vein_ore[c]]
		var damage := 1.0 - float(tile_hp[c]) / float(v["hp"])
		var center := cell_center(c)
		for i in int(damage * 5.0) + 1:
			var dir := Vector2.from_angle(_hash(c.x, c.y, 70 + i) * TAU)
			var reach := 6.0 + 9.0 * damage
			_fx.draw_polyline(PackedVector2Array([center, center + dir * reach * 0.5 + dir.orthogonal() * 2.0, center + dir * reach]),
				Color(0, 0, 0, 0.7), 1.5)
	for p in _particles:
		var col: Color = p["color"]
		col.a = clampf(p["life"] * 2.5, 0.0, 1.0)
		var s: float = p["size"]
		_fx.draw_rect(Rect2(p["pos"] - Vector2(s, s) * 0.5, Vector2(s, s)), col)
	var font := ThemeDB.fallback_font
	for f in _floaters:
		var col: Color = f["color"]
		col.a = clampf(f["life"], 0.0, 1.0)
		var pos: Vector2 = f["pos"] + Vector2(-70, 0)
		_fx.draw_string_outline(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 140, 12, 3, Color(0, 0, 0, col.a))
		_fx.draw_string(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 140, 12, col)


# --- Ground drawing ------------------------------------------------------------

func _hash(x: int, y: int, k: int) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + k * 37.719) * 43758.5453
	return v - floor(v)


func _draw_chunk(ci: Node2D, cc: Vector2i) -> void:
	var x0 := cc.x * CHUNK
	var y0 := cc.y * CHUNK
	for y in range(y0, mini(y0 + CHUNK, height)):
		for x in range(x0, mini(x0 + CHUNK, width)):
			_draw_tile(ci, x, y)


func _draw_tile(ci: Node2D, x: int, y: int) -> void:
	var c := Vector2i(x, y)
	var r := Rect2(x * TILE, y * TILE, TILE, TILE)
	var t := tile_at(c)
	var h := _hash(x, y, 1)
	if t == Data.T_GRASS:
		ci.draw_rect(r, Color(0.36, 0.56, 0.27).lerp(Color(0.31, 0.5, 0.24), h))
		for i in 3:
			var p := r.position + Vector2(_hash(x, y, 10 + i), _hash(x, y, 20 + i)) * (TILE - 6) + Vector2(3, 3)
			ci.draw_line(p, p + Vector2(-1, -4), Color(0.26, 0.44, 0.2), 1.0)
			ci.draw_line(p, p + Vector2(2, -3), Color(0.26, 0.44, 0.2), 1.0)
		if _hash(x, y, 5) > 0.92:
			var p := r.position + Vector2(_hash(x, y, 6), _hash(x, y, 7)) * (TILE - 10) + Vector2(5, 5)
			var petal: Color = [Color(0.95, 0.9, 0.4), Color(0.95, 0.6, 0.75), Color(0.9, 0.9, 0.95)][int(_hash(x, y, 8) * 3.0)]
			for i in 4:
				ci.draw_circle(p + Vector2.from_angle(i * TAU / 4.0) * 2.0, 1.8, petal)
			ci.draw_circle(p, 1.2, Color(0.9, 0.7, 0.2))
	elif t == Data.T_PATH:
		ci.draw_rect(r, Color(0.56, 0.45, 0.3).lerp(Color(0.5, 0.4, 0.27), h))
		for i in 3:
			var p := r.position + Vector2(_hash(x, y, 30 + i), _hash(x, y, 40 + i)) * (TILE - 6) + Vector2(3, 3)
			ci.draw_circle(p, 1.5, Color(0.45, 0.36, 0.24))
	elif t == Data.T_WATER:
		ci.draw_rect(r, Color(0.2, 0.42, 0.62).lerp(Color(0.18, 0.38, 0.58), h))
		if tile_at(c + Vector2i.UP) != Data.T_WATER:
			ci.draw_rect(Rect2(r.position, Vector2(TILE, 4)), Color(0.45, 0.62, 0.75))
		var p := r.position + Vector2(_hash(x, y, 9) * 18 + 4, _hash(x, y, 11) * 22 + 6)
		ci.draw_line(p, p + Vector2(8, 0), Color(0.5, 0.7, 0.85, 0.6), 1.0)
	elif t == Data.T_THICKET:
		ci.draw_rect(r, Color(0.12, 0.24, 0.12))
		for i in 2:
			var p := r.position + Vector2(_hash(x, y, 50 + i), _hash(x, y, 60 + i)) * TILE
			ci.draw_circle(p, 12.0 + _hash(x, y, 70 + i) * 6.0, Color(0.15, 0.3, 0.15).lerp(Color(0.1, 0.22, 0.12), _hash(x, y, 80 + i)))
	elif t == Data.T_CAVE_FLOOR:
		ci.draw_rect(r, Color(0.24, 0.21, 0.19).lerp(Color(0.21, 0.18, 0.16), h))
		for i in 2:
			var p := r.position + Vector2(_hash(x, y, 30 + i), _hash(x, y, 40 + i)) * (TILE - 6) + Vector2(3, 3)
			ci.draw_circle(p, 1.5, Color(0.22, 0.2, 0.18))
	elif t == Data.T_CAVE_WALL or t == Data.T_VEIN:
		_draw_rock(ci, c, r, h)
	elif t == Data.T_PLANKS:
		ci.draw_rect(r, Color(0.56, 0.39, 0.24).lerp(Color(0.52, 0.36, 0.22), h))
		for i in 4:
			ci.draw_line(r.position + Vector2(0, i * 8), r.position + Vector2(TILE, i * 8), Color(0.42, 0.28, 0.16), 1.0)
			var seam := r.position.x + fmod(_hash(x, y + i, 3) * TILE + i * 11.0, TILE)
			ci.draw_line(Vector2(seam, r.position.y + i * 8), Vector2(seam, r.position.y + i * 8 + 8), Color(0.42, 0.28, 0.16), 1.0)
	elif t == Data.T_HOUSE_WALL:
		_draw_house_wall(ci, c, r)
	else:
		ci.draw_rect(r, Color.BLACK)


func _draw_rock(ci: Node2D, c: Vector2i, r: Rect2, h: float) -> void:
	var rock := Color(0.44, 0.4, 0.37).lerp(Color(0.4, 0.36, 0.34), h)
	ci.draw_rect(r, rock)
	if not (tile_at(c + Vector2i.UP) in [Data.T_CAVE_WALL, Data.T_VEIN, Data.T_VOID]):
		ci.draw_rect(Rect2(r.position, Vector2(TILE, 3)), rock.lightened(0.15))
	# Rock seen from the floor below shows its darker front face.
	var below := tile_at(c + Vector2i.DOWN)
	if not (below in [Data.T_CAVE_WALL, Data.T_VEIN, Data.T_VOID]):
		ci.draw_rect(Rect2(r.position + Vector2(0, TILE - 11), Vector2(TILE, 11)), rock.darkened(0.35))
	for i in 2:
		var p := r.position + Vector2(_hash(c.x, c.y, 12 + i), _hash(c.x, c.y, 22 + i)) * (TILE - 14) + Vector2(4, 3)
		ci.draw_line(p, p + Vector2(6, 3), rock.darkened(0.2), 1.0)
	if tile_at(c) == Data.T_VEIN:
		var v: Dictionary = Data.VEINS[vein_ore[c]]
		var col: Color = Data.ITEMS[v["item"]]["color"]
		for i in 5:
			var p := r.get_center() + Vector2(_hash(c.x, c.y, 30 + i) - 0.5, _hash(c.x, c.y, 40 + i) - 0.5) * 22.0 + Vector2(0, -3)
			var s := 2.0 + _hash(c.x, c.y, 50 + i) * 2.5
			ci.draw_circle(p, s, col.darkened(0.3))
			ci.draw_circle(p - Vector2(0.6, 0.6), s * 0.7, col)
			ci.draw_circle(p - Vector2(s * 0.3, s * 0.3), s * 0.28, col.lightened(0.55))


func _draw_house_wall(ci: Node2D, c: Vector2i, r: Rect2) -> void:
	var below := tile_at(c + Vector2i.DOWN)
	if below == Data.T_PLANKS or (below == Data.T_HOUSE_WALL and tile_at(c + Vector2i(0, 2)) == Data.T_PLANKS):
		# Wall face with wallpaper, seen from inside the room.
		ci.draw_rect(r, Color(0.66, 0.55, 0.44))
		for i in 4:
			ci.draw_line(r.position + Vector2(i * 8 + 4, 0), r.position + Vector2(i * 8 + 4, TILE), Color(0.62, 0.5, 0.4), 2.0)
		if below == Data.T_PLANKS:
			ci.draw_rect(Rect2(r.position + Vector2(0, TILE - 6), Vector2(TILE, 6)), Color(0.42, 0.28, 0.16))
		if c.x in windows and below == Data.T_PLANKS:
			var win := Rect2(r.position + Vector2(4, -20), Vector2(TILE - 8, TILE + 8))
			ci.draw_rect(win.grow(2), Color(0.4, 0.27, 0.15))
			ci.draw_rect(win, Color(0.62, 0.8, 0.95))
			ci.draw_line(Vector2(win.get_center().x, win.position.y), Vector2(win.get_center().x, win.end.y), Color(0.4, 0.27, 0.15), 2.0)
			ci.draw_line(Vector2(win.position.x, win.get_center().y), Vector2(win.end.x, win.get_center().y), Color(0.4, 0.27, 0.15), 2.0)
	else:
		ci.draw_rect(r, Color(0.28, 0.2, 0.16))
		ci.draw_rect(Rect2(r.position, Vector2(TILE, TILE)), Color(0.32, 0.23, 0.18), false, 1.0)
