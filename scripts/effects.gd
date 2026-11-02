extends Node3D
# Short-lived things to look at: flying chips, sparks, dust, blasts, lightning and the damage
# numbers that pop out of whatever you hit. Chips are little triangular shards; dust and smoke
# are eight-sided puffs.

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;

instance uniform float fill = 1.0;

void vertex() {
	// Always face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.12) + step(0.88, uv.y);
	vec3 c = uv.x < fill ? mix(vec3(0.75, 0.12, 0.08), vec3(0.95, 0.3, 0.2), uv.y) : vec3(0.08, 0.06, 0.06);
	ALBEDO = border > 0.0 ? vec3(0.02) : c;
}
"""

# A chip: a lopsided pyramid of four triangles. A puff: eight triangles round a point.
const SHARD := [Vector3(0.0, 0.62, 0.0), Vector3(-0.55, -0.3, 0.38), Vector3(0.6, -0.25, 0.3), Vector3(0.05, -0.32, -0.62)]
const SHARD_FACES := [[0, 1, 2], [0, 2, 3], [0, 3, 1], [1, 3, 2]]
const PUFF := [Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0.5, 0), Vector3(0, -0.5, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5)]
const PUFF_FACES := [[0, 2, 4], [4, 2, 1], [1, 2, 5], [5, 2, 0], [0, 4, 3], [4, 1, 3], [1, 5, 3], [5, 0, 3]]

var material: Material        # the world's, so your lamp and the lanterns light the bits too
var _shard: ArrayMesh
var _glow_shard: ArrayMesh
var _puff: ArrayMesh
var _shrink: Curve
var _numbers: Array = []      # {"label", "time", "life"}
var _bolts: Array = []        # {"node", "time"}
var _bolt_material: StandardMaterial3D
var bar_material: ShaderMaterial


func _ready() -> void:
	_shard = _make_solid(SHARD, SHARD_FACES, 0.0)
	_glow_shard = _make_solid(SHARD, SHARD_FACES, 1.6)
	_puff = _make_solid(PUFF, PUFF_FACES, 0.0)
	_shrink = Curve.new()
	_shrink.add_point(Vector2(0.0, 1.0))
	_shrink.add_point(Vector2(0.65, 0.85))
	_shrink.add_point(Vector2(1.0, 0.0))
	_bolt_material = StandardMaterial3D.new()
	_bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_material.albedo_color = Color(0.85, 0.92, 1.0)
	var shader := Shader.new()
	shader.code = BAR_SHADER
	bar_material = ShaderMaterial.new()
	bar_material.shader = shader


func _process(delta: float) -> void:
	var k := _numbers.size() - 1
	while k >= 0:
		var n: Dictionary = _numbers[k]
		n["time"] = float(n["time"]) + delta
		var t: float = n["time"] / n["life"]
		var label: Label3D = n["label"]
		label.position.y += delta * 1.1 * (1.0 - t)
		label.modulate.a = 1.0 - smoothstep(0.6, 1.0, t)
		if t >= 1.0:
			label.queue_free()
			_numbers.remove_at(k)
		k -= 1
	k = _bolts.size() - 1
	while k >= 0:
		_bolts[k]["time"] = float(_bolts[k]["time"]) - delta
		if float(_bolts[k]["time"]) <= 0.0:
			_bolts[k]["node"].queue_free()
			_bolts.remove_at(k)
		k -= 1


# A spray of little shards (or puffs). Glowing ones (sparks, fire) shine in the dark.
func burst(pos: Vector3, color: Color, amount := 14, speed := 2.5, size := 0.05, dir := Vector3.UP, spread := 70.0, gravity := 12.0, life := 0.7, glow := false, puff := false) -> void:
	var p := _particles(glow, puff)
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(size * 1.5, 0.04)
	p.direction = dir if dir.length_squared() > 0.0001 else Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -gravity, 0.0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size * 1.3
	p.scale_amount_curve = _shrink
	p.color = color.srgb_to_linear()
	p.position = pos
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# A solid about a unit across made of triangles, lit from above like everything else.
static func _make_solid(corners: Array, faces: Array, glow: float) -> ArrayMesh:
	var middle := Vector3.ZERO
	for c: Vector3 in corners:
		middle += c / corners.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Array in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		# Clockwise seen from outside, as Godot draws front faces.
		if (b - a).cross(c - a).dot((a + b + c) / 3.0 - middle) > 0.0:
			var swap := b
			b = c
			c = swap
		var n := (c - a).cross(b - a).normalized()
		var shade := 0.55 + 0.45 * (n.y * 0.5 + 0.5)
		for v: Vector3 in [a, b, c]:
			st.set_color(Color(shade, shade, shade))
			st.set_normal(n)
			st.set_uv2(Vector2(glow, -1.0))
			st.add_vertex(v)
	return st.commit()


func _particles(glow: bool, puff := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = _puff if puff else (_glow_shard if glow else _shard)
	p.material_override = material
	return p


# Bits of the block you hit, flying out of its face.
func debris(pos: Vector3, normal: Vector3, color: Color, amount := 12) -> void:
	burst(pos + normal * 0.05, color, amount, 2.8, 0.04, normal + Vector3(0.0, 0.4, 0.0), 55.0)


func dust(pos: Vector3, color := Color(0.5, 0.45, 0.4)) -> void:
	burst(pos, color, 6, 0.5, 0.045, Vector3.UP, 80.0, -0.5, 0.8, false, true)


func sparks(pos: Vector3, normal: Vector3) -> void:
	burst(pos + normal * 0.03, Color(1.0, 0.8, 0.4), 12, 5.5, 0.02, normal, 45.0, 7.0, 0.35, true)


func explosion(pos: Vector3, radius: float, color: Color) -> void:
	burst(pos, Color(1.0, 0.7, 0.3), 40, radius * 7.0, 0.08, Vector3.UP, 180.0, 2.0, 0.45, true)
	burst(pos, Color(1.0, 0.42, 0.12), 30, radius * 5.0, 0.11, Vector3.UP, 180.0, 1.0, 0.6, true)
	burst(pos, Color(0.25, 0.23, 0.22), 26, radius * 1.6, 0.2, Vector3.UP, 120.0, -1.2, 1.8, false, true)
	burst(pos, color, 36, radius * 6.0, 0.06, Vector3.UP, 160.0, 14.0, 1.1)


# A jagged bolt from the sky (well, the ceiling) down to `to`.
func lightning(to: Vector3) -> void:
	var node := Node3D.new()
	add_child(node)
	var p := to + Vector3(randf_range(-0.6, 0.6), 4.0, randf_range(-0.6, 0.6))
	for k in 8:
		var next := p.lerp(to, 1.0 / (8 - k)) + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
		if k == 7:
			next = to
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 0.06, p.distance_to(next))
		seg.mesh = box
		seg.material_override = _bolt_material
		node.add_child(seg)
		seg.position = (p + next) * 0.5
		if p.distance_to(next) > 0.01:
			seg.look_at_from_position(seg.position, next, Vector3.RIGHT if absf((next - p).normalized().y) > 0.99 else Vector3.UP)
		p = next
	_bolts.append({"node": node, "time": 0.18})
	burst(to, Color(0.8, 0.9, 1.0), 20, 5.0, 0.03, Vector3.UP, 180.0, 4.0, 0.4, true)


# A ring of dust running out along the floor.
func shockwave(pos: Vector3, radius: float) -> void:
	var p := _particles(false, true)
	p.amount = 40
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 0.3
	p.emission_ring_inner_radius = 0.2
	p.emission_ring_height = 0.05
	p.direction = Vector3.UP
	p.spread = 20.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.radial_accel_min = radius * 9.0
	p.radial_accel_max = radius * 11.0
	p.gravity = Vector3(0.0, -3.0, 0.0)
	p.scale_amount_min = 0.06
	p.scale_amount_max = 0.12
	p.scale_amount_curve = _shrink
	p.color = Color(0.6, 0.55, 0.48).srgb_to_linear()
	p.position = pos + Vector3(0.0, 0.1, 0.0)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func whirl(pos: Vector3, radius: float) -> void:
	var p := _particles(true)
	p.amount = 36
	p.lifetime = 0.45
	p.one_shot = true
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius * 0.8
	p.emission_ring_inner_radius = radius * 0.6
	p.emission_ring_height = 1.2
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.0
	p.tangential_accel_min = 30.0
	p.tangential_accel_max = 40.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.03
	p.scale_amount_max = 0.06
	p.scale_amount_curve = _shrink
	p.color = Color(0.85, 0.95, 1.0).srgb_to_linear()
	p.position = pos + Vector3(0.0, 0.9, 0.0)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


# A number that floats up and fades.
func number(pos: Vector3, text: String, color: Color, big := false) -> void:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0011 if big else 0.0008
	l.font_size = 48
	l.outline_size = 14
	l.modulate = color
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	l.render_priority = 20
	l.outline_render_priority = 19
	l.position = pos + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15))
	add_child(l)
	_numbers.append({"label": l, "time": 0.0, "life": 1.0 if big else 0.8})
