extends Node2D
## Game root and the day loop: at home time stands still; the door sends you to the forest
## or the mine for a 5-minute trip, then you come home and a new day starts. Also owns the
## backpack, tools, building, the forge and saving.

const Data := preload("res://scripts/game_data.gd")
const AreaScript := preload("res://scripts/world/area.gd")
const WorldGen := preload("res://scripts/world/world_gen.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")

const SAVE_PATH := "user://save_v2.json"
const ZOOM := 1.75
const INTERACT_DISTANCE := 30.0
const HOUSE_LIGHT := Color(0.95, 0.9, 0.82)
const MINE_DARK := Color(0.1, 0.09, 0.12)
const FOREST_DAY := Color(1, 1, 1)
const FOREST_DUSK := Color(0.55, 0.42, 0.55)

var day := 1
var inventory := {}
var tools: Array = []
var equipped := 0
var placed: Array = []
var forge_lit := false
var location := "house"
var mine_depth := 0
var run_left := 0.0
var day_gains := {}
var build_mode := false
var build_kind := ""

var area
var player
var hud
var camera: Camera2D
var target_cell := Vector2i(-1, -1)
var target_info := {}

var _hit_held := false
var _transitioning := false
var _msg_cooldown := 0.0
var _warned := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_setup_input()
	var has_save := _load_game()
	if tools.is_empty():
		tools = Data.STARTING_TOOLS.duplicate()
	equipped = clampi(equipped, 0, tools.size() - 1)

	camera = Camera2D.new()
	camera.zoom = Vector2(ZOOM, ZOOM)
	add_child(camera)
	player = PlayerScript.new()
	player.game = self
	hud = HudScript.new()
	hud.game = self
	add_child(hud)

	_enter_area(_make_house())
	hud.refresh()
	if not has_save:
		hud.show_message("Welcome home! Walk out the door to start your first day.", Data.ITEMS["handle"]["color"].lightened(0.4))


func _process(delta: float) -> void:
	_msg_cooldown -= delta
	if area == null:
		return
	if build_mode or location == "house":
		target_info = {}
	else:
		target_cell = player.aim_cell()
		target_info = area.hit_info(target_cell)

	var hint := ""
	if can_control() and not build_mode:
		var e = area.nearest_interactable(player.position, INTERACT_DISTANCE)
		if e != null:
			hint = "[E]  " + Data.INTERACTIONS[e.kind]
	hud.set_hint(hint)

	if location != "house" and not _transitioning:
		run_left -= delta
		_warn_at(60.0, "One minute left before nightfall.")
		_warn_at(15.0, "It's getting dark. Time to head home!")
		if run_left <= 0.0:
			run_left = 0.0
			end_run(false)
	hud.update_clock(run_left if location != "house" else -1.0)
	_update_ambient()
	_update_camera(delta)


func _warn_at(seconds: float, text: String) -> void:
	if run_left <= seconds and not _warned.has(seconds):
		_warned[seconds] = true
		hud.show_message(text, Color(1, 0.75, 0.5))


# --- Queries used by the player and the HUD -----------------------------------------

func can_control() -> bool:
	return not _transitioning and not hud.any_open()


func wants_hit() -> bool:
	return _hit_held and can_control() and not build_mode


func equipped_tool() -> Dictionary:
	if tools.is_empty():
		return {}
	return Data.TOOLS[tools[equipped]]


func count(id: String) -> int:
	return int(inventory.get(id, 0))


func has_items(cost: Dictionary) -> bool:
	for id in cost:
		if count(id) < int(cost[id]):
			return false
	return true


func place_name() -> String:
	match location:
		"forest":
			return "The Forest"
		"mine":
			return "The Mine  -  depth %d" % (mine_depth + 1)
	return "Home"


## The next tool you can forge for a kind ("pickaxe", "axe"), or "" if yours is the best.
func next_tool(kind: String) -> String:
	var line: Array = Data.TOOL_LINES[kind]
	var best := -1
	for id in tools:
		best = maxi(best, line.find(id))
	if best + 1 >= line.size():
		return ""
	return line[best + 1]


# --- Inventory ----------------------------------------------------------------------

func add_item(id: String, n: int) -> void:
	inventory[id] = count(id) + n
	if location != "house":
		day_gains[id] = int(day_gains.get(id, 0)) + n


func _pay(cost: Dictionary) -> void:
	for id in cost:
		inventory[id] = count(id) - int(cost[id])
		if inventory[id] <= 0:
			inventory.erase(id)


