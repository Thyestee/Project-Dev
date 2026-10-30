extends Node2D
## One floor of the mine: a narrow grid of rock, ore and relics that slowly grows back.

const Data := preload("res://scripts/game_data.gd")

const W := 13
const H := 12
const TILE := 40
const ELEVATOR := Vector2i(1, 0)
const REGROW_INTERVAL := 4.0
const LIGHT_RADIUS := 3.0
const SUPPORT_COLUMNS := [4, 8, 11]

var level_index := 0
var cells: Array = []
var player

var _mine_cell := Vector2i(-1, -1)
var _mine_progress := 0.0
var _chip_timer := 0.0
var _regrow_timer := 0.0
var _particles: Array = []
var _floaters: Array = []
var _flashes := {}
var _rng := RandomNumberGenerator.new()
var _fx: Node2D


func _ready() -> void:
	_rng.randomize()
	# Effects draw on top of the player, so they live on their own canvas item.
	_fx = Node2D.new()
	_fx.z_index = 1
	_fx.draw.connect(_draw_fx)
	add_child(_fx)


func generate(index: int) -> void:
	level_index = index
	cells.resize(W * H)
	for y in H:
		for x in W:
			var t: int = Data.AIR
			if x == 0 or x == W - 1 or y == H - 1:
				t = Data.BEDROCK
			elif y > 0:
				t = _random_block()
			cells[y * W + x] = t
	_reset_effects()


func restore(index: int, saved: Array) -> void:
	level_index = index
	cells = saved.duplicate()
	_reset_effects()


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func get_cell(c: Vector2i) -> int:
	if not in_bounds(c):
		return Data.BEDROCK
	return cells[c.y * W + c.x]


func set_cell(c: Vector2i, t: int) -> void:
	cells[c.y * W + c.x] = t


func is_walkable(c: Vector2i) -> bool:
	return get_cell(c) == Data.AIR


func is_mineable(c: Vector2i) -> bool:
	var t := get_cell(c)
	return t != Data.AIR and t != Data.BEDROCK


func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE * 0.5, c.y * TILE + TILE * 0.5)


func hardness(t: int) -> float:
	if t == Data.STONE:
		return 1.0 + 0.35 * level_index
	return float(Data.BLOCKS[t]["hardness"])


func rock_color() -> Color:
	return Data.LEVELS[level_index]["rock"]


func block_color(t: int) -> Color:
	if t == Data.STONE or t == Data.RELIC:
		return rock_color()
	return Data.BLOCKS[t]["color"]


## Digs at a block for one frame. Returns the block type once it breaks, -1 otherwise.
func mine(c: Vector2i, delta: float, power: float) -> int:
	if c != _mine_cell:
		_mine_cell = c
		_mine_progress = 0.0
		_chip_timer = 0.0
	var t := get_cell(c)
	_mine_progress += delta * power / (hardness(t) * 0.45)
	_chip_timer -= delta
	if _chip_timer <= 0.0:
		_chip_timer = 0.12
		_spawn_particles(c, t, 2, 90.0)
	if _mine_progress < 1.0:
		return -1
	set_cell(c, Data.AIR)
	_spawn_particles(c, t, 14, 190.0)
	reset_mining()
	return t


func reset_mining() -> void:
	_mine_cell = Vector2i(-1, -1)
	_mine_progress = 0.0


func add_floater(c: Vector2i, text: String, color: Color) -> void:
	_floaters.append({"pos": cell_center(c) + Vector2(0, -12), "text": text, "color": color, "life": 1.3})


func _random_block() -> int:
	var info: Dictionary = Data.LEVELS[level_index]
	if _rng.randf() < float(info["relic_chance"]):
		return Data.RELIC
	return Data.pick_weighted(info["weights"], _rng)


func _reset_effects() -> void:
	reset_mining()
	_particles.clear()
	_floaters.clear()
	_flashes.clear()
	_regrow_timer = 0.0


