@tool
class_name FlowSplineBend
extends RefCounted

## Mesh deformation along a Curve3D segment (Unreal's spline mesh component,
## which Godot does not have). Pure functions: inputs are never mutated and the
## output only depends on the arguments, so the math is unit-testable.
##
## Model. The mesh's forward axis (`forward_axis`) runs along the curve. Its
## extent along that axis, [f_min, f_max] (the mesh AABB), maps linearly onto
## the curve offsets [from_offset, to_offset] (baked arc length). The two other
## axes form the cross-section, which is placed in the curve frame at that
## offset: side and up, scaled by lerp(scale_start, scale_end, t). For each axis
## choice the mapping local -> (side, up, forward) is a proper rotation, so a
## straight curve along the forward axis leaves the mesh unchanged except for
## the stretch along that axis and the translation to the curve start.

enum eAxis {
	X,
	Y,
	Z,
}

enum eTangentMode {
	## Follow the curve: positions and directions from the baked cubic curve.
	Curve,
	## Straight chord between the segment's end points (no bending).
	Linear,
}

enum eUpMode {
	## The curve's up vectors (with tilt) when Curve3D.up_vector_enabled, else world up.
	CurveUp,
	## World +Y, re-orthogonalised against the tangent.
	WorldUp,
}

## Bending options with their defaults.
static func default_options() -> Dictionary:
	return {
		"forward_axis": eAxis.Z,
		"tangent_mode": eTangentMode.Curve,
		"up_mode": eUpMode.CurveUp,
		"scale_start": Vector2.ONE,
		"scale_end": Vector2.ONE,
	}

static func _opts( options : Dictionary ) -> Dictionary:
	var out := default_options()
	for k in options:
		out[k] = options[k]
	return out

## Columns map frame coordinates (side, up, forward) to mesh-local coordinates.
## Orthonormal with determinant +1 for every axis.
static func local_basis( forward_axis : int ) -> Basis:
	match forward_axis:
		eAxis.X:
			return Basis( Vector3( 0, 0, -1 ), Vector3( 0, 1, 0 ), Vector3( 1, 0, 0 ) )
		eAxis.Y:
			return Basis( Vector3( -1, 0, 0 ), Vector3( 0, 0, 1 ), Vector3( 0, 1, 0 ) )
	return Basis.IDENTITY

static func axis_vector( forward_axis : int ) -> Vector3:
	match forward_axis:
		eAxis.X:
			return Vector3.RIGHT
		eAxis.Y:
			return Vector3.UP
	return Vector3.BACK

## Extent of `aabb` along the forward axis, as Vector2(min, max).
static func forward_range( aabb : AABB, forward_axis : int ) -> Vector2:
	var axis := axis_vector( forward_axis )
	var lo := aabb.position.dot( axis )
	return Vector2( lo, lo + aabb.size.dot( axis ) )

static func _orthonormal_up( forward : Vector3, up : Vector3 ) -> Vector3:
	var u := up - forward * forward.dot( up )
	if u.length_squared() < 1e-10:
		var alt := Vector3.BACK if absf( forward.dot( Vector3.BACK ) ) < 0.9 else Vector3.RIGHT
		u = alt - forward * forward.dot( alt )
	return u.normalized()

## The curve frame at `offset` as a Transform3D: origin on the curve, basis
## columns (side, up, forward), orthonormal and right-handed (side = up x forward).
## `from_offset` / `to_offset` bound the segment (used by the Linear tangent mode).
static func frame_at( curve : Curve3D, offset : float, options : Dictionary, from_offset : float, to_offset : float ) -> Transform3D:
	var tangent_mode : int = int( options.get( "tangent_mode", eTangentMode.Curve ) )
	var up_mode : int = int( options.get( "up_mode", eUpMode.CurveUp ) )
	var origin : Vector3
	var forward : Vector3
	var up := Vector3.UP
	var rot := curve.sample_baked_with_rotation( offset, true, true )
	if tangent_mode == eTangentMode.Linear:
		var p0 := curve.sample_baked( from_offset, true )
		var p1 := curve.sample_baked( to_offset, true )
		var span := to_offset - from_offset
		var t := ( offset - from_offset ) / span if absf( span ) > 1e-9 else 0.0
		origin = p0.lerp( p1, t )
		forward = ( p1 - p0 ).normalized()
		if forward.length_squared() < 0.5:
			forward = -rot.basis.z.normalized()
	else:
		origin = curve.sample_baked( offset, true )
		forward = -rot.basis.z.normalized()
	if up_mode == eUpMode.CurveUp and curve.up_vector_enabled:
		up = rot.basis.y
	up = _orthonormal_up( forward, up )
	var side := up.cross( forward ).normalized()
	return Transform3D( Basis( side, up, forward ), origin )

