extends Node3D
# Deep Finds: take the stairs down from your house and dig. The ground goes on as far as you
# like in every direction and 10 km down, and every wall hides ore and gems, better the deeper
# you go. Carry what you find home to sell or smelt; break into the hidden rooms all through it
# for gear, treasure and scrolls; and improve your gear at the forge to dig deeper still.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Items := preload("res://scripts/items.gd")
const Goods := preload("res://scripts/goods.gd")
const Catalog := preload("res://scripts/catalog.gd")
const World := preload("res://scripts/world.gd")
const House := preload("res://scripts/house.gd")
const Rooms := preload("res://scripts/rooms.gd")
const Player := preload("res://scripts/player.gd")
const Hud := preload("res://scripts/hud.gd")
const Menus := preload("res://scripts/menus.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Effects := preload("res://scripts/effects.gd")
const Enemies := preload("res://scripts/enemies.gd")
const Projectiles := preload("res://scripts/projectiles.gd")
const Models := preload("res://scripts/models.gd")

const SAVE_PATH := "user://deep_finds_save.json"
const WORLD_PATH := "user://deep_finds_world.dat"
const SAVE_VERSION := 6
const AUTOSAVE_SECONDS := 30.0
const RESTED_SECONDS := 600.0
const LEVEL_CUT := 12
const LEVEL_FILL := 8
const DIG_POWER := 560.0      # density a pickaxe blow takes off the middle of its dent (see World.dent)
const BLAST_ORE := 0.5        # share of the ore an explosion leaves in one piece
const TREASURE_HINT := 3.0    # metres: this close to buried treasure, your pick rings
const HOLLOW_HINT := 2.5      # metres: this close to a sealed hidden room, your blows sound hollow
const WARN := Color(1.0, 0.6, 0.45)
# The bars (or gems) a chest holds at each band of rock, to help improve your gear.
const CHEST_BARS := ["iron_bar", "steel_bar", "gold_bar", "diamond", "mithril_bar", "adamant_bar", "starmetal_bar", "starmetal_bar"]

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
var found := {}           # treasure type -> how many you've ever found
var mined := {}           # good id -> how many pieces you've ever dug out
var learned := {}         # affix id -> the strongest version of it you've learned from a scroll
var coins := 0
var bag: Array = []       # your pack: gear, ore, bars, treasure and scrolls (see Goods)
var equipped := {"pickaxe": {}, "sword": {}, "mace": {}, "shield": {}}
var supplies := {"dynamite": 0, "charge": 0}
var workshop := {"pack": 0}
var house_tier := 0
var decor: Array = []         # decorations you own, in the order you bought them
var furniture: Array = []     # placed furniture: {"id", "type", "x", "z", "rot"}
var unplaced: Array = []      # furniture you've bought or picked up but not put down yet
var storage := {}             # furniture id (as text) -> what's inside
var next_furniture_id := 1
var room_state := {}          # room id -> {"opened", "dead": [guard numbers], "chests": {number: [loot]}, "seen"}
var explosive_index := 0
var rested := 0.0
var tracked := {}             # the hidden room your compass points at: {"id", "name", "center", "top"}
var return_point := []        # where you were when you last went home: [x, y, z, yaw, pitch], or []
var deepest := 0.0            # the deepest you've ever been, in metres
var _rng := RandomNumberGenerator.new()
var _has_save := false
var _new_game := false
var _autosave := 0.0
var _time := 0.0
var _ore_dust := {}           # good id -> cells of it dug towards the next piece
var _notes := {}              # message -> seconds before it may show again
var _arrive := {}             # where to put you once the world around it is ready: {"pos", "look", "then"}
var _traps_cool := {}         # "room/plate" -> seconds before that plate can go off again
var _spikes: Array = []       # spikes on their way up: {"room", "plate", "time", "node", "hit"}
var _gas: Array = []          # clouds of poison from trapped chests: {"pos", "time", "damage", "tick"}
var _spike_mesh: Mesh
var _in_room := ""            # the hidden room you're standing in
var _fell := false            # whether you're down on a trial's floor
var _welcome := ""            # said when you start playing: what became of a 0.5 save


func _ready() -> void:
	_rng.randomize()
	_setup_input()
	_setup_environment()
	sfx = Sfx.new()
	add_child(sfx)
	world = World.new()
	world.on_room_loaded = Callable(self, "_room_loaded")
	world.on_room_unloaded = Callable(self, "_room_unloaded")
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
	# Let the loading screen draw before the world is made.
	await get_tree().process_frame
	await get_tree().process_frame
	_start_world()


func _start_world() -> void:
	var save := _read_save()
	_has_save = not save.is_empty()
	_new_game = not _has_save
	if _has_save:
		_load_progress(save)
		if int(save.get("refund", -1)) >= 0:
			_welcome = "A whole new world to dig, as deep as 10 km! Your gear moved to the new materials%s." % \
				(", and your bows, arrows and pickaxe upgrades became %s coins" % Hud.thousands(int(save["refund"])) if int(save["refund"]) > 0 else "")
	var found_ids := {}
	for id in save.get("found_ids", []):
		found_ids[str(id)] = true
	world.begin(int(save["seed"]) if _has_save else randi(), house_tier, found_ids)
	if _has_save:
		world.load_edits(WORLD_PATH)
	else:
		equipped["pickaxe"] = Items.make("pickaxe", 1, 0, _rng)
		equipped["sword"] = Items.make("sword", 0, 0, _rng)
		supplies["dynamite"] = 2
	world.pinning = true
	House.build_base(world, house_tier)
	world.pinning = false
	world.restore_house_edits()
	_furnish()
	var at: Vector3 = world.spawn_point()
	var look := Vector2.ZERO
	if _has_save:
		var p: Array = save.get("player", [])
		if p.size() == 5:
			at = Vector3(p[0], p[1], p[2])
			look = Vector2(p[3], p[4])
		player.health = clampf(float(save.get("health", 100.0)), 1.0, player.max_health())
		player.select(clampi(int(save.get("slot", 0)), 0, Player.SLOTS.size() - 1))
	player.stamina = player.max_stamina()
	player.refresh_view()
	hud.refresh()
	_go(at, look, "title")


# Makes the world around `at` and puts you there once it's ready: then shows the title, or plays.
func _go(at: Vector3, look: Vector2, then: String) -> void:
	_arrive = {"pos": at, "look": look, "then": then}
	player.set_active(false)
	world.look_around(at)
	world.loading = true
	state = "loading"
	menus.show_loading(0.0)


func _arrived() -> void:
	world.loading = false
	player.teleport(_arrive["pos"])
	player.set_look(_arrive["look"].x, _arrive["look"].y)
	var then: String = _arrive["then"]
	_arrive = {}
	if then == "title":
		show_title()
	else:
		hud.fade(0.8)
		resume()


func _process(delta: float) -> void:
	if state == "starting":
		return
	_time += delta
	world.material.set_shader_parameter("lamp_pos", player.camera.global_position)
	world.update_lights(_time, delta, player.camera.global_position)
	if state == "loading":
		menus.show_loading(world.build_progress())
		if world.ready_around():
			_arrived()
	else:
		world.focus = player.position
	if state == "playing":
		var d := minf(delta, 0.05)
		player.update(d)
		enemies.update(d)
		projectiles.update(d)
		_update_traps(d)
		_update_rooms()
		rested = maxf(0.0, rested - d)
		deepest = maxf(deepest, world.depth_at(player.position))
		for key: String in _notes.keys():
			_notes[key] = float(_notes[key]) - d
			if float(_notes[key]) <= 0.0:
				_notes.erase(key)
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


# --- Screens ----------------------------------------------------------------------------------

func show_title() -> void:
	state = "title"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_title(_has_save)


func start_playing() -> void:
	resume()
	if _new_game:
		_new_game = false
		toast("Take the stairs down and dig. Hidden rooms are everywhere down there. When your pack is full, bring it home.")
	elif _welcome != "":
		toast(_welcome, Hud.GOLD)
		_welcome = ""


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


# Opens one of the menus: shop, forge, inventory, journal, anvil, map, or a chest (with `data`).
func open_menu(menu: String, data = null) -> void:
	state = "menu"
	player.set_active(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.open(menu, data)


# Home in an instant. The rope lift by your door takes you back down to where you were.
func return_home() -> void:
	if world.depth_at(player.position) > 3.0:
		return_point = [player.position.x, player.position.y, player.position.z, player.yaw, player.pitch]
	save_game()
	_go(world.spawn_point(), Vector2.ZERO, "play")


func ride_lift() -> void:
	if return_point.size() != 5:
		toast("The rope lift takes you back down to wherever you were when you last went home (from the pause menu).")
		return
	sfx.play("place", 0.6)
	_go(Vector3(return_point[0], return_point[1], return_point[2]), Vector2(return_point[3], return_point[4]), "play")


func return_depth() -> float:
	return world.depth_at(Vector3(return_point[0], return_point[1], return_point[2])) if return_point.size() == 5 else 0.0


func ask_new_world() -> void:
	state = "confirm"
	menus.show_new_world_confirm()


func cancel_new_world() -> void:
	if menus.confirm_from == "paused":
		pause()
	else:
		show_title()


# A fresh world with new ground, ore, treasure and hidden rooms. Everything you own carries over.
func new_world() -> void:
	var data := _save_data()
	data["seed"] = randi()
	data["rooms"] = {}
	data["found_ids"] = []
	data["tracked"] = {}
	data["return"] = []
	data.erase("player")
	_write_save(data)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(WORLD_PATH))
	state = "starting"
	get_tree().reload_current_scene()


func save_and_quit() -> void:
	save_game()
	get_tree().quit()


# --- Small helpers ------------------------------------------------------------------------------

func toast(text: String, color := Color(0.93, 0.91, 0.86)) -> void:
	hud.toast(text, color)


# A toast that waits `wait` seconds before it shows again, for things that happen over and over.
func note(text: String, color := Color(0.93, 0.91, 0.86), wait := 20.0) -> void:
	if not _notes.has(text):
		_notes[text] = wait
		toast(text, color)


func shake(amount: float, at: Vector3) -> void:
	player.shake(amount * clampf(1.3 - player.position.distance_to(at) / 14.0, 0.0, 1.0))


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


# R: the next kind of explosive, or a turn of the furniture you're placing.
func cycle() -> void:
	if not player.placing.is_empty():
		player.turn_placing()
		return
	if Player.SLOTS[player.slot] == "bomb":
		explosive_index = (explosive_index + 1) % Catalog.EXPLOSIVE_ORDER.size()
		player.refresh_explosive()
		hud.refresh()


# Bonuses from every piece of equipped gear: vitality, regen and swift.
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
	var id: int = world.furniture.get(World.key(c.x, c.y, c.z), -1)
	return furniture_record(id) if id >= 0 else {}


# Radius in cubes of the dent each pickaxe blow leaves, and of the disc it flattens.
func dig_radius() -> float:
	return Items.dig_radius(equipped["pickaxe"])


func _room(id: String) -> Dictionary:
	if not room_state.has(id):
		room_state[id] = {"opened": false, "dead": [], "chests": {}, "seen": false}
	return room_state[id]


# --- What's under the crosshair, and E ------------------------------------------------------------

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
		hud.set_target("Workbench  ·  E to buy and sell", Hud.GOLD)
	elif House.is_forge(c):
		hud.set_target("Forge  ·  E to smelt ore and improve your gear", Hud.GOLD)
	elif House.is_lift(c):
		if return_point.size() == 5:
			hud.set_target("Rope lift  ·  E to go back down (%s m)" % Hud.thousands(roundi(return_depth())), Hud.GOLD)
		else:
			hud.set_target("Rope lift  ·  it takes you back to where you were when you last went home", Hud.GOLD)
	elif not rec.is_empty():
		var def: Dictionary = Catalog.FURNITURE[rec["type"]]
		var verb: String = def["verb"]
		hud.set_target("%s%s  ·  G to move it" % [def["name"], "  ·  E: " + verb if verb != "" else "  ·  hit it!"], Hud.GOLD)
	elif Blocks.is_loot_chest(b):
		var id: String = world.room_containing(World.center_of(c))
		var text := "An old chest  ·  E to open it"
		if id != "":
			var k := Rooms.chest_at(world.rooms[id], c)
			var contents = _room(id)["chests"].get(str(k))
			if contents != null and (contents as Array).is_empty():
				text = "An empty chest"
			elif k >= 0 and world.rooms[id]["chests"][k].get("sealed", false) and guards_left(id) > 0:
				text = "A sealed chest  ·  bring down the guards to open it"
		hud.set_target(text, Hud.GOLD)
	elif b == Blocks.RELIC:
		hud.set_target("Something glints in the soil  ·  E to dig it out", Hud.GOLD)
	elif b == Blocks.CHEST or b == Blocks.CHEST_TRIM:
		hud.set_target("A buried chest  ·  E to dig it up", Hud.GOLD)
	elif Blocks.is_trial(b):
		hud.set_target("Trial stone  ·  nothing digs through it. The way in is somewhere along it.", Color(0.6, 0.85, 1.0))
	elif Blocks.TIER[b] > Items.hardness(equipped["pickaxe"]):
		hud.set_target("%s  ·  needs %s pickaxe" % [Blocks.NAMES[b], _article(Items.MATERIALS[Blocks.TIER[b]].to_lower())], Color(1.0, 0.55, 0.45))
	elif Blocks.is_ore(b):
		hud.set_target(Blocks.NAMES[b], Goods.LIST[Goods.BLOCK_GOOD[b]]["color"])
	else:
		hud.set_target(Blocks.NAMES[b])


static func _article(word: String) -> String:
	return ("an " if "aeiouAEIOU".contains(word[0]) else "a ") + word


func interact() -> void:
	var t: Dictionary = player.target
	if t.is_empty():
		return
	var c: Vector3i = t["cell"]
	var rec := furniture_at(c)
	if House.is_workbench(c):
		open_menu("shop")
	elif House.is_forge(c):
		open_menu("forge")
	elif House.is_lift(c):
		ride_lift()
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
		var id: String = world.room_containing(World.center_of(c))
		if id != "":
			var k := Rooms.chest_at(world.rooms[id], c)
			if k >= 0:
				_open_loot_chest(id, k)
	elif Blocks.is_treasure(t["block"]):
		var here: String = world.treasure_at(c)
		if here != "":
			_dig_out(here)


func sleep() -> void:
	player.health = player.max_health()
	rested = RESTED_SECONDS
	player.stamina = player.max_stamina()
	hud.fade(1.4)
	sfx.play("sleep")
	toast("You wake up well rested: +25% stamina for 10 minutes.", Hud.GOLD)
	save_game()


# --- Digging and flattening ------------------------------------------------------------------------

# Seconds per swing at block b: faster with a better pickaxe, and one stronger than the rock needs.
func swing_time(b: int) -> float:
	var item: Dictionary = equipped["pickaxe"]
	var base: float = Blocks.DIG_TIME[b] if Blocks.DIG_TIME[b] > 0.0 else 0.45
	var spare := clampi(Items.hardness(item) - maxi(Blocks.TIER[b], 0), 0, 3)
	return base * pow(0.85, spare) / Items.dig_speed(item)


# Whether the pickaxe can break this block; if not, says why and makes the blow glance off.
func _can_dig(target: Dictionary) -> bool:
	var b: int = target["block"]
	var tier: int = Blocks.TIER[b]
	var point: Vector3 = target["point"]
	var normal: Vector3 = target["normal"]
	if Blocks.is_treasure(b):
		effects.sparks(point, normal)
		player.impact(0.6, true)
		toast("Careful with that! Press E to dig it out.", Hud.GOLD)
		return false
	if tier < 0:
		effects.sparks(point, normal)
		player.impact(1.0, true)
		if b == Blocks.BEDROCK:
			toast("Bedrock. Nothing digs through this." + (" This is the bottom of the world." if world.depth_at(point) > 9000.0 else ""))
		elif Blocks.is_trial(b):
			note("Trial stone: nothing digs through it. Follow the wall to find the way in.", Color(0.6, 0.85, 1.0), 8.0)
		elif b == Blocks.BRICK:
			toast("These bricks hold the stairs up. Better leave them be.")
		elif Blocks.is_loot_chest(b):
			toast("An old chest. Press E to open it.")
		else:
			toast("Better not dig up your own house.")
		return false
	if tier > Items.hardness(equipped["pickaxe"]):
		effects.sparks(point, normal)
		player.impact(1.0, true)
		toast("Too hard! %s needs %s pickaxe. Improve yours at the forge, or find a better one." % [Blocks.NAMES[b], _article(Items.MATERIALS[tier].to_lower())], Color(1.0, 0.65, 0.5))
		return false
	return true


# The pickaxe lands: it wears a dent in the ground around where you aimed, and any ore it breaks
# out goes into your pack. Treasure it uncovers stays in the ground until you pick it up (E).
func on_swing_hit(target: Dictionary) -> void:
	var cell: Vector3i = target["cell"]
	var b: int = target["block"]
	var item: Dictionary = equipped["pickaxe"]
	var hardness := Items.hardness(item)
	var point: Vector3 = target["point"]
	var normal: Vector3 = target["normal"]
	var rec := furniture_at(cell)
	if not rec.is_empty() and rec["type"] == "dummy":
		_dummy_hit(point, Items.damage(item))
		player.impact(0.6, false)
		return
	hit_sound(b)
	if not _can_dig(target):
		return
	var radius := dig_radius()
	var power := DIG_POWER
	var strong := _rng.randf() * 100.0 < Items.affix(item, "double")
	if strong:
		power *= 2.0
	# The blow lands a little way into the surface, so the dent opens right where you aimed.
	var result: Dictionary = world.dent(point - normal * (radius * 0.2 * World.VOXEL), radius, power, hardness)
	if Items.legend(item) == "tunneler":
		var dir: Vector3 = player.forward()
		for k in range(1, 7):
			var more: Dictionary = world.blast((point + dir * (k * 0.5)) / World.VOXEL, maxf(radius * 1.2, 3.6), hardness)
			result["removed"] = int(result["removed"]) + int(more["removed"])
			result["vault"] = result["vault"] or more["vault"]
			for ore: int in more["ore"]:
				result["ore"][ore] = int(result["ore"].get(ore, 0)) + int(more["ore"][ore])
	player.impact(0.7 if Blocks.TIER[b] > 1 else 0.5, false)
	var color: Color = Blocks.COLORS[b]
	effects.debris(point, normal, color, 8 + mini(int(result["removed"]) / 4, 16))
	if Blocks.is_ore(b):
		effects.burst(point + normal * 0.05, Blocks.FLECKS[b], 6, 2.4, 0.03, normal, 50.0, 12.0, 0.6, Blocks.GLOW[b] > 0.2)
	if int(result["removed"]) > 0:
		sfx.play("break", randf_range(0.85, 1.1), -9.0 if int(result["removed"]) < 20 else -5.0)
		effects.dust(point, color.darkened(0.3))
	if strong:
		effects.sparks(point, normal)
		player.impact(0.5, true)
	_collect_ore(result["ore"], point, 1.0, item)
	_listen(point)
	_check_rooms(result, point / World.VOXEL, radius)


# What a blow sounds like depends on what it lands on: a thud in dirt, a crunch in sand or
# gravel, a crack in stone, a clank off deeprock, a ring off ore and metal, a chime off gems.
func hit_sound(b: int, volume := -3.0) -> void:
	var surface: String = Blocks.SOUND[b]
	if surface == "":
		return
	var pitch := randf_range(0.93, 1.07)
	if Blocks.is_ore(b):
		pitch *= 0.85 + 0.04 * (b - Blocks.COAL)
	sfx.play("pick_" + surface, pitch, volume)


# Ore and gems you break out go into your pack: a piece for every so many cells of it. `share`
# is how much of it survives (explosions shatter some).
func _collect_ore(ore: Dictionary, point: Vector3, share: float, item := {}) -> void:
	if ore.is_empty():
		return
	var luck := 1.0 + Items.affix(item, "lucky") / 100.0
	var rise := 0.0
	var lost := false
	for b: int in ore:
		var id: String = Goods.BLOCK_GOOD[b]
		var per := float(Goods.LIST[id]["cells"])
		var dust := float(_ore_dust.get(id, 0.0)) + int(ore[b]) * share * luck
		var n := floori(dust / per)
		_ore_dust[id] = dust - n * per
		if n <= 0:
			continue
		var added: int = Goods.add(bag, pack_slots(), id, n)
		if added > 0:
			mined[id] = int(mined.get(id, 0)) + added
			effects.number(point + Vector3(0.0, 0.15 + rise, 0.0), "+%d %s" % [added, Goods.LIST[id]["name"]], Goods.LIST[id]["color"])
			rise += 0.16
		lost = lost or added < n
	if rise > 0.0:
		sfx.play("pickup", randf_range(1.0, 1.15), -13.0)
		hud.refresh()
	if lost:
		note("Your pack is full! Head home to sell, smelt or store what you've found.", WARN, 8.0)


# Close to buried treasure, your pick rings: the nearer it is, the clearer. Close to a sealed
# hidden room, your blows sound hollow.
func _listen(point: Vector3) -> void:
	var d: float = world.nearest_treasure_distance(point)
	if d < TREASURE_HINT:
		var k := 1.0 - d / TREASURE_HINT
		sfx.play("ring", 0.9 + 0.3 * k, -18.0 + 12.0 * k)
		note("Your pick rings oddly... something is buried close by.", Hud.GOLD, 30.0)
	var best := INF
	for id: String in world.rooms:
		if not _room(id)["opened"]:
			best = minf(best, Rooms.distance(world.rooms[id], point))
	if best < HOLLOW_HINT:
		var k := 1.0 - best / HOLLOW_HINT
		sfx.play("hollow", 0.9 + 0.2 * k, -14.0 + 10.0 * k)
		note("That sounded hollow... there's a room in the rock nearby.", Color(1.0, 0.75, 0.5), 30.0)


# A hidden room you broke into wakes up.
func _check_rooms(result: Dictionary, center: Vector3, radius: float) -> void:
	if result.get("vault", false):
		for id in world.rooms_near(center, radius):
			if not _room(id)["opened"]:
				open_room(id)


# Right click with the pickaxe: flattens the floor, wall or ceiling you're looking at over a disc
# as wide as the pickaxe's dent, cutting away bumps and filling dips with the ground around them.
func on_flatten(target: Dictionary) -> void:
	var item: Dictionary = equipped["pickaxe"]
	var face: Vector3i = target["face"]
	var axis := 0 if face.x != 0 else (1 if face.y != 0 else 2)
	var b: int = target["block"]
	var cell: Vector3i = target["cell"]
	var point: Vector3 = target["point"]
	if Blocks.is_trial(b) or (b > Blocks.BEDROCK and Blocks.TIER[b] < 0):
		hit_sound(b)
		effects.sparks(point, target["normal"])
		player.impact(0.8, true)
		return
	var fill_block: int = b if Blocks.is_natural(b) and not Blocks.is_ore(b) else world.rock_at(cell)
	var result: Dictionary = world.flatten(point, axis, face[axis], dig_radius(), LEVEL_CUT, LEVEL_FILL, Items.hardness(item), fill_block, player.body.lo(), player.body.hi())
	hit_sound(b, -6.0)
	if not result["changed"]:
		sfx.play("clink", 1.2, -8.0)
		note("It's already flat here.", Color(0.93, 0.91, 0.86), 4.0)
		return
	sfx.play("level", randf_range(0.9, 1.1), -4.0)
	player.impact(0.4, false)
	effects.dust(point)
	effects.debris(point, Vector3(face), Blocks.COLORS[b], 6)
	_collect_ore(result["ore"], point, 1.0, item)
	_check_rooms(result, point / World.VOXEL, dig_radius())


# E on treasure you've uncovered: it comes out of the ground and into your pack.
func _dig_out(id: String) -> void:
	if bag_full():
		toast("Your pack is full. Make room before you dig this out.", WARN)
		return
	var info: Dictionary = world.treasures[id]
	world.collect(id)
	effects.debris(info["center"], Vector3.UP, Blocks.COLORS[Blocks.DIRT], 14)
	_found_treasure(int(info["type"]), Treasures.value_at(int(info["type"]), float(info["depth"])), info["center"], equipped["pickaxe"])


func _found_treasure(t: int, worth: int, where: Vector3, item := {}) -> void:
	found[t] = int(found.get(t, 0)) + 1
	var value := roundi(worth * (1.0 + Items.affix(item, "prospector") / 100.0))
	bag.append({"kind": "treasure", "id": t, "value": value})
	sfx.play("treasure")
	effects.burst(where, Hud.GOLD, 24, 3.0, 0.05)
	hud.show_find(t, value)
	hud.refresh()
	House.show_trophies(world, decor, found, house_tier)
	save_game()


# --- Explosions -----------------------------------------------------------------------------------

func explode_bomb(kind: String, pos: Vector3) -> void:
	var def: Dictionary = Catalog.EXPLOSIVES[kind]
	explode(pos, float(def["radius"]), int(def["tier"]), float(def["damage"]), {}, 0.6)


# Blows a ball of ground apart, hurting everything nearby (you included, by `self_harm`). Some of
# the ore it breaks survives in one piece.
func explode(pos: Vector3, radius: float, tier: int, damage: float, item: Dictionary, self_harm: float) -> void:
	var center := pos / World.VOXEL
	var result: Dictionary = world.blast(center, radius / World.VOXEL, tier)
	var color: Color = Blocks.COLORS[result["block"] if int(result["block"]) != Blocks.AIR else Blocks.DIRT]
	_check_rooms(result, center, radius / World.VOXEL)
	_collect_ore(result["ore"], pos, BLAST_ORE)
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


# --- Fighting ---------------------------------------------------------------------------------------

# One blow from a piece of gear, with its crits, fire, knockback, stun and life steal.
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


# A swing that hit the walls instead of a guard.
func melee_hit_block(target: Dictionary, item: Dictionary, damage: float) -> void:
	var cell: Vector3i = target["cell"]
	var point: Vector3 = target["point"]
	var rec := furniture_at(cell)
	if not rec.is_empty() and rec["type"] == "dummy":
		var crit := _rng.randf() * 100.0 < Items.affix(item, "crit")
		_dummy_hit(point, damage * (2.0 if crit else 1.0), crit)
		return
	hit_sound(int(target["block"]), -8.0)
	effects.sparks(point, target["normal"])


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
	var result: Dictionary = world.blast(at / World.VOXEL, 1.0 / World.VOXEL, 2)
	_check_rooms(result, at / World.VOXEL, 8.0)
	_collect_ore(result["ore"], at, BLAST_ORE)


# An arrow or dart sent back by a Mirror Ward finds its mark.
func arrow_hit_enemy(p: Dictionary, e, at: Vector3) -> void:
	melee_hit(e, p.get("item", {}), float(p["damage"]), {"knockback": 2.5})
	sfx.play_at("thunk", at, randf_range(1.1, 1.3), -4.0)


func blade_hit_enemy(p: Dictionary, e) -> void:
	melee_hit(e, p.get("item", {}), float(p["damage"]), {"knockback": 2.0})


# A skeleton's arrow or a trap's dart reaches you. Returns whether it's used up (a Mirror Ward
# sends it back).
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


func on_enemy_killed(e) -> void:
	var gained := roundi(e.coins * (1.0 + Items.affix(e.last_item, "bounty") / 100.0))
	coins += gained
	var top: Vector3 = e.body.position + Vector3(0.0, float(e.def["height"]) + 0.6, 0.0)
	effects.number(top, "+%d coins" % gained, Hud.GOLD, true)
	sfx.play("coin")
	_room(e.room)["dead"].append(e.spawn)
	if e.def.get("boss", false):
		toast("The Warden falls! His treasure is yours.", Hud.GOLD)
		sfx.play("treasure", 0.8)
	elif guards_left(e.room) == 0:
		toast("Every guard here is down. The chest's seal breaks: help yourself!", Hud.GOLD)
		sfx.play("chest", 0.8)
	hud.refresh()


# How many of a room's guards are still standing.
func guards_left(id: String) -> int:
	var room: Dictionary = world.rooms.get(id, {})
	if room.is_empty():
		return 0
	return maxi(0, (room.get("spawns", []) as Array).size() - (_room(id)["dead"] as Array).size())


func on_player_died() -> void:
	if world.depth_at(player.position) > 3.0:
		return_point = [player.position.x, player.position.y, player.position.z, player.yaw, player.pitch]
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
	enemies.reset()
	projectiles.clear()
	_clear_traps()
	_go(spot, Vector2.ZERO, "play")


# --- Hidden rooms --------------------------------------------------------------------------------

# A room comes into the world around you: its guards take their places (asleep, unless you've
# broken in before), and chests you emptied stay empty.
func _room_loaded(room: Dictionary) -> void:
	var id: String = room["id"]
	var st: Dictionary = room_state.get(id, {})
	if room["type"] == "fight":
		enemies.spawn_room(room, st.get("dead", []), st.get("opened", false))
	if st.get("opened", false):
		world.lit_rooms[id] = true
	var chests: Array = room.get("chests", [])
	for key in st.get("chests", {}):
		var k := int(key)
		if (st["chests"][key] as Array).is_empty() and k < chests.size():
			_mark_chest_empty(chests[k])


func _room_unloaded(room: Dictionary) -> void:
	enemies.despawn_room(room["id"])


func open_room(id: String) -> void:
	var st := _room(id)
	st["opened"] = true
	world.lit_rooms[id] = true
	enemies.wake_room(id)
	sfx.play("vault")
	var room: Dictionary = world.rooms[id]
	match room["type"]:
		"fight":
			toast("You broke into a guard room! Something stirs inside...", Color(1.0, 0.7, 0.45))
		"treasure":
			toast("You broke into a treasure room! Watch your step: these old rooms were built to keep thieves out.", Color(1.0, 0.8, 0.45))
		_:
			toast("You broke into a hidden room!", Color(1.0, 0.7, 0.45))
	if tracked.get("id", "") == id:
		tracked = {}


# Where you are, room-wise: noticing a trial when you step into it, and when you've fallen.
func _update_rooms() -> void:
	var id: String = world.room_containing(player.body.position + Vector3(0.0, 0.2, 0.0))
	if id != _in_room:
		_in_room = id
		_fell = false
		if id != "":
			var st := _room(id)
			var room: Dictionary = world.rooms[id]
			if room["type"] == "trial" and not st["seen"]:
				toast("A trial! Jump from pillar to pillar to the reward on the far ledge.", Color(0.6, 0.85, 1.0))
			if not st["opened"] and room["type"] == "trial":
				st["opened"] = true
			st["seen"] = true
	if _in_room != "":
		var room: Dictionary = world.rooms[_in_room]
		if room["type"] == "trial":
			var floor_y: float = (Vector3(room["lo"]) * World.VOXEL).y
			var down: bool = player.body.on_floor and player.body.position.y < floor_y + 0.3
			if down and not _fell:
				note("Down you go. The stairs in the corner take you back up to the start.", Color(0.6, 0.85, 1.0), 6.0)
			_fell = down


func _open_loot_chest(id: String, k: int) -> void:
	var st := _room(id)
	var key := str(k)
	var room: Dictionary = world.rooms[id]
	var chest: Dictionary = room["chests"][k]
	if chest.get("sealed", false) and guards_left(id) > 0:
		toast("The chest is sealed shut. Bring down every guard in the room to break the seal.", WARN)
		sfx.play("clink", 0.8)
		return
	if not st["chests"].has(key):
		var loot := _roll_loot(room, chest)
		st["chests"][key] = loot[0]
		coins += int(loot[1])
		sfx.play("chest")
		toast("Inside: %s coins, and..." % Hud.thousands(int(loot[1])), Hud.GOLD)
		if chest.get("trapped", false):
			_spring_chest(chest)
	open_menu("chest", {"title": "%s chest" % Items.RARITY_NAMES[chest["rarity"]], "items": st["chests"][key], "slots": 0, "loot": true, "room": id, "chest": k})


# What a chest holds: gear of its rarity, sometimes a second piece, and by the kind of room a
# scroll, a treasure, and bars or gems for the forge. Everything is worth more the deeper it is.
# Returns [items, coins].
func _roll_loot(room: Dictionary, chest: Dictionary) -> Array:
	var depth: float = room["depth"]
	var level: float = room["level"]
	var rarity: int = chest["rarity"]
	var type: String = room["type"]
	var items := [Items.loot(depth, rarity, _rng)]
	if _rng.randf() < 0.35:
		items.append(Items.loot(depth, maxi(1, rarity - 1), _rng))
	var scroll_chance: float = {"trial": 0.6, "treasure": 0.2, "fight": 0.28}[type]
	if _rng.randf() < scroll_chance:
		var id: String = Items.SCROLL_AFFIXES[_rng.randi_range(0, Items.SCROLL_AFFIXES.size() - 1)]
		items.append(Goods.make_scroll(id, Items.scroll_value(id, depth, _rng), roundi(120.0 * pow(1.5, level))))
	var treasure_chance: float = {"trial": 0.35, "treasure": 0.45, "fight": 0.2}[type]
	if _rng.randf() < treasure_chance:
		var t := Treasures.pick(_rng, maxf(depth, 18.0))
		if t >= 0:
			found[t] = int(found.get(t, 0)) + 1
			items.append({"kind": "treasure", "id": t, "value": Treasures.value_at(t, depth)})
			House.show_trophies(world, decor, found, house_tier)
	if _rng.randf() < 0.45:
		items.append(Goods.make(CHEST_BARS[Blocks.band(depth)], _rng.randi_range(2, 5)))
	var bonus := roundi(rarity * 30 * pow(1.5, level) * _rng.randf_range(0.8, 1.2))
	return [items, bonus]


func chest_closed(data: Dictionary) -> void:
	if data.get("loot", false) and (data["items"] as Array).is_empty():
		var room: Dictionary = world.rooms.get(data["room"], {})
		if not room.is_empty():
			_mark_chest_empty(room["chests"][data["chest"]])


# Recolours an emptied chest's trim (and keeps it that way).
func _mark_chest_empty(chest: Dictionary) -> void:
	var lo: Vector3i = chest["lo"]
	var hi: Vector3i = chest["hi"]
	for z in range(lo.z, hi.z + 1):
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				var b: int = world.block(x, y, z)
				if b >= Blocks.LOOT_TRIM and b < Blocks.LOOT_TRIM + 4:
					world.repaint(x, y, z, Blocks.LOOT_EMPTY)


# The hidden rooms around you, for the map table: nearest first, with how far and which way.
func rooms_around() -> Array:
	var here := World.cell_of(player.position)
	var reach := Vector3i(480, 240, 480)
	var out := []
	for room: Dictionary in world.gen.rooms_in_box(here - reach, here + reach):
		out.append(room)
	var p: Vector3 = player.position
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return p.distance_to(a["center"]) < p.distance_to(b["center"]))
	return out


