extends Node3D
# The digger: first-person walking with voxel collisions, mouse look, digging and placing
# blocks, and the shovel and metal detector held in view.

const Blocks := preload("res://scripts/blocks.gd")
const World := preload("res://scripts/world.gd")
const Mesher := preload("res://scripts/chunk_mesher.gd")
const Textures := preload("res://scripts/textures.gd")

const WALK_SPEED := 4.5
const SPRINT_SPEED := 6.8
const JUMP_SPEED := 8.0
const GRAVITY := 24.0
const HALF_WIDTH := 0.3
const HEIGHT := 1.8
const EYE_HEIGHT := 1.62
const REACH := 5.0
const MOUSE_SENSITIVITY := 0.0025
const PLACE_REPEAT := 0.25
const DIG_TICK := 0.25
const SHOVEL_POS := Vector3(0.42, -0.5, -0.8)
const SHOVEL_ROT := Vector3(0.45, 0.3, 0.25)

# Held items are drawn on top of everything so they never poke into walls.
const VIEW_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_back;
uniform vec3 color : source_color = vec3(1.0);
uniform float glow = 0.0;
void fragment() {
	float light = 0.55 + 0.45 * clamp(dot(NORMAL, normalize(vec3(0.4, 0.8, 0.45))), 0.0, 1.0);
	ALBEDO = color * light + color * glow;
	ALPHA = 1.0;
}
"""

const CRACK_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
uniform sampler2D crack : filter_nearest;
uniform float progress = 0.0;
void fragment() {
	if (texture(crack, UV).r > progress) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.6;
}
"""

var game
var world
var camera: Camera3D
var velocity := Vector3.ZERO
var on_floor := false
var yaw := 0.0
var pitch := 0.0
var target := {}       # what the crosshair points at, from world.raycast()
var _active := false
var _dig_cell := Vector3i(0, -100, 0)
var _dig_time := 0.0
var _dig_armed := false
var _digging := false
var _place_timer := 0.0
var _swing_phase := 0.0
var _swing_amount := 0.0
var _bob := 0.0
var _step_dist := 0.0
var _led_glow := 0.0
var _view_shader: Shader
var _shovel: Node3D
var _detector: Node3D
var _led_mat: ShaderMaterial
var _screen_mat: ShaderMaterial
var _outline: MeshInstance3D
var _crack: MeshInstance3D
var _crack_mat: ShaderMaterial


func _ready() -> void:
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.05
	camera.far = 300.0
	add_child(camera)
	camera.make_current()
	_build_viewmodel()
	_outline = _make_outline()
	add_child(_outline)
	var crack_shader := Shader.new()
	crack_shader.code = CRACK_SHADER
	_crack_mat = ShaderMaterial.new()
	_crack_mat.shader = crack_shader
	_crack_mat.set_shader_parameter("crack", Textures.crack)
	_crack_mat.render_priority = 5
	_crack = MeshInstance3D.new()
	_crack.top_level = true
	_crack.mesh = _cube_mesh(1.006)
	_crack.material_override = _crack_mat
	add_child(_crack)
	set_active(false)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and _active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_look(yaw - motion.relative.x * MOUSE_SENSITIVITY, pitch - motion.relative.y * MOUSE_SENSITIVITY)


func set_look(new_yaw: float, new_pitch: float) -> void:
	yaw = wrapf(new_yaw, -PI, PI)
	pitch = clampf(new_pitch, -1.55, 1.55)
	rotation.y = yaw
	camera.rotation.x = pitch


func set_active(active: bool) -> void:
	_active = active
	_dig_armed = false
	_digging = false
	_dig_time = 0.0
	if not active:
		_outline.visible = false
		_crack.visible = false
		target = {}


# Moves somewhere and pops up out of anything solid.
func teleport(p: Vector3) -> void:
	position = p
	velocity = Vector3.ZERO
	while world.box_hits_solid(_box_lo(), _box_hi()) and position.y < World.SY + 2:
		position.y += 1.0


func flash_led(strength: float) -> void:
	_led_glow = 1.0
	_screen_mat.set_shader_parameter("glow", strength * 0.9)


func update(delta: float) -> void:
	_walk(delta)
	_interact(delta)
	_animate_view(delta)


# --- Movement ------------------------------------------------------------------

