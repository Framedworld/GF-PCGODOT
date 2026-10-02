@tool
class_name FlowTriangleGrid
extends RefCounted

## Immutable triangle soup with a uniform XZ acceleration grid (compressed sparse
## rows: cell -> triangle ids). Shared by FlowMeshSurface and FlowMeshVolume.
##
## Every triangle is registered in each grid cell its XZ bounding rectangle
## overlaps. The cell size targets about two triangles per cell, so:
##  * a vertical query (column hits, inside-parity) tests the triangles of ONE
##    cell, independent of the total triangle count;
##  * a nearest-point query walks rings of cells outwards and stops as soon as the
##    best distance found is below the ring's lower bound.
## count_column_candidates() exposes the per-query work so tests can assert it
## does not scale with the mesh size.

const MAX_CELLS_PER_AXIS := 1024

var vertices : PackedVector3Array	# world space, three per triangle
var normals : PackedVector3Array	# one per triangle (unit, raw winding)
var tri_count : int = 0
var bounds : AABB

var _x0 : float = 0.0
var _z0 : float = 0.0
var _cell : float = 1.0
var _nx : int = 1
var _nz : int = 1
var _cell_starts := PackedInt32Array()
var _cell_tris := PackedInt32Array()
var _cell_ymin := PackedFloat32Array()	# height range of the triangles in each cell
var _cell_ymax := PackedFloat32Array()

func _init( world_vertices : PackedVector3Array = PackedVector3Array() ) -> void:
	var n := world_vertices.size() - world_vertices.size() % 3
	vertices = world_vertices.slice( 0, n )
	tri_count = n / 3
	normals.resize( tri_count )
	for t in range( tri_count ):
		var a := vertices[t * 3]
		var nrm := ( vertices[t * 3 + 1] - a ).cross( vertices[t * 3 + 2] - a )
		normals[t] = nrm.normalized() if nrm.length_squared() > 1e-24 else Vector3.UP
	_build()

func _build() -> void:
	if tri_count == 0:
		bounds = AABB()
		_cell_starts = PackedInt32Array( [ 0, 0 ] )
		return
	bounds = AABB( vertices[0], Vector3.ZERO )
	for v in vertices:
		bounds = bounds.expand( v )
	var sx := maxf( bounds.size.x, 1e-4 )
	var sz := maxf( bounds.size.z, 1e-4 )
	var target_cells := maxf( 1.0, tri_count / 2.0 )
	_cell = maxf( sqrt( sx * sz / target_cells ), 1e-4 )
	_nx = clampi( int( ceil( sx / _cell ) ), 1, MAX_CELLS_PER_AXIS )
	_nz = clampi( int( ceil( sz / _cell ) ), 1, MAX_CELLS_PER_AXIS )
	_cell = maxf( sx / _nx, sz / _nz )
	_x0 = bounds.position.x
	_z0 = bounds.position.z
	# Two passes: count, then fill (CSR layout).
	var counts := PackedInt32Array()
	counts.resize( _nx * _nz )
	counts.fill( 0 )
	var ranges := PackedInt32Array()
	ranges.resize( tri_count * 4 )
	for t in range( tri_count ):
		var a := vertices[t * 3]
		var b := vertices[t * 3 + 1]
		var c := vertices[t * 3 + 2]
		var ix0 := _cx( minf( a.x, minf( b.x, c.x ) ) )
		var ix1 := _cx( maxf( a.x, maxf( b.x, c.x ) ) )
		var iz0 := _cz( minf( a.z, minf( b.z, c.z ) ) )
		var iz1 := _cz( maxf( a.z, maxf( b.z, c.z ) ) )
		ranges[t * 4] = ix0
		ranges[t * 4 + 1] = ix1
		ranges[t * 4 + 2] = iz0
		ranges[t * 4 + 3] = iz1
		for iz in range( iz0, iz1 + 1 ):
			for ix in range( ix0, ix1 + 1 ):
				counts[iz * _nx + ix] += 1
	_cell_starts.resize( _nx * _nz + 1 )
	_cell_starts[0] = 0
	for i in range( _nx * _nz ):
		_cell_starts[i + 1] = _cell_starts[i] + counts[i]
	_cell_tris.resize( _cell_starts[_nx * _nz] )
	_cell_ymin.resize( _nx * _nz )
	_cell_ymax.resize( _nx * _nz )
	_cell_ymin.fill( INF )
	_cell_ymax.fill( -INF )
	var fill := _cell_starts.slice( 0, _nx * _nz )
	for t in range( tri_count ):
		var a := vertices[t * 3]
		var b := vertices[t * 3 + 1]
		var c := vertices[t * 3 + 2]
		var y0 := minf( a.y, minf( b.y, c.y ) )
		var y1 := maxf( a.y, maxf( b.y, c.y ) )
		for iz in range( ranges[t * 4 + 2], ranges[t * 4 + 3] + 1 ):
			for ix in range( ranges[t * 4], ranges[t * 4 + 1] + 1 ):
				var cell := iz * _nx + ix
				_cell_tris[fill[cell]] = t
				fill[cell] += 1
				_cell_ymin[cell] = minf( _cell_ymin[cell], y0 )
				_cell_ymax[cell] = maxf( _cell_ymax[cell], y1 )

