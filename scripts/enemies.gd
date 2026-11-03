extends Node3D
# The guards of the hidden rooms: skeletons, skeleton archers, crypt spiders, stone golems and
# the Warden. They sleep until you break into their room, then come for you. Guards deeper down
# are tougher and hit harder.

const Body := preload("res://scripts/body.gd")
const Models := preload("res://scripts/models.gd")

const TYPES := {
	"skeleton": {"name": "Skeleton", "health": 30.0, "damage": 8.0, "speed": 2.9, "half": 0.27, "height": 1.8, "reach": 1.6,
		"windup": 0.55, "recover": 0.6, "cooldown": 0.5, "coins": 6, "color": Color(0.86, 0.83, 0.74), "sound": "hit_bone"},
	"archer": {"name": "Skeleton archer", "health": 22.0, "damage": 7.0, "speed": 2.6, "half": 0.27, "height": 1.8, "reach": 15.0,
		"windup": 0.9, "recover": 0.5, "cooldown": 1.6, "coins": 8, "color": Color(0.86, 0.83, 0.74), "sound": "hit_bone", "ranged": true},
	"spider": {"name": "Crypt spider", "health": 16.0, "damage": 5.0, "speed": 5.0, "half": 0.4, "height": 0.6, "reach": 2.4,
		"windup": 0.35, "recover": 0.7, "cooldown": 0.6, "coins": 5, "color": Color(0.3, 0.2, 0.34), "sound": "hit_soft"},
	"golem": {"name": "Stone golem", "health": 140.0, "damage": 22.0, "speed": 1.8, "half": 0.55, "height": 2.3, "reach": 2.4,
		"windup": 0.95, "recover": 0.9, "cooldown": 0.8, "coins": 30, "color": Color(0.5, 0.5, 0.52), "sound": "hit_stone", "heavy": true},
	"warden": {"name": "The Warden", "health": 520.0, "damage": 20.0, "speed": 2.7, "half": 0.5, "height": 2.6, "reach": 2.8,
		"windup": 0.75, "recover": 0.7, "cooldown": 0.4, "coins": 250, "color": Color(0.3, 0.3, 0.33), "sound": "hit_metal", "heavy": true, "boss": true},
}
const GRAVITY := 24.0


class Enemy:
	extends RefCounted
	var type := ""
	var def: Dictionary
	var room := ""
	var spawn := -1
	var node: Node3D
	var parts := {}
	var meshes: Array = []
	var bar: MeshInstance3D
	var body
	var health := 1.0
	var max_health := 1.0
	var damage := 1.0
	var coins := 1
	var state := "sleep"     # sleep, idle, chase, windup, recover, charge, return
	var attack := ""
	var timer := 0.0
	var cooldown := 0.0
	var stun := 0.0
	var burn := 0.0
	var burn_damage := 0.0
	var burn_tick := 0.0
	var flash := 0.0
	var tint := Color(0, 0, 0, 0)
	var walk := 0.0
	var turn := 0.0
	var home := Vector3.ZERO
	var look_timer := 0.0
	var sees := false
	var struck := false
	var lunge := 0.0
	var charge_dir := Vector3.FORWARD
	var stuck := 0.0
	var detour := 0.0
	var detour_dir := Vector3.ZERO
	var dead := false
	var last_item := {}


var game
var list: Array = []


func clear() -> void:
	for e: Enemy in list:
		e.node.queue_free()
	list.clear()


func spawn_room(room: Dictionary, dead: Array, awake: bool) -> void:
	var spawns: Array = room.get("spawns", [])
	for k in spawns.size():
		if dead.has(k):
			continue
		var s: Dictionary = spawns[k]
		var e := _make(s["type"], float(room["level"]))
		e.room = room["id"]
		e.spawn = k
		e.home = s["pos"]
		e.body.position = s["pos"]
		e.turn = randf() * TAU
		e.node.position = e.body.position
		e.node.rotation.y = e.turn
		e.state = "idle" if awake else "sleep"
		e.node.visible = awake
		list.append(e)


# A room far behind you: its guards go, and come back as they were when you return.
func despawn_room(id: String) -> void:
	var k := list.size() - 1
	while k >= 0:
		var e: Enemy = list[k]
		if e.room == id:
			e.node.queue_free()
			list.remove_at(k)
		k -= 1


# Breaking a wall makes a racket: the guards come straight for you.
func wake_room(id: String) -> void:
	for e: Enemy in list:
		if e.room == id and e.state == "sleep":
			e.state = "idle"
			e.node.visible = true
			_alert(e)
			e.cooldown = randf_range(0.6, 1.4)


