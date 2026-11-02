extends RefCounted
# Models made of coloured boxes: the enemies, arrows, explosives, the ghost of furniture you're
# placing, and everything you hold. Models out in the world use the world's shader, so your lamp
# and the lanterns light them; held items use VIEW_SHADER and are drawn over everything.

const NORMALS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
# Corners of each face of a box from -1 to 1, counter-clockwise seen from outside.
const CORNERS := [
	[Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)],
	[Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)],
	[Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)],
	[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
	[Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)],
	[Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)],
]
const SHADE := [0.7, 0.7, 1.0, 0.5, 0.82, 0.82]

const VIEW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, depth_draw_always;

varying vec2 info;

void vertex() {
	info = UV2;
}

void fragment() {
	float light = 0.55 + 0.45 * clamp(dot(NORMAL, normalize(vec3(0.4, 0.8, 0.45))), 0.0, 1.0);
	float shimmer = 0.6 + 0.4 * sin(TIME * 4.0 + FRAGCOORD.x * 0.02 + FRAGCOORD.y * 0.015);
	ALBEDO = COLOR.rgb * light + COLOR.rgb * info.x * shimmer;
	// Squeeze what you hold into the sliver of depth right at the camera (depth runs from 1 at
	// the camera to 0 far away), so it is never hidden by a wall you're pressed against.
	DEPTH = 0.97 + 0.03 * FRAGCOORD.z;
	ALPHA = 1.0;
}
"""

const GHOST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;

uniform vec4 color : source_color = vec4(0.4, 1.0, 0.5, 0.3);

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""

static var _view_material: ShaderMaterial


static func view_material() -> ShaderMaterial:
	if _view_material == null:
		var shader := Shader.new()
		shader.code = VIEW_SHADER
		_view_material = ShaderMaterial.new()
		_view_material.shader = shader
	return _view_material


static func ghost_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = GHOST_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


# One box. `shaded` bakes the same face shading as the world's cubes into the colours (models
# out in the world); held items are lit by their own shader instead.
static func add_box(st: SurfaceTool, xf: Transform3D, size: Vector3, color: Color, glow := 0.0, shaded := true) -> void:
	var half := size * 0.5
	var lin := color.srgb_to_linear()
	for f in 6:
		var n: Vector3 = (xf.basis * NORMALS[f]).normalized()
		var c: Color = lin * (SHADE[f] if shaded else 1.0)
		c.a = 1.0
		var corners: Array = CORNERS[f]
		var p: Array[Vector3] = []
		for k in 4:
			p.append(xf * (corners[k] * half))
		for k: int in [0, 2, 1, 0, 3, 2]:
			st.set_color(c)
			st.set_normal(n)
			st.set_uv2(Vector2(glow, -1.0))
			st.add_vertex(p[k])


# Boxes as [centre, size, colour] with an optional glow and an optional rotation (Euler angles).
static func build(boxes: Array, shaded := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Array in boxes:
		var basis := Basis.from_euler(b[4]) if b.size() > 4 else Basis()
		add_box(st, Transform3D(basis, b[0]), b[1], b[2], float(b[3]) if b.size() > 3 else 0.0, shaded)
	return st.commit()


static func instance(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	parent.add_child(mi)
	return mi
