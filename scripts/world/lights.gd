extends RefCounted
## Builds soft round 2D lights (the miner's lamp, the forge fire, daylight down a ladder).

static var _texture: GradientTexture2D


static func make(radius: float, color: Color, energy := 1.0) -> PointLight2D:
	if _texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.5, Color(1, 1, 1, 0.45))
		_texture = GradientTexture2D.new()
		_texture.gradient = g
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.width = 256
		_texture.height = 256
	var light := PointLight2D.new()
	light.texture = _texture
	light.texture_scale = radius / 128.0
	light.color = color
	light.energy = energy
	return light
