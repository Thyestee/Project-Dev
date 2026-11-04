extends CanvasLayer
# The full-screen menus: loading, title, pause, the journal, the workbench, the forge, your pack,
# chests, the anvil, the map table, the checkpoints you can travel to, and coming round after a
# knockout.

const Treasures := preload("res://scripts/treasures.gd")
const Items := preload("res://scripts/items.gd")
const Goods := preload("res://scripts/goods.gd")
const Catalog := preload("res://scripts/catalog.gd")
const House := preload("res://scripts/house.gd")
const Blocks := preload("res://scripts/blocks.gd")

const GOLD := Color(1.0, 0.84, 0.4)
const TEXT := Color(0.93, 0.91, 0.86)
const DIM := Color(0.75, 0.75, 0.75)
const GOOD := Color(0.55, 0.85, 0.5)
const BAD := Color(0.8, 0.5, 0.45)
const SHOP_TABS := [["sell", "Sell"], ["gear", "Gear"], ["supplies", "Supplies"], ["workshop", "Workshop"], ["house", "House"], ["furniture", "Furniture"]]
const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
const CONTROLS := [
	"WASD move  ·  Space jump  ·  Shift sprint  ·  Ctrl crouch  ·  hold Alt against a wall to climb  ·  Mouse look",
	"1-4 or wheel: pickaxe, sword, mace, explosives  ·  R changes the explosive",
	"Pickaxe: left click digs, right click flattens  ·  Sword or mace: right click raises your shield",
	"E use or pick up  ·  G move furniture  ·  I pack  ·  Tab journal  ·  Esc pause",
]

var game
var current := ""          # the menu that's open, or ""
var confirm_from := "title"
var _data = null
var _root: ColorRect
var _box: VBoxContainer
var _loading_label: Label
var _selected := {}        # {"where": "bag" / "equipped" / "chest", "index": number or kind}
var _details: VBoxContainer
var _shop_tab := "sell"


func _ready() -> void:
	layer = 10
	_root = ColorRect.new()
	_root.color = Color(0.03, 0.025, 0.02, 0.72)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	center.add_child(_box)
	var version := _label("v" + str(ProjectSettings.get_setting("application/config/version", "dev")), 14, DIM)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(version)


# --- Building blocks ----------------------------------------------------------------