func track(room: Dictionary) -> void:
	if room.is_empty():
		tracked = {}
		return
	tracked = {"id": room["id"], "name": room["name"], "center": room["center"], "top": (Vector3(room["lo"]) * World.VOXEL).y}


# --- Traps --------------------------------------------------------------------------------------

# Pressure plates in treasure rooms: step on one and it clicks. A moment later spikes shoot up
# through it, or darts fly out of the wall at you. Dig a plate out and it's harmless.
func _update_traps(delta: float) -> void:
	for key: String in _traps_cool.keys():
		_traps_cool[key] = float(_traps_cool[key]) - delta
		if float(_traps_cool[key]) <= 0.0:
			_traps_cool.erase(key)
	var feet := World.cell_of(player.body.position - Vector3(0.0, 0.06, 0.0))
	if player.body.on_floor and world.block(feet.x, feet.y, feet.z) == Blocks.TRAP_PLATE:
		var id: String = world.room_containing(player.body.position + Vector3(0.0, 0.2, 0.0))
		if id != "":
			var plates: Array = world.rooms[id].get("plates", [])
			for k in plates.size():
				var plate: Dictionary = plates[k]
				var lo: Vector3i = plate["lo"]
				var hi: Vector3i = plate["hi"]
				if feet.x >= lo.x and feet.x <= hi.x and feet.z >= lo.z and feet.z <= hi.z and not _traps_cool.has("%s/%d" % [id, k]):
					_spring(id, k)
	var i := _spikes.size() - 1
	while i >= 0:
		var s: Dictionary = _spikes[i]
		s["time"] = float(s["time"]) + delta
		var node: Node3D = s["node"]
		var t: float = s["time"]
		# A pause, a quick thrust up, a moment at the top, and back down.
		var up := 0.0
		if t > 0.35:
			up = clampf((t - 0.35) / 0.08, 0.0, 1.0) if t < 1.2 else clampf(1.0 - (t - 1.2) / 0.3, 0.0, 1.0)
		node.position.y = float(s["base"]) - 0.3 + 0.32 * up
		if up > 0.8 and not s["hit"]:
			var plate: Dictionary = s["plate"]
			var lo := Vector3(plate["lo"]) * World.VOXEL
			var hi := (Vector3(plate["hi"]) + Vector3.ONE) * World.VOXEL + Vector3(0.0, 0.6, 0.0)
			if player.body.overlaps(lo, hi):
				s["hit"] = true
				player.take_damage(float(s["damage"]), player.body.position + Vector3(0.0, -1.0, 0.0), 3.0)
		if t > 1.6:
			node.queue_free()
			_spikes.remove_at(i)
		i -= 1
	i = _gas.size() - 1
	while i >= 0:
		var g: Dictionary = _gas[i]
		g["time"] = float(g["time"]) - delta
		g["tick"] = float(g["tick"]) - delta
		if float(g["tick"]) <= 0.0:
			g["tick"] = 0.5
			effects.burst(g["pos"] + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 1.2), randf_range(-0.6, 0.6)), Color(0.45, 0.85, 0.3), 10, 0.6, 0.12, Vector3.UP, 80.0, -0.5, 1.2, false, true)
			if (player.body.position + Vector3(0.0, 0.9, 0.0)).distance_to(g["pos"]) < 2.2:
				player.take_damage(float(g["damage"]) * 0.5, g["pos"], 0.0)
		if float(g["time"]) <= 0.0:
			_gas.remove_at(i)
		i -= 1


