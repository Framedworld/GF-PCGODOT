@tool
class_name FlowDebugShapes
extends RefCounted

## Data preparation for the viewport debug draw (node_draw_debug.gd): turns a
## FlowData.Data into world-space line segments with per-vertex colours. Pure
## functions, no RenderingServer, so the geometry can be checked numerically;
## NodeDrawDebug only uploads the result as one PRIMITIVE_LINES mesh.
##
## What is drawn:
## - Spline shapes: the polyline of the curve's baked points, through the
##   shape's transform (closed curves are closed).
## - Box volumes: the 12 edges of the oriented box. Sphere volumes: three great
##   circles (an ellipsoid when the transform scales).
## - Polygon surfaces: the outline at the polygon's height.
## - Heightfield surfaces: the border plus a coarse grid along the heights.
## - Mesh surfaces: the bounds box plus a coarse grid of vertical hits.
## - Mesh volumes: triangle edges (or the bounds box when there are too many).
## - Points volumes: one axis-aligned box per point.
## - Composites: both operands, B tinted by the operation, plus a combining
##   indicator: the composite's bounds as a dashed box with an operation glyph
##   on top (Union "+", Intersection "x", Difference "-") in the operation colour.
## - Unknown FlowSpatial subclasses: their bounds box.
## - Points with bounds_min and bounds_max streams: one box per point
##   (EXTENDS debug mode only), oriented by the point rotation, coloured like
##   the point cubes, the inspected row in the selection colour.
##
## Draw cost is bounded by the caps below. When a cap is hit the geometry is
## subsampled (splines, outlines, grids) or dropped (point boxes, triangle
## edges), and Lines.truncated / Lines.notes say so.

## Total line segments for one node's debug draw.
const MAX_SEGMENTS := 65536
## Polyline vertices per spline (baked points are subsampled above this).
const MAX_SPLINE_POINTS := 2048
## Outline vertices per polygon or heightfield border side.
const MAX_OUTLINE_POINTS := 2048
## Segments per great circle of a sphere.
const CIRCLE_SEGMENTS := 48
## Grid lines per axis on heightfield and mesh surfaces (so at most
## (SURFACE_GRID + 1)^2 samples and 2 * SURFACE_GRID * (SURFACE_GRID + 1) segments).
const SURFACE_GRID := 24
## Points per heightfield grid line (the line follows the relief between the
## coarse lines with up to this many height samples).
const HEIGHTFIELD_LINE_POINTS := 256
## Triangle edges drawn for a mesh volume; above it only the bounds box is drawn.
const MAX_MESH_EDGES := 6000
## Per-point boxes (bounds boxes of points, boxes of a points volume).
const MAX_POINT_BOXES := 4096
## Composite nesting drawn (deeper operands are drawn as their bounds box).
const MAX_COMPOSITE_DEPTH := 8

const OP_COLORS := {
	FlowSpatial.Op.Union: Color( 0.35, 0.95, 0.45 ),
	FlowSpatial.Op.Intersection: Color( 1.0, 0.85, 0.2 ),
	FlowSpatial.Op.Difference: Color( 1.0, 0.35, 0.35 ),
}

## Line segments with one colour per vertex, filled under a segment cap.
class Lines:
	extends RefCounted
	## Two vertices per segment.
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	var max_segments : int = FlowDebugShapes.MAX_SEGMENTS
	## True when a cap dropped or subsampled geometry.
	var truncated : bool = false
	## Segments per category ("spline", "box", "sphere", "polygon",
	## "heightfield", "mesh_surface", "mesh_volume", "points_volume",
	## "composite", "point_bounds", "bounds").
	var counts : Dictionary = {}
	## Human-readable reasons for truncation.
	var notes : PackedStringArray = PackedStringArray()

	func segment_count() -> int:
		return points.size() / 2

	func is_full() -> bool:
		return segment_count() >= max_segments

	## Adds one segment. Returns false (and marks truncated) when full.
	func add( a : Vector3, b : Vector3, color : Color, category : String ) -> bool:
		if is_full():
			if not truncated:
				notes.append( "segment cap %d reached" % max_segments )
			truncated = true
			return false
		points.append( a )
		points.append( b )
		colors.append( color )
		colors.append( color )
		counts[category] = int( counts.get( category, 0 ) ) + 1
		return true

	## Adds a polyline (consecutive points). Returns false when it was cut.
	func add_polyline( pts : PackedVector3Array, color : Color, category : String, closed : bool = false ) -> bool:
		for i in range( pts.size() - 1 ):
			if not add( pts[i], pts[i + 1], color, category ):
				return false
		if closed and pts.size() > 2 and not pts[pts.size() - 1].is_equal_approx( pts[0] ):
			return add( pts[pts.size() - 1], pts[0], color, category )
		return true

	func note( text : String ) -> void:
		truncated = true
		notes.append( text )