# After you're knocked out, the guards go home and get their strength back.
func reset() -> void:
	for e: Enemy in list:
		if e.dead:
			continue
		e.health = e.max_health
		e.body.position = e.home
		e.body.velocity = Vector3.ZERO
		e.stun = 0.0
		e.burn = 0.0
		if e.state != "sleep":
			e.state = "idle"


func alive_in_room(id: String) -> int:
	var n := 0
	for e: Enemy in list:
		if e.room == id and not e.dead:
			n += 1
	return n


# The boss you're fighting, if any (for the health bar at the top of the screen).
func active_boss() -> Enemy:
	for e: Enemy in list:
		if not e.dead and e.def.get("boss", false) and e.state in ["chase", "windup", "recover", "charge"]:
			return e
	return null


func update(delta: float) -> void:
	var player = game.player
	var eye: Vector3 = player.camera.global_position
	for e: Enemy in list:
		if e.dead or e.state == "sleep":
			continue
		_think(e, delta, player, eye)
		_animate(e, delta, eye)
	_separate(player)


# --- What they do -------------------------------------------------------------------------------

func _think(e: Enemy, delta: float, player, eye: Vector3) -> void:
	var b = e.body
	var me: Vector3 = b.position
	var to: Vector3 = player.body.position - me
	var flat := Vector3(to.x, 0.0, to.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.01 else Vector3.FORWARD
	e.cooldown -= delta
	e.flash = maxf(0.0, e.flash - delta * 5.0)
	if e.burn > 0.0:
		e.burn -= delta
		e.burn_tick -= delta
		if e.burn_tick <= 0.0:
			e.burn_tick = 0.5
			hurt(e, e.burn_damage * 0.5, me, {"knockback": 0.0, "burning": true})
			if e.dead:
				return
	var wish := Vector3.ZERO
	var speed: float = e.def["speed"]
	var playing: bool = game.state == "playing" and player.health > 0.0
	if e.stun > 0.0:
		e.stun -= delta
	else:
		e.look_timer -= delta
		if e.look_timer <= 0.0:
			e.look_timer = 0.25
			e.sees = dist < 24.0 and game.world.line_of_sight(me + Vector3(0.0, float(e.def["height"]) * 0.8, 0.0), eye)
		match e.state:
			"idle":
				if playing and ((e.sees and dist < 14.0) or game.world.room_containing(player.body.position) == e.room):
					_alert(e)
			"chase":
				e.turn = _yaw_toward(dir)
				if not playing:
					e.state = "return"
				elif me.distance_to(e.home) > 30.0:
					e.state = "return"
				elif e.def.get("ranged", false):
					if e.sees and dist < float(e.def["reach"]) and e.cooldown <= 0.0:
						_windup(e, dist)
					elif dist > 9.0 or not e.sees:
						wish = dir
					elif dist < 5.0:
						wish = -dir
				elif dist < float(e.def["reach"]) and absf(to.y) < 2.0 and e.cooldown <= 0.0:
					_windup(e, dist)
				elif e.type == "warden" and dist > 5.0 and dist < 12.0 and e.cooldown <= 0.0 and e.sees and randf() < delta * 0.6:
					_windup(e, dist)
				else:
					wish = dir
			"windup":
				e.timer -= delta
				e.turn = _yaw_toward(dir)
				if e.timer <= 0.0:
					e.state = _strike(e, player, dist, dir, to)
			"recover":
				e.timer -= delta
				if e.lunge > 0.0:
					e.lunge -= delta
					if not e.struck and (player.body.position + Vector3(0.0, 0.9, 0.0)).distance_to(me + Vector3(0.0, 0.3, 0.0)) < 1.4:
						e.struck = true
						player.take_damage(e.damage, me, 3.0, e)
				if e.timer <= 0.0:
					e.state = "chase"
					e.cooldown = float(e.def["cooldown"]) * randf_range(0.8, 1.3)
			"charge":
				e.timer -= delta
				wish = e.charge_dir
				speed = 9.5
				e.turn = _yaw_toward(e.charge_dir)
				if not e.struck and dist < 1.3 and absf(to.y) < 2.0:
					e.struck = true
					player.take_damage(e.damage * 1.4, me, 9.0, e)
				if e.timer <= 0.0 or b.hit_wall:
					e.state = "recover"
					e.timer = 0.9
					if b.hit_wall:
						game.shake(0.25, me)
						e.stun = 0.8
			"return":
				var home_flat: Vector3 = e.home - me
				home_flat.y = 0.0
				if home_flat.length() < 0.7:
					e.state = "idle"
					e.health = e.max_health
				else:
					wish = home_flat.normalized()
					e.turn = _yaw_toward(wish)
				if playing and e.sees and dist < 8.0:
					_alert(e)
	# Stuck against something: go round it for a moment.
	if e.detour > 0.0 and wish.length() > 0.1:
		e.detour -= delta
		wish = (e.detour_dir + wish * 0.35).normalized()
	var v: Vector3 = b.velocity
	var blend := 1.0 - exp(-delta * (10.0 if b.on_floor else 1.5))
	v.x = lerpf(v.x, wish.x * speed, blend)
	v.z = lerpf(v.z, wish.z * speed, blend)
	v.y = maxf(v.y - GRAVITY * delta, -40.0)
	b.velocity = v
	b.move(v * delta)
	if b.hit_wall and wish.length() > 0.1:
		# Hop up ledges too tall to step over; if that doesn't do it, step aside.
		if b.on_floor:
			b.velocity.y = 6.8
		e.stuck += delta
		if e.stuck > 0.4 and e.detour <= 0.0:
			e.stuck = 0.0
			e.detour = 0.9
			e.detour_dir = Vector3(-wish.z, 0.0, wish.x) * (1.0 if randf() < 0.5 else -1.0)
	else:
		e.stuck = maxf(0.0, e.stuck - delta)
	e.walk += Vector2(b.velocity.x, b.velocity.z).length() * delta
	e.node.position = b.position
	e.node.rotation.y = lerp_angle(e.node.rotation.y, e.turn, 1.0 - exp(-delta * (5.0 if e.def.get("heavy", false) else 10.0)))


static func _yaw_toward(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


func _alert(e: Enemy) -> void:
	if e.state in ["chase", "windup", "recover", "charge"]:
		return
	e.state = "chase"
	e.cooldown = randf_range(0.2, 0.6)
	game.sfx.play_at("alert", e.body.position + Vector3(0.0, 1.5, 0.0), randf_range(0.8, 1.1) * (0.6 if e.def.get("heavy", false) else 1.0), -2.0)
	if e.def.get("boss", false):
		game.toast("The Warden rises from his throne!", Color(1.0, 0.45, 0.35))


func _windup(e: Enemy, dist: float) -> void:
	e.state = "windup"
	e.timer = float(e.def["windup"])
	e.attack = ""
	if e.type == "warden":
		var roll := randf()
		e.attack = "charge" if dist > 4.0 else ("slam" if roll < 0.35 else "sweep")
		if e.attack == "charge":
			e.timer = 0.6


# The blow itself. Returns the state to go to next.
func _strike(e: Enemy, player, dist: float, dir: Vector3, to: Vector3) -> String:
	var me: Vector3 = e.body.position
	e.timer = float(e.def["recover"])
	match e.type:
		"archer":
			var from := me + Vector3(0.0, 1.45, 0.0) + dir * 0.4
			var aim: Vector3 = player.body.position + Vector3(0.0, 1.2, 0.0) + player.body.velocity * (dist / 26.0) * 0.5
			var d := aim - from
			var t := maxf(d.length() / 26.0, 0.05)
			game.projectiles.shoot(from, d / t + Vector3(0.0, 4.5 * t, 0.0), false, {"damage": e.damage, "shooter": e})
			game.sfx.play_at("twang", from, 0.8, -3.0)
		"spider":
			e.body.velocity = dir * 7.5 + Vector3(0.0, 3.5, 0.0)
			e.struck = false
			e.lunge = 0.5
			game.sfx.play_at("hiss", me, randf_range(0.9, 1.2), -4.0)
		"golem":
			game.effects.shockwave(me + dir * 1.2, 2.6)
			game.shake(0.35, me)
			game.sfx.play_at("slam", me, 0.8, 0.0)
			if dist < 2.9 and absf(to.y) < 1.6:
				player.take_damage(e.damage, me, 7.0, e)
		"warden":
			match e.attack:
				"charge":
					e.charge_dir = dir
					e.timer = 0.9
					e.struck = false
					game.sfx.play_at("alert", me, 0.6, 0.0)
					return "charge"
				"slam":
					game.effects.shockwave(me + dir * 1.4, 3.6)
					game.shake(0.45, me)
					game.sfx.play_at("slam", me, 0.7, 2.0)
					if dist < 3.8 and absf(to.y) < 1.8:
						player.take_damage(e.damage * 1.3, me, 8.0, e)
				_:
					game.sfx.play_at("swing", me, 0.6, 0.0)
					if dist < float(e.def["reach"]) * 1.15 and absf(to.y) < 2.0 and _facing(e, dir, 0.0):
						player.take_damage(e.damage, me, 6.0, e)
		_:
			game.sfx.play_at("swing", me, randf_range(0.9, 1.1), -4.0)
			if dist < float(e.def["reach"]) * 1.25 and absf(to.y) < 1.6 and _facing(e, dir, 0.4):
				player.take_damage(e.damage, me, 4.0, e)
	return "recover"


func _facing(e: Enemy, dir: Vector3, min_dot: float) -> bool:
	var forward := Vector3(-sin(e.node.rotation.y), 0.0, -cos(e.node.rotation.y))
	return forward.dot(dir) > min_dot


# --- Getting hurt --------------------------------------------------------------------------------

# opts: knockback (m/s), stun (s), burn, crit, item (what hit it), burning (a tick of fire).
func hurt(e: Enemy, amount: float, from: Vector3, opts := {}) -> void:
	if e.dead:
		return
	var heavy: bool = e.def.get("heavy", false)
	e.health -= amount
	e.flash = 1.0
	if opts.has("item"):
		e.last_item = opts["item"]
	var knock := float(opts.get("knockback", 3.0)) * (0.3 if heavy else 1.0)
	var away: Vector3 = e.body.position - from
	away.y = 0.0
	if knock > 0.0 and away.length() > 0.01:
		e.body.velocity += away.normalized() * knock + Vector3(0.0, knock * 0.3, 0.0)
	var stun := float(opts.get("stun", 0.0)) * (0.4 if e.def.get("boss", false) else 1.0)
	if stun > 0.0:
		e.stun = maxf(e.stun, stun)
		if e.state == "windup":
			e.state = "chase"
	if opts.get("burn", false):
		e.burn = 3.0
		e.burn_damage = amount * 0.3
		e.burn_tick = 0.5
	if e.state in ["sleep", "idle", "return"]:
		e.node.visible = true
		_alert(e)
	var top: Vector3 = e.body.position + Vector3(0.0, float(e.def["height"]) + 0.25, 0.0)
	var crit: bool = opts.get("crit", false)
	var color := Color(1.0, 0.55, 0.2) if opts.get("burning", false) else (Color(1.0, 0.85, 0.3) if crit else Color(1.0, 1.0, 1.0))
	game.effects.number(top, ("%d!" if crit else "%d") % maxi(1, roundi(amount)), color, crit)
	if not opts.get("burning", false):
		game.effects.burst(e.body.position + Vector3(0.0, float(e.def["height"]) * 0.6, 0.0), e.def["color"], 8, 2.5, 0.04)
		game.sfx.play_at(e.def["sound"], top, randf_range(0.9, 1.1), -2.0)
	if e.health <= 0.0:
		_die(e)


func _die(e: Enemy) -> void:
	e.dead = true
	e.node.visible = false
	var middle: Vector3 = e.body.position + Vector3(0.0, float(e.def["height"]) * 0.5, 0.0)
	game.effects.burst(middle, e.def["color"], 40, 4.0, 0.07, Vector3.UP, 120.0, 12.0, 1.0)
	game.sfx.play_at("crumble", middle, randf_range(0.8, 1.0) * (0.7 if e.def.get("heavy", false) else 1.0), 0.0)
	game.on_enemy_killed(e)


# --- Finding them ---------------------------------------------------------------------------------

func _targetable(e: Enemy) -> bool:
	return not e.dead and e.state != "sleep"


# The nearest guard along a ray: {"enemy", "dist"} or {}.
func ray_hit(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var hit := segment_hit(origin, origin + dir * max_dist, [])
	if not hit.is_empty():
		hit["dist"] = float(hit["t"]) * max_dist
	return hit


func segment_hit(a: Vector3, b: Vector3, exclude: Array) -> Dictionary:
	var best := {}
	for e: Enemy in list:
		if not _targetable(e) or exclude.has(e):
			continue
		var t := Body.segment_box(a, b, e.body.lo(), e.body.hi())
		if t >= 0.0 and (best.is_empty() or t < float(best["t"])):
			best = {"enemy": e, "t": t}
	return best


# Guards within reach in front of you (cos_angle: how wide the swing is), that you can see.
func in_cone(origin: Vector3, forward: Vector3, reach: float, cos_angle: float) -> Array:
	var out := []
	for e: Enemy in list:
		if not _targetable(e):
			continue
		var c: Vector3 = e.body.position + Vector3(0.0, float(e.def["height"]) * 0.5, 0.0)
		var to := c - origin
		var d := to.length()
		var half: float = e.def["half"]
		if d - half > reach:
			continue
		if d > half + 0.5 and to.normalized().dot(forward) < cos_angle:
			continue
		if not game.world.line_of_sight(origin, c):
			continue
		out.append(e)
	return out


func near(point: Vector3, radius: float) -> Array:
	var out := []
	for e: Enemy in list:
		if _targetable(e) and (e.body.position + Vector3(0.0, float(e.def["height"]) * 0.5, 0.0)).distance_to(point) < radius + float(e.def["half"]):
			out.append(e)
	return out


func _separate(player) -> void:
	for i in list.size():
		var a: Enemy = list[i]
		if not _targetable(a):
			continue
		for j in range(i + 1, list.size()):
			var b: Enemy = list[j]
			if not _targetable(b):
				continue
			var d := Vector2(b.body.position.x - a.body.position.x, b.body.position.z - a.body.position.z)
			var min_d: float = float(a.def["half"]) + float(b.def["half"])
			if d.length() < min_d and d.length() > 0.001:
				var push := d.normalized() * (min_d - d.length()) * 0.5
				a.body.move(Vector3(-push.x, 0.0, -push.y))
				b.body.move(Vector3(push.x, 0.0, push.y))
		# Don't walk into the player.
		var p := Vector2(a.body.position.x - player.body.position.x, a.body.position.z - player.body.position.z)
		var reach: float = float(a.def["half"]) + 0.3
		if p.length() < reach and p.length() > 0.001 and absf(a.body.position.y - player.body.position.y) < 1.8:
			var push := p.normalized() * (reach - p.length())
			a.body.move(Vector3(push.x, 0.0, push.y))


# --- Looks --------------------------------------------------------------------------------------

func _animate(e: Enemy, delta: float, eye: Vector3) -> void:
	var p: Dictionary = e.parts
	var stride := sin(e.walk * (3.5 if e.def.get("heavy", false) else 5.0))
	var t := Time.get_ticks_msec() / 1000.0
	if e.type == "spider":
		for k in 8:
			var leg: Node3D = p["leg%d" % k]
			leg.rotation.x = sin(e.walk * 9.0 + k * 1.7) * 0.35
		p["root"].rotation.x = -0.35 if e.state == "windup" or e.lunge > 0.0 else 0.0
	else:
		var swing := stride * (0.45 if e.def.get("heavy", false) else 0.7)
		p["leg_l"].rotation.x = swing
		p["leg_r"].rotation.x = -swing
		var arm_l := -swing * 0.7
		var arm_r := swing * 0.7
		match e.state:
			"windup":
				var k := 1.0 - clampf(e.timer / float(e.def["windup"]), 0.0, 1.0)
				if e.type == "archer":
					arm_l = -1.5
					arm_r = -1.5 + k * 0.3
				elif e.type == "golem" or e.attack == "slam":
					arm_l = -2.8 * k
					arm_r = -2.8 * k
				else:
					arm_r = -2.4 * k
			"recover":
				var k := clampf(e.timer / float(e.def["recover"]), 0.0, 1.0)
				if e.type == "golem" or e.attack == "slam":
					arm_l = 0.4 * k
					arm_r = 0.4 * k
				elif e.type != "archer":
					arm_r = 0.9 * k
			"charge":
				arm_r = -1.3
				arm_l = -0.6
			"idle":
				arm_l = sin(t * 1.3 + e.spawn) * 0.06
				arm_r = -arm_l
		p["arm_l"].rotation.x = lerpf(p["arm_l"].rotation.x, arm_l, 1.0 - exp(-delta * 18.0))
		p["arm_r"].rotation.x = lerpf(p["arm_r"].rotation.x, arm_r, 1.0 - exp(-delta * 18.0))
		var head: Node3D = p["head"]
		head.rotation.z = sin(t * 9.0) * 0.25 if e.stun > 0.0 else 0.0
		p["root"].rotation.x = 0.25 if e.state == "charge" else 0.0
	# A flash when hit, a red glow while winding up, flickering orange while on fire.
	var tint := Color(0, 0, 0, 0)
	if e.flash > 0.0:
		tint = Color(1.0, 1.0, 1.0, e.flash * 0.75)
	elif e.burn > 0.0:
		tint = Color(1.0, 0.45, 0.1, 0.3 + 0.15 * sin(t * 20.0))
	elif e.state == "windup":
		tint = Color(1.0, 0.15, 0.08, 0.3)
	if tint != e.tint:
		e.tint = tint
		for mi: MeshInstance3D in e.meshes:
			mi.set_instance_shader_parameter("tint", tint)
	var show_bar: bool = e.health < e.max_health and eye.distance_to(e.body.position) < 25.0 and not e.def.get("boss", false)
	e.bar.visible = show_bar
	if show_bar:
		e.bar.set_instance_shader_parameter("fill", clampf(e.health / e.max_health, 0.0, 1.0))


# A guard as tough as its room is deep: `level` is how far down it is (see Blocks.level). Their
# health keeps up with what your weapons hit for at that depth; their blows grow more slowly.
func _make(type: String, level: float) -> Enemy:
	var e := Enemy.new()
	e.type = type
	e.def = TYPES[type]
	e.max_health = float(e.def["health"]) * pow(1.42, level)
	e.health = e.max_health
	e.damage = float(e.def["damage"]) * pow(1.22, level)
	e.coins = roundi(float(e.def["coins"]) * pow(1.5, level))
	e.body = Body.new()
	e.body.world = game.world
	e.body.set_size(e.def["half"], e.def["height"])
	e.node = Node3D.new()
	add_child(e.node)
	match type:
		"skeleton", "archer":
			_skeleton(e, type == "archer")
		"spider":
			_spider(e)
		"golem":
			_golem(e)
		"warden":
			_warden(e)
	e.bar = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.09)
	e.bar.mesh = quad
	e.bar.material_override = game.effects.bar_material
	e.bar.position.y = float(e.def["height"]) + 0.35
	e.bar.visible = false
	e.node.add_child(e.bar)
	return e


func _part(e: Enemy, name: String, parent: Node3D, pivot: Vector3, boxes: Array) -> Node3D:
	var node := Node3D.new()
	node.position = pivot
	parent.add_child(node)
	if not boxes.is_empty():
		e.meshes.append(Models.instance(node, Models.build(boxes), game.world.material))
	e.parts[name] = node
	return node


func _skeleton(e: Enemy, archer: bool) -> void:
	var bone := Color(0.86, 0.83, 0.74)
	var dark := Color(0.1, 0.08, 0.08)
	var eye := Color(1.0, 0.25, 0.15)
	var root := _part(e, "root", e.node, Vector3.ZERO, [
		[Vector3(0, 0.95, 0), Vector3(0.3, 0.1, 0.16), bone],
		[Vector3(0, 1.12, 0), Vector3(0.06, 0.26, 0.06), bone],
		[Vector3(0, 1.26, 0), Vector3(0.32, 0.05, 0.19), bone],
		[Vector3(0, 1.34, 0), Vector3(0.36, 0.05, 0.21), bone],
		[Vector3(0, 1.42, 0), Vector3(0.36, 0.05, 0.21), bone],
		[Vector3(0, 1.5, 0), Vector3(0.44, 0.06, 0.16), bone],
		[Vector3(0, 1.34, -0.095), Vector3(0.05, 0.26, 0.04), bone],
	])
	var skull := [
		[Vector3(0, 0.15, 0), Vector3(0.26, 0.26, 0.26), bone],
		[Vector3(0, 0.0, -0.02), Vector3(0.2, 0.07, 0.2), bone],
		[Vector3(-0.065, 0.16, -0.125), Vector3(0.075, 0.07, 0.03), dark],
		[Vector3(0.065, 0.16, -0.125), Vector3(0.075, 0.07, 0.03), dark],
		[Vector3(-0.065, 0.16, -0.137), Vector3(0.03, 0.03, 0.02), eye, 2.5],
		[Vector3(0.065, 0.16, -0.137), Vector3(0.03, 0.03, 0.02), eye, 2.5],
		[Vector3(0, 0.08, -0.125), Vector3(0.04, 0.04, 0.03), dark],
	]
	if archer:
		var cloth := Color(0.2, 0.24, 0.18)
		skull.append([Vector3(0, 0.25, 0.02), Vector3(0.3, 0.12, 0.3), cloth])
		skull.append([Vector3(0, 0.14, 0.13), Vector3(0.3, 0.28, 0.06), cloth])
		skull.append([Vector3(-0.145, 0.14, 0.0), Vector3(0.03, 0.28, 0.28), cloth])
		skull.append([Vector3(0.145, 0.14, 0.0), Vector3(0.03, 0.28, 0.28), cloth])
	_part(e, "head", root, Vector3(0, 1.56, 0), skull)
	var arm := [[Vector3(0, -0.16, 0), Vector3(0.06, 0.32, 0.06), bone], [Vector3(0, -0.46, 0), Vector3(0.05, 0.3, 0.05), bone]]
	var left := arm.duplicate()
	var right := arm.duplicate()
	if archer:
		var wood := Color(0.42, 0.28, 0.16)
		left.append([Vector3(0, -0.62, -0.06), Vector3(0.035, 0.8, 0.035), wood])
		left.append([Vector3(0, -0.62, 0.0), Vector3(0.008, 0.76, 0.008), Color(0.85, 0.85, 0.8)])
	else:
		right.append([Vector3(0, -0.62, -0.04), Vector3(0.05, 0.05, 0.14), Color(0.3, 0.2, 0.12)])
		right.append([Vector3(0, -0.62, -0.12), Vector3(0.18, 0.03, 0.03), Color(0.4, 0.36, 0.3)])
		right.append([Vector3(0, -0.62, -0.42), Vector3(0.05, 0.025, 0.55), Color(0.55, 0.42, 0.32)])
	_part(e, "arm_l", root, Vector3(-0.25, 1.48, 0), left)
	_part(e, "arm_r", root, Vector3(0.25, 1.48, 0), right)
	var leg := [[Vector3(0, -0.21, 0), Vector3(0.07, 0.42, 0.07), bone], [Vector3(0, -0.63, 0), Vector3(0.06, 0.42, 0.06), bone], [Vector3(0, -0.88, -0.04), Vector3(0.09, 0.05, 0.16), bone]]
	_part(e, "leg_l", root, Vector3(-0.1, 0.92, 0), leg)
	_part(e, "leg_r", root, Vector3(0.1, 0.92, 0), leg)


func _spider(e: Enemy) -> void:
	var shell := Color(0.22, 0.15, 0.26)
	var belly := Color(0.32, 0.2, 0.36)
	var eye := Color(1.0, 0.2, 0.15)
	var root := _part(e, "root", e.node, Vector3.ZERO, [
		[Vector3(0, 0.32, -0.12), Vector3(0.38, 0.24, 0.36), shell],
		[Vector3(0, 0.42, 0.3), Vector3(0.56, 0.42, 0.6), belly],
		[Vector3(0, 0.64, 0.3), Vector3(0.12, 0.03, 0.26), Color(0.75, 0.12, 0.08), 0.6],
		[Vector3(0, 0.3, -0.38), Vector3(0.26, 0.2, 0.2), shell],
		[Vector3(-0.06, 0.36, -0.485), Vector3(0.04, 0.04, 0.02), eye, 2.5],
		[Vector3(0.06, 0.36, -0.485), Vector3(0.04, 0.04, 0.02), eye, 2.5],
		[Vector3(-0.1, 0.31, -0.485), Vector3(0.03, 0.03, 0.02), eye, 2.5],
		[Vector3(0.1, 0.31, -0.485), Vector3(0.03, 0.03, 0.02), eye, 2.5],
		[Vector3(-0.05, 0.2, -0.5), Vector3(0.03, 0.08, 0.03), Color(0.8, 0.78, 0.7)],
		[Vector3(0.05, 0.2, -0.5), Vector3(0.03, 0.08, 0.03), Color(0.8, 0.78, 0.7)],
	])
	var k := 0
	for side: float in [-1.0, 1.0]:
		for z: float in [-0.26, -0.12, 0.02, 0.16]:
			_part(e, "leg%d" % k, root, Vector3(0.17 * side, 0.34, z), [
				[Vector3(0.2 * side, 0.08, 0), Vector3(0.4, 0.05, 0.05), shell, 0.0, Vector3(0, 0, 0.45 * side)],
				[Vector3(0.42 * side, -0.12, 0), Vector3(0.05, 0.44, 0.05), shell, 0.0, Vector3(0, 0, -0.3 * side)],
			])
			k += 1


func _golem(e: Enemy) -> void:
	var stone := Color(0.5, 0.5, 0.52)
	var dark := Color(0.38, 0.37, 0.39)
	var moss := Color(0.33, 0.45, 0.25)
	var glow := Color(1.0, 0.65, 0.2)
	var root := _part(e, "root", e.node, Vector3.ZERO, [
		[Vector3(0, 1.5, 0), Vector3(1.05, 0.9, 0.65), stone],
		[Vector3(0, 1.0, 0), Vector3(0.7, 0.25, 0.5), dark],
		[Vector3(0, 1.55, -0.33), Vector3(0.3, 0.3, 0.04), glow, 2.0],
		[Vector3(-0.38, 1.97, 0), Vector3(0.36, 0.08, 0.5), moss],
		[Vector3(0.36, 1.97, 0.05), Vector3(0.3, 0.07, 0.4), moss],
	])
	_part(e, "head", root, Vector3(0, 1.95, 0), [
		[Vector3(0, 0.22, -0.05), Vector3(0.5, 0.42, 0.48), stone],
		[Vector3(-0.12, 0.26, -0.3), Vector3(0.09, 0.06, 0.03), glow, 2.5],
		[Vector3(0.12, 0.26, -0.3), Vector3(0.09, 0.06, 0.03), glow, 2.5],
	])
	for side: float in [-1.0, 1.0]:
		_part(e, "arm_l" if side < 0.0 else "arm_r", root, Vector3(0.72 * side, 1.85, 0), [
			[Vector3(0, -0.5, 0), Vector3(0.36, 1.0, 0.38), stone],
			[Vector3(0, -1.08, 0), Vector3(0.44, 0.3, 0.44), dark],
		])
		_part(e, "leg_l" if side < 0.0 else "leg_r", root, Vector3(0.28 * side, 1.0, 0), [
			[Vector3(0, -0.5, 0), Vector3(0.38, 1.0, 0.42), dark],
		])


func _warden(e: Enemy) -> void:
	var armor := Color(0.24, 0.24, 0.27)
	var gold := Color(1.0, 0.8, 0.3)
	var cape := Color(0.45, 0.08, 0.08)
	var bone := Color(0.86, 0.83, 0.74)
	var glow := Color(0.4, 0.9, 1.0)
	var root := _part(e, "root", e.node, Vector3.ZERO, [
		[Vector3(0, 1.32, 0), Vector3(0.5, 0.12, 0.3), gold],
		[Vector3(0, 1.7, 0), Vector3(0.66, 0.66, 0.38), armor],
		[Vector3(0, 1.7, -0.195), Vector3(0.08, 0.6, 0.02), gold],
		[Vector3(-0.42, 2.02, 0), Vector3(0.3, 0.16, 0.42), armor],
		[Vector3(0.42, 2.02, 0), Vector3(0.3, 0.16, 0.42), armor],
		[Vector3(0, 1.45, 0.22), Vector3(0.62, 1.2, 0.04), cape],
	])
	_part(e, "head", root, Vector3(0, 2.05, 0), [
		[Vector3(0, 0.2, 0), Vector3(0.34, 0.38, 0.34), armor],
		[Vector3(0, 0.22, -0.172), Vector3(0.24, 0.04, 0.02), glow, 3.0],
		[Vector3(-0.22, 0.4, 0), Vector3(0.06, 0.22, 0.06), bone, 0.0, Vector3(0, 0, 0.4)],
		[Vector3(0.22, 0.4, 0), Vector3(0.06, 0.22, 0.06), bone, 0.0, Vector3(0, 0, -0.4)],
		[Vector3(0, 0.4, 0), Vector3(0.36, 0.04, 0.36), gold],
	])
	var arm := [[Vector3(0, -0.28, 0), Vector3(0.17, 0.56, 0.18), armor], [Vector3(0, -0.78, 0), Vector3(0.15, 0.5, 0.16), armor]]
	var right := arm.duplicate()
	right.append([Vector3(0, -1.05, -0.05), Vector3(0.05, 0.05, 0.24), Color(0.15, 0.1, 0.08)])
	right.append([Vector3(0, -1.05, -0.19), Vector3(0.38, 0.05, 0.05), gold])
	right.append([Vector3(0, -1.05, -0.92), Vector3(0.12, 0.035, 1.4), Color(0.72, 0.76, 0.82), 0.3])
	_part(e, "arm_l", root, Vector3(-0.44, 1.95, 0), arm)
	_part(e, "arm_r", root, Vector3(0.44, 1.95, 0), right)
	var leg := [[Vector3(0, -0.32, 0), Vector3(0.18, 0.62, 0.2), armor], [Vector3(0, -0.95, 0), Vector3(0.16, 0.66, 0.18), armor], [Vector3(0, -1.27, -0.06), Vector3(0.2, 0.07, 0.3), armor]]
	_part(e, "leg_l", root, Vector3(-0.17, 1.3, 0), leg)
	_part(e, "leg_r", root, Vector3(0.17, 1.3, 0), leg)
