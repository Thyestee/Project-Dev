extends CanvasLayer
# Everything on screen while you play: stats, health and stamina, what's in your pack, the tool
# hotbar, messages, the boss's health and the compass to a hidden room you're tracking.

const Treasures := preload("res://scripts/treasures.gd")
const Items := preload("res://scripts/items.gd")
const Goods := preload("res://scripts/goods.gd")
const Catalog := preload("res://scripts/catalog.gd")
const House := preload("res://scripts/house.gd")
const PlayerScript := preload("res://scripts/player.gd")

const GOLD := Color(1.0, 0.84, 0.4)
const TEXT := Color(0.93, 0.91, 0.86)
const DIM := Color(0.75, 0.75, 0.75)
const PACK_WIDTH := 250.0
const BAR_WIDTH := 300.0
const DIRECTIONS := ["ahead", "ahead and to the right", "to your right", "behind you, to the right", "behind you", "behind you, to the left", "to your left", "ahead and to the left"]


# A small drawing of a tool for the hotbar.
class ToolIcon:
	extends Control
	var kind := ""
	var color := Color.WHITE
	var dim := false

	func _draw() -> void:
		var s := size.x / 16.0
		var a := 0.3 if dim else 1.0
		var c := Color(color, a)
		var wood := Color(0.62, 0.43, 0.25, a)
		var dark := Color(0.3, 0.2, 0.12, a)
		match kind:
			"pickaxe":
				draw_line(Vector2(3, 14) * s, Vector2(11, 6) * s, wood, 1.7 * s)
				draw_polyline(PackedVector2Array([Vector2(4.5, 3.5) * s, Vector2(8.5, 3.2) * s, Vector2(11, 6) * s, Vector2(12.8, 8.5) * s, Vector2(13, 12.5) * s]), c, 2.0 * s)
			"leveler":
				draw_line(Vector2(2.5, 13.5) * s, Vector2(6.5, 9.5) * s, wood, 2.0 * s)
				draw_line(Vector2(6.5, 9.5) * s, Vector2(8, 8) * s, Color(0.4, 0.4, 0.42, a), 1.2 * s)
				draw_colored_polygon(PackedVector2Array([Vector2(7.5, 8.5) * s, Vector2(9, 3) * s, Vector2(14, 2) * s, Vector2(13, 7) * s]), Color(0.75, 0.77, 0.8, a))
			"sword":
				draw_line(Vector2(5.5, 10.5) * s, Vector2(13.5, 2.5) * s, c, 2.0 * s)
				draw_line(Vector2(3.5, 8.5) * s, Vector2(7.5, 12.5) * s, Color(0.9, 0.75, 0.3, a), 1.6 * s)
				draw_line(Vector2(5.5, 10.5) * s, Vector2(2.5, 13.5) * s, dark, 1.8 * s)
			"mace":
				draw_line(Vector2(2.5, 13.5) * s, Vector2(9, 7) * s, wood, 1.7 * s)
				for k in 8:
					var d := Vector2.from_angle(k * TAU / 8.0)
					draw_line(Vector2(10.5, 5.5) * s + d * 2.0 * s, Vector2(10.5, 5.5) * s + d * 3.6 * s, c, 1.0 * s)
				draw_circle(Vector2(10.5, 5.5) * s, 2.6 * s, c)
			"bow":
				draw_arc(Vector2(4.0, 8.0) * s, 6.5 * s, -1.2, 1.2, 14, wood, 1.7 * s)
				var top := Vector2(4.0, 8.0) * s + Vector2.from_angle(-1.2) * 6.5 * s
				var bottom := Vector2(4.0, 8.0) * s + Vector2.from_angle(1.2) * 6.5 * s
				draw_line(top, bottom, Color(0.9, 0.9, 0.85, a), 0.6 * s)
				draw_line(Vector2(5.5, 8) * s, Vector2(14, 8) * s, Color(0.8, 0.7, 0.5, a), 1.0 * s)
				draw_colored_polygon(PackedVector2Array([Vector2(14.5, 8) * s, Vector2(12.5, 6.8) * s, Vector2(12.5, 9.2) * s]), Color(0.7, 0.72, 0.76, a))
			"bomb":
				draw_rect(Rect2(Vector2(4.5, 6) * s, Vector2(6, 8.5) * s), Color(0.8, 0.2, 0.14, a))
				draw_rect(Rect2(Vector2(4.5, 9) * s, Vector2(6, 1.2) * s), Color(0.9, 0.85, 0.6, a))
				draw_polyline(PackedVector2Array([Vector2(7.5, 6) * s, Vector2(8.5, 3.5) * s, Vector2(10.5, 2.5) * s]), Color(0.9, 0.85, 0.7, a), 0.9 * s)
				draw_circle(Vector2(11, 2.2) * s, 1.0 * s, Color(1.0, 0.75, 0.2, a))


