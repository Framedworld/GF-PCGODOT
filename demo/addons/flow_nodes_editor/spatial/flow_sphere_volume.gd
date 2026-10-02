@tool
class_name FlowSphereVolume
extends FlowSpatial

## Sphere volume (ellipsoid when `transform` scales non-uniformly) of `radius`
## around the local origin. sample_density: t = |local| / radius shaped by
## `steepness` (see FlowSpatial.falloff).

var transform : Transform3D
var radius : float = 0.5

var _inv : Transform3D
var _bounds : AABB
var _uniform_scale : float = 0.0	# > 0 when the transform scales uniformly (a true sphere)

func _init( xform : Transform3D = Transform3D.IDENTITY, sphere_radius : float = 0.5, sphere_steepness : float = 1.0 ) -> void:
	transform = xform
	radius = maxf( 0.0, sphere_radius )
	steepness = clampf( sphere_steepness, 0.0, 1.0 )
	_inv = transform.affine_inverse()
	_bounds = transform * AABB( -Vector3.ONE * radius, Vector3.ONE * radius * 2.0 )
	var sx := transform.basis.x.length()
	if sx > 0.0 and absf( transform.basis.y.length() - sx ) <= sx * 1e-5 and absf( transform.basis.z.length() - sx ) <= sx * 1e-5 \
			and absf( transform.basis.x.dot( transform.basis.y ) ) <= sx * sx * 1e-5 \
			and absf( transform.basis.y.dot( transform.basis.z ) ) <= sx * sx * 1e-5 \
			and absf( transform.basis.x.dot( transform.basis.z ) ) <= sx * sx * 1e-5:
		_uniform_scale = sx
	_hash = hash( [ "sphere", FlowSpatial.hash_transform( transform ), radius, steepness ] )

static func at( center : Vector3, sphere_radius : float, sphere_steepness : float = 1.0 ) -> FlowSphereVolume:
	return FlowSphereVolume.new( Transform3D( Basis.IDENTITY, center ), sphere_radius, sphere_steepness )

func get_kind() -> int:
	return FlowData.Kind.Volume

func get_type_name() -> String:
	return "Sphere Volume"

func get_bounds() -> AABB:
	return _bounds

func sample_density( world_pos : Vector3 ) -> float:
	if radius <= 0.0:
		return 0.0
	return FlowSpatial.falloff( ( _inv * world_pos ).length() / radius, steepness )

## BoundsBox overlap (see FlowSpatial.box_overlap). For a true sphere (uniform
## scale, any rotation) the peak is exact: the density at the point of the box
## nearest to the centre. The coverage (box-sphere intersection volume has no
## simple closed form) comes from the fixed sample set, capped by the peak.
## Ellipsoids use the sample set for both.
func box_overlap( box_min : Vector3, box_max : Vector3 ) -> Vector2:
	if _uniform_scale <= 0.0 or radius <= 0.0:
		return super.box_overlap( box_min, box_max )
	var c := transform.origin
	var nearest := Vector3( clampf( c.x, box_min.x, box_max.x ), clampf( c.y, box_min.y, box_max.y ), clampf( c.z, box_min.z, box_max.z ) )
	var peak := FlowSpatial.falloff( nearest.distance_to( c ) / ( _uniform_scale * radius ), steepness )
	if peak <= 0.0:
		return Vector2.ZERO
	var sampled := FlowSpatial.box_overlap_sampled( self, box_min, box_max )
	return Vector2( peak, minf( sampled.y, peak ) )