func _cx( x : float ) -> int:
	return clampi( int( floor( ( x - _x0 ) / _cell ) ), 0, _nx - 1 )

func _cz( z : float ) -> int:
	return clampi( int( floor( ( z - _z0 ) / _cell ) ), 0, _nz - 1 )

func _in_xz( x : float, z : float ) -> bool:
	return x >= bounds.position.x - 1e-6 and x <= bounds.end.x + 1e-6 and z >= bounds.position.z - 1e-6 and z <= bounds.end.z + 1e-6

## Triangles a vertical query at (x, z) examines (0 outside the grid).
func count_column_candidates( x : float, z : float ) -> int:
	if tri_count == 0 or not _in_xz( x, z ):
		return 0
	var cell := _cz( z ) * _nx + _cx( x )
	return _cell_starts[cell + 1] - _cell_starts[cell]

## Height of triangle t on the vertical through (x, z), or NAN when the vertical
## misses it (or the triangle is vertical in XZ). Edges count as inside within a
## small tolerance (projection must not fall through seams); the parity test
## passes strict = true so a probe on a shared edge is not counted twice.
func _vertical_y( t : int, x : float, z : float, strict : bool = false ) -> float:
	var a := vertices[t * 3]
	var b := vertices[t * 3 + 1]
	var c := vertices[t * 3 + 2]
	var det := ( b.z - c.z ) * ( a.x - c.x ) + ( c.x - b.x ) * ( a.z - c.z )
	if absf( det ) < 1e-12:
		return NAN
	var l1 := ( ( b.z - c.z ) * ( x - c.x ) + ( c.x - b.x ) * ( z - c.z ) ) / det
	var l2 := ( ( c.z - a.z ) * ( x - c.x ) + ( a.x - c.x ) * ( z - c.z ) ) / det
	var l3 := 1.0 - l1 - l2
	var eps := 0.0 if strict else -1e-6
	if strict:
		if l1 <= 0.0 or l2 <= 0.0 or l3 <= 0.0:
			return NAN
	elif l1 < eps or l2 < eps or l3 < eps:
		return NAN
	return l1 * a.y + l2 * b.y + l3 * c.y

## Hit of the vertical through (x, z). `prefer` = "top" (highest y) or a float
## reference height (hit nearest to it). Returns { position, normal, tri } or {}.
## The normal is oriented upwards (+Y side).
func vertical_hit( x : float, z : float, reference_y = null ) -> Dictionary:
	if tri_count == 0 or not _in_xz( x, z ):
		return {}
	var cell := _cz( z ) * _nx + _cx( x )
	var best_t := -1
	var best_y := 0.0
	var best_score := INF
	for k in range( _cell_starts[cell], _cell_starts[cell + 1] ):
		var t := _cell_tris[k]
		var y := _vertical_y( t, x, z )
		if is_nan( y ):
			continue
		var score : float = -y if reference_y == null else absf( y - float( reference_y ) )
		if score < best_score:
			best_score = score
			best_y = y
			best_t = t
	if best_t < 0:
		return {}
	var n := normals[best_t]
	if n.y < 0.0:
		n = -n
	return { "position": Vector3( x, best_y, z ), "normal": n, "tri": best_t }

## Number of triangles crossed by the upward vertical from `p` (parity test for
## closed meshes). The probe is nudged by a tiny fixed skew so it never runs
## exactly along a shared edge.
func count_crossings_above( p : Vector3 ) -> int:
	var x := p.x + _cell * 1.2345e-4
	var z := p.z + _cell * 2.3456e-4
	if tri_count == 0 or not _in_xz( x, z ):
		return 0
	var cell := _cz( z ) * _nx + _cx( x )
	var crossings := 0
	for k in range( _cell_starts[cell], _cell_starts[cell + 1] ):
		var y := _vertical_y( _cell_tris[k], x, z, true )
		if not is_nan( y ) and y > p.y:
			crossings += 1
	return crossings