var game
var _coins_label: Label
var _found_label: Label
var _depth_label: Label
var _buff_label: Label
var _target_label: Label
var _pack_title: Label
var _pack_fill: ColorRect
var _pack_text: Label
var _health_fill: ColorRect
var _health_text: Label
var _stamina_fill: ColorRect
var _stamina_text: Label
var _info_label: Label
var _slots: Array = []
var _slot_style: StyleBoxFlat
var _slot_selected_style: StyleBoxFlat
var _toast: Label
var _toast_time := 0.0
var _find_box: VBoxContainer
var _find_time := 0.0
var _hurt: ColorRect
var _hurt_alpha := 0.0
var _fade: ColorRect
var _fade_time := 0.0
var _fade_length := 1.0
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_fill: ColorRect
var _compass: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_hurt = ColorRect.new()
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(0.7, 0.05, 0.02, 0.0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hurt)
	_build_crosshair(root)
	_build_stats(root)
	_build_pack(root)
	_build_bottom(root)
	_build_top(root)
	_build_messages(root)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)


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


func _bar(parent: Control, color: Color, height: float) -> Array:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(BAR_WIDTH, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.size = Vector2(BAR_WIDTH, height)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(BAR_WIDTH, height)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var text := _centered(_label("", 11))
	text.size = Vector2(BAR_WIDTH, height)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.position.y = -1
	bar.add_child(text)
	return [fill, text]


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
	_target_label.position = Vector2(-300, 16)
	_target_label.size = Vector2(600, 20)
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
	_buff_label = _label("", 13, Color(0.6, 0.9, 0.6))
	box.add_child(_coins_label)
	box.add_child(_found_label)
	box.add_child(_depth_label)
	box.add_child(_buff_label)


# Bottom left: how full your pack is and what's in it.
func _build_pack(root: Control) -> void:
	var panel := _panel()
	root.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	_pack_title = _label("", 15, GOLD)
	box.add_child(_pack_title)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(PACK_WIDTH, 10)
	box.add_child(bar)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.5)
	back.size = Vector2(PACK_WIDTH, 10)
	bar.add_child(back)
	_pack_fill = ColorRect.new()
	_pack_fill.size = Vector2(0, 10)
	bar.add_child(_pack_fill)
	_pack_text = _label("", 13)
	_pack_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pack_text.custom_minimum_size = Vector2(PACK_WIDTH, 0)
	box.add_child(_pack_text)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_bottom(root: Control) -> void:
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
	column.add_theme_constant_override("separation", 4)
	root.add_child(column)
	_info_label = _centered(_label("", 15))
	column.add_child(_info_label)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 3)
	bars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(bars)
	var health := _bar(bars, Color(0.8, 0.16, 0.12), 14)
	_health_fill = health[0]
	_health_text = health[1]
	var stamina := _bar(bars, Color(0.85, 0.75, 0.25), 9)
	_stamina_fill = stamina[0]
	_stamina_text = stamina[1]
	_stamina_text.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(row)
	for i in 6:
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(62, 62)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := ToolIcon.new()
		icon.position = Vector2(11, 6)
		icon.size = Vector2(40, 40)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var key := _label(str(i + 1), 11, Color(1, 1, 1, 0.6))
		key.position = Vector2(5, 1)
		slot.add_child(key)
		var note := _label("", 12)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		note.position = Vector2(2, 42)
		note.size = Vector2(56, 18)
		slot.add_child(note)
		row.add_child(slot)
		_slots.append({"panel": slot, "icon": icon, "note": note})
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_top(root: Control) -> void:
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.offset_left = -260
	top.offset_right = 260
	top.offset_top = 14
	root.add_child(top)
	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	top.add_child(_boss_box)
	_boss_name = _centered(_label("", 18, Color(1.0, 0.5, 0.4)))
	_boss_box.add_child(_boss_name)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(520, 14)
	_boss_box.add_child(bar)
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.6)
	back.size = Vector2(520, 14)
	bar.add_child(back)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(0.75, 0.12, 0.1)
	_boss_fill.size = Vector2(520, 14)
	bar.add_child(_boss_fill)
	_compass = _centered(_label("", 15, Color(1.0, 0.75, 0.5)))
	top.add_child(_compass)