func _box_lo() -> Vector3:
	return position - Vector3(HALF_WIDTH, 0.0, HALF_WIDTH)


func _box_hi() -> Vector3:
	return position + Vector3(HALF_WIDTH, HEIGHT, HALF_WIDTH)


func _walk(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var blend := 1.0 - exp(-delta * (12.0 if on_floor else 3.0))
	velocity.x = lerpf(velocity.x, wish.x * speed, blend)
	velocity.z = lerpf(velocity.z, wish.z * speed, blend)
	if on_floor and Input.is_action_pressed("jump"):
		velocity.y = JUMP_SPEED
	velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
	_move(velocity * delta)
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if on_floor and ground_speed > 0.5:
		_bob += delta * ground_speed * 2.2
		_step_dist += ground_speed * delta
		if _step_dist > 2.1:
			_step_dist = 0.0
			game.sfx.play("step", randf_range(0.8, 1.2), -8.0)
	camera.position.y = EYE_HEIGHT + sin(_bob) * 0.035 * clampf(ground_speed / WALK_SPEED, 0.0, 1.0)


# Moves one axis at a time in small steps, sliding along walls.
func _move(motion: Vector3) -> void:
	var largest := maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z)))
	var steps := maxi(1, ceili(largest / 0.35))
	var part := motion / steps
	on_floor = false
	for s in steps:
		for axis: int in [1, 0, 2]:
			if part[axis] != 0.0 and _move_axis(axis, part[axis]):
				if axis == 1 and part.y < 0.0:
					on_floor = true
				velocity[axis] = 0.0
				part[axis] = 0.0


func _move_axis(axis: int, amount: float) -> bool:
	var p := position
	p[axis] += amount
	position = p
	if not world.box_hits_solid(_box_lo(), _box_hi()):
		return false
	if amount > 0.0:
		var hi := _box_hi()[axis]
		p[axis] -= hi - floorf(hi) + 0.001
	else:
		var lo := _box_lo()[axis]
		p[axis] += floorf(lo) + 1.0 - lo + 0.001
	position = p
	return true


# --- Digging and placing ---------------------------------------------------------

func _interact(delta: float) -> void:
	target = world.raycast(camera.global_position, -camera.global_transform.basis.z, REACH)
	var has_target := not target.is_empty()
	_outline.visible = has_target
	if has_target:
		var cell: Vector3i = target["cell"]
		_outline.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	game.hud.set_target(_target_text())
	_digging = false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _dig_armed and has_target:
			_digging = true
			_dig(delta)
	else:
		# Wait for a fresh click, so the click that started the game doesn't dig.
		_dig_armed = true
	if not _digging:
		_dig_time = 0.0
		_crack.visible = false
	_place_timer -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if has_target and _place_timer <= 0.0:
			_place_timer = PLACE_REPEAT
			_place()
	else:
		_place_timer = 0.0


func _target_text() -> String:
	if target.is_empty():
		return ""
	var b: int = target["block"]
	if b == Blocks.RELIC:
		return "Something glints in the soil!"
	if b == Blocks.CHEST:
		return "An old chest!"
	return Blocks.NAMES[b]


func _dig(delta: float) -> void:
	var cell: Vector3i = target["cell"]
	var b: int = target["block"]
	if cell != _dig_cell:
		_dig_cell = cell
		_dig_time = 0.0
	var hardness: float = Blocks.HARDNESS[b]
	if hardness < 0.0:
		game.toast("Bedrock. Nothing digs through this.")
		_crack.visible = false
		return
	if _dig_time == 0.0 or floori(_dig_time / DIG_TICK) != floori((_dig_time + delta) / DIG_TICK):
		game.sfx.play("dig", randf_range(0.8, 1.15), -4.0)
	_dig_time += delta
	if _dig_time >= hardness:
		_dig_time = 0.0
		_crack.visible = false
		game.on_block_dug(cell, b)
		return
	_crack.visible = true
	_crack.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	_crack_mat.set_shader_parameter("progress", _dig_time / hardness)