func _trap_damage(id: String, base: float) -> float:
	var room: Dictionary = world.rooms.get(id, {})
	return base * pow(1.22, float(room.get("level", 1.0)))


func _spring(id: String, k: int) -> void:
	var plate: Dictionary = world.rooms[id]["plates"][k]
	_traps_cool["%s/%d" % [id, k]] = 3.0
	sfx.play("trap", randf_range(0.9, 1.0), -2.0)
	if plate["kind"] == "spikes":
		if _spike_mesh == null:
			var boxes := []
			for a in 4:
				for b in 4:
					boxes.append([Vector3(0.09 + a * 0.155, 0.12, 0.09 + b * 0.155), Vector3(0.035, 0.28, 0.035), Color(0.62, 0.63, 0.66)])
					boxes.append([Vector3(0.09 + a * 0.155, 0.28, 0.09 + b * 0.155), Vector3(0.016, 0.06, 0.016), Color(0.85, 0.86, 0.9)])
			_spike_mesh = Models.build(boxes)
		var base: float = (float(plate["lo"].y) + 1.0) * World.VOXEL
		var node := Models.instance(effects, _spike_mesh, world.material, Vector3(plate["lo"].x * World.VOXEL, base - 0.3, plate["lo"].z * World.VOXEL))
		_spikes.append({"room": id, "plate": plate, "time": 0.0, "node": node, "hit": false, "base": base, "damage": _trap_damage(id, 16.0)})
		get_tree().create_timer(0.35).timeout.connect(func() -> void: sfx.play_at("spikes", node.position + Vector3(0.4, 0.3, 0.4), randf_range(0.9, 1.1), 0.0))
	else:
		var aim: Vector3 = player.body.position + Vector3(0.0, 0.9, 0.0)
		var damage := _trap_damage(id, 10.0)
		var slits: Array = plate.get("slits", [])
		var n := 0
		for from: Vector3 in slits:
			n += 1
			get_tree().create_timer(0.25 + 0.12 * n).timeout.connect(func() -> void:
				if state != "playing":
					return
				projectiles.dart(from, (aim - from).normalized() * 24.0, damage)
				sfx.play_at("twang", from, randf_range(1.4, 1.6), -2.0))


