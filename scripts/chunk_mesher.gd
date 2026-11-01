extends RefCounted
# Turns one chunk of the world into a mesh. Only faces that touch air are drawn, with face
# shading and ambient occlusion in the red vertex channel and sky light in the green one.

const Blocks := preload("res://scripts/blocks.gd")

# Faces: +X, -X, +Y, -Y, +Z, -Z. Corners run counter-clockwise seen from outside the block.
const NORMALS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNERS := [
	[Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1), Vector3i(1, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(0, 1, 0), Vector3i(0, 0, 0)],
	[Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0)],
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(1, 0, 0)],
]

static var _shade := PackedFloat32Array([0.62, 0.62, 1.0, 0.36, 0.5, 0.5])
static var _ao_levels := PackedFloat32Array([0.3, 0.5, 0.72, 1.0])
static var _px := -1
static var _n_off := PackedInt32Array()       # index offset to the neighbour each face looks at
static var _n_xyz := PackedInt32Array()       # the same neighbour as x, y, z
static var _ao_off := PackedInt32Array()      # per face corner: side, side, diagonal offsets
static var _corner_pos := PackedVector3Array()
static var _corner_uv := PackedVector2Array()
static var _tiles: Array[PackedInt32Array] = []
static var _glow := PackedFloat32Array()


static func _prepare(px: int, layer: int) -> void:
	if _px == px:
		return
	_px = px
	for f in 6:
		var n: Vector3i = NORMALS[f]
		var axes: Array[int] = []
		for a in 3:
			if n[a] == 0:
				axes.append(a)
		_n_off.append(n.x + n.z * px + n.y * layer)
		_n_xyz.append(n.x)
		_n_xyz.append(n.y)
		_n_xyz.append(n.z)
		for c in 4:
			var corner: Vector3i = CORNERS[f][c]
			var s1 := Vector3i.ZERO
			var s2 := Vector3i.ZERO
			s1[axes[0]] = 1 if corner[axes[0]] == 1 else -1
			s2[axes[1]] = 1 if corner[axes[1]] == 1 else -1
			for o: Vector3i in [n + s1, n + s2, n + s1 + s2]:
				_ao_off.append(o.x + o.z * px + o.y * layer)
			_corner_pos.append(Vector3(corner))
			if n.y != 0:
				_corner_uv.append(Vector2(corner.x, corner.z))
			elif n.x != 0:
				_corner_uv.append(Vector2(corner.z, 1 - corner.y))
			else:
				_corner_uv.append(Vector2(corner.x, 1 - corner.y))
	var side := PackedInt32Array(Blocks.TILE_SIDE)
	_tiles = [side, side, PackedInt32Array(Blocks.TILE_TOP), PackedInt32Array(Blocks.TILE_BOTTOM), side, side]
	_glow = PackedFloat32Array(Blocks.GLOW)


# Sky light of the air cell at height y in a column: full under open sky (dimmer down a deep
# shaft), half next to an open column, none underground.
static func sky_light(top: PackedInt32Array, ground: PackedInt32Array, col: int, y: int, px: int) -> float:
	var open := clampf(1.0 - float(maxi(ground[col] - y, 0)) * 0.035, 0.3, 1.0)
	if y > top[col]:
		return open
	if y > top[col + 1] or y > top[col - 1] or y > top[col + px] or y > top[col - px]:
		return open * 0.55
	return 0.0


static func _ao(blocks: PackedByteArray, i: int, k: int) -> int:
	var s1 := blocks[i + _ao_off[k]] != 0
	var s2 := blocks[i + _ao_off[k + 1]] != 0
	if s1 and s2:
		return 0
	return 3 - int(s1) - int(s2) - int(blocks[i + _ao_off[k + 2]] != 0)


static func build(blocks: PackedByteArray, top: PackedInt32Array, ground: PackedInt32Array, px: int, layer: int, x0: int, y0: int, z0: int, size: int) -> ArrayMesh:
	_prepare(px, layer)
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var infos := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for y in range(y0, y0 + size):
		for z in range(z0, z0 + size):
			var i := (x0 + 1) + (z + 1) * px + (y + 1) * layer
			for x in range(x0, x0 + size):
				var b := blocks[i]
				if b != 0:
					for f in 6:
						if blocks[i + _n_off[f]] != 0:
							continue
						var ax := x + _n_xyz[f * 3]
						var ay := y + _n_xyz[f * 3 + 1]
						var az := z + _n_xyz[f * 3 + 2]
						var sky := sky_light(top, ground, (ax + 1) + (az + 1) * px, ay, px)
						var k := f * 12
						var a0 := _ao(blocks, i, k)
						var a1 := _ao(blocks, i, k + 3)
						var a2 := _ao(blocks, i, k + 6)
						var a3 := _ao(blocks, i, k + 9)
						var shade := _shade[f]
						var info := Vector2(_tiles[f][b], _glow[b])
						var base := Vector3(x, y, z)
						var ci := f * 4
						var start := verts.size()
						verts.append(base + _corner_pos[ci])
						verts.append(base + _corner_pos[ci + 1])
						verts.append(base + _corner_pos[ci + 2])
						verts.append(base + _corner_pos[ci + 3])
						uvs.append(_corner_uv[ci])
						uvs.append(_corner_uv[ci + 1])
						uvs.append(_corner_uv[ci + 2])
						uvs.append(_corner_uv[ci + 3])
						infos.append(info)
						infos.append(info)
						infos.append(info)
						infos.append(info)
						colors.append(Color(shade * _ao_levels[a0], sky, 0.0))
						colors.append(Color(shade * _ao_levels[a1], sky, 0.0))
						colors.append(Color(shade * _ao_levels[a2], sky, 0.0))
						colors.append(Color(shade * _ao_levels[a3], sky, 0.0))
						# Split the quad along its brighter diagonal so the shading stays smooth.
						if a0 + a2 > a1 + a3:
							indices.append(start)
							indices.append(start + 2)
							indices.append(start + 1)
							indices.append(start)
							indices.append(start + 3)
							indices.append(start + 2)
						else:
							indices.append(start)
							indices.append(start + 3)
							indices.append(start + 1)
							indices.append(start + 1)
							indices.append(start + 3)
							indices.append(start + 2)
				i += 1
	if verts.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = infos
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