## Closest point on the mesh to `p`: { position, normal, distance, tri } or {}.
## The normal is oriented towards `p` (upwards when `p` is level with the
## face). Rings of cells are visited outwards from
## p's (clamped) cell. Two lower bounds keep the walk local:
##  * per cell: XZ distance to the cell rectangle and height distance to the
##    cell's triangle height range; cells that cannot beat the best are skipped;
##  * per ring: q = p projected onto the grid rectangle satisfies
##    |p - y|^2 >= |p - q|^2 + |q - y|^2 for every y in the rectangle, so ring r
##    is at least D0^2 + ((r - 1) * cell)^2 + dy0^2 away (D0: XZ distance to the
##    grid, dy0: height distance to the mesh). The walk stops when the best
##    distance is within that bound.
func nearest( p : Vector3 ) -> Dictionary:
	if tri_count == 0:
		return {}
	var cx := _cx( p.x )
	var cz := _cz( p.z )
	var qx := clampf( p.x, bounds.position.x, bounds.end.x )
	var qz := clampf( p.z, bounds.position.z, bounds.end.z )
	var d0_2 := ( p.x - qx ) * ( p.x - qx ) + ( p.z - qz ) * ( p.z - qz )
	var dy0 := maxf( 0.0, maxf( bounds.position.y - p.y, p.y - bounds.end.y ) )
	var base_2 := d0_2 + dy0 * dy0
	var best_d2 := INF
	var best_t := -1
	var best_p := Vector3.ZERO
	var max_ring := maxi( _nx, _nz )
	var seen := {}
	for r in range( 0, max_ring + 1 ):
		var ring := maxf( 0.0, ( r - 1 ) * _cell )
		if best_t >= 0 and best_d2 <= base_2 + ring * ring:
			break
		for iz in range( cz - r, cz + r + 1 ):
			if iz < 0 or iz >= _nz:
				continue
			for ix in range( cx - r, cx + r + 1 ):
				if ix < 0 or ix >= _nx:
					continue
				if r > 0 and absi( ix - cx ) != r and absi( iz - cz ) != r:
					continue
				var cell := iz * _nx + ix
				if _cell_starts[cell] == _cell_starts[cell + 1]:
					continue
				var x0 := _x0 + ix * _cell
				var z0 := _z0 + iz * _cell
				var ddx := maxf( 0.0, maxf( x0 - p.x, p.x - ( x0 + _cell ) ) )
				var ddz := maxf( 0.0, maxf( z0 - p.z, p.z - ( z0 + _cell ) ) )
				var ddy := maxf( 0.0, maxf( _cell_ymin[cell] - p.y, p.y - _cell_ymax[cell] ) )
				if ddx * ddx + ddy * ddy + ddz * ddz >= best_d2:
					continue
				for k in range( _cell_starts[cell], _cell_starts[cell + 1] ):
					var t := _cell_tris[k]
					if seen.has( t ):
						continue
					seen[t] = true
					var q := FlowSpatial.closest_point_on_triangle( p, vertices[t * 3], vertices[t * 3 + 1], vertices[t * 3 + 2] )
					var d2 := p.distance_squared_to( q )
					if d2 < best_d2:
						best_d2 = d2
						best_t = t
						best_p = q
	if best_t < 0:
		return {}
	var n := normals[best_t]
	var side := n.dot( p - best_p )
	if absf( side ) <= 1e-6 * maxf( 1.0, sqrt( best_d2 ) ):
		# p is level with the face (beside a flat mesh, or on it): no side to
		# face, so face up as vertical_hit does instead of following the winding.
		if n.y < 0.0:
			n = -n
	elif side < 0.0:
		n = -n
	return { "position": best_p, "normal": n, "distance": sqrt( best_d2 ), "tri": best_t }

## Hash of the triangle data (geometry only).
func geometry_hash() -> int:
	return hash( vertices )

## Total surface area of the triangles.
func total_area() -> float:
	var area := 0.0
	for t in range( tri_count ):
		var a := vertices[t * 3]
		area += ( vertices[t * 3 + 1] - a ).cross( vertices[t * 3 + 2] - a ).length() * 0.5
	return area

## Triangles (world space) of a Mesh under `xform`.
static func mesh_world_vertices( mesh : Mesh, xform : Transform3D ) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh == null:
		return out
	var faces := mesh.get_faces()
	out.resize( faces.size() )
	for i in range( faces.size() ):
		out[i] = xform * faces[i]
	return out
