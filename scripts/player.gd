extends Node2D
## The player: walks with WASD, aims with the mouse and swings the selected tool.

const Icons := preload("res://scripts/icons.gd")
const Lights := preload("res://scripts/world/lights.gd")

const SPEED := 125.0
const RADIUS := 7.0
const REACH := 58.0
const SWING_COOLDOWN := 0.34
const SWING_TIME := 0.22

var game
var area
var facing := Vector2.DOWN
var light: PointLight2D

var _walk := 0.0
var _moving := false
var _swing := 0.0
var _swing_angle := 0.0
var _swing_side := 1.0
var _cooldown := 0.0


func _ready() -> void:
	light = Lights.make(210, Color(1.0, 0.86, 0.62), 1.1)
	light.position = Vector2(0, -14)
	add_child(light)


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if game.can_control():
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_moving = dir != Vector2.ZERO
	if _moving:
		position = area.move_body(position, dir * SPEED * delta, RADIUS)
		_walk += delta * 12.0
	var aim := get_global_mouse_position() - chest()
	if aim.length() > 6.0:
		facing = aim.normalized()

	_cooldown -= delta
	_swing = maxf(_swing - delta, 0.0)
	if game.wants_hit() and _cooldown <= 0.0:
		_cooldown = SWING_COOLDOWN
		_swing = SWING_TIME
		_swing_angle = facing.angle()
		_swing_side = 1.0 if facing.x >= 0.0 else -1.0
		game.on_swing(aim_cell())
	queue_redraw()


func chest() -> Vector2:
	return position + Vector2(0, -12)


## The tile the next swing will hit: what's under the mouse if it's in reach,
## otherwise whatever hittable thing is right next to you in the aim direction.
func aim_cell() -> Vector2i:
	var mouse := get_global_mouse_position()
	var c := chest()
	var f := (mouse - c).normalized()
	var candidates: Array = []
	if mouse.distance_to(c) <= REACH:
		candidates.append(area.cell_of(mouse))
	candidates.append(area.cell_of(c + f * 20.0))
	candidates.append(area.cell_of(position + f * 20.0))
	candidates.append(area.cell_of(c + f * 36.0))
	for cell in candidates:
		if not area.hit_info(cell).is_empty():
			return cell
	return candidates[0]


func _draw() -> void:
	var bob := -absf(sin(_walk)) * 1.5 if _moving else 0.0
	var o := Vector2(0, bob)
	var side := 0.0
	if absf(facing.x) > 0.25:
		side = signf(facing.x)
	var away := facing.y < -0.5 and absf(facing.x) < 0.7

	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if away:
		_draw_tool(o)
	var step := sin(_walk) * 2.0 if _moving else 0.0
	draw_rect(Rect2(Vector2(-5, -7 + step) + o, Vector2(4, 7 - step)), Color(0.22, 0.24, 0.32))
	draw_rect(Rect2(Vector2(1, -7 - step) + o, Vector2(4, 7 + step)), Color(0.22, 0.24, 0.32))
	draw_rect(Rect2(Vector2(-7, -18) + o, Vector2(14, 12)), Color(0.72, 0.32, 0.22))
	draw_rect(Rect2(Vector2(-5, -13) + o, Vector2(10, 7)), Color(0.24, 0.42, 0.72))
	draw_circle(Vector2(0, -23) + o, 6.5, Color(0.96, 0.78, 0.62))
	# Hair, then eyes unless we're looking away.
	var hair := PackedVector2Array()
	for i in 9:
		hair.append(Vector2(0, -24) + o + Vector2.from_angle(PI + i * PI / 8.0) * 7.0)
	draw_colored_polygon(hair, Color(0.36, 0.22, 0.12))
	if away:
		draw_circle(Vector2(0, -23) + o, 6.0, Color(0.36, 0.22, 0.12))
	else:
		draw_circle(Vector2(-2.5 + side * 2.0, -22) + o, 1.1, Color(0.1, 0.1, 0.1))
		draw_circle(Vector2(2.5 + side * 2.0, -22) + o, 1.1, Color(0.1, 0.1, 0.1))
	if not away:
		_draw_tool(o)


func _draw_tool(o: Vector2) -> void:
	var tool: Dictionary = game.equipped_tool()
	if tool.is_empty():
		return
	var angle: float
	if _swing > 0.0:
		var t := 1.0 - _swing / SWING_TIME
		angle = _swing_angle - _swing_side * 1.4 + _swing_side * t * 2.2
	else:
		angle = facing.angle() - (1.0 if facing.x >= 0.0 else -1.0) * 1.1
	var hand := Vector2(0, -12) + o + facing * 5.0
	Icons.draw_tool(self, tool, hand, angle, 14.0)