func _process(delta: float) -> void:
	for p in _particles:
		p["vel"] += Vector2(0, 520) * delta
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
	_particles = _particles.filter(func(p): return p["life"] > 0.0)
	for f in _floaters:
		f["pos"] += Vector2(0, -26) * delta
		f["life"] -= delta
	_floaters = _floaters.filter(func(f): return f["life"] > 0.0)
	for k in _flashes.keys():
		_flashes[k] -= delta * 1.5
		if _flashes[k] <= 0.0:
			_flashes.erase(k)

	_regrow_timer += delta
	if _regrow_timer >= REGROW_INTERVAL:
		_regrow_timer = 0.0
		_regrow_one()

	queue_redraw()
	_fx.queue_redraw()


# The mine slowly heals itself: a dug-out cell away from the player fills back in.
func _regrow_one() -> void:
	var pc := Vector2i(-99, -99)
	if player != null:
		pc = player.cell
	for attempt in 24:
		var c := Vector2i(_rng.randi_range(1, W - 2), _rng.randi_range(1, H - 2))
		if get_cell(c) != Data.AIR:
			continue
		if maxi(absi(c.x - pc.x), absi(c.y - pc.y)) < 2:
			continue
		set_cell(c, _random_block())
		_flashes[c] = 1.0
		return


func _spawn_particles(c: Vector2i, t: int, count: int, speed: float) -> void:
	var center := cell_center(c)
	var col := block_color(t)
	var rock := rock_color().lightened(0.15)
	for i in count:
		_particles.append({
			"pos": center + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12)),
			"vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(0.3, 1.0) * speed + Vector2(0, -60),
			"life": _rng.randf_range(0.4, 0.8),
			"size": _rng.randf_range(2.0, 5.0),
			"color": col if _rng.randf() < 0.6 else rock,
		})


func _hash(x: int, y: int, k: int) -> float:
	var v := sin(x * 12.9898 + y * 78.233 + k * 37.719) * 43758.5453
	return v - floor(v)


func _draw() -> void:
	var rock := rock_color()
	var tunnel := rock.darkened(0.72)
	var now := Time.get_ticks_msec() / 1000.0

	# Frame and ceiling, with the elevator shaft punched through it.
	draw_rect(Rect2(-10, -TILE - 10, W * TILE + 20, (H + 1) * TILE + 20), Color(0.05, 0.04, 0.04))
	for x in W:
		var r := Rect2(x * TILE, -TILE, TILE, TILE)
		if x == ELEVATOR.x:
			draw_rect(r, Color(0.03, 0.03, 0.03))
		else:
			_draw_bedrock(r, x, -1)

	for y in H:
		for x in W:
			var t: int = cells[y * W + x]
			var r := Rect2(x * TILE, y * TILE, TILE, TILE)
			if t == Data.AIR:
				_draw_tunnel(r, x, y, tunnel)
			elif t == Data.BEDROCK:
				_draw_bedrock(r, x, y)
			else:
				_draw_rock(r, x, y, rock)
				if t != Data.STONE and t != Data.RELIC:
					_draw_ore(r, x, y, t, now)

	_draw_supports(now)
	_draw_elevator()
	_draw_cracks()

	# Darkness beyond the reach of the helmet lamp; deeper floors are darker.
	var light := cell_center(ELEVATOR)
	if player != null:
		light = player.position
	var max_dark := 0.4 + 0.045 * level_index
	for y in H:
		for x in W:
			var d := (cell_center(Vector2i(x, y)) - light).length() / TILE
			var a := clampf((d - LIGHT_RADIUS) / 4.0, 0.0, 1.0) * max_dark
			if a > 0.01:
				draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), Color(0, 0, 0, a))

	# Relics glint even in the dark.
	for y in H:
		for x in W:
			if cells[y * W + x] == Data.RELIC:
				_draw_sparkle(cell_center(Vector2i(x, y)), now, x * 1.7 + y)

	for c in _flashes:
		draw_rect(Rect2(Vector2(c) * TILE, Vector2(TILE, TILE)), Color(1, 1, 0.9, 0.45 * _flashes[c]))