# A trapped chest: poison gas pours out of it when it opens.
func _spring_chest(chest: Dictionary) -> void:
	var lo := Vector3(chest["lo"]) * World.VOXEL
	var hi := (Vector3(chest["hi"]) + Vector3.ONE) * World.VOXEL
	var at := (lo + hi) * 0.5
	var id: String = world.room_containing(at + Vector3(0.0, 0.2, 0.0))
	_gas.append({"pos": at, "time": 3.5, "tick": 0.0, "damage": _trap_damage(id, 7.0)})
	sfx.play("hiss", 0.7, 0.0)
	toast("A trap! Poison gas pours out of the chest. Step back!", WARN)


func _clear_traps() -> void:
	for s: Dictionary in _spikes:
		(s["node"] as Node).queue_free()
	_spikes.clear()
	_gas.clear()


# --- Your house ---------------------------------------------------------------------------------------

# Decorations, trophies and furniture on top of the house the world was made with. Furniture
# standing where a fixture now is (from before there was one) moves out of its way.
func _furnish() -> void:
	for id: String in decor:
		House.apply_decor(world, id, house_tier)
	House.show_trophies(world, decor, found, house_tier)
	var in_the_way: Array = []
	for rec: Dictionary in furniture:
		if House.blocks_fixture(rec):
			in_the_way.append(rec)
		else:
			House.build_furniture(world, rec)
	for rec: Dictionary in in_the_way:
		var spot: Vector2i = House.free_spot(world, rec["type"], rec["rot"], house_tier)
		if spot.x >= 0:
			rec["x"] = spot.x
			rec["z"] = spot.y
			House.build_furniture(world, rec)
			continue
		# Nowhere to put it: back in your pack to place again, and whatever was in it with it.
		furniture.erase(rec)
		unplaced.append(rec["type"])
		bag.append_array(storage.get(str(rec["id"]), []))
		storage.erase(str(rec["id"]))
	_update_lights()


