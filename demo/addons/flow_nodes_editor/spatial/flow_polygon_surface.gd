@tool
class_name FlowPolygonSurface
extends FlowSpatial

## A flat surface bounded by a closed polygon (UE `UPCGPolygon2DData` /
## Create Surface From Spline). The polygon lives on the local XZ plane at local
## height `height`; `transform` maps local space to world space.
##
## Density is 1 inside the polygon footprint and 0 outside. With
## `vertical_tolerance` <= 0 (default) the footprint extends infinitely along the
## local Y axis, so "inside the polygon" means inside its XZ outline whatever the
## height: this is what lets Intersection(landscape, polygon) sample terrain inside
## a closed spline. A positive tolerance limits density to |y - height| <= tolerance.
##
## Point-in-polygon tests use Z bands (each band lists the edges that cross it),
## so a query tests only the edges near it, not all of them.

var polygon : PackedVector2Array
var transform : Transform3D
var height : float = 0.0
var vertical_tolerance : float = -1.0

var _inv : Transform3D
var _bounds : AABB
var _local_rect : Rect2
var _band_z0 : float = 0.0
var _band_size : float = 1.0
var _band_count : int = 0
var _band_starts := PackedInt32Array()
var _band_edges := PackedInt32Array()
var _area : float = 0.0

func _init( local_polygon : PackedVector2Array = PackedVector2Array(), xform : Transform3D = Transform3D.IDENTITY, local_height : float = 0.0, tolerance : float = -1.0 ) -> void:
	polygon = local_polygon.duplicate()
	# Drop a closing duplicate vertex.
	if polygon.size() > 1 and polygon[0].is_equal_approx( polygon[polygon.size() - 1] ):
		polygon.resize( polygon.size() - 1 )
	transform = xform
	height = local_height
	vertical_tolerance = tolerance
	_inv = transform.affine_inverse()
	_build()
	_hash = hash( [ "polygon_surface", polygon, FlowSpatial.hash_transform( transform ), height, vertical_tolerance ] )

## Polygon from world-space points (a closed outline) projected on the plane
## chosen by `plane` (0 = XZ, 1 = XY, 2 = YZ, matching create_surface_* ePlane).
## The surface height is the mean of the points along the plane normal.
static func from_world_points( points : PackedVector3Array, plane : int = 0 ) -> FlowPolygonSurface:
	var basis := plane_basis( plane )
	var xform := Transform3D( basis, Vector3.ZERO )
	var inv := xform.affine_inverse()
	var poly := PackedVector2Array()
	var h := 0.0
	for p in points:
		var l : Vector3 = inv * p
		poly.append( Vector2( l.x, l.z ) )
		h += l.y
	if points.size() > 0:
		h /= points.size()
	return FlowPolygonSurface.new( poly, xform, h )

## Local->world basis mapping the local XZ plane onto the requested world plane
## (0 = XZ identity, 1 = XY, 2 = YZ). Right handed in every case.
static func plane_basis( plane : int ) -> Basis:
	match plane:
		1:
			return Basis( Vector3( 1, 0, 0 ), Vector3( 0, 0, -1 ), Vector3( 0, 1, 0 ) )
		2:
			return Basis( Vector3( 0, 1, 0 ), Vector3( -1, 0, 0 ), Vector3( 0, 0, 1 ) )
		_:
			return Basis.IDENTITY

