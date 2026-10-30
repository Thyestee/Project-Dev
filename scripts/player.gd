extends Node2D
## The miner: steps through dug tunnels and digs into rock by holding a direction.

const MOVE_TIME := 0.13

var level
var game
var cell := Vector2i(1, 0)
var facing := Vector2i.RIGHT
var input_enabled := true

var _look_x := 1
var _moving := false
var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _t := 0.0
var _swing := 0.0
var _bob := 0.0


func place_at(c: Vector2i) -> void:
	cell = c
	_moving = false
	_swing = 0.0
	position = level.cell_center(c)


func _process(delta: float) -> void:
	if _moving:
		_t = minf(_t + delta / MOVE_TIME, 1.0)
		position = _from.lerp(_to, _t)
		_bob += delta * 20.0
		if _t >= 1.0:
			_moving = false
	if not _moving:
		_handle_input(delta)
	queue_redraw()


func _handle_input(delta: float) -> void:
	var dir := _read_dir() if input_enabled else Vector2i.ZERO
	if dir == Vector2i.ZERO:
		level.reset_mining()
		_swing = 0.0
		return
	facing = dir
	if dir.x != 0:
		_look_x = dir.x
	var target := cell + dir
	if level.is_walkable(target):
		level.reset_mining()
		_swing = 0.0
		cell = target
		_from = position
		_to = level.cell_center(target)
		_t = 0.0
		_moving = true
	elif level.is_mineable(target):
		var t: int = level.get_cell(target)
		if not game.can_mine(t):
			_swing = 0.0
			return
		_swing += delta
		var mined: int = level.mine(target, delta, game.pick_power())
		if mined >= 0:
			game.on_block_mined(mined, target)


func _read_dir() -> Vector2i:
	if Input.is_action_pressed("move_left"):
		return Vector2i.LEFT
	if Input.is_action_pressed("move_right"):
		return Vector2i.RIGHT
	if Input.is_action_pressed("move_up"):
		return Vector2i.UP
	if Input.is_action_pressed("move_down"):
		return Vector2i.DOWN
	return Vector2i.ZERO


func _draw() -> void:
	var sx := float(_look_x)
	var o := Vector2(0, sin(_bob) * 1.5 if _moving else 0.0)
	var pants := Color(0.2, 0.22, 0.3)
	var boots := Color(0.28, 0.16, 0.08)

	# Lamp glow, legs, boots, overalls.
	draw_circle(Vector2(sx * 6, -15) + o, 18, Color(1, 0.9, 0.5, 0.08))
	draw_rect(Rect2(Vector2(-7, 8) + o, Vector2(5, 9)), pants)
	draw_rect(Rect2(Vector2(2, 8) + o, Vector2(5, 9)), pants)
	draw_rect(Rect2(Vector2(-8, 16) + o, Vector2(7, 3)), boots)
	draw_rect(Rect2(Vector2(1, 16) + o, Vector2(7, 3)), boots)
	draw_rect(Rect2(Vector2(-8, -4) + o, Vector2(16, 13)), Color(0.75, 0.32, 0.2))
	draw_rect(Rect2(Vector2(-6, 0) + o, Vector2(12, 9)), Color(0.22, 0.42, 0.75))

	# Head, eye and helmet with lamp.
	draw_circle(Vector2(0, -10) + o, 6.5, Color(0.96, 0.78, 0.62))
	draw_circle(Vector2(sx * 3, -10) + o, 1.2, Color(0.1, 0.1, 0.1))
	var helmet := PackedVector2Array()
	for i in 9:
		helmet.append(Vector2(0, -12) + o + Vector2.from_angle(PI + i * PI / 8.0) * 8.0)
	draw_colored_polygon(helmet, Color(1.0, 0.8, 0.15))
	draw_rect(Rect2(Vector2(-9, -13) + o, Vector2(18, 2.5)), Color(0.88, 0.66, 0.1))
	draw_circle(Vector2(sx * 6, -15) + o, 2.5, Color(1, 1, 0.8))

	_draw_pickaxe(o, sx)


func _draw_pickaxe(o: Vector2, sx: float) -> void:
	# Raised while idle, swings down toward the facing direction while digging.
	var swing := (1.0 - cos(_swing * 14.0)) * 0.45
	var a := Vector2(facing).angle() - sx * (0.9 - swing)
	var hand := Vector2(sx * 5, 1) + o
	var dir := Vector2.from_angle(a)
	var tip := hand + dir * 15.0
	var perp := dir.orthogonal()
	draw_line(hand, tip, Color(0.55, 0.36, 0.2), 3.0)
	draw_polyline(PackedVector2Array([tip + perp * 8 - dir * 4, tip + dir, tip - perp * 8 - dir * 4]), Color(0.75, 0.78, 0.82), 3.0)