func _update_lights() -> void:
	world.set_lights(House.lights(decor, house_tier))


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
		toast("Empty it first: take everything out before moving it.")
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


# --- Your pack and gear ------------------------------------------------------------------------------

func pack_slots() -> int:
	return int(Catalog.PACKS[workshop["pack"]]["slots"])


func bag_full() -> bool:
	return bag.size() >= pack_slots()


func equip(i: int) -> void:
	var item: Dictionary = bag[i]
	if not Goods.is_gear(item):
		return
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


# Moves something from a chest into your pack. Goods top up the stacks you already carry, so a
# stack may only partly fit.
func take_item(container: Array, i: int) -> void:
	var item: Dictionary = container[i]
	var before := int(item.get("count", 1))
	if Goods.put(bag, pack_slots(), item):
		container.remove_at(i)
		sfx.play("pickup", 1.0, -6.0)
	else:
		if Goods.is_good(item) and int(item["count"]) < before:
			sfx.play("pickup", 1.0, -6.0)
		toast("Your pack is full. Put something away first.")
	hud.refresh()
	menus.refresh()


func store_item(container: Array, slots: int, i: int) -> void:
	var item: Dictionary = bag[i]
	if Goods.put(container, slots, item):
		bag.remove_at(i)
		sfx.play("place", 1.1, -6.0)
	else:
		toast("It's full.")
	hud.refresh()
	menus.refresh()


