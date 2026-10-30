extends CanvasLayer
## On-screen UI: stats, ore bag, messages, the elevator shop and the relic collection.

const Data := preload("res://scripts/game_data.gd")

const PANEL_COLOR := Color(0.08, 0.07, 0.07, 0.9)
const BORDER_COLOR := Color(0.55, 0.42, 0.25)
const TEXT_COLOR := Color(0.92, 0.9, 0.86)
const DIM_COLOR := Color(0.55, 0.52, 0.48)
const GOLD := Color(1.0, 0.84, 0.35)

var game

var _money_label: Label
var _level_label: Label
var _pick_label: Label
var _bag_label: Label
var _bag_bar: ProgressBar
var _bonus_label: Label
var _bag_value_label: Label
var _ore_labels := {}
var _title_label: Label
var _toast: Label
var _toast_tween: Tween
var _hint: Label
var _elevator: PanelContainer
var _elevator_box: VBoxContainer
var _level_buttons: Array = []
var _collection: PanelContainer
var _collection_box: VBoxContainer
var _status_timer := 0.0


func _ready() -> void:
	_build_stats()
	_build_bag()
	_build_overlay_labels()
	_elevator = _make_panel(Vector2(370, 40), Vector2(540, 0))
	_elevator_box = VBoxContainer.new()
	_elevator_box.add_theme_constant_override("separation", 8)
	_elevator.add_child(_elevator_box)
	_elevator.hide()
	_collection = _make_panel(Vector2(160, 40), Vector2(960, 0))
	_collection_box = VBoxContainer.new()
	_collection_box.add_theme_constant_override("separation", 10)
	_collection.add_child(_collection_box)
	_collection.hide()
	refresh()


func _process(delta: float) -> void:
	# Keep the regrow countdowns in the elevator menu ticking.
	_status_timer -= delta
	if _elevator.visible and _status_timer <= 0.0:
		_status_timer = 0.5
		for i in _level_buttons.size():
			var b: Button = _level_buttons[i]
			b.text = _level_button_text(i)


# --- Public API -------------------------------------------------------------

func refresh() -> void:
	if game == null:
		return
	var info: Dictionary = Data.LEVELS[game.current_level]
	var level_text := "Level %d - %s" % [game.current_level + 1, info["name"]]
	_money_label.text = "$%d" % game.money
	_level_label.text = level_text
	_title_label.text = level_text
	_pick_label.text = "%s  (power %.1f)" % [Data.PICKAXES[game.pick_tier]["name"], game.pick_power()]
	_bag_label.text = "%s  %d / %d" % [Data.BAGS[game.bag_tier]["name"], game.bag_count(), game.bag_capacity()]
	_bag_bar.max_value = game.bag_capacity()
	_bag_bar.value = game.bag_count()
	_bonus_label.text = "Relics %d / %d  (+%d%% ore value)" % [
		game.unique_relics(), Data.COLLECTIBLES.size(), roundi(game.relic_bonus() * 100.0)]
	for t in _ore_labels:
		var labels: Array = _ore_labels[t]
		var count := int(game.inventory.get(t, 0))
		labels[1].text = "x %d" % count
		var col := TEXT_COLOR if count > 0 else DIM_COLOR
		labels[0].add_theme_color_override("font_color", col)
		labels[1].add_theme_color_override("font_color", col)
	_bag_value_label.text = "Worth  $%d" % game.bag_value()
	if _elevator.visible:
		_rebuild_elevator()
	if _collection.visible:
		_rebuild_collection()


func show_message(text: String, color := Color.WHITE) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


func set_hint_visible(on: bool) -> void:
	_hint.visible = on


func any_open() -> bool:
	return _elevator.visible or _collection.visible


func elevator_open() -> bool:
	return _elevator.visible


func open_elevator() -> void:
	_collection.hide()
	_elevator.show()
	_rebuild_elevator()
	_update_input()


func toggle_collection() -> void:
	if _collection.visible:
		close_menus()
		return
	_elevator.hide()
	_collection.show()
	_rebuild_collection()
	_update_input()


func close_menus() -> void:
	_elevator.hide()
	_collection.hide()
	_update_input()


# --- Builders ---------------------------------------------------------------

func _update_input() -> void:
	game.player.input_enabled = not any_open()


