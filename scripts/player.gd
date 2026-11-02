extends Node3D
# The digger: first-person walking with collisions against the small cubes (stepping up single
# cubes on its own), crouching, mouse look, swinging the pickaxe, placing blocks, and the pickaxe
# and metal detector held in view.

const Blocks := preload("res://scripts/blocks.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const World := preload("res://scripts/world.gd")
const Room := preload("res://scripts/room.gd")

const WALK_SPEED := 4.2
const SPRINT_SPEED := 6.4
const CROUCH_SPEED := 2.2
const JUMP_SPEED := 7.6
const GRAVITY := 24.0
const HALF_WIDTH := 0.28
const HEIGHT := 1.8
const CROUCH_HEIGHT := 1.05
const EYE_HEIGHT := 1.62
const CROUCH_EYE := 0.9
const STEP_UP := World.VOXEL + 0.02
const REACH := 4.0
const MOUSE_SENSITIVITY := 0.0025
const PLACE_REPEAT := 0.2
const PICK_POS := Vector3(0.4, -0.66, -0.66)
const PICK_ROT := Vector3(-0.3, -0.4, 0.38)

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

var game
var world
var camera: Camera3D
var velocity := Vector3.ZERO
var on_floor := false
var crouching := false
var yaw := 0.0
var pitch := 0.0
var target := {}       # what the crosshair points at, from world.raycast()
var _active := false
var _height := HEIGHT
var _eye := EYE_HEIGHT
var _eye_offset := 0.0
var _swing := 0.0      # progress of the current pickaxe swing, 0 to 1
var _dig_armed := false
var _digging := false
var _place_timer := 0.0
var _bob := 0.0
var _step_dist := 0.0
var _led_glow := 0.0
var _view_shader: Shader
var _pick: Node3D
var _head_mats: Array[ShaderMaterial] = []
var _detector: Node3D
var _led_mat: ShaderMaterial
var _screen_mat: ShaderMaterial
var _outline: MeshInstance3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.03
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	_build_viewmodel()
	_outline = _make_outline()
	add_child(_outline)
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
	_swing = 0.0
	if not active:
		_outline.visible = false
		target = {}


func set_head(level: int) -> void:
	for m in _head_mats:
		m.set_shader_parameter("color", Upgrades.HEADS[level]["color"])


# Moves somewhere, crouching if the space is low, or popping up a little out of anything solid.
# Back to the room if there's no room to stand nearby.
func teleport(p: Vector3) -> void:
	velocity = Vector3.ZERO
	for rise in 13:
		position = p + Vector3(0.0, rise * World.VOXEL, 0.0)
		for crouch: bool in [false, true]:
			crouching = crouch
			_height = CROUCH_HEIGHT if crouch else HEIGHT
			if not world.box_hits_solid(_box_lo(), _box_hi()):
				return
	crouching = false
	_height = HEIGHT
	position = world.spawn_point()


func flash_led(strength: float) -> void:
	_led_glow = 1.0
	_screen_mat.set_shader_parameter("glow", strength * 0.9)


func looking_at_workbench() -> bool:
	return not target.is_empty() and Room.is_workbench(target["cell"])


func update(delta: float) -> void:
	_walk(delta)
	_interact(delta)
	_animate_view(delta)


# --- Movement ------------------------------------------------------------------

func _box_lo() -> Vector3:
	return position - Vector3(HALF_WIDTH, 0.0, HALF_WIDTH)


func _box_hi() -> Vector3:
	return position + Vector3(HALF_WIDTH, _height, HALF_WIDTH)


func _walk(delta: float) -> void:
	if Input.is_action_pressed("crouch"):
		crouching = true
	elif crouching and not world.box_hits_solid(_box_lo(), position + Vector3(HALF_WIDTH, HEIGHT, HALF_WIDTH)):
		crouching = false
	_height = CROUCH_HEIGHT if crouching else HEIGHT
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	var blend := 1.0 - exp(-delta * (12.0 if on_floor else 3.0))
	velocity.x = lerpf(velocity.x, wish.x * speed, blend)
	velocity.z = lerpf(velocity.z, wish.z * speed, blend)
	if on_floor and not crouching and Input.is_action_pressed("jump"):
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
	_eye = move_toward(_eye, CROUCH_EYE if crouching else EYE_HEIGHT, delta * 4.0)
	_eye_offset *= exp(-delta * 14.0)
	camera.position.y = _eye + _eye_offset + sin(_bob) * 0.035 * clampf(ground_speed / WALK_SPEED, 0.0, 1.0)


# Moves one axis at a time in steps smaller than a cube, sliding along walls and walking up
# single cubes.
func _move(motion: Vector3) -> void:
	var largest := maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z)))
	var steps := maxi(1, ceili(largest / 0.1))
	var part := motion / steps
	var was_on_floor := on_floor
	on_floor = false
	for s in steps:
		if part.y != 0.0 and _move_axis(1, part.y):
			if part.y < 0.0:
				on_floor = true
			velocity.y = 0.0
			part.y = 0.0
		for axis: int in [0, 2]:
			if part[axis] != 0.0 and _move_axis(axis, part[axis]):
				if (on_floor or was_on_floor) and _step_up(axis, part[axis]):
					continue
				velocity[axis] = 0.0
				part[axis] = 0.0