func _build_messages(root: Control) -> void:
	_toast = _centered(_label("", 18))
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.offset_left = -450
	_toast.offset_right = 450
	_toast.offset_top = 110
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.modulate.a = 0.0
	root.add_child(_toast)
	_find_box = VBoxContainer.new()
	_find_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_find_box.anchor_left = 0.5
	_find_box.anchor_right = 0.5
	_find_box.anchor_top = 0.2
	_find_box.anchor_bottom = 0.2
	_find_box.offset_left = -350
	_find_box.offset_right = 350
	_find_box.modulate.a = 0.0
	root.add_child(_find_box)


# --- Updates --------------------------------------------------------------------------

func refresh() -> void:
	var buried: int = game.world.remaining_treasures()
	var total: int = game.world.treasure_list.size()
	_coins_label.text = "Coins: %s" % thousands(game.coins)
	_found_label.text = "Treasures found here: %d / %d" % [total - buried, total]
	_refresh_pack()
	var player = game.player
	for i in _slots.size():
		var kind: String = PlayerScript.SLOTS[i]
		var slot: Dictionary = _slots[i]
		var icon: ToolIcon = slot["icon"]
		var note: Label = slot["note"]
		icon.kind = kind
		icon.dim = false
		note.text = ""
		match kind:
			"pickaxe", "sword", "mace", "bow":
				var item: Dictionary = game.equipped[kind]
				icon.dim = item.is_empty()
				icon.color = Items.TIER_COLORS[item["tier"]] if not item.is_empty() else Color(0.6, 0.6, 0.6)
				if kind == "bow":
					note.text = str(game.supplies["arrows"])
				if not item.is_empty() and item["rarity"] > 0:
					note.text = (note.text + " " if note.text != "" else "") + "●"
					note.add_theme_color_override("font_color", Items.color(item))
				else:
					note.add_theme_color_override("font_color", TEXT)
			"leveler":
				icon.color = Color(0.75, 0.77, 0.8)
				note.add_theme_color_override("font_color", TEXT)
			"bomb":
				var n: int = game.supplies[game.selected_explosive()]
				icon.dim = n <= 0
				note.text = str(n)
				note.add_theme_color_override("font_color", TEXT)
		icon.queue_redraw()
		var panel: Panel = slot["panel"]
		panel.add_theme_stylebox_override("panel", _slot_selected_style if i == player.slot else _slot_style)
	_info_label.text = _slot_info()


