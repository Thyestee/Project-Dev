extends CanvasLayer
# Everything on screen: stats, the detector readout, the hotbar, messages, the treasure
# journal, the workbench and the loading, title and pause screens.

const Blocks := preload("res://scripts/blocks.gd")
const Treasures := preload("res://scripts/treasures.gd")
const Upgrades := preload("res://scripts/upgrades.gd")

const GOLD := Color(1.0, 0.84, 0.4)
const TEXT := Color(0.93, 0.91, 0.86)
const DIM := Color(0.75, 0.75, 0.75)
const SIGNAL_WIDTH := 230.0

var game
var _coins_label: Label
var _found_label: Label
var _depth_label: Label
var _pick_label: Label
var _target_label: Label
var _detector_title: Label
var _signal_fill: ColorRect
var _signal_text: Label
var _signal_flash := 0.0
var _block_name: Label
var _slots: Array = []
var _slot_style: StyleBoxFlat
var _slot_selected_style: StyleBoxFlat
var _toast: Label
var _toast_time := 0.0
var _find_box: VBoxContainer
var _find_time := 0.0
var _journal: CenterContainer
var _journal_box: VBoxContainer
var _overlay: ColorRect
var _overlay_box: VBoxContainer
var _loading_label: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_crosshair(root)
	_build_stats(root)
	_build_detector(root)
	_build_hotbar(root)
	_build_messages(root)
	_build_journal(root)
	_build_overlay(root)


func _process(delta: float) -> void:
	_signal_flash = move_toward(_signal_flash, 0.0, delta * 6.0)
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
	if _find_time > 0.0:
		_find_time -= delta
		_find_box.modulate.a = clampf(_find_time / 0.8, 0.0, 1.0)


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


func _panel(alpha := 0.45) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.04, alpha)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


static func thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return s + out


func _build_crosshair(root: Control) -> void:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	for r: Rect2 in [Rect2(-8, -1, 16, 2), Rect2(-1, -8, 2, 16)]:
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.85)
		line.position = r.position
		line.size = r.size
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(line)
	_target_label = _centered(_label("", 14, Color(1, 1, 1, 0.85)))
	_target_label.position = Vector2(-160, 16)
	_target_label.size = Vector2(320, 20)
	c.add_child(_target_label)


func _build_stats(root: Control) -> void:
	var panel := _panel()
	panel.position = Vector2(16, 16)
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_coins_label = _label("", 18, GOLD)
	_found_label = _label("", 15)
	_depth_label = _label("", 15, Color(0.78, 0.84, 0.9))
	_pick_label = _label("", 13, DIM)
	box.add_child(_coins_label)
	box.add_child(_found_label)
	box.add_child(_depth_label)
	box.add_child(_pick_label)


func _build_detector(root: Control) -> void:
	var panel := _panel()
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_detector_title = _label("", 15, GOLD)
	box.add_child(_detector_title)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(SIGNAL_WIDTH, 12)
	box.add_child(bar)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.5)
	back.size = Vector2(SIGNAL_WIDTH, 12)
	bar.add_child(back)
	_signal_fill = ColorRect.new()
	_signal_fill.size = Vector2(0, 12)
	bar.add_child(_signal_fill)
	_signal_text = _label("", 14)
	box.add_child(_signal_text)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_hotbar(root: Control) -> void:
	_slot_style = StyleBoxFlat.new()
	_slot_style.bg_color = Color(0.06, 0.05, 0.04, 0.55)
	_slot_style.set_corner_radius_all(5)
	_slot_style.set_border_width_all(2)
	_slot_style.border_color = Color(0, 0, 0, 0.4)
	_slot_selected_style = _slot_style.duplicate() as StyleBoxFlat
	_slot_selected_style.border_color = GOLD
	_slot_selected_style.set_border_width_all(3)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(column)
	_block_name = _centered(_label("", 15))
	column.add_child(_block_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	for i in Blocks.HOTBAR.size():
		var b: int = Blocks.HOTBAR[i]
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(58, 58)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := ColorRect.new()
		icon.color = Blocks.COLORS[b]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(14, 12)
		icon.size = Vector2(30, 30)
		slot.add_child(icon)
		var key := _label(str(i + 1), 11, Color(1, 1, 1, 0.6))
		key.position = Vector2(5, 1)
		slot.add_child(key)
		var count := _label("0", 14)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.position = Vector2(2, 36)
		count.size = Vector2(51, 20)
		slot.add_child(count)
		row.add_child(slot)
		_slots.append({"panel": slot, "icon": icon, "count": count})
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_messages(root: Control) -> void:
	_toast = _centered(_label("", 18))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -450
	_toast.offset_right = 450
	_toast.offset_top = 96
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	_find_box = VBoxContainer.new()
	_find_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_box.anchor_left = 0.5
	_find_box.anchor_right = 0.5
	_find_box.anchor_top = 0.18
	_find_box.anchor_bottom = 0.18
	_find_box.offset_left = -350
	_find_box.offset_right = 350
	_find_box.modulate.a = 0.0
	root.add_child(_find_box)


func _build_journal(root: Control) -> void:
	_journal = CenterContainer.new()
	_journal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_journal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_journal.visible = false
	root.add_child(_journal)
	var panel := _panel(0.85)
	_journal.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	_journal_box = VBoxContainer.new()
	_journal_box.add_theme_constant_override("separation", 10)
	margin.add_child(_journal_box)


func _build_overlay(root: Control) -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.03, 0.025, 0.02, 0.62)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 10)
	center.add_child(_overlay_box)
	var version := _label("v" + str(ProjectSettings.get_setting("application/config/version", "dev")), 14, DIM)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_overlay.add_child(version)