# --- Entry point -----------------------------------------------------------------

## Builds the debug lines of `data`. Options:
##   color : Color            colour of shapes (debug_color)
##   draw_point_bounds : bool per-point bounds boxes (default true; NodeDrawDebug
##                            passes false outside EXTENDS mode)
##   point_colors : PackedColorArray  colour per point for bounds boxes
##                            (missing entries use `color`)
##   selected_row : int       point drawn in `selection_color` (-1 = none)
##   selection_color : Color
##   max_segments : int       overrides MAX_SEGMENTS
static func build_for_data( data : FlowData.Data, options : Dictionary = {} ) -> Lines:
	var lines := Lines.new()
	lines.max_segments = int( options.get( "max_segments", MAX_SEGMENTS ) )
	if data == null:
		return lines
	var color : Color = options.get( "color", Color.WHITE )
	if data.shape != null:
		add_shape( lines, data.shape, color )
	if bool( options.get( "draw_point_bounds", true ) ) and has_point_bounds( data ):
		add_point_bounds( lines, data, options.get( "point_colors", PackedColorArray() ), color, int( options.get( "selected_row", -1 ) ), options.get( "selection_color", Color.MAGENTA ) )
	return lines

## True when the Data has both bounds streams and positions.
static func has_point_bounds( data : FlowData.Data ) -> bool:
	return data != null and data.size() > 0 and data.hasStream( FlowData.AttrPosition ) and data.streams.has( FlowData.AttrBoundsMin ) and data.streams.has( FlowData.AttrBoundsMax )

# --- Shapes ----------------------------------------------------------------------

## Adds the lines of one shape (recursing into composites).
static func add_shape( lines : Lines, shape : FlowSpatial, color : Color, depth : int = 0 ) -> void:
	if shape == null:
		return
	if shape is FlowCompositeShape:
		_add_composite( lines, shape, color, depth )
	elif shape is FlowSplineShape:
		var poly := spline_polyline( shape )
		if poly.size() < 2 and shape.curve.point_count == 1:
			# A one-point curve: a small cross at the point.
			_add_cross( lines, shape.transform * shape.curve.get_point_position( 0 ), 0.25, color, "spline" )
		else:
			lines.add_polyline( poly, color, "spline", shape.closed )
	elif shape is FlowBoxVolume:
		add_box( lines, shape.transform, shape.half_extents, color, "box" )
	elif shape is FlowSphereVolume:
		for poly in sphere_circles( shape.transform, shape.radius ):
			lines.add_polyline( poly, color, "sphere", false )
	elif shape is FlowPolygonSurface:
		lines.add_polyline( polygon_outline( shape, lines ), color, "polygon", true )
	elif shape is FlowHeightfieldSurface:
		for poly in heightfield_polylines( shape, lines ):
			lines.add_polyline( poly, color, "heightfield", false )
	elif shape is FlowMeshSurface:
		add_aabb( lines, shape.get_bounds(), color.darkened( 0.4 ), "mesh_surface" )
		for poly in surface_grid_polylines( shape, shape.get_bounds() ):
			lines.add_polyline( poly, color, "mesh_surface", false )
	elif shape is FlowMeshVolume:
		_add_mesh_volume( lines, shape, color )
	elif shape is FlowPointsVolume:
		var n : int = shape.get_point_count()
		if n > MAX_POINT_BOXES:
			lines.note( "points volume: %d of %d boxes drawn" % [ MAX_POINT_BOXES, n ] )
		for i in range( mini( n, MAX_POINT_BOXES ) ):
			add_aabb( lines, AABB( shape.box_min[i], shape.box_max[i] - shape.box_min[i] ), color, "points_volume" )
	else:
		add_aabb( lines, shape.get_bounds(), color, "bounds" )

static func _add_composite( lines : Lines, shape : FlowCompositeShape, color : Color, depth : int ) -> void:
	var op_color : Color = OP_COLORS.get( shape.op, Color.WHITE )
	op_color.a = color.a
	if depth >= MAX_COMPOSITE_DEPTH:
		lines.note( "composite deeper than %d drawn as bounds" % MAX_COMPOSITE_DEPTH )
		add_aabb( lines, shape.get_bounds(), op_color, "composite" )
		return
	add_shape( lines, shape.a, color, depth + 1 )
	add_shape( lines, shape.b, color.lerp( op_color, 0.7 ), depth + 1 )
	add_combining_indicator( lines, shape.get_bounds(), shape.op, op_color )

