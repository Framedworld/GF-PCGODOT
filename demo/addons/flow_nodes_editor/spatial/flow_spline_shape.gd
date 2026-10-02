@tool
class_name FlowSplineShape
extends FlowSpatial

## Spline data (UE `UPCGSplineData`): a private copy of a Curve3D plus its
## local-to-world transform and closed flag.
##
## As a spatial shape a spline is a tube of radius `half_width` around the curve:
## sample_density is 1 on the curve and falls off with `steepness` (1 = hard tube),
## which is what Difference / Intersection against a spline use (UE treats a spline
## as a volume of its point bounds). to_points() samples along the curve.
##
## The curve is duplicated and baked in the constructor; queries never touch the
## source Path3D or its Curve3D, and never re-bake.

var curve : Curve3D
var transform : Transform3D
var closed : bool = false
var half_width : float = 1.0

var _inv : Transform3D
var _length : float = 0.0
var _bounds : AABB
## World-space baked polyline, kept only when `transform` is not conformal
## (non-uniform scale or shear): the closest point in curve space is then not
## the closest point in world space.
var _world_baked := PackedVector3Array()

## `source_curve` is copied; `xform` maps curve space to world space.
## `is_closed` defaults to the curve's own `closed` flag when it has one.
func _init( source_curve : Curve3D = null, xform : Transform3D = Transform3D.IDENTITY, is_closed = null, tube_half_width : float = 1.0, tube_steepness : float = 1.0 ) -> void:
	curve = source_curve.duplicate( true ) if source_curve != null else Curve3D.new()
	transform = xform
	if is_closed == null:
		var c = curve.get( "closed" )
		closed = bool( c ) if c != null else false
	else:
		closed = bool( is_closed )
		if "closed" in curve:
			curve.set( "closed", closed )
	half_width = maxf( 0.0, tube_half_width )
	steepness = clampf( tube_steepness, 0.0, 1.0 )
	_inv = transform.affine_inverse()
	# Bake now so every later read is a pure read (thread safe, no lazy re-bake).
	_length = curve.get_baked_length()
	var baked := curve.get_baked_points()
	_bounds = AABB()
	for i in range( baked.size() ):
		var w := transform * baked[i]
		if i == 0:
			_bounds = AABB( w, Vector3.ZERO )
		else:
			_bounds = _bounds.expand( w )
	if not FlowSplineShape.is_conformal( transform.basis ):
		_world_baked.resize( baked.size() )
		for i in range( baked.size() ):
			_world_baked[i] = transform * baked[i]
	if baked.size() > 0:
		# An empty curve has no density anywhere: keep its bounds empty.
		_bounds = _bounds.grow( half_width )
	var pts := []
	for i in range( curve.point_count ):
		pts.append( [ curve.get_point_position( i ), curve.get_point_in( i ), curve.get_point_out( i ), curve.get_point_tilt( i ) ] )
	_hash = hash( [ "spline", pts, curve.bake_interval, curve.up_vector_enabled, closed, FlowSpatial.hash_transform( transform ), half_width, steepness ] )

## Builds a spline shape from a Path3D (world transform when inside the tree).
static func from_path( path : Path3D, tube_half_width : float = 1.0, tube_steepness : float = 1.0 ) -> FlowSplineShape:
	if path == null or path.curve == null:
		return null
	var xform : Transform3D = path.global_transform if path.is_inside_tree() else path.transform
	return FlowSplineShape.new( path.curve, xform, null, tube_half_width, tube_steepness )

func get_kind() -> int:
	return FlowData.Kind.Spline

func get_type_name() -> String:
	return "Spline"

func get_bounds() -> AABB:
	return _bounds

func get_length() -> float:
	return _length

## True when `b` is a rotation (or mirror) times a uniform scale, so distances
## in curve space are proportional to world distances.
static func is_conformal( b : Basis ) -> bool:
	var sx := b.x.length()
	if sx <= 0.0:
		return false
	var tol := sx * sx * 1e-5
	return absf( b.y.length_squared() - sx * sx ) <= tol and absf( b.z.length_squared() - sx * sx ) <= tol \
		and absf( b.x.dot( b.y ) ) <= tol and absf( b.y.dot( b.z ) ) <= tol and absf( b.x.dot( b.z ) ) <= tol

## Closest world-space point on the curve.
func closest_point( world_pos : Vector3 ) -> Vector3:
	if curve.point_count == 0:
		return transform.origin
	if _world_baked.size() == 1:
		return _world_baked[0]
	if _world_baked.size() > 1:
		# Non-conformal transform: search the world-space polyline.
		var best := _world_baked[0]
		var best_d2 := INF
		for i in range( _world_baked.size() - 1 ):
			var q := Geometry3D.get_closest_point_to_segment( world_pos, _world_baked[i], _world_baked[i + 1] )
			var d2 := world_pos.distance_squared_to( q )
			if d2 < best_d2:
				best_d2 = d2
				best = q
		return best
	return transform * curve.get_closest_point( _inv * world_pos )

func sample_density( world_pos : Vector3 ) -> float:
	if curve.point_count == 0:
		return 0.0
	if half_width <= 0.0:
		return 0.0
	var d := world_pos.distance_to( closest_point( world_pos ) )
	return FlowSpatial.falloff( d / half_width, steepness )

## Distance-along-curve sample as a world transform (rotation from the curve).
func sample_transform( offset : float ) -> Transform3D:
	var t := curve.sample_baked_with_rotation( offset )
	return Transform3D( transform.basis * t.basis, transform * t.origin )

## World-space polyline of the curve (tessellated, closed curves include the
## closing point when Curve3D supports `closed`).
func world_polyline( max_stages : int = 5, tolerance_degrees : float = 4.0 ) -> PackedVector3Array:
	var pts := curve.tessellate( max_stages, tolerance_degrees )
	for i in range( pts.size() ):
		pts[i] = transform * pts[i]
	return pts

## Samples along the curve. Settings: interval (1.0), seed (0).
## Each point carries the curve rotation, unit scale, bounds of `interval`,
## density 1 and a position seed.
func to_points( settings : Dictionary = {} ) -> FlowData.Data:
	var interval := maxf( 0.01, float( settings.get( "interval", 1.0 ) ) )
	var node_seed := int( settings.get( "seed", 0 ) )
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	if curve.point_count > 0:
		var n := int( floor( _length / interval ) ) + 1
		for i in range( n ):
			var t := sample_transform( minf( i * interval, _length ) )
			positions.append( t.origin )
			rotations.append( FlowData.basisToEuler( t.basis.orthonormalized() ) )
	return FlowSpatial.make_points_data( positions, rotations, PackedVector3Array(), PackedFloat32Array(), Vector3.ONE * interval, node_seed )
