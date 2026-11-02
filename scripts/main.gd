extends Node3D
# Deep Finds: take the stairs down from your house, dig for lost treasure with a metal detector,
# break into hidden rooms and fight their guards for better gear, and spend what you find on
# your gear and your house.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Items := preload("res://scripts/items.gd")
const Catalog := preload("res://scripts/catalog.gd")
const World := preload("res://scripts/world.gd")
const House := preload("res://scripts/house.gd")
const Vaults := preload("res://scripts/vaults.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Menus := preload("res://scripts/menus.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Effects := preload("res://scripts/effects.gd")
const Enemies := preload("res://scripts/enemies.gd")
const Projectiles := preload("res://scripts/projectiles.gd")

const SAVE_PATH := "user://deep_finds_save.json"
const SAVE_VERSION := 3
const DETECTOR_RANGE := 14.0
const AUTOSAVE_SECONDS := 30.0
const BAG_SIZE := 16
const RESTED_SECONDS := 600.0
const LEVEL_CUT := 12
const LEVEL_FILL := 8

var world
var player
var hud
var menus
var sfx
var effects
var enemies
var projectiles
var env: Environment
var state := "starting"   # starting, loading, title, playing, menu, paused, confirm, dead
var materials := {}       # block id -> count
var found := {}           # treasure type -> how many you've ever found
var coins := 0
var bag: Array = []       # gear in your pack
var equipped := {"pickaxe": {}, "sword": {}, "mace": {}, "bow": {}, "shield": {}}
var supplies := {"arrows": 0, "dynamite": 0, "charge": 0}
var workshop := {"grip": 0, "size": 0}
var house_tier := 0
var decor: Array = []         # decorations you own, in the order you bought them
var furniture: Array = []     # placed furniture: {"id", "type", "x", "z", "rot"}
var unplaced: Array = []      # furniture you've bought or picked up but not put down yet
var storage := {}             # furniture id (as text) -> the gear inside
var next_furniture_id := 1
var vault_state: Array = []   # per hidden room: {"opened", "dead": [guard numbers], "chests": {number: [gear]}}
var material_index := 0
var explosive_index := 0
var detector_on := true
var rested := 0.0
var tracked := -1             # the hidden room your compass points at
var _rng := RandomNumberGenerator.new()
var _has_save := false
var _new_game := false
var _beep_timer := 0.0
var _autosave := 0.0
var _time := 0.0


func _ready() -> void:
	_rng.randomize()
	_setup_input()
	_setup_environment()
	sfx = Sfx.new()
	add_child(sfx)
	world = World.new()
	add_child(world)
	effects = Effects.new()
	effects.material = world.material
	add_child(effects)
	projectiles = Projectiles.new()
	projectiles.game = self
	add_child(projectiles)
	enemies = Enemies.new()
	enemies.game = self
	add_child(enemies)
	player = Player.new()
	player.game = self
	player.world = world
	add_child(player)
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	menus = Menus.new()
	menus.game = self
	add_child(menus)
	menus.show_loading(0.0)
	# Let the loading screen draw before the world is generated.
	await get_tree().process_frame
	await get_tree().process_frame
	_start_world()


func _start_world() -> void:
	var save := _read_save()
	_has_save = not save.is_empty()
	_new_game = not _has_save
	if _has_save:
		_load_progress(save)
	world.generate(int(save["seed"]) if _has_save else randi(), house_tier)
	if _has_save:
		world.apply_edits_data(save.get("edits", {}))
	else:
		equipped["pickaxe"] = Items.make("pickaxe", 0, 0, _rng)
		supplies["dynamite"] = 2
	_furnish()
	_setup_vaults(save.get("vaults", []) if _has_save else [])
	player.teleport(world.spawn_point())
	if _has_save:
		var p: Array = save.get("player", [])
		if p.size() == 5:
			player.teleport(Vector3(p[0], p[1], p[2]))
			player.set_look(p[3], p[4])
		player.health = clampf(float(save.get("health", 100.0)), 1.0, player.max_health())
		player.select(clampi(int(save.get("slot", 0)), 0, Player.SLOTS.size() - 1))
	player.stamina = player.max_stamina()
	player.refresh_view()
	world.queue_all_chunks(player.position)
	world.loading = true
	hud.refresh()
	state = "loading"


func _process(delta: float) -> void:
	if state == "starting":
		return
	_time += delta
	world.material.set_shader_parameter("lamp_pos", player.camera.global_position)
	world.update_lights(_time, delta, player.camera.global_position)
	world.focus = player.position
	if state == "loading":
		var progress: float = world.build_progress()
		menus.show_loading(progress)
		if progress >= 1.0:
			world.loading = false
			show_title()
	elif state == "playing":
		var d := minf(delta, 0.05)
		player.update(d)
		enemies.update(d)
		projectiles.update(d)
		rested = maxf(0.0, rested - d)
		_update_detector(d)
		_autosave += d
		if _autosave >= AUTOSAVE_SECONDS:
			_autosave = 0.0
			save_game()
	_update_atmosphere(delta)
	hud.update_status(delta)


func _unhandled_input(event: InputEvent) -> void:
	match state:
		"playing":
			if event.is_action_pressed("ui_cancel"):
				if not player.placing.is_empty():
					stop_placing()
				else:
					pause()
			elif event.is_action_pressed("detector"):
				detector_on = not detector_on
				_beep_timer = 0.0
			elif event.is_action_pressed("journal"):
				open_menu("journal")
			elif event.is_action_pressed("inventory"):
				open_menu("inventory")
			elif event.is_action_pressed("interact"):
				interact()
			elif event.is_action_pressed("pickup"):
				move_furniture()
			elif event.is_action_pressed("cycle"):
				cycle()
			else:
				var mb := event as InputEventMouseButton
				if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
					select_slot(player.slot - 1)
				elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
					select_slot(player.slot + 1)
				for i in Player.SLOTS.size():
					if event.is_action_pressed("slot_%d" % (i + 1)):
						select_slot(i)
		"menu":
			if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact") \
					or (event.is_action_pressed("inventory") and menus.current == "inventory") \
					or (event.is_action_pressed("journal") and menus.current == "journal"):
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
	menus.show_title(_has_save)


func start_playing() -> void:
	resume()
	if _new_game:
		_new_game = false
		toast("Take the stairs down, switch on your detector and start digging.")


func resume() -> void:
	state = "playing"
	menus.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set_active(true)
	hud.refresh()


func pause() -> void:
	state = "paused"
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_pause()
	save_game()


# Opens one of the menus: shop, inventory, journal, anvil, map, or a chest (with `data`).
func open_menu(menu: String, data = null) -> void:
	state = "menu"
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.open(menu, data)


func return_home() -> void:
	player.teleport(world.spawn_point())
	player.set_look(0.0, 0.0)
	resume()


func ask_new_world() -> void:
	state = "confirm"
	menus.show_new_world_confirm()


func cancel_new_world() -> void:
	if menus.confirm_from == "paused":
		pause()
	else:
		show_title()


# A fresh patch of ground with new treasure and new hidden rooms. Everything you own carries over.
func new_world() -> void:
	var data := _save_data()
	data["seed"] = randi()
	data["edits"] = {}
	data["vaults"] = []
	data["tracked"] = -1
	data.erase("player")
	_write_save(data)
	state = "starting"
	get_tree().reload_current_scene()


func save_and_quit() -> void:
	save_game()
	get_tree().quit()


# --- Small helpers ------------------------------------------------------------------

func toast(text: String, color := Color(0.93, 0.91, 0.86)) -> void:
	hud.toast(text, color)


func shake(amount: float, at: Vector3) -> void:
	player.shake(amount * clampf(1.3 - player.position.distance_to(at) / 14.0, 0.0, 1.0))


func count(b: int) -> int:
	return materials.get(b, 0)


func selected_material() -> int:
	return Blocks.MATERIALS[material_index]


func selected_explosive() -> String:
	return Catalog.EXPLOSIVE_ORDER[explosive_index]


func found_count() -> int:
	var n := 0
	for t: int in found:
		n += int(found[t])
	return n


func select_slot(i: int) -> void:
	player.select(i)
	hud.refresh()


# R: the next material to place, the next kind of explosive, or a turn of the furniture you're placing.
func cycle() -> void:
	if not player.placing.is_empty():
		player.turn_placing()
		return
	match Player.SLOTS[player.slot]:
		"bomb":
			explosive_index = (explosive_index + 1) % Catalog.EXPLOSIVE_ORDER.size()
			player.refresh_explosive()
		_:
			for step in range(1, Blocks.MATERIALS.size() + 1):
				var i := (material_index + step) % Blocks.MATERIALS.size()
				if count(Blocks.MATERIALS[i]) > 0 or step == Blocks.MATERIALS.size():
					material_index = i
					break
	hud.refresh()


# Bonuses from every piece of equipped gear: vitality, regen, swift and sense.
func global_affix(id: String) -> float:
	var total := 0.0
	for kind: String in equipped:
		total += Items.affix(equipped[kind], id)
	return total


func at_home() -> bool:
	return House.contains(World.cell_of(player.position + Vector3(0.0, 0.1, 0.0)), house_tier)


func furniture_record(id: int) -> Dictionary:
	for rec: Dictionary in furniture:
		if int(rec["id"]) == id:
			return rec
	return {}


func furniture_at(c: Vector3i) -> Dictionary:
	var id: int = world.furniture.get(World.index(c.x, c.y, c.z), -1)
	return furniture_record(id) if id >= 0 else {}


func level_half() -> int:
	return 6 + 2 * int(workshop["size"])


# --- What's under the crosshair, and E ------------------------------------------------------

func show_target() -> void:
	var e = player.target_enemy
	if e != null:
		hud.set_target("%s  ·  %d / %d" % [e.def["name"], ceili(e.health), ceili(e.max_health)], Color(1.0, 0.55, 0.45))
		return
	var t: Dictionary = player.target
	if t.is_empty():
		hud.set_target("")
		return
	var c: Vector3i = t["cell"]
	var b: int = t["block"]
	var rec := furniture_at(c)
	if House.is_workbench(c):
		hud.set_target("Workbench  ·  E to buy things", Hud.GOLD)
	elif not rec.is_empty():
		var def: Dictionary = Catalog.FURNITURE[rec["type"]]
		var verb: String = def["verb"]
		hud.set_target("%s%s  ·  G to move it" % [def["name"], "  ·  E: " + verb if verb != "" else "  ·  hit it!"], Hud.GOLD)
	elif Blocks.is_loot_chest(b):
		var v: int = world.vault_containing(World.center_of(c))
		var empty := false
		if v >= 0:
			var k := Vaults.chest_at(world.vaults[v], c)
			var contents = vault_state[v]["chests"].get(str(k))
			empty = contents != null and (contents as Array).is_empty()
		hud.set_target("An empty chest" if empty else "An old chest  ·  E to open it", Hud.GOLD)
	elif b == Blocks.RELIC:
		hud.set_target("Something glints in the soil!", Hud.GOLD)
	elif b == Blocks.CHEST or b == Blocks.CHEST_TRIM:
		hud.set_target("A buried chest!", Hud.GOLD)
	elif Blocks.TIER[b] > Items.hardness(equipped["pickaxe"]):
		hud.set_target("%s  ·  needs %s pickaxe" % [Blocks.NAMES[b], _article(Items.TIER_NAMES["pickaxe"][Blocks.TIER[b]])], Color(1.0, 0.55, 0.45))
	else:
		hud.set_target(Blocks.NAMES[b])


static func _article(word: String) -> String:
	return ("an " if "AEIOU".contains(word[0]) else "a ") + word


func interact() -> void:
	var t: Dictionary = player.target
	if t.is_empty():
		return
	var c: Vector3i = t["cell"]
	var rec := furniture_at(c)
	if House.is_workbench(c):
		open_menu("shop")
	elif not rec.is_empty():
		match rec["type"]:
			"bed":
				sleep()
			"chest", "wardrobe":
				open_menu("chest", {"title": Catalog.FURNITURE[rec["type"]]["name"], "items": storage[str(rec["id"])], "slots": Catalog.FURNITURE[rec["type"]]["slots"], "loot": false})
			"anvil":
				open_menu("anvil")
			"map":
				open_menu("map")
	elif Blocks.is_loot_chest(t["block"]):
		var v: int = world.vault_containing(World.center_of(c))
		if v >= 0:
			var k := Vaults.chest_at(world.vaults[v], c)
			if k >= 0:
				_open_loot_chest(v, k)


func sleep() -> void:
	player.health = player.max_health()
	rested = RESTED_SECONDS
	player.stamina = player.max_stamina()
	hud.fade(1.4)
	sfx.play("sleep")
	toast("You wake up well rested: +25% stamina for 10 minutes.", Hud.GOLD)
	save_game()


# --- Digging, levelling and placing -----------------------------------------------------------

# Seconds per swing at block b: faster with a better grip, a faster pickaxe, and a pickaxe
# stronger than the rock needs.
func swing_time(b: int) -> float:
	var item: Dictionary = equipped["pickaxe"]
	var base: float = Blocks.DIG_TIME[b] if Blocks.DIG_TIME[b] > 0.0 else 0.45
	var spare := clampi(Items.hardness(item) - maxi(Blocks.TIER[b], 0), 0, 3)
	return base * pow(0.85, spare) / (float(Catalog.GRIPS[workshop["grip"]]["speed"]) * Items.dig_speed(item))


func on_swing_hit(target: Dictionary) -> void:
	var cell: Vector3i = target["cell"]
	var b: int = target["block"]
	var tier: int = Blocks.TIER[b]
	var item: Dictionary = equipped["pickaxe"]
	var hardness := Items.hardness(item)
	var point := World.center_of(cell) + Vector3(target["normal"]) * World.VOXEL * 0.5
	var rec := furniture_at(cell)
	if not rec.is_empty() and rec["type"] == "dummy":
		_dummy_hit(point, Items.damage(item))
		player.impact(0.6, false)
		return
	if tier < 0:
		sfx.play("clink", randf_range(0.9, 1.1), -4.0)
		effects.sparks(point, Vector3(target["normal"]))
		player.impact(1.0, true)
		if b == Blocks.BEDROCK:
			toast("Bedrock. Nothing digs through this.")
		elif b == Blocks.BRICK:
			toast("These bricks hold the stairs up. Better leave them be.")
		elif Blocks.is_loot_chest(b):
			toast("An old chest. Press E to open it.")
		else:
			toast("Better not dig up your own house.")
		return
	if tier > hardness:
		sfx.play("clink", randf_range(0.9, 1.1), -4.0)
		effects.sparks(point, Vector3(target["normal"]))
		player.impact(1.0, true)
		toast("Too hard! %s needs %s pickaxe. Buy one at your workbench." % [Blocks.NAMES[b], _article(Items.TIER_NAMES["pickaxe"][tier])], Color(1.0, 0.65, 0.5))
		return
	var radius: float = float(Catalog.SIZES[workshop["size"]]["radius"]) * Items.dig_size(item)
	var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var result: Dictionary = world.carve(center, radius, hardness)
	if Items.legend(item) == "tunneler":
		var dir: Vector3 = player.forward()
		for k in range(1, 7):
			_merge(result, world.carve(center + dir * (k * 0.5 / World.VOXEL), radius * 0.85, hardness))
	sfx.play("dig", randf_range(0.8, 1.15), -3.0)
	player.impact(0.7 if Blocks.TIER[b] > 0 else 0.5, false)
	if int(result["removed"]) > 0:
		sfx.play("break", randf_range(0.85, 1.1), -2.0)
		effects.debris(point, Vector3(target["normal"]), Blocks.COLORS[b], 16)
		effects.dust(point)
	_take_result(result, center, radius, item)


func _merge(into: Dictionary, more: Dictionary) -> void:
	into["removed"] = int(into["removed"]) + int(more["removed"])
	into["vault"] = into["vault"] or more["vault"]
	for d: int in more["drops"]:
		into["drops"][d] = int(into["drops"].get(d, 0)) + int(more["drops"][d])
	for t: int in more["treasures"]:
		if not into["treasures"].has(t):
			into["treasures"].append(t)


# Whatever came loose goes in your pack, any treasure is found, and a hidden room you broke
# into wakes up.
func _take_result(result: Dictionary, center: Vector3, radius: float, item: Dictionary, share := 1.0) -> void:
	var double := Items.affix(item, "double")
	var drops: Dictionary = result["drops"]
	for d: int in drops:
		var n := roundi(int(drops[d]) * share)
		if double > 0.0 and _rng.randf() * 100.0 < double:
			n *= 2
		materials[d] = count(d) + n
	for t: int in result["treasures"]:
		_found_treasure(int(world.treasure_list[t]["type"]), world.treasure_list[t]["center"], item)
	if result.get("vault", false):
		for v in world.vaults_near(center, radius):
			if not vault_state[v]["opened"]:
				open_vault(v)
	hud.refresh()


func on_level(target: Dictionary) -> void:
	var item: Dictionary = equipped["pickaxe"]
	var mat := selected_material()
	var half := level_half()
	var result: Dictionary = world.flatten(target["cell"], target["normal"], half, LEVEL_CUT, LEVEL_FILL, Items.hardness(item), mat, count(mat), player.body.lo(), player.body.hi())
	materials[mat] = count(mat) - int(result["placed"])
	var point := World.center_of(target["cell"]) + Vector3(target["normal"]) * World.VOXEL * 0.5
	if int(result["removed"]) + int(result["placed"]) == 0:
		sfx.play("clink", 1.2, -8.0)
		toast("It's already flat here." if count(mat) > 0 else "It's flat as far as it goes; holes need %s to fill them. R picks another material." % String(Blocks.NAMES[mat]).to_lower())
		return
	sfx.play("level", randf_range(0.9, 1.1))
	effects.dust(point)
	effects.debris(point, Vector3(target["normal"]), Blocks.COLORS[target["block"]], 10)
	if count(mat) <= 0:
		toast("Out of %s. Some holes may still be open: R picks another material." % String(Blocks.NAMES[mat]).to_lower(), Color(1.0, 0.75, 0.5))
	_take_result(result, Vector3(target["cell"]), float(half), item)


func on_blocks_placed(cells: Array[Vector3i], b: int) -> void:
	var n := mini(cells.size(), count(b))
	for k in n:
		world.set_block(cells[k], b)
	materials[b] = count(b) - n
	sfx.play("place", randf_range(0.9, 1.1))
	hud.refresh()


func _found_treasure(t: int, where: Vector3, item := {}) -> void:
	found[t] = int(found.get(t, 0)) + 1
	var info: Dictionary = Treasures.LIST[t]
	var value := roundi(int(info["value"]) * (1.0 + Items.affix(item, "prospector") / 100.0))
	coins += value
	sfx.play("treasure")
	effects.burst(where, Hud.GOLD, 24, 3.0, 0.05)
	hud.show_find(t, value)
	House.show_trophies(world, decor, found, house_tier)
	if world.remaining_treasures() == 0:
		toast("Every treasure here has been found! Start a new dig site from the pause menu.", Hud.GOLD)
	save_game()


func _update_detector(delta: float) -> void:
	if not detector_on:
		hud.set_detector(false, 0.0, false)
		return
	var distance: float = world.nearest_treasure_distance(player.camera.global_position)
	var strength := clampf(1.0 - distance / (DETECTOR_RANGE + global_affix("sense")), 0.0, 1.0)
	var beeped := false
	if strength > 0.0:
		_beep_timer -= delta
		if _beep_timer <= 0.0:
			_beep_timer = lerpf(1.1, 0.08, pow(strength, 1.3))
			sfx.play("beep", 0.8 + strength * 0.9, -8.0 + strength * 6.0)
			player.flash_led(strength)
			beeped = true
	hud.set_detector(true, strength, beeped)


# --- Explosions -----------------------------------------------------------------------------

func explode_bomb(kind: String, pos: Vector3) -> void:
	var def: Dictionary = Catalog.EXPLOSIVES[kind]
	explode(pos, float(def["radius"]), int(def["tier"]), float(def["damage"]), {}, 0.6)


# Blows a ball of ground apart, hurting everything nearby (you included, by `self_harm`).
func explode(pos: Vector3, radius: float, tier: int, damage: float, item: Dictionary, self_harm: float) -> void:
	var center := pos / World.VOXEL
	var result: Dictionary = world.carve(center, radius / World.VOXEL, tier)
	var color: Color = Blocks.COLORS[Blocks.DIRT]
	var most := 0
	for d: int in result["drops"]:
		if int(result["drops"][d]) > most:
			most = int(result["drops"][d])
			color = Blocks.COLORS[d]
	_take_result(result, center, radius / World.VOXEL, item, 0.5)
	var reach := radius * 1.8
	for e in enemies.near(pos, reach):
		var falloff := clampf(1.0 - e.body.position.distance_to(pos) / reach, 0.3, 1.0)
		enemies.hurt(e, damage * falloff, pos, {"knockback": 9.0 * falloff, "item": item})
	var me: Vector3 = player.body.position + Vector3(0.0, 0.9, 0.0)
	var dist := me.distance_to(pos)
	if dist < reach and world.line_of_sight(pos, me):
		player.take_damage(damage * clampf(1.0 - dist / reach, 0.2, 1.0) * self_harm, pos, 9.0 * (1.0 - dist / reach))
	effects.explosion(pos, radius, color)
	world.flash(pos, Color(1.0, 0.7, 0.4) * 3.0, radius * 6.0, 0.35)
	sfx.play_at("boom", pos, randf_range(0.85, 1.05) * (1.2 if radius < 1.0 else 1.0), 4.0)
	player.shake(clampf(1.3 - dist / (radius * 7.0), 0.0, 1.0))


# --- Fighting -------------------------------------------------------------------------------

# One blow (or arrow) from a piece of gear, with its crits, fire, knockback, stun and life steal.
func melee_hit(e, item: Dictionary, damage: float, opts: Dictionary) -> void:
	var crit := _rng.randf() * 100.0 < Items.affix(item, "crit")
	if crit:
		damage *= 2.0
	var hit := {
		"knockback": float(opts.get("knockback", 3.0)) * (1.0 + Items.affix(item, "knockback") / 100.0),
		"stun": float(opts.get("stun", 0.0)) * (1.0 + Items.affix(item, "stun") / 100.0),
		"burn": _rng.randf() * 100.0 < Items.affix(item, "burn"),
		"crit": crit,
		"item": item,
	}
	if Items.legend(item) == "thunder":
		damage *= 2.0
		var at: Vector3 = e.body.position
		effects.lightning(at)
		world.flash(at + Vector3(0.0, 1.5, 0.0), Color(0.7, 0.85, 1.0) * 3.0, 9.0, 0.25)
		sfx.play_at("zap", at, randf_range(0.9, 1.1), 2.0)
		for other in enemies.near(at, 3.0):
			if other != e:
				enemies.hurt(other, damage * 0.25, at, {"knockback": 3.0, "stun": 0.4, "item": item})
	enemies.hurt(e, damage, player.body.position, hit)
	var leech := Items.affix(item, "leech")
	if leech > 0.0:
		player.heal(damage * leech / 100.0)


# A swing that hit the cubes instead of a guard.
func melee_hit_block(target: Dictionary, item: Dictionary, damage: float) -> void:
	var cell: Vector3i = target["cell"]
	var point := World.center_of(cell) + Vector3(target["normal"]) * World.VOXEL * 0.5
	var rec := furniture_at(cell)
	if not rec.is_empty() and rec["type"] == "dummy":
		var crit := _rng.randf() * 100.0 < Items.affix(item, "crit")
		_dummy_hit(point, damage * (2.0 if crit else 1.0), crit)
		return
	sfx.play("clink", randf_range(0.7, 0.9), -8.0)
	effects.sparks(point, Vector3(target["normal"]))


func _dummy_hit(point: Vector3, damage: float, crit := false) -> void:
	effects.number(point + Vector3(0.0, 0.3, 0.0), ("%d!" if crit else "%d") % roundi(damage), Color(1.0, 0.85, 0.3) if crit else Color.WHITE, crit)
	effects.burst(point, Color(0.85, 0.72, 0.38), 8, 2.0, 0.035)
	sfx.play("hit_soft", randf_range(0.9, 1.1), -3.0)


func tempest(item: Dictionary, damage: float) -> void:
	var at: Vector3 = player.body.position
	effects.whirl(at, 3.5)
	sfx.play("swing", 0.6, 2.0)
	for e in enemies.near(at + Vector3(0.0, 0.9, 0.0), 3.5):
		melee_hit(e, item, damage * 0.8, {"knockback": 6.0})


func earthshake(item: Dictionary, at: Vector3, damage: float) -> void:
	effects.shockwave(at, 4.0)
	shake(0.35, at)
	sfx.play_at("slam", at, 0.9, 0.0)
	for e in enemies.near(at, 4.0):
		enemies.hurt(e, damage * 0.5, at, {"knockback": 5.0, "stun": 1.0, "item": item})
	var result: Dictionary = world.carve(at / World.VOXEL, 1.0 / World.VOXEL, 1)
	_take_result(result, at / World.VOXEL, 8.0, item)


func arrow_hit_enemy(p: Dictionary, e, at: Vector3) -> void:
	if p.get("blast", false):
		arrow_blast(p, at)
		return
	melee_hit(e, p.get("item", {}), float(p["damage"]), {"knockback": 2.5})
	sfx.play_at("thunk", at, randf_range(1.1, 1.3), -4.0)


func arrow_blast(p: Dictionary, at: Vector3) -> void:
	explode(at, 0.9, 1, float(p["damage"]), p.get("item", {}), 0.3)


func blade_hit_enemy(p: Dictionary, e) -> void:
	melee_hit(e, p.get("item", {}), float(p["damage"]), {"knockback": 2.0})


# A skeleton's arrow reaches you. Returns whether it's used up (a Mirror Ward sends it back).
func enemy_arrow_hits_player(p: Dictionary) -> bool:
	var vel: Vector3 = p["vel"]
	var from: Vector3 = p["pos"] - vel.normalized() * 3.0
	var shield: Dictionary = equipped["shield"]
	var facing := Vector3(-sin(player.yaw), 0.0, -cos(player.yaw))
	var to: Vector3 = from - player.body.position
	to.y = 0.0
	if player.blocking and Items.legend(shield) == "mirror" and to.length() > 0.01 and facing.dot(to.normalized()) > 0.34:
		var shooter = p.get("shooter")
		var aim: Vector3 = from
		if shooter != null and not shooter.dead:
			aim = shooter.body.position + Vector3(0.0, 1.2, 0.0)
		p["friendly"] = true
		p["vel"] = (aim - p["pos"]).normalized() * 32.0
		p["damage"] = float(p["damage"]) * 1.5
		p["item"] = {}
		p["hits"] = []
		sfx.play("block", 1.3)
		return false
	player.take_damage(float(p["damage"]), from, 2.0, p.get("shooter"))
	return true


func pick_up_arrow() -> void:
	supplies["arrows"] = int(supplies["arrows"]) + 1
	sfx.play("pickup", randf_range(1.0, 1.2), -14.0)
	hud.refresh()


func use_arrow(item: Dictionary) -> void:
	if _rng.randf() * 100.0 >= Items.affix(item, "thrifty"):
		supplies["arrows"] = maxi(0, int(supplies["arrows"]) - 1)
	hud.refresh()


func on_enemy_killed(e) -> void:
	var gained := roundi(e.coins * (1.0 + Items.affix(e.last_item, "bounty") / 100.0))
	coins += gained
	var top: Vector3 = e.body.position + Vector3(0.0, float(e.def["height"]) + 0.6, 0.0)
	effects.number(top, "+%d coins" % gained, Hud.GOLD, true)
	sfx.play("coin")
	vault_state[e.vault]["dead"].append(e.spawn)
	if e.type == "archer":
		var arrows := _rng.randi_range(2, 4)
		supplies["arrows"] = int(supplies["arrows"]) + arrows
	if e.def.get("boss", false):
		toast("The Warden falls! His treasure is yours.", Hud.GOLD)
		sfx.play("treasure", 0.8)
	elif enemies.alive_in_vault(e.vault) == 0:
		toast("This hidden room is clear. Help yourself!", Hud.GOLD)
	hud.refresh()


func on_player_died() -> void:
	state = "dead"
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sfx.play("hurt", 0.6)
	menus.show_dead()


# You come round in bed if you have one, or by the stairs door. The guards heal up too.
func wake_up() -> void:
	player.health = player.max_health()
	player.stamina = player.max_stamina()
	player.exhausted = false
	var spot: Vector3 = world.spawn_point()
	for rec: Dictionary in furniture:
		if rec["type"] == "bed":
			spot = House.front_spot(rec)
			break
	player.teleport(spot)
	enemies.reset()
	projectiles.clear()
	hud.fade(1.0)
	resume()


# --- Hidden rooms ------------------------------------------------------------------------------

func _setup_vaults(saved: Array) -> void:
	vault_state.clear()
	enemies.clear()
	for v in world.vaults.size():
		var st := {"opened": false, "dead": [], "chests": {}}
		if v < saved.size() and saved[v] is Dictionary:
			var s: Dictionary = saved[v]
			st["opened"] = bool(s.get("opened", false))
			for k in s.get("dead", []):
				st["dead"].append(int(k))
			var chests: Dictionary = s.get("chests", {})
			for key in chests:
				var list := []
				for d in chests[key]:
					var item := Items.sanitize(d)
					if not item.is_empty():
						list.append(item)
				st["chests"][str(key)] = list
		vault_state.append(st)
		if st["opened"]:
			world.lit_vaults[v] = true
		for key: String in st["chests"]:
			if (st["chests"][key] as Array).is_empty() and int(key) < world.vaults[v]["chests"].size():
				Vaults.mark_chest_empty(world, world.vaults[v]["chests"][int(key)])
		enemies.spawn_vault(world.vaults[v], st["dead"], st["opened"])
	_update_lights()


func open_vault(v: int) -> void:
	vault_state[v]["opened"] = true
	world.lit_vaults[v] = true
	enemies.wake_vault(v)
	sfx.play("vault")
	var guards: int = enemies.alive_in_vault(v)
	toast("You broke into a hidden room!" + (" Something stirs inside..." if guards > 0 else ""), Color(1.0, 0.7, 0.45))
	if tracked == v:
		tracked = -1


func _open_loot_chest(v: int, k: int) -> void:
	var st: Dictionary = vault_state[v]
	var key := str(k)
	var vault: Dictionary = world.vaults[v]
	if not st["chests"].has(key):
		var rarity: int = vault["chests"][k]["rarity"]
		var depth: float = vault["depth"]
		var items := [Items.loot(depth, rarity, _rng)]
		if _rng.randf() < 0.35:
			items.append(Items.loot(depth, maxi(1, rarity - 1), _rng))
		st["chests"][key] = items
		var bonus := roundi(rarity * 30 * (1.0 + depth / 20.0) * _rng.randf_range(0.8, 1.2))
		var arrows := _rng.randi_range(4, 12)
		coins += bonus
		supplies["arrows"] = int(supplies["arrows"]) + arrows
		sfx.play("chest")
		toast("Inside: %d coins and %d arrows, and..." % [bonus, arrows], Hud.GOLD)
	open_menu("chest", {"title": "%s chest" % Items.RARITY_NAMES[vault["chests"][k]["rarity"]], "items": st["chests"][key], "slots": 0, "loot": true, "vault": v, "chest": k})


func chest_closed(data: Dictionary) -> void:
	if data.get("loot", false) and (data["items"] as Array).is_empty():
		Vaults.mark_chest_empty(world, world.vaults[data["vault"]]["chests"][data["chest"]])


# --- Your house ---------------------------------------------------------------------------------

# Decorations, trophies and furniture on top of the house the world was generated with.
func _furnish() -> void:
	for id: String in decor:
		House.apply_decor(world, id, house_tier)
	House.show_trophies(world, decor, found, house_tier)
	for rec: Dictionary in furniture:
		House.build_furniture(world, rec)
	_update_lights()


func _update_lights() -> void:
	var list: Array = House.lights(decor, house_tier)
	for v: Dictionary in world.vaults:
		list.append_array(v["lights"])
	world.set_lights(list)


func place_furniture(type: String, x: int, z: int, rot: int) -> void:
	var rec := {"id": next_furniture_id, "type": type, "x": x, "z": z, "rot": rot}
	next_furniture_id += 1
	furniture.append(rec)
	unplaced.erase(type)
	House.build_furniture(world, rec)
	if Catalog.FURNITURE[type].has("slots"):
		storage[str(rec["id"])] = []
	player.cancel_placing()
	sfx.play("place", 0.8)
	toast("%s placed." % Catalog.FURNITURE[type]["name"])
	hud.refresh()
	save_game()


func start_placing(type: String) -> void:
	resume()
	player.start_placing(type)


func stop_placing() -> void:
	player.cancel_placing()
	toast("Put away. Place it from your pack (I) whenever you like.")


# G: pick up the furniture you're looking at and carry it somewhere else.
func move_furniture() -> void:
	if player.target.is_empty() or not player.placing.is_empty():
		return
	var rec := furniture_at(player.target["cell"])
	if rec.is_empty():
		return
	var key := str(rec["id"])
	if storage.has(key) and not (storage[key] as Array).is_empty():
		toast("Empty it first: take your gear out before moving it.")
		return
	House.remove_furniture(world, rec)
	furniture.erase(rec)
	storage.erase(key)
	unplaced.append(rec["type"])
	# Anything decorative that was hidden under it comes back.
	for id: String in decor:
		House.apply_decor(world, id, house_tier)
	House.show_trophies(world, decor, found, house_tier)
	for other: Dictionary in furniture:
		House.build_furniture(world, other)
	player.start_placing(rec["type"])
	sfx.play("place", 0.7)


# --- Gear --------------------------------------------------------------------------------------

func bag_full() -> bool:
	return bag.size() >= BAG_SIZE


func equip(i: int) -> void:
	var item: Dictionary = bag[i]
	var kind: String = item["kind"]
	var old: Dictionary = equipped[kind]
	equipped[kind] = item
	bag.remove_at(i)
	if not old.is_empty():
		bag.insert(i, old)
	sfx.play("place", 1.2)
	_gear_changed()


func unequip(kind: String) -> void:
	if kind == "pickaxe":
		toast("You need a pickaxe. Equip another one instead.")
		return
	if bag_full():
		toast("Your pack is full.")
		return
	bag.append(equipped[kind])
	equipped[kind] = {}
	_gear_changed()


func _gear_changed() -> void:
	player.refresh_view()
	player.health = minf(player.health, player.max_health())
	hud.refresh()
	menus.refresh()


# Moves gear between a chest and your pack.
func take_item(container: Array, i: int) -> void:
	if bag_full():
		toast("Your pack is full. Put something away first.")
		return
	bag.append(container[i])
	container.remove_at(i)
	sfx.play("pickup", 1.0, -6.0)
	menus.refresh()


func store_item(container: Array, slots: int, i: int) -> void:
	if container.size() >= slots:
		toast("It's full.")
		return
	container.append(bag[i])
	bag.remove_at(i)
	sfx.play("place", 1.1, -6.0)
	menus.refresh()


func take_all(container: Array) -> void:
	while not container.is_empty() and not bag_full():
		bag.append(container[0])
		container.remove_at(0)
	if not container.is_empty():
		toast("Your pack is full.")
	sfx.play("pickup", 1.0, -6.0)
	menus.refresh()


func salvage(i: int) -> void:
	var item: Dictionary = bag[i]
	var value := Items.salvage_value(item)
	coins += value
	bag.remove_at(i)
	sfx.play("anvil", 0.8, -4.0)
	toast("Broken down for %d coins." % value, Hud.GOLD)
	hud.refresh()
	menus.refresh()


func reforge(item: Dictionary, k: int) -> void:
	var cost := Items.reforge_cost(item)
	if coins < cost:
		return
	coins -= cost
	Items.reforge(item, k, _rng)
	sfx.play("anvil", randf_range(0.95, 1.05))
	_gear_changed()
	save_game()


# --- Buying --------------------------------------------------------------------------------------

func buy_gear(kind: String, tier: int) -> void:
	var cost: int = Catalog.GEAR_PRICES[kind][tier]
	if coins < cost:
		return
	if not equipped[kind].is_empty() and bag_full():
		toast("Your pack is full. Make room first.")
		return
	coins -= cost
	var item := Items.make(kind, tier, 0, _rng)
	if equipped[kind].is_empty():
		equipped[kind] = item
		toast("%s equipped." % Items.base_name(item))
	else:
		bag.append(item)
		toast("%s is in your pack. Equip it from there (I)." % Items.base_name(item))
	_bought()
	_gear_changed()


func buy_supply(id: String) -> void:
	var s := Catalog.supply(id)
	if coins < int(s["cost"]):
		return
	coins -= int(s["cost"])
	supplies[id] = int(supplies[id]) + int(s["amount"])
	_bought()


func buy_workshop(kind: String) -> void:
	var list: Array = Catalog.WORKSHOP[kind]
	var level: int = workshop[kind]
	if level + 1 >= list.size() or coins < int(list[level + 1]["cost"]):
		return
	coins -= int(list[level + 1]["cost"])
	workshop[kind] = level + 1
	_bought()


func buy_house_tier() -> void:
	if house_tier + 1 >= Catalog.HOUSE_TIERS.size():
		return
	var cost: int = Catalog.HOUSE_TIERS[house_tier + 1]["cost"]
	if coins < cost:
		return
	coins -= cost
	house_tier += 1
	world.house_tier = house_tier
	House.build_shell(world, house_tier)
	_furnish()
	toast("Your house is now a %s!" % String(Catalog.HOUSE_TIERS[house_tier]["name"]).to_lower(), Hud.GOLD)
	_bought()


func buy_decor(id: String) -> void:
	var i := Catalog.decor_index(id)
	if i < 0 or decor.has(id) or coins < int(Catalog.DECOR[i]["cost"]):
		return
	coins -= int(Catalog.DECOR[i]["cost"])
	decor.append(id)
	House.apply_decor(world, id, house_tier)
	House.show_trophies(world, decor, found, house_tier)
	_update_lights()
	_bought()


func buy_furniture(type: String) -> void:
	var cost: int = Catalog.FURNITURE[type]["cost"]
	if coins < cost:
		return
	coins -= cost
	unplaced.append(type)
	sfx.play("buy")
	save_game()
	start_placing(type)


func _bought() -> void:
	sfx.play("buy")
	hud.refresh()
	menus.refresh()
	save_game()


# --- Setup and saving ------------------------------------------------------------------------

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
		"inventory": [KEY_I],
		"interact": [KEY_E],
		"cycle": [KEY_R],
		"pickup": [KEY_G],
	}
	for i in Player.SLOTS.size():
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
		"materials": materials,
		"found": found,
		"coins": coins,
		"bag": bag,
		"equipped": equipped,
		"supplies": supplies,
		"workshop": workshop,
		"house": {"tier": house_tier, "decor": decor, "furniture": furniture, "unplaced": unplaced, "next_id": next_furniture_id},
		"storage": storage,
		"vaults": vault_state,
		"player": [p.x, p.y, p.z, player.yaw, player.pitch],
		"health": player.health,
		"rested": rested,
		"detector": detector_on,
		"slot": player.slot,
		"material": material_index,
		"explosive": explosive_index,
		"tracked": tracked,
	}


