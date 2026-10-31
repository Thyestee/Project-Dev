extends RefCounted
## Shared drawing for items and tools, used by the HUD and by the player's hands.

const Data := preload("res://scripts/game_data.gd")


static func draw_item(ci: CanvasItem, id: String, c: Vector2, s: float) -> void:
	var info: Dictionary = Data.ITEMS[id]
	var col: Color = info["color"]
	var icon: String = info["icon"]
	if icon == "log":
		ci.draw_rect(Rect2(c + Vector2(-0.45, -0.2) * s, Vector2(0.8, 0.4) * s), col)
		ci.draw_rect(Rect2(c + Vector2(-0.45, -0.2) * s, Vector2(0.8, 0.08) * s), col.lightened(0.2))
		ci.draw_circle(c + Vector2(0.35, 0) * s, 0.2 * s, col.lightened(0.35))
		ci.draw_circle(c + Vector2(0.35, 0) * s, 0.09 * s, col.darkened(0.15))
	elif icon == "handle":
		ci.draw_line(c + Vector2(-0.4, 0.4) * s, c + Vector2(0.4, -0.4) * s, col, 0.18 * s)
		ci.draw_line(c + Vector2(-0.28, 0.28) * s, c + Vector2(-0.16, 0.16) * s, col.darkened(0.35), 0.22 * s)
	elif icon == "stone":
		_draw_stone(ci, c, s * 0.42, col)
	elif icon == "lump":
		for p in [Vector2(-0.18, 0.1), Vector2(0.18, 0.12), Vector2(0.0, -0.15)]:
			ci.draw_circle(c + p * s, 0.22 * s, col)
			ci.draw_circle(c + (p + Vector2(-0.06, -0.07)) * s, 0.07 * s, col.lightened(0.4))
	elif icon == "ore":
		_draw_stone(ci, c, s * 0.42, Color(0.48, 0.46, 0.45))
		for p in [Vector2(-0.15, -0.08), Vector2(0.14, 0.05), Vector2(-0.02, 0.18)]:
			ci.draw_circle(c + p * s, 0.1 * s, col)
	elif icon == "bar":
		var pts := PackedVector2Array([
			c + Vector2(-0.45, 0.22) * s, c + Vector2(0.45, 0.22) * s,
			c + Vector2(0.3, -0.18) * s, c + Vector2(-0.3, -0.18) * s])
		ci.draw_colored_polygon(pts, col.darkened(0.15))
		ci.draw_rect(Rect2(c + Vector2(-0.3, -0.18) * s, Vector2(0.6, 0.12) * s), col.lightened(0.3))


static func _draw_stone(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var jitter := [1.0, 0.85, 0.95, 0.8, 1.0, 0.9, 0.85]
	for i in jitter.size():
		pts.append(c + Vector2.from_angle(i * TAU / jitter.size()) * r * float(jitter[i]))
	ci.draw_colored_polygon(pts, col)
	ci.draw_circle(c + Vector2(-0.3, -0.3) * r, r * 0.25, col.lightened(0.25))


## Draws a tool held at `hand`, its handle pointing along `angle`.
static func draw_tool(ci: CanvasItem, tool: Dictionary, hand: Vector2, angle: float, length: float) -> void:
	var dir := Vector2.from_angle(angle)
	var perp := dir.orthogonal()
	var tip := hand + dir * length
	var head: Color = tool["head"]
	ci.draw_line(hand - dir * 3.0, tip, Color(0.55, 0.36, 0.2), maxf(2.0, length * 0.16))
	if tool["kind"] == "pickaxe":
		var w := length * 0.55
		ci.draw_polyline(PackedVector2Array([
			tip + perp * w - dir * w * 0.45, tip + dir * 1.5, tip - perp * w - dir * w * 0.45]),
			head, maxf(2.5, length * 0.2))
	else:
		var w := length * 0.5
		var blade := PackedVector2Array([
			tip - dir * w * 0.5, tip + dir * w * 0.25,
			tip + dir * w * 0.45 + perp * w, tip - dir * w * 0.7 + perp * w * 0.9])
		ci.draw_colored_polygon(blade, head)
		ci.draw_line(tip + dir * w * 0.45 + perp * w, tip - dir * w * 0.7 + perp * w * 0.9, head.lightened(0.4), 1.5)
