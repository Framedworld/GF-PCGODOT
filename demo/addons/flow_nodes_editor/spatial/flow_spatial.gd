@tool
class_name FlowSpatial
extends RefCounted

## Spatial data (UE `UPCGSpatialData` parity): a deferred description of a spline,
## surface or volume carried on `FlowData.Data.shape`, alongside or instead of
## point streams.
##
## Contract (docs/PARITY_ROUND2.md, WP2):
##   get_kind()              FlowData.Kind.Spline / Surface / Volume
##   get_bounds()            world-space AABB of the region where density can be > 0
##   sample_density(p)       0..1 at a world position, steepness-aware where the
##                           shape has a falloff
##   project(p)              {} or { position, normal, density }; surfaces only
##   to_points(settings)     default concrete sampling ("To Point")
##   content_hash()          stable hash of geometry, transform and parameters
##
## Shapes are IMMUTABLE value objects. Constructors copy the source geometry
## (Curve3D, mesh triangles, height samples) and build every acceleration
## structure eagerly, so:
##  * later scene edits never change a cached result,
##  * every query is a pure read and is safe from worker threads,
##  * copies of a Data may share the same shape reference.
## Never mutate a shape after construction; build a new one instead.
##
## Subclasses override the virtual methods below. Shared helpers (density
## falloff, density combination, the default surface / volume / spline
## samplers and the point-data builder) are static functions on this class.

## Density functions, same values and meaning as
## DifferenceNodeSettings.eDensityFunction (Binary / Minimum / Multiply / Subtract).
const DENSITY_BINARY := 0
const DENSITY_MINIMUM := 1
const DENSITY_MULTIPLY := 2
const DENSITY_SUBTRACT := 3

## Composite operations.
enum Op { Union, Intersection, Difference }

## Default safety cap for the generic samplers (candidate cells or voxels).
const DEFAULT_MAX_CANDIDATES := 4000000

## Hardness of the shape's boundary, 0..1 (UE Steepness). 1 = binary edge; lower
## values ramp density from 1 at the core to 0 on the boundary. Only shapes with
## a falloff (box, sphere, spline tube, points volume) use it.
var steepness : float = 1.0

## Cached content hash, computed once by the subclass constructor.
var _hash : int = 0

# --- Virtual interface ------------------------------------------------------

func get_kind() -> int:
	return FlowData.Kind.Volume

func get_bounds() -> AABB:
	return AABB()

func sample_density( _world_pos : Vector3 ) -> float:
	return 0.0

func project( _world_pos : Vector3 ) -> Dictionary:
	return {}

## Surfaces only: the hit of the vertical line through (x, z), or {}.
## Returns { position, normal, density } where density is this shape's density
## at the hit (composites fold their operands in). Used by the surface sampler.
func project_vertical( _x : float, _z : float ) -> Dictionary:
	return {}

func to_points( settings : Dictionary = {} ) -> FlowData.Data:
	match get_kind():
		FlowData.Kind.Surface:
			return FlowSpatial.sample_surface( self, settings )
		_:
			return FlowSpatial.sample_volume( self, settings )

func content_hash() -> int:
	return _hash

## Human readable type ("Spline", "Mesh Surface", ...), for tooltips and logs.
func get_type_name() -> String:
	return "Spatial"

## Paint-layer weights carried by a surface (terrain adapters attach them), or
## null. Samplers write one weight attribute per layer when present (WP6).
func get_layers() -> FlowSurfaceLayers:
	return null

## Leaves of nested unions (or [self]). Lets spline consumers treat a merged
## spline collection as its individual splines.
func union_leaves() -> Array:
	return [ self ]

func is_surface() -> bool:
	return get_kind() == FlowData.Kind.Surface

func is_volume() -> bool:
	return get_kind() == FlowData.Kind.Volume

func is_spline() -> bool:
	return get_kind() == FlowData.Kind.Spline

## sample_density for many positions.
func sample_density_batch( positions : PackedVector3Array ) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize( positions.size() )
	for i in range( positions.size() ):
		out[i] = sample_density( positions[i] )
	return out

