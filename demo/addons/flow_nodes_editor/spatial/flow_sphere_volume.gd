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

func _init( xform : Transform3D = Transform3D.IDENTITY, sphere_radius : float = 0.5, sphere_steepness : float = 1.0 ) -> void:
	transform = xform
	radius = maxf( 0.0, sphere_radius )
	steepness = clampf( sphere_steepness, 0.0, 1.0 )
	_inv = transform.affine_inverse()
	_bounds = transform * AABB( -Vector3.ONE * radius, Vector3.ONE * radius * 2.0 )
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
