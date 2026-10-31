extends CanvasLayer
## Screen UI: day and trip timer, backpack, tool hotbar, hints, menus (door, forge,
## workbench, day summary), the build palette and screen fades.

const Data := preload("res://scripts/game_data.gd")
const Icons := preload("res://scripts/icons.gd")

const VIEW := Vector2(1280, 720)
const PANEL_COLOR := Color(0.08, 0.07, 0.06, 0.9)
const BORDER_COLOR := Color(0.55, 0.42, 0.25)
const TEXT_COLOR := Color(0.93, 0.9, 0.85)
const DIM_COLOR := Color(0.62, 0.58, 0.52)
const GOLD := Color(1.0, 0.84, 0.35)
const WARN := Color(1.0, 0.55, 0.45)
const GOOD := Color(0.6, 0.9, 0.6)

var game

var _day_label: Label
var _place_label: Label
var _clock_label: Label
var _inv_box: VBoxContainer
var _hotbar: HBoxContainer
var _tool_label: Label
var _hint: Label
var _toast: Label
var _toast_tween: Tween
var _menu: PanelContainer
var _menu_box: VBoxContainer
var _menu_kind := ""
var _menu_data := {}
var _build_panel: PanelContainer
var _build_box: HBoxContainer
var _fade: ColorRect


func _ready() -> void:
	_build_status()
	_build_backpack()
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 8)
	add_child(_hotbar)
	_tool_label = _make_label("", 15, TEXT_COLOR, true)
	_tool_label.position = Vector2(440, 612)
	_tool_label.size = Vector2(400, 24)
	add_child(_tool_label)
	_hint = _make_label("", 17, GOLD, true)
	_hint.position = Vector2(340, 580)
	_hint.size = Vector2(600, 26)
	add_child(_hint)
	_toast = _make_label("", 18, TEXT_COLOR, true)
	_toast.position = Vector2(290, 70)
	_toast.size = Vector2(700, 28)
	_toast.modulate.a = 0.0
	add_child(_toast)

	var help := _make_label("WASD move   Left click hit   1-2 / wheel switch tool   E interact   B build (at home)", 13, DIM_COLOR, true)
	help.position = Vector2(16, 694)
	add_child(help)

	_build_panel = _make_panel(Vector2.ZERO)
	var build_v := VBoxContainer.new()
	build_v.add_theme_constant_override("separation", 6)
	_build_panel.add_child(build_v)
	build_v.add_child(_make_label("BUILD   -   left click: place   right click: cancel / pick up   B: done", 13, DIM_COLOR))
	_build_box = HBoxContainer.new()
	_build_box.add_theme_constant_override("separation", 6)
	build_v.add_child(_build_box)
	_build_panel.hide()

	_menu = _make_panel(Vector2.ZERO)
	_menu.custom_minimum_size = Vector2(460, 0)
	_menu_box = VBoxContainer.new()
	_menu_box.add_theme_constant_override("separation", 8)
	_menu.add_child(_menu_box)
	_menu.hide()

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.size = VIEW
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


# --- Public API -----------------------------------------------------------------

func refresh() -> void:
	if game == null:
		return
	_day_label.text = "Day %d" % game.day
	_place_label.text = game.place_name()
	_rebuild_backpack()
	_rebuild_hotbar()
	if _menu.visible:
		_rebuild_menu()
	if _build_panel.visible:
		_rebuild_build()


func update_clock(seconds_left: float) -> void:
	if seconds_left < 0.0:
		_clock_label.hide()
		return
	_clock_label.show()
	var s := ceili(seconds_left)
	_clock_label.text = "%d:%02d" % [s / 60, s % 60]
	_clock_label.add_theme_color_override("font_color", WARN if seconds_left <= 60.0 else GOLD)


func show_message(text: String, color := TEXT_COLOR) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


func set_hint(text: String) -> void:
	_hint.text = text


func any_open() -> bool:
	return _menu.visible


func open_menu(kind: String, data := {}) -> void:
	_menu_kind = kind
	_menu_data = data
	_menu.show()
	_rebuild_menu()


func close_menus() -> void:
	_menu.hide()
	_menu_kind = ""


func set_build_mode(on: bool) -> void:
	_build_panel.visible = on
	if on:
		_rebuild_build()