func _make_panel(pos: Vector2, min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = pos
	panel.custom_minimum_size = min_size
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	return panel


func _make_label(text: String, font_size := 18, color := TEXT_COLOR) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_button(text: String, callback: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.add_theme_font_size_override("font_size", 17)
	b.custom_minimum_size = Vector2(0, 36)
	b.pressed.connect(callback)
	return b


func _build_stats() -> void:
	var panel := _make_panel(Vector2(24, 24), Vector2(320, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_make_label("HOLLOW VEIN MINE", 14, BORDER_COLOR.lightened(0.3)))
	_money_label = _make_label("$0", 30, GOLD)
	box.add_child(_money_label)
	_level_label = _make_label("", 17)
	box.add_child(_level_label)
	_pick_label = _make_label("", 17)
	box.add_child(_pick_label)
	_bag_label = _make_label("", 17)
	box.add_child(_bag_label)
	_bag_bar = ProgressBar.new()
	_bag_bar.show_percentage = false
	_bag_bar.custom_minimum_size = Vector2(0, 10)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.2, 0.18, 0.16)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = GOLD.darkened(0.15)
	bar_fill.set_corner_radius_all(4)
	_bag_bar.add_theme_stylebox_override("background", bar_bg)
	_bag_bar.add_theme_stylebox_override("fill", bar_fill)
	box.add_child(_bag_bar)
	_bonus_label = _make_label("", 15, Color(1, 0.9, 0.6))
	box.add_child(_bonus_label)

	var help := _make_panel(Vector2(24, 530), Vector2(320, 0))
	help.add_child(_make_label(
		"Move / dig (hold):  WASD or arrows\n" +
		"(ZQSD on AZERTY keyboards)\n" +
		"E  -  elevator: sell, upgrade, travel\n" +
		"C  -  relic collection\n" +
		"Esc  -  close menu", 15, DIM_COLOR.lightened(0.2)))


func _build_bag() -> void:
	var panel := _make_panel(Vector2(936, 24), Vector2(320, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(_make_label("ORE BAG", 14, BORDER_COLOR.lightened(0.3)))
	for t in Data.ORE_ORDER:
		var info: Dictionary = Data.BLOCKS[t]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = info["color"]
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var name_label := _make_label("%s  ($%d)" % [info["name"], info["value"]], 17)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count_label := _make_label("x 0", 17)
		row.add_child(count_label)
		box.add_child(row)
		_ore_labels[t] = [name_label, count_label]
	box.add_child(HSeparator.new())
	_bag_value_label = _make_label("", 18, GOLD)
	box.add_child(_bag_value_label)


func _build_overlay_labels() -> void:
	_title_label = _make_label("", 26, TEXT_COLOR)
	_title_label.position = Vector2(370, 22)
	_title_label.size = Vector2(540, 36)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)

	_toast = _make_label("", 19)
	_toast.position = Vector2(340, 72)
	_toast.size = Vector2(600, 30)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.modulate.a = 0.0
	add_child(_toast)

	_hint = _make_label("Press E to use the elevator", 18, GOLD)
	_hint.position = Vector2(370, 668)
	_hint.size = Vector2(540, 30)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_constant_override("outline_size", 5)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.hide()
	add_child(_hint)


func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


# --- Elevator ---------------------------------------------------------------

func _rebuild_elevator() -> void:
	# Remember which button had focus so keyboard navigation survives a rebuild.
	var focus_index := 0
	var owner_control := get_viewport().gui_get_focus_owner()
	var old_buttons := _buttons_in(_elevator_box)
	if owner_control != null and owner_control in old_buttons:
		focus_index = old_buttons.find(owner_control)

	_clear(_elevator_box)
	_level_buttons.clear()
	_elevator_box.add_child(_make_label("MINE ELEVATOR", 22, GOLD))
	_elevator_box.add_child(_make_label("Money  $%d" % game.money, 18))

	var worth: int = game.bag_value()
	_elevator_box.add_child(_make_button("Sell all ore  (+$%d)" % worth, Callable(game, "sell_all"), worth > 0))

	var pick_cost: int = game.next_pick_cost()
	if pick_cost < 0:
		_elevator_box.add_child(_make_button("Pickaxe fully upgraded", func(): pass, false))
	else:
		var next_pick: Dictionary = Data.PICKAXES[game.pick_tier + 1]
		_elevator_box.add_child(_make_button("Upgrade pickaxe: %s (power %.1f)  $%d" % [
			next_pick["name"], next_pick["power"], pick_cost], Callable(game, "buy_pickaxe"), game.money >= pick_cost))

	var bag_cost: int = game.next_bag_cost()
	if bag_cost < 0:
		_elevator_box.add_child(_make_button("Bag fully upgraded", func(): pass, false))
	else:
		var next_bag: Dictionary = Data.BAGS[game.bag_tier + 1]
		_elevator_box.add_child(_make_button("Upgrade bag: %s (%d slots)  $%d" % [
			next_bag["name"], next_bag["capacity"], bag_cost], Callable(game, "buy_bag"), game.money >= bag_cost))

	_elevator_box.add_child(HSeparator.new())
	_elevator_box.add_child(_make_label("LEVELS", 16, BORDER_COLOR.lightened(0.3)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_elevator_box.add_child(grid)
	for i in Data.LEVELS.size():
		var b: Button
		if i < game.unlocked:
			b = _make_button(_level_button_text(i), Callable(game, "travel_to").bind(i), i != game.current_level)
		elif i == game.unlocked:
			var cost: int = Data.LEVELS[i]["cost"]
			b = _make_button("Buy level %d: %s\n$%d" % [i + 1, Data.LEVELS[i]["name"], cost],
				Callable(game, "buy_level"), game.money >= cost)
		else:
			b = _make_button("Level %d\n(locked)" % (i + 1), func(): pass, false)
		b.custom_minimum_size = Vector2(250, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		if i < game.unlocked:
			_level_buttons.append(b)

	_elevator_box.add_child(HSeparator.new())
	_elevator_box.add_child(_make_button("Relic collection  (C)", toggle_collection))
	_elevator_box.add_child(_make_button("Close  (E / Esc)", close_menus))

	_elevator.reset_size()
	var buttons := _buttons_in(_elevator_box)
	var enabled := buttons.filter(func(b): return not b.disabled)
	if focus_index < buttons.size() and not buttons[focus_index].disabled:
		buttons[focus_index].grab_focus()
	elif not enabled.is_empty():
		enabled[0].grab_focus()


func _level_button_text(i: int) -> String:
	var name_line := "Level %d: %s" % [i + 1, Data.LEVELS[i]["name"]]
	if i == game.current_level:
		return name_line + "\n(you are here)"
	var remaining: float = game.regen_remaining(i)
	if remaining > 0.0:
		return name_line + "\nregrowing... %ds" % ceili(remaining)
	return name_line + "\nfully regrown"


func _buttons_in(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_buttons_in(child))
	return result


# --- Relic collection -------------------------------------------------------

func _rebuild_collection() -> void:
	_clear(_collection_box)
	_collection_box.add_child(_make_label("RELIC COLLECTION", 22, GOLD))
	_collection_box.add_child(_make_label(
		"Relics hide in sparkling blocks. Every new relic adds +5% to the value of all ore you sell.", 15, DIM_COLOR.lightened(0.2)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	_collection_box.add_child(grid)
	for i in Data.COLLECTIBLES.size():
		var info: Dictionary = Data.COLLECTIBLES[i]
		var count := int(game.collection.get(i, 0))
		var found := count > 0
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.14, 0.12, 0.11) if found else Color(0.1, 0.09, 0.09)
		style.border_color = Color(info["color"], 0.6) if found else Color(0.25, 0.22, 0.2)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", style)
		card.custom_minimum_size = Vector2(225, 0)
		card.tooltip_text = info["desc"] if found else "Not found yet. Look for sparkles on level %d." % (int(info["level"]) + 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(44, 44)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.draw.connect(_draw_relic_icon.bind(icon, info["color"], found, int(info["weight"]) == 1))
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		var rarity := "Rare" if int(info["weight"]) == 1 else "Uncommon"
		text.add_child(_make_label(info["name"] if found else "???", 15, TEXT_COLOR if found else DIM_COLOR))
		text.add_child(_make_label("Level %d  -  %s" % [int(info["level"]) + 1, rarity], 13, DIM_COLOR))
		if found:
			text.add_child(_make_label("Found x%d" % count, 13, GOLD))
		grid.add_child(card)
	_collection_box.add_child(_make_button("Close  (C / Esc)", close_menus))
	_collection.reset_size()


func _draw_relic_icon(icon: Control, color: Color, found: bool, rare: bool) -> void:
	var c := icon.size / 2.0
	if not found:
		icon.draw_circle(c, 18, Color(0.17, 0.15, 0.15))
		icon.draw_string(ThemeDB.fallback_font, c + Vector2(-22, 8), "?", HORIZONTAL_ALIGNMENT_CENTER, 44, 22, DIM_COLOR)
		return
	icon.draw_circle(c, 20, Color(color, 0.18))
	var s := 14.0
	var top := c + Vector2(0, -s)
	var right := c + Vector2(s * 0.8, 0)
	icon.draw_colored_polygon(PackedVector2Array([top, right, c + Vector2(0, s), c + Vector2(-s * 0.8, 0)]), color)
	icon.draw_colored_polygon(PackedVector2Array([top, right, c]), color.lightened(0.5))
	if rare:
		icon.draw_arc(c, 20, 0, TAU, 32, GOLD, 2.0)