func _draw_tunnel(r: Rect2, x: int, y: int, col: Color) -> void:
	draw_rect(r, col)
	var p := r.position + Vector2(_hash(x, y, 3) * 26, _hash(x, y, 4) * 30)
	draw_rect(Rect2(p, Vector2(10, 6)), col.darkened(0.2))


func _draw_bedrock(r: Rect2, x: int, y: int) -> void:
	var col := Color(0.13, 0.12, 0.13)
	draw_rect(r, col)
	for i in 3:
		var p := r.position + Vector2(_hash(x, y, 5 + i) * 30, _hash(x, y, 8 + i) * 30)
		draw_line(p, p + Vector2(8, 6), col.lightened(0.08), 2.0)


func _draw_rock(r: Rect2, x: int, y: int, rock: Color) -> void:
	var shade := 0.9 + _hash(x, y, 1) * 0.18
	draw_rect(r, Color(rock.r * shade, rock.g * shade, rock.b * shade))
	for i in 3:
		var p := r.position + Vector2(4 + _hash(x, y, 10 + i) * (TILE - 12), 4 + _hash(x, y, 20 + i) * (TILE - 12))
		draw_rect(Rect2(p, Vector2(7, 4)), rock.darkened(0.25))
		draw_rect(Rect2(p, Vector2(5, 1)), rock.lightened(0.15))
	draw_line(r.position, r.position + Vector2(TILE, 0), rock.lightened(0.12), 1.0)
	draw_line(r.position + Vector2(0, TILE - 1), r.position + Vector2(TILE, TILE - 1), rock.darkened(0.35), 1.0)


func _draw_ore(r: Rect2, x: int, y: int, t: int, now: float) -> void:
	var col: Color = Data.BLOCKS[t]["color"]
	var center := r.get_center()
	if t in Data.GEMS:
		if t == Data.MYTHRIL:
			var pulse := 0.5 + 0.5 * sin(now * 2.5 + x + y)
			draw_circle(center, 16, Color(col, 0.12 + 0.1 * pulse))
		for i in 3:
			var p := center + Vector2(_hash(x, y, 30 + i) - 0.5, _hash(x, y, 40 + i) - 0.5) * 20.0
			var s := 4.5 + _hash(x, y, 50 + i) * 3.0
			var top := p + Vector2(0, -s)
			var right := p + Vector2(s * 0.75, 0)
			draw_colored_polygon(PackedVector2Array([top, right, p + Vector2(0, s), p + Vector2(-s * 0.75, 0)]), col)
			draw_colored_polygon(PackedVector2Array([top, right, p]), col.lightened(0.45))
	else:
		for i in 5:
			var p := center + Vector2(_hash(x, y, 30 + i) - 0.5, _hash(x, y, 40 + i) - 0.5) * 24.0
			var s := 2.5 + _hash(x, y, 50 + i) * 2.5
			draw_circle(p, s, col.darkened(0.3))
			draw_circle(p - Vector2(0.7, 0.7), s * 0.75, col)
			draw_circle(p - Vector2(s * 0.3, s * 0.3), s * 0.25, col.lightened(0.5))


func _draw_supports(now: float) -> void:
	var wood := Color(0.42, 0.27, 0.14)
	for sx in SUPPORT_COLUMNS:
		var left := float(sx) * TILE
		draw_rect(Rect2(left + 2, 0, 5, TILE), wood)
		draw_rect(Rect2(left + TILE - 7, 0, 5, TILE), wood)
		draw_rect(Rect2(left, 0, TILE, 5), wood.darkened(0.25))
	# A hanging lantern in the corridor.
	var lamp := Vector2(6.5 * TILE, 14)
	draw_line(Vector2(lamp.x, 0), lamp, Color(0.2, 0.2, 0.2), 1.0)
	var flicker := 0.85 + 0.15 * sin(now * 9.0) * sin(now * 3.7)
	draw_circle(lamp, 22, Color(1, 0.75, 0.3, 0.08 * flicker))
	draw_circle(lamp, 5, Color(1, 0.8, 0.35, flicker))


