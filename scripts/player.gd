extends Node3D
# You: first-person walking (ducking and crawling through tight spots on your own), health and
# stamina, and what you hold: the pickaxe (left click digs, right click flattens), a sword or a
# mace (with your shield on the other arm), or explosives. Only digging, swinging a weapon and
# blocking with your shield tire you out; running and jumping never do.

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
const CRAWL_SPEED := 1.5
const JUMP_SPEED := 7.6
const GRAVITY := 24.0
const HALF_WIDTH := 0.22
const HEIGHT := 1.75
const CROUCH_HEIGHT := 1.0
const CRAWL_HEIGHT := 0.55    # the lowest you squeeze down to in a tight spot
const EYE_GAP := 0.14         # your eyes sit this far below the top of your head
const REACH := 4.0
const MOUSE_SENSITIVITY := 0.0025
const BASE_HEALTH := 100.0
const BASE_STAMINA := 100.0
const STAMINA_REGEN := 28.0
const SLOTS := ["pickaxe", "sword", "mace", "bomb"]
const SLOT_NAMES := ["Pickaxe", "Sword", "Mace", "Explosives"]

# The pickaxe's poses as [grip position, rotation]: resting, raised over your shoulder, and the
# moment it strikes. Its head runs front to back, so the front spike leads the swing and bites
# into the middle of the view.
const PICK_REST := [Vector3(0.36, -0.56, -0.58), Vector3(-0.45, 0.1, -0.25)]
const PICK_RAISED := [Vector3(0.38, -0.42, -0.45), Vector3(0.45, 0.15, -0.3)]
const PICK_STRIKE := [Vector3(0.18, -0.5, -0.46), Vector3(-0.7, 0.25, 0.12)]
# Where everything else rests in front of the camera.
const SWORD_POS := Vector3(0.36, -0.5, -0.62)
const SWORD_ROT := Vector3(-0.55, -0.2, -0.25)
const MACE_POS := Vector3(0.38, -0.58, -0.64)
const MACE_ROT := Vector3(-0.45, -0.3, 0.2)
const BOMB_POS := Vector3(0.3, -0.38, -0.56)
const SHIELD_POS := Vector3(-0.46, -0.48, -0.62)
const SHIELD_UP := Vector3(-0.12, -0.26, -0.44)

var game
var world
var camera: Camera3D
var body
var yaw := 0.0
var pitch := 0.0
var crouching := false    # holding the crouch key (you also duck on your own where it's low)
var target := {}          # what's under the crosshair, from world.raycast()
var target_enemy = null   # the guard under the crosshair, if nearer than the block
var slot := 0
var health := BASE_HEALTH
var stamina := BASE_STAMINA
var exhausted := false
var blocking := false
var placing := {}         # furniture being placed: {"type", "rot", "x", "z", "ok"}
var _active := false
var _eye := HEIGHT - EYE_GAP
var _eye_offset := 0.0
var _armed := false       # waits for a fresh click, so the click that closes a menu does nothing
var _acting := false
var _action := 0.0        # how far through the current swing, 0 to 1
var _hit_done := false
var _combo := 0
var _flattening := false  # the swing under way is a flattening one (right click)
var _follow := 0.0        # the pickaxe's follow-through after it lands, 1 down to 0
var _throw_timer := 0.0
var _throw_anim := 0.0
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
var _hand: Node3D
var _tools := {}          # slot name -> Node3D in your right hand
var _shield: Node3D
var _line_mat: StandardMaterial3D
var _outline: MeshInstance3D
var _ring: MeshInstance3D       # where the pickaxe will dent the ground
var _plane: MeshInstance3D
var _plane_mesh: ImmediateMesh
var _ghost: MeshInstance3D
var _ghost_mat: ShaderMaterial


func _ready() -> void:
	body = Body.new()
	body.world = world
	body.set_size(HALF_WIDTH, HEIGHT, CRAWL_HEIGHT)
	body.step_height = 3.0 * World.VOXEL + 0.02
	camera = Camera3D.new()
	camera.position.y = _eye
	camera.fov = 75.0
	camera.near = 0.03
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	_hand = Node3D.new()
	camera.add_child(_hand)
	_outline = _make_outline()
	add_child(_outline)
	_ring = _make_ring()
	add_child(_ring)
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
	_action = 0.0
	blocking = false
	if not active:
		_outline.visible = false
		_ring.visible = false
		_plane.visible = false
		target = {}
		target_enemy = null


func forward() -> Vector3:
	return -camera.global_transform.basis.z


func eye() -> Vector3:
	return camera.global_position