func _label(text: String, font_size := 16, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _wrapped(l: Label, width: float) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _style(bg: Color, border: Color, width := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	return sb


func _button(text: String, action: Callable, min_size := Vector2(280, 44), font_size := 18) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", _style(Color(0.2, 0.15, 0.1, 0.92), Color(0.55, 0.43, 0.24)))
	button.add_theme_stylebox_override("hover", _style(Color(0.32, 0.24, 0.13, 0.95), GOLD))
	button.add_theme_stylebox_override("pressed", _style(Color(0.14, 0.1, 0.06, 0.95), GOLD))
	button.add_theme_stylebox_override("disabled", _style(Color(0.1, 0.09, 0.08, 0.8), Color(0.25, 0.22, 0.2)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.4))
	button.pressed.connect(action)
	return button


func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, height)
	return gap


func _column(title: String, width := 0.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	if width > 0.0:
		column.custom_minimum_size = Vector2(width, 0)
	column.add_child(_label(title, 20, GOLD))
	return column


# A list that scrolls when it's taller than `height`.
func _scroll_list(parent: Control, size: Vector2) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list


static func thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _open(title: String, title_size := 40) -> void:
	_clear(_box)
	game.hud.hide_messages()
	_root.visible = true
	_box.add_child(_centered(_label(title, title_size, GOLD)))


func _show_simple(title: String, lines: Array, buttons: Array) -> void:
	current = ""
	_open(title, 54)
	for line: String in lines:
		_box.add_child(_centered(_label(line, 17)))
	if not buttons.is_empty():
		_box.add_child(_gap(12))
	for b: Array in buttons:
		_box.add_child(_button(b[0], b[1]))


# --- Simple screens -------------------------------------------------------------------

func close() -> void:
	if current == "chest" and _data is Dictionary:
		game.chest_closed(_data)
	current = ""
	_data = null
	_selected = {}
	_root.visible = false


func show_loading(progress: float) -> void:
	if _loading_label == null or not is_instance_valid(_loading_label) or not _root.visible:
		_show_simple("DEEP FINDS", ["Digging..."], [])
		_loading_label = _box.get_child(1) as Label
	_loading_label.text = "Digging... %d%%" % int(progress * 100.0)


func show_title(has_save: bool) -> void:
	var lines: Array = ["Under your house the ground goes on for ever, and 10 km down. It's full of ore and gems, better the deeper you dig.",
		"Carry them home to sell at the workbench, or smelt them at the forge to improve your gear.",
		"Hidden rooms are everywhere down there: guards, chests and traps, trials to test your jumping, and checkpoints to take you home.", ""]
	lines.append_array(CONTROLS)
	var buttons: Array = [["Continue digging" if has_save else "Start digging", Callable(game, "start_playing")]]
	if has_save:
		lines.append("")
		lines.append("So far: %d treasures found, %s coins to spend, %s m down at the deepest." % [game.found_count(), thousands(game.coins), thousands(roundi(game.deepest))])
		buttons.append(["New game", Callable(self, "_ask_new_game").bind("title")])
	_show_simple("DEEP FINDS", lines, buttons)


func show_pause() -> void:
	var lines: Array = [""]
	lines.append_array(CONTROLS)
	lines.append("")
	lines.append("To get home, climb back up or use a checkpoint: find one deep down and unlock its waystone.")
	_show_simple("Paused", lines, [
		["Resume", Callable(game, "resume")],
		["New game", Callable(self, "_ask_new_game").bind("paused")],
		["Save and quit", Callable(game, "save_and_quit")],
	])


func _ask_new_game(from: String) -> void:
	confirm_from = from
	game.ask_new_game()


func show_new_game_confirm() -> void:
	_show_simple("Start a new game?", ["Everything starts over: a new world, and no coins, gear, pack, house, furniture, scrolls or journal.", "There's no going back to this game afterwards."], [
		["Yes, start over", Callable(game, "new_game")],
		["Cancel", Callable(game, "cancel_new_game")],
	])


func show_dead() -> void:
	_show_simple("Knocked out!", ["Everything goes dark...", "You come round at home, a bit bruised. You keep everything you had.", "The guards you left standing are back on their feet. The rope lift by your door takes you down to any checkpoint you've unlocked."], [
		["Wake up", Callable(game, "wake_up")],
	])


# --- The menus you open while playing --------------------------------------------------------

func open(menu: String, data = null) -> void:
	current = menu
	_data = data
	_selected = {}
	if menu == "shop" and _has_sellables():
		_shop_tab = "sell"
	refresh()


func refresh() -> void:
	match current:
		"shop":
			_shop()
		"forge":
			_forge()
		"inventory":
			_inventory()
		"chest":
			_chest()
		"anvil":
			_anvil()
		"map":
			_map()
		"journal":
			_journal()
		"travel":
			_travel()


func _close_hint(text: String) -> void:
	_box.add_child(_button("Back", Callable(game, "resume"), Vector2(200, 38), 16))
	_box.add_child(_centered(_label(text, 13, DIM)))


# --- Item widgets ---------------------------------------------------------------------------

# Two short lines for a slot: what it is, and how many or what kind.
func _short(item: Dictionary) -> String:
	if Goods.is_good(item):
		return "%s\n×%d" % [Goods.LIST[item["id"]]["name"], item["count"]]
	if Goods.is_treasure(item):
		var words: PackedStringArray = String(Treasures.LIST[item["id"]]["name"]).split(" ")
		return "%s\ntreasure" % words[words.size() - 1]
	if Goods.is_scroll(item):
		return "%s\nscroll" % Items.AFFIXES[item["id"]]["scroll"]
	var top: String = Items.LEGENDS[item["legend"]]["name"] if item["legend"] != "" else Items.MATERIALS[item["tier"]]
	return "%s\n%s" % [top, Items.KIND_NAMES[item["kind"]]]


func _item_button(item: Dictionary, selected: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 56)
	b.text = _short(item)
	b.add_theme_font_size_override("font_size", 13)
	var c := Goods.color(item)
	b.add_theme_stylebox_override("normal", _style(Color(0.09, 0.075, 0.06, 0.95), c if selected else c.darkened(0.35), 3 if selected else 2))
	b.add_theme_stylebox_override("hover", _style(Color(0.18, 0.14, 0.1, 0.95), c, 3))
	b.add_theme_stylebox_override("pressed", _style(Color(0.18, 0.14, 0.1, 0.95), c, 3))
	b.add_theme_stylebox_override("disabled", _style(Color(0.07, 0.06, 0.05, 0.8), Color(0.22, 0.2, 0.18)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", c)
	b.add_theme_color_override("font_disabled_color", c.darkened(0.55))
	b.pressed.connect(on_press)
	b.mouse_entered.connect(_show_details.bind(item))
	b.mouse_exited.connect(_show_selected_details)
	return b


func _empty_slot(text := "") -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(96, 56)
	p.add_theme_stylebox_override("panel", _style(Color(0.06, 0.05, 0.04, 0.7), Color(0.22, 0.2, 0.18)))
	if text != "":
		var l := _centered(_label(text, 12, Color(0.45, 0.42, 0.4)))
		l.size = Vector2(96, 56)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	return p


# A grid of slots. With `gear_only`, anything that isn't gear is shown but can't be picked.
func _grid(items: Array, slots: int, where: String, gear_only := false) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in maxi(slots, items.size()):
		if i < items.size():
			var sel: bool = _selected.get("where", "") == where and _selected.get("index", -1) == i
			var b := _item_button(items[i], sel, _select.bind(where, i))
			b.disabled = gear_only and not Goods.is_gear(items[i])
			grid.add_child(b)
		else:
			grid.add_child(_empty_slot())
	return grid


func _select(where: String, index) -> void:
	_selected = {"where": where, "index": index}
	refresh()


func _selected_item() -> Dictionary:
	match _selected.get("where", ""):
		"bag":
			var i: int = _selected["index"]
			return game.bag[i] if i < game.bag.size() else {}
		"equipped":
			return game.equipped[_selected["index"]]
		"chest":
			var items: Array = _data["items"]
			var i: int = _selected["index"]
			return items[i] if i < items.size() else {}
	return {}


func _show_details(item: Dictionary) -> void:
	if _details == null or not is_instance_valid(_details):
		return
	_clear(_details)
	if item.is_empty():
		_details.add_child(_wrapped(_label("Point at something to see what it is. Click it to pick it.", 14, DIM), 300))
		return
	var c := Goods.color(item)
	_details.add_child(_wrapped(_label(Goods.title(item), 24, c), 300))
	if Goods.is_good(item):
		var def: Dictionary = Goods.LIST[item["id"]]
		_details.add_child(_label("×%d  ·  %d coins each" % [item["count"], def["value"]], 14, c.darkened(0.1)))
		_details.add_child(_wrapped(_label(def["text"], 14), 300))
		_details.add_child(_label("Sells for %s coins at the workbench" % thousands(Goods.worth(item)), 12, DIM))
		return
	if Goods.is_treasure(item):
		var info: Dictionary = Treasures.LIST[item["id"]]
		_details.add_child(_label("%s treasure" % Treasures.RARITY_NAMES[info["rarity"]], 14, c.darkened(0.1)))
		_details.add_child(_wrapped(_label(info["text"], 14), 300))
		_details.add_child(_label("Sells for %s coins at the workbench" % thousands(Goods.worth(item)), 12, DIM))
		return
	if Goods.is_scroll(item):
		var known := int(game.learned.get(item["id"], 0))
		_details.add_child(_wrapped(_label("Teaches: %s" % Goods.scroll_text(item), 15, Color(0.6, 0.8, 1.0)), 300))
		_details.add_child(_wrapped(_label("Read it to learn it for good, then inscribe it on your gear at the forge. It never turns up on gear by chance.", 13), 300))
		if known > 0:
			_details.add_child(_wrapped(_label("You already know it: %s" % Items.affix_text({"id": item["id"], "value": known}), 13, GOOD if known >= int(item["value"]) else DIM), 300))
		_details.add_child(_label("Sells for %s coins at the workbench" % thousands(Goods.worth(item)), 12, DIM))
		return
	_details.add_child(_label(Items.subtitle(item), 14, c.darkened(0.1)))
	for line in Items.stat_lines(item):
		_details.add_child(_wrapped(_label(line, 14), 300))
	for a: Dictionary in item["affixes"]:
		_details.add_child(_wrapped(_label("•  " + Items.affix_text(a), 14, Color(0.6, 0.8, 1.0)), 300))
	var ins: Dictionary = item.get("inscription", {})
	if not ins.is_empty():
		_details.add_child(_wrapped(_label("✎  " + Items.affix_text(ins) + " (inscribed)", 14, Goods.SCROLL_COLOR), 300))
	if item["legend"] != "":
		var legend: Dictionary = Items.LEGENDS[item["legend"]]
		_details.add_child(_wrapped(_label("★  %s: %s" % [legend["name"], legend["text"]], 14, Color(1.0, 0.65, 0.2)), 300))
	_details.add_child(_label("Worth %d coins broken down" % Items.salvage_value(item), 12, DIM))


func _show_selected_details() -> void:
	_show_details(_selected_item())


func _details_column() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(310, 300)
	column.add_theme_constant_override("separation", 8)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 4)
	column.add_child(_details)
	_show_selected_details()
	return column


func _pack_title() -> String:
	return "Your pack  (%d / %d)" % [game.bag.size(), game.pack_slots()]


# --- Your pack -----------------------------------------------------------------------------

func _inventory() -> void:
	_open("Your pack")
	_box.add_child(_centered(_label("Coins: %s" % thousands(game.coins), 18, GOLD)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_box.add_child(row)
	var worn := _column("Equipped")
	for kind: String in Items.KINDS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name := _label(Items.KIND_NAMES[kind], 14, DIM)
		name.custom_minimum_size = Vector2(62, 0)
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(name)
		var item: Dictionary = game.equipped[kind]
		if item.is_empty():
			line.add_child(_empty_slot("none"))
		else:
			var sel: bool = _selected.get("where", "") == "equipped" and _selected.get("index", "") == kind
			line.add_child(_item_button(item, sel, _select.bind("equipped", kind)))
		worn.add_child(line)
	row.add_child(worn)
	var pack := _column("Carrying  (%d / %d slots)" % [game.bag.size(), game.pack_slots()])
	pack.add_child(_grid(game.bag, game.pack_slots(), "bag"))
	pack.add_child(_wrapped(_label("Ore, gems and bars stack up to %d in a slot. Sell what you find at the workbench, or smelt it at the forge. Read scrolls to learn what they teach." % Goods.STACK, 12, DIM), 400))
	row.add_child(pack)
	var details := _details_column()
	row.add_child(details)
	var where: String = _selected.get("where", "")
	var selected := _selected_item()
	if where == "bag" and not selected.is_empty() and Goods.is_gear(selected):
		details.add_child(_button("Equip", Callable(self, "_equip_selected"), Vector2(160, 36), 16))
	elif where == "bag" and not selected.is_empty() and Goods.is_scroll(selected):
		var b := _button("Read it", Callable(self, "_read_selected"), Vector2(160, 36), 16)
		b.disabled = int(game.learned.get(selected["id"], 0)) >= int(selected["value"])
		details.add_child(b)
	elif where == "equipped" and _selected["index"] != "pickaxe" and not selected.is_empty():
		details.add_child(_button("Put in pack", Callable(self, "_unequip_selected"), Vector2(160, 36), 16))
	# Supplies and furniture waiting to be placed.
	var supplies := "Dynamite: %d   ·   Blasting charges: %d" % [game.supplies["dynamite"], game.supplies["charge"]]
	_box.add_child(_centered(_label(supplies, 15)))
	if not game.unplaced.is_empty():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_child(_label("Furniture to place:", 15, GOLD))
		var seen := {}
		for type: String in game.unplaced:
			seen[type] = int(seen.get(type, 0)) + 1
		for type: String in seen:
			var text: String = Catalog.FURNITURE[type]["name"] + (" ×%d" % seen[type] if seen[type] > 1 else "")
			line.add_child(_button(text, Callable(game, "start_placing").bind(type), Vector2(0, 32), 14))
		_box.add_child(line)
	_close_hint("I or Esc to close")


func _equip_selected() -> void:
	var i: int = _selected["index"]
	_selected = {}
	game.equip(i)


func _unequip_selected() -> void:
	var kind: String = _selected["index"]
	_selected = {}
	game.unequip(kind)


func _read_selected() -> void:
	var i: int = _selected["index"]
	_selected = {}
	game.learn_scroll(i)


# --- Chests ----------------------------------------------------------------------------------

func _chest() -> void:
	var data: Dictionary = _data
	var items: Array = data["items"]
	var loot: bool = data["loot"]
	_open(data["title"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_box.add_child(row)
	var inside := _column("Inside" if loot else "Stored  (%d / %d)" % [items.size(), data["slots"]])
	if items.is_empty() and loot:
		inside.add_child(_label("Empty.", 15, DIM))
	else:
		inside.add_child(_grid(items, 0 if loot else int(data["slots"]), "chest"))
	row.add_child(inside)
	var pack := _column(_pack_title())
	pack.add_child(_grid(game.bag, game.pack_slots(), "bag"))
	row.add_child(pack)
	var details := _details_column()
	row.add_child(details)
	var where: String = _selected.get("where", "")
	if where == "chest" and not _selected_item().is_empty():
		details.add_child(_button("Take", Callable(self, "_take_selected"), Vector2(160, 36), 16))
	elif where == "bag" and not loot and not _selected_item().is_empty():
		details.add_child(_button("Store", Callable(self, "_store_selected"), Vector2(160, 36), 16))
	if not items.is_empty():
		details.add_child(_button("Take everything", Callable(game, "take_all").bind(items), Vector2(200, 36), 16))
	if not loot:
		var finds := 0
		for item: Dictionary in game.bag:
			if not Goods.is_gear(item):
				finds += 1
		if finds > 0:
			details.add_child(_button("Store all your finds", Callable(game, "store_finds").bind(items, int(data["slots"])), Vector2(200, 36), 16))
	_close_hint("E or Esc to close")


func _take_selected() -> void:
	var i: int = _selected["index"]
	_selected = {}
	game.take_item(_data["items"], i)


func _store_selected() -> void:
	var i: int = _selected["index"]
	_selected = {}
	game.store_item(_data["items"], int(_data["slots"]), i)


# --- The anvil ---------------------------------------------------------------------------------

func _anvil() -> void:
	_open("Anvil")
	_box.add_child(_centered(_label("Coins: %s" % thousands(game.coins), 18, GOLD)))
	_box.add_child(_centered(_label("Reforging swaps one affix for a different random one; the price goes up each time. Breaking gear down turns it into coins.", 14, DIM)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_box.add_child(row)
	var worn := _column("Equipped")
	var worn_grid := GridContainer.new()
	worn_grid.columns = 3
	worn_grid.add_theme_constant_override("h_separation", 6)
	worn_grid.add_theme_constant_override("v_separation", 6)
	for kind: String in Items.KINDS:
		var item: Dictionary = game.equipped[kind]
		if not item.is_empty():
			var sel: bool = _selected.get("where", "") == "equipped" and _selected.get("index", "") == kind
			worn_grid.add_child(_item_button(item, sel, _select.bind("equipped", kind)))
	worn.add_child(worn_grid)
	row.add_child(worn)
	var pack := _column("Pack")
	pack.add_child(_grid(game.bag, game.pack_slots(), "bag", true))
	row.add_child(pack)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(330, 300)
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)
	_details = null
	var item := _selected_item()
	if item.is_empty() or not Goods.is_gear(item):
		column.add_child(_wrapped(_label("Pick a piece of gear to work on.", 15, DIM), 320))
	else:
		var c := Items.color(item)
		column.add_child(_wrapped(_label(Items.title(item), 24, c), 320))
		column.add_child(_label(Items.subtitle(item), 14, c.darkened(0.1)))
		for line in Items.stat_lines(item):
			column.add_child(_wrapped(_label(line, 14), 320))
		var cost := Items.reforge_cost(item)
		var affixes: Array = item["affixes"]
		if affixes.is_empty():
			column.add_child(_wrapped(_label("Common gear has no affixes to reforge.", 14, DIM), 320))
		for k in affixes.size():
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			var text := _wrapped(_label("•  " + Items.affix_text(affixes[k]), 14, Color(0.6, 0.8, 1.0)), 190)
			text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.add_child(text)
			var b := _button("Reforge: %s" % thousands(cost), Callable(game, "reforge").bind(item, k), Vector2(130, 30), 13)
			b.disabled = game.coins < cost
			line.add_child(b)
			column.add_child(line)
		if item["legend"] != "":
			var legend: Dictionary = Items.LEGENDS[item["legend"]]
			column.add_child(_wrapped(_label("★  %s: %s (can't be reforged)" % [legend["name"], legend["text"]], 14, Color(1.0, 0.65, 0.2)), 320))
		var ins: Dictionary = item.get("inscription", {})
		if not ins.is_empty():
			column.add_child(_wrapped(_label("✎  %s (inscribed at the forge)" % Items.affix_text(ins), 14, Goods.SCROLL_COLOR), 320))
		if _selected.get("where", "") == "bag":
			column.add_child(_gap(6))
			column.add_child(_button("Break down for %d coins" % Items.salvage_value(item), Callable(self, "_salvage_selected"), Vector2(240, 34), 15))
	_close_hint("E or Esc to close")


func _salvage_selected() -> void:
	var i: int = _selected["index"]
	_selected = {}
	game.salvage(i)


# --- The forge -----------------------------------------------------------------------------------

func _forge() -> void:
	_open("Forge")
	_box.add_child(_centered(_wrapped(_label("Smelting burns coal to turn ore into bars. Bars, gems and coins improve a piece of your gear a step: it keeps its rarity and affixes, and digs harder rock or hits harder. Wooden gear can't be improved. Affixes you've learned from scrolls are inscribed here too. Everything comes out of your pack.", 14, DIM), 1000)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(row)
	var left := _column("Smelt")
	row.add_child(left)
	var smelt := _scroll_list(left, Vector2(330, 400))
	for k in Goods.SMELT.size():
		var recipe: Dictionary = Goods.SMELT[k]
		var out: String = recipe["out"]
		var can: int = Goods.times(game.bag, recipe["in"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(Goods.LIST[out]["name"], 15, Goods.LIST[out]["color"]))
		info.add_child(_wrapped(_label("%s  ·  enough for %d" % [Goods.needs_text(recipe["in"]), can], 11, DIM if can > 0 else BAD), 190))
		line.add_child(info)
		var one := _button("Smelt", Callable(game, "smelt").bind(k, 1), Vector2(62, 30), 13)
		one.disabled = can <= 0
		one.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(one)
		var all := _button("All", Callable(game, "smelt").bind(k, can), Vector2(44, 30), 13)
		all.disabled = can <= 1
		all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(all)
		smelt.add_child(line)
	# Your gear, to pick one to work on.
	var middle := _column("Your gear")
	var worn := GridContainer.new()
	worn.columns = 2
	worn.add_theme_constant_override("h_separation", 6)
	worn.add_theme_constant_override("v_separation", 6)
	for kind: String in Items.KINDS:
		var item: Dictionary = game.equipped[kind]
		if not item.is_empty():
			var sel: bool = _selected.get("where", "") == "equipped" and _selected.get("index", "") == kind
			worn.add_child(_item_button(item, sel, _select.bind("equipped", kind)))
	middle.add_child(_label("Equipped", 13, DIM))
	middle.add_child(worn)
	middle.add_child(_label("In your pack", 13, DIM))
	var pack := GridContainer.new()
	pack.columns = 2
	pack.add_theme_constant_override("h_separation", 6)
	pack.add_theme_constant_override("v_separation", 6)
	for i in game.bag.size():
		var item: Dictionary = game.bag[i]
		if Goods.is_gear(item):
			var sel: bool = _selected.get("where", "") == "bag" and _selected.get("index", -1) == i
			pack.add_child(_item_button(item, sel, _select.bind("bag", i)))
	middle.add_child(pack)
	row.add_child(middle)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 400)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	_details = null
	var item := _selected_item()
	if item.is_empty() or not Goods.is_gear(item):
		right.add_child(_wrapped(_label("Pick a piece of gear to improve or inscribe.", 15, DIM), 370))
	else:
		_forge_item(right, item)
	_box.add_child(_centered(_wrapped(_label(_carrying_text(), 13, TEXT), 1000)))
	_close_hint("E or Esc to close")


func _forge_item(column: VBoxContainer, item: Dictionary) -> void:
	var c := Items.color(item)
	column.add_child(_wrapped(_label(Items.title(item), 24, c), 370))
	column.add_child(_label(Items.subtitle(item), 14, c.darkened(0.1)))
	for line in Items.stat_lines(item):
		column.add_child(_wrapped(_label(line, 13), 370))
	column.add_child(_gap(4))
	var tier: int = item["tier"]
	if Items.can_upgrade(item):
		var cost: Dictionary = Goods.UPGRADES[tier + 1]
		var better: Dictionary = item.duplicate(true)
		better["tier"] = tier + 1
		var ok: bool = game.coins >= int(cost["coins"]) and Goods.times(game.bag, cost["in"]) >= 1
		column.add_child(_label("Improve to %s" % Items.MATERIALS[tier + 1].to_lower(), 18, Items.TIER_COLORS[tier + 1].lightened(0.2)))
		column.add_child(_wrapped(_label("  ·  ".join(Items.stat_lines(better).slice(0, 2)), 12, DIM), 370))
		column.add_child(_wrapped(_label("Takes %s + %s coins" % [Goods.needs_text(cost["in"]), thousands(int(cost["coins"]))], 13, TEXT if ok else BAD), 370))
		var b := _button("Improve", Callable(game, "upgrade_gear").bind(item), Vector2(140, 34), 15)
		b.disabled = not ok
		column.add_child(b)
	elif tier == 0:
		column.add_child(_wrapped(_label("Wood can't be improved. Metal gear turns up in the chests of hidden rooms.", 13, DIM), 370))
	else:
		column.add_child(_wrapped(_label("Starmetal: as good as gear gets.", 13, GOOD), 370))
	column.add_child(_gap(6))
	column.add_child(_label("Inscription", 18, Goods.SCROLL_COLOR))
	var ins: Dictionary = item.get("inscription", {})
	column.add_child(_wrapped(_label("Now: " + (Items.affix_text(ins) if not ins.is_empty() else "nothing"), 13, Goods.SCROLL_COLOR if not ins.is_empty() else DIM), 370))
	var cost := Items.inscribe_cost(item)
	var any := false
	for id: String in Items.SCROLL_AFFIXES:
		if not game.learned.has(id) or not Items.fits_affix(item, id):
			continue
		any = true
		var a := {"id": id, "value": game.learned[id]}
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var text := _wrapped(_label(Items.affix_text(a), 13, Color(0.6, 0.8, 1.0)), 220)
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(text)
		var b := _button("Inscribe: %s" % thousands(cost), Callable(game, "inscribe").bind(item, id), Vector2(140, 30), 13)
		b.disabled = game.coins < cost or (ins.get("id", "") == id and int(ins.get("value", 0)) >= int(a["value"]))
		line.add_child(b)
		column.add_child(line)
	if not any:
		column.add_child(_wrapped(_label("Read scrolls from hidden rooms to learn affixes you can inscribe on this.", 13, DIM), 370))


# "In your pack: Coal 12  ·  Iron ore 30  ·  ..."
func _carrying_text() -> String:
	var parts: Array[String] = []
	for id: String in Goods.LIST:
		var n := Goods.count(game.bag, id)
		if n > 0:
			parts.append("%s %d" % [Goods.LIST[id]["name"], n])
	return "In your pack: " + ("  ·  ".join(parts) if not parts.is_empty() else "no ore or bars") + "  ·  Coins: %s" % thousands(game.coins)


# --- Checkpoints -----------------------------------------------------------------------------------

# Where a waystone (or the rope lift at home) can take you: home, and every checkpoint you've
# unlocked, shallowest first.
func _travel() -> void:
	var here: String = _data.get("here", "home") if _data is Dictionary else "home"
	_open("Checkpoints")
	_box.add_child(_centered(_wrapped(_label("Travel home, or to any checkpoint you've unlocked. Checkpoints are the only way home from deep down, short of climbing.", 15, DIM), 760)))
	var list := _scroll_list(_box, Vector2(760, 380))
	if here != "home":
		list.add_child(_travel_row("Home", "Your house, the workbench and the forge", "home"))
	var ids: Array = game.checkpoints.keys()
	ids.sort_custom(func(a, b) -> bool: return float(game.checkpoints[a]["depth"]) < float(game.checkpoints[b]["depth"]))
	for id in ids:
		if id == here:
			continue
		var cp: Dictionary = game.checkpoints[id]
		list.add_child(_travel_row(cp["name"], "%s m down" % thousands(roundi(float(cp["depth"]))), id))
	if ids.is_empty() and here == "home":
		list.add_child(_wrapped(_label("You haven't unlocked any checkpoints yet. They're deep down, behind walls of ward stone nothing digs through, with a single way in.", 15), 740))
	_close_hint("E or Esc to close")


func _travel_row(title: String, text: String, id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(title, 18, Color(0.35, 1.0, 0.82) if id != "home" else GOLD))
	info.add_child(_label(text, 13, DIM))
	row.add_child(info)
	var go := _button("Go", Callable(game, "travel").bind(id), Vector2(100, 36), 16)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(go)
	return row


# --- The map table -------------------------------------------------------------------------------

func _map() -> void:
	_open("Map of the rooms around you")
	_box.add_child(_centered(_label("The hidden rooms within about 60 m of where you are, nearest first:", 15, DIM)))
	var list := _scroll_list(_box, Vector2(900, 440))
	var here: Vector3 = game.player.position
	var shown := 0
	for room: Dictionary in game.rooms_around():
		if shown >= 16:
			break
		shown += 1
		var id: String = room["id"]
		var center: Vector3 = room["center"]
		var to := Vector2(center.x - here.x, center.z - here.z)
		var heading := wrapf(atan2(to.x, -to.y), 0.0, TAU)
		var dir: String = COMPASS[int(round(heading / (TAU / 8.0))) % 8]
		var st: Dictionary = game.room_state.get(id, {})
		var status := "Sealed"
		var color := TEXT
		if room["type"] == "checkpoint":
			status = "Unlocked" if game.checkpoints.has(id) else "Its door is somewhere along its walls"
			color = GOOD if game.checkpoints.has(id) else TEXT
		elif room["type"] == "trial":
			status = "Visited" if st.get("seen", false) else "Its door is somewhere along its walls"
			color = GOOD if st.get("seen", false) else TEXT
		elif st.get("opened", false):
			var left: int = game.guards_left(id) if game.world.rooms.has(id) else -1
			status = "Broken into" if left != 0 or room["type"] != "fight" else "Cleared"
			if left > 0:
				status = "Broken into  ·  %d guard%s left" % [left, "" if left == 1 else "s"]
			color = GOOD if left == 0 else Color(1.0, 0.7, 0.45)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var name := _label(room["name"], 17, {"trial": Color(0.6, 0.85, 1.0), "checkpoint": Color(0.35, 1.0, 0.82), "treasure": GOLD}.get(room["type"], TEXT))
		name.custom_minimum_size = Vector2(150, 0)
		line.add_child(name)
		var where := _label("%s m down, %d m %s" % [thousands(roundi(float(room["depth"]))), roundi(to.length()), dir], 15)
		where.custom_minimum_size = Vector2(270, 0)
		line.add_child(where)
		var state := _label(status, 15, color)
		state.custom_minimum_size = Vector2(300, 0)
		line.add_child(state)
		if not st.get("opened", false):
			var tracking: bool = game.tracked.get("id", "") == id
			line.add_child(_button("Stop tracking" if tracking else "Track", Callable(self, "_track").bind({} if tracking else room), Vector2(130, 30), 14))
		list.add_child(line)
	if shown == 0:
		list.add_child(_label("None near here. Dig a little further out and look again.", 15))
	_box.add_child(_centered(_label("Tracking a room shows the way to it at the top of your screen.", 13, DIM)))
	_close_hint("E or Esc to close")


func _track(room: Dictionary) -> void:
	game.track(room)
	refresh()


# --- The journal ---------------------------------------------------------------------------------

func _journal() -> void:
	_open("Journal", 30)
	var list := _scroll_list(_box, Vector2(920, 560))
	list.add_child(_centered(_label("Treasures  ·  %d found in all  ·  the deepest you've been: %s m" % [game.found_count(), thousands(roundi(game.deepest))], 17, GOLD)))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 10)
	list.add_child(grid)
	for t in Treasures.LIST.size():
		var info: Dictionary = Treasures.LIST[t]
		var n: int = game.found.get(t, 0)
		var rarity: int = info["rarity"]
		var color: Color = Treasures.RARITY_COLORS[rarity]
		var depth: Array = info["depth"]
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		entry.add_child(_label("%s  ×%d" % [info["name"], n] if n > 0 else "? ? ?", 16, color if n > 0 else DIM))
		entry.add_child(_label("%s  ·  from %s coins" % [Treasures.RARITY_NAMES[rarity], thousands(info["value"])], 13, color.darkened(0.15)))
		var text: String = info["text"] if n > 0 else "Only deep down: from %s m." % thousands(int(depth[0]))
		entry.add_child(_wrapped(_label(text, 13, Color(0.82, 0.8, 0.75)), 280))
		grid.add_child(entry)
	list.add_child(_gap(6))
	list.add_child(_centered(_label("Scrolls  ·  read them to learn an affix, then inscribe it at the forge", 17, Goods.SCROLL_COLOR)))
	var scrolls := GridContainer.new()
	scrolls.columns = 3
	scrolls.add_theme_constant_override("h_separation", 22)
	scrolls.add_theme_constant_override("v_separation", 8)
	list.add_child(scrolls)
	for id: String in Items.SCROLL_AFFIXES:
		var def: Dictionary = Items.AFFIXES[id]
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		var known: bool = game.learned.has(id)
		entry.add_child(_label("Scroll of %s" % def["scroll"] if known else "? ? ?", 16, Goods.SCROLL_COLOR if known else DIM))
		var kinds: Array = []
		for kind: String in def["kinds"]:
			kinds.append(Items.KIND_NAMES[kind].to_lower() + "s")
		entry.add_child(_wrapped(_label(Items.affix_text({"id": id, "value": game.learned[id]}) if known else "Found in the chests of hidden rooms.", 13, Color(0.82, 0.8, 0.75)), 280))
		entry.add_child(_label("For %s" % ", ".join(kinds), 12, DIM))
		scrolls.add_child(entry)
	list.add_child(_gap(6))
	list.add_child(_centered(_label("Ores and gems  ·  the deeper, the better", 17, GOLD)))
	var ores := GridContainer.new()
	ores.columns = 4
	ores.add_theme_constant_override("h_separation", 22)
	ores.add_theme_constant_override("v_separation", 10)
	list.add_child(ores)
	for id: String in Goods.ore_ids():
		var def: Dictionary = Goods.LIST[id]
		var n: int = game.mined.get(id, 0)
		var depth := Goods.depth_of(id)
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		entry.add_child(_label(def["name"], 16, def["color"] if n > 0 else DIM))
		entry.add_child(_label("%d coins each  ·  %s to %s m" % [def["value"], thousands(int(depth[0])), thousands(int(depth[1]))], 12, Color(0.82, 0.8, 0.75)))
		var tier := Goods.tier_needed(id)
		var dug := "Dug out: %s" % thousands(n) if n > 0 else "Not found yet"
		entry.add_child(_label("%s  ·  %s pickaxe" % [dug, Items.MATERIALS[tier]], 12, DIM))
		ores.add_child(entry)
	list.add_child(_gap(6))
	list.add_child(_centered(_label("The bands of rock  ·  each needs a better pickaxe than the last", 17, GOLD)))
	var bands := GridContainer.new()
	bands.columns = 4
	bands.add_theme_constant_override("h_separation", 22)
	bands.add_theme_constant_override("v_separation", 6)
	list.add_child(bands)
	for k in Blocks.BAND_ROCK.size():
		var rock: int = Blocks.BAND_ROCK[k]
		var reached: bool = game.deepest >= float(Blocks.BANDS[k])
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 0)
		entry.add_child(_label(Blocks.NAMES[rock] if reached else "? ? ?", 15, Blocks.COLORS[rock].lightened(0.45) if reached else DIM))
		entry.add_child(_label("%s to %s m  ·  %s pickaxe" % [thousands(int(Blocks.BANDS[k])), thousands(int(Blocks.BANDS[k + 1])), Items.MATERIALS[Blocks.TIER[rock]]], 12, DIM))
		bands.add_child(entry)
	_close_hint("Tab or Esc to close")


# --- The workbench ------------------------------------------------------------------------------

func _shop() -> void:
	_open("Workbench")
	_box.add_child(_centered(_label("Coins: %s" % thousands(game.coins), 20, GOLD)))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	for tab: Array in SHOP_TABS:
		var b := _button(tab[1], Callable(self, "_shop_switch").bind(tab[0]), Vector2(122, 36), 16)
		if tab[0] == _shop_tab:
			b.add_theme_stylebox_override("normal", _style(Color(0.34, 0.25, 0.12, 0.95), GOLD, 3))
			b.add_theme_color_override("font_color", GOLD)
		tabs.add_child(b)
	_box.add_child(tabs)
	var list := _scroll_list(_box, Vector2(820, 430))
	match _shop_tab:
		"sell":
			_shop_sell(list)
		"gear":
			_shop_gear(list)
		"supplies":
			_shop_supplies(list)
		"workshop":
			_shop_workshop(list)
		"house":
			_shop_house(list)
		"furniture":
			_shop_furniture(list)
	_close_hint("E or Esc to close")


func _shop_switch(tab: String) -> void:
	_shop_tab = tab
	refresh()


func _has_sellables() -> bool:
	for item: Dictionary in game.bag:
		if Goods.worth(item) > 0:
			return true
	return false


func _row(title: String, text: String, cost: int, action: Callable, verb: String, title_color := TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(title, 16, title_color))
	info.add_child(_wrapped(_label(text, 12, DIM), 520))
	row.add_child(info)
	if cost < 0:
		var done := _label(verb, 15, GOOD)
		done.custom_minimum_size = Vector2(212, 0)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(done)
		return row
	var affordable: bool = game.coins >= cost
	var price := _label("%s coins" % thousands(cost), 14, GOLD if affordable else BAD)
	price.custom_minimum_size = Vector2(100, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(price)
	var button := _button(verb, action, Vector2(100, 34), 15)
	button.disabled = not affordable
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(button)
	return row


func _heading(list: VBoxContainer, text: String, note := "") -> void:
	list.add_child(_gap(4))
	list.add_child(_label(text, 20, GOLD))
	if note != "":
		list.add_child(_wrapped(_label(note, 13, DIM), 780))


# Everything in your pack the workbench will buy, a stack at a time or all of a sort at once.
func _shop_sell(list: VBoxContainer) -> void:
	list.add_child(_wrapped(_label("The workbench buys everything you dig up or smelt, treasure and scrolls. Bars are worth more than the ore they're made from, and they improve your gear at the forge.", 14, DIM), 780))
	var totals := {"ore": 0, "bar": 0, "treasure": 0, "scroll": 0}
	for item: Dictionary in game.bag:
		var sort := Goods.sort_of(item)
		if totals.has(sort):
			totals[sort] = int(totals[sort]) + Goods.worth(item)
	if int(totals["ore"]) + int(totals["bar"]) + int(totals["treasure"]) + int(totals["scroll"]) <= 0:
		list.add_child(_gap(8))
		list.add_child(_label("Nothing to sell. Bring home ore, gems, bars or treasure in your pack.", 15, TEXT))
		return
	var all := HBoxContainer.new()
	all.add_theme_constant_override("separation", 8)
	for pair: Array in [["ore", "Sell all ore and gems"], ["bar", "Sell all bars"], ["treasure", "Sell all treasure"]]:
		if int(totals[pair[0]]) > 0:
			all.add_child(_button("%s: %s" % [pair[1], thousands(totals[pair[0]])], Callable(game, "sell_all").bind(pair[0]), Vector2(0, 34), 14))
	list.add_child(all)
	for i in game.bag.size():
		var item: Dictionary = game.bag[i]
		var value := Goods.worth(item)
		if value <= 0:
			continue
		var each := ""
		if Goods.is_good(item):
			each = "×%d  ·  %d coins each" % [item["count"], Goods.LIST[item["id"]]["value"]]
		elif Goods.is_scroll(item):
			each = "Scroll  ·  teaches %s%s" % [Goods.scroll_text(item), "  ·  you know it already" if int(game.learned.get(item["id"], 0)) >= int(item["value"]) else "  ·  read it first?"]
		else:
			each = "%s treasure" % Treasures.RARITY_NAMES[Treasures.LIST[item["id"]]["rarity"]]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(Goods.title(item), 16, Goods.color(item)))
		info.add_child(_label(each, 12, DIM))
		row.add_child(info)
		var price := _label("%s coins" % thousands(value), 14, GOLD)
		price.custom_minimum_size = Vector2(100, 0)
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(price)
		var button := _button("Sell", Callable(game, "sell").bind(i), Vector2(100, 34), 15)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
		list.add_child(row)


func _shop_gear(list: VBoxContainer) -> void:
	list.add_child(_wrapped(_label("Wooden gear, to get you started. Metal tools and weapons, with their affixes, turn up in the chests of hidden rooms, and the forge improves them. Wood can't be improved.", 14, DIM), 780))
	for kind: String in Catalog.GEAR_PRICES:
		var have: Dictionary = game.equipped[kind]
		_heading(list, Items.KIND_NAMES[kind] + "s", "Equipped: %s" % (Items.title(have) + " (" + Items.RARITY_NAMES[have["rarity"]].to_lower() + ")" if not have.is_empty() else "nothing"))
		var sample := Items.make(kind, 0, 0, RandomNumberGenerator.new())
		list.add_child(_row(Items.base_name(sample), "  ·  ".join(Items.stat_lines(sample).slice(0, 1)), Catalog.GEAR_PRICES[kind], Callable(game, "buy_gear").bind(kind), "Buy", Items.TIER_COLORS[0].lightened(0.2)))


func _shop_supplies(list: VBoxContainer) -> void:
	for s: Dictionary in Catalog.SUPPLIES:
		var have: int = game.supplies[s["id"]]
		var title: String = "%s ×%d" % [s["name"], s["amount"]] if int(s["amount"]) > 1 else String(s["name"])
		list.add_child(_row(title, "%s You have %d." % [s["text"], have], s["cost"], Callable(game, "buy_supply").bind(s["id"]), "Buy"))
	list.add_child(_wrapped(_label("Throw explosives with the explosives slot (4). Get clear: the blast hurts you too, and it shatters half the ore it breaks.", 13, DIM), 780))


func _shop_workshop(list: VBoxContainer) -> void:
	_heading(list, "Pack", "Ore, gems and bars stack up to %d in a slot; gear, treasure and scrolls take a slot each. A bigger pack means fewer trips home." % Goods.STACK)
	var packs: Array = Catalog.PACKS
	var pack: int = game.workshop["pack"]
	if pack + 1 < packs.size():
		list.add_child(_row(packs[pack + 1]["name"], "Now: %s, %d slots. Next: %d slots." % [packs[pack]["name"], packs[pack]["slots"], packs[pack + 1]["slots"]], packs[pack + 1]["cost"], Callable(game, "buy_workshop").bind("pack"), "Upgrade"))
	else:
		list.add_child(_row(packs[pack]["name"], "%d slots." % packs[pack]["slots"], -1, Callable(), "Maxed"))


func _shop_house(list: VBoxContainer) -> void:
	var tiers: Array = Catalog.HOUSE_TIERS
	var tier: int = game.house_tier
	_heading(list, "Bigger house", "Your house is a %s, %s A bigger house has more floor for furniture." % [String(tiers[tier]["name"]).to_lower(), tiers[tier]["text"]])
	if tier + 1 < tiers.size():
		list.add_child(_row(tiers[tier + 1]["name"], tiers[tier + 1]["text"], tiers[tier + 1]["cost"], Callable(game, "buy_house_tier"), "Build"))
	else:
		list.add_child(_row(tiers[tier]["name"], "As big as it gets.", -1, Callable(), "Built"))
	_heading(list, "Decorations")
	for item: Dictionary in Catalog.DECOR:
		var id: String = item["id"]
		if game.decor.has(id):
			list.add_child(_row(item["name"], item["text"], -1, Callable(), "Owned"))
		else:
			list.add_child(_row(item["name"], item["text"], item["cost"], Callable(game, "buy_decor").bind(id), "Buy"))


func _shop_furniture(list: VBoxContainer) -> void:
	list.add_child(_wrapped(_label("You place furniture yourself, anywhere on the floor of your house. G picks it up again to move it.", 14, DIM), 780))
	for type: String in Catalog.FURNITURE_ORDER:
		var def: Dictionary = Catalog.FURNITURE[type]
		var placed := 0
		for rec: Dictionary in game.furniture:
			if rec["type"] == type:
				placed += 1
		var owned: int = placed + game.unplaced.count(type)
		var text: String = def["text"] + ("  You have %d." % owned if owned > 0 else "")
		list.add_child(_row(def["name"], text, def["cost"], Callable(game, "buy_furniture").bind(type), "Buy"))