func _draw_elevator() -> void:
	var e := Rect2(ELEVATOR.x * TILE, 0, TILE, TILE)
	var steel := Color(0.6, 0.62, 0.66)
	var cx := e.get_center().x
	draw_line(Vector2(cx, -TILE * 3), Vector2(cx, 2), Color(0.3, 0.3, 0.3), 2.0)
	draw_rect(e.grow(-2), Color(0.25, 0.25, 0.28, 0.5))
	for i in range(1, 4):
		draw_line(Vector2(e.position.x + i * 10, 3), Vector2(e.position.x + i * 10, TILE - 4), steel.darkened(0.35), 1.0)
	draw_rect(e.grow(-2), steel, false, 2.0)
	draw_rect(Rect2(e.position.x, TILE - 5, TILE, 5), steel.darkened(0.2))


func _draw_cracks() -> void:
	if _mine_cell.x < 0 or _mine_progress <= 0.0:
		return
	var r := Rect2(Vector2(_mine_cell) * TILE, Vector2(TILE, TILE))
	var c := r.get_center()
	var n := int(_mine_progress * 6.0) + 1
	for i in n:
		var a := _hash(_mine_cell.x, _mine_cell.y, 60 + i) * TAU
		var reach := 8.0 + 11.0 * _mine_progress
		var dir := Vector2.from_angle(a)
		var mid := c + dir * reach * 0.5 + dir.orthogonal() * 3.0
		draw_polyline(PackedVector2Array([c, mid, c + dir * reach]), Color(0, 0, 0, 0.75), 2.0)


func _draw_sparkle(c: Vector2, now: float, phase: float) -> void:
	var pulse := 0.5 + 0.5 * sin(now * 3.0 + phase)
	draw_circle(c, 11 + pulse * 5, Color(1, 0.9, 0.5, 0.1 + 0.1 * pulse))
	var pts := PackedVector2Array()
	for i in 8:
		var rad := 9.0 + pulse * 3.0 if i % 2 == 0 else 2.5
		pts.append(c + Vector2.from_angle(now * 0.8 + phase + i * TAU / 8.0) * rad)
	draw_colored_polygon(pts, Color(1, 0.95, 0.7, 0.7 + 0.3 * pulse))


func _draw_fx() -> void:
	# Mining progress bar above the block being dug.
	if _mine_cell.x >= 0 and _mine_progress > 0.0:
		var bar := Rect2(Vector2(_mine_cell) * TILE + Vector2(4, -7), Vector2(TILE - 8, 5))
		_fx.draw_rect(bar, Color(0, 0, 0, 0.7))
		_fx.draw_rect(Rect2(bar.position, Vector2(bar.size.x * _mine_progress, bar.size.y)), Color(1, 0.85, 0.3))
	for p in _particles:
		var col: Color = p["color"]
		col.a = clampf(p["life"] * 2.0, 0.0, 1.0)
		var s: float = p["size"]
		_fx.draw_rect(Rect2(p["pos"] - Vector2(s, s) * 0.5, Vector2(s, s)), col)
	var font := ThemeDB.fallback_font
	for f in _floaters:
		var col: Color = f["color"]
		col.a = clampf(f["life"], 0.0, 1.0)
		var pos: Vector2 = f["pos"] + Vector2(-90, 0)
		_fx.draw_string_outline(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 180, 16, 4, Color(0, 0, 0, col.a))
		_fx.draw_string(font, pos, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 180, 16, col)
