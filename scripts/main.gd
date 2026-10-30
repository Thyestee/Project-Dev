extends Node2D
## Game root: owns the player's progress, switches mine levels, saves and loads.

const Data := preload("res://scripts/game_data.gd")
const LevelScript := preload("res://scripts/mine_level.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")

const SAVE_PATH := "user://mine_save.json"
const LEVEL_REGEN_TIME := 45.0
const AUTOSAVE_INTERVAL := 20.0
const VIEW_SIZE := Vector2(1280, 720)

var money := 0
var pick_tier := 0
var bag_tier := 0
var unlocked := 1
var inventory := {}
var collection := {}
var current_level := 0

var level
var player
var hud

# Floors you left keep their dug state until they have had time to regrow.
var _level_states := {}
var _rng := RandomNumberGenerator.new()
var _bag_msg_cooldown := 0.0
var _autosave_timer := 0.0


func _ready() -> void:
	_rng.randomize()
	_setup_input()
	var has_save := _load_game()

	level = LevelScript.new()
	level.position = Vector2((VIEW_SIZE.x - LevelScript.W * LevelScript.TILE) / 2.0, 170)
	add_child(level)
	player = PlayerScript.new()
	player.level = level
	player.game = self
	level.player = player
	level.add_child(player)
	hud = HudScript.new()
	hud.game = self
	add_child(hud)

	_enter_level(0, false)
	if not has_save:
		hud.show_message("You bought an old mine! Dig ore, then sell it at the elevator.", Color(1, 0.9, 0.6))


func _process(delta: float) -> void:
	_bag_msg_cooldown -= delta
	hud.set_hint_visible(player.cell == LevelScript.ELEVATOR and not hud.any_open())
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		_save_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if hud.elevator_open():
			hud.close_menus()
		elif player.cell == LevelScript.ELEVATOR and not hud.any_open():
			hud.open_elevator()
	elif event.is_action_pressed("collection"):
		hud.toggle_collection()
	elif event.is_action_pressed("ui_cancel"):
		hud.close_menus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


func _draw() -> void:
	var bg: Color = Data.LEVELS[current_level]["rock"].darkened(0.82)
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), bg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 140:
		var p := Vector2(rng.randf() * VIEW_SIZE.x, rng.randf() * VIEW_SIZE.y)
		var s := Vector2(rng.randf_range(10, 60), rng.randf_range(4, 16))
		draw_rect(Rect2(p, s), bg.lightened(rng.randf_range(0.02, 0.07)))


# --- Mining -------------------------------------------------------------------

func can_mine(t: int) -> bool:
	if t in Data.ORE_ORDER and bag_count() >= bag_capacity():
		if _bag_msg_cooldown <= 0.0:
			hud.show_message("Your bag is full! Head back to the elevator to sell.", Color(1, 0.55, 0.45))
			_bag_msg_cooldown = 2.5
		return false
	return true


func on_block_mined(t: int, c: Vector2i) -> void:
	if t == Data.RELIC:
		_find_relic(c)
	elif t in Data.ORE_ORDER:
		inventory[t] = int(inventory.get(t, 0)) + 1
		var info: Dictionary = Data.BLOCKS[t]
		var col: Color = info["color"]
		level.add_floater(c, "+1 %s" % info["name"], col.lerp(Color.WHITE, 0.35))
	hud.refresh()


func _find_relic(c: Vector2i) -> void:
	# Each floor hides its own relics; ones you have not found yet turn up more often.
	var weights := {}
	for i in Data.COLLECTIBLES.size():
		var info: Dictionary = Data.COLLECTIBLES[i]
		if int(info["level"]) == current_level:
			weights[i] = int(info["weight"]) * (1 if collection.has(i) else 2)
	var idx: int = Data.pick_weighted(weights, _rng)
	var relic: Dictionary = Data.COLLECTIBLES[idx]
	var count := int(collection.get(idx, 0)) + 1
	collection[idx] = count
	if count == 1:
		hud.show_message("NEW RELIC: %s!  All ore now sells for +5%% more." % relic["name"], relic["color"])
		level.add_floater(c, relic["name"], Color(1, 0.92, 0.55))
	else:
		var reward := relic_duplicate_value(current_level)
		money += reward
		hud.show_message("Another %s - sold the duplicate for $%d" % [relic["name"], reward], Color(1, 0.9, 0.55))
		level.add_floater(c, "+$%d" % reward, Color(1, 0.9, 0.4))
	_save_game()


func relic_duplicate_value(index: int) -> int:
	return 20 * (index + 1) * (index + 1)


