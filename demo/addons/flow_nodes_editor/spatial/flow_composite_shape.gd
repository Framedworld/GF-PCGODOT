@tool
class_name FlowCompositeShape
extends FlowSpatial

## Set operation of two shapes (UE `UPCGUnionData` / `UPCGIntersectionData` /
## `UPCGDifferenceData`). Nothing is sampled when the composite is built: the
## operands are kept and combined lazily per query, so a surface can be sampled
## inside a volume, outside another surface, etc. before any point exists.
##
## Density: FlowSpatial.combine_density(op, density_function, a(p), b(p)) with the
## same four density functions `difference` offers (Binary / Minimum / Multiply /
## Subtract).
##
## Kind: Difference keeps A's kind; Intersection is a Surface when either operand
## is a surface; Union is a Surface only when both operands are. Splines count
## as volumes (their tube) inside composites.
##
## Projection (surface composites): onto the surface operand (A for a difference,
## the surface side of an intersection, the nearest / top-most of both for a
## union), with the composite density at the hit.

var op : int = FlowSpatial.Op.Union
var a : FlowSpatial
var b : FlowSpatial
var density_function : int = FlowSpatial.DENSITY_BINARY

var _kind : int
var _bounds : AABB

func _init( operation : int = FlowSpatial.Op.Union, shape_a : FlowSpatial = null, shape_b : FlowSpatial = null, fn : int = FlowSpatial.DENSITY_BINARY ) -> void:
	op = operation
	a = shape_a
	b = shape_b
	density_function = fn
	assert( a != null and b != null, "FlowCompositeShape needs two operands" )
	_kind = _compute_kind()
	_bounds = _compute_bounds()
	_hash = hash( [ "composite", op, density_function, a.get_type_name(), a.content_hash(), b.get_type_name(), b.content_hash() ] )

## Union of `shapes` (nulls skipped): null for none, the shape itself for one.
## Built as a balanced tree (pairs, then pairs of pairs) so queries recurse
## log2(n) deep, not n deep: a left-deep chain of about a thousand operands
## exceeded GDScript's call depth. union_leaves() keeps the input order.
static func union_of( shapes : Array, fn : int = FlowSpatial.DENSITY_BINARY ) -> FlowSpatial:
	var level : Array = []
	for s in shapes:
		if s != null:
			level.append( s )
	if level.is_empty():
		return null
	while level.size() > 1:
		var next : Array = []
		for i in range( 0, level.size() - 1, 2 ):
			next.append( FlowCompositeShape.new( FlowSpatial.Op.Union, level[i], level[i + 1], fn ) )
		if level.size() % 2 == 1:
			next.append( level[level.size() - 1] )
		level = next
	return level[0]

static func _as_composite_kind( kind : int ) -> int:
	return FlowData.Kind.Surface if kind == FlowData.Kind.Surface else FlowData.Kind.Volume

func _compute_kind() -> int:
	var ka := _as_composite_kind( a.get_kind() )
	var kb := _as_composite_kind( b.get_kind() )
	match op:
		FlowSpatial.Op.Difference:
			return ka
		FlowSpatial.Op.Intersection:
			return FlowData.Kind.Surface if ( ka == FlowData.Kind.Surface or kb == FlowData.Kind.Surface ) else FlowData.Kind.Volume
		_:
			return FlowData.Kind.Surface if ( ka == FlowData.Kind.Surface and kb == FlowData.Kind.Surface ) else FlowData.Kind.Volume

func _compute_bounds() -> AABB:
	var ba := a.get_bounds()
	var bb := b.get_bounds()
	match op:
		FlowSpatial.Op.Difference:
			return ba
		FlowSpatial.Op.Union:
			return ba.merge( bb )
		_:
			# XZ: overlap of both. Y: a surface operand keeps its own height range
			# (surface footprints extend vertically); otherwise the overlap.
			var mn := Vector3( maxf( ba.position.x, bb.position.x ), 0.0, maxf( ba.position.z, bb.position.z ) )
			var mx := Vector3( minf( ba.end.x, bb.end.x ), 0.0, minf( ba.end.z, bb.end.z ) )
			var a_surf := a.get_kind() == FlowData.Kind.Surface
			var b_surf := b.get_kind() == FlowData.Kind.Surface
			if a_surf:
				mn.y = ba.position.y
				mx.y = ba.end.y
			elif b_surf:
				mn.y = bb.position.y
				mx.y = bb.end.y
			else:
				mn.y = maxf( ba.position.y, bb.position.y )
				mx.y = minf( ba.end.y, bb.end.y )
			if mx.x < mn.x or mx.y < mn.y or mx.z < mn.z:
				return AABB( mn, Vector3.ZERO )
			return AABB( mn, mx - mn )

func get_kind() -> int:
	return _kind

func get_type_name() -> String:
	return "%s Composite" % FlowSpatial.Op.keys()[op]

func get_bounds() -> AABB:
	return _bounds

func union_leaves() -> Array:
	if op != FlowSpatial.Op.Union:
		return [ self ]
	var out := a.union_leaves()
	out.append_array( b.union_leaves() )
	return out

func sample_density( world_pos : Vector3 ) -> float:
	var da := a.sample_density( world_pos )
	if da <= 0.0 and op != FlowSpatial.Op.Union:
		return 0.0
	return FlowSpatial.combine_density( op, density_function, da, b.sample_density( world_pos ) )

## Paint layers of the surface operand: A for a difference, the surface side of
## an intersection, A's (else B's) for a union.
func get_layers() -> FlowSurfaceLayers:
	match op:
		FlowSpatial.Op.Difference:
			return a.get_layers()
		FlowSpatial.Op.Intersection:
			if a.get_kind() != FlowData.Kind.Surface and b.get_kind() == FlowData.Kind.Surface:
				return b.get_layers()
			return a.get_layers()
		_:
			var la := a.get_layers()
			return la if la != null else b.get_layers()

## The operand(s) that carry the surface for projection.
func _surface_operands() -> Array:
	if _kind != FlowData.Kind.Surface:
		return []
	match op:
		FlowSpatial.Op.Difference:
			return [ a ]
		FlowSpatial.Op.Intersection:
			return [ a ] if a.get_kind() == FlowData.Kind.Surface else [ b ]
		_:
			return [ a, b ]

func _with_density( hit : Dictionary ) -> Dictionary:
	if hit.is_empty():
		return {}
	return { "position": hit.position, "normal": hit.normal, "density": sample_density( hit.position ) }

func project( world_pos : Vector3 ) -> Dictionary:
	var best := {}
	var best_d := INF
	for s in _surface_operands():
		var hit : Dictionary = s.project( world_pos )
		if hit.is_empty():
			continue
		var d : float = world_pos.distance_squared_to( hit.position )
		if d < best_d:
			best_d = d
			best = hit
	return _with_density( best )

func project_vertical( x : float, z : float ) -> Dictionary:
	var best := {}
	for s in _surface_operands():
		var hit : Dictionary = s.project_vertical( x, z )
		if hit.is_empty():
			continue
		if best.is_empty() or hit.position.y > best.position.y:
			best = hit
	return _with_density( best )
