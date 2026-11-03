extends Node3D
# Things in flight: the skeletons' arrows, darts from traps, ghostly blades, and thrown explosives
# that bounce about until their fuse runs out.

const Models := preload("res://scripts/models.gd")
const Body := preload("res://scripts/body.gd")
const Catalog := preload("res://scripts/catalog.gd")

const ARROW_GRAVITY := 9.0
const BOMB_GRAVITY := 20.0
const BOMB_HALF := 0.06

var game
var _list: Array = []
var _meshes := {}


func _ready() -> void:
	var fletch := Color(0.92, 0.9, 0.86)
	_meshes["arrow"] = Models.build([
		[Vector3.ZERO, Vector3(0.022, 0.022, 0.62), Color(0.62, 0.45, 0.28)],
		[Vector3(0.0, 0.0, -0.33), Vector3(0.04, 0.04, 0.07), Color(0.62, 0.64, 0.68)],
		[Vector3(0.0, 0.024, 0.26), Vector3(0.006, 0.045, 0.1), fletch],
		[Vector3(0.024, 0.0, 0.26), Vector3(0.045, 0.006, 0.1), fletch],
	])
	_meshes["bone_arrow"] = Models.build([
		[Vector3.ZERO, Vector3(0.022, 0.022, 0.6), Color(0.36, 0.3, 0.26)],
		[Vector3(0.0, 0.0, -0.32), Vector3(0.04, 0.04, 0.07), Color(0.86, 0.83, 0.74)],
		[Vector3(0.0, 0.024, 0.25), Vector3(0.006, 0.045, 0.1), Color(0.6, 0.12, 0.1)],
		[Vector3(0.024, 0.0, 0.25), Vector3(0.045, 0.006, 0.1), Color(0.6, 0.12, 0.1)],
	])
	_meshes["dart"] = Models.build([
		[Vector3.ZERO, Vector3(0.018, 0.018, 0.3), Color(0.24, 0.22, 0.2)],
		[Vector3(0.0, 0.0, -0.16), Vector3(0.03, 0.03, 0.05), Color(0.55, 0.57, 0.6)],
		[Vector3(0.0, 0.0, 0.13), Vector3(0.045, 0.045, 0.04), Color(0.7, 0.2, 0.15)],
	])
	_meshes["blade"] = Models.build([
		[Vector3.ZERO, Vector3(0.9, 0.035, 0.22), Color(0.55, 0.85, 1.0), 1.6],
		[Vector3(0.0, 0.0, 0.08), Vector3(0.6, 0.03, 0.12), Color(0.8, 0.95, 1.0), 2.0],
	])
	_meshes["dynamite"] = Models.build([
		[Vector3.ZERO, Vector3(0.07, 0.07, 0.22), Color(0.8, 0.18, 0.12)],
		[Vector3(0.0, 0.0, 0.0), Vector3(0.075, 0.075, 0.03), Color(0.85, 0.8, 0.6)],
		[Vector3(0.0, 0.0, -0.135), Vector3(0.014, 0.014, 0.05), Color(0.9, 0.85, 0.7)],
	])
	_meshes["charge"] = Models.build([
		[Vector3.ZERO, Vector3(0.2, 0.13, 0.15), Color(0.3, 0.32, 0.36)],
		[Vector3.ZERO, Vector3(0.21, 0.035, 0.16), Color(0.85, 0.7, 0.2)],
		[Vector3(0.0, 0.09, 0.0), Vector3(0.016, 0.06, 0.016), Color(0.9, 0.85, 0.7)],
	])


func clear() -> void:
	for p: Dictionary in _list:
		p["node"].queue_free()
	_list.clear()


# An arrow. `info` carries what the hit does: {"item", "damage", "shooter"}.
func shoot(from: Vector3, vel: Vector3, friendly: bool, info: Dictionary) -> void:
	var node := Models.instance(self, _meshes["arrow" if friendly else "bone_arrow"], game.world.material, from)
	var p := {"kind": "arrow", "node": node, "pos": from, "vel": vel, "friendly": friendly, "life": 6.0, "stuck": false, "hits": []}
	p.merge(info)
	_list.append(p)
	_orient(p)


# A dart from a trap: it flies like a skeleton's arrow, only faster and flatter.
func dart(from: Vector3, vel: Vector3, damage: float) -> void:
	var node := Models.instance(self, _meshes["dart"], game.world.material, from)
	var p := {"kind": "arrow", "node": node, "pos": from, "vel": vel, "friendly": false, "life": 3.0, "stuck": false, "hits": [], "damage": damage, "dart": true}
	_list.append(p)
	_orient(p)


func blade(from: Vector3, dir: Vector3, info: Dictionary) -> void:
	var node := Models.instance(self, _meshes["blade"], game.world.material, from)
	var p := {"kind": "blade", "node": node, "pos": from, "vel": dir * 16.0, "life": 0.9, "hits": []}
	p.merge(info)
	_list.append(p)
	_orient(p)


