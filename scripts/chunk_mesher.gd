extends RefCounted
# Turns one brick of the world (BRICK cells on a side) into triangles.
#
# The ground is one smooth surface: every cell has a density, and the surface runs where the
# density crosses the middle (surface nets: one vertex per corner where the cells meet, placed
# where the density says, and two triangles for every pair of neighbours with ground on one side
# and air on the other). Built things, from the house to the hidden rooms and buried treasure,
# stay crisp cubes. No vertex is shared, so every triangle keeps its own flat shade.
#
# Vertex colours have the shading baked in. UV marks the corners of each ground triangle so the
# shader can line its edges. UV2 holds the glow, and either the cube's shade variation or -2 for
# ground.

const Blocks := preload("res://scripts/blocks.gd")

const BRICK := 8
const SOLID := 128             # densities from here up are solid
const BUILT := 255             # every built block has this density
const GROUND_KIND := -2.0

# Cube faces: +X, -X, +Y, -Y, +Z, -Z. Corners run counter-clockwise seen from outside the block.
const NORMALS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNERS := [
	[Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1), Vector3i(1, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(0, 1, 0), Vector3i(0, 0, 0)],
	[Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0)],
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(1, 0, 0)],
]
# The two ways to split a cube face into triangles.
const SPLIT_A := [0, 2, 1, 0, 3, 2]
const SPLIT_B := [0, 3, 1, 1, 3, 2]
# Light on a ground vertex by how many of the eight cells around it are solid: brighter on
# ridges, darker in hollows.
const GROUND_AO := [1.0, 1.14, 1.1, 1.05, 1.0, 0.93, 0.83, 0.72, 0.62]

static var _shade := PackedFloat32Array([0.7, 0.7, 1.0, 0.5, 0.82, 0.82])
static var _ao_levels := PackedFloat32Array([0.42, 0.6, 0.8, 1.0])
static var _stride_x := -1
static var _stride_z := -1
static var _n_off := PackedInt32Array()       # index offset to the neighbour each face looks at
static var _ao_off := PackedInt32Array()      # per face corner: side, side, diagonal offsets
static var _corner_pos := PackedVector3Array()
static var _normals := PackedVector3Array()
static var _colors := PackedColorArray()      # block colours, linear
static var _info := PackedVector2Array()      # block glow and shade variation
# For each axis and each side the ground is on, the four vertices around an edge: offsets of
# their dual cells from the edge's lower cell, in the brick's dual-cell numbering and in cells,
# in clockwise order seen from the air.
static var _q_local := PackedInt32Array()
static var _q_cell: Array[Vector3i] = []


static func _offset(v: Vector3i, stride_x: int, stride_z: int) -> int:
	return v.y + v.x * stride_x + v.z * stride_z


static func _prepare(stride_x: int, stride_z: int) -> void:
	if _stride_x == stride_x:
		return
	_stride_x = stride_x
	_stride_z = stride_z
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
	# Around the edge along axis a, with u and v the next two axes, the dual cells sit at
	# (du, dv) = (-1, -1), (0, -1), (0, 0), (-1, 0): counter-clockwise seen from +a.
	var dual_stride := [1, BRICK + 1, (BRICK + 1) * (BRICK + 1)]
	for a in 3:
		var u := (a + 1) % 3
		var v := (a + 2) % 3
		for ground_low: bool in [true, false]:
			var order: Array = [Vector2i(-1, 0), Vector2i(0, 0), Vector2i(0, -1), Vector2i(-1, -1)] if ground_low \
				else [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(0, 0), Vector2i(-1, 0)]
			for o: Vector2i in order:
				var cell := Vector3i.ZERO
				cell[u] = o.x
				cell[v] = o.y
				_q_cell.append(cell)
				_q_local.append(cell.x * dual_stride[0] + cell.y * dual_stride[1] + cell.z * dual_stride[2])


static func _ao(blocks: PackedByteArray, i: int, k: int) -> int:
	var s1 := blocks[i + _ao_off[k]] != 0
	var s2 := blocks[i + _ao_off[k + 1]] != 0
	if s1 and s2:
		return 0
	return 3 - int(s1) - int(s2) - int(blocks[i + _ao_off[k + 2]] != 0)