func _load_progress(save: Dictionary) -> void:
	var saved_materials: Dictionary = save.get("materials", {})
	for k in saved_materials:
		if int(k) > 0 and int(k) < Blocks.DEFS.size():
			materials[int(k)] = int(saved_materials[k])
	var saved_found: Dictionary = save.get("found", {})
	for k in saved_found:
		found[int(k)] = int(saved_found[k])
	coins = int(save.get("coins", 0))
	for d in save.get("bag", []):
		var item := Items.sanitize(d)
		if not item.is_empty() and bag.size() < BAG_SIZE:
			bag.append(item)
	var saved_equipped: Dictionary = save.get("equipped", {})
	for kind: String in equipped:
		var item := Items.sanitize(saved_equipped.get(kind, {}))
		equipped[kind] = item if not item.is_empty() and item["kind"] == kind else {}
	if equipped["pickaxe"].is_empty():
		equipped["pickaxe"] = Items.make("pickaxe", 0, 0, _rng)
	var saved_supplies: Dictionary = save.get("supplies", {})
	for id: String in supplies:
		supplies[id] = maxi(0, int(saved_supplies.get(id, 0)))
	var saved_workshop: Dictionary = save.get("workshop", {})
	for kind: String in workshop:
		workshop[kind] = clampi(int(saved_workshop.get(kind, 0)), 0, Catalog.WORKSHOP[kind].size() - 1)
	var house: Dictionary = save.get("house", {})
	house_tier = clampi(int(house.get("tier", 0)), 0, Catalog.HOUSE_TIERS.size() - 1)
	for id in house.get("decor", []):
		if Catalog.decor_index(str(id)) >= 0 and not decor.has(str(id)):
			decor.append(str(id))
	next_furniture_id = maxi(1, int(house.get("next_id", 1)))
	for r in house.get("furniture", []):
		if r is Dictionary and Catalog.FURNITURE.has(str(r.get("type", ""))):
			var rec := {"id": int(r.get("id", 0)), "type": str(r["type"]), "x": int(r.get("x", 0)), "z": int(r.get("z", 0)), "rot": posmod(int(r.get("rot", 0)), 4)}
			furniture.append(rec)
			next_furniture_id = maxi(next_furniture_id, rec["id"] + 1)
	for t in house.get("unplaced", []):
		if Catalog.FURNITURE.has(str(t)):
			unplaced.append(str(t))
	var saved_storage: Dictionary = save.get("storage", {})
	for rec: Dictionary in furniture:
		if Catalog.FURNITURE[rec["type"]].has("slots"):
			var list := []
			for d in saved_storage.get(str(rec["id"]), []):
				var item := Items.sanitize(d)
				if not item.is_empty():
					list.append(item)
			storage[str(rec["id"])] = list
	rested = maxf(0.0, float(save.get("rested", 0.0)))
	detector_on = bool(save.get("detector", true))
	material_index = clampi(int(save.get("material", 0)), 0, Blocks.MATERIALS.size() - 1)
	explosive_index = clampi(int(save.get("explosive", 0)), 0, Catalog.EXPLOSIVE_ORDER.size() - 1)
	tracked = int(save.get("tracked", -1))


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