func _refund(cost: Dictionary) -> void:
	for id in cost:
		inventory[id] = count(id) + int(cost[id])


# --- Hitting ------------------------------------------------------------------------

func on_swing(cell: Vector2i) -> void:
	var result: Dictionary = area.hit(cell, equipped_tool())
	if result.has("problem"):
		_message(result["problem"], Color(1, 0.7, 0.55))
	elif result.has("drops"):
		var at: Vector2 = result["at"]
		var drops: Dictionary = result["drops"]
		for id in drops:
			add_item(id, drops[id])
			var col: Color = Data.ITEMS[id]["color"]
			area.add_floater(at, "+%d %s" % [drops[id], Data.ITEMS[id]["name"]], col.lerp(Color.WHITE, 0.4))
			at += Vector2(0, -14)
		hud.refresh()


func equip(index: int) -> void:
	if index < 0 or index >= tools.size():
		return
	equipped = index
	hud.refresh()


# --- Day loop -----------------------------------------------------------------------

func start_run(dest: String) -> void:
	if location != "house" or _transitioning:
		return
	hud.close_menus()
	_set_build_mode(false)
	_begin_transition(_do_start_run.bind(dest))


func _do_start_run(dest: String) -> void:
	forge_lit = false
	location = dest
	mine_depth = 0
	run_left = Data.RUN_SECONDS
	day_gains = {}
	_warned = {}
	_enter_area(_make_destination())
	hud.refresh()
	if dest == "forest":
		hud.show_message("Chop trees with your axe. Old oaks need a copper axe.", Color(0.75, 0.95, 0.7))
	else:
		hud.show_message("Follow the ore veins with your pickaxe. Find the hole to go deeper.", Color(0.9, 0.85, 0.7))


func descend() -> void:
	_begin_transition(_do_descend)


func _do_descend() -> void:
	mine_depth += 1
	_enter_area(_make_destination())
	hud.refresh()
	hud.show_message("Depth %d. The veins look richer down here." % (mine_depth + 1), Color(0.9, 0.85, 0.7))


func end_run(early: bool) -> void:
	if location == "house" or _transitioning:
		return
	_begin_transition(_do_end_run.bind(early))


func _do_end_run(early: bool) -> void:
	var finished := day
	day += 1
	location = "house"
	run_left = 0.0
	_enter_area(_make_house())
	_save_game()
	hud.refresh()
	hud.open_menu("summary", {"day": finished, "gains": day_gains.duplicate(), "early": early})


func _begin_transition(mid: Callable) -> void:
	_transitioning = true
	_hit_held = false
	hud.fade(mid, _end_transition)


func _end_transition() -> void:
	_transitioning = false


func _make_house():
	var a = AreaScript.new()
	WorldGen.build_house(a, placed)
	return a


func _make_destination():
	var a = AreaScript.new()
	if location == "forest":
		WorldGen.build_forest(a, _rng)
	else:
		WorldGen.build_mine(a, mine_depth, _rng)
	return a


func _enter_area(new_area) -> void:
	if area != null:
		area.entities.remove_child(player)
		remove_child(area)
		area.queue_free()
	area = new_area
	area.game = self
	add_child(area)
	move_child(area, 0)
	area.entities.add_child(player)
	player.area = area
	player.position = area.spawn
	player.light.visible = area.kind == "mine"
	target_info = {}
	_update_ambient()
	_update_camera(0.0, true)


func _update_ambient() -> void:
	match area.kind:
		"house":
			area.set_ambient(HOUSE_LIGHT)
		"mine":
			area.set_ambient(MINE_DARK)
		"forest":
			var t := 1.0 - run_left / Data.RUN_SECONDS
			area.set_ambient(FOREST_DAY.lerp(FOREST_DUSK, smoothstep(0.55, 1.0, t)))


func _update_camera(delta: float, snap := false) -> void:
	var view := get_viewport_rect().size / camera.zoom
	var world := Vector2(area.width, area.height) * Data.TILE
	var target: Vector2 = player.position + Vector2(0, -12)
	for axis in 2:
		if world[axis] <= view[axis]:
			target[axis] = world[axis] / 2.0
		else:
			target[axis] = clampf(target[axis], view[axis] / 2.0, world[axis] - view[axis] / 2.0)
	if snap:
		camera.position = target
		camera.reset_smoothing()
	else:
		camera.position = camera.position.lerp(target, 1.0 - exp(-delta * 10.0))


# --- Interacting --------------------------------------------------------------------