func _build() -> void:
	var n := polygon.size()
	if n == 0:
		_bounds = AABB( transform.origin, Vector3.ZERO )
		return
	var mn := polygon[0]
	var mx := polygon[0]
	var area2 := 0.0
	for i in range( n ):
		mn = mn.min( polygon[i] )
		mx = mx.max( polygon[i] )
		var a := polygon[i]
		var b := polygon[( i + 1 ) % n]
		area2 += a.x * b.y - b.x * a.y
	_area = absf( area2 ) * 0.5
	_local_rect = Rect2( mn, mx - mn )
	# World bounds of the outline (at the surface height).
	_bounds = AABB()
	for i in range( n ):
		var w := transform * Vector3( polygon[i].x, height, polygon[i].y )
		_bounds = AABB( w, Vector3.ZERO ) if i == 0 else _bounds.expand( w )
	# Z bands for the point-in-polygon test.
	_band_count = clampi( int( sqrt( float( n ) ) ) * 2, 1, 1024 )
	_band_z0 = mn.y
	_band_size = maxf( ( mx.y - mn.y ) / _band_count, 1e-6 )
	var per_band : Array = []
	per_band.resize( _band_count )
	for b in range( _band_count ):
		per_band[b] = PackedInt32Array()
	for i in range( n ):
		var a := polygon[i]
		var c := polygon[( i + 1 ) % n]
		var b0 := clampi( int( floor( ( minf( a.y, c.y ) - _band_z0 ) / _band_size ) ), 0, _band_count - 1 )
		var b1 := clampi( int( floor( ( maxf( a.y, c.y ) - _band_z0 ) / _band_size ) ), 0, _band_count - 1 )
		for b in range( b0, b1 + 1 ):
			per_band[b].append( i )
	_band_starts.resize( _band_count + 1 )
	_band_starts[0] = 0
	for b in range( _band_count ):
		_band_starts[b + 1] = _band_starts[b] + per_band[b].size()
		_band_edges.append_array( per_band[b] )

func get_kind() -> int:
	return FlowData.Kind.Surface

func get_type_name() -> String:
	return "Polygon Surface"

func get_bounds() -> AABB:
	return _bounds

## Polygon area in local units.
func get_area() -> float:
	return _area

## Number of polygon edges a point-in-polygon test at local (x, z) examines.
## Exposed for the scaling tests (must not grow with the full edge count).
func count_edge_tests( local_x : float, local_z : float ) -> int:
	if _band_count == 0:
		return 0
	var b := clampi( int( floor( ( local_z - _band_z0 ) / _band_size ) ), 0, _band_count - 1 )
	return _band_starts[b + 1] - _band_starts[b]

## Even-odd test of local (x, z) against the polygon, using the Z band edges only.
func contains_local( lx : float, lz : float ) -> bool:
	var n := polygon.size()
	if n < 3 or not _local_rect.grow( 1e-6 ).has_point( Vector2( lx, lz ) ):
		return false
	var b := clampi( int( floor( ( lz - _band_z0 ) / _band_size ) ), 0, _band_count - 1 )
	var inside := false
	for k in range( _band_starts[b], _band_starts[b + 1] ):
		var i := _band_edges[k]
		var p := polygon[i]
		var q := polygon[( i + 1 ) % n]
		if ( p.y > lz ) != ( q.y > lz ):
			var x_cross := p.x + ( lz - p.y ) * ( q.x - p.x ) / ( q.y - p.y )
			if lx < x_cross:
				inside = not inside
	return inside

func sample_density( world_pos : Vector3 ) -> float:
	var l := _inv * world_pos
	if vertical_tolerance > 0.0 and absf( l.y - height ) > vertical_tolerance:
		return 0.0
	return 1.0 if contains_local( l.x, l.z ) else 0.0

func _hit_local( lx : float, lz : float ) -> Dictionary:
	if not contains_local( lx, lz ):
		return {}
	return {
		"position": transform * Vector3( lx, height, lz ),
		"normal": FlowSpatial.transform_normal( transform, Vector3.UP ),
		"density": 1.0,
	}

## Projects along the surface's local Y axis onto the polygon plane.
func project( world_pos : Vector3 ) -> Dictionary:
	var l := _inv * world_pos
	return _hit_local( l.x, l.z )

## Intersection of the world vertical through (x, z) with the polygon plane.
## Vertical planes (XY / YZ polygons) have no such hit and return {}.
func project_vertical( x : float, z : float ) -> Dictionary:
	var n := FlowSpatial.transform_normal( transform, Vector3.UP )
	if absf( n.y ) < 1e-6:
		return {}
	var p0 := transform * Vector3( 0.0, height, 0.0 )
	var y := p0.y - ( n.x * ( x - p0.x ) + n.z * ( z - p0.z ) ) / n.y
	var l := _inv * Vector3( x, y, z )
	return _hit_local( l.x, l.z )