func _move_axis(axis: int, amount: float) -> bool:
	var start := position
	var p := position
	p[axis] += amount
	position = p
	if not world.box_hits_solid(_box_lo(), _box_hi()):
		return false
	# Back off to the face of the cube we ran into.
	if amount > 0.0:
		var hi := _box_hi()[axis] / World.VOXEL
		p[axis] -= (hi - floorf(hi)) * World.VOXEL + 0.001
	else:
		var lo := _box_lo()[axis] / World.VOXEL
		p[axis] += (floorf(lo) + 1.0 - lo) * World.VOXEL + 0.001
	position = p
	if world.box_hits_solid(_box_lo(), _box_hi()):
		position = start
	return true


func _step_up(axis: int, amount: float) -> bool:
	var start := position
	position.y += STEP_UP
	var p := position
	p[axis] += amount
	position = p
	if world.box_hits_solid(_box_lo(), _box_hi()):
		position = start
		return false
	_move_axis(1, -STEP_UP)
	_eye_offset -= position.y - start.y
	on_floor = true
	return true


# --- Digging and placing ---------------------------------------------------------

func _interact(delta: float) -> void:
	target = world.raycast(camera.global_position, -camera.global_transform.basis.z, REACH)
	var has_target := not target.is_empty()
	_outline.visible = has_target
	if has_target:
		_outline.position = World.center_of(target["cell"])
	_show_target()
	_digging = false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _dig_armed and has_target:
			_digging = true
			_swing += delta / game.swing_time(target["block"])
			if _swing >= 1.0:
				_swing = 0.0
				game.on_swing_hit(target)
	else:
		# Wait for a fresh click, so the click that started the game doesn't dig.
		_dig_armed = true
	if not _digging:
		_swing = move_toward(_swing, 0.0, delta * 3.0)
	_place_timer -= delta
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if has_target and _place_timer <= 0.0:
			_place_timer = PLACE_REPEAT
			_place()
	else:
		_place_timer = 0.0


func _show_target() -> void:
	if target.is_empty():
		game.hud.set_target("")
		return
	var b: int = target["block"]
	if Room.is_workbench(target["cell"]):
		game.hud.set_target("Workbench  ·  press E for upgrades", game.hud.GOLD)
	elif b == Blocks.RELIC:
		game.hud.set_target("Something glints in the soil!", game.hud.GOLD)
	elif b == Blocks.CHEST or b == Blocks.CHEST_TRIM:
		game.hud.set_target("An old chest!", game.hud.GOLD)
	elif Blocks.is_natural(b) and Blocks.TIER[b] > game.upgrades["head"]:
		game.hud.set_target("%s  ·  needs %s pick head" % [Blocks.NAMES[b], Upgrades.head_name(Blocks.TIER[b])], Color(1.0, 0.55, 0.45))
	else:
		game.hud.set_target(Blocks.NAMES[b])


# Places a 2x2x2 block of the selected material against the face you're looking at.
func _place() -> void:
	var b: int = game.selected_block()
	if game.count(b) <= 0:
		game.toast("You have no %s to place. Dig some up first." % String(Blocks.NAMES[b]).to_lower())
		return
	var cell: Vector3i = target["cell"]
	var prev: Vector3i = target["prev"]
	var lo := prev
	for axis in 3:
		if prev[axis] == cell[axis]:
			lo[axis] = prev[axis] - posmod(prev[axis], 2)
		elif prev[axis] < cell[axis]:
			lo[axis] = prev[axis] - 1
	var cells: Array[Vector3i] = []
	var me_lo := _box_lo() / World.VOXEL
	var me_hi := _box_hi() / World.VOXEL
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var c := lo + Vector3i(dx, dy, dz)
				var inside_me := me_lo.x < c.x + 1 and me_hi.x > c.x and me_lo.y < c.y + 1 and me_hi.y > c.y and me_lo.z < c.z + 1 and me_hi.z > c.z
				if world.can_place(c) and not inside_me:
					cells.append(c)
	if not cells.is_empty():
		game.on_blocks_placed(cells, b)