## Overlap of a world-space axis-aligned box (a point's bounds) with this
## shape's density field, for the BoundsBox overlap mode of the set operations.
## Returns Vector2(peak, coverage):
##   peak      the highest density found over the box (0 = no overlap)
##   coverage  the mean density over the box, 0..peak
## The default evaluates a fixed, deterministic sample set (box_sample_points:
## centre, 8 corners, 6 face centres). Box and sphere volumes override it with
## exact results where the math is closed-form. Surfaces are tested over their
## whole column (their density ignores Y unless vertical_tolerance > 0), so no
## broad-phase rejection on Y is made here.
func box_overlap( box_min : Vector3, box_max : Vector3 ) -> Vector2:
	var b := get_bounds()
	if box_max.x < b.position.x or box_min.x > b.end.x or box_max.z < b.position.z or box_min.z > b.end.z:
		return Vector2.ZERO
	return FlowSpatial.box_overlap_sampled( self, box_min, box_max )

## The 15 fixed sample positions of a box: centre, 8 corners, 6 face centres.
static func box_sample_points( box_min : Vector3, box_max : Vector3 ) -> PackedVector3Array:
	var c := ( box_min + box_max ) * 0.5
	var out := PackedVector3Array()
	out.append( c )
	for ix in [ box_min.x, box_max.x ]:
		for iy in [ box_min.y, box_max.y ]:
			for iz in [ box_min.z, box_max.z ]:
				out.append( Vector3( ix, iy, iz ) )
	out.append( Vector3( box_min.x, c.y, c.z ) )
	out.append( Vector3( box_max.x, c.y, c.z ) )
	out.append( Vector3( c.x, box_min.y, c.z ) )
	out.append( Vector3( c.x, box_max.y, c.z ) )
	out.append( Vector3( c.x, c.y, box_min.z ) )
	out.append( Vector3( c.x, c.y, box_max.z ) )
	return out

## Vector2(peak, coverage) of `shape` over a box from the fixed sample set.
static func box_overlap_sampled( shape : FlowSpatial, box_min : Vector3, box_max : Vector3 ) -> Vector2:
	var peak := 0.0
	var total := 0.0
	var samples := box_sample_points( box_min, box_max )
	for p in samples:
		var d := clampf( shape.sample_density( p ), 0.0, 1.0 )
		peak = maxf( peak, d )
		total += d
	return Vector2( peak, total / float( samples.size() ) )

## One overlap density from box_overlap()'s (peak, coverage) and the point's
## steepness, generalising the point-versus-point rule of `difference`
## (BoundsOverlapUtil.shape_factor of the penetration ratio):
##   steepness 1 (hard point)  -> peak
##   steepness < 1             -> peak * shape_factor(coverage / peak, steepness)
## Against a hard shape (peak 1 wherever it overlaps) this is exactly the
## point-versus-point factor with the penetration ratio replaced by coverage.
static func overlap_factor( overlap : Vector2, point_steepness : float ) -> float:
	var peak := clampf( overlap.x, 0.0, 1.0 )
	if peak <= 0.0:
		return 0.0
	var s := clampf( point_steepness, 0.0, 1.0 )
	if s >= 1.0:
		return peak
	return peak * BoundsOverlapUtil.shape_factor( clampf( overlap.y / peak, 0.0, 1.0 ), s )

func _to_string() -> String:
	return "<%s %s>" % [ get_type_name(), str( get_bounds() ) ]

# --- Density helpers ------------------------------------------------------------

## Density at normalized distance `t` from a shape's core (0 = centre, 1 = boundary),
## shaped by `steepness_value` (UE semantics): steepness 1 is a hard edge (1 inside,
## 0 outside); lower steepness keeps a core of radius `steepness` at density 1 and
## ramps linearly to 0 at the boundary. t > 1 is always 0.
static func falloff( t : float, steepness_value : float ) -> float:
	if t > 1.0 or is_nan( t ):
		return 0.0
	var s := clampf( steepness_value, 0.0, 1.0 )
	if s >= 1.0 or t <= s:
		return 1.0
	return clampf( ( 1.0 - t ) / ( 1.0 - s ), 0.0, 1.0 )