func throw(from: Vector3, vel: Vector3, kind: String) -> void:
	var node := Models.instance(self, _meshes[kind], game.world.material, from)
	var fuse := CPUParticles3D.new()
	fuse.amount = 12
	fuse.lifetime = 0.3
	fuse.mesh = BoxMesh.new()
	(fuse.mesh as BoxMesh).size = Vector3(0.02, 0.02, 0.02)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.35)
	fuse.mesh.surface_set_material(0, mat)
	fuse.direction = Vector3.UP
	fuse.spread = 60.0
	fuse.initial_velocity_min = 0.6
	fuse.initial_velocity_max = 1.6
	fuse.gravity = Vector3(0.0, -2.0, 0.0)
	fuse.position = Vector3(0.0, 0.0, -0.16) if kind == "dynamite" else Vector3(0.0, 0.12, 0.0)
	node.add_child(fuse)
	var def: Dictionary = Catalog.EXPLOSIVES[kind]
	_list.append({"kind": "bomb", "type": kind, "node": node, "pos": from, "vel": vel, "fuse": def["fuse"], "hiss": 0.0, "spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))})


func update(delta: float) -> void:
	var k := _list.size() - 1
	while k >= 0:
		var p: Dictionary = _list[k]
		var done := false
		match p["kind"]:
			"arrow":
				done = _update_arrow(p, delta)
			"blade":
				done = _update_blade(p, delta)
			"bomb":
				done = _update_bomb(p, delta)
		if done:
			p["node"].queue_free()
			_list.remove_at(k)
		k -= 1


func _orient(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	node.position = p["pos"]
	var v: Vector3 = p["vel"]
	if v.length_squared() > 0.0001:
		var up := Vector3.RIGHT if absf(v.normalized().y) > 0.98 else Vector3.UP
		node.look_at(node.position + v, up)


func _update_arrow(p: Dictionary, delta: float) -> bool:
	if p["stuck"]:
		p["life"] = float(p["life"]) - delta
		return float(p["life"]) <= 0.0
	var vel: Vector3 = p["vel"]
	vel.y -= ARROW_GRAVITY * delta * (0.3 if p.get("dart", false) else 1.0)
	p["vel"] = vel
	var a: Vector3 = p["pos"]
	var b := a + vel * delta
	var length := a.distance_to(b)
	var wall: Dictionary = game.world.raycast(a, (b - a) / length, length) if length > 0.0001 else {}
	var wall_t: float = float(wall["dist"]) / length if not wall.is_empty() else 2.0
	p["life"] = float(p["life"]) - delta
	if p["friendly"]:
		# Sent back by a Mirror Ward: now it's after them.
		var hit: Dictionary = game.enemies.segment_hit(a, b, p["hits"])
		if not hit.is_empty() and float(hit["t"]) < wall_t:
			game.arrow_hit_enemy(p, hit["enemy"], a.lerp(b, hit["t"]))
			return true
	else:
		var t := Body.segment_box(a, b, game.player.body.lo(), game.player.body.hi())
		if t >= 0.0 and t < wall_t:
			return game.enemy_arrow_hits_player(p)
	if not wall.is_empty():
		var hit_pos := a.lerp(b, wall_t)
		p["pos"] = hit_pos - vel.normalized() * 0.12
		p["stuck"] = true
		p["life"] = 3.0
		_orient(p)
		game.sfx.play_at("thunk", hit_pos, randf_range(0.9, 1.1), -6.0)
		return false
	p["pos"] = b
	_orient(p)
	return float(p["life"]) <= 0.0


func _update_blade(p: Dictionary, delta: float) -> bool:
	var a: Vector3 = p["pos"]
	var vel: Vector3 = p["vel"]
	var b := a + vel * delta
	var hits: Array = p["hits"]
	while true:
		var hit: Dictionary = game.enemies.segment_hit(a, b, hits)
		if hit.is_empty():
			break
		hits.append(hit["enemy"])
		game.blade_hit_enemy(p, hit["enemy"])
	p["life"] = float(p["life"]) - delta
	if not game.world.line_of_sight(a, b):
		return true
	p["pos"] = b
	_orient(p)
	var node: Node3D = p["node"]
	node.rotate_object_local(Vector3.UP, delta * 14.0)
	return float(p["life"]) <= 0.0


# Bounces off the ground and walls, losing speed, until the fuse burns down.
func _update_bomb(p: Dictionary, delta: float) -> bool:
	p["fuse"] = float(p["fuse"]) - delta
	p["hiss"] = float(p["hiss"]) - delta
	if float(p["hiss"]) <= 0.0:
		p["hiss"] = 0.3
		game.sfx.play_at("fuse", p["pos"], randf_range(0.9, 1.1), -10.0)
	var vel: Vector3 = p["vel"]
	vel.y -= BOMB_GRAVITY * delta
	var pos: Vector3 = p["pos"]
	var motion := vel * delta
	var half := Vector3(BOMB_HALF, BOMB_HALF, BOMB_HALF)
	var bounced := false
	for axis: int in [1, 0, 2]:
		var np := pos
		np[axis] += motion[axis]
		if game.world.box_hits_solid(np - half, np + half):
			vel[axis] *= -0.35
			if axis == 1:
				vel.x *= 0.7
				vel.z *= 0.7
			bounced = bounced or absf(vel[axis]) > 1.0
		else:
			pos = np
	if bounced:
		game.sfx.play_at("place", pos, randf_range(1.2, 1.5), -12.0)
	p["vel"] = vel
	p["pos"] = pos
	var node: Node3D = p["node"]
	node.position = pos
	var spin: Vector3 = p["spin"] * clampf(vel.length() / 6.0, 0.0, 1.0)
	node.rotation += spin * delta
	if float(p["fuse"]) <= 0.0:
		game.explode_bomb(p["type"], pos)
		return true
	return false