## Deformed position of mesh-local point `p`. `along` is the mesh extent on the
## forward axis (forward_range). Pure.
static func bend_point( p : Vector3, curve : Curve3D, from_offset : float, to_offset : float, along : Vector2, options : Dictionary ) -> Vector3:
	var o := _opts( options )
	var lb := local_basis( int( o.forward_axis ) )
	var q : Vector3 = lb.transposed() * p
	var length := along.y - along.x
	var t := ( q.z - along.x ) / length if absf( length ) > 1e-9 else 0.0
	var offset := lerpf( from_offset, to_offset, t )
	var frame := frame_at( curve, offset, o, from_offset, to_offset )
	var sc : Vector2 = Vector2( o.scale_start ).lerp( Vector2( o.scale_end ), clampf( t, 0.0, 1.0 ) )
	return frame.origin + frame.basis.x * ( q.x * sc.x ) + frame.basis.y * ( q.y * sc.y )

## Deformed positions of every point. Pure.
static func bend_positions( positions : PackedVector3Array, curve : Curve3D, from_offset : float, to_offset : float, along : Vector2, options : Dictionary = {} ) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize( positions.size() )
	for i in range( positions.size() ):
		out[i] = bend_point( positions[i], curve, from_offset, to_offset, along, options )
	return out

## Bent copy of one surface's arrays (Mesh.ARRAY_*): vertices, normals and
## tangents deformed, every other array kept. Pure.
static func bend_arrays( arrays : Array, curve : Curve3D, from_offset : float, to_offset : float, along : Vector2, options : Dictionary = {} ) -> Array:
	var o := _opts( options )
	var out := arrays.duplicate()
	var verts : PackedVector3Array = arrays[ Mesh.ARRAY_VERTEX ]
	var normals = arrays[ Mesh.ARRAY_NORMAL ]
	var tangents = arrays[ Mesh.ARRAY_TANGENT ]
	var has_normals : bool = normals is PackedVector3Array and normals.size() == verts.size()
	var has_tangents : bool = tangents is PackedFloat32Array and tangents.size() == verts.size() * 4
	var lb := local_basis( int( o.forward_axis ) )
	var lbt := lb.transposed()
	var length := along.y - along.x
	var stretch := ( to_offset - from_offset ) / length if absf( length ) > 1e-9 else 1.0
	var new_verts := PackedVector3Array()
	new_verts.resize( verts.size() )
	var new_normals := PackedVector3Array()
	if has_normals:
		new_normals.resize( verts.size() )
	var new_tangents := PackedFloat32Array()
	if has_tangents:
		new_tangents.resize( tangents.size() )
	for i in range( verts.size() ):
		var q : Vector3 = lbt * verts[i]
		var t := ( q.z - along.x ) / length if absf( length ) > 1e-9 else 0.0
		var offset := lerpf( from_offset, to_offset, t )
		var frame := frame_at( curve, offset, o, from_offset, to_offset )
		var sc : Vector2 = Vector2( o.scale_start ).lerp( Vector2( o.scale_end ), clampf( t, 0.0, 1.0 ) )
		var b := frame.basis
		new_verts[i] = frame.origin + b.x * ( q.x * sc.x ) + b.y * ( q.y * sc.y )
		if has_normals:
			var nq : Vector3 = lbt * normals[i]
			var n := b.x * ( nq.x / maxf( absf( sc.x ), 1e-6 ) ) + b.y * ( nq.y / maxf( absf( sc.y ), 1e-6 ) ) + b.z * ( nq.z / maxf( absf( stretch ), 1e-6 ) )
			new_normals[i] = n.normalized() if n.length_squared() > 1e-12 else b.y
		if has_tangents:
			var tq : Vector3 = lbt * Vector3( tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2] )
			var tn := ( b.x * ( tq.x * sc.x ) + b.y * ( tq.y * sc.y ) + b.z * ( tq.z * stretch ) ).normalized()
			new_tangents[i * 4] = tn.x
			new_tangents[i * 4 + 1] = tn.y
			new_tangents[i * 4 + 2] = tn.z
			new_tangents[i * 4 + 3] = tangents[i * 4 + 3]
	out[ Mesh.ARRAY_VERTEX ] = new_verts
	if has_normals:
		out[ Mesh.ARRAY_NORMAL ] = new_normals
	if has_tangents:
		out[ Mesh.ARRAY_TANGENT ] = new_tangents
	return out