# Moves somewhere, ducking if the space is low, or popping up a little out of anything solid.
# Back to the house if there's no room nearby.
func teleport(p: Vector3) -> void:
	body.velocity = Vector3.ZERO
	body.height = HEIGHT
	for rise in 25:
		var at := p + Vector3(0.0, rise * World.VOXEL, 0.0)
		var room: float = body.room_at(at)
		if room >= CRAWL_HEIGHT:
			body.position = at
			body.cur_height = room
			position = at
			return
	body.position = world.spawn_point()
	body.cur_height = HEIGHT
	position = body.position


func max_health() -> float:
	return BASE_HEALTH + game.global_affix("vitality")


func max_stamina() -> float:
	return BASE_STAMINA * (1.25 if game.rested > 0.0 else 1.0)


func heal(amount: float) -> void:
	health = minf(max_health(), health + amount)


func select(i: int) -> void:
	slot = posmod(i, SLOTS.size())
	_acting = false
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
	# Holding crouch keeps you low; anywhere too low to stand, you duck or crawl on your own and
	# stand back up once there's room.
	crouching = Input.is_action_pressed("crouch")
	body.height = CROUCH_HEIGHT if crouching else HEIGHT
	body.cur_height = minf(body.cur_height, body.height)
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	var speed := WALK_SPEED
	var tall: float = body.cur_height
	if tall < CROUCH_HEIGHT - 0.05:
		speed = CRAWL_SPEED
	elif tall < HEIGHT - 0.05:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint") and input.length() > 0.1 and not blocking:
		speed = SPRINT_SPEED
	if blocking:
		speed *= 0.45 * (1.0 + game.global_affix("swift") / 100.0)
	speed *= 1.0 + game.global_affix("swift") / 100.0
	var v: Vector3 = body.velocity
	var blend := 1.0 - exp(-delta * (12.0 if body.on_floor else 3.0))
	v.x = lerpf(v.x, wish.x * speed, blend)
	v.z = lerpf(v.z, wish.z * speed, blend)
	if body.on_floor and not crouching and tall > CROUCH_HEIGHT and Input.is_action_pressed("jump"):
		v.y = JUMP_SPEED
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
	# Your eyes follow your height, but drop at once under a low ceiling so you never see
	# through it.
	var eye_height: float = body.cur_height - EYE_GAP
	_eye = move_toward(_eye, eye_height, delta * (6.0 if _eye > eye_height else 3.0))
	if body.cur_height < HEIGHT:
		_eye = minf(_eye, world.headroom(body.lo(), body.hi(), HEIGHT) - 0.1)
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
	var lmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not lmb and not rmb:
		_armed = true
	var use := lmb and _armed
	var flat := rmb and _armed and not lmb
	blocking = false
	_show_aim(kind, flat or (_acting and _flattening))
	game.show_target()
	match kind:
		"pickaxe":
			_use_pickaxe(delta, use, flat)
		"sword", "mace":
			blocking = rmb and _armed and not game.equipped["shield"].is_empty() and not exhausted and not _acting
			_use_melee(delta, use and not blocking, kind)
		"bomb":
			_use_bomb(delta, use)


# With the pickaxe: a ring on the ground where the next blow will dent it, the disc it will
# flatten while you hold the right button, or an outline round a built block.
func _show_aim(kind: String, flat: bool) -> void:
	_outline.visible = false
	_ring.visible = false
	_plane.visible = false
	if kind != "pickaxe" or target.is_empty() or target_enemy != null:
		return
	if flat and target["face"] != Vector3i.ZERO:
		_plane.visible = true
		_draw_plane(target["point"], target["face"], game.dig_radius())
	elif Blocks.is_ground(target["block"]):
		var up: Vector3 = target["normal"]
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		var r: float = game.dig_radius() * World.VOXEL * 0.75
		_ring.visible = true
		_ring.global_transform = Transform3D(Basis(side * r, up, side.cross(up) * r), target["point"] + up * 0.01)
	else:
		_outline.visible = true
		_outline.position = World.center_of(target["cell"])


func _note_tired() -> void:
	if _tired_note <= 0.0:
		_tired_note = 2.5
		game.toast("Too tired! Wait for your stamina to come back.", Color(1.0, 0.75, 0.45))