## Dashed bounds box plus the operation glyph centred on its top face.
static func add_combining_indicator( lines : Lines, bounds : AABB, op : int, color : Color ) -> void:
	var corners := aabb_corners( bounds )
	for e in BOX_EDGES:
		_add_dashed( lines, corners[e[0]], corners[e[1]], color, "composite", 8 )
	var top := bounds.get_center() + Vector3( 0.0, bounds.size.y * 0.5, 0.0 )
	var s := maxf( 0.25, maxf( bounds.size.x, bounds.size.z ) * 0.08 )
	match op:
		FlowSpatial.Op.Union:
			lines.add( top - Vector3( s, 0, 0 ), top + Vector3( s, 0, 0 ), color, "composite" )
			lines.add( top - Vector3( 0, 0, s ), top + Vector3( 0, 0, s ), color, "composite" )
		FlowSpatial.Op.Intersection:
			lines.add( top + Vector3( -s, 0, -s ), top + Vector3( s, 0, s ), color, "composite" )
			lines.add( top + Vector3( -s, 0, s ), top + Vector3( s, 0, -s ), color, "composite" )
		_:
			lines.add( top - Vector3( s, 0, 0 ), top + Vector3( s, 0, 0 ), color, "composite" )

static func _add_dashed( lines : Lines, a : Vector3, b : Vector3, color : Color, category : String, dashes : int ) -> void:
	for i in range( dashes ):
		var t0 := float( 2 * i ) / float( 2 * dashes - 1 )
		var t1 := float( 2 * i + 1 ) / float( 2 * dashes - 1 )
		if not lines.add( a.lerp( b, t0 ), a.lerp( b, t1 ), color, category ):
			return

static func _add_cross( lines : Lines, p : Vector3, s : float, color : Color, category : String ) -> void:
	lines.add( p - Vector3( s, 0, 0 ), p + Vector3( s, 0, 0 ), color, category )
	lines.add( p - Vector3( 0, s, 0 ), p + Vector3( 0, s, 0 ), color, category )
	lines.add( p - Vector3( 0, 0, s ), p + Vector3( 0, 0, s ), color, category )

static func _add_mesh_volume( lines : Lines, shape : FlowMeshVolume, color : Color ) -> void:
	var grid : FlowTriangleGrid = shape.grid
	if grid == null or grid.tri_count * 3 > MAX_MESH_EDGES:
		if grid != null:
			lines.note( "mesh volume: %d triangles, drawn as bounds" % grid.tri_count )
		add_aabb( lines, shape.get_bounds(), color, "mesh_volume" )
		return
	var v := grid.vertices
	for t in range( grid.tri_count ):
		var a := v[3 * t]
		var b := v[3 * t + 1]
		var c := v[3 * t + 2]
		if not ( lines.add( a, b, color, "mesh_volume" ) and lines.add( b, c, color, "mesh_volume" ) and lines.add( c, a, color, "mesh_volume" ) ):
			return

## World-space polyline of a spline shape: the curve's baked points through the
## shape transform, subsampled to at most MAX_SPLINE_POINTS (first and last
## point always kept).
static func spline_polyline( shape : FlowSplineShape ) -> PackedVector3Array:
	var baked : PackedVector3Array = shape.curve.get_baked_points() if shape.curve != null else PackedVector3Array()
	var out := PackedVector3Array()
	var n := baked.size()
	if n == 0:
		return out
	var idx := _subsample_indices( n, MAX_SPLINE_POINTS )
	out.resize( idx.size() )
	for k in range( idx.size() ):
		out[k] = shape.transform * baked[idx[k]]
	return out

## Indices 0..n-1 subsampled to at most `cap`, keeping the first and the last.
static func _subsample_indices( n : int, cap : int ) -> PackedInt32Array:
	var out := PackedInt32Array()
	if n <= 0:
		return out
	if n <= cap or cap < 2:
		out.resize( n )
		for i in range( n ):
			out[i] = i
		return out
	out.resize( cap )
	for k in range( cap ):
		out[k] = int( round( float( k ) * float( n - 1 ) / float( cap - 1 ) ) )
	return out