## Fades to black, calls `mid`, fades back in, then calls `done`.
func fade(mid: Callable, done: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_callback(mid)
	tw.tween_interval(0.1)
	tw.tween_property(_fade, "color:a", 0.0, 0.35)
	tw.tween_callback(done)


# --- Builders -----------------------------------------------------------------------

func _make_panel(pos: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _make_label(text: String, font_size := 16, color := TEXT_COLOR, outline := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_constant_override("outline_size", 5)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


func _make_button(text: String, callback: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 15)
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(callback)
	return b


func _make_icon(id: String, s := 22.0) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(s, s)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_item_icon.bind(icon, id, s))
	return icon


func _draw_item_icon(icon: Control, id: String, s: float) -> void:
	Icons.draw_item(icon, id, icon.size / 2.0, s)


func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _build_status() -> void:
	var panel := _make_panel(Vector2(16, 16))
	panel.custom_minimum_size = Vector2(200, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	_day_label = _make_label("", 22, GOLD)
	box.add_child(_day_label)
	_place_label = _make_label("", 15, DIM_COLOR)
	box.add_child(_place_label)
	_clock_label = _make_label("", 30, GOLD)
	box.add_child(_clock_label)
	_clock_label.hide()


func _build_backpack() -> void:
	var panel := _make_panel(Vector2(1044, 16))
	panel.custom_minimum_size = Vector2(220, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	box.add_child(_make_label("BACKPACK", 13, BORDER_COLOR.lightened(0.3)))
	_inv_box = VBoxContainer.new()
	_inv_box.add_theme_constant_override("separation", 3)
	box.add_child(_inv_box)


func _rebuild_backpack() -> void:
	_clear(_inv_box)
	var any := false
	for id in Data.ITEM_ORDER:
		var n: int = game.count(id)
		if n <= 0:
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_icon(id))
		var name_label := _make_label(Data.ITEMS[id]["name"], 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(_make_label(str(n), 15, GOLD))
		_inv_box.add_child(row)
	if not any:
		_inv_box.add_child(_make_label("Empty", 14, DIM_COLOR))


func _rebuild_hotbar() -> void:
	_clear(_hotbar)
	for i in game.tools.size():
		var tool: Dictionary = Data.TOOLS[game.tools[i]]
		var slot := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_COLOR
		style.border_color = GOLD if i == game.equipped else BORDER_COLOR.darkened(0.3)
		style.set_border_width_all(3 if i == game.equipped else 2)
		style.set_corner_radius_all(6)
		slot.add_theme_stylebox_override("panel", style)
		slot.custom_minimum_size = Vector2(56, 56)
		slot.gui_input.connect(_on_slot_input.bind(i))
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(_draw_tool_icon.bind(icon, tool))
		slot.add_child(icon)
		var key := _make_label(str(i + 1), 12, DIM_COLOR)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(key)
		_hotbar.add_child(slot)
	var n: int = game.tools.size()
	_hotbar.position = Vector2(VIEW.x / 2.0 - (n * 64 - 8) / 2.0, 640)
	var current: Dictionary = game.equipped_tool()
	_tool_label.text = current.get("name", "")


func _draw_tool_icon(icon: Control, tool: Dictionary) -> void:
	Icons.draw_tool(icon, tool, icon.size / 2.0 + Vector2(-9, 9), -PI / 4.0, 22.0)


func _on_slot_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		game.equip(index)


func _rebuild_build() -> void:
	_clear(_build_box)
	for id in Data.BUILD_ORDER:
		var info: Dictionary = Data.BUILDABLES[id]
		var affordable: bool = game.has_items(info["cost"])
		var b := _make_button("%s\n%s" % [info["name"], Data.cost_text(info["cost"])],
			Callable(game, "select_build").bind(id), affordable or game.build_kind == id)
		b.toggle_mode = true
		b.button_pressed = game.build_kind == id
		b.custom_minimum_size = Vector2(118, 50)
		b.focus_mode = Control.FOCUS_NONE
		_build_box.add_child(b)
	_build_panel.reset_size()
	_build_panel.position = Vector2((VIEW.x - _build_panel.size.x) / 2.0, 500)


# --- Menus ------------------------------------------------------------------------------

func _rebuild_menu() -> void:
	_clear(_menu_box)
	match _menu_kind:
		"door":
			_menu_door()
		"forge":
			_menu_forge()
		"workbench":
			_menu_workbench()
		"summary":
			_menu_summary()
	_menu.reset_size()
	_menu.position = ((VIEW - _menu.get_combined_minimum_size()) / 2.0).floor()
	call_deferred("_recenter_menu")


func _recenter_menu() -> void:
	_menu.reset_size()
	_menu.position = ((VIEW - _menu.size) / 2.0).floor()


func _title(text: String) -> void:
	_menu_box.add_child(_make_label(text, 22, GOLD))


func _text(text: String, color := TEXT_COLOR, font_size := 15) -> void:
	var l := _make_label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(436, 0)
	_menu_box.add_child(l)


func _section(text: String) -> void:
	_menu_box.add_child(HSeparator.new())
	_menu_box.add_child(_make_label(text, 13, BORDER_COLOR.lightened(0.3)))


func _menu_door() -> void:
	_title("Day %d" % game.day)
	_text("Where are you heading today? A trip lasts 5 minutes, then you walk back home. Time stands still while you're inside.", DIM_COLOR)
	_menu_box.add_child(_make_button("The Forest   -   chop trees for wood", Callable(game, "start_run").bind("forest")))
	_menu_box.add_child(_make_button("The Mine   -   rocks, coal and ore veins", Callable(game, "start_run").bind("mine")))
	_menu_box.add_child(_make_button("Stay inside", close_menus))


func _menu_forge() -> void:
	_title("Forge")
	if game.forge_lit:
		_text("The fire is roaring. It goes out when you leave the house.", GOOD)
	else:
		_text("The forge is cold. Light it with coal to smelt ore and forge tools.", DIM_COLOR)
		_menu_box.add_child(_make_button("Light the forge  (%s)" % Data.cost_text(Data.FORGE_LIGHT_COST),
			Callable(game, "light_forge"), game.has_items(Data.FORGE_LIGHT_COST)))

	_section("SMELT  (2 ore makes 1 bar)")
	for i in Data.SMELTING.size():
		var r: Dictionary = Data.SMELTING[i]
		var have: int = game.count(r["input"])
		var can: bool = game.forge_lit and have >= int(r["amount"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_make_icon(r["input"]))
		var label := _make_label("%s  (%d)" % [Data.ITEMS[r["input"]]["name"], have], 15, TEXT_COLOR if have > 0 else DIM_COLOR)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_make_button("Smelt 1", Callable(game, "smelt").bind(i, 1), can))
		row.add_child(_make_button("Smelt all", Callable(game, "smelt").bind(i, 999), can))
		_menu_box.add_child(row)

	_section("FORGE TOOLS  (a handle from the workbench + 3 bars)")
	for kind in Data.TOOL_LINES:
		var next_id: String = game.next_tool(kind)
		if next_id == "":
			_text("Your %s can't get any better." % kind, DIM_COLOR)
			continue
		var tool: Dictionary = Data.TOOLS[next_id]
		_menu_box.add_child(_make_button("Forge %s  (%s)" % [tool["name"], Data.cost_text(tool["recipe"])],
			Callable(game, "forge_tool").bind(next_id), game.forge_lit and game.has_items(tool["recipe"])))
	_menu_box.add_child(HSeparator.new())
	_menu_box.add_child(_make_button("Close  (Esc)", close_menus))


func _menu_workbench() -> void:
	_title("Workbench")
	_text("Carve wood into handles for new tools. Furniture is built with B, anywhere in the house.", DIM_COLOR)
	var cost := Data.cost_text(Data.HANDLE_RECIPE)
	_menu_box.add_child(_make_button("Carve 1 tool handle  (%s)" % cost,
		Callable(game, "craft_handle").bind(1), game.has_items(Data.HANDLE_RECIPE)))
	_menu_box.add_child(_make_button("Carve 5 tool handles",
		Callable(game, "craft_handle").bind(5), game.count("wood") >= 10))
	_menu_box.add_child(HSeparator.new())
	_menu_box.add_child(_make_button("Close  (Esc)", close_menus))


func _menu_summary() -> void:
	_title("Day %d is over" % int(_menu_data.get("day", 0)))
	if _menu_data.get("early", false):
		_text("You headed home early.", DIM_COLOR)
	else:
		_text("The light is gone. You walk back home, tired but happy.", DIM_COLOR)
	var gains: Dictionary = _menu_data.get("gains", {})
	if gains.is_empty():
		_text("You came back empty-handed.", DIM_COLOR)
	else:
		_section("YOU BROUGHT BACK")
		for id in Data.ITEM_ORDER:
			if not gains.has(id):
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(_make_icon(id))
			row.add_child(_make_label("%d  %s" % [gains[id], Data.ITEMS[id]["name"]], 15))
			_menu_box.add_child(row)
	_menu_box.add_child(HSeparator.new())
	_menu_box.add_child(_make_button("Continue", close_menus))