# Hold the left button to dig, the right to flatten: each swing lands when it's gone all the way
# round, and the next one starts straight after.
func _use_pickaxe(delta: float, held: bool, flat: bool) -> void:
	var item: Dictionary = game.equipped["pickaxe"]
	if held or flat:
		if not _acting:
			_flattening = flat and not held
		_acting = true
		var t := 0.6
		if target_enemy != null and not _flattening:
			t = Items.attack_time(item)
		elif not target.is_empty() and float(target["dist"]) <= REACH:
			t = game.swing_time(target["block"]) * (1.25 if _flattening else 1.0)
		if exhausted:
			t /= 0.55
		if _hitstop <= 0.0:
			_action += delta / t
		if _action >= 1.0:
			_action = 0.0
			_follow = 1.0
			spend(Items.stamina_cost(item))
			if _flattening:
				if not target.is_empty() and target["face"] != Vector3i.ZERO and target_enemy == null:
					game.on_flatten(target)
				else:
					game.sfx.play("swing", randf_range(1.1, 1.3), -8.0)
			elif target_enemy != null:
				game.melee_hit(target_enemy, item, Items.damage(item), {"knockback": 3.0})
				impact(0.7, false)
			elif not target.is_empty():
				game.on_swing_hit(target)
			else:
				game.sfx.play("swing", randf_range(1.1, 1.3), -8.0)
			_flattening = flat and not held
	else:
		_acting = false
		_flattening = false
		_action = move_toward(_action, 0.0, delta * 3.0)


func _use_melee(delta: float, held: bool, kind: String) -> void:
	var item: Dictionary = game.equipped[kind]
	if item.is_empty():
		if held:
			game.toast("You don't have a %s yet. They turn up in the chests of hidden rooms." % kind)
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
			game.earthshake(item, wall["point"], damage)
	else:
		impact(0.5 if kind == "sword" else 0.9, false)
		if legend == "earthshaker":
			game.earthshake(item, targets[0].body.position, damage)


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
	_ring.visible = false
	_plane.visible = false
	var type: String = placing["type"]
	var rot: int = placing["rot"]
	var size := House.furniture_size(type, rot)
	target = world.raycast(eye(), forward(), 6.0)
	placing["ok"] = false
	if not target.is_empty() and target["face"] == Vector3i(0, 1, 0) and target["cell"].y == House.FLOOR - 1:
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
	if _shield:
		_shield.queue_free()
		_shield = null
	_tools["pickaxe"] = _view_node(_hand, _pickaxe_boxes(game.equipped["pickaxe"]))
	if not game.equipped["sword"].is_empty():
		_tools["sword"] = _view_node(_hand, _sword_boxes(game.equipped["sword"]))
	if not game.equipped["mace"].is_empty():
		_tools["mace"] = _view_node(_hand, _mace_boxes(game.equipped["mace"]))
	_tools["bomb"] = _view_node(_hand, [])
	_refresh_bomb()
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
	if _shield:
		_shield.visible = kind == "sword" or kind == "mace"


static func _glow(item: Dictionary) -> float:
	return [0.0, 0.0, 0.12, 0.3, 0.7][item["rarity"]]


func _pickaxe_boxes(item: Dictionary) -> Array:
	var head: Color = Items.TIER_COLORS[item["tier"]]
	var g := _glow(item)
	# The head runs front to back (along z), in the plane of the swing.
	var boxes := [
		[Vector3(0, 0.28, 0), Vector3(0.04, 0.6, 0.04), Color(0.55, 0.37, 0.21)],
		[Vector3(0, 0.02, 0), Vector3(0.05, 0.12, 0.05), Color(0.28, 0.2, 0.13)],
		[Vector3(0, 0.6, 0), Vector3(0.07, 0.08, 0.09), head, g],
		[Vector3(0, 0.585, -0.13), Vector3(0.05, 0.05, 0.2), head, g, Vector3(-0.22, 0, 0)],
		[Vector3(0, 0.585, 0.13), Vector3(0.05, 0.05, 0.2), head, g, Vector3(0.22, 0, 0)],
		[Vector3(0, 0.545, -0.26), Vector3(0.032, 0.032, 0.08), head, g, Vector3(-0.45, 0, 0)],
		[Vector3(0, 0.545, 0.26), Vector3(0.032, 0.032, 0.08), head, g, Vector3(0.45, 0, 0)],
	]
	if item["rarity"] > 0:
		boxes.append([Vector3(0, 0.46, 0), Vector3(0.046, 0.03, 0.046), Items.color(item), 0.5])
	return boxes


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