func _refresh_pack() -> void:
	var bag: Array = game.bag
	var slots: int = game.pack_slots()
	# How full it is, counting a part-filled stack as part of a slot.
	var fill := 0.0
	var totals := {}
	var treasure := 0
	for item: Dictionary in bag:
		if Goods.is_good(item):
			fill += float(item["count"]) / Goods.STACK
			totals[item["id"]] = int(totals.get(item["id"], 0)) + int(item["count"])
		else:
			fill += 1.0
			if Goods.is_treasure(item):
				treasure += 1
	var ratio := clampf(fill / slots, 0.0, 1.0)
	var full := ratio >= 0.999
	_pack_title.text = "Pack  %d / %d slots%s" % [bag.size(), slots, "  ·  full!" if full else ""]
	_pack_title.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4) if full else (Color(1.0, 0.68, 0.35) if bag.size() >= slots else GOLD))
	_pack_fill.size.x = PACK_WIDTH * ratio
	_pack_fill.color = Color(0.45, 0.75, 0.4).lerp(Color(0.95, 0.75, 0.25), clampf(ratio * 2.0 - 0.6, 0.0, 1.0)).lerp(Color(0.95, 0.35, 0.25), clampf(ratio * 5.0 - 4.0, 0.0, 1.0))
	var parts: Array[String] = []
	for id: String in Goods.LIST:
		if totals.has(id):
			parts.append("%s %d" % [Goods.LIST[id]["name"], totals[id]])
	if treasure > 0:
		parts.append("%d treasure%s" % [treasure, "" if treasure == 1 else "s"])
	if parts.is_empty():
		_pack_text.text = "Empty. The ore you dig out goes in here."
	else:
		_pack_text.text = "  ·  ".join(parts) + ("\nHead home to sell, smelt or store it." if full else "")


func _slot_info() -> String:
	var player = game.player
	var kind: String = PlayerScript.SLOTS[player.slot]
	match kind:
		"pickaxe":
			return "%s  ·  hold to dig  ·  E digs out treasure" % Items.title(game.equipped["pickaxe"])
		"leveler":
			return "Leveller: click a floor, wall or ceiling to make it flat"
		"sword", "mace", "bow":
			var item: Dictionary = game.equipped[kind]
			if item.is_empty():
				return "No %s yet: %s" % [kind, "buy one at the workbench" if kind == "bow" else "make one at your forge"]
			var extra := ""
			if kind == "bow":
				extra = "  ·  %d arrows  ·  hold to draw" % game.supplies["arrows"]
			elif not game.equipped["shield"].is_empty():
				extra = "  ·  right click to block"
			return Items.title(item) + extra
		"bomb":
			var id: String = game.selected_explosive()
			return "%s ×%d  ·  click to throw  ·  R to change" % [Catalog.EXPLOSIVES[id]["name"], game.supplies[id]]
	return ""