## Combine two densities for a composite operation with one of the density
## functions `difference` offers. Difference uses exactly the BoundsOverlapUtil
## fold (factor = density of B). Intersection is its complement-of-B form and
## Union is the dual (1 - inter(1 - a, 1 - b)); Binary is the hard-membership form:
##   Difference    Binary: b > 0 ? 0 : a   Minimum: min(a, 1-b)   Multiply: a(1-b)   Subtract: a-b
##   Intersection  Binary: b > 0 ? a : 0   Minimum: min(a, b)     Multiply: ab       Subtract: a-(1-b)
##   Union         Binary: a>0 or b>0 ? 1 : 0   Minimum: max(a, b)   Multiply: a+b-ab   Subtract: min(a+b, 1)
static func combine_density( op : int, density_function : int, a : float, b : float ) -> float:
	match op:
		Op.Difference:
			match density_function:
				DENSITY_MINIMUM:
					return clampf( minf( a, 1.0 - b ), 0.0, 1.0 )
				DENSITY_MULTIPLY:
					return clampf( a * ( 1.0 - b ), 0.0, 1.0 )
				DENSITY_SUBTRACT:
					return clampf( a - b, 0.0, 1.0 )
				_:
					return 0.0 if b > 0.0 else clampf( a, 0.0, 1.0 )
		Op.Intersection:
			match density_function:
				DENSITY_MINIMUM:
					return clampf( minf( a, b ), 0.0, 1.0 )
				DENSITY_MULTIPLY:
					return clampf( a * b, 0.0, 1.0 )
				DENSITY_SUBTRACT:
					return clampf( a - ( 1.0 - b ), 0.0, 1.0 )
				_:
					return clampf( a, 0.0, 1.0 ) if b > 0.0 else 0.0
		_:
			match density_function:
				DENSITY_MINIMUM:
					return clampf( maxf( a, b ), 0.0, 1.0 )
				DENSITY_MULTIPLY:
					return clampf( a + b - a * b, 0.0, 1.0 )
				DENSITY_SUBTRACT:
					return clampf( a + b, 0.0, 1.0 )
				_:
					return 1.0 if ( a > 0.0 or b > 0.0 ) else 0.0

# --- Hash helpers -------------------------------------------------------------------

static func hash_transform( t : Transform3D ) -> int:
	return hash( [ t.basis.x, t.basis.y, t.basis.z, t.origin ] )

# --- Point-data builder -------------------------------------------------------------

## Builds a sampler-convention point Data: position, rotation (Euler degrees),
## size, density, seed (FlowData.point_seed of the position and `node_seed`),
## symmetric bounds from `extents` (full extent per point, or one shared value)
## and, when given, normal and steepness streams.
static func make_points_data( positions : PackedVector3Array, rotations : PackedVector3Array, normals : PackedVector3Array, densities : PackedFloat32Array, extent : Vector3, node_seed : int, point_size : Vector3 = Vector3.ONE, point_steepness : float = -1.0 ) -> FlowData.Data:
	var n := positions.size()
	var out := FlowData.Data.new()
	out.addCommonStreams( 0 )
	var spos := out.getVector3Container( FlowData.AttrPosition )
	var srot := out.getVector3Container( FlowData.AttrRotation )
	var ssize := out.getVector3Container( FlowData.AttrSize )
	spos.append_array( positions )
	if rotations.size() == n:
		srot.append_array( rotations )
	else:
		srot.resize( n )
	ssize.resize( n )
	ssize.fill( point_size )
	var extents := PackedVector3Array()
	extents.resize( n )
	extents.fill( extent )
	out.setSymmetricBounds( extents )
	if normals.size() == n and n > 0:
		out.registerStream( FlowData.AttrNormal, normals, FlowData.DataType.Vector )
	var sdens := PackedFloat32Array()
	if densities.size() == n:
		sdens = densities
	else:
		sdens.resize( n )
		sdens.fill( 1.0 )
	out.registerStream( FlowData.AttrDensity, sdens, FlowData.DataType.Float )
	var sseed := PackedInt32Array()
	sseed.resize( n )
	for i in range( n ):
		sseed[i] = FlowData.point_seed( positions[i], node_seed )
	out.registerStream( FlowData.AttrSeed, sseed, FlowData.DataType.Int )
	if point_steepness >= 0.0:
		var ssteep := PackedFloat32Array()
		ssteep.resize( n )
		ssteep.fill( clampf( point_steepness, 0.0, 1.0 ) )
		out.registerStream( FlowData.AttrSteepness, ssteep, FlowData.DataType.Float )
	return out

