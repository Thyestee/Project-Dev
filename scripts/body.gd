extends RefCounted
# An upright box that walks through the cubes: gravity, sliding along walls and stepping up
# low ledges on its own. The player and every enemy move with one of these.

const World := preload("res://scripts/world.gd")

var world
var position := Vector3.ZERO     # the middle of the feet
var velocity := Vector3.ZERO
var half_width := 0.28
var height := 1.8
var step_height := 2.0 * World.VOXEL + 0.02
var on_floor := false
var hit_wall := false            # ran into something too tall to step over during the last move
var stepped := 0.0               # how far up the last move stepped


func lo() -> Vector3:
	return position - Vector3(half_width, 0.0, half_width)


func hi() -> Vector3:
	return position + Vector3(half_width, height, half_width)


func blocked() -> bool:
	return world.box_hits_solid(lo(), hi())


func fits(p: Vector3, h: float) -> bool:
	return not world.box_hits_solid(p - Vector3(half_width, 0.0, half_width), p + Vector3(half_width, h, half_width))


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


# Moves one axis at a time in steps smaller than a cube, sliding along walls and stepping up
# anything lower than step_height.
func move(motion: Vector3) -> void:
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
				if (on_floor or was_on_floor) and _step_up(axis, part[axis]):
					continue
				hit_wall = true
				velocity[axis] = 0.0
				part[axis] = 0.0


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