func _shield_boxes(item: Dictionary) -> Array:
	var tier: int = item["tier"]
	var face: Color = Items.TIER_COLORS[0] if tier == 0 else Items.TIER_COLORS[tier].darkened(0.2)
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
	_throw_anim = move_toward(_throw_anim, 0.0, delta * 2.5)
	_block_blend = move_toward(_block_blend, 1.0 if blocking else 0.0, delta * 8.0)
	var tool: Node3D = _tools.get(kind)
	match kind:
		"pickaxe":
			# Wind up over your shoulder, bring it down head first, and follow through for a
			# moment after it lands.
			_follow = move_toward(_follow, 0.0, delta * 5.0)
			var lift := 0.0
			if _acting:
				var p := _action
				lift = sin(p / 0.62 * PI * 0.5) if p < 0.62 else lerpf(1.0, -1.0, pow((p - 0.62) / 0.38, 1.6))
			lift = lerpf(lift, -1.0, _follow * _follow)
			var pose := _pick_pose(lift)
			var rot: Vector3 = pose[1]
			# Flattening swings come down flatter, the head skimming the surface.
			var skim := 0.45 if _flattening else 0.0
			tool.position = pose[0] + bob + sway + Vector3(0.0, _recoil * 0.03 + 0.06 * skim, _recoil * 0.03)
			tool.rotation = rot + Vector3(_recoil * 0.35 + skim * maxf(-lift, 0.0), 0.0, -skim * 0.5)
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
	if _shield and _shield.visible:
		var b := _block_blend
		_shield.position = SHIELD_POS.lerp(SHIELD_UP, b) + bob * 0.6 + Vector3(0.0, 0.0, 0.02 * _recoil)
		_shield.rotation = Vector3(0.1, 0.5, 0.0).lerp(Vector3(0.0, 0.05, 0.0), b)


# The pickaxe part of the way between its poses: 0 at rest, 1 raised, -1 striking.
static func _pick_pose(lift: float) -> Array:
	var to: Array = PICK_RAISED if lift > 0.0 else PICK_STRIKE
	var t := absf(lift)
	var rest_pos: Vector3 = PICK_REST[0]
	var rest_rot: Vector3 = PICK_REST[1]
	return [rest_pos.lerp(to[0], t), rest_rot.lerp(to[1], t)]


func _update_camera(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 1.8)
	_kick = move_toward(_kick, 0.0, delta * 0.4) * exp(-delta * 6.0)
	var t := Time.get_ticks_msec() / 1000.0
	var shake_amount := _trauma * _trauma
	var sx := (sin(t * 37.0) + sin(t * 53.0 + 1.3)) * 0.5 * shake_amount * 0.05
	var sy := (sin(t * 41.0 + 2.1) + sin(t * 59.0)) * 0.5 * shake_amount * 0.05
	var sz := sin(t * 47.0 + 0.7) * shake_amount * 0.04
	camera.rotation = Vector3(pitch + _kick + sx, sy, sz)
	var ground_speed := Vector2(body.velocity.x, body.velocity.z).length()
	camera.position.y = _eye + _eye_offset + sin(_bob) * 0.035 * clampf(ground_speed / WALK_SPEED, 0.0, 1.0)


# --- Outlines -----------------------------------------------------------------------------------

# The disc a flattening blow will level, where the new surface will be (see World.flatten):
# `radius` cells across, the same as the pickaxe's dent.
func _draw_plane(point: Vector3, face: Vector3i, radius: float) -> void:
	var a := 0 if face.x != 0 else (1 if face.y != 0 else 2)
	var u := (a + 1) % 3
	var v := (a + 2) % 3
	var c := point / World.VOXEL
	var level := roundf(c[a]) + float(face[a]) * 0.02
	var cu := floorf(c[u])
	var cv := floorf(c[v])
	_plane_mesh.clear_surfaces()
	_plane_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	for inset: float in [0.0, 0.35]:
		var points: Array[Vector3] = []
		for k in 24:
			var p := Vector3.ZERO
			p[a] = level
			p[u] = cu + cos(k * TAU / 24.0) * (radius - inset)
			p[v] = cv + sin(k * TAU / 24.0) * (radius - inset)
			points.append(p * World.VOXEL)
		for k in 24:
			_plane_mesh.surface_add_vertex(points[k])
			_plane_mesh.surface_add_vertex(points[(k + 1) % 24])
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


# A circle one metre across, lying flat; it's turned and sized to sit on the ground. Drawn over
# everything, faintly, so a bump in the way doesn't hide it.
func _make_ring() -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for k in 32:
		im.surface_add_vertex(Vector3(cos(k * TAU / 32.0), 0.0, sin(k * TAU / 32.0)))
		im.surface_add_vertex(Vector3(cos((k + 1) * TAU / 32.0), 0.0, sin((k + 1) * TAU / 32.0)))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.top_level = true
	mi.visible = false
	return mi


static func _cube_corner(i: int, e: float) -> Vector3:
	return Vector3(e if i & 1 else -e, e if i & 2 else -e, e if i & 4 else -e)