## Box edges as corner index pairs (corners in aabb_corners / box_corners order:
## bit 0 = +x, bit 1 = +y, bit 2 = +z).
const BOX_EDGES := [
	[ 0, 1 ], [ 2, 3 ], [ 4, 5 ], [ 6, 7 ],
	[ 0, 2 ], [ 1, 3 ], [ 4, 6 ], [ 5, 7 ],
	[ 0, 4 ], [ 1, 5 ], [ 2, 6 ], [ 3, 7 ],
]

## The 8 corners of the box [-half, half] mapped by `xform`.
static func box_corners( xform : Transform3D, half : Vector3 ) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize( 8 )
	for i in range( 8 ):
		var l := Vector3( half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z )
		out[i] = xform * l
	return out

static func aabb_corners( aabb : AABB ) -> PackedVector3Array:
	return box_corners( Transform3D( Basis.IDENTITY, aabb.get_center() ), aabb.size * 0.5 )

static func add_box( lines : Lines, xform : Transform3D, half : Vector3, color : Color, category : String ) -> void:
	_add_corners( lines, box_corners( xform, half ), color, category )

static func add_aabb( lines : Lines, aabb : AABB, color : Color, category : String ) -> void:
	_add_corners( lines, aabb_corners( aabb ), color, category )

static func _add_corners( lines : Lines, corners : PackedVector3Array, color : Color, category : String ) -> void:
	for e in BOX_EDGES:
		if not lines.add( corners[e[0]], corners[e[1]], color, category ):
			return

## Three closed great circles (XY, XZ, YZ planes) of radius `radius` mapped by
## `xform`, each CIRCLE_SEGMENTS + 1 points (first point repeated at the end).
static func sphere_circles( xform : Transform3D, radius : float ) -> Array:
	var out := []
	for plane in range( 3 ):
		var poly := PackedVector3Array()
		poly.resize( CIRCLE_SEGMENTS + 1 )
		for k in range( CIRCLE_SEGMENTS + 1 ):
			var a := TAU * float( k % CIRCLE_SEGMENTS ) / float( CIRCLE_SEGMENTS )
			var c := cos( a ) * radius
			var s := sin( a ) * radius
			var l : Vector3
			match plane:
				0:
					l = Vector3( c, s, 0.0 )
				1:
					l = Vector3( c, 0.0, s )
				_:
					l = Vector3( 0.0, c, s )
			poly[k] = xform * l
		out.append( poly )
	return out

## World-space outline of a polygon surface at its height (closed by the
## caller), subsampled to MAX_OUTLINE_POINTS.
static func polygon_outline( shape : FlowPolygonSurface, lines : Lines = null ) -> PackedVector3Array:
	var n := shape.polygon.size()
	if n > MAX_OUTLINE_POINTS and lines != null:
		lines.note( "polygon outline: %d of %d vertices drawn" % [ MAX_OUTLINE_POINTS, n ] )
	var idx := _subsample_indices( n, MAX_OUTLINE_POINTS )
	var out := PackedVector3Array()
	out.resize( idx.size() )
	for k in range( idx.size() ):
		var p := shape.polygon[idx[k]]
		out[k] = shape.transform * Vector3( p.x, shape.height, p.y )
	return out

## SURFACE_GRID + 1 lines along each local axis (the first and last of each set
## form the border), each following the heights with at most
## HEIGHTFIELD_LINE_POINTS samples. World space.
static func heightfield_polylines( shape : FlowHeightfieldSurface, lines : Lines = null ) -> Array:
	var out := []
	var w := shape.width
	var d := shape.depth
	if w < 2 or d < 2:
		return out
	# Grid lines (and the border, which is the first and last line of each set).
	var cols := _grid_line_indices( w )
	var rows := _grid_line_indices( d )
	var along_x := _subsample_indices( w, HEIGHTFIELD_LINE_POINTS )
	var along_z := _subsample_indices( d, HEIGHTFIELD_LINE_POINTS )
	if ( w > HEIGHTFIELD_LINE_POINTS or d > HEIGHTFIELD_LINE_POINTS ) and lines != null:
		lines.note( "heightfield %dx%d: grid lines subsampled to %d points" % [ w, d, HEIGHTFIELD_LINE_POINTS ] )
	for j in rows:
		var poly := PackedVector3Array()
		for i in along_x:
			poly.append( _heightfield_point( shape, i, j ) )
		out.append( poly )
	for i in cols:
		var poly := PackedVector3Array()
		for j in along_z:
			poly.append( _heightfield_point( shape, i, j ) )
		out.append( poly )
	return out