# --- Generic samplers ---------------------------------------------------------------

## Deterministic per-cell RNG seed: the same world cell always draws the same
## jitter, so sampling is stable when the sampled region grows or shrinks.
static func cell_seed( node_seed : int, cx : int, cz : int ) -> int:
	return int( hash( [ node_seed, cx, cz ] ) & 0x7fffffff )

## Surface sampling (UE Surface Sampler). Settings (all optional):
##   points_per_square_meter : float = 0.1   candidate density on the XZ plane
##   num_points : int = 0                    > 0 switches to "count" mode: exactly up
##                                           to this many random hits over the bounds
##   point_extents : Vector3 = (1, 1, 1)     half extents of each point (bounds)
##   looseness : float = 1.0                 0 = regular grid, 1 = full jitter in the cell
##   seed : int = 0
##   apply_density : bool = true             write the surface density, else 1.0
##   keep_zero_density : bool = false        keep candidates whose density is 0
##   point_steepness : float = 0.5           written to the steepness stream (< 0: none)
##   align_to_normal : bool = false          rotation from the surface normal (Y up)
##   point_size : Vector3 = (1, 1, 1)        scale written to `size`
##   max_candidates : int = 4000000          safety cap; above it sampling errors out
##   bounds : AABB                           optional extra XZ restriction
##   write_layers : bool = true              write the surface's paint-layer weights
##   layer_prefix : String = "layer_"        prefix of those weight streams
## Candidates are placed on a world-anchored XZ grid (cell = 1/sqrt(points per m^2))
## with per-cell seeded jitter, projected with project_vertical(), and weighted by
## the hit density: composites (surface minus a volume, surface inside another
## surface) are therefore sampled before any points exist.
## `errors`, when given, receives a message on failure.
static func sample_surface( shape : FlowSpatial, settings : Dictionary = {}, errors : Array = [] ) -> FlowData.Data:
	var extents : Vector3 = settings.get( "point_extents", Vector3.ONE )
	extents = extents.abs()
	var looseness := clampf( float( settings.get( "looseness", 1.0 ) ), 0.0, 1.0 )
	var node_seed := int( settings.get( "seed", 0 ) )
	var apply_density := bool( settings.get( "apply_density", true ) )
	var keep_zero := bool( settings.get( "keep_zero_density", false ) )
	var point_steepness := float( settings.get( "point_steepness", 0.5 ) )
	var align := bool( settings.get( "align_to_normal", false ) )
	var point_size : Vector3 = settings.get( "point_size", Vector3.ONE )
	var max_candidates := int( settings.get( "max_candidates", DEFAULT_MAX_CANDIDATES ) )
	var count := int( settings.get( "num_points", 0 ) )

	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var normals := PackedVector3Array()
	var densities := PackedFloat32Array()

	var bounds := shape.get_bounds()
	if settings.has( "bounds" ):
		bounds = _intersect_xz( bounds, settings["bounds"] )

	if bounds.size.x > 0.0 and bounds.size.z > 0.0:
		if count > 0:
			var rng := RandomNumberGenerator.new()
			rng.seed = node_seed
			var attempts := 0
			var max_attempts := count * 16
			while positions.size() < count and attempts < max_attempts:
				attempts += 1
				var x := rng.randf_range( bounds.position.x, bounds.end.x )
				var z := rng.randf_range( bounds.position.z, bounds.end.z )
				_accept_surface_hit( shape, x, z, keep_zero, apply_density, align, positions, rotations, normals, densities )
		else:
			var ppsm := float( settings.get( "points_per_square_meter", 0.1 ) )
			if ppsm <= 0.0:
				errors.append( "points_per_square_meter must be greater than zero" )
				return make_points_data( positions, rotations, normals, densities, extents * 2.0, node_seed, point_size, point_steepness )
			var cell := 1.0 / sqrt( ppsm )
			var cx0 := int( floor( bounds.position.x / cell ) )
			var cx1 := int( floor( bounds.end.x / cell ) )
			var cz0 := int( floor( bounds.position.z / cell ) )
			var cz1 := int( floor( bounds.end.z / cell ) )
			var num_cells : int = ( cx1 - cx0 + 1 ) * ( cz1 - cz0 + 1 )
			if num_cells > max_candidates:
				errors.append( "Surface sampling would test %d candidates (cap %d); lower points_per_square_meter" % [ num_cells, max_candidates ] )
				return make_points_data( positions, rotations, normals, densities, extents * 2.0, node_seed, point_size, point_steepness )
			var jx := maxf( 0.0, cell * 0.5 - extents.x ) * looseness
			var jz := maxf( 0.0, cell * 0.5 - extents.z ) * looseness
			var rng := RandomNumberGenerator.new()
			for cz in range( cz0, cz1 + 1 ):
				for cx in range( cx0, cx1 + 1 ):
					rng.seed = cell_seed( node_seed, cx, cz )
					var x := ( cx + 0.5 ) * cell + rng.randf_range( -jx, jx )
					var z := ( cz + 0.5 ) * cell + rng.randf_range( -jz, jz )
					if x < bounds.position.x or x > bounds.end.x or z < bounds.position.z or z > bounds.end.z:
						continue
					_accept_surface_hit( shape, x, z, keep_zero, apply_density, align, positions, rotations, normals, densities )

	var out := make_points_data( positions, rotations, normals, densities, extents * 2.0, node_seed, point_size, point_steepness )
	_write_layers( shape, out, settings, errors )
	return out

