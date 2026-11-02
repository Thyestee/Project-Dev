extends RefCounted
# An upright box that walks through the world: gravity, sliding along walls, stepping up low
# ledges on its own, edging round corners into gaps just to one side, and (if it's allowed to)
# ducking down to squeeze under low ceilings. The player and every enemy move with one of these.

const World := preload("res://scripts/world.gd")

var world
var position := Vector3.ZERO     # the middle of the feet
var velocity := Vector3.ZERO
var half_width := 0.28
var height := 1.8                # how tall it stands when there's room
var min_height := 1.8            # how low it can duck (the player crawls; enemies don't)
var cur_height := 1.8            # how tall it is right now
var step_height := 2.0 * World.VOXEL + 0.02
var on_floor := false
var hit_wall := false            # ran into something it couldn't get past during the last move
var stepped := 0.0               # how far up the last move stepped


func set_size(new_half_width: float, new_height: float, lowest := -1.0) -> void:
	half_width = new_half_width
	height = new_height
	cur_height = new_height
	min_height = lowest if lowest > 0.0 else new_height


func lo() -> Vector3:
	return position - Vector3(half_width, 0.0, half_width)


func hi() -> Vector3:
	return position + Vector3(half_width, cur_height, half_width)


func blocked() -> bool:
	return world.box_hits_solid(lo(), hi())


func fits(p: Vector3, h: float) -> bool:
	return not world.box_hits_solid(p - Vector3(half_width, 0.0, half_width), p + Vector3(half_width, h, half_width))


# How tall it could be standing at p, up to its full height.
func room_at(p: Vector3) -> float:
	return world.headroom(p - Vector3(half_width, 0.0, half_width), p + Vector3(half_width, 0.0, half_width), height)


# Where along the segment a..b (0 to 1) it first enters the box lo..hi, or -1 if it misses.
static func segment_box(a: Vector3, b: Vector3, box_lo: Vector3, box_hi: Vector3) -> float:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	for axis in 3:
		if absf(d[axis]) < 0.000001:
			if a[axis] < box_lo[axis] or a[axis] > box_hi[axis]:
				return -1.0
			continue
		var ta := (box_lo[axis] - a[axis]) / d[axis]
		var tb := (box_hi[axis] - a[axis]) / d[axis]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return -1.0
	return t0


func overlaps(box_lo: Vector3, box_hi: Vector3) -> bool:
	var a := lo()
	var b := hi()
	return a.x < box_hi.x and b.x > box_lo.x and a.y < box_hi.y and b.y > box_lo.y and a.z < box_hi.z and b.z > box_lo.z


# Moves one axis at a time in steps smaller than a cube, sliding along walls and getting past
# whatever it can.
func move(motion: Vector3) -> void:
	_stand_up()
	var largest := maxf(absf(motion.x), maxf(absf(motion.y), absf(motion.z)))
	var steps := maxi(1, ceili(largest / 0.1))
	var part := motion / steps
	var was_on_floor := on_floor
	on_floor = false
	hit_wall = false
	stepped = 0.0
	for s in steps:
		if part.y != 0.0 and _move_axis(1, part.y):
			if part.y < 0.0:
				on_floor = true
			velocity.y = 0.0
			part.y = 0.0
		for axis: int in [0, 2]:
			if part[axis] != 0.0 and _move_axis(axis, part[axis]):
				if _get_past(axis, part[axis], on_floor or was_on_floor):
					continue
				hit_wall = true
				velocity[axis] = 0.0
				part[axis] = 0.0


# Stands back up as far as there's room.
func _stand_up() -> void:
	if cur_height < height:
		cur_height = clampf(room_at(position), cur_height, height)


func _move_axis(axis: int, amount: float) -> bool:
	var start := position
	var p := position
	p[axis] += amount
	position = p
	if not blocked():
		return false
	# Back off to the face of the cube we ran into.
	if amount > 0.0:
		var top := hi()[axis] / World.VOXEL
		p[axis] -= (top - floorf(top)) * World.VOXEL + 0.001
	else:
		var bottom := lo()[axis] / World.VOXEL
		p[axis] += (floorf(bottom) + 1.0 - bottom) * World.VOXEL + 0.001
	position = p
	if blocked():
		position = start
	return true


# Ran into something moving `amount` along `axis`: steps up onto it, ducks under it or edges
# round it, if it can. Returns whether it got anywhere.
func _get_past(axis: int, amount: float, grounded: bool) -> bool:
	if grounded and _step_up(axis, amount):
		return true
	if min_height < height and _duck(axis, amount):
		return true
	return _edge_round(axis, amount)


func _step_up(axis: int, amount: float) -> bool:
	var start := position
	var p := position
	p.y += step_height
	p[axis] += amount
	position = p
	if blocked():
		position = start
		return false
	_move_axis(1, -step_height)
	stepped += position.y - start.y
	on_floor = true
	return true


# Squeezes into a low gap ahead, as low as min_height, stepping up into it if it has to.
func _duck(axis: int, amount: float) -> bool:
	for rise: float in [0.0, step_height]:
		var p := position
		p.y += rise
		p[axis] += amount
		var room := room_at(p)
		if room < min_height:
			continue
		var start := position
		var was := cur_height
		cur_height = minf(cur_height, room)
		position = p
		if blocked():
			position = start
			cur_height = was
			continue
		if rise > 0.0:
			_move_axis(1, -rise)
			stepped += position.y - start.y
			on_floor = true
		return true
	return false


# Ran into an edge with an opening just to one side of it: slides over towards the opening.
func _edge_round(axis: int, amount: float) -> bool:
	var side := 2 if axis == 0 else 0
	for reach: float in [World.VOXEL, 2.0 * World.VOXEL]:
		for dir: float in [1.0, -1.0]:
			var p := position
			p[side] += dir * reach
			if not fits(p, cur_height):
				continue
			p[axis] += amount
			if not fits(p, cur_height):
				continue
			var q := position
			q[side] += dir * minf(reach, absf(amount) * 1.5 + 0.005)
			if fits(q, cur_height):
				position = q
				return true
	return false