# --- What you hold ---------------------------------------------------------------

func _animate_view(delta: float) -> void:
	# Raise the pick, then bring it down hard at the end of the swing.
	var lift := 0.0
	if _digging:
		lift = sin(_swing / 0.7 * PI * 0.5) if _swing < 0.7 else lerpf(1.0, -1.0, (_swing - 0.7) / 0.3)
	_pick.rotation = PICK_ROT + Vector3(lift * (0.35 if lift > 0.0 else 0.8), 0.0, 0.0)
	_pick.position = PICK_POS + Vector3(0.0, sin(_bob * 2.0) * 0.01 + maxf(lift, 0.0) * 0.12, 0.0)
	_detector.visible = game.detector_on
	_led_glow = move_toward(_led_glow, 0.0, delta * 6.0)
	_led_mat.set_shader_parameter("glow", _led_glow * 2.0)


func _build_viewmodel() -> void:
	_view_shader = Shader.new()
	_view_shader.code = VIEW_SHADER
	# The pick pivots at your hand: handle up from there, head across the top, its points
	# curving down at both ends.
	_pick = Node3D.new()
	camera.add_child(_pick)
	_pick.position = PICK_POS
	_pick.rotation = PICK_ROT
	_view_box(_pick, Vector3(0.04, 0.6, 0.04), Vector3(0.0, 0.28, 0.0), Vector3.ZERO, _view_mat(Color(0.55, 0.37, 0.21)))
	_view_box(_pick, Vector3(0.05, 0.12, 0.05), Vector3(0.0, 0.02, 0.0), Vector3.ZERO, _view_mat(Color(0.28, 0.2, 0.13)))
	var head := _view_mat(Upgrades.HEADS[0]["color"])
	var tip := _view_mat(Upgrades.HEADS[0]["color"])
	_head_mats = [head, tip]
	_view_box(_pick, Vector3(0.09, 0.08, 0.07), Vector3(0.0, 0.6, 0.0), Vector3.ZERO, head)
	_view_box(_pick, Vector3(0.2, 0.05, 0.05), Vector3(-0.13, 0.585, 0.0), Vector3(0.0, 0.0, 0.22), head)
	_view_box(_pick, Vector3(0.2, 0.05, 0.05), Vector3(0.13, 0.585, 0.0), Vector3(0.0, 0.0, -0.22), head)
	_view_box(_pick, Vector3(0.08, 0.032, 0.032), Vector3(-0.26, 0.545, 0.0), Vector3(0.0, 0.0, 0.45), tip)
	_view_box(_pick, Vector3(0.08, 0.032, 0.032), Vector3(0.26, 0.545, 0.0), Vector3(0.0, 0.0, -0.45), tip)

	_detector = Node3D.new()
	camera.add_child(_detector)
	_detector.position = Vector3(-0.4, -0.36, -0.62)
	_detector.rotation = Vector3(0.65, -0.3, 0.0)
	_detector.scale = Vector3(0.85, 0.85, 0.85)
	_view_box(_detector, Vector3(0.14, 0.04, 0.2), Vector3.ZERO, Vector3.ZERO, _view_mat(Color(0.22, 0.26, 0.22)))
	_view_box(_detector, Vector3(0.035, 0.035, 0.12), Vector3(0.0, -0.01, 0.15), Vector3.ZERO, _view_mat(Color(0.12, 0.12, 0.12)))
	_screen_mat = _view_mat(Color(0.12, 0.3, 0.16))
	_view_box(_detector, Vector3(0.1, 0.006, 0.08), Vector3(0.0, 0.022, -0.03), Vector3.ZERO, _screen_mat)
	_led_mat = _view_mat(Color(0.25, 0.9, 0.35))
	_view_box(_detector, Vector3(0.025, 0.012, 0.025), Vector3(0.045, 0.024, 0.06), Vector3.ZERO, _led_mat)


func _view_mat(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _view_shader
	m.set_shader_parameter("color", c)
	m.render_priority = 10
	return m


func _view_box(parent: Node3D, box_size: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = box_size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


func _make_outline() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var e := World.VOXEL * 0.5 + 0.004
	for a in 8:
		for b in range(a + 1, 8):
			var diff := a ^ b
			if diff == 1 or diff == 2 or diff == 4:
				im.surface_add_vertex(_cube_corner(a, e))
				im.surface_add_vertex(_cube_corner(b, e))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.top_level = true
	return mi


static func _cube_corner(i: int, e: float) -> Vector3:
	return Vector3(e if i & 1 else -e, e if i & 2 else -e, e if i & 4 else -e)