# Builds the brick whose lowest corner is cell (x0, y0, z0). Cells are stored column by column:
# index = (y + 1) + (x + 1) * stride_x + (z + 1) * stride_z. Returns [vertices, normals, colours,
# uv2], or [] if there's nothing to draw. `has_built` says whether the brick may hold built
# blocks at all.
static func build(blocks: PackedByteArray, dens: PackedByteArray, stride_x: int, stride_z: int, x0: int, y0: int, z0: int, has_built: bool, voxel: float) -> Array:
	_prepare(stride_x, stride_z)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var infos := PackedVector2Array()
	_ground(blocks, dens, x0, y0, z0, voxel, verts, normals, colors, infos)
	if has_built:
		_cubes(blocks, x0, y0, z0, voxel, verts, normals, colors, infos)
	if verts.is_empty():
		return []
	return [verts, normals, colors, infos]


# --- The ground ------------------------------------------------------------------------------

static func _ground(blocks: PackedByteArray, dens: PackedByteArray, x0: int, y0: int, z0: int, voxel: float,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, infos: PackedVector2Array) -> void:
	var sx := _stride_x
	var sz := _stride_z
	var n := BRICK + 1
	# Each column of cells from y0 to y0 + BRICK, for x and z from the brick's corner to one past
	# it: 0 if all solid, 1 if all air, 2 if mixed. Two neighbouring columns can only have ground
	# meeting air between them if they aren't both all solid or both all air.
	var types := PackedByteArray()
	types.resize(n * n)
	var seen := 0
	for cz in n:
		for cx in n:
			var i := (y0 + 1) + (x0 + cx + 1) * sx + (z0 + cz + 1) * sz
			var air := blocks.slice(i, i + n).count(0)
			var t := 0 if air == 0 else (1 if air == n else 2)
			types[cx + cz * n] = t
			seen |= 1 << t
	if seen == 1 or seen == 2:
		return
	# Every edge between two cells, one solid and one air, owned by this brick: its lower cell is
	# in the brick. Packed as lx | ly << 4 | lz << 8 | axis << 12 | (ground on the low side) << 14.
	var edges := PackedInt32Array()
	for lz in BRICK:
		for lx in BRICK:
			var t := types[lx + lz * n]
			var tx := types[lx + 1 + lz * n]
			var tz := types[lx + (lz + 1) * n]
			var i := (y0 + 1) + (x0 + lx + 1) * sx + (z0 + lz + 1) * sz
			var key := lx | (lz << 8)
			if t == 2:
				for ly in BRICK:
					var a := blocks[i + ly] != 0
					if a != (blocks[i + ly + 1] != 0):
						edges.append(key | (ly << 4) | (1 << 12) | (int(a) << 14))
			if t == 2 or t != tx:
				for ly in BRICK:
					var a := blocks[i + ly] != 0
					if a != (blocks[i + ly + sx] != 0):
						edges.append(key | (ly << 4) | (int(a) << 14))
			if t == 2 or t != tz:
				for ly in BRICK:
					var a := blocks[i + ly] != 0
					if a != (blocks[i + ly + sz] != 0):
						edges.append(key | (ly << 4) | (2 << 12) | (int(a) << 14))
	if edges.is_empty():
		return
	# Vertices of the dual cells (the cubes between eight cell centres), worked out as needed.
	# Numbered (dx + 1) + (dy + 1) * n + (dz + 1) * n * n for a lowest corner at the brick's
	# corner plus (dx, dy, dz), each from -1 to BRICK - 1.
	var vpos := PackedVector3Array()
	vpos.resize(n * n * n)
	var vlight := PackedFloat32Array()
	vlight.resize(n * n * n)
	var vcol := PackedColorArray()      # the colour of the ground round each vertex (alpha 0: none)
	vcol.resize(n * n * n)
	var vdone := PackedByteArray()
	vdone.resize(n * n * n)
	var quad := PackedVector3Array()
	quad.resize(4)
	var light := PackedFloat32Array()
	light.resize(4)
	var tint := PackedColorArray()
	tint.resize(4)
	var axis_off := PackedInt32Array([sx, 1, sz])
	for e in edges:
		var lx := e & 15
		var ly := (e >> 4) & 15
		var lz := (e >> 8) & 15
		var axis := (e >> 12) & 3
		var ground_low := (e >> 14) & 1
		var low := (y0 + 1 + ly) + (x0 + lx + 1) * sx + (z0 + lz + 1) * sz
		var ground_i := low if ground_low == 1 else low + axis_off[axis]
		var mat := blocks[ground_i]
		if mat > Blocks.BEDROCK:
			continue    # a built block's side: the cube is drawn instead
		var base_d := (lx + 1) + (ly + 1) * n + (lz + 1) * n * n
		var q := axis * 8 + (1 - ground_low) * 4
		for k in 4:
			var d := base_d + _q_local[q + k]
			if vdone[d] == 0:
				vdone[d] = 1
				var m: Vector3i = Vector3i(x0 + lx, y0 + ly, z0 + lz) + _q_cell[q + k]
				var i := (m.y + 1) + (m.x + 1) * sx + (m.z + 1) * sz
				var v0 := dens[i]
				var v1 := dens[i + 1]
				var v2 := dens[i + sx]
				var v3 := dens[i + sx + 1]
				var v4 := dens[i + sz]
				var v5 := dens[i + sz + 1]
				var v6 := dens[i + sx + sz]
				var v7 := dens[i + sx + sz + 1]
				var s0 := v0 >= SOLID
				var s1 := v1 >= SOLID
				var s2 := v2 >= SOLID
				var s3 := v3 >= SOLID
				var s4 := v4 >= SOLID
				var s5 := v5 >= SOLID
				var s6 := v6 >= SOLID
				var s7 := v7 >= SOLID
				# Next to anything built, the surface meets the cubes halfway between cells, so the
				# two line up without gaps.
				var crisp := v0 == BUILT or v1 == BUILT or v2 == BUILT or v3 == BUILT or v4 == BUILT or v5 == BUILT or v6 == BUILT or v7 == BUILT
				var px := 0.0
				var py := 0.0
				var pz := 0.0
				var cnt := 0
				if s0 != s1:
					py += 0.5 if crisp else (127.5 - v0) / (v1 - v0)
					cnt += 1
				if s2 != s3:
					px += 1.0
					py += 0.5 if crisp else (127.5 - v2) / (v3 - v2)
					cnt += 1
				if s4 != s5:
					py += 0.5 if crisp else (127.5 - v4) / (v5 - v4)
					pz += 1.0
					cnt += 1
				if s6 != s7:
					px += 1.0
					py += 0.5 if crisp else (127.5 - v6) / (v7 - v6)
					pz += 1.0
					cnt += 1
				if s0 != s2:
					px += 0.5 if crisp else (127.5 - v0) / (v2 - v0)
					cnt += 1
				if s1 != s3:
					px += 0.5 if crisp else (127.5 - v1) / (v3 - v1)
					py += 1.0
					cnt += 1
				if s4 != s6:
					px += 0.5 if crisp else (127.5 - v4) / (v6 - v4)
					pz += 1.0
					cnt += 1
				if s5 != s7:
					px += 0.5 if crisp else (127.5 - v5) / (v7 - v5)
					py += 1.0
					pz += 1.0
					cnt += 1
				if s0 != s4:
					pz += 0.5 if crisp else (127.5 - v0) / (v4 - v0)
					cnt += 1
				if s1 != s5:
					py += 1.0
					pz += 0.5 if crisp else (127.5 - v1) / (v5 - v1)
					cnt += 1
				if s2 != s6:
					px += 1.0
					pz += 0.5 if crisp else (127.5 - v2) / (v6 - v2)
					cnt += 1
				if s3 != s7:
					px += 1.0
					py += 1.0
					pz += 0.5 if crisp else (127.5 - v3) / (v7 - v3)
					cnt += 1
				var inv := 1.0 / maxi(cnt, 1)
				vpos[d] = Vector3(m.x + 0.5 + px * inv, m.y + 0.5 + py * inv, m.z + 0.5 + pz * inv) * voxel
				vlight[d] = GROUND_AO[int(s0) + int(s1) + int(s2) + int(s3) + int(s4) + int(s5) + int(s6) + int(s7)]
				# Blend the colours of the ground cells round it, so one kind of ground fades into the
				# next instead of changing in steps.
				var sum := Color(0.0, 0.0, 0.0, 0.0)
				var kinds := 0
				if s0 and blocks[i] <= Blocks.BEDROCK:
					sum += _colors[blocks[i]]
					kinds += 1
				if s1 and blocks[i + 1] <= Blocks.BEDROCK:
					sum += _colors[blocks[i + 1]]
					kinds += 1
				if s2 and blocks[i + sx] <= Blocks.BEDROCK:
					sum += _colors[blocks[i + sx]]
					kinds += 1
				if s3 and blocks[i + sx + 1] <= Blocks.BEDROCK:
					sum += _colors[blocks[i + sx + 1]]
					kinds += 1
				if s4 and blocks[i + sz] <= Blocks.BEDROCK:
					sum += _colors[blocks[i + sz]]
					kinds += 1
				if s5 and blocks[i + sz + 1] <= Blocks.BEDROCK:
					sum += _colors[blocks[i + sz + 1]]
					kinds += 1
				if s6 and blocks[i + sx + sz] <= Blocks.BEDROCK:
					sum += _colors[blocks[i + sx + sz]]
					kinds += 1
				if s7 and blocks[i + sx + sz + 1] <= Blocks.BEDROCK:
					sum += _colors[blocks[i + sx + sz + 1]]
					kinds += 1
				vcol[d] = sum / float(kinds) if kinds > 0 else Color(0.0, 0.0, 0.0, 0.0)
			quad[k] = vpos[d]
			light[k] = vlight[d]
			tint[k] = vcol[d] if vcol[d].a > 0.0 else _colors[mat]
		# Four triangles fanned round the point where the surface crosses this edge.
		var va := dens[low]
		var vb := dens[low + axis_off[axis]]
		var center := Vector3(x0 + lx + 0.5, y0 + ly + 0.5, z0 + lz + 0.5)
		center[axis] += (127.5 - va) / (vb - va)
		center *= voxel
		var mid_light := (light[0] + light[1] + light[2] + light[3]) * 0.25
		var col: Color = _colors[mat]
		var jitter: float = _info[mat].y
		var info := Vector2(_info[mat].x, GROUND_KIND)
		var h := ((x0 + lx) * 73856093) ^ ((y0 + ly) * 19349663) ^ ((z0 + lz) * 83492791) ^ (axis * 1640531527)
		for k in 4:
			var pb := quad[k]
			var pc := quad[(k + 1) & 3]
			var normal := (pc - center).cross(pb - center)
			if normal.length_squared() < 1e-12:
				continue
			normal = normal.normalized()
			var shade := normal.x * normal.x * 0.7 + normal.z * normal.z * 0.82 + normal.y * normal.y * (1.0 if normal.y > 0.0 else 0.5)
			var r := float((h >> (k * 7)) & 127) / 127.0
			var f := shade * (1.0 + (r - 0.5) * 1.6 * jitter)
			verts.append(center)
			verts.append(pb)
			verts.append(pc)
			normals.append(normal)
			normals.append(normal)
			normals.append(normal)
			colors.append(col * (f * mid_light))
			colors.append(tint[k] * (f * light[k]))
			colors.append(tint[(k + 1) & 3] * (f * light[(k + 1) & 3]))
			infos.append(info)
			infos.append(info)
			infos.append(info)


# --- Built blocks ------------------------------------------------------------------------------

static func _cubes(blocks: PackedByteArray, x0: int, y0: int, z0: int, voxel: float,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, infos: PackedVector2Array) -> void:
	for z in range(z0, z0 + BRICK):
		for x in range(x0, x0 + BRICK):
			var i := (y0 + 1) + (x + 1) * _stride_x + (z + 1) * _stride_z
			for y in range(y0, y0 + BRICK):
				var b := blocks[i]
				if b > Blocks.BEDROCK:
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
						var p: Array[Vector3] = [(base + _corner_pos[ci]) * voxel, (base + _corner_pos[ci + 1]) * voxel, (base + _corner_pos[ci + 2]) * voxel, (base + _corner_pos[ci + 3]) * voxel]
						var c: Array[Color] = [col * _ao_levels[a0], col * _ao_levels[a1], col * _ao_levels[a2], col * _ao_levels[a3]]
						var normal := _normals[f]
						# Split the quad along its brighter diagonal so the shading stays smooth.
						for o in (SPLIT_A if a0 + a2 > a1 + a3 else SPLIT_B):
							verts.append(p[o])
							normals.append(normal)
							colors.append(c[o])
							infos.append(info)
				i += 1
