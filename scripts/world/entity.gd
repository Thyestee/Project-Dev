extends Node2D
## Something standing in an area: trees, boulders, ladders, doors and furniture.
## Its position is the bottom-centre of its footprint, so y-sorting puts it in front of
## or behind the player correctly.

const Data := preload("res://scripts/game_data.gd")
const Lights := preload("res://scripts/world/lights.gd")
const TILE := Data.TILE

var kind := ""
var cell := Vector2i.ZERO
var size := Vector2i.ONE
var area
var solid := true
var hp := 0.0
var max_hp := 0.0

var _shake := 0.0
var _light: PointLight2D
var _seed := 0.0


func _ready() -> void:
	_seed = fposmod(sin(cell.x * 12.9898 + cell.y * 78.233) * 43758.5453, 1.0)
	if kind == "forge":
		_light = Lights.make(190, Color(1.0, 0.55, 0.2), 1.2)
		_light.position = Vector2(0, -26)
		add_child(_light)
	elif kind == "ladder_up":
		_light = Lights.make(110, Color(1.0, 0.92, 0.75), 0.9)
		_light.position = Vector2(0, -20)
		add_child(_light)
	set_process(kind == "forge")


func shake() -> void:
	_shake = 0.25
	set_process(true)


func particle_color() -> Color:
	if kind == "boulder":
		return Color(0.55, 0.53, 0.52)
	return Color(0.55, 0.38, 0.2)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake -= delta
		queue_redraw()
	if kind == "forge":
		var lit := _is_lit()
		_light.visible = lit
		if lit:
			_light.energy = 1.1 + 0.15 * sin(Time.get_ticks_msec() / 90.0) * sin(Time.get_ticks_msec() / 230.0)
		queue_redraw()
	elif _shake <= 0.0:
		set_process(false)


func _is_lit() -> bool:
	return area != null and area.game != null and area.game.forge_lit


func _draw() -> void:
	var o := Vector2.ZERO
	if _shake > 0.0:
		o.x = sin(_shake * 90.0) * 2.0
	match kind:
		"tree":
			_draw_tree(o, 1.0, Color(0.24, 0.5, 0.22))
		"old_tree":
			_draw_tree(o, 1.4, Color(0.18, 0.38, 0.2))
		"boulder":
			_draw_boulder(o)
		"ladder_up":
			_draw_ladder_up()
		"ladder_down":
			_draw_ladder_down()
		"exit_sign":
			_draw_sign()
		"door":
			_draw_door()
		"bed":
			_draw_bed()
		"workbench":
			_draw_workbench()
		"forge":
			_draw_forge()
		"chair":
			_draw_chair()
		"table":
			_draw_table()
		"bookshelf":
			_draw_bookshelf()
		"planter":
			_draw_planter()


func _shadow(rx: float, alpha := 0.25) -> void:
	draw_set_transform(Vector2(0, -3), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tree(o: Vector2, s: float, green: Color) -> void:
	var g := green.lerp(green.lightened(0.15), _seed)
	_shadow(15.0 * s)
	draw_rect(Rect2(Vector2(-4, -20) * s + o, Vector2(8, 20) * s), Color(0.42, 0.27, 0.15))
	draw_rect(Rect2(Vector2(-4, -20) * s + o, Vector2(3, 20) * s), Color(0.5, 0.33, 0.19))
	draw_circle(Vector2(-10, -27) * s + o, 12.0 * s, g.darkened(0.2))
	draw_circle(Vector2(10, -27) * s + o, 12.0 * s, g.darkened(0.2))
	draw_circle(Vector2(0, -33) * s + o, 15.0 * s, g)
	draw_circle(Vector2(0, -44) * s + o, 11.0 * s, g.lightened(0.05))
	draw_circle(Vector2(-5, -40) * s + o, 5.0 * s, g.lightened(0.2))


func _draw_boulder(o: Vector2) -> void:
	var dark: bool = area != null and area.kind == "mine"
	var col := Color(0.42, 0.39, 0.37) if dark else Color(0.58, 0.57, 0.56)
	_shadow(14.0)
	var pts := PackedVector2Array()
	for i in 9:
		var r := 13.0 * (0.85 + 0.15 * sin(i * 2.3 + _seed * 9.0))
		pts.append(Vector2(0, -11) + o + Vector2.from_angle(i * TAU / 9.0) * Vector2(r, r * 0.85))
	draw_colored_polygon(pts, col)
	draw_circle(Vector2(-4, -15) + o, 4.5, col.lightened(0.18))
	draw_line(Vector2(2, -6) + o, Vector2(6, -13) + o, col.darkened(0.3), 1.5)


func _draw_ladder_up() -> void:
	var wood := Color(0.55, 0.38, 0.2)
	draw_line(Vector2(-7, 0), Vector2(-7, -40), wood, 3.0)
	draw_line(Vector2(7, 0), Vector2(7, -40), wood, 3.0)
	for i in 5:
		var y := -4.0 - i * 8.0
		draw_line(Vector2(-7, y), Vector2(7, y), wood.lightened(0.15), 2.0)


func _draw_ladder_down() -> void:
	draw_set_transform(Vector2(0, -14), 0.0, Vector2(1.0, 0.75))
	draw_circle(Vector2.ZERO, 15.0, Color(0.2, 0.18, 0.17))
	draw_circle(Vector2.ZERO, 12.0, Color(0.02, 0.02, 0.02))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var wood := Color(0.5, 0.34, 0.18)
	draw_line(Vector2(-6, -22), Vector2(-5, -8), wood, 2.5)
	draw_line(Vector2(6, -22), Vector2(5, -8), wood, 2.5)
	for y in [-19.0, -14.0, -9.0]:
		draw_line(Vector2(-6, y), Vector2(6, y), wood.lightened(0.1), 2.0)


func _draw_sign() -> void:
	_shadow(8.0)
	draw_rect(Rect2(-2, -24, 4, 24), Color(0.45, 0.3, 0.16))
	var board := PackedVector2Array([Vector2(-14, -30), Vector2(10, -30), Vector2(16, -24), Vector2(10, -18), Vector2(-14, -18)])
	draw_colored_polygon(board, Color(0.66, 0.48, 0.28))
	draw_string(ThemeDB.fallback_font, Vector2(-13, -20), "HOME", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.2, 0.12, 0.05))