func take_all(container: Array) -> void:
	var i := 0
	while i < container.size():
		if Goods.put(bag, pack_slots(), container[i]):
			container.remove_at(i)
		else:
			i += 1
	if not container.is_empty():
		toast("Your pack is full.")
	sfx.play("pickup", 1.0, -6.0)
	hud.refresh()
	menus.refresh()


# Puts away everything in your pack that isn't gear: ore, gems, bars, treasure and scrolls.
func store_finds(container: Array, slots: int) -> void:
	var i := 0
	var full := false
	while i < bag.size():
		var item: Dictionary = bag[i]
		if not Goods.is_gear(item) and Goods.put(container, slots, item):
			bag.remove_at(i)
		else:
			full = full or not Goods.is_gear(item)
			i += 1
	if full:
		toast("It's full.")
	sfx.play("place", 1.1, -6.0)
	hud.refresh()
	menus.refresh()


func salvage(i: int) -> void:
	var item: Dictionary = bag[i]
	if not Goods.is_gear(item):
		return
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


# Reading a scroll teaches you its affix for good (or a stronger version of one you know), to
# inscribe on your gear at the forge.
func learn_scroll(i: int) -> void:
	var item: Dictionary = bag[i]
	if not Goods.is_scroll(item):
		return
	var id: String = item["id"]
	var value := int(item["value"])
	if int(learned.get(id, 0)) >= value:
		toast("You already know this, at least as well. Sell the scroll at the workbench instead.")
		return
	var better := learned.has(id)
	learned[id] = value
	bag.remove_at(i)
	sfx.play("treasure", 1.2, -4.0)
	toast("%s %s: %s. Inscribe it on your gear at the forge." % ["You know it better now" if better else "Learned", Items.AFFIXES[id]["scroll"], Items.affix_text({"id": id, "value": value})], Hud.GOLD)
	hud.refresh()
	menus.refresh()
	save_game()