# --- Updates --------------------------------------------------------------------------

func refresh() -> void:
	var buried: int = game.world.remaining_treasures()
	_coins_label.text = "Coins: %s" % thousands(game.coins)
	_found_label.text = "Treasures found here: %d / %d" % [Treasures.PER_WORLD - buried, Treasures.PER_WORLD]
	var head: Dictionary = Upgrades.HEADS[game.upgrades["head"]]
	_pick_label.text = "%s pick  ·  %s  ·  %s" % [head["name"], Upgrades.GRIPS[game.upgrades["grip"]]["name"], Upgrades.SIZES[game.upgrades["size"]]["name"]]
	var selected: int = game.hotbar_index
	for i in _slots.size():
		var b: int = Blocks.HOTBAR[i]
		var n: int = game.count(b)
		var slot: Dictionary = _slots[i]
		var count: Label = slot["count"]
		count.text = str(n)
		var icon: ColorRect = slot["icon"]
		icon.modulate = Color.WHITE if n > 0 else Color(1, 1, 1, 0.3)
		var panel: Panel = slot["panel"]
		panel.add_theme_stylebox_override("panel", _slot_selected_style if i == selected else _slot_style)
	_block_name.text = Blocks.NAMES[Blocks.HOTBAR[selected]]


func set_depth(metres: float, home: bool) -> void:
	if home:
		_depth_label.text = "In your room"
	elif metres < 0.5:
		_depth_label.text = "On the stairs"
	else:
		_depth_label.text = "Depth: %.1f m" % metres


func set_target(text: String, color := Color(1, 1, 1, 0.85)) -> void:
	_target_label.text = text
	_target_label.add_theme_color_override("font_color", color)


func set_detector(on: bool, strength: float, beeped: bool) -> void:
	if beeped:
		_signal_flash = 1.0
	if not on:
		_detector_title.text = "Metal detector: off  [F]"
		_signal_fill.size.x = 0.0
		_signal_text.text = "Press F to switch it on."
		return
	_detector_title.text = "Metal detector  [F]"
	_signal_fill.size.x = SIGNAL_WIDTH * strength
	var color := Color(0.35, 0.85, 0.4).lerp(Color(1.0, 0.8, 0.2), clampf(strength * 1.6, 0.0, 1.0))
	color = color.lerp(Color(1.0, 0.35, 0.2), clampf(strength * 2.0 - 1.0, 0.0, 1.0))
	_signal_fill.color = color.lightened(_signal_flash * 0.45)
	if strength <= 0.0:
		_signal_text.text = "No signal. Walk around and listen."
	elif strength < 0.35:
		_signal_text.text = "Faint signal"
	elif strength < 0.65:
		_signal_text.text = "Getting closer..."
	elif strength < 0.85:
		_signal_text.text = "Strong signal!"
	else:
		_signal_text.text = "It's right here!"