## Bent ArrayMesh of `mesh` over [from_offset, to_offset]; surface materials are
## copied. Blend shapes are dropped. Not cached (see bent_mesh_cached).
static func bend_mesh( mesh : Mesh, curve : Curve3D, from_offset : float, to_offset : float, options : Dictionary = {} ) -> ArrayMesh:
	var o := _opts( options )
	var along := forward_range( mesh.get_aabb(), int( o.forward_axis ) )
	var out := ArrayMesh.new()
	for s in range( mesh.get_surface_count() ):
		var arrays := mesh.surface_get_arrays( s )
		# A 2D-vertex surface (PackedVector2Array) cannot be bent in 3D.
		if arrays.is_empty() or not ( arrays[ Mesh.ARRAY_VERTEX ] is PackedVector3Array ):
			continue
		var prim : int = Mesh.PRIMITIVE_TRIANGLES
		if mesh is ArrayMesh:
			prim = ( mesh as ArrayMesh ).surface_get_primitive_type( s )
		out.add_surface_from_arrays( prim, bend_arrays( arrays, curve, from_offset, to_offset, along, o ) )
		var mat := mesh.surface_get_material( s )
		if mat != null:
			out.surface_set_material( out.get_surface_count() - 1, mat )
	return out

# --- Cache -------------------------------------------------------------------------

const CACHE_LIMIT := 256

## key -> ArrayMesh, with _cache_order for least-recently-used eviction.
static var _cache : Dictionary = {}
static var _cache_order : Array = []
static var cache_hits : int = 0
static var cache_misses : int = 0

static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()
	cache_hits = 0
	cache_misses = 0

static func cache_size() -> int:
	return _cache.size()

## Hash of everything that shapes the baked curve.
static func curve_hash( curve : Curve3D ) -> int:
	var parts : Array = [ curve.point_count, curve.bake_interval, curve.up_vector_enabled, curve.get( "closed" ) ]
	for i in range( curve.point_count ):
		parts.append( curve.get_point_position( i ) )
		parts.append( curve.get_point_in( i ) )
		parts.append( curve.get_point_out( i ) )
		parts.append( curve.get_point_tilt( i ) )
	return hash( parts )

## Identity of a mesh for the cache: its file path when saved on its own,
## else its instance id, plus its AABB and surface count to catch in-place edits.
static func mesh_key( mesh : Mesh ) -> Array:
	var id = mesh.resource_path if mesh.resource_path != "" and not mesh.resource_path.contains( "::" ) else mesh.get_instance_id()
	return [ id, mesh.get_aabb(), mesh.get_surface_count() ]

## bend_mesh through a bounded LRU cache keyed by mesh identity, curve content,
## segment offsets and options. The returned mesh is shared between callers
## asking for the same segment; do not modify it.
static func bent_mesh_cached( mesh : Mesh, curve : Curve3D, from_offset : float, to_offset : float, options : Dictionary = {} ) -> ArrayMesh:
	var o := _opts( options )
	# The key is the field array itself (Dictionary keys compare by value), not
	# a 32-bit hash() of it: two segments whose hashes collide must not share
	# a slot.
	var key := [ mesh_key( mesh ), curve_hash( curve ), from_offset, to_offset,
		int( o.forward_axis ), int( o.tangent_mode ), int( o.up_mode ), o.scale_start, o.scale_end ]
	if _cache.has( key ):
		cache_hits += 1
		_cache_order.erase( key )
		_cache_order.append( key )
		return _cache[ key ]
	cache_misses += 1
	var bent := bend_mesh( mesh, curve, from_offset, to_offset, o )
	_cache[ key ] = bent
	_cache_order.append( key )
	while _cache_order.size() > CACHE_LIMIT:
		var old = _cache_order.pop_front()
		_cache.erase( old )
	return bent