## Surfaces carrying paint layers (terrain adapters): one Float weight stream
## per layer, `layer_prefix` + name (settings write_layers = true by default,
## layer_prefix = "layer_", the Sample Terrain Layers prefix). Shapes without
## layers are untouched.
static func _write_layers( shape : FlowSpatial, out : FlowData.Data, settings : Dictionary, errors : Array ) -> void:
	if not bool( settings.get( "write_layers", true ) ):
		return
	var layers := shape.get_layers()
	if layers == null or layers.is_empty():
		return
	var err := layers.write_streams( out, str( settings.get( "layer_prefix", "layer_" ) ) )
	if err != "":
		errors.append( err )

static func _accept_surface_hit( shape : FlowSpatial, x : float, z : float, keep_zero : bool, apply_density : bool, align : bool, positions : PackedVector3Array, rotations : PackedVector3Array, normals : PackedVector3Array, densities : PackedFloat32Array ) -> bool:
	var hit := shape.project_vertical( x, z )
	if hit.is_empty():
		return false
	var d := float( hit.get( "density", 1.0 ) )
	if d <= 0.0 and not keep_zero:
		return false
	var n : Vector3 = hit.get( "normal", Vector3.UP )
	positions.append( hit.position )
	normals.append( n )
	rotations.append( FlowData.basisToEuler( FlowData.basisFromNormal( n, Vector3.UP, "y" ) ) if align else Vector3.ZERO )
	densities.append( d if apply_density else 1.0 )
	return true

static func _intersect_xz( a : AABB, b : AABB ) -> AABB:
	var mn := Vector3( maxf( a.position.x, b.position.x ), a.position.y, maxf( a.position.z, b.position.z ) )
	var mx := Vector3( minf( a.end.x, b.end.x ), a.end.y, minf( a.end.z, b.end.z ) )
	if mx.x < mn.x or mx.z < mn.z:
		return AABB( mn, Vector3.ZERO )
	return AABB( mn, mx - mn )