func _place() -> void:
	var b: int = game.selected_block()
	if game.count(b) <= 0:
		game.toast("You have no %s to place. Dig some up first." % String(Blocks.NAMES[b]).to_lower())
		return
	var c: Vector3i = target["prev"]
	if not World.in_bounds(c) or world.block(c.x, c.y, c.z) != Blocks.AIR:
		return
	var lo := _box_lo()
	var hi := _box_hi()
	if lo.x < c.x + 1 and hi.x > c.x and lo.y < c.y + 1 and hi.y > c.y and lo.z < c.z + 1 and hi.z > c.z:
		return
	game.on_block_placed(c, b)


# --- What you hold ---------------------------------------------------------------

func _animate_view(delta: float) -> void:
	_swing_phase += delta * 14.0
	_swing_amount = move_toward(_swing_amount, 1.0 if _digging else 0.0, delta * 6.0)
	var s := sin(_swing_phase) * _swing_amount
	_shovel.rotation = SHOVEL_ROT + Vector3(s * 0.35, 0.0, 0.0)
	_shovel.position = SHOVEL_POS + Vector3(0.0, sin(_bob * 2.0) * 0.01, -s * 0.08)
	_detector.visible = game.detector_on
	_led_glow = move_toward(_led_glow, 0.0, delta * 6.0)
	_led_mat.set_shader_parameter("glow", _led_glow * 2.0)


func _build_viewmodel() -> void:
	_view_shader = Shader.new()
	_view_shader.code = VIEW_SHADER
	_shovel = Node3D.new()
	camera.add_child(_shovel)
	var steel := _view_mat(Color(0.58, 0.6, 0.64))
	_view_box(_shovel, Vector3(0.035, 0.035, 0.5), Vector3(0.0, 0.0, 0.08), _view_mat(Color(0.55, 0.38, 0.22)))
	_view_box(_shovel, Vector3(0.13, 0.04, 0.04), Vector3(0.0, 0.0, 0.33), _view_mat(Color(0.3, 0.22, 0.15)))
	_view_box(_shovel, Vector3(0.05, 0.05, 0.06), Vector3(0.0, 0.0, -0.19), steel)
	_view_box(_shovel, Vector3(0.19, 0.022, 0.22), Vector3(0.0, -0.005, -0.32), steel)

	_detector = Node3D.new()
	camera.add_child(_detector)
	_detector.position = Vector3(-0.4, -0.36, -0.62)
	_detector.rotation = Vector3(0.65, -0.3, 0.0)
	_detector.scale = Vector3(0.85, 0.85, 0.85)
	_view_box(_detector, Vector3(0.14, 0.04, 0.2), Vector3.ZERO, _view_mat(Color(0.22, 0.26, 0.22)))
	_view_box(_detector, Vector3(0.035, 0.035, 0.12), Vector3(0.0, -0.01, 0.15), _view_mat(Color(0.12, 0.12, 0.12)))
	_screen_mat = _view_mat(Color(0.12, 0.3, 0.16))
	_view_box(_detector, Vector3(0.1, 0.006, 0.08), Vector3(0.0, 0.022, -0.03), _screen_mat)
	_led_mat = _view_mat(Color(0.25, 0.9, 0.35))
	_view_box(_detector, Vector3(0.025, 0.012, 0.025), Vector3(0.045, 0.024, 0.06), _led_mat)


func _view_mat(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _view_shader
	m.set_shader_parameter("color", c)
	m.render_priority = 10
	return m


func _view_box(parent: Node3D, box_size: Vector3, pos: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = box_size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _make_outline() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for a in 8:
		for b in range(a + 1, 8):
			var diff := a ^ b
			if diff == 1 or diff == 2 or diff == 4:
				im.surface_add_vertex(_cube_corner(a, 0.503))
				im.surface_add_vertex(_cube_corner(b, 0.503))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.top_level = true
	return mi


static func _cube_corner(i: int, e: float) -> Vector3:
	return Vector3(e if i & 1 else -e, e if i & 2 else -e, e if i & 4 else -e)


# A cube centred on the origin with a full 0-1 texture on every face.
static func _cube_mesh(scale: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
	for f in 6:
		for k: int in [0, 2, 1, 0, 3, 2]:
			var corner: Vector3i = Mesher.CORNERS[f][k]
			st.set_uv(uv[k])
			st.add_vertex((Vector3(corner) - Vector3(0.5, 0.5, 0.5)) * scale)
	return st.commit()
