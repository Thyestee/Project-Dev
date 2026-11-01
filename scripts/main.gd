extends Node3D
# Deep Finds: dig through a voxel field with a metal detector and unearth lost treasure.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Textures := preload("res://scripts/textures.gd")
const World := preload("res://scripts/world.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Sfx := preload("res://scripts/sfx.gd")

const SAVE_PATH := "user://deep_finds_save.json"
const DETECTOR_RANGE := 16.0
const AUTOSAVE_SECONDS := 30.0
const SKY_FOG := Color(0.68, 0.78, 0.88)
const CAVE_FOG := Color(0.015, 0.012, 0.01)

var world
var player
var hud
var sfx
var env: Environment
var state := "starting"   # starting, loading, title, playing, journal, paused, confirm
var inventory := {}       # block id -> count
var found := {}           # treasure type -> count
var total_value := 0
var hotbar_index := 0
var detector_on := true
var _has_save := false
var _beep_timer := 0.0
var _exposure := 1.0
var _autosave := 0.0
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
	world.generate(int(save["seed"]) if _has_save else randi())
	player.teleport(world.spawn_point())
	if _has_save:
		world.apply_edits(save.get("edits", []))
		var saved_inventory: Dictionary = save.get("inventory", {})
		for k in saved_inventory:
			inventory[int(k)] = int(saved_inventory[k])
		var saved_found: Dictionary = save.get("found", {})
		for k in saved_found:
			found[int(k)] = int(saved_found[k])
		total_value = int(save.get("value", 0))
		detector_on = bool(save.get("detector", true))
		hotbar_index = clampi(int(save.get("hotbar", 0)), 0, Blocks.HOTBAR.size() - 1)
		var p: Array = save.get("player", [])
		if p.size() == 5:
			player.teleport(Vector3(p[0], p[1], p[2]))
			player.set_look(p[3], p[4])
	world.queue_all_chunks(player.position)
	hud.refresh()
	state = "loading"


func _process(delta: float) -> void:
	if state == "starting":
		return
	world.material.set_shader_parameter("lamp_pos", player.camera.global_position)
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
	hud.set_depth(world.depth_at(player.position))


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


func return_to_surface() -> void:
	player.teleport(world.surface_point(player.position))
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


func new_world() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
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


func on_block_dug(cell: Vector3i, b: int) -> void:
	var treasure: Dictionary = world.treasure_at(cell)
	world.set_block(cell, Blocks.AIR)
	_burst(cell, b)
	sfx.play("break", randf_range(0.85, 1.1))
	if not treasure.is_empty():
		_found_treasure(int(treasure["type"]))
		return
	var drop: int = Blocks.DROPS[b]
	if drop != Blocks.AIR:
		inventory[drop] = count(drop) + 1
	hud.refresh()


func on_block_placed(cell: Vector3i, b: int) -> void:
	world.set_block(cell, b)
	inventory[b] = count(b) - 1
	sfx.play("place", randf_range(0.9, 1.1))
	hud.refresh()


func _found_treasure(t: int) -> void:
	found[t] = int(found.get(t, 0)) + 1
	var info: Dictionary = Treasures.LIST[t]
	total_value += int(info["value"])
	sfx.play("treasure")
	hud.show_find(t)
	hud.refresh()
	if world.treasures.is_empty():
		toast("Every treasure in this world has been found! Start a new world from the pause menu.", Hud.GOLD)
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


func _burst(cell: Vector3i, b: int) -> void:
	if _particle_mesh == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		_particle_mesh = BoxMesh.new()
		_particle_mesh.size = Vector3(0.12, 0.12, 0.12)
		_particle_mesh.material = mat
	var p := CPUParticles3D.new()
	p.mesh = _particle_mesh
	p.amount = 14
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.3, 0.3)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.color = Hud.GOLD if Blocks.is_treasure(b) else Textures.average[Blocks.TILE_SIDE[b]] * 0.85
	p.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# Fog fades from sky haze to darkness as you go underground.
func _update_atmosphere(delta: float) -> void:
	var sky: float = world.sky_at(player.camera.global_position)
	_exposure = lerpf(_exposure, sky, 1.0 - exp(-delta * 2.5))
	env.fog_light_color = CAVE_FOG.lerp(SKY_FOG, _exposure)
	env.fog_density = lerpf(0.03, 0.01, _exposure)


# --- Setup and saving -------------------------------------------------------------------

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"detector": [KEY_F],
		"journal": [KEY_TAB, KEY_J],
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
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.5, 0.82)
	sky_mat.sky_horizon_color = SKY_FOG
	sky_mat.ground_horizon_color = SKY_FOG
	sky_mat.ground_bottom_color = Color(0.35, 0.4, 0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_enabled = true
	env.fog_light_color = SKY_FOG
	env.fog_density = 0.01
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# Only lights the sky (the sun disc); blocks do their own lighting.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)


func save_game() -> void:
	if state in ["starting", "loading"]:
		return
	var p: Vector3 = player.position
	var data := {
		"version": 1,
		"seed": world.world_seed,
		"edits": world.edits_list(),
		"inventory": inventory,
		"found": found,
		"value": total_value,
		"player": [p.x, p.y, p.z, player.yaw, player.pitch],
		"detector": detector_on,
		"hotbar": hotbar_index,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	_has_save = true


func _read_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary and parsed.has("seed"):
		return parsed
	return {}