## Sample indices of the coarse grid lines: SURFACE_GRID + 1 evenly spaced
## indices including 0 and n - 1 (all of them when n is smaller).
static func _grid_line_indices( n : int ) -> PackedInt32Array:
	return _subsample_indices( n, SURFACE_GRID + 1 )

static func _heightfield_point( shape : FlowHeightfieldSurface, i : int, j : int ) -> Vector3:
	var l := shape.origin + Vector3( i * shape.cell_size, shape.get_height( i, j ), j * shape.cell_size )
	return shape.transform * l

## Coarse grid of vertical hits over `bounds` (SURFACE_GRID + 1 lines per
## axis): each polyline runs along one grid line and is split where the
## surface is missed. World space.
static func surface_grid_polylines( shape : FlowSpatial, bounds : AABB ) -> Array:
	var out := []
	var n := SURFACE_GRID
	var hits := []
	hits.resize( ( n + 1 ) * ( n + 1 ) )
	for j in range( n + 1 ):
		for i in range( n + 1 ):
			var x := bounds.position.x + bounds.size.x * float( i ) / float( n )
			var z := bounds.position.z + bounds.size.z * float( j ) / float( n )
			var hit : Dictionary = shape.project_vertical( x, z )
			hits[j * ( n + 1 ) + i] = hit.position if not hit.is_empty() else null
	for j in range( n + 1 ):
		_append_runs( out, hits, func( k ): return j * ( n + 1 ) + k, n + 1 )
	for i in range( n + 1 ):
		_append_runs( out, hits, func( k ): return k * ( n + 1 ) + i, n + 1 )
	return out

static func _append_runs( out : Array, hits : Array, index_of : Callable, count : int ) -> void:
	var run := PackedVector3Array()
	for k in range( count ):
		var p = hits[index_of.call( k )]
		if p == null:
			if run.size() >= 2:
				out.append( run )
			run = PackedVector3Array()
		else:
			run.append( p )
	if run.size() >= 2:
		out.append( run )

# --- Points ----------------------------------------------------------------------

## One box per point (at most MAX_POINT_BOXES) from the local bounds_min /
## bounds_max corners, rotated by the point rotation and placed at its position
## (the size stream does not scale them: with bounds streams present the
## bounds are the point's extents, as getEffectiveBounds reads them).
static func add_point_bounds( lines : Lines, data : FlowData.Data, point_colors : PackedColorArray, color : Color, selected_row : int = -1, selection_color : Color = Color.MAGENTA ) -> void:
	var boxes := point_bounds_boxes( data, MAX_POINT_BOXES )
	var n := data.size()
	if n > MAX_POINT_BOXES:
		lines.note( "point bounds: %d of %d boxes drawn" % [ MAX_POINT_BOXES, n ] )
	for i in range( boxes.size() ):
		var c : Color = point_colors[i] if i < point_colors.size() else color
		if i == selected_row:
			c = selection_color
		var box : Dictionary = boxes[i]
		_add_corners( lines, box.corners, c, "point_bounds" )
		if lines.is_full():
			return
	# The selected row past the cap is still drawn.
	if selected_row >= boxes.size() and selected_row < n:
		var extra := point_bounds_boxes( data, 1, selected_row )
		if not extra.is_empty():
			_add_corners( lines, extra[0].corners, selection_color, "point_bounds" )

## Per-point boxes: [{ index, corners (8 world points) }] for points
## first .. first + max_count - 1.
static func point_bounds_boxes( data : FlowData.Data, max_count : int, first : int = 0 ) -> Array:
	var out := []
	if not has_point_bounds( data ):
		return out
	var positions := data.getVector3Container( FlowData.AttrPosition )
	var bounds := data.getEffectiveBounds()
	var bmin : PackedVector3Array = bounds.min
	var bmax : PackedVector3Array = bounds.max
	var trs = data.getTransformsStream()
	var end := mini( positions.size(), first + max_count )
	for i in range( first, end ):
		var basis := Basis.IDENTITY
		if trs != null and i < trs.size():
			basis = trs.basisAt( i )
		var lo : Vector3 = bmin[i]
		var hi : Vector3 = bmax[i]
		var center := ( lo + hi ) * 0.5
		var xform := Transform3D( basis, positions[i] ) * Transform3D( Basis.IDENTITY, center )
		out.append( { "index": i, "corners": box_corners( xform, ( hi - lo ).abs() * 0.5 ) } )
	return out
