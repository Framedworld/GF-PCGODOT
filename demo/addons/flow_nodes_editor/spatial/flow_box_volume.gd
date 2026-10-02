@tool
class_name FlowBoxVolume
extends FlowSpatial

## Oriented box volume (UE `UPCGVolumeData` / primitive box). The box spans
## [-half_extents, +half_extents] in local space; `transform` maps it to world
## space (rotation, scale and translation allowed).
##
## sample_density: normalized Chebyshev distance t = max(|x|/hx, |y|/hy, |z|/hz)
## shaped by `steepness` (1 = hard box, lower = linear ramp outside a core of
## size steepness), see FlowSpatial.falloff.

var transform : Transform3D
var half_extents : Vector3

var _inv : Transform3D
var _bounds : AABB

func _init( xform : Transform3D = Transform3D.IDENTITY, box_half_extents : Vector3 = Vector3( 0.5, 0.5, 0.5 ), box_steepness : float = 1.0 ) -> void:
	transform = xform
	half_extents = box_half_extents.abs()
	steepness = clampf( box_steepness, 0.0, 1.0 )
	_inv = transform.affine_inverse()
	_bounds = transform * AABB( -half_extents, half_extents * 2.0 )
	_hash = hash( [ "box", FlowSpatial.hash_transform( transform ), half_extents, steepness ] )

## Axis-aligned box from a world AABB.
static func from_aabb( aabb : AABB, box_steepness : float = 1.0 ) -> FlowBoxVolume:
	return FlowBoxVolume.new( Transform3D( Basis.IDENTITY, aabb.get_center() ), aabb.size * 0.5, box_steepness )

func get_kind() -> int:
	return FlowData.Kind.Volume

func get_type_name() -> String:
	return "Box Volume"

func get_bounds() -> AABB:
	return _bounds

func sample_density( world_pos : Vector3 ) -> float:
	var l := _inv * world_pos
	var t := 0.0
	for axis in range( 3 ):
		var h : float = half_extents[axis]
		if h <= 0.0:
			if absf( l[axis] ) > 1e-6:
				return 0.0
			continue
		t = maxf( t, absf( l[axis] ) / h )
	return FlowSpatial.falloff( t, steepness )