func _draw_door() -> void:
	var w := size.x * TILE
	draw_rect(Rect2(-w / 2.0 + 6, -TILE - 14, w - 12, TILE + 14), Color(0.3, 0.2, 0.12))
	draw_rect(Rect2(-w / 2.0 + 9, -TILE - 11, w - 18, TILE + 11), Color(0.55, 0.36, 0.2))
	draw_line(Vector2(0, -TILE - 11), Vector2(0, 0), Color(0.36, 0.23, 0.12), 2.0)
	draw_circle(Vector2(-6, -18), 2.0, Color(0.9, 0.78, 0.35))
	draw_circle(Vector2(6, -18), 2.0, Color(0.9, 0.78, 0.35))
	draw_rect(Rect2(-w / 2.0 + 10, -2, w - 20, 6), Color(0.45, 0.55, 0.3))


func _draw_bed() -> void:
	var w := size.x * TILE
	var h := size.y * TILE
	draw_rect(Rect2(-w / 2.0 + 2, -h + 2, w - 4, h - 4), Color(0.45, 0.29, 0.16))
	draw_rect(Rect2(-w / 2.0 + 5, -h + 6, w - 10, h - 12), Color(0.92, 0.9, 0.86))
	draw_rect(Rect2(-w / 2.0 + 9, -h + 9, w - 18, 14), Color(1, 1, 1))
	draw_rect(Rect2(-w / 2.0 + 5, -h + 30, w - 10, h - 36), Color(0.3, 0.45, 0.7))
	for i in 3:
		draw_line(Vector2(-w / 2.0 + 5, -h + 42 + i * 14), Vector2(w / 2.0 - 5, -h + 42 + i * 14), Color(0.25, 0.38, 0.6), 2.0)


func _draw_workbench() -> void:
	var w := size.x * TILE
	_shadow(w * 0.45)
	draw_rect(Rect2(-w / 2.0 + 3, -22, 4, 22), Color(0.4, 0.26, 0.14))
	draw_rect(Rect2(w / 2.0 - 7, -22, 4, 22), Color(0.4, 0.26, 0.14))
	draw_rect(Rect2(-w / 2.0 + 1, -30, w - 2, 12), Color(0.62, 0.43, 0.25))
	draw_rect(Rect2(-w / 2.0 + 1, -30, w - 2, 3), Color(0.72, 0.53, 0.33))
	# A saw and a hammer lying on top.
	draw_rect(Rect2(-22, -28, 16, 5), Color(0.7, 0.72, 0.75))
	draw_rect(Rect2(-8, -28, 6, 5), Color(0.5, 0.3, 0.15))
	draw_line(Vector2(6, -24), Vector2(20, -27), Color(0.5, 0.3, 0.15), 2.5)
	draw_rect(Rect2(17, -30, 6, 6), Color(0.45, 0.45, 0.5))


