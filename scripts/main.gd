extends Node3D
# Deep Finds: take the stairs down from your room, dig through the ground with a metal detector
# and unearth lost treasure, then spend the coins on your pickaxe and your room.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Upgrades := preload("res://scripts/upgrades.gd")
const World := preload("res://scripts/world.gd")
const Room := preload("res://scripts/room.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SAVE_PATH := "user://deep_finds_save.json"
const SAVE_VERSION := 2
const DETECTOR_RANGE := 14.0
const AUTOSAVE_SECONDS := 30.0

var world
var player
var hud
var sfx
var env: Environment
var state := "starting"   # starting, loading, title, playing, journal, shop, paused, confirm
var inventory := {}       # block id -> count
var found := {}           # treasure type -> how many you've ever found
var coins := 0
var upgrades := {"head": 0, "grip": 0, "size": 0}
var room_owned: Array = []  # ids from Upgrades.ROOM, in the order they were bought
var hotbar_index := 0
var detector_on := true
var _has_save := false
var _new_game := false
var _beep_timer := 0.0
var _autosave := 0.0
var _time := 0.0
var _confirm_from := "title"
var _particle_mesh: BoxMesh


func _ready() -> void:
	_setup_input()
	_setup_environment()
	sfx = Sfx.new()
	add_child(sfx)
	world = World.new()
	add_child(world)
	player = Player.new()
	player.game = self
	player.world = world
	add_child(player)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.show_loading(0.0)
	# Let the loading screen draw before the world is generated.
	await get_tree().process_frame
	await get_tree().process_frame
	_start_world()


func _start_world() -> void:
	var save := _read_save()
	_has_save = not save.is_empty()
	_new_game = not _has_save
	world.generate(int(save["seed"]) if _has_save else randi())
	player.teleport(world.spawn_point())
	if _has_save:
		world.apply_edits_data(save.get("edits", {}))
		var saved_inventory: Dictionary = save.get("inventory", {})
		for k in saved_inventory:
			inventory[int(k)] = int(saved_inventory[k])
		var saved_found: Dictionary = save.get("found", {})
		for k in saved_found:
			found[int(k)] = int(saved_found[k])
		coins = int(save.get("coins", 0))
		var saved_upgrades: Dictionary = save.get("upgrades", {})
		for kind: String in upgrades:
			upgrades[kind] = clampi(int(saved_upgrades.get(kind, 0)), 0, Upgrades.PICKAXE[kind].size() - 1)
		for id in save.get("room", []):
			if Upgrades.room_index(str(id)) >= 0 and not room_owned.has(str(id)):
				room_owned.append(str(id))
		detector_on = bool(save.get("detector", true))
		hotbar_index = clampi(int(save.get("hotbar", 0)), 0, Blocks.HOTBAR.size() - 1)
		var p: Array = save.get("player", [])
		if p.size() == 5:
			player.teleport(Vector3(p[0], p[1], p[2]))
			player.set_look(p[3], p[4])
	for id: String in room_owned:
		Room.apply(world, id)
	Room.show_trophies(world, room_owned, found)
	world.set_lights(Room.lights(room_owned))
	player.set_head(upgrades["head"])
	world.queue_all_chunks(player.position)
	hud.refresh()
	state = "loading"


func _process(delta: float) -> void:
	if state == "starting":
		return
	_time += delta
	world.material.set_shader_parameter("lamp_pos", player.camera.global_position)
	world.update_lights(_time)
	if state == "loading":
		var progress: float = world.build_progress()
		hud.show_loading(progress)
		if progress >= 1.0:
			show_title()
	elif state == "playing":
		player.update(minf(delta, 0.05))
		_update_detector(delta)
		_autosave += delta
		if _autosave >= AUTOSAVE_SECONDS:
			_autosave = 0.0
			save_game()
	_update_atmosphere(delta)
	hud.set_depth(world.depth_at(player.position), Room.contains(World.cell_of(player.position + Vector3(0.0, 0.1, 0.0))))


func _unhandled_input(event: InputEvent) -> void:
	match state:
		"playing":
			if event.is_action_pressed("ui_cancel"):
				pause()
			elif event.is_action_pressed("detector"):
				detector_on = not detector_on
				_beep_timer = 0.0
			elif event.is_action_pressed("journal"):
				state = "journal"
				player.set_active(false)
				hud.show_journal(true)
			elif event.is_action_pressed("interact") and player.looking_at_workbench():
				open_shop()
			else:
				var mb := event as InputEventMouseButton
				if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					select_slot(hotbar_index - 1)
				elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					select_slot(hotbar_index + 1)
				for i in Blocks.HOTBAR.size():
					if event.is_action_pressed("slot_%d" % (i + 1)):
						select_slot(i)
		"journal":
			if event.is_action_pressed("journal") or event.is_action_pressed("ui_cancel"):
				hud.show_journal(false)
				state = "playing"
				player.set_active(true)
		"shop":
			if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
				resume()
		"paused":
			if event.is_action_pressed("ui_cancel"):
				resume()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and state not in ["starting", "loading"]:
		save_game()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == "playing":
		pause()


# --- Screens ----------------------------------------------------------------------

func show_title() -> void:
	state = "title"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_title(_has_save)


func start_playing() -> void:
	resume()
	if _new_game:
		_new_game = false
		toast("Take the stairs down, switch on your detector and start digging.")


func resume() -> void:
	state = "playing"
	hud.hide_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_active(true)


func pause() -> void:
	state = "paused"
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_pause()
	save_game()


func open_shop() -> void:
	state = "shop"
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_shop()


func return_to_room() -> void:
	player.teleport(world.spawn_point())
	player.set_look(0.0, 0.0)
	resume()


func ask_new_world() -> void:
	_confirm_from = state
	state = "confirm"
	hud.show_new_world_confirm()


func cancel_new_world() -> void:
	if _confirm_from == "paused":
		pause()
	else:
		show_title()


# A fresh patch of ground with new treasure. Coins, upgrades and finds carry over.
func new_world() -> void:
	var data := _save_data()
	data["seed"] = randi()
	data["edits"] = {}
	data.erase("player")
	_write_save(data)
	state = "starting"
	get_tree().reload_current_scene()


func save_and_quit() -> void:
	save_game()
	get_tree().quit()


# --- Digging, placing, treasure ---------------------------------------------------------

func selected_block() -> int:
	return Blocks.HOTBAR[hotbar_index]


func count(b: int) -> int:
	return inventory.get(b, 0)


func found_count() -> int:
	var n := 0
	for t: int in found:
		n += int(found[t])
	return n


func select_slot(i: int) -> void:
	hotbar_index = posmod(i, Blocks.HOTBAR.size())
	hud.refresh()


func toast(text: String, color := Color(0.93, 0.91, 0.86)) -> void:
	hud.toast(text, color)


# Seconds per swing at block b: faster with a better grip, and with a head stronger than needed.
func swing_time(b: int) -> float:
	var base: float = Blocks.DIG_TIME[b] if Blocks.DIG_TIME[b] > 0.0 else 0.45
	var spare := maxi(0, int(upgrades["head"]) - maxi(int(Blocks.TIER[b]), 0))
	return base * pow(0.85, spare) / float(Upgrades.GRIPS[upgrades["grip"]]["speed"])


func on_swing_hit(target: Dictionary) -> void:
	var cell: Vector3i = target["cell"]
	var b: int = target["block"]
	var tier: int = Blocks.TIER[b]
	if tier < 0:
		sfx.play("clink", randf_range(0.9, 1.1), -4.0)
		if b == Blocks.BEDROCK:
			toast("Bedrock. Nothing digs through this.")
		elif b == Blocks.BRICK:
			toast("These bricks hold the stairs up. Better leave them be.")
		else:
			toast("Better not dig up your own room.")
		return
	if tier > upgrades["head"]:
		sfx.play("clink", randf_range(0.9, 1.1), -4.0)
		toast("Too hard! %s needs %s pick head. Upgrade it at your workbench." % [Blocks.NAMES[b], Upgrades.head_name(tier)], Color(1.0, 0.65, 0.5))
		return
	var result: Dictionary = world.carve(cell, Upgrades.SIZES[upgrades["size"]]["radius"], upgrades["head"])
	sfx.play("dig", randf_range(0.8, 1.15), -3.0)
	if int(result["removed"]) > 0:
		sfx.play("break", randf_range(0.85, 1.1), -2.0)
		_burst(World.center_of(cell), Blocks.COLORS[b])
	var drops: Dictionary = result["drops"]
	for d: int in drops:
		inventory[d] = count(d) + int(drops[d])
	for t: int in result["treasures"]:
		_found_treasure(int(world.treasure_list[t]["type"]), world.treasure_list[t]["center"])
	hud.refresh()


func on_blocks_placed(cells: Array[Vector3i], b: int) -> void:
	var n := mini(cells.size(), count(b))
	for k in n:
		world.set_block(cells[k], b)
	inventory[b] = count(b) - n
	sfx.play("place", randf_range(0.9, 1.1))
	hud.refresh()


func _found_treasure(t: int, where: Vector3) -> void:
	found[t] = int(found.get(t, 0)) + 1
	var info: Dictionary = Treasures.LIST[t]
	coins += int(info["value"])
	sfx.play("treasure")
	_burst(where, Hud.GOLD)
	hud.show_find(t)
	Room.show_trophies(world, room_owned, found)
	if world.remaining_treasures() == 0:
		toast("Every treasure here has been found! Start a new dig site from the pause menu.", Hud.GOLD)
	save_game()


func _update_detector(delta: float) -> void:
	if not detector_on:
		hud.set_detector(false, 0.0, false)
		return
	var distance: float = world.nearest_treasure_distance(player.camera.global_position)
	var strength := clampf(1.0 - distance / DETECTOR_RANGE, 0.0, 1.0)
	var beeped := false
	if strength > 0.0:
		_beep_timer -= delta
		if _beep_timer <= 0.0:
			_beep_timer = lerpf(1.1, 0.08, pow(strength, 1.3))
			sfx.play("beep", 0.8 + strength * 0.9, -8.0 + strength * 6.0)
			player.flash_led(strength)
			beeped = true
	hud.set_detector(true, strength, beeped)


func _burst(where: Vector3, color: Color) -> void:
	if _particle_mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		_particle_mesh = BoxMesh.new()
		_particle_mesh.size = Vector3(0.07, 0.07, 0.07)
		_particle_mesh.material = mat
	var p := CPUParticles3D.new()
	p.mesh = _particle_mesh
	p.amount = 18
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 80.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	p.color = color * 0.85
	p.position = where
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# --- Buying -----------------------------------------------------------------------------

func buy_pickaxe(kind: String) -> void:
	var list: Array = Upgrades.PICKAXE[kind]
	var level: int = upgrades[kind]
	if level + 1 >= list.size() or coins < int(list[level + 1]["cost"]):
		return
	coins -= int(list[level + 1]["cost"])
	upgrades[kind] = level + 1
	player.set_head(upgrades["head"])
	_bought()


func buy_room(id: String) -> void:
	var i := Upgrades.room_index(id)
	if i < 0 or room_owned.has(id) or coins < int(Upgrades.ROOM[i]["cost"]):
		return
	coins -= int(Upgrades.ROOM[i]["cost"])
	room_owned.append(id)
	Room.apply(world, id)
	Room.show_trophies(world, room_owned, found)
	world.set_lights(Room.lights(room_owned))
	_bought()


func _bought() -> void:
	sfx.play("buy")
	hud.refresh()
	hud.show_shop()
	save_game()


# --- Setup and saving -------------------------------------------------------------------

func _update_atmosphere(delta: float) -> void:
	var home := 1.0 if world.depth_at(player.position) < 0.5 else 0.0
	env.fog_density = lerpf(env.fog_density, lerpf(0.035, 0.006, home), 1.0 - exp(-delta * 2.0))


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],
		"detector": [KEY_F],
		"journal": [KEY_TAB, KEY_J],
		"interact": [KEY_E],
	}
	for i in Blocks.HOTBAR.size():
		keys["slot_%d" % (i + 1)] = [KEY_1 + i]
	# Physical keys, so WASD sits in the same place on AZERTY keyboards (ZQSD).
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.016, 0.012)
	env.fog_density = 0.006
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _save_data() -> Dictionary:
	var p: Vector3 = player.position
	return {
		"version": SAVE_VERSION,
		"seed": world.world_seed,
		"edits": world.edits_data(),
		"inventory": inventory,
		"found": found,
		"coins": coins,
		"upgrades": upgrades,
		"room": room_owned,
		"player": [p.x, p.y, p.z, player.yaw, player.pitch],
		"detector": detector_on,
		"hotbar": hotbar_index,
	}


func save_game() -> void:
	if state in ["starting", "loading"]:
		return
	_write_save(_save_data())
	_has_save = true


func _write_save(data: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary and parsed.has("seed") and int(parsed.get("version", 0)) == SAVE_VERSION:
		return parsed
	return {}