func toast(text: String, color := TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_time = 3.0
	_toast.modulate.a = 1.0


func show_find(t: int) -> void:
	var info: Dictionary = Treasures.LIST[t]
	var rarity: int = info["rarity"]
	var color: Color = Treasures.RARITY_COLORS[rarity]
	_clear(_find_box)
	_find_box.add_child(_centered(_label("You found", 18, TEXT)))
	_find_box.add_child(_centered(_label(info["name"], 36, color)))
	_find_box.add_child(_centered(_label("%s  ·  +%s coins" % [Treasures.RARITY_NAMES[rarity], thousands(info["value"])], 17, color)))
	_find_box.add_child(_wrapped(_centered(_label(info["text"], 15, Color(0.88, 0.86, 0.8))), 700))
	_find_time = 5.0
	_find_box.modulate.a = 1.0


func show_journal(open: bool) -> void:
	_journal.visible = open
	if not open:
		return
	_hide_find()
	_clear(_journal_box)
	var found_n: int = game.found_count()
	var buried: int = game.world.remaining_treasures()
	_journal_box.add_child(_label("Treasure Journal", 28, GOLD))
	_journal_box.add_child(_label("%d found in all  ·  %d still buried at this dig site" % [found_n, buried], 15))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 14)
	_journal_box.add_child(grid)
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
	_journal_box.add_child(_label("Tab to close", 13, DIM))


# --- Full-screen overlays ---------------------------------------------------------------

func hide_overlay() -> void:
	_overlay.visible = false


func _hide_find() -> void:
	_find_time = 0.0
	_find_box.modulate.a = 0.0
	_toast_time = 0.0
	_toast.modulate.a = 0.0


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	return sb


func _button(text: String, action: Callable, min_size := Vector2(280, 44), font_size := 18) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = min_size
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_stylebox_override("normal", _button_style(Color(0.2, 0.15, 0.1, 0.92), Color(0.55, 0.43, 0.24)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.32, 0.24, 0.13, 0.95), GOLD))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.14, 0.1, 0.06, 0.95), GOLD))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.1, 0.09, 0.08, 0.8), Color(0.25, 0.22, 0.2)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.4))
	button.pressed.connect(action)
	return button


func _open_overlay() -> void:
	_clear(_overlay_box)
	_hide_find()
	_overlay.visible = true


func _show_overlay(title: String, lines: Array, buttons: Array) -> void:
	_open_overlay()
	_overlay_box.add_child(_centered(_label(title, 54, GOLD)))
	for line: String in lines:
		_overlay_box.add_child(_centered(_label(line, 17)))
	if not buttons.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 12)
		_overlay_box.add_child(gap)
	for b: Array in buttons:
		_overlay_box.add_child(_button(b[0], b[1]))


func show_loading(progress: float) -> void:
	if _loading_label == null or not is_instance_valid(_loading_label) or not _overlay.visible:
		_show_overlay("DEEP FINDS", ["Burying treasure..."], [])
		_loading_label = _overlay_box.get_child(1) as Label
	_loading_label.text = "Burying treasure... %d%%" % int(progress * 100.0)


const CONTROLS := [
	"WASD move  ·  Space jump  ·  Shift sprint  ·  Ctrl crouch  ·  Mouse look",
	"Left click dig  ·  Right click place blocks  ·  1-7 or wheel pick a block",
	"F metal detector  ·  E workbench  ·  Tab journal  ·  Esc pause",
]


func show_title(has_save: bool) -> void:
	var lines: Array = ["Somewhere under your house, lost treasures are waiting.",
		"Take the stairs down and listen to your metal detector: the faster it beeps, the closer you are.",
		"Spend what you find on your pickaxe and your room at the workbench.", ""]
	lines.append_array(CONTROLS)
	var buttons: Array = [["Continue digging" if has_save else "Start digging", Callable(game, "start_playing")]]
	if has_save:
		lines.append("")
		lines.append("So far: %d treasures found, %s coins to spend, %d still buried here." % [game.found_count(), thousands(game.coins), game.world.remaining_treasures()])
		buttons.append(["New dig site", Callable(game, "ask_new_world")])
	_show_overlay("DEEP FINDS", lines, buttons)


