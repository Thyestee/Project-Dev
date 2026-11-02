extends Node3D
# You: first-person walking on the cubes, health and stamina, and what you hold: the pickaxe,
# the leveller, a sword or a mace (with your shield on the other arm), a bow, or explosives.
# The metal detector sits in your free hand while you dig.

const Blocks := preload("res://scripts/blocks.gd")
const Items := preload("res://scripts/items.gd")
const Catalog := preload("res://scripts/catalog.gd")
const World := preload("res://scripts/world.gd")
const House := preload("res://scripts/house.gd")
const Body := preload("res://scripts/body.gd")
const Models := preload("res://scripts/models.gd")

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
const REACH := 4.0
const MOUSE_SENSITIVITY := 0.0025
const PLACE_REPEAT := 0.2
const BASE_HEALTH := 100.0
const BASE_STAMINA := 100.0
const SPRINT_COST := 16.0     # stamina per second
const JUMP_COST := 6.0
const STAMINA_REGEN := 28.0
const SLOTS := ["pickaxe", "leveler", "sword", "mace", "bow", "bomb"]
const SLOT_NAMES := ["Pickaxe", "Leveller", "Sword", "Mace", "Bow", "Explosives"]

# Where each held thing rests in front of the camera.
const PICK_POS := Vector3(0.4, -0.66, -0.66)
const PICK_ROT := Vector3(-0.3, -0.4, 0.38)
const SWORD_POS := Vector3(0.36, -0.5, -0.62)
const SWORD_ROT := Vector3(-0.55, -0.2, -0.25)
const MACE_POS := Vector3(0.38, -0.58, -0.64)
const MACE_ROT := Vector3(-0.45, -0.3, 0.2)
const TROWEL_POS := Vector3(0.34, -0.42, -0.58)
const TROWEL_ROT := Vector3(-0.35, -0.25, 0.1)
const BOMB_POS := Vector3(0.3, -0.38, -0.56)
const BOW_POS := Vector3(0.06, -0.3, -0.6)
const SHIELD_POS := Vector3(-0.46, -0.48, -0.62)
const SHIELD_UP := Vector3(-0.12, -0.26, -0.44)
const DETECTOR_POS := Vector3(-0.4, -0.36, -0.62)