# --- Selling and the forge -------------------------------------------------------------------------

# The workbench buys everything you dig up or smelt, treasure and scrolls.
func sell(i: int) -> void:
	var value := Goods.worth(bag[i])
	if value <= 0:
		return
	var what := Goods.title(bag[i])
	bag.remove_at(i)
	coins += value
	sfx.play("coin")
	toast("Sold %s for %s coins." % [what, Hud.thousands(value)], Hud.GOLD)
	_bought()


# Sells everything of one sort: "ore" (ore and gems), "bar" or "treasure".
func sell_all(sort: String) -> void:
	var total := 0
	var i := bag.size() - 1
	while i >= 0:
		var item: Dictionary = bag[i]
		if Goods.sort_of(item) == sort:
			total += Goods.worth(item)
			bag.remove_at(i)
		i -= 1
	if total <= 0:
		return
	coins += total
	sfx.play("coin")
	toast("Sold for %s coins." % Hud.thousands(total), Hud.GOLD)
	_bought()


# Smelts a recipe up to `times` times over, as far as your pack has what it needs. The batch is
# worked out as a whole, so a full pack can still smelt once the ore it uses up makes room.
func smelt(k: int, times: int) -> void:
	var recipe: Dictionary = Goods.SMELT[k]
	var needs: Dictionary = recipe["in"]
	var n := mini(times, Goods.times(bag, needs))
	while n > 0:
		var after := _smelted(needs, recipe["out"], n)
		if not after.is_empty():
			bag.clear()
			bag.append_array(after)
			break
		n -= 1
	if n > 0:
		sfx.play("hiss", 0.7, -4.0)
		sfx.play("anvil", 1.3, -10.0)
		toast("Smelted %s." % Goods.amount(recipe["out"], n), Hud.GOLD)
	elif Goods.times(bag, needs) > 0:
		toast("Your pack is full. Make room first.", WARN)
	hud.refresh()
	menus.refresh()
	save_game()


# Your pack after smelting n times, or [] if the bars wouldn't fit. Your pack is left as it is.
func _smelted(needs: Dictionary, out: String, n: int) -> Array:
	var after := []
	for item: Dictionary in bag:
		after.append(item.duplicate() if Goods.is_good(item) else item)
	for id: String in needs:
		Goods.take(after, id, int(needs[id]) * n)
	if Goods.add(after, pack_slots(), out, n) < n:
		return []
	return after


# Improves a piece of gear you have one step, to the next material: it keeps its rarity and
# affixes, and digs harder rock or hits harder.
func upgrade_gear(item: Dictionary) -> void:
	if not Items.can_upgrade(item):
		return
	var next := int(item["tier"]) + 1
	var cost: Dictionary = Goods.UPGRADES[next]
	if coins < int(cost["coins"]) or Goods.times(bag, cost["in"]) < 1:
		return
	coins -= int(cost["coins"])
	for id: String in cost["in"]:
		Goods.take(bag, id, int(cost["in"][id]))
	var before := Items.title(item)
	item["tier"] = next
	sfx.play("anvil")
	sfx.play("hiss", 0.9, -8.0)
	toast("%s is %s now." % [before, Items.MATERIALS[next].to_lower()], Hud.GOLD)
	_gear_changed()
	save_game()


# Inscribes an affix you've learned from a scroll on a piece of gear, in place of what was
# inscribed there before.
func inscribe(item: Dictionary, id: String) -> void:
	if not learned.has(id) or not Items.fits_affix(item, id):
		return
	var cost := Items.inscribe_cost(item)
	if coins < cost:
		return
	coins -= cost
	item["inscription"] = {"id": id, "value": int(learned[id])}
	sfx.play("anvil", 1.1)
	sfx.play("treasure", 1.3, -10.0)
	toast("Inscribed: %s." % Items.affix_text(item["inscription"]), Hud.GOLD)
	_gear_changed()
	save_game()


# --- Buying ----------------------------------------------------------------------------------------

func buy_gear(kind: String) -> void:
	var cost: int = Catalog.GEAR_PRICES[kind]
	if coins < cost:
		return
	if not equipped[kind].is_empty() and bag_full():
		toast("Your pack is full. Make room first.")
		return
	coins -= cost
	var item := Items.make(kind, 0, 0, _rng)
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
	world.pinning = true
	House.build_shell(world, house_tier)
	_furnish()
	world.pinning = false
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


# --- Setup and saving -----------------------------------------------------------------------------