func show_pause() -> void:
	var lines: Array = [""]
	lines.append_array(CONTROLS)
	_show_overlay("Paused", lines, [
		["Resume", Callable(game, "resume")],
		["Return to your room", Callable(game, "return_to_room")],
		["New dig site", Callable(game, "ask_new_world")],
		["Save and quit", Callable(game, "save_and_quit")],
	])


func show_new_world_confirm() -> void:
	_show_overlay("New dig site?", ["The ground is filled back in and new treasure is buried.", "Your coins, pickaxe, room and journal stay with you."], [
		["Yes, new dig site", Callable(game, "new_world")],
		["Cancel", Callable(game, "cancel_new_world")],
	])


# --- The workbench -------------------------------------------------------------------------

func show_shop() -> void:
	_open_overlay()
	_overlay_box.add_child(_centered(_label("Workbench", 44, GOLD)))
	_overlay_box.add_child(_centered(_label("Coins: %s" % thousands(game.coins), 20, GOLD)))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	_overlay_box.add_child(columns)

	var pick := _shop_column("Your pickaxe")
	columns.add_child(pick)
	var heads: Array = Upgrades.HEADS
	var head: int = game.upgrades["head"]
	var head_next := "%s head: also digs %s." % [heads[head + 1]["name"], heads[head + 1]["digs"]] if head + 1 < heads.size() else ""
	pick.add_child(_pickaxe_row("head", "Pick head: %s" % heads[head]["name"], "Digs %s." % heads[head]["digs"] if head == 0 else "Digs up to %s." % heads[head]["digs"], head_next))
	var grips: Array = Upgrades.GRIPS
	var grip: int = game.upgrades["grip"]
	var grip_next := "%s: swings %.2fx as fast." % [grips[grip + 1]["name"], grips[grip + 1]["speed"]] if grip + 1 < grips.size() else ""
	pick.add_child(_pickaxe_row("grip", grips[grip]["name"], "Swing speed %.2fx." % grips[grip]["speed"], grip_next))
	var sizes: Array = Upgrades.SIZES
	var size: int = game.upgrades["size"]
	var size_next := "%s: clears more ground every swing." % sizes[size + 1]["name"] if size + 1 < sizes.size() else ""
	pick.add_child(_pickaxe_row("size", sizes[size]["name"], "Clears %.1f m across." % (sizes[size]["radius"] * 2.0 * 0.25), size_next))

	var room := _shop_column("Your room")
	columns.add_child(room)
	for item: Dictionary in Upgrades.ROOM:
		var id: String = item["id"]
		if game.room_owned.has(id):
			room.add_child(_shop_row(item["name"], item["text"], -1, Callable(), "Owned"))
		else:
			room.add_child(_shop_row(item["name"], item["text"], item["cost"], Callable(game, "buy_room").bind(id), "Buy"))

	_overlay_box.add_child(_button("Back to digging", Callable(game, "resume"), Vector2(240, 40), 16))
	_overlay_box.add_child(_centered(_label("E or Esc to close", 13, DIM)))


func _shop_column(title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.add_child(_label(title, 22, GOLD))
	return column


func _pickaxe_row(kind: String, title: String, now: String, next: String) -> HBoxContainer:
	var list: Array = Upgrades.PICKAXE[kind]
	var level: int = game.upgrades[kind]
	if level + 1 >= list.size():
		return _shop_row(title, now + " Fully upgraded.", -1, Callable(), "Maxed")
	return _shop_row(title, now + "\nNext: " + next, list[level + 1]["cost"], Callable(game, "buy_pickaxe").bind(kind), "Upgrade")


func _shop_row(title: String, text: String, cost: int, action: Callable, verb: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(title, 16))
	info.add_child(_wrapped(_label(text, 12, DIM), 290))
	row.add_child(info)
	if cost < 0:
		var done := _label(verb, 15, Color(0.55, 0.85, 0.5))
		done.custom_minimum_size = Vector2(212, 0)
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(done)
		return row
	var affordable: bool = game.coins >= cost
	var price := _label("%s coins" % thousands(cost), 14, GOLD if affordable else Color(0.8, 0.5, 0.45))
	price.custom_minimum_size = Vector2(100, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(price)
	var button := _button(verb, action, Vector2(100, 34), 15)
	button.disabled = not affordable
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(button)
	return row
