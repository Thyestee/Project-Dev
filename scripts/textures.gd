extends RefCounted
# Pixel-art block tiles painted in code and packed into a texture array, plus the crack pattern
# shown while digging.

const SIZE := 16

static var images: Array[Image] = []
static var average: Array[Color] = []
static var array: Texture2DArray
static var crack: ImageTexture


static func build() -> void:
	if array != null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	# Same order as the TX_ constants in blocks.gd.
	images = [_grass_top(rng), _grass_side(rng), _dirt(rng), _sand(rng), _clay(rng), _gravel(rng),
		_stone(rng), _slate(rng), _bedrock(rng), _log_side(rng), _log_top(rng), _leaves(rng),
		_relic(rng), _chest_side(rng), _chest_top(rng)]
	var mipped: Array[Image] = []
	average.clear()
	for img in images:
		average.append(_average(img))
		var m := img.duplicate() as Image
		m.generate_mipmaps()
		mipped.append(m)
	array = Texture2DArray.new()
	array.create_from_images(mipped)
	crack = ImageTexture.create_from_image(_crack(rng))


static func _new_image() -> Image:
	return Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)


static func _tint(c: Color, amount: float) -> Color:
	return Color(clampf(c.r * (1.0 + amount), 0.0, 1.0), clampf(c.g * (1.0 + amount), 0.0, 1.0), clampf(c.b * (1.0 + amount), 0.0, 1.0))


static func _fill(rng: RandomNumberGenerator, base: Color, vary: float) -> Image:
	var img := _new_image()
	for y in SIZE:
		for x in SIZE:
			img.set_pixel(x, y, _tint(base, rng.randf_range(-vary, vary)))
	return img


static func _specks(img: Image, rng: RandomNumberGenerator, color: Color, count: int) -> void:
	for i in count:
		img.set_pixel(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1), _tint(color, rng.randf_range(-0.08, 0.08)))


static func _cracks(img: Image, rng: RandomNumberGenerator, color: Color, count: int, length: int) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
	for i in count:
		var p := Vector2i(rng.randi_range(0, SIZE - 1), rng.randi_range(0, SIZE - 1))
		for s in length:
			img.set_pixel(posmod(p.x, SIZE), posmod(p.y, SIZE), color)
			p += dirs[rng.randi() % dirs.size()]


static func _average(img: Image) -> Color:
	var sum := Color(0, 0, 0)
	for y in SIZE:
		for x in SIZE:
			sum += img.get_pixel(x, y)
	return Color(sum.r / (SIZE * SIZE), sum.g / (SIZE * SIZE), sum.b / (SIZE * SIZE))


static func _grass_top(rng: RandomNumberGenerator) -> Image:
	var img := _fill(rng, Color(0.36, 0.6, 0.23), 0.12)
	_specks(img, rng, Color(0.27, 0.48, 0.17), 30)
	_specks(img, rng, Color(0.47, 0.7, 0.3), 18)
	return img


static func _grass_side(rng: RandomNumberGenerator) -> Image:
	var img := _dirt(rng)
	for x in SIZE:
		for y in rng.randi_range(2, 5):
			img.set_pixel(x, y, _tint(Color(0.36, 0.6, 0.23), rng.randf_range(-0.12, 0.12)))
	return img


static func _dirt(rng: RandomNumberGenerator) -> Image:
	var img := _fill(rng, Color(0.45, 0.31, 0.2), 0.14)
	_specks(img, rng, Color(0.32, 0.21, 0.13), 22)
	_specks(img, rng, Color(0.58, 0.44, 0.3), 10)
	_specks(img, rng, Color(0.5, 0.48, 0.45), 4)
	return img


static func _sand(rng: RandomNumberGenerator) -> Image:
	var img := _fill(rng, Color(0.85, 0.77, 0.54), 0.05)
	_specks(img, rng, Color(0.74, 0.65, 0.44), 20)
	_specks(img, rng, Color(0.94, 0.88, 0.7), 12)
	return img


static func _clay(rng: RandomNumberGenerator) -> Image:
	var img := _new_image()
	for y in SIZE:
		var band := rng.randf_range(-0.07, 0.07)
		for x in SIZE:
			img.set_pixel(x, y, _tint(Color(0.64, 0.42, 0.33), band + rng.randf_range(-0.04, 0.04)))
	_specks(img, rng, Color(0.74, 0.54, 0.43), 10)
	return img


static func _gravel(rng: RandomNumberGenerator) -> Image:
	var img := _fill(rng, Color(0.36, 0.33, 0.3), 0.1)
	for i in 16:
		var px := rng.randi_range(0, SIZE - 1)
		var py := rng.randi_range(0, SIZE - 1)
		var c := _tint(Color(0.56, 0.54, 0.5), rng.randf_range(-0.3, 0.15))
		var w := rng.randi_range(2, 3)
		for dx in w:
			img.set_pixel((px + dx) % SIZE, py, c.lightened(0.15))
			img.set_pixel((px + dx) % SIZE, (py + 1) % SIZE, c)
			img.set_pixel((px + dx) % SIZE, (py + 2) % SIZE, c.darkened(0.45))
	return img