func _draw_forge() -> void:
	var w := size.x * TILE
	var h := size.y * TILE
	var lit := _is_lit()
	var stone := Color(0.46, 0.44, 0.43)
	_shadow(w * 0.5, 0.3)
	draw_rect(Rect2(-w / 2.0 + 2, -h - 6, w - 4, h + 4), stone)
	for row in 5:
		var y := -h - 6 + row * 14.0
		draw_line(Vector2(-w / 2.0 + 2, y), Vector2(w / 2.0 - 2, y), stone.darkened(0.25), 1.0)
		var shift := 8.0 if row % 2 == 0 else 0.0
		for bx in range(-24, 25, 16):
			draw_line(Vector2(bx + shift, y), Vector2(bx + shift, y + 14), stone.darkened(0.25), 1.0)
	# Chimney and the fire mouth.
	draw_rect(Rect2(10, -h - 22, 14, 18), stone.darkened(0.15))
	var mouth := Rect2(-16, -30, 32, 22)
	draw_rect(mouth, Color(0.08, 0.06, 0.05))
	draw_circle(Vector2(0, -30), 16.0, Color(0.08, 0.06, 0.05))
	if lit:
		var t := Time.get_ticks_msec() / 1000.0
		for i in 5:
			var fx := -10.0 + i * 5.0
			var fh := 10.0 + 6.0 * absf(sin(t * 7.0 + i * 1.7))
			var flame := PackedVector2Array([Vector2(fx - 4, -9), Vector2(fx + 4, -9), Vector2(fx, -9 - fh)])
			draw_colored_polygon(flame, Color(1.0, 0.5 + 0.1 * i, 0.15))
		draw_rect(Rect2(-14, -12, 28, 4), Color(1.0, 0.85, 0.4))
	else:
		draw_rect(Rect2(-12, -12, 24, 4), Color(0.25, 0.22, 0.2))


func _draw_chair() -> void:
	_shadow(10.0)
	var wood := Color(0.6, 0.4, 0.22)
	draw_rect(Rect2(-10, -34, 20, 6), wood.darkened(0.15))
	draw_rect(Rect2(-10, -34, 3, 26), wood.darkened(0.15))
	draw_rect(Rect2(7, -34, 3, 26), wood.darkened(0.15))
	draw_rect(Rect2(-11, -16, 22, 8), wood)
	draw_rect(Rect2(-10, -8, 3, 8), wood.darkened(0.25))
	draw_rect(Rect2(7, -8, 3, 8), wood.darkened(0.25))


func _draw_table() -> void:
	var w := size.x * TILE
	var wood := Color(0.58, 0.39, 0.22)
	_shadow(w * 0.45)
	draw_rect(Rect2(-w / 2.0 + 4, -16, 4, 16), wood.darkened(0.3))
	draw_rect(Rect2(w / 2.0 - 8, -16, 4, 16), wood.darkened(0.3))
	draw_rect(Rect2(-w / 2.0 + 1, -30, w - 2, 16), wood)
	draw_rect(Rect2(-w / 2.0 + 1, -30, w - 2, 3), wood.lightened(0.15))


func _draw_bookshelf() -> void:
	var w := size.x * TILE
	var wood := Color(0.45, 0.29, 0.16)
	draw_rect(Rect2(-w / 2.0 + 1, -56, w - 2, 56), wood)
	var colors := [Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.3, 0.6, 0.3), Color(0.8, 0.7, 0.3), Color(0.5, 0.3, 0.6)]
	for shelf in 3:
		var y := -52.0 + shelf * 17.0
		draw_rect(Rect2(-w / 2.0 + 4, y, w - 8, 14), wood.darkened(0.4))
		var x := -w / 2.0 + 5
		var i := shelf * 2
		while x < w / 2.0 - 9:
			var bw := 4.0 + float((i * 7 + shelf) % 3)
			draw_rect(Rect2(x, y + 2 + float(i % 2), bw, 12 - float(i % 2)), colors[i % colors.size()])
			x += bw + 1.0
			i += 1


func _draw_planter() -> void:
	_shadow(10.0)
	draw_rect(Rect2(-11, -14, 22, 14), Color(0.55, 0.36, 0.2))
	draw_rect(Rect2(-11, -14, 22, 3), Color(0.65, 0.45, 0.27))
	for p in [Vector2(-5, -22), Vector2(4, -24), Vector2(0, -30), Vector2(-1, -19)]:
		draw_circle(p, 6.0, Color(0.3, 0.6, 0.3))
	draw_circle(Vector2(3, -28), 2.5, Color(0.95, 0.55, 0.7))