## Volume sampling (UE Volume Sampler): voxel centres on a world-anchored grid
## inside get_bounds(), kept where sample_density() > 0. Settings (optional):
##   voxel_size : Vector3 = (1, 1, 1)
##   seed : int = 0
##   apply_density : bool = true
##   keep_zero_density : bool = false
##   point_steepness : float = -1 (no steepness stream)
##   max_candidates : int = 4000000
static func sample_volume( shape : FlowSpatial, settings : Dictionary = {}, errors : Array = [] ) -> FlowData.Data:
	var voxel : Vector3 = settings.get( "voxel_size", Vector3.ONE )
	voxel = voxel.abs()
	var node_seed := int( settings.get( "seed", 0 ) )
	var apply_density := bool( settings.get( "apply_density", true ) )
	var keep_zero := bool( settings.get( "keep_zero_density", false ) )
	var point_steepness := float( settings.get( "point_steepness", -1.0 ) )
	var max_candidates := int( settings.get( "max_candidates", DEFAULT_MAX_CANDIDATES ) )
	var positions := PackedVector3Array()
	var densities := PackedFloat32Array()
	if voxel.x <= 0.0 or voxel.y <= 0.0 or voxel.z <= 0.0:
		errors.append( "voxel_size must be greater than zero on every axis" )
		return make_points_data( positions, PackedVector3Array(), PackedVector3Array(), densities, voxel, node_seed, Vector3.ONE, point_steepness )
	var bounds := shape.get_bounds()
	var i0 := Vector3i( floori( bounds.position.x / voxel.x ), floori( bounds.position.y / voxel.y ), floori( bounds.position.z / voxel.z ) )
	var i1 := Vector3i( ceili( bounds.end.x / voxel.x ) - 1, ceili( bounds.end.y / voxel.y ) - 1, ceili( bounds.end.z / voxel.z ) - 1 )
	var total : int = maxi( 0, i1.x - i0.x + 1 ) * maxi( 0, i1.y - i0.y + 1 ) * maxi( 0, i1.z - i0.z + 1 )
	if total > max_candidates:
		errors.append( "Volume sampling would test %d voxels (cap %d); raise voxel_size" % [ total, max_candidates ] )
		return make_points_data( positions, PackedVector3Array(), PackedVector3Array(), densities, voxel, node_seed, Vector3.ONE, point_steepness )
	for iz in range( i0.z, i1.z + 1 ):
		for iy in range( i0.y, i1.y + 1 ):
			for ix in range( i0.x, i1.x + 1 ):
				var p := Vector3( ( ix + 0.5 ) * voxel.x, ( iy + 0.5 ) * voxel.y, ( iz + 0.5 ) * voxel.z )
				var d := shape.sample_density( p )
				if d <= 0.0 and not keep_zero:
					continue
				positions.append( p )
				densities.append( d if apply_density else 1.0 )
	return make_points_data( positions, PackedVector3Array(), PackedVector3Array(), densities, voxel, node_seed, Vector3.ONE, point_steepness )

# --- Geometry helpers -----------------------------------------------------------------

## Closest point to `p` on triangle (a, b, c) (Ericson, Real-Time Collision Detection 5.1.5).
static func closest_point_on_triangle( p : Vector3, a : Vector3, b : Vector3, c : Vector3 ) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot( ap )
	var d2 := ac.dot( ap )
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot( bp )
	var d4 := ac.dot( bp )
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * ( d1 / ( d1 - d3 ) )
	var cp := p - c
	var d5 := ab.dot( cp )
	var d6 := ac.dot( cp )
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * ( d2 / ( d2 - d6 ) )
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and ( d4 - d3 ) >= 0.0 and ( d5 - d6 ) >= 0.0:
		return b + ( c - b ) * ( ( d4 - d3 ) / ( ( d4 - d3 ) + ( d5 - d6 ) ) )
	var denom := 1.0 / ( va + vb + vc )
	return a + ab * ( vb * denom ) + ac * ( vc * denom )

## Normal transform for a local->world transform (inverse transpose of the basis).
static func transform_normal( t : Transform3D, local_normal : Vector3 ) -> Vector3:
	var n := t.basis.inverse().transposed() * local_normal
	if n.length_squared() < 1e-20:
		return Vector3.UP
	return n.normalized()
