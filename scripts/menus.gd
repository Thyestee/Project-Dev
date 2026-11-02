extends CanvasLayer
# The full-screen menus: loading, title, pause, the treasure journal, the workbench, your pack,
# chests, the anvil, the map table, and coming round after a knockout.

const Treasures := preload("res://scripts/treasures.gd")
const Items := preload("res://scripts/items.gd")
const Catalog := preload("res://scripts/catalog.gd")
const House := preload("res://scripts/house.gd")

const GOLD := Color(1.0, 0.84, 0.4)
const TEXT := Color(0.93, 0.91, 0.86)
const DIM := Color(0.75, 0.75, 0.75)
const GOOD := Color(0.55, 0.85, 0.5)
const BAD := Color(0.8, 0.5, 0.45)
const SHOP_TABS := [["gear", "Gear"], ["supplies", "Supplies"], ["workshop", "Workshop"], ["house", "House"], ["furniture", "Furniture"]]
const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
const CONTROLS := [
	"WASD move  ·  Space jump  ·  Shift sprint  ·  Ctrl crouch  ·  Mouse look",
	"1-6 or wheel: pickaxe, leveller, sword, mace, bow, explosives  ·  R changes the explosive",
	"Left click use  ·  Right click raises your shield  ·  You duck and crawl through tight gaps on your own",
	"E use or pick up  ·  G move furniture  ·  I pack  ·  Tab journal  ·  F detector  ·  Esc pause",
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
var _shop_tab := "gear"


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
		_show_simple("DEEP FINDS", ["Burying treasure..."], [])
		_loading_label = _box.get_child(1) as Label
	_loading_label.text = "Burying treasure... %d%%" % int(progress * 100.0)


func show_title(has_save: bool) -> void:
	var lines: Array = ["Somewhere under your house, lost treasures and hidden rooms are waiting.",
		"Take the stairs down and listen to your metal detector: the faster it beeps, the closer you are.",
		"Hidden rooms hold old chests full of gear, and guards who don't like visitors.", ""]
	lines.append_array(CONTROLS)
	var buttons: Array = [["Continue digging" if has_save else "Start digging", Callable(game, "start_playing")]]
	if has_save:
		lines.append("")
		lines.append("So far: %d treasures found, %s coins to spend, %d still buried here." % [game.found_count(), thousands(game.coins), game.world.remaining_treasures()])
		buttons.append(["New dig site", Callable(self, "_ask_new_world").bind("title")])
	_show_simple("DEEP FINDS", lines, buttons)


func show_pause() -> void:
	var lines: Array = [""]
	lines.append_array(CONTROLS)
	_show_simple("Paused", lines, [
		["Resume", Callable(game, "resume")],
		["Go home", Callable(game, "return_home")],
		["New dig site", Callable(self, "_ask_new_world").bind("paused")],
		["Save and quit", Callable(game, "save_and_quit")],
	])


func _ask_new_world(from: String) -> void:
	confirm_from = from
	game.ask_new_world()


func show_new_world_confirm() -> void:
	_show_simple("New dig site?", ["The ground is filled back in, with new treasure and new hidden rooms.", "Your coins, gear, house and journal stay with you."], [
		["Yes, new dig site", Callable(game, "new_world")],
		["Cancel", Callable(game, "cancel_new_world")],
	])


func show_dead() -> void:
	_show_simple("Knocked out!", ["Everything goes dark...", "You come round at home, a bit bruised. You keep everything you had.", "The guards you left standing are back on their feet."], [
		["Wake up", Callable(game, "wake_up")],
	])


# --- The menus you open while playing --------------------------------------------------------

func open(menu: String, data = null) -> void:
	current = menu
	_data = data
	_selected = {}
	refresh()


func refresh() -> void:
	match current:
		"shop":
			_shop()
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


func _close_hint(text: String) -> void:
	_box.add_child(_button("Back", Callable(game, "resume"), Vector2(200, 38), 16))
	_box.add_child(_centered(_label(text, 13, DIM)))


# --- Gear widgets ---------------------------------------------------------------------------

func _short(item: Dictionary) -> String:
	var top: String = Items.LEGENDS[item["legend"]]["name"] if item["legend"] != "" else Items.TIER_NAMES[item["kind"]][item["tier"]]
	return "%s\n%s" % [top, Items.KIND_NAMES[item["kind"]]]


func _item_button(item: Dictionary, selected: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 56)
	b.text = _short(item)
	b.add_theme_font_size_override("font_size", 13)
	var c := Items.color(item)
	b.add_theme_stylebox_override("normal", _style(Color(0.09, 0.075, 0.06, 0.95), c if selected else c.darkened(0.35), 3 if selected else 2))
	b.add_theme_stylebox_override("hover", _style(Color(0.18, 0.14, 0.1, 0.95), c, 3))
	b.add_theme_stylebox_override("pressed", _style(Color(0.18, 0.14, 0.1, 0.95), c, 3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", c)
	b.add_theme_color_override("font_hover_color", c.lightened(0.2))
	b.add_theme_color_override("font_pressed_color", c)
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


func _grid(items: Array, slots: int, where: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in maxi(slots, items.size()):
		if i < items.size():
			var sel: bool = _selected.get("where", "") == where and _selected.get("index", -1) == i
			grid.add_child(_item_button(items[i], sel, _select.bind(where, i)))
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
		_details.add_child(_wrapped(_label("Point at a piece of gear to see what it does. Click it to pick it.", 14, DIM), 300))
		return
	var c := Items.color(item)
	_details.add_child(_wrapped(_label(Items.title(item), 24, c), 300))
	_details.add_child(_label(Items.subtitle(item), 14, c.darkened(0.1)))
	for line in Items.stat_lines(item):
		_details.add_child(_wrapped(_label(line, 14), 300))
	for a: Dictionary in item["affixes"]:
		_details.add_child(_wrapped(_label("•  " + Items.affix_text(a), 14, Color(0.6, 0.8, 1.0)), 300))
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
	var pack := _column("Pack  (%d / %d)" % [game.bag.size(), game.BAG_SIZE])
	pack.add_child(_grid(game.bag, game.BAG_SIZE, "bag"))
	row.add_child(pack)
	var details := _details_column()
	row.add_child(details)
	var where: String = _selected.get("where", "")
	if where == "bag" and not _selected_item().is_empty():
		details.add_child(_button("Equip", Callable(self, "_equip_selected"), Vector2(160, 36), 16))
	elif where == "equipped" and _selected["index"] != "pickaxe" and not _selected_item().is_empty():
		details.add_child(_button("Put in pack", Callable(self, "_unequip_selected"), Vector2(160, 36), 16))
	# Supplies and furniture waiting to be placed.
	var supplies := "Arrows: %d   ·   Dynamite: %d   ·   Blasting charges: %d" % [game.supplies["arrows"], game.supplies["dynamite"], game.supplies["charge"]]
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
	var pack := _column("Your pack  (%d / %d)" % [game.bag.size(), game.BAG_SIZE])
	pack.add_child(_grid(game.bag, game.BAG_SIZE, "bag"))
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
	pack.add_child(_grid(game.bag, game.BAG_SIZE, "bag"))
	row.add_child(pack)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(330, 300)
	column.add_theme_constant_override("separation", 6)
	row.add_child(column)
	_details = null
	var item := _selected_item()
	if item.is_empty():
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
		if _selected.get("where", "") == "bag":
			column.add_child(_gap(6))
			column.add_child(_button("Break down for %d coins" % Items.salvage_value(item), Callable(self, "_salvage_selected"), Vector2(240, 34), 15))
	_close_hint("E or Esc to close")


func _salvage_selected() -> void:
	var i: int = _selected["index"]
	_selected = {}
	game.salvage(i)


# --- The map table -------------------------------------------------------------------------------

func _map() -> void:
	_open("Map of this dig site")
	_box.add_child(_centered(_label("The hidden rooms, measured from the top of the stairs:", 15, DIM)))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	_box.add_child(list)
	var door := Vector3(House.DOOR_X, House.FLOOR, House.Z0) * 0.125
	for v in game.world.vaults.size():
		var vault: Dictionary = game.world.vaults[v]
		var center: Vector3 = vault["center"]
		var to := Vector2(center.x - door.x, center.z - door.z)
		var heading := wrapf(atan2(to.x, -to.y), 0.0, TAU)
		var dir: String = COMPASS[int(round(heading / (TAU / 8.0))) % 8]
		var st: Dictionary = game.vault_state[v]
		var guards: int = game.enemies.alive_in_vault(v)
		var status := "Sealed"
		var color := TEXT
		if st["opened"]:
			status = "Cleared" if guards == 0 else "Broken into  ·  %d guard%s left" % [guards, "" if guards == 1 else "s"]
			color = GOOD if guards == 0 else Color(1.0, 0.7, 0.45)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		var name := _label("%s" % vault["name"], 17, GOLD if vault["throne"] else TEXT)
		name.custom_minimum_size = Vector2(130, 0)
		line.add_child(name)
		var where := _label("%d m down, %d m %s" % [roundi(float(vault["depth"])), roundi(to.length()), dir], 15)
		where.custom_minimum_size = Vector2(260, 0)
		line.add_child(where)
		var state := _label(status, 15, color)
		state.custom_minimum_size = Vector2(250, 0)
		line.add_child(state)
		if not st["opened"]:
			var tracking: bool = game.tracked == v
			line.add_child(_button("Stop tracking" if tracking else "Track", Callable(self, "_track").bind(-1 if tracking else v), Vector2(130, 30), 14))
		list.add_child(line)
	_box.add_child(_centered(_label("Tracking a room shows the way to it at the top of your screen.", 13, DIM)))
	_close_hint("E or Esc to close")


func _track(v: int) -> void:
	game.tracked = v
	refresh()


# --- The journal ---------------------------------------------------------------------------------

func _journal() -> void:
	_open("Treasure Journal", 30)
	var found_n: int = game.found_count()
	var buried: int = game.world.remaining_treasures()
	_box.add_child(_centered(_label("%d found in all  ·  %d still buried at this dig site" % [found_n, buried], 15)))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 12)
	_box.add_child(grid)
	for t in Treasures.LIST.size():
		var info: Dictionary = Treasures.LIST[t]
		var n: int = game.found.get(t, 0)
		var rarity: int = info["rarity"]
		var color: Color = Treasures.RARITY_COLORS[rarity]
		var depth: Array = info["depth"]
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)
		entry.add_child(_label("%s  ×%d" % [info["name"], n] if n > 0 else "? ? ?", 17, color if n > 0 else DIM))
		entry.add_child(_label("%s  ·  %s coins" % [Treasures.RARITY_NAMES[rarity], thousands(info["value"])], 13, color.darkened(0.15)))
		var text: String = info["text"] if n > 0 else "Usually %d to %d m down." % [depth[0], depth[1]]
		entry.add_child(_wrapped(_label(text, 13, Color(0.82, 0.8, 0.75)), 260))
		grid.add_child(entry)
	_close_hint("Tab or Esc to close")


# --- The workbench ------------------------------------------------------------------------------

func _shop() -> void:
	_open("Workbench")
	_box.add_child(_centered(_label("Coins: %s" % thousands(game.coins), 20, GOLD)))
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	for tab: Array in SHOP_TABS:
		var b := _button(tab[1], Callable(self, "_shop_switch").bind(tab[0]), Vector2(130, 36), 16)
		if tab[0] == _shop_tab:
			b.add_theme_stylebox_override("normal", _style(Color(0.34, 0.25, 0.12, 0.95), GOLD, 3))
			b.add_theme_color_override("font_color", GOLD)
		tabs.add_child(b)
	_box.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	match _shop_tab:
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


func _shop_gear(list: VBoxContainer) -> void:
	list.add_child(_wrapped(_label("Plain, common gear. Gear with better rarities and affixes only turns up in the chests of hidden rooms.", 14, DIM), 780))
	for kind: String in Items.KINDS:
		var have: Dictionary = game.equipped[kind]
		_heading(list, Items.KIND_NAMES[kind] + "s", "Equipped: %s" % (Items.title(have) + " (" + Items.RARITY_NAMES[have["rarity"]].to_lower() + ")" if not have.is_empty() else "nothing"))
		var prices: Array = Catalog.GEAR_PRICES[kind]
		for tier in prices.size():
			if int(prices[tier]) <= 0:
				continue
			var sample := Items.make(kind, tier, 0, RandomNumberGenerator.new())
			list.add_child(_row(Items.base_name(sample), "  ·  ".join(Items.stat_lines(sample)), prices[tier], Callable(game, "buy_gear").bind(kind, tier), "Buy", Items.TIER_COLORS[tier].lightened(0.2)))


func _shop_supplies(list: VBoxContainer) -> void:
	for s: Dictionary in Catalog.SUPPLIES:
		var have: int = game.supplies[s["id"]]
		var title: String = "%s ×%d" % [s["name"], s["amount"]] if int(s["amount"]) > 1 else String(s["name"])
		list.add_child(_row(title, "%s You have %d." % [s["text"], have], s["cost"], Callable(game, "buy_supply").bind(s["id"]), "Buy"))
	list.add_child(_wrapped(_label("Throw explosives with the explosives slot (6). Get clear: the blast hurts you too.", 13, DIM), 780))


func _shop_workshop(list: VBoxContainer) -> void:
	list.add_child(_wrapped(_label("Workshop upgrades work on every pickaxe you own, now and later.", 14, DIM), 780))
	var grips: Array = Catalog.GRIPS
	var grip: int = game.workshop["grip"]
	if grip + 1 < grips.size():
		list.add_child(_row(grips[grip + 1]["name"], "Now: %s, swings %.2fx as fast. Next: %.2fx." % [grips[grip]["name"], grips[grip]["speed"], grips[grip + 1]["speed"]], grips[grip + 1]["cost"], Callable(game, "buy_workshop").bind("grip"), "Upgrade"))
	else:
		list.add_child(_row(grips[grip]["name"], "Swings %.2fx as fast." % grips[grip]["speed"], -1, Callable(), "Maxed"))
	var sizes: Array = Catalog.SIZES
	var size: int = game.workshop["size"]
	if size + 1 < sizes.size():
		list.add_child(_row(sizes[size + 1]["name"], "Now: %s, every blow dents the ground %.1f m across, and the leveller flattens %.1f m squares. Next: %.1f m." % [sizes[size]["name"], sizes[size]["radius"] * 0.25, (6 + 2 * size) * 0.25, sizes[size + 1]["radius"] * 0.25], sizes[size + 1]["cost"], Callable(game, "buy_workshop").bind("size"), "Upgrade"))
	else:
		list.add_child(_row(sizes[size]["name"], "Every blow dents the ground %.1f m across." % (sizes[size]["radius"] * 0.25), -1, Callable(), "Maxed"))


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