func _interact() -> void:
	var e = area.nearest_interactable(player.position, INTERACT_DISTANCE)
	if e == null:
		return
	match e.kind:
		"door":
			hud.open_menu("door")
		"forge":
			hud.open_menu("forge")
		"workbench":
			hud.open_menu("workbench")
		"bed":
			_message("You're not sleepy. Days only pass while you're out.", Color(0.85, 0.85, 1.0))
		"ladder_down":
			descend()
		"ladder_up", "exit_sign":
			end_run(true)
	_hit_held = false


func light_forge() -> void:
	if forge_lit or not has_items(Data.FORGE_LIGHT_COST):
		return
	_pay(Data.FORGE_LIGHT_COST)
	forge_lit = true
	hud.show_message("The forge roars to life.", Color(1, 0.7, 0.4))
	_after_crafting()


func smelt(recipe_index: int, times: int) -> void:
	var r: Dictionary = Data.SMELTING[recipe_index]
	var n := mini(times, count(r["input"]) / int(r["amount"]))
	if not forge_lit or n <= 0:
		return
	_pay({r["input"]: n * int(r["amount"])})
	add_item(r["output"], n)
	hud.show_message("Smelted %d %s." % [n, Data.ITEMS[r["output"]]["name"]], Color(1, 0.8, 0.5))
	_after_crafting()


func forge_tool(tool_id: String) -> void:
	var tool: Dictionary = Data.TOOLS[tool_id]
	if not forge_lit or not has_items(tool["recipe"]):
		return
	_pay(tool["recipe"])
	# The new tool replaces the old one of the same kind, in the same hotbar slot.
	var slot := -1
	for i in tools.size():
		if Data.TOOLS[tools[i]]["kind"] == tool["kind"]:
			slot = i
	if slot >= 0:
		tools[slot] = tool_id
	else:
		tools.append(tool_id)
		slot = tools.size() - 1
	equipped = slot
	hud.show_message("You forged a %s!" % tool["name"], Color(1, 0.85, 0.4))
	_after_crafting()


func craft_handle(times: int) -> void:
	var n := mini(times, count("wood") / int(Data.HANDLE_RECIPE["wood"]))
	if n <= 0:
		return
	_pay({"wood": n * int(Data.HANDLE_RECIPE["wood"])})
	add_item("handle", n)
	hud.show_message("Carved %d tool handle%s." % [n, "" if n == 1 else "s"], Color(0.9, 0.8, 0.6))
	_after_crafting()


func _after_crafting() -> void:
	_save_game()
	hud.refresh()


# --- Building -----------------------------------------------------------------------

func _set_build_mode(on: bool) -> void:
	build_mode = on and location == "house"
	build_kind = ""
	_hit_held = false
	hud.set_build_mode(build_mode)


func select_build(kind: String) -> void:
	build_kind = "" if build_kind == kind else kind
	hud.refresh()


func _ghost_cell() -> Vector2i:
	var size := Data.entity_size(build_kind)
	return area.cell_of(area.get_global_mouse_position()) - Vector2i((size.x - 1) / 2, (size.y - 1) / 2)


func _player_rect() -> Rect2:
	return Rect2(player.position - Vector2(8, 10), Vector2(16, 12))


func _try_place() -> void:
	var info: Dictionary = Data.BUILDABLES[build_kind]
	var cell := _ghost_cell()
	if not has_items(info["cost"]):
		_message("You need %s for a %s." % [Data.cost_text(info["cost"]), String(info["name"]).to_lower()], Color(1, 0.7, 0.55))
		return
	if not area.can_place(cell, info["size"], _player_rect()):
		_message("It doesn't fit there.", Color(1, 0.7, 0.55))
		return
	_pay(info["cost"])
	placed.append({"kind": build_kind, "x": cell.x, "y": cell.y})
	area.add_entity(build_kind, cell)
	if not has_items(info["cost"]):
		build_kind = ""
	_after_crafting()


func _try_pick_up() -> void:
	var e = area.entity_at(area.cell_of(area.get_global_mouse_position()))
	if e == null or not Data.BUILDABLES.has(e.kind):
		return
	if e.kind == "forge":
		forge_lit = false
	_refund(Data.BUILDABLES[e.kind]["cost"])
	for i in placed.size():
		var p: Dictionary = placed[i]
		if p["kind"] == e.kind and int(p["x"]) == e.cell.x and int(p["y"]) == e.cell.y:
			placed.remove_at(i)
			break
	area.remove_entity(e)
	_after_crafting()