static func _stone(rng: RandomNumberGenerator) -> Image:
	var img := _fill(rng, Color(0.5, 0.5, 0.52), 0.07)
	_specks(img, rng, Color(0.62, 0.62, 0.64), 14)
	_cracks(img, rng, Color(0.37, 0.37, 0.39), 3, 6)
	return img


static func _slate(rng: RandomNumberGenerator) -> Image:
	var img := _new_image()
	for y in SIZE:
		var band := -0.18 if y % 4 == 0 else rng.randf_range(-0.05, 0.05)
		for x in SIZE:
			img.set_pixel(x, y, _tint(Color(0.3, 0.32, 0.38), band + rng.randf_range(-0.05, 0.05)))
	_specks(img, rng, Color(0.4, 0.42, 0.5), 10)
	return img


static func _bedrock(rng: RandomNumberGenerator) -> Image:
	var img := _fill(rng, Color(0.2, 0.2, 0.22), 0.25)
	_specks(img, rng, Color(0.42, 0.42, 0.44), 26)
	_specks(img, rng, Color(0.07, 0.07, 0.08), 26)
	return img


static func _log_side(rng: RandomNumberGenerator) -> Image:
	var img := _new_image()
	for x in SIZE:
		var stripe := rng.randf_range(-0.12, 0.12) - (0.2 if x % 4 == 0 else 0.0)
		for y in SIZE:
			img.set_pixel(x, y, _tint(Color(0.4, 0.28, 0.17), stripe + rng.randf_range(-0.05, 0.05)))
	return img


static func _log_top(rng: RandomNumberGenerator) -> Image:
	var img := _new_image()
	var center := Vector2(7.5, 7.5)
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x, y).distance_to(center)
			var c := Color(0.36, 0.25, 0.15)
			if d < 6.8:
				c = Color(0.72, 0.56, 0.36) if int(d) % 2 == 0 else Color(0.62, 0.47, 0.29)
			img.set_pixel(x, y, _tint(c, rng.randf_range(-0.05, 0.05)))
	return img


static func _leaves(rng: RandomNumberGenerator) -> Image:
	var img := _fill(rng, Color(0.24, 0.48, 0.19), 0.18)
	_specks(img, rng, Color(0.12, 0.28, 0.09), 30)
	_specks(img, rng, Color(0.37, 0.6, 0.27), 16)
	return img


static func _relic(rng: RandomNumberGenerator) -> Image:
	var img := _dirt(rng)
	for i in 10:
		img.set_pixel(rng.randi_range(1, SIZE - 2), rng.randi_range(1, SIZE - 2), _tint(Color(0.95, 0.78, 0.3), rng.randf_range(-0.15, 0.1)))
	for i in 3:
		img.set_pixel(rng.randi_range(1, SIZE - 2), rng.randi_range(1, SIZE - 2), Color(1.0, 0.97, 0.85))
	return img


static func _chest_side(rng: RandomNumberGenerator) -> Image:
	var img := _new_image()
	for y in SIZE:
		for x in SIZE:
			var c := _tint(Color(0.5, 0.32, 0.17), rng.randf_range(-0.08, 0.08))
			if y % 5 == 0:
				c = c.darkened(0.3)
			if x == 2 or x == 3 or x == 12 or x == 13:
				c = _tint(Color(0.82, 0.64, 0.26), rng.randf_range(-0.1, 0.1))
			if y == 0 or y == SIZE - 1:
				c = Color(0.25, 0.16, 0.09)
			img.set_pixel(x, y, c)
	# The lock.
	for y in range(6, 10):
		for x in range(6, 10):
			var rim := x == 6 or x == 9 or y == 6 or y == 9
			img.set_pixel(x, y, Color(0.88, 0.72, 0.3) if rim else Color(0.15, 0.1, 0.05))
	return img


static func _chest_top(rng: RandomNumberGenerator) -> Image:
	var img := _new_image()
	for y in SIZE:
		for x in SIZE:
			var c := _tint(Color(0.52, 0.34, 0.18), rng.randf_range(-0.08, 0.08))
			if x % 5 == 0:
				c = c.darkened(0.3)
			if y == 2 or y == 3 or y == 12 or y == 13:
				c = _tint(Color(0.82, 0.64, 0.26), rng.randf_range(-0.1, 0.1))
			if x == 0 or x == SIZE - 1 or y == 0 or y == SIZE - 1:
				c = Color(0.25, 0.16, 0.09)
			img.set_pixel(x, y, c)
	return img


# Each pixel holds the dig progress at which it cracks; untouched pixels never do.
static func _crack(rng: RandomNumberGenerator) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_L8)
	img.fill(Color(1, 1, 1))
	var lines := 6
	var length := 10
	for i in lines:
		var p := Vector2(7.5, 7.5) + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
		var dir := Vector2.RIGHT.rotated(TAU * (float(i) + rng.randf()) / lines)
		for s in length:
			var v := (float(s) + float(i) / lines) / length * 0.95
			var q := Vector2i(int(p.x), int(p.y))
			if q.x >= 0 and q.x < SIZE and q.y >= 0 and q.y < SIZE and img.get_pixel(q.x, q.y).r > v:
				img.set_pixel(q.x, q.y, Color(v, v, v))
			dir = dir.rotated(rng.randf_range(-0.5, 0.5))
			p += dir
	return img