# --- Economy ----------------------------------------------------------------

func pick_power() -> float:
	return float(Data.PICKAXES[pick_tier]["power"])


func bag_capacity() -> int:
	return int(Data.BAGS[bag_tier]["capacity"])


func bag_count() -> int:
	var n := 0
	for k in inventory:
		n += int(inventory[k])
	return n


func unique_relics() -> int:
	return collection.size()


func relic_bonus() -> float:
	return 0.05 * unique_relics()


func bag_value() -> int:
	var total := 0
	for k in inventory:
		total += int(inventory[k]) * int(Data.BLOCKS[k]["value"])
	return roundi(total * (1.0 + relic_bonus()))


func next_pick_cost() -> int:
	if pick_tier + 1 >= Data.PICKAXES.size():
		return -1
	return int(Data.PICKAXES[pick_tier + 1]["cost"])


func next_bag_cost() -> int:
	if bag_tier + 1 >= Data.BAGS.size():
		return -1
	return int(Data.BAGS[bag_tier + 1]["cost"])


func sell_all() -> void:
	var value := bag_value()
	if value <= 0:
		return
	money += value
	inventory.clear()
	hud.show_message("Sold your ore for $%d" % value, Color(1, 0.85, 0.3))
	_save_game()
	hud.refresh()


func buy_pickaxe() -> void:
	var cost := next_pick_cost()
	if cost < 0 or money < cost:
		return
	money -= cost
	pick_tier += 1
	hud.show_message("New pickaxe: %s!" % Data.PICKAXES[pick_tier]["name"], Color(0.7, 0.9, 1.0))
	_save_game()
	hud.refresh()


func buy_bag() -> void:
	var cost := next_bag_cost()
	if cost < 0 or money < cost:
		return
	money -= cost
	bag_tier += 1
	hud.show_message("New bag: %s!" % Data.BAGS[bag_tier]["name"], Color(0.7, 0.9, 1.0))
	_save_game()
	hud.refresh()


func buy_level() -> void:
	if unlocked >= Data.LEVELS.size():
		return
	var cost := int(Data.LEVELS[unlocked]["cost"])
	if money < cost:
		return
	money -= cost
	unlocked += 1
	hud.show_message("Level %d unlocked: %s" % [unlocked, Data.LEVELS[unlocked - 1]["name"]], Color(0.7, 1.0, 0.7))
	_save_game()
	hud.refresh()


# --- Levels -----------------------------------------------------------------

func travel_to(index: int) -> void:
	if index >= unlocked or index == current_level:
		return
	hud.close_menus()
	_enter_level(index)


func regen_remaining(index: int) -> float:
	if index == current_level or not _level_states.has(index):
		return 0.0
	var left_at: float = _level_states[index]["left_at"]
	return maxf(0.0, LEVEL_REGEN_TIME - (_now() - left_at))


func _enter_level(index: int, store_current := true) -> void:
	if store_current:
		_level_states[current_level] = {"cells": level.cells.duplicate(), "left_at": _now()}
	var still_dug := regen_remaining(index) > 0.0
	current_level = index
	if still_dug:
		level.restore(index, _level_states[index]["cells"])
	else:
		level.generate(index)
	player.place_at(LevelScript.ELEVATOR)
	queue_redraw()
	hud.refresh()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Input & saving -----------------------------------------------------------

func _setup_input() -> void:
	# Physical keys, so WASD is ZQSD on AZERTY keyboards automatically.
	var bindings := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_E],
		"collection": [KEY_C],
	}
	for action in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _save_game() -> void:
	var inv := {}
	for k in inventory:
		inv[str(k)] = inventory[k]
	var col := {}
	for k in collection:
		col[str(k)] = collection[k]
	var data := {
		"money": money, "pick": pick_tier, "bag": bag_tier, "unlocked": unlocked,
		"inventory": inv, "collection": col,
	}
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
	money = int(parsed.get("money", 0))
	pick_tier = clampi(int(parsed.get("pick", 0)), 0, Data.PICKAXES.size() - 1)
	bag_tier = clampi(int(parsed.get("bag", 0)), 0, Data.BAGS.size() - 1)
	unlocked = clampi(int(parsed.get("unlocked", 1)), 1, Data.LEVELS.size())
	var inv: Dictionary = parsed.get("inventory", {})
	for k in inv:
		inventory[str(k).to_int()] = int(inv[k])
	var col: Dictionary = parsed.get("collection", {})
	for k in col:
		collection[str(k).to_int()] = int(col[k])
	return true