func _update_atmosphere(delta: float) -> void:
	var home := 1.0 if world.depth_at(player.position) < 0.5 else 0.0
	env.fog_density = lerpf(env.fog_density, lerpf(0.04, 0.006, home), 1.0 - exp(-delta * 2.0))


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],
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
	var tracked_out := {}
	if not tracked.is_empty():
		var c: Vector3 = tracked["center"]
		tracked_out = {"id": tracked["id"], "name": tracked["name"], "center": [c.x, c.y, c.z], "top": tracked["top"]}
	return {
		"version": SAVE_VERSION,
		"seed": world.world_seed,
		"found": found,
		"found_ids": world.found_ids.keys(),
		"mined": mined,
		"learned": learned,
		"coins": coins,
		"bag": bag,
		"equipped": equipped,
		"supplies": supplies,
		"workshop": workshop,
		"house": {"tier": house_tier, "decor": decor, "furniture": furniture, "unplaced": unplaced, "next_id": next_furniture_id},
		"storage": storage,
		"rooms": room_state,
		"player": [p.x, p.y, p.z, player.yaw, player.pitch],
		"return": return_point,
		"deepest": deepest,
		"health": player.health,
		"rested": rested,
		"slot": player.slot,
		"explosive": explosive_index,
		"tracked": tracked_out,
	}


func _load_progress(save: Dictionary) -> void:
	var saved_found: Dictionary = save.get("found", {})
	for k in saved_found:
		found[int(k)] = int(saved_found[k])
	var saved_mined: Dictionary = save.get("mined", {})
	for id in saved_mined:
		if Goods.LIST.has(str(id)):
			mined[str(id)] = maxi(0, int(saved_mined[id]))
	var saved_learned: Dictionary = save.get("learned", {})
	for id in saved_learned:
		if Items.SCROLL_AFFIXES.has(str(id)):
			learned[str(id)] = int(saved_learned[id])
	coins = int(save.get("coins", 0))
	for d in save.get("bag", []):
		var item := Goods.sanitize(d)
		if not item.is_empty():
			bag.append(item)
	var saved_equipped: Dictionary = save.get("equipped", {})
	for kind: String in equipped:
		var item := Items.sanitize(saved_equipped.get(kind, {}))
		equipped[kind] = item if not item.is_empty() and item["kind"] == kind else {}
	if equipped["pickaxe"].is_empty():
		equipped["pickaxe"] = Items.make("pickaxe", 1, 0, _rng)
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
				var item := Goods.sanitize(d)
				if not item.is_empty():
					list.append(item)
			storage[str(rec["id"])] = list
	var saved_rooms = save.get("rooms", {})
	if saved_rooms is Dictionary:
		for id in saved_rooms:
			var s = saved_rooms[id]
			if not s is Dictionary:
				continue
			var st := {"opened": bool(s.get("opened", false)), "dead": [], "chests": {}, "seen": bool(s.get("seen", false))}
			for k in s.get("dead", []):
				st["dead"].append(int(k))
			var chests: Dictionary = s.get("chests", {})
			for key in chests:
				var list := []
				for d in chests[key]:
					var item := Goods.sanitize(d)
					if not item.is_empty():
						list.append(item)
				st["chests"][str(key)] = list
			room_state[str(id)] = st
	rested = maxf(0.0, float(save.get("rested", 0.0)))
	deepest = maxf(0.0, float(save.get("deepest", 0.0)))
	explosive_index = clampi(int(save.get("explosive", 0)), 0, Catalog.EXPLOSIVE_ORDER.size() - 1)
	var back: Array = save.get("return", [])
	if back.size() == 5:
		return_point = [float(back[0]), float(back[1]), float(back[2]), float(back[3]), float(back[4])]
	var t = save.get("tracked", {})
	if t is Dictionary and t.has("id") and (t.get("center", []) as Array).size() == 3:
		var c: Array = t["center"]
		tracked = {"id": str(t["id"]), "name": str(t.get("name", "Hidden room")), "center": Vector3(c[0], c[1], c[2]), "top": float(t.get("top", c[1]))}


func save_game() -> void:
	if state in ["starting", "loading"]:
		return
	world.save_edits(WORLD_PATH)
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
	if not parsed is Dictionary or not parsed.has("seed"):
		return {}
	var data: Dictionary = parsed
	match int(data.get("version", 0)):
		SAVE_VERSION:
			return data
		3, 4, 5:
			return _from_old(data)
	return {}


# A save from 0.3 to 0.5 keeps everything you own, but the ground was a single dig site then, so
# you start in a fresh, endless world. Gear moves to the new materials; bows and arrows are
# gone, and so are the pickaxe grips and heads (every pickaxe's material sets how fast and wide
# it digs now): what they cost comes back as coins. You also get the wooden sword everyone
# starts with now, if you had no sword.
func _from_old(data: Dictionary) -> Dictionary:
	var refunds: Array[int] = []
	data["bag"] = _old_items(data.get("bag", []), refunds)
	var storage_in: Dictionary = data.get("storage", {})
	for key in storage_in:
		storage_in[key] = _old_items(storage_in[key], refunds)
	var equipped_in: Dictionary = data.get("equipped", {})
	var equipped_out := {}
	for kind in equipped_in:
		var got: Array = _old_items([equipped_in[kind]], refunds)
		if not got.is_empty() and str(kind) != "bow":
			equipped_out[str(kind)] = got[0]
	if (equipped_out.get("sword", {}) as Dictionary).is_empty():
		equipped_out["sword"] = Items.make("sword", 0, 0, _rng)
	data["equipped"] = equipped_out
	var refund := 0
	for n in refunds:
		refund += n
	var saved_workshop: Dictionary = data.get("workshop", {})
	refund += int(Catalog.OLD_GRIP_COSTS[clampi(int(saved_workshop.get("grip", 0)), 0, 3)])
	refund += int(Catalog.OLD_SIZE_COSTS[clampi(int(saved_workshop.get("size", 0)), 0, 3)])
	var arrows := int((data.get("supplies", {}) as Dictionary).get("arrows", 0))
	refund += arrows
	var carried := (data["bag"] as Array).size()
	var level := clampi(int(saved_workshop.get("pack", 0)), 0, Catalog.PACKS.size() - 1)
	while level < Catalog.PACKS.size() - 1 and int(Catalog.PACKS[level]["slots"]) < carried:
		level += 1
	data["workshop"] = {"pack": level}
	data["coins"] = int(data.get("coins", 0)) + refund
	data["version"] = SAVE_VERSION
	data["seed"] = randi()
	data["rooms"] = {}
	data["found_ids"] = []
	data["tracked"] = {}
	data["return"] = []
	data.erase("player")
	data.erase("vaults")
	data.erase("edits")
	data["refund"] = refund
	return data


# Gear from 0.5 or earlier moved to the new materials. A bow is broken down for what it was worth
# then, into `refunds`.
func _old_items(list, refunds: Array[int]) -> Array:
	var out := []
	if not list is Array:
		return out
	for d in list:
		if d is Dictionary and str(d.get("kind", "")) == "bow":
			refunds.append(roundi([8, 35, 100, 260, 700][clampi(int(d.get("rarity", 0)), 0, 4)] * (1.0 + 0.6 * clampi(int(d.get("tier", 0)), 0, 3))))
		elif d is Dictionary and Items.KINDS.has(str(d.get("kind", ""))):
			var item := Items.from_old(d)
			if not item.is_empty():
				out.append(item)
		else:
			out.append(d)
	return out