func update_status(delta: float) -> void:
	var player = game.player
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
	if _find_time > 0.0:
		_find_time -= delta
		_find_box.modulate.a = clampf(_find_time / 0.8, 0.0, 1.0)
	_hurt_alpha = move_toward(_hurt_alpha, 0.0, delta * 1.6)
	var low := clampf(1.0 - player.health / player.max_health() * 3.0, 0.0, 1.0) * 0.18
	_hurt.color.a = maxf(_hurt_alpha * 0.45, low)
	if _fade_time > 0.0:
		_fade_time -= delta
		var t := 1.0 - _fade_time / _fade_length
		_fade.color.a = sin(clampf(t, 0.0, 1.0) * PI)
	else:
		_fade.color.a = 0.0
	var health_ratio := clampf(player.health / player.max_health(), 0.0, 1.0)
	_health_fill.size.x = lerpf(_health_fill.size.x, BAR_WIDTH * health_ratio, 1.0 - exp(-delta * 12.0))
	_health_text.text = "%d / %d" % [ceili(player.health), roundi(player.max_health())]
	var stamina_ratio := clampf(player.stamina / player.max_stamina(), 0.0, 1.0)
	_stamina_fill.size.x = BAR_WIDTH * stamina_ratio
	if player.exhausted:
		_stamina_fill.color = Color(0.85, 0.3, 0.2).lerp(Color(0.5, 0.2, 0.15), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0))
	else:
		_stamina_fill.color = Color(0.85, 0.75, 0.25) if game.rested <= 0.0 else Color(0.55, 0.9, 0.45)
	if game.state in ["playing", "menu", "paused"]:
		var at_home: bool = game.at_home()
		var metres: float = game.world.depth_at(player.position)
		if at_home:
			_depth_label.text = "At home"
		elif metres < 0.5:
			_depth_label.text = "On the stairs"
		else:
			var v: int = game.world.vault_containing(player.position + Vector3(0.0, 0.2, 0.0))
			_depth_label.text = ("In a hidden room  ·  " if v >= 0 else "") + "Depth: %.1f m" % metres
	_buff_label.text = "Well rested: %d:%02d" % [int(game.rested) / 60, int(game.rested) % 60] if game.rested > 0.0 else ""
	_buff_label.visible = game.rested > 0.0
	var boss = game.enemies.active_boss()
	_boss_box.visible = boss != null and game.state == "playing"
	if boss != null:
		_boss_name.text = boss.def["name"]
		_boss_fill.size.x = 520.0 * clampf(boss.health / boss.max_health, 0.0, 1.0)
	_compass.text = _compass_text()


func _compass_text() -> String:
	var v: int = game.tracked
	if v < 0 or v >= game.world.vaults.size() or game.vault_state[v]["opened"]:
		return ""
	var player = game.player
	var center: Vector3 = game.world.vaults[v]["center"]
	var to: Vector3 = center - player.position
	var flat := Vector2(to.x, to.z)
	var ahead := Vector2(-sin(player.yaw), -cos(player.yaw))
	var angle := wrapf(ahead.angle_to(flat), 0.0, TAU)
	var dir: String = DIRECTIONS[int(round(angle / (TAU / 8.0))) % 8]
	var down: float = player.position.y - (Vector3(game.world.vaults[v]["lo"]) * 0.125).y
	var vertical := "%d m below you" % roundi(down) if down > 1.0 else ("%d m above you" % roundi(-down) if down < -1.0 else "level with you")
	return "Hidden room: %d m %s, %s" % [roundi(flat.length()), dir, vertical]


func set_target(text: String, color := Color(1, 1, 1, 0.85)) -> void:
	_target_label.text = text
	_target_label.add_theme_color_override("font_color", color)


func toast(text: String, color := TEXT) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast_time = 3.5
	_toast.modulate.a = 1.0


func show_find(t: int, value: int) -> void:
	var info: Dictionary = Treasures.LIST[t]
	var rarity: int = info["rarity"]
	var color: Color = Treasures.RARITY_COLORS[rarity]
	_clear(_find_box)
	_find_box.add_child(_centered(_label("You found", 18, TEXT)))
	_find_box.add_child(_centered(_label(info["name"], 36, color)))
	_find_box.add_child(_centered(_label("%s  ·  worth %s coins" % [Treasures.RARITY_NAMES[rarity], thousands(value)], 17, color)))
	var text := _centered(_label(info["text"], 15, Color(0.88, 0.86, 0.8)))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(700, 0)
	_find_box.add_child(text)
	_find_box.add_child(_centered(_label("It's in your pack. Sell it at your workbench.", 14, DIM)))
	_find_time = 5.0
	_find_box.modulate.a = 1.0


func hide_messages() -> void:
	_find_time = 0.0
	_find_box.modulate.a = 0.0
	_toast_time = 0.0
	_toast.modulate.a = 0.0


func flash_hurt(strength: float) -> void:
	_hurt_alpha = maxf(_hurt_alpha, strength)


# Fades to black and back, over `length` seconds.
func fade(length: float) -> void:
	_fade_length = length
	_fade_time = length
