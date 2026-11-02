extends RefCounted
# Turns one chunk of the world into a mesh. Only faces that touch air are drawn. Each vertex
# carries the block colour with face shading and ambient occlusion baked in, plus the block's
# glow and shade variation in UV2.

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

static var _shade := PackedFloat32Array([0.7, 0.7, 1.0, 0.5, 0.82, 0.82])
static var _ao_levels := PackedFloat32Array([0.42, 0.6, 0.8, 1.0])
static var _stride_x := -1
static var _n_off := PackedInt32Array()       # index offset to the neighbour each face looks at
static var _ao_off := PackedInt32Array()      # per face corner: side, side, diagonal offsets
static var _corner_pos := PackedVector3Array()
static var _normals := PackedVector3Array()
static var _colors := PackedColorArray()      # block colours, linear
static var _info := PackedVector2Array()      # block glow and shade variation


static func _offset(v: Vector3i, stride_x: int, stride_z: int) -> int:
	return v.y + v.x * stride_x + v.z * stride_z


static func _prepare(stride_x: int, stride_z: int) -> void:
	if _stride_x == stride_x:
		return
	_stride_x = stride_x
	for f in 6:
		var n: Vector3i = NORMALS[f]
		var axes: Array[int] = []
		for a in 3:
			if n[a] == 0:
				axes.append(a)
		_n_off.append(_offset(n, stride_x, stride_z))
		_normals.append(Vector3(n))
		for c in 4:
			var corner: Vector3i = CORNERS[f][c]
			var s1 := Vector3i.ZERO
			var s2 := Vector3i.ZERO
			s1[axes[0]] = 1 if corner[axes[0]] == 1 else -1
			s2[axes[1]] = 1 if corner[axes[1]] == 1 else -1
			for o: Vector3i in [n + s1, n + s2, n + s1 + s2]:
				_ao_off.append(_offset(o, stride_x, stride_z))
			_corner_pos.append(Vector3(corner))
	for b in Blocks.COLORS.size():
		var c: Color = Blocks.COLORS[b]
		_colors.append(c.srgb_to_linear())
		_info.append(Vector2(Blocks.GLOW[b], Blocks.JITTER[b]))


static func _ao(blocks: PackedByteArray, i: int, k: int) -> int:
	var s1 := blocks[i + _ao_off[k]] != 0
	var s2 := blocks[i + _ao_off[k + 1]] != 0
	if s1 and s2:
		return 0
	return 3 - int(s1) - int(s2) - int(blocks[i + _ao_off[k + 2]] != 0)


# Builds the chunk whose lowest corner is block (x0, y0, z0). Blocks are stored column by
# column: index = (y + 1) + (x + 1) * stride_x + (z + 1) * stride_z.
static func build(blocks: PackedByteArray, stride_x: int, stride_z: int, x0: int, y0: int, z0: int, size: int, voxel: float) -> ArrayMesh:
	_prepare(stride_x, stride_z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var infos := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for z in range(z0, z0 + size):
		for x in range(x0, x0 + size):
			var i := (y0 + 1) + (x + 1) * stride_x + (z + 1) * stride_z
			for y in range(y0, y0 + size):
				var b := blocks[i]
				if b != 0:
					for f in 6:
						if blocks[i + _n_off[f]] != 0:
							continue
						var k := f * 12
						var a0 := _ao(blocks, i, k)
						var a1 := _ao(blocks, i, k + 3)
						var a2 := _ao(blocks, i, k + 6)
						var a3 := _ao(blocks, i, k + 9)
						var col := _colors[b] * _shade[f]
						var info := _info[b]
						var base := Vector3(x, y, z)
						var ci := f * 4
						var start := verts.size()
						verts.append((base + _corner_pos[ci]) * voxel)
						verts.append((base + _corner_pos[ci + 1]) * voxel)
						verts.append((base + _corner_pos[ci + 2]) * voxel)
						verts.append((base + _corner_pos[ci + 3]) * voxel)
						var normal := _normals[f]
						normals.append(normal)
						normals.append(normal)
						normals.append(normal)
						normals.append(normal)
						infos.append(info)
						infos.append(info)
						infos.append(info)
						infos.append(info)
						colors.append(col * _ao_levels[a0])
						colors.append(col * _ao_levels[a1])
						colors.append(col * _ao_levels[a2])
						colors.append(col * _ao_levels[a3])
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
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = infos
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