## Called by the area's effect layer every frame: target outline, build ghost.
func draw_world_overlay(ci: CanvasItem) -> void:
	if build_mode:
		var mouse_cell: Vector2i = area.cell_of(area.get_global_mouse_position())
		if build_kind != "":
			var info: Dictionary = Data.BUILDABLES[build_kind]
			var cell := _ghost_cell()
			var ok: bool = area.can_place(cell, info["size"], _player_rect()) and has_items(info["cost"])
			var rect := Rect2(Vector2(cell) * Data.TILE, Vector2(info["size"]) * Data.TILE)
			var col := Color(0.4, 1.0, 0.5) if ok else Color(1.0, 0.4, 0.35)
			ci.draw_rect(rect, Color(col, 0.3))
			ci.draw_rect(rect, col, false, 2.0)
			ci.draw_string(ThemeDB.fallback_font, rect.position + Vector2(0, -4), info["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		else:
			var e = area.entity_at(mouse_cell)
			if e != null and Data.BUILDABLES.has(e.kind):
				ci.draw_rect(area.footprint(e).grow(1), Color(1, 0.85, 0.4), false, 2.0)
		return
	if target_info.is_empty():
		return
	var problem := Data.tool_problem(target_info, equipped_tool())
	var rect: Rect2 = target_info["rect"]
	ci.draw_rect(rect.grow(1), Color(1, 1, 1, 0.55) if problem == "" else Color(1, 0.45, 0.4, 0.7), false, 1.5)
	var hp: float = target_info["hp"]
	var max_hp: float = target_info["max_hp"]
	if hp < max_hp:
		var bar := Rect2(rect.position + Vector2(2, -6), Vector2(rect.size.x - 4, 4))
		ci.draw_rect(bar, Color(0, 0, 0, 0.6))
		ci.draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp / max_hp, bar.size.y)), Color(1, 0.85, 0.3))


func _message(text: String, color: Color) -> void:
	if _msg_cooldown > 0.0:
		return
	_msg_cooldown = 1.5
	hud.show_message(text, color)


# --- Input ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Releasing the button anywhere (even over the UI) stops repeated swings.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_hit_held = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if build_mode:
					if build_kind != "" and can_control():
						_try_place()
				else:
					_hit_held = true
			MOUSE_BUTTON_RIGHT:
				if build_mode and can_control():
					if build_kind != "":
						build_kind = ""
						hud.refresh()
					else:
						_try_pick_up()
			MOUSE_BUTTON_WHEEL_UP:
				if can_control() and not tools.is_empty():
					equip((equipped - 1 + tools.size()) % tools.size())
			MOUSE_BUTTON_WHEEL_DOWN:
				if can_control() and not tools.is_empty():
					equip((equipped + 1) % tools.size())
		return
	if event.is_action_pressed("ui_cancel"):
		if hud.any_open():
			hud.close_menus()
		elif build_mode:
			_set_build_mode(false)
		return
	if not can_control():
		return
	if event.is_action_pressed("interact") and not build_mode:
		_interact()
	elif event.is_action_pressed("build"):
		if location == "house":
			_set_build_mode(not build_mode)
		else:
			_message("You can only build at home.", Color(1, 0.7, 0.55))
	else:
		for i in 5:
			if event.is_action_pressed("tool_%d" % (i + 1)):
				equip(i)


func _setup_input() -> void:
	# Physical keys, so WASD is ZQSD on AZERTY keyboards automatically.
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_E],
		"build": [KEY_B],
		"tool_1": [KEY_1],
		"tool_2": [KEY_2],
		"tool_3": [KEY_3],
		"tool_4": [KEY_4],
		"tool_5": [KEY_5],
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


# --- Saving -------------------------------------------------------------------------------

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


func _save_game() -> void:
	var data := {"day": day, "inventory": inventory, "tools": tools, "equipped": equipped, "placed": placed}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func _load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	day = maxi(1, int(parsed.get("day", 1)))
	var inv: Dictionary = parsed.get("inventory", {})
	for id in inv:
		if Data.ITEMS.has(id) and int(inv[id]) > 0:
			inventory[id] = int(inv[id])
	for id in parsed.get("tools", []):
		if Data.TOOLS.has(id):
			tools.append(String(id))
	equipped = int(parsed.get("equipped", 0))
	for p in parsed.get("placed", []):
		if typeof(p) == TYPE_DICTIONARY and Data.BUILDABLES.has(p.get("kind", "")):
			placed.append({"kind": String(p["kind"]), "x": int(p["x"]), "y": int(p["y"])})
	return true