const LED_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, depth_draw_always;
uniform float glow = 0.0;
void fragment() {
	ALBEDO = vec3(0.1, 0.45, 0.16) + vec3(0.25, 0.9, 0.35) * glow;
	DEPTH = 0.97 + 0.03 * FRAGCOORD.z;
	ALPHA = 1.0;
}
"""

var game
var world
var camera: Camera3D
var body
var yaw := 0.0
var pitch := 0.0
var crouching := false
var target := {}          # the block under the crosshair, from world.raycast()
var target_enemy = null   # the guard under the crosshair, if nearer than the block
var slot := 0
var health := BASE_HEALTH
var stamina := BASE_STAMINA
var exhausted := false
var blocking := false
var placing := {}         # furniture being placed: {"type", "rot", "x", "z", "ok"}
var _active := false
var _height := HEIGHT
var _eye := EYE_HEIGHT
var _eye_offset := 0.0
var _armed := false       # waits for a fresh click, so the click that closes a menu does nothing
var _acting := false
var _action := 0.0        # how far through the current swing, 0 to 1
var _hit_done := false
var _combo := 0
var _drawing := false
var _draw := 0.0
var _place_timer := 0.0
var _level_timer := 0.0
var _throw_timer := 0.0
var _swipe := 0.0
var _throw_anim := 0.0
var _bow_kick := 0.0
var _block_blend := 0.0
var _stamina_delay := 0.0
var _regen_delay := 0.0
var _invulnerable := 0.0
var _aegis_ready := 0.0
var _tired_note := 0.0
var _trauma := 0.0
var _kick := 0.0
var _recoil := 0.0
var _recoil_vel := 0.0
var _hitstop := 0.0
var _sway := Vector2.ZERO
var _bob := 0.0
var _step_dist := 0.0
var _led_glow := 0.0
var _hand: Node3D
var _tools := {}          # slot name -> Node3D in your right hand
var _bow: Node3D
var _nocked: Node3D
var _shield: Node3D
var _detector: Node3D
var _led_mat: ShaderMaterial
var _line_mat: StandardMaterial3D
var _outline: MeshInstance3D
var _plane: MeshInstance3D
var _plane_mesh: ImmediateMesh
var _ghost: MeshInstance3D
var _ghost_mat: ShaderMaterial


func _ready() -> void:
	body = Body.new()
	body.world = world
	body.half_width = HALF_WIDTH
	body.height = HEIGHT
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75.0
	camera.near = 0.03
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	_hand = Node3D.new()
	camera.add_child(_hand)
	_outline = _make_outline()
	add_child(_outline)
	_plane_mesh = ImmediateMesh.new()
	_plane = MeshInstance3D.new()
	_plane.mesh = _plane_mesh
	_plane.top_level = true
	add_child(_plane)
	_ghost_mat = Models.ghost_material()
	_ghost = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost.mesh = box
	_ghost.material_override = _ghost_mat
	_ghost.top_level = true
	_ghost.visible = false
	add_child(_ghost)
	_build_detector()
	set_active(false)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion and _active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		set_look(yaw - motion.relative.x * MOUSE_SENSITIVITY, pitch - motion.relative.y * MOUSE_SENSITIVITY)
		_sway += motion.relative * 0.0004


func set_look(new_yaw: float, new_pitch: float) -> void:
	yaw = wrapf(new_yaw, -PI, PI)
	pitch = clampf(new_pitch, -1.55, 1.55)
	rotation.y = yaw
	camera.rotation.x = pitch


func set_active(active: bool) -> void:
	_active = active
	_armed = false
	_acting = false
	_drawing = false
	_draw = 0.0
	_action = 0.0
	blocking = false
	if not active:
		_outline.visible = false
		_plane.visible = false
		target = {}
		target_enemy = null


func forward() -> Vector3:
	return -camera.global_transform.basis.z


func eye() -> Vector3:
	return camera.global_position


# Moves somewhere, crouching if the space is low, or popping up a little out of anything
# solid. Back to the house if there's no room to stand nearby.
func teleport(p: Vector3) -> void:
	body.velocity = Vector3.ZERO
	for rise in 25:
		body.position = p + Vector3(0.0, rise * World.VOXEL, 0.0)
		for crouch: bool in [false, true]:
			crouching = crouch
			_height = CROUCH_HEIGHT if crouch else HEIGHT
			body.height = _height
			if not body.blocked():
				position = body.position
				return
	crouching = false
	_height = HEIGHT
	body.height = HEIGHT
	body.position = world.spawn_point()
	position = body.position


func flash_led(strength: float) -> void:
	_led_glow = 0.4 + 0.6 * strength


func max_health() -> float:
	return BASE_HEALTH + game.global_affix("vitality")


func max_stamina() -> float:
	return BASE_STAMINA * (1.25 if game.rested > 0.0 else 1.0)


func heal(amount: float) -> void:
	health = minf(max_health(), health + amount)


func select(i: int) -> void:
	slot = posmod(i, SLOTS.size())
	_acting = false
	_drawing = false
	_draw = 0.0
	_action = 0.0
	_update_visibility()


func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func update(delta: float) -> void:
	_vitals(delta)
	_walk(delta)
	if placing.is_empty():
		_use_tool(delta)
	else:
		_update_placing()
	_animate_view(delta)
	_update_camera(delta)


# --- Health and stamina ----------------------------------------------------------------------

func _vitals(delta: float) -> void:
	_invulnerable -= delta
	_aegis_ready -= delta
	_regen_delay -= delta
	_tired_note -= delta
	var top := max_health()
	if health > top:
		health = top
	if _regen_delay <= 0.0 and health < top:
		var rate: float = 1.0 + game.global_affix("regen") + (4.0 if game.at_home() else 0.0)
		health = minf(top, health + rate * delta)
	_stamina_delay -= delta
	if _stamina_delay <= 0.0:
		stamina = minf(max_stamina(), stamina + STAMINA_REGEN * delta)
	if exhausted and stamina >= max_stamina() * 0.3:
		exhausted = false


# Uses up stamina for something. Returns false if you're too worn out to do it properly.
func spend(amount: float) -> bool:
	_stamina_delay = 0.7
	if exhausted:
		return false
	stamina -= amount
	if stamina <= 0.0:
		stamina = 0.0
		exhausted = true
	return true


# Something hits you from `from`. Your shield takes most of a blow from in front.
func take_damage(amount: float, from: Vector3, knockback: float, attacker = null) -> void:
	if _invulnerable > 0.0 or game.state != "playing" or health <= 0.0:
		return
	var shield: Dictionary = game.equipped["shield"]
	if blocking and not shield.is_empty():
		var to: Vector3 = from - body.position
		to.y = 0.0
		var facing := Vector3(-sin(yaw), 0.0, -cos(yaw))
		if to.length() < 0.01 or facing.dot(to.normalized()) > 0.34:
			var blocked := amount * Items.guard(shield)
			var cost := blocked * Items.stamina_cost(shield)
			if spend(cost):
				amount -= blocked
				game.sfx.play("block", randf_range(0.9, 1.1))
				_recoil_vel += 8.0
				shake(0.12)
				var thorns := Items.affix(shield, "thorns")
				if attacker != null and thorns > 0.0:
					game.enemies.hurt(attacker, blocked * thorns / 100.0, body.position, {"knockback": 2.0})
				if attacker != null and Items.legend(shield) == "mirror":
					game.enemies.hurt(attacker, 0.0, body.position, {"knockback": 5.0, "stun": 1.2})
			else:
				amount -= blocked * 0.5
				blocking = false
				game.sfx.play("block", 0.7)
				game.toast("Your guard breaks! Catch your breath.", Color(1.0, 0.6, 0.45))
	if amount <= 0.0:
		return
	health -= amount
	_regen_delay = 5.0
	if health <= 0.0:
		if Items.legend(shield) == "aegis" and _aegis_ready <= 0.0:
			health = 1.0
			_invulnerable = 3.0
			_aegis_ready = 90.0
			game.toast("Aegis holds! You're untouchable for 3 seconds.", Color(1.0, 0.8, 0.3))
			game.sfx.play("buy", 0.8)
		else:
			health = 0.0
			game.on_player_died()
			return
	var push: Vector3 = body.position - from
	push.y = 0.0
	if push.length() > 0.01:
		body.velocity += push.normalized() * knockback + Vector3(0.0, knockback * 0.3, 0.0)
	_kick += 0.06
	shake(clampf(amount / 30.0, 0.15, 0.6))
	game.hud.flash_hurt(clampf(amount / 25.0, 0.3, 1.0))
	game.sfx.play("hurt", randf_range(0.9, 1.1))


# --- Movement ------------------------------------------------------------------------------------

func _walk(delta: float) -> void:
	if Input.is_action_pressed("crouch"):
		crouching = true
	elif crouching and body.fits(body.position, HEIGHT):
		crouching = false
	_height = CROUCH_HEIGHT if crouching else HEIGHT
	body.height = _height
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	var speed := WALK_SPEED
	if crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint") and input.length() > 0.1 and not exhausted and not blocking and not _drawing:
		speed = SPRINT_SPEED
		stamina = maxf(0.0, stamina - SPRINT_COST * delta)
		_stamina_delay = 0.5
		if stamina <= 0.0:
			exhausted = true
	if blocking:
		speed *= 0.45 * (1.0 + game.global_affix("swift") / 100.0)
	if _drawing:
		speed *= 0.55
	speed *= 1.0 + game.global_affix("swift") / 100.0
	var v: Vector3 = body.velocity
	var blend := 1.0 - exp(-delta * (12.0 if body.on_floor else 3.0))
	v.x = lerpf(v.x, wish.x * speed, blend)
	v.z = lerpf(v.z, wish.z * speed, blend)
	if body.on_floor and not crouching and Input.is_action_pressed("jump") and stamina > 0.0:
		v.y = JUMP_SPEED
		stamina = maxf(0.0, stamina - JUMP_COST)
		_stamina_delay = 0.5
	v.y = maxf(v.y - GRAVITY * delta, -40.0)
	body.velocity = v
	body.move(v * delta)
	position = body.position
	_eye_offset -= body.stepped
	var ground_speed := Vector2(body.velocity.x, body.velocity.z).length()
	if body.on_floor and ground_speed > 0.5:
		_bob += delta * ground_speed * 2.2
		_step_dist += ground_speed * delta
		if _step_dist > 2.1:
			_step_dist = 0.0
			game.sfx.play("step", randf_range(0.8, 1.2), -8.0)
	_eye = move_toward(_eye, CROUCH_EYE if crouching else EYE_HEIGHT, delta * 4.0)
	_eye_offset *= exp(-delta * 14.0)


# --- Using what you hold ----------------------------------------------------------------------

func _use_tool(delta: float) -> void:
	var from := eye()
	var dir := forward()
	target = world.raycast(from, dir, REACH)
	var hit: Dictionary = game.enemies.ray_hit(from, dir, REACH)
	target_enemy = null
	if not hit.is_empty() and (target.is_empty() or float(hit["dist"]) < float(target["dist"])):
		target_enemy = hit["enemy"]
	var kind: String = SLOTS[slot]
	_outline.visible = not target.is_empty() and kind == "pickaxe" and target_enemy == null
	if _outline.visible:
		_outline.position = World.center_of(target["cell"])
	game.show_target()
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not lmb and not rmb:
		_armed = true
	var use := lmb and _armed
	blocking = false
	_plane.visible = false
	match kind:
		"pickaxe":
			_use_pickaxe(delta, use)
			_place_blocks(delta, rmb and _armed)
		"leveler":
			_use_leveler(delta, use)
			_place_blocks(delta, rmb and _armed)
		"sword", "mace":
			blocking = rmb and _armed and not game.equipped["shield"].is_empty() and not exhausted and not _acting
			_use_melee(delta, use and not blocking, kind)
		"bow":
			_use_bow(delta, use)
		"bomb":
			_use_bomb(delta, use)


func _note_tired() -> void:
	if _tired_note <= 0.0:
		_tired_note = 2.5
		game.toast("Too tired! Wait for your stamina to come back.", Color(1.0, 0.75, 0.45))


func _use_pickaxe(delta: float, held: bool) -> void:
	var item: Dictionary = game.equipped["pickaxe"]
	if held:
		_acting = true
		var t := 0.6
		if target_enemy != null:
			t = Items.attack_time(item) / float(Catalog.GRIPS[game.workshop["grip"]]["speed"])
		elif not target.is_empty() and float(target["dist"]) <= REACH:
			t = game.swing_time(target["block"])
		if exhausted:
			t /= 0.55
		if _hitstop <= 0.0:
			_action += delta / t
		if _action >= 1.0:
			_action = 0.0
			spend(Items.stamina_cost(item))
			if target_enemy != null:
				game.melee_hit(target_enemy, item, Items.damage(item), {"knockback": 3.0})
				impact(0.7, false)
			elif not target.is_empty():
				game.on_swing_hit(target)
			else:
				game.sfx.play("swing", randf_range(1.1, 1.3), -8.0)
	else:
		_acting = false
		_action = move_toward(_action, 0.0, delta * 3.0)


# The flatten tool: one click levels a square of ground with the face you're looking at.
func _use_leveler(delta: float, held: bool) -> void:
	_level_timer -= delta
	var half: int = game.level_half()
	var ok: bool = not target.is_empty() and target["normal"] != Vector3i.ZERO and target_enemy == null
	_plane.visible = ok
	if ok:
		_draw_plane(target["cell"], target["normal"], half)
	if held and ok and _level_timer <= 0.0:
		_level_timer = 0.45
		_swipe = 1.0
		game.on_level(target)
		_armed = false


func _use_melee(delta: float, held: bool, kind: String) -> void:
	var item: Dictionary = game.equipped[kind]
	if item.is_empty():
		if held:
			game.toast("You don't have a %s yet. Buy one at the workbench, or find one in a hidden room." % kind)
			_armed = false
		return
	if _acting:
		if _hitstop <= 0.0:
			_action += delta / Items.attack_time(item)
		var hit_at := 0.45 if kind == "sword" else 0.62
		if not _hit_done and _action >= hit_at:
			_hit_done = true
			_strike(kind, item)
		if _action >= 1.0:
			_acting = false
			_action = 0.0
	if not _acting and held:
		if spend(Items.stamina_cost(item)):
			_acting = true
			_action = 0.0
			_hit_done = false
			_combo += 1
			game.sfx.play("swing", randf_range(0.95, 1.1) * (1.0 if kind == "sword" else 0.7), -3.0)
		else:
			_note_tired()


func _strike(kind: String, item: Dictionary) -> void:
	var from := eye()
	var dir := forward()
	var reach := Items.reach(item)
	var cone := cos(deg_to_rad(50.0 if kind == "sword" else 35.0))
	var targets: Array = game.enemies.in_cone(from, dir, reach, cone)
	var damage := Items.damage(item)
	var opts := {"knockback": 4.0, "stun": 0.0} if kind == "sword" else {"knockback": 7.5, "stun": 0.55}
	for e in targets:
		game.melee_hit(e, item, damage, opts)
	var legend := Items.legend(item)
	if legend == "tempest" and _combo % 3 == 0:
		game.tempest(item, damage)
	if legend == "phantom":
		game.projectiles.blade(from + dir * 0.6, dir, {"item": item, "damage": damage * 0.6})
	var wall: Dictionary = world.raycast(from, dir, reach)
	if targets.is_empty():
		if not wall.is_empty():
			game.melee_hit_block(wall, item, damage)
			impact(0.6 if kind == "sword" else 1.0, true)
		if legend == "earthshaker" and not wall.is_empty():
			game.earthshake(item, World.center_of(wall["cell"]), damage)
	else:
		impact(0.5 if kind == "sword" else 0.9, false)
		if legend == "earthshaker":
			game.earthshake(item, targets[0].body.position, damage)


func _use_bow(delta: float, held: bool) -> void:
	var item: Dictionary = game.equipped["bow"]
	if item.is_empty():
		if held:
			game.toast("You don't have a bow yet. Buy one at the workbench, or find one in a hidden room.")
			_armed = false
		return
	if held:
		if not _drawing:
			if game.supplies["arrows"] <= 0:
				game.toast("Out of arrows. Buy more at the workbench, or pick up the ones you've shot.")
				_armed = false
				return
			_drawing = true
			_draw = 0.0
			game.sfx.play("draw", randf_range(0.95, 1.05), -6.0)
		_draw = minf(1.0, _draw + delta / Items.attack_time(item))
	elif _drawing:
		_drawing = false
		if _draw >= 0.2:
			_shoot(item, _draw)
		_draw = 0.0


func _shoot(item: Dictionary, power: float) -> void:
	if not spend(Items.stamina_cost(item)):
		power *= 0.6
	var from := eye()
	var dir := forward()
	var speed := 18.0 + 30.0 * power
	var info := {"item": item, "damage": Items.damage(item) * (0.25 + 0.75 * power), "pierce": int(Items.affix(item, "pierce")), "blast": Items.legend(item) == "blast"}
	var dirs: Array[Vector3] = [dir]
	if Items.legend(item) == "volley":
		var up := camera.global_transform.basis.y
		for a: float in [-0.2, -0.1, 0.1, 0.2]:
			dirs.append(dir.rotated(up, a))
	for d in dirs:
		game.projectiles.shoot(from + d * 0.45 - camera.global_transform.basis.y * 0.05, d * speed, true, info.duplicate())
	game.use_arrow(item)
	game.sfx.play("twang", randf_range(0.95, 1.1))
	_bow_kick = 1.0
	_kick += 0.015 * power


func _use_bomb(delta: float, held: bool) -> void:
	_throw_timer -= delta
	if not held or _throw_timer > 0.0:
		return
	_armed = false
	var kind: String = game.selected_explosive()
	if int(game.supplies[kind]) <= 0:
		game.toast("You have no %s. Buy some at the workbench." % String(Catalog.EXPLOSIVES[kind]["name"]).to_lower())
		return
	_throw_timer = 0.8
	game.supplies[kind] = int(game.supplies[kind]) - 1
	var dir := forward()
	game.projectiles.throw(eye() + dir * 0.5, dir * 11.0 + Vector3(0.0, 3.0, 0.0) + body.velocity * 0.5, kind)
	game.sfx.play("swing", 1.3, -4.0)
	game.hud.refresh()
	_throw_anim = 1.0


# Places a 50 cm block (4 by 4 by 4 cubes) of the selected material against the face you're
# looking at, lined up on a 50 cm grid along the face.
func _place_blocks(delta: float, held: bool) -> void:
	_place_timer -= delta
	if not held:
		_place_timer = 0.0
		return
	if target.is_empty() or target_enemy != null or _place_timer > 0.0:
		return
	_place_timer = PLACE_REPEAT
	var b: int = game.selected_material()
	if game.count(b) <= 0:
		game.toast("You have no %s to place. Dig some up first." % String(Blocks.NAMES[b]).to_lower())
		return
	var cell: Vector3i = target["cell"]
	var prev: Vector3i = target["prev"]
	var lo := prev
	for axis in 3:
		if prev[axis] == cell[axis]:
			lo[axis] = prev[axis] - posmod(prev[axis], 4)
		elif prev[axis] < cell[axis]:
			lo[axis] = prev[axis] - 3
	var cells: Array[Vector3i] = []
	var me_lo: Vector3 = body.lo() / World.VOXEL
	var me_hi: Vector3 = body.hi() / World.VOXEL
	for dz in 4:
		for dy in 4:
			for dx in 4:
				var c := lo + Vector3i(dx, dy, dz)
				var inside_me := me_lo.x < c.x + 1 and me_hi.x > c.x and me_lo.y < c.y + 1 and me_hi.y > c.y and me_lo.z < c.z + 1 and me_hi.z > c.z
				if world.can_place(c) and not inside_me:
					cells.append(c)
	if not cells.is_empty():
		game.on_blocks_placed(cells, b)


# A hit landed: the held item bounces back and the view shakes, harder for hard rock.
func impact(strength: float, hard: bool) -> void:
	_recoil_vel += (20.0 if hard else 11.0) * strength
	_hitstop = 0.05 if hard else 0.035
	shake((0.22 if hard else 0.1) * strength)
	_kick += 0.01 * strength


# --- Placing furniture ----------------------------------------------------------------------------

func start_placing(type: String) -> void:
	placing = {"type": type, "rot": House.rotation_facing(yaw), "ok": false}
	_armed = false


func cancel_placing() -> void:
	placing = {}
	_ghost.visible = false


func turn_placing() -> void:
	if not placing.is_empty():
		placing["rot"] = (int(placing["rot"]) + 1) % 4


func _update_placing() -> void:
	_outline.visible = false
	_plane.visible = false
	var type: String = placing["type"]
	var rot: int = placing["rot"]
	var size := House.furniture_size(type, rot)
	target = world.raycast(eye(), forward(), 6.0)
	placing["ok"] = false
	if not target.is_empty() and target["normal"] == Vector3i(0, 1, 0) and target["cell"].y == House.FLOOR - 1:
		var c: Vector3i = target["prev"]
		var x := c.x - size.x / 2
		var z := c.z - size.z / 2
		var lo := Vector3(x, House.FLOOR, z) * World.VOXEL
		var hi := lo + Vector3(size) * World.VOXEL
		var ok: bool = House.can_place_furniture(world, type, x, z, rot, game.house_tier) and not body.overlaps(lo, hi)
		placing["x"] = x
		placing["z"] = z
		placing["ok"] = ok
		_ghost.visible = true
		_ghost.position = (lo + hi) * 0.5
		_ghost.scale = Vector3(size) * World.VOXEL + Vector3(0.02, 0.02, 0.02)
		_ghost_mat.set_shader_parameter("color", Color(0.4, 1.0, 0.5, 0.3) if ok else Color(1.0, 0.35, 0.3, 0.3))
	else:
		_ghost.visible = false
	game.hud.set_target("Placing: %s  ·  click to place  ·  R to turn  ·  right click to put it away" % Catalog.FURNITURE[type]["name"], game.hud.GOLD)
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not lmb and not rmb:
		_armed = true
	if _armed and lmb:
		_armed = false
		if placing["ok"]:
			game.place_furniture(type, placing["x"], placing["z"], rot)
		else:
			game.sfx.play("clink", 0.9, -6.0)
			game.toast("It doesn't fit there. Find a clear spot on the floor of your house.")
	elif _armed and rmb:
		_armed = false
		game.stop_placing()


# --- What you hold ---------------------------------------------------------------------------

func refresh_view() -> void:
	for n: Node3D in _tools.values():
		n.queue_free()
	_tools.clear()
	if _bow:
		_bow.queue_free()
		_bow = null
	if _shield:
		_shield.queue_free()
		_shield = null
	_tools["pickaxe"] = _view_node(_hand, _pickaxe_boxes(game.equipped["pickaxe"]))
	_tools["leveler"] = _view_node(_hand, _trowel_boxes())
	if not game.equipped["sword"].is_empty():
		_tools["sword"] = _view_node(_hand, _sword_boxes(game.equipped["sword"]))
	if not game.equipped["mace"].is_empty():
		_tools["mace"] = _view_node(_hand, _mace_boxes(game.equipped["mace"]))
	_tools["bomb"] = _view_node(_hand, [])
	_refresh_bomb()
	if not game.equipped["bow"].is_empty():
		_bow = _view_node(camera, _bow_boxes(game.equipped["bow"]))
		_nocked = _view_node(_bow, [[Vector3(0, 0, -0.1), Vector3(0.012, 0.012, 0.62), Color(0.62, 0.45, 0.28)],
			[Vector3(0, 0, -0.43), Vector3(0.03, 0.03, 0.06), Color(0.62, 0.64, 0.68)],
			[Vector3(0, 0.02, 0.17), Vector3(0.005, 0.035, 0.08), Color(0.92, 0.9, 0.86)]])
	if not game.equipped["shield"].is_empty():
		_shield = _view_node(camera, _shield_boxes(game.equipped["shield"]))
	_update_visibility()


func _refresh_bomb() -> void:
	var node: Node3D = _tools.get("bomb")
	if node == null:
		return
	for c in node.get_children():
		c.queue_free()
	var kind: String = game.selected_explosive()
	var boxes := []
	if kind == "dynamite":
		boxes = [[Vector3.ZERO, Vector3(0.06, 0.2, 0.06), Color(0.8, 0.18, 0.12)], [Vector3(0, 0.0, 0), Vector3(0.065, 0.03, 0.065), Color(0.85, 0.8, 0.6)], [Vector3(0, 0.12, 0), Vector3(0.012, 0.05, 0.012), Color(0.9, 0.85, 0.7)]]
	else:
		boxes = [[Vector3.ZERO, Vector3(0.18, 0.12, 0.14), Color(0.3, 0.32, 0.36)], [Vector3.ZERO, Vector3(0.19, 0.03, 0.15), Color(0.85, 0.7, 0.2)], [Vector3(0, 0.08, 0), Vector3(0.015, 0.05, 0.015), Color(0.9, 0.85, 0.7)]]
	Models.instance(node, Models.build(boxes, false), Models.view_material())


func refresh_explosive() -> void:
	_refresh_bomb()


func _view_node(parent: Node3D, boxes: Array) -> Node3D:
	var node := Node3D.new()
	parent.add_child(node)
	if not boxes.is_empty():
		Models.instance(node, Models.build(boxes, false), Models.view_material())
	return node


func _update_visibility() -> void:
	var kind: String = SLOTS[slot]
	for k: String in _tools:
		_tools[k].visible = k == kind
	if _bow:
		_bow.visible = kind == "bow"
	if _shield:
		_shield.visible = kind == "sword" or kind == "mace"


static func _glow(item: Dictionary) -> float:
	return [0.0, 0.0, 0.12, 0.3, 0.7][item["rarity"]]


func _pickaxe_boxes(item: Dictionary) -> Array:
	var head: Color = Items.TIER_COLORS[item["tier"]]
	var g := _glow(item)
	var boxes := [
		[Vector3(0, 0.28, 0), Vector3(0.04, 0.6, 0.04), Color(0.55, 0.37, 0.21)],
		[Vector3(0, 0.02, 0), Vector3(0.05, 0.12, 0.05), Color(0.28, 0.2, 0.13)],
		[Vector3(0, 0.6, 0), Vector3(0.09, 0.08, 0.07), head, g],
		[Vector3(-0.13, 0.585, 0), Vector3(0.2, 0.05, 0.05), head, g, Vector3(0, 0, 0.22)],
		[Vector3(0.13, 0.585, 0), Vector3(0.2, 0.05, 0.05), head, g, Vector3(0, 0, -0.22)],
		[Vector3(-0.26, 0.545, 0), Vector3(0.08, 0.032, 0.032), head, g, Vector3(0, 0, 0.45)],
		[Vector3(0.26, 0.545, 0), Vector3(0.08, 0.032, 0.032), head, g, Vector3(0, 0, -0.45)],
	]
	if item["rarity"] > 0:
		boxes.append([Vector3(0, 0.46, 0), Vector3(0.046, 0.03, 0.046), Items.color(item), 0.5])
	return boxes


func _trowel_boxes() -> Array:
	return [
		[Vector3(0, 0, 0), Vector3(0.04, 0.16, 0.04), Color(0.55, 0.37, 0.21)],
		[Vector3(0, 0.1, -0.03), Vector3(0.016, 0.05, 0.07), Color(0.35, 0.35, 0.37)],
		[Vector3(0, 0.125, -0.18), Vector3(0.17, 0.012, 0.26), Color(0.7, 0.72, 0.76)],
	]


func _sword_boxes(item: Dictionary) -> Array:
	var metal: Color = Items.TIER_COLORS[item["tier"]]
	var g := _glow(item)
	var guard := Color(1.0, 0.8, 0.3) if item["rarity"] >= 2 else Color(0.4, 0.38, 0.36)
	return [
		[Vector3(0, 0, 0), Vector3(0.036, 0.16, 0.036), Color(0.3, 0.2, 0.12)],
		[Vector3(0, -0.095, 0), Vector3(0.05, 0.04, 0.05), guard],
		[Vector3(0, 0.095, 0), Vector3(0.2, 0.035, 0.05), guard],
		[Vector3(0, 0.46, 0), Vector3(0.056, 0.68, 0.016), metal, g],
		[Vector3(0, 0.83, 0), Vector3(0.03, 0.06, 0.014), metal, g],
		[Vector3(0, 0.44, -0.009), Vector3(0.016, 0.56, 0.004), metal.darkened(0.25), g],
		[Vector3(0, 0.0, 0), Vector3(0.04, 0.02, 0.04), Items.color(item), 0.5],
	]


func _mace_boxes(item: Dictionary) -> Array:
	var metal: Color = Items.TIER_COLORS[item["tier"]]
	var g := _glow(item)
	return [
		[Vector3(0, 0.2, 0), Vector3(0.04, 0.5, 0.04), Color(0.45, 0.3, 0.17)],
		[Vector3(0, 0.0, 0), Vector3(0.05, 0.14, 0.05), Color(0.3, 0.2, 0.12)],
		[Vector3(0, 0.5, 0), Vector3(0.13, 0.13, 0.13), metal, g],
		[Vector3(0.085, 0.5, 0), Vector3(0.04, 0.17, 0.04), metal.darkened(0.15), g],
		[Vector3(-0.085, 0.5, 0), Vector3(0.04, 0.17, 0.04), metal.darkened(0.15), g],
		[Vector3(0, 0.5, 0.085), Vector3(0.04, 0.17, 0.04), metal.darkened(0.15), g],
		[Vector3(0, 0.5, -0.085), Vector3(0.04, 0.17, 0.04), metal.darkened(0.15), g],
		[Vector3(0, 0.6, 0), Vector3(0.04, 0.07, 0.04), metal, g],
		[Vector3(0, 0.3, 0), Vector3(0.046, 0.03, 0.046), Items.color(item), 0.5],
	]


func _bow_boxes(item: Dictionary) -> Array:
	var wood: Color = Items.WOOD_COLORS[item["tier"]]
	var g := _glow(item)
	# Limbs sweep forward from the grip in three pieces each, so the curve shows.
	return [
		[Vector3(0, 0, 0), Vector3(0.05, 0.13, 0.055), Color(0.3, 0.2, 0.12)],
		[Vector3(0, 0.14, -0.015), Vector3(0.042, 0.17, 0.04), wood, g, Vector3(-0.12, 0, 0)],
		[Vector3(0, 0.29, -0.045), Vector3(0.036, 0.16, 0.034), wood, g, Vector3(-0.32, 0, 0)],
		[Vector3(0, 0.41, -0.09), Vector3(0.03, 0.12, 0.03), wood, g, Vector3(-0.55, 0, 0)],
		[Vector3(0, -0.14, -0.015), Vector3(0.042, 0.17, 0.04), wood, g, Vector3(0.12, 0, 0)],
		[Vector3(0, -0.29, -0.045), Vector3(0.036, 0.16, 0.034), wood, g, Vector3(0.32, 0, 0)],
		[Vector3(0, -0.41, -0.09), Vector3(0.03, 0.12, 0.03), wood, g, Vector3(0.55, 0, 0)],
		[Vector3(0, 0.47, -0.12), Vector3(0.034, 0.04, 0.034), Items.color(item), 0.4],
		[Vector3(0, -0.47, -0.12), Vector3(0.034, 0.04, 0.034), Items.color(item), 0.4],
		[Vector3(0, 0, 0.0), Vector3(0.006, 0.92, 0.006), Color(0.9, 0.9, 0.85), 0.0, Vector3(0, 0, 0)],
	]


func _shield_boxes(item: Dictionary) -> Array:
	var tier: int = item["tier"]
	var face: Color = Items.WOOD_COLORS[0] if tier == 0 else Items.TIER_COLORS[tier].darkened(0.2)
	var rim: Color = Color(0.4, 0.38, 0.36) if tier == 0 else Items.TIER_COLORS[tier]
	var leather := Color(0.35, 0.22, 0.13)
	var g := _glow(item)
	# The rim shows from both sides; the straps you hold it by are on the back.
	return [
		[Vector3(0, 0, 0), Vector3(0.44, 0.52, 0.04), face, g * 0.5],
		[Vector3(0, 0.27, 0), Vector3(0.46, 0.03, 0.06), rim, g],
		[Vector3(0, -0.27, 0), Vector3(0.46, 0.03, 0.06), rim, g],
		[Vector3(0.23, 0, 0), Vector3(0.03, 0.56, 0.06), rim, g],
		[Vector3(-0.23, 0, 0), Vector3(0.03, 0.56, 0.06), rim, g],
		[Vector3(0, 0, -0.035), Vector3(0.12, 0.12, 0.04), rim, g],
		[Vector3(0, 0, -0.022), Vector3(0.05, 0.5, 0.006), Items.color(item), 0.4],
		[Vector3(0, 0.09, 0.03), Vector3(0.34, 0.045, 0.02), leather],
		[Vector3(0, -0.09, 0.03), Vector3(0.34, 0.045, 0.02), leather],
		[Vector3(0.0, 0.0, 0.045), Vector3(0.05, 0.16, 0.03), leather],
		[Vector3(0, 0, 0.022), Vector3(0.05, 0.5, 0.006), Items.color(item), 0.4],
	]


func _build_detector() -> void:
	_detector = Node3D.new()
	camera.add_child(_detector)
	_detector.position = DETECTOR_POS
	_detector.rotation = Vector3(0.65, -0.3, 0.0)
	_detector.scale = Vector3(0.85, 0.85, 0.85)
	Models.instance(_detector, Models.build([
		[Vector3.ZERO, Vector3(0.14, 0.04, 0.2), Color(0.22, 0.26, 0.22)],
		[Vector3(0, -0.01, 0.15), Vector3(0.035, 0.035, 0.12), Color(0.12, 0.12, 0.12)],
		[Vector3(0, 0.022, -0.03), Vector3(0.1, 0.006, 0.08), Color(0.12, 0.3, 0.16)],
	], false), Models.view_material())
	var shader := Shader.new()
	shader.code = LED_SHADER
	_led_mat = ShaderMaterial.new()
	_led_mat.shader = shader
	Models.instance(_detector, Models.build([[Vector3(0.045, 0.024, 0.06), Vector3(0.025, 0.012, 0.025), Color(0.25, 0.9, 0.35)]], false), _led_mat)


# Puts everything you hold where it should be for this moment of the swing.
func _animate_view(delta: float) -> void:
	_hitstop -= delta
	var kind: String = SLOTS[slot]
	var bob := Vector3(0.0, sin(_bob * 2.0) * 0.01, 0.0)
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-delta * 8.0))
	var sway := Vector3(-_sway.x, _sway.y, 0.0).limit_length(0.05)
	# The bounce after a hit is a stiff spring.
	_recoil_vel += (-220.0 * _recoil - 18.0 * _recoil_vel) * delta
	_recoil += _recoil_vel * delta
	_swipe = move_toward(_swipe, 0.0, delta * 3.0)
	_throw_anim = move_toward(_throw_anim, 0.0, delta * 2.5)
	_bow_kick = move_toward(_bow_kick, 0.0, delta * 5.0)
	_block_blend = move_toward(_block_blend, 1.0 if blocking else 0.0, delta * 8.0)
	var tool: Node3D = _tools.get(kind)
	match kind:
		"pickaxe":
			# Wind up (raising and drawing back), then bring it down hard at the end.
			var lift := 0.0
			if _acting:
				var p := _action
				lift = sin(p / 0.62 * PI * 0.5) if p < 0.62 else lerpf(1.0, -1.0, pow((p - 0.62) / 0.38, 1.6))
			tool.rotation = PICK_ROT + Vector3(lift * (0.6 if lift > 0.0 else 0.95) + _recoil * 0.35, lift * 0.1, lift * 0.14)
			tool.position = PICK_POS + bob + sway + Vector3(0.0, maxf(lift, 0.0) * 0.13 + _recoil * 0.04, maxf(lift, 0.0) * 0.06 + _recoil * 0.03)
		"leveler":
			var s := sin(_swipe * PI)
			tool.rotation = TROWEL_ROT + Vector3(-0.6 * s, 0.5 * s, 0.0)
			tool.position = TROWEL_POS + bob + sway + Vector3(-0.12 * s, -0.04 * s, -0.18 * s)
		"sword":
			if tool:
				var s := 0.0
				if _acting:
					var p := _action
					if p < 0.35:
						s = smoothstep(0.0, 1.0, p / 0.35)
					elif p < 0.6:
						s = lerpf(1.0, -1.0, (p - 0.35) / 0.25)
					else:
						s = lerpf(-1.0, 0.0, smoothstep(0.0, 1.0, (p - 0.6) / 0.4))
				var d := 1.0 if _combo % 2 == 0 else -1.0
				tool.rotation = SWORD_ROT + Vector3(0.35 * absf(s) + _recoil * 0.3, -0.9 * s * d, -1.1 * s * d)
				tool.position = SWORD_POS + bob + sway + Vector3(0.22 * s * d, 0.1 * absf(s), -0.1 * absf(s))
		"mace":
			if tool:
				var s := 0.0
				if _acting:
					var p := _action
					if p < 0.55:
						s = sin(p / 0.55 * PI * 0.5)
					elif p < 0.7:
						s = lerpf(1.0, -1.0, (p - 0.55) / 0.15)
					else:
						s = lerpf(-1.0, 0.0, smoothstep(0.0, 1.0, (p - 0.7) / 0.3))
				tool.rotation = MACE_ROT + Vector3(s * (0.75 if s > 0.0 else 1.1) + _recoil * 0.3, 0.0, -0.25 * maxf(s, 0.0))
				tool.position = MACE_POS + bob + sway + Vector3(0.06 * maxf(s, 0.0), 0.12 * maxf(s, 0.0), -0.04 * maxf(s, 0.0))
		"bomb":
			# Draw back and throw; a fresh one comes up as the arm returns.
			var s := sin(_throw_anim * PI)
			tool.rotation = Vector3(-0.2 - 1.2 * s, -0.3, 0.2)
			tool.position = BOMB_POS + bob + sway + Vector3(0.0, 0.1 * s, 0.15 * s)
			tool.visible = _throw_anim < 0.5 and int(game.supplies[game.selected_explosive()]) > 0
	if _bow and _bow.visible:
		var d := _draw
		# Held a little left of centre, turned so you see the curve of the limbs, and canted
		# more as you draw.
		_bow.position = BOW_POS.lerp(Vector3(-0.04, -0.17, -0.48), d) + bob + sway + Vector3(0.0, 0.0, -0.04 * _bow_kick)
		_bow.rotation = Vector3(0.05, -0.55 + 0.25 * d, 0.25 + 0.1 * d)
		_nocked.visible = _drawing
		_nocked.position = Vector3(0.0, 0.0, 0.03 + 0.22 * d)
		_nocked.rotation.y = 0.55 - 0.25 * d
	if _shield and _shield.visible:
		var b := _block_blend
		_shield.position = SHIELD_POS.lerp(SHIELD_UP, b) + bob * 0.6 + Vector3(0.0, 0.0, 0.02 * _recoil)
		_shield.rotation = Vector3(0.1, 0.5, 0.0).lerp(Vector3(0.0, 0.05, 0.0), b)
	_detector.visible = game.detector_on and kind in ["pickaxe", "leveler", "bomb"]
	_led_glow = move_toward(_led_glow, 0.0, delta * 6.0)
	_led_mat.set_shader_parameter("glow", _led_glow * 2.0)


func _update_camera(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	_kick = move_toward(_kick, 0.0, delta * 0.4) * exp(-delta * 6.0)
	var t := Time.get_ticks_msec() / 1000.0
	var shake_amount := _trauma * _trauma
	var sx := (sin(t * 37.0) + sin(t * 53.0 + 1.3)) * 0.5 * shake_amount * 0.05
	var sy := (sin(t * 41.0 + 2.1) + sin(t * 59.0)) * 0.5 * shake_amount * 0.05
	var sz := sin(t * 47.0 + 0.7) * shake_amount * 0.04
	camera.rotation = Vector3(pitch + _kick + sx, sy, sz)
	var fov := 75.0 - 8.0 * _draw
	camera.fov = lerpf(camera.fov, fov, 1.0 - exp(-delta * 10.0))
	var ground_speed := Vector2(body.velocity.x, body.velocity.z).length()
	camera.position.y = _eye + _eye_offset + sin(_bob) * 0.035 * clampf(ground_speed / WALK_SPEED, 0.0, 1.0)


# --- Outlines -----------------------------------------------------------------------------------

func _draw_plane(cell: Vector3i, normal: Vector3i, half: int) -> void:
	var a := 0 if normal.x != 0 else (1 if normal.y != 0 else 2)
	var u := (a + 1) % 3
	var v := (a + 2) % 3
	var face := float(cell[a]) + (1.0 if normal[a] > 0 else 0.0) + float(normal[a]) * 0.02
	_plane_mesh.clear_surfaces()
	_plane_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	for inset: float in [0.0, 0.25]:
		var corners: Array[Vector3] = []
		for k: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var p := Vector3.ZERO
			p[a] = face
			p[u] = float(cell[u]) + k.x * (half - inset)
			p[v] = float(cell[v]) + k.y * (half - inset)
			corners.append(p * World.VOXEL)
		for k in 4:
			_plane_mesh.surface_add_vertex(corners[k])
			_plane_mesh.surface_add_vertex(corners[(k + 1) % 4])
	_plane_mesh.surface_end()


func _make_outline() -> MeshInstance3D:
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	var e := World.VOXEL * 0.5 + 0.003
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
