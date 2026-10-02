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
var _axis_aligned : bool = false

func _init( xform : Transform3D = Transform3D.IDENTITY, box_half_extents : Vector3 = Vector3( 0.5, 0.5, 0.5 ), box_steepness : float = 1.0 ) -> void:
	transform = xform
	half_extents = box_half_extents.abs()
	steepness = clampf( box_steepness, 0.0, 1.0 )
	_inv = transform.affine_inverse()
	_bounds = transform * AABB( -half_extents, half_extents * 2.0 )
	_axis_aligned = FlowBoxVolume.basis_is_axis_aligned( transform.basis )
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

## True when every basis column points along one world axis (any scale,
## permutation or mirroring), so world AABBs map to local AABBs exactly.
static func basis_is_axis_aligned( b : Basis ) -> bool:
	for c in [ b.x, b.y, b.z ]:
		var v : Vector3 = c
		var len := v.length()
		if len <= 0.0:
			return false
		var nonzero := 0
		for axis in range( 3 ):
			if absf( v[axis] ) > len * 1e-6:
				nonzero += 1
		if nonzero != 1:
			return false
	return true

## BoundsBox overlap (see FlowSpatial.box_overlap). Exact when the box is
## aligned with the world axes: the peak is the density at the point of the box
## nearest to the core (Chebyshev distance is separable per axis), and for a
## hard box (steepness 1) the coverage is the overlapped volume fraction, the
## same penetration ratio point-versus-point difference uses. A soft box takes
## its coverage from the fixed sample set; a rotated box uses the sample set.
func box_overlap( box_min : Vector3, box_max : Vector3 ) -> Vector2:
	if not _axis_aligned:
		return super.box_overlap( box_min, box_max )
	var l := _inv * AABB( box_min, box_max - box_min )
	var lo := l.position
	var hi := l.end
	var t := 0.0
	for axis in range( 3 ):
		var h : float = half_extents[axis]
		var d := 0.0
		if lo[axis] > 0.0:
			d = lo[axis]
		elif hi[axis] < 0.0:
			d = -hi[axis]
		if h <= 0.0:
			if d > 1e-6:
				return Vector2.ZERO
			continue
		t = maxf( t, d / h )
	var peak := FlowSpatial.falloff( t, steepness )
	if peak <= 0.0:
		return Vector2.ZERO
	if steepness < 1.0:
		var sampled := FlowSpatial.box_overlap_sampled( self, box_min, box_max )
		return Vector2( peak, minf( sampled.y, peak ) )
	var coverage := 1.0
	for axis in range( 3 ):
		var ext : float = hi[axis] - lo[axis]
		if ext <= 0.0:
			continue
		var h : float = half_extents[axis]
		coverage *= clampf( ( minf( hi[axis], h ) - maxf( lo[axis], -h ) ) / ext, 0.0, 1.0 )
	return Vector2( peak, coverage )
