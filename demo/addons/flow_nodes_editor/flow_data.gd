extends Object
class_name FlowData

# Defines the DataTypes and Data class that is passed between nodes
# A FlowData.Data is basically a dict of streams, where each stream is:
#   Container: Continuous typed array of the actual data stored
#   data_type
#   name
# The storage is column oriented, not row oriented

enum DataType {
	Bool,
	Int,
	Float,
	Vector,
	String,
	Resource,
	NodeMesh,
	NodePath,
	Color,
	Quaternion,		# Rotation as a unit quaternion, stored as a Vector4 (x,y,z,w)
	# Extended attribute types (UE PCG parity). Values are explicit so saved
	# graphs keep their meaning; keys()[value] stays valid for 0..Double.
	Vector2 = 10,	# PackedVector2Array
	Vector4 = 11,	# PackedVector4Array. Inference maps PackedVector4Array to Quaternion, so register Vector4 explicitly
	Transform = 12,	# Array[Transform3D] (typed Array)
	Int64 = 13,		# PackedInt64Array
	Double = 14,	# PackedFloat64Array
	Invalid = 999
}

# Spatial data type lattice marker. A Data is a bag of point streams by default;
# `kind` says what the data *represents* so consumers (e.g. filter_data_by_type)
# can classify it honestly instead of heuristically. When a Data carries a
# FlowSpatial `shape` (spatial/flow_spatial.gd), `kind` follows shape.get_kind().
# Absent/Points = identical to historical behavior, so existing .tres / graphs
# are untouched.
enum Kind {
	Points,     # default: per-point streams
	Spline,     # spline data (FlowSplineShape, or a NodePath 'node' stream)
	Surface,    # surface data (FlowPolygonSurface / FlowMeshSurface / FlowHeightfieldSurface / surface composites)
	Volume,     # volume data (FlowBoxVolume / FlowSphereVolume / FlowMeshVolume / volume composites)
	AttrSet     # an attribute set with no spatial role
}

# Selector prefix for the per-data attribute domain (UE @Data parity). A stream
# name beginning with this prefix addresses `data_attrs` instead of a per-point
# stream. See findStream()/registerStream().
const DataAttrPrefix : String = "@data."

const AttrPosition : StringName = &"position"
const AttrRotation : StringName = &"rotation"
const AttrSize     : StringName = &"size"
# Optional canonical stream: when present it WINS over AttrRotation (Euler) for
# building point bases (see getTransformsStream). Stored as DataType.Quaternion
# (PackedVector4Array of x,y,z,w). Absent by default — Euler stays the default
# authoring representation and existing graphs are unaffected.
const AttrRotationQuat : StringName = &"rotation_quat"
const AttrDensity  : StringName = &"density"	# Float, 0..1, soft existence probability (UE $Density)
const AttrSeed     : StringName = &"seed"		# Int, per-point deterministic seed (UE $Seed)
const AttrNormal   : StringName = &"normal"		# Vector, surface normal where known
# Optional bounds/steepness attributes (UE PCG parity). When these streams are
# absent, consumers MUST behave exactly as before (deriving symmetric bounds
# from `size`), so existing graphs are byte-for-byte unchanged.
const AttrBoundsMin : StringName = &"bounds_min"	# Vector, per-point local-space min corner of the bounds box
const AttrBoundsMax : StringName = &"bounds_max"	# Vector, per-point local-space max corner of the bounds box
const AttrSteepness : StringName = &"steepness"		# Float, 0..1, hardness of the point volume edge (UE $Steepness; 1 = binary box)

## Canonical point attributes and the only DataType each may be registered with.
## Data.registerStream refuses (push_error + returns the error string) a
## registration of one of these names with any other type, so a graph that
## writes, say, a Float `rotation` fails loudly instead of breaking orientation.
const CANONICAL_ATTRIBUTE_TYPES := {
	&"position": DataType.Vector,
	&"rotation": DataType.Vector,		# Euler angles in degrees
	&"size": DataType.Vector,
	&"rotation_quat": DataType.Quaternion,
	&"density": DataType.Float,
	&"seed": DataType.Int,
	&"normal": DataType.Vector,
	&"bounds_min": DataType.Vector,
	&"bounds_max": DataType.Vector,
	&"steepness": DataType.Float,
}

## Error message for registering canonical attribute `name` as `data_type`, or ""
## when `name` is not canonical or the type is the canonical one.
static func canonical_type_error( name : String, data_type : DataType ) -> String:
	var expected = CANONICAL_ATTRIBUTE_TYPES.get( StringName( name ), null )
	if expected == null or expected == data_type:
		return ""
	return "Attribute '%s' is canonical and must be %s, not %s; registration refused. Write the value to another attribute name." % [
		name, DataType.find_key( expected ), _data_type_label( data_type ) ]

## `data_type`, or the canonical type of attribute `name` when both are numeric
## (Int <-> Float), so an inferred `{"density": 1}` or `seed = 5.0` registers.
static func canonical_numeric_type( name : String, data_type : DataType ) -> DataType:
	var expected = CANONICAL_ATTRIBUTE_TYPES.get( StringName( name ), null )
	if expected == DataType.Float and ( data_type == DataType.Int or data_type == DataType.Int64 or data_type == DataType.Double ):
		return DataType.Float
	if expected == DataType.Int and ( data_type == DataType.Float or data_type == DataType.Int64 or data_type == DataType.Double ):
		return DataType.Int
	return data_type

## UE-style `$Name` selector aliases (case-insensitive) for the canonical
## streams. They only add names: a stream literally named "$Foo" still wins,
## and every other selector resolves exactly as before. Component access works
## on an alias ("$Position.X" reads position.X).
const SELECTOR_ALIASES := {
	"$position": "position",
	"$rotation": "rotation",
	"$scale": "size",
	"$density": "density",
	"$seed": "seed",
	"$boundsmin": "bounds_min",
	"$boundsmax": "bounds_max",
	"$steepness": "steepness",
	"$color": "color",
	"$index": "index",
}

## The canonical name `selector` aliases ("$Scale.x" -> "size.x"), or "" when
## it is not an alias.
static func resolveSelectorAlias( selector : String ) -> String:
	if not selector.begins_with( "$" ):
		return ""
	var dot := selector.find( "." )
	var root := selector if dot == -1 else selector.substr( 0, dot )
	var target = SELECTOR_ALIASES.get( root.to_lower(), null )
	if target == null:
		return ""
	return String( target ) + ( "" if dot == -1 else selector.substr( dot ) )

static func _data_type_label( data_type : DataType ) -> String:
	var key = DataType.find_key( data_type )
	return String( key ) if key != null else str( data_type )

# Per-evaluation state shared by every node of one graph evaluation. Build one
# with FlowNodeIO.make_context(); nested subgraph/loop evaluations derive a
# child context from it (see FlowNodeIO._build_evaluation_state).
class EvaluationContext:
	## The host of this evaluation: normally a FlowGraphNode3D, but any Node3D
	## works as the spawn parent / scene anchor (component features such as
	## args, transient_output and overrides are read only when present).
	## MAY BE NULL (owner-less evaluation via FlowNodeIO.evaluate); nodes that
	## need a scene (spawners, scanners, apply_on_actor) then report an error
	## and pass their input through.
	var owner : Node3D
	## Evaluation counter (the editor bumps it per regen). Never a seed.
	var eval_id : int = 0
	## Graph seed. 0 = legacy: every node uses its own settings.random_seed.
	## Otherwise each node derives hash([seed, random_seed]) & 0x7fffffff.
	var seed : int = 0
	## owner.get_instance_id(), or 0. Stamped into spawned nodes' flow_owner
	## meta so components sharing a spawn parent never clean up each other.
	var component_id : int = 0
	var graph : FlowGraphResource
	var gedit_nodes_by_name : Dictionary
	## Always contains "seed" mirrored from `seed` once the evaluator built it.
	var runtime_params : Dictionary = {}
	var variables : Dictionary = {}
	## Per-instance node setting overrides, "node_name/property" -> value.
	var overrides : Dictionary = {}
	## True only for the editor dock's live preview (flow_editor.gd sets it);
	## nested subgraph/loop evaluations inherit it. In a preview with no owner
	## (a graph opened on its own) nodes stay silent about missing inputs and
	## the missing owner and emit empty Data (FlowNodeBase.is_ownerless_preview).
	## Runtime callers, @tool scripts included, leave it false and get real errors.
	var preview : bool = false
	# --- Hierarchical (world) generation, set by FlowWorld3D (WP5) -------------
	# All zero / false outside world generation. Nested subgraph and loop
	# evaluations inherit them (FlowExecutor.build_state).
	## Execution bounds of the current cell: the cell box intersected with the
	## world bounds (the whole world bounds on the Unbounded level). World space.
	var bounds : AABB = AABB()
	## True while a FlowWorld3D cell (or its Unbounded run) is being generated.
	var has_bounds : bool = false
	## Cell size of the current level in world units (a power of two); 0 on the
	## Unbounded level and outside world generation.
	var grid_size : float = 0.0
	## Cell coordinate on the XZ plane: floor(x / grid_size), floor(z / grid_size).
	var cell_coord : Vector2i = Vector2i.ZERO
	## Depth of the current level: 1 for the coarsest grid level of the graph,
	## increasing toward finer levels; 0 on the Unbounded level and outside
	## world generation.
	var hierarchy_level : int = 0

## Deterministic per-point seed (UE $Seed parity): hashes the position
## quantized per component at *1000 (the same quantization mutate_seed.gd
## uses, so both produce agreeing values) combined with the node seed.
## Result is masked to a positive 31-bit int so it fits a PackedInt32Array.
static func point_seed( pos : Vector3, node_seed : int ) -> int:
	var px = int(round(pos.x * 1000.0))
	var py = int(round(pos.y * 1000.0))
	var pz = int(round(pos.z * 1000.0))
	return hash([px, py, pz, node_seed]) & 0x7fffffff

## Broadcast convention: a stream whose container holds a single element is a
## "broadcast" stream — that one value applies to every point. Streams with
## more than one element are read per point. Use this helper to compute the
## read index into a container that may be broadcast.
static func bcast_idx( container_size : int, i : int ) -> int:
	return i if container_size > 1 else 0

## Resolve the deterministic per-point RNG seed for point `i` (UE $Seed parity).
## Preference order, so randomness is reorder-/count-stable wherever possible:
##   1. an explicit per-point seed stream (the point's own $Seed), xored with the node seed
##   2. a hash of the point's position (same quantization as point_seed)
##   3. index arithmetic — last resort when neither seed nor position exists
## Both `point_seeds` and `positions` may be null or broadcast (size 1).
static func resolve_seed( point_seeds, positions, i : int, node_seed : int ) -> int:
	if point_seeds != null and point_seeds.size() > 0:
		return int(point_seeds[bcast_idx(point_seeds.size(), i)]) ^ node_seed
	if positions != null and positions.size() > 0:
		return point_seed( positions[bcast_idx(positions.size(), i)], node_seed )
	return node_seed + i * 256

## Build a stable orthonormal Basis from a surface normal.
## - `normal` is the axis you want to align (default aligns to +Z).
## - `up` is your preferred up; a safe fallback is chosen if nearly parallel.
## - `axis` can be "z" (default), "y", or "x" for which axis the normal should align to.
static func basisFromNormal(normal: Vector3, up: Vector3 = Vector3.UP, axis: String = "z") -> Basis:
	var n := normal.normalized()
	if n.length() == 0.0 or not n.is_finite():
		return Basis.IDENTITY

	# Pick a safe up if nearly parallel to n
	var safe_up := up
	if abs(n.dot(safe_up)) > 0.999: # ~parallel
		# pick the axis least aligned with n
		safe_up = Vector3.UP if (abs(n.y) < 0.9) else Vector3.RIGHT

	# Build tangent/bitangent
	var t := safe_up.cross(n).normalized()    # tangent
	var b := n.cross(t)                       # bitangent; already unit-length if t,n are

	var basis: Basis
	match axis:
		"x":
			basis = Basis(n, t, b)            # X=n, Y=t, Z=b
		"y":
			basis = Basis(t, n, b)            # X=t, Y=n, Z=b
		_:
			basis = Basis(t, b, n)            # X=t, Y=b, Z=n (default: Z=n)

	return basis.orthonormalized()

# basis.get_euler() * 180.0 / PI		# <-- This is much faster
static func basisToEuler( basis : Basis ) -> Vector3:
	var euler = basis.get_euler()
	euler.x = rad_to_deg( euler.x )
	euler.y = rad_to_deg( euler.y )
	euler.z = rad_to_deg( euler.z )
	return euler

static func eulerToBasis( euler : Vector3) -> Basis:
	euler.x = deg_to_rad( euler.x )
	euler.y = deg_to_rad( euler.y )
	euler.z = deg_to_rad( euler.z )
	return Basis.from_euler( euler )

# --- Quaternion helpers ---------------------------------------------------
# A Quaternion stream stores each rotation as a Vector4 (x,y,z,w) so it can live
# in a PackedVector4Array container. These convert between that storage form and
# Godot's Quaternion/Basis without any degree<->radian round-trips.

static func vec4ToQuat( v : Vector4 ) -> Quaternion:
	return Quaternion( v.x, v.y, v.z, v.w )

static func quatToVec4( q : Quaternion ) -> Vector4:
	return Vector4( q.x, q.y, q.z, q.w )

static func quatToBasis( q : Quaternion ) -> Basis:
	return Basis( q )

static func basisToQuat( basis : Basis ) -> Quaternion:
	return basis.orthonormalized().get_rotation_quaternion()

# Euler (degrees) <-> Quaternion bridges, layered on the existing Euler helpers
# so both representations agree.
static func eulerToQuat( euler : Vector3 ) -> Quaternion:
	return eulerToBasis( euler ).get_rotation_quaternion()

static func quatToEuler( q : Quaternion ) -> Vector3:
	return basisToEuler( Basis( q ) )

# A wrapper around the Position/Rotation/Scale streams
class TransformsStream:
	var positions : PackedVector3Array
	var eulers : PackedVector3Array
	var sizes : PackedVector3Array
	# When an AttrRotationQuat stream is present, getTransformsStream fills these
	# and sets use_quats = true. The quaternion path then WINS over the Euler one.
	# When absent (the default), use_quats stays false and behavior is identical
	# to the historical Euler-only path.
	var quats : PackedVector4Array
	var use_quats : bool = false

	func basisAt( id: int ) -> Basis:
		if use_quats:
			return FlowData.quatToBasis( FlowData.vec4ToQuat( quats[id] ) )
		return FlowData.eulerToBasis( eulers[id] )

	func atIndex( id: int ) -> Transform3D:
		var basis := basisAt( id )
		return Transform3D( basis.scaled( sizes[id] ), positions[id] )

	func atIndexAbsScale( id: int, scale: float ) -> Transform3D:
		var basis := basisAt( id )
		return Transform3D( basis.scaled( Vector3.ONE * scale ), positions[id] )

	func size() -> int:
		return positions.size()

# The basic information that is passed between nodes
class Data:
	var streams : Dictionary = {}
	var last_added_stream_name : String
	var tags : PackedStringArray = PackedStringArray()
	# Per-data attribute domain (UE @Data parity). Maps attribute name -> a small
	# record { value, data_type }. Addressed via the "@data." selector prefix in
	# findStream()/registerStream(). Absent/empty == historical behavior.
	var data_attrs : Dictionary = {}
	# Spatial data type lattice marker. Defaults to Points so absent == today.
	var kind : Kind = Kind.Points
	# Deferred spatial description (a FlowSpatial: spline, surface, volume, composite)
	# carried alongside — or instead of — point streams. null for plain point data.
	# Shapes are immutable value objects, so copies share the reference. A
	# shape-bearing Data may have zero points. Setting a shape makes `kind` follow
	# shape.get_kind(); clearing it (null) leaves `kind` as it was.
	var shape : FlowSpatial = null:
		set( value ):
			shape = value
			if value != null:
				kind = value.get_kind() as Kind

	## A zero-point Data carrying `spatial` (kind follows the shape).
	static func from_shape( spatial : FlowSpatial ) -> Data:
		var d := Data.new()
		d.shape = spatial
		return d

	## True when this Data carries a spatial shape.
	func has_shape() -> bool:
		return shape != null

	## Copies everything that is not a per-point stream from `src`: tags, per-data
	## attributes, the kind marker and the spatial shape. EVERY site that rebuilds a
	## Data from another one (filter, duplicate, graph boundaries, output nodes) must
	## go through this, so new metadata added here reaches all of them at once.
	func copy_meta_from( src : Data ) -> Data:
		tags = src.tags.duplicate()
		data_attrs = src.data_attrs.duplicate( true )
		# Shape first: its setter derives kind; then copy the source kind verbatim.
		shape = src.shape
		kind = src.kind
		return self

	## Stable hash of the whole Data: stream order, names, types and contents, tags,
	## per-data attributes, kind and shape. Equal content gives an equal hash across
	## processes for plain values; object-valued elements hash by resource path (or
	## instance id when unsaved), so two Data are only "equal" if they reference the
	## same objects. Used as a cache key, never for security.
	func content_hash() -> int:
		var h : int = hash( [ int(kind), last_added_stream_name, Array( tags ) ] )
		for stream_name in streams:
			var stream : Dictionary = streams[stream_name]
			h = hash( [ h, stream_name, int(stream.data_type), _container_content_hash( stream.container ) ] )
		for attr_name in data_attrs:
			var rec = data_attrs[attr_name]
			var value = rec.get( "value", null ) if rec is Dictionary else rec
			h = hash( [ h, attr_name, _value_content_hash( value ) ] )
		if shape != null:
			h = hash( [ h, shape.get_type_name(), shape.content_hash() ] )
		return h

	static func _value_content_hash( value ) -> int:
		if value is Object:
			if not is_instance_valid( value ):
				return 0
			if value is Resource and value.resource_path != "":
				return hash( value.resource_path )
			return value.get_instance_id()
		return hash( value )

	static func _container_content_hash( container ) -> int:
		if container is Array:
			var h : int = container.size()
			for element in container:
				h = hash( [ h, _value_content_hash( element ) ] )
			return h
		return hash( container )


	static func newContainerOfType( data_type : DataType ):
		match data_type:
			DataType.Bool:
				return PackedByteArray()
			DataType.Int:
				return PackedInt32Array()
			DataType.Float:
				return PackedFloat32Array()
			DataType.Vector:
				return PackedVector3Array()
			DataType.String:
				return PackedStringArray()
			DataType.Resource:
				return Array([], TYPE_OBJECT, "Resource", null)
			DataType.NodeMesh:
				return Array([], TYPE_OBJECT, "Node", null)
			DataType.NodePath:
				return Array([], TYPE_OBJECT, "Node", null)
			DataType.Color:
				return PackedColorArray()
			DataType.Quaternion:
				return PackedVector4Array()
			DataType.Vector2:
				return PackedVector2Array()
			DataType.Vector4:
				return PackedVector4Array()
			DataType.Transform:
				return Array([], TYPE_TRANSFORM3D, "", null)
			DataType.Int64:
				return PackedInt64Array()
			DataType.Double:
				return PackedFloat64Array()
			_:
				push_error( "newContainerOfType(%d) type not supported" % [ data_type ])
		return null

	static func writeValue( container, index : int, value, data_type : DataType ) -> void:
		match data_type:
			DataType.Bool:
				var typed_container : PackedByteArray = container
				typed_container[index] = 1 if bool(value) else 0
			DataType.Int:
				var typed_container : PackedInt32Array = container
				typed_container[index] = int(value)
			DataType.Float:
				var typed_container : PackedFloat32Array = container
				typed_container[index] = float(value)
			DataType.Vector:
				var typed_container : PackedVector3Array = container
				typed_container[index] = value
			DataType.String:
				var typed_container : PackedStringArray = container
				typed_container[index] = str(value)
			DataType.Resource:
				var typed_container : Array = container
				typed_container[index] = value
			DataType.NodeMesh:
				var typed_container : Array = container
				typed_container[index] = value
			DataType.NodePath:
				var typed_container : Array = container
				typed_container[index] = value
			DataType.Color:
				var typed_container : PackedColorArray = container
				typed_container[index] = value
			DataType.Quaternion:
				var typed_container : PackedVector4Array = container
				if value is Quaternion:
					typed_container[index] = FlowData.quatToVec4( value )
				else:
					typed_container[index] = value
			DataType.Vector2:
				var typed_container : PackedVector2Array = container
				if value is Vector2 or value is Vector2i:
					typed_container[index] = Vector2( value )
				else:
					push_error( "writeValue(Vector2): cannot store a %s" % type_string( typeof( value ) ) )
			DataType.Vector4:
				var typed_container : PackedVector4Array = container
				if value is Vector4 or value is Vector4i:
					typed_container[index] = Vector4( value )
				elif value is Quaternion:
					typed_container[index] = FlowData.quatToVec4( value )
				elif value is Color:
					typed_container[index] = Vector4( value.r, value.g, value.b, value.a )
				else:
					push_error( "writeValue(Vector4): cannot store a %s" % type_string( typeof( value ) ) )
			DataType.Transform:
				var typed_container : Array = container
				if value is Transform3D:
					typed_container[index] = value
				elif value is Basis:
					typed_container[index] = Transform3D( value, Vector3.ZERO )
				else:
					push_error( "writeValue(Transform): cannot store a %s" % type_string( typeof( value ) ) )
			DataType.Int64:
				var typed_container : PackedInt64Array = container
				typed_container[index] = int(value)
			DataType.Double:
				var typed_container : PackedFloat64Array = container
				typed_container[index] = float(value)
			_:
				push_error( "writeValue(%d) type not supported" % [ data_type ])
	
	# Infer a DataType from a concrete packed-array container. Returns Invalid
	# when the container type isn't one of the recognized packed arrays.
	static func _inferContainerType( container ) -> DataType:
		if container is PackedFloat32Array:
			return FlowData.DataType.Float
		elif container is PackedInt32Array:
			return FlowData.DataType.Int
		elif container is PackedVector3Array:
			return FlowData.DataType.Vector
		elif container is PackedColorArray:
			return FlowData.DataType.Color
		elif container is PackedVector4Array:
			return FlowData.DataType.Quaternion
		elif container is PackedStringArray:
			return FlowData.DataType.String
		elif container is PackedByteArray:
			return FlowData.DataType.Bool
		elif container is PackedVector2Array:
			return FlowData.DataType.Vector2
		elif container is PackedInt64Array:
			return FlowData.DataType.Int64
		elif container is PackedFloat64Array:
			return FlowData.DataType.Double
		elif container is Array and container.get_typed_builtin() == TYPE_TRANSFORM3D:
			return FlowData.DataType.Transform
		return FlowData.DataType.Invalid

	## True when `container` is the storage newContainerOfType( data_type )
	## creates. Resource / NodeMesh / NodePath accept any Array (historically
	## untyped arrays are registered for them); Transform accepts a typed
	## Array[Transform3D] or an untyped Array holding only Transform3D values;
	## Vector4 and Quaternion share PackedVector4Array.
	static func containerMatchesType( container, data_type : DataType ) -> bool:
		match data_type:
			DataType.Bool:
				return container is PackedByteArray
			DataType.Int:
				return container is PackedInt32Array
			DataType.Float:
				return container is PackedFloat32Array
			DataType.Vector:
				return container is PackedVector3Array
			DataType.String:
				return container is PackedStringArray
			DataType.Resource, DataType.NodeMesh, DataType.NodePath:
				return container is Array
			DataType.Color:
				return container is PackedColorArray
			DataType.Quaternion, DataType.Vector4:
				return container is PackedVector4Array
			DataType.Vector2:
				return container is PackedVector2Array
			DataType.Transform:
				if not ( container is Array ):
					return false
				if container.get_typed_builtin() == TYPE_TRANSFORM3D:
					return true
				if container.is_typed():
					return false
				for element in container:
					if not ( element is Transform3D ):
						return false
				return true
			DataType.Int64:
				return container is PackedInt64Array
			DataType.Double:
				return container is PackedFloat64Array
		return false

	## The extended attribute types (Vector2, Vector4, Transform, Int64, Double).
	## registerStream refuses a container that does not match one of these
	## types instead of storing a mistyped stream.
	static func isExtendedType( data_type : DataType ) -> bool:
		return data_type == DataType.Vector2 or data_type == DataType.Vector4 \
			or data_type == DataType.Transform or data_type == DataType.Int64 \
			or data_type == DataType.Double

	## One-element Data holding `value` in stream `name` (e.g. to feed a graph
	## input or a runtime parameter). The type is inferred from the value when
	## `data_type` is Invalid.
	static func scalar( name : String, value, data_type : DataType = DataType.Invalid ) -> Data:
		var data := Data.new()
		if data_type == DataType.Invalid:
			data_type = FlowData.canonical_numeric_type( name, _inferValueType( value ) )
		if data_type == DataType.Invalid:
			push_warning( "Data.scalar('%s'): unsupported value type %s" % [ name, type_string( typeof( value ) ) ] )
			return data
		var new_container = data.addStream( name, data_type )
		if new_container == null:
			return data
		new_container.resize( 1 )
		writeValue( new_container, 0, value, data_type )
		return data

	# Same mapping as FlowNodeBase.getFlowDataTypeFromObject (kept local so
	# flow_data.gd does not depend on node.gd), plus StringName, Quaternion and
	# Node values.
	static func _inferValueType( value ) -> DataType:
		match typeof( value ):
			TYPE_BOOL:
				return DataType.Bool
			TYPE_INT:
				return DataType.Int
			TYPE_FLOAT:
				return DataType.Float
			TYPE_STRING, TYPE_STRING_NAME:
				return DataType.String
			TYPE_VECTOR3:
				return DataType.Vector
			TYPE_COLOR:
				return DataType.Color
			TYPE_QUATERNION, TYPE_VECTOR4:
				return DataType.Quaternion
			TYPE_VECTOR2, TYPE_VECTOR2I:
				return DataType.Vector2
			TYPE_TRANSFORM3D:
				return DataType.Transform
		if value is Resource:
			return DataType.Resource
		if value is Node:
			return DataType.NodeMesh
		return DataType.Invalid

	# findStream without the push_error noise for absent streams, so the
	# convenience readers fall back to their defaults silently.
	func _findStreamQuiet( name : String ):
		if name == "":
			return null
		if name == "@last":
			if last_added_stream_name == "":
				return null
			return findStream( name )
		if name.begins_with( DataAttrPrefix ):
			return findStream( name )
		var translated : String = translateStreamName( name )
		var parts := translated.split( "." )
		if parts.size() > 2:
			return null
		if parts.size() == 2:
			var root = findStream( parts[0] )
			if root == null or getSubStreamIndex( parts[1] ) == -1:
				return null
			if getSubStreamIndex( parts[1] ) >= _componentCount( root.data_type ):
				return null
		return findStream( name )

	static func _readElement( stream : Dictionary, index : int ):
		var value = stream.container[ index ]
		if stream.data_type == DataType.Bool:
			return bool( value )
		return value

	## Element 0 of stream `name`, else the per-data attribute `name`, else
	## `default`. Accepts every selector findStream accepts ("@last",
	## "position.x", "@data.foo", "Yaw").
	func first( name : String, default = null ):
		var stream = _findStreamQuiet( name )
		if stream != null and stream.container.size() > 0:
			return _readElement( stream, 0 )
		if not name.begins_with( DataAttrPrefix ) and data_attrs.has( name ):
			return get_data_attr( name, default )
		return default

	## Value of stream `name` for point `i`, honouring broadcast: a one-element
	## stream (and a per-data attribute, "@data.<name>" or a plain name with no
	## stream) applies to every point (FlowData.bcast_idx). Returns `default`
	## when the name resolves to nothing or `i` is outside the stream. Bool
	## streams come back as bool, like first(). Same selectors as first().
	func value_at( name : String, i : int, default = null ):
		var stream = _findStreamQuiet( name )
		if stream != null and stream.container.size() > 0:
			var count : int = stream.container.size()
			var idx := FlowData.bcast_idx( count, i )
			if i < 0 or idx >= count:
				return default
			return _readElement( stream, idx )
		if not name.begins_with( DataAttrPrefix ) and data_attrs.has( name ):
			return get_data_attr( name, default )
		return default

	## The packed container (or Array for Resource/Node streams) of stream
	## `name`, or null when absent. Same selectors as first().
	func container( name : String ):
		var stream = _findStreamQuiet( name )
		if stream == null:
			return null
		return stream.container

	## Set per-data attribute `name` (read back with get_data_attr, first() or
	## the "@data.<name>" selector). Type inferred when `data_type` is Invalid.
	## A data attribute holds ONE value: prefer this over
	## registerStream("@data.<name>", container), which silently keeps only
	## element 0 of a multi-element container (it now warns).
	func set_data_attr( name : String, value, data_type : DataType = DataType.Invalid ) -> void:
		if data_type == DataType.Invalid:
			data_type = _inferValueType( value )
		if data_type == DataType.Invalid:
			push_warning( "Data.set_data_attr('%s'): unsupported value type %s" % [ name, type_string( typeof( value ) ) ] )
			return
		# Store exactly what registerStream("@data.<name>", ...) would store:
		# the value coerced to the declared type (Bool as a 0/1 byte).
		var coerced = newContainerOfType( data_type )
		if coerced == null:
			return
		coerced.resize( 1 )
		writeValue( coerced, 0, value, data_type )
		var holder : Dictionary = { "container" : coerced }
		data_attrs[ name ] = { "value" : holder.container[0], "data_type" : data_type }

	func get_data_attr( name : String, default = null ):
		var rec = data_attrs.get( name, null )
		if rec == null:
			return default
		if rec.data_type == DataType.Bool and rec.value != null:
			return bool( rec.value )
		return rec.value

	func numFields() -> int:
		return streams.size()
		
	func size() -> int:
		if streams.size() == 0:
			return 0
		var key0 = streams.keys()[0]
		return streams[ key0 ].container.size()
	
	func hasStream( name : StringName ) -> bool:
		return streams.has( name )
		
	func hasStreamOfType( name : StringName, data_type : DataType ) -> bool:
		return streams.has( name ) and streams[ name ].data_type == data_type
	
	func getContainerChecked( name : String, data_type : DataType ):
		var stream = streams.get( name, null )
		if stream and stream.data_type == data_type:
			return stream.container
		return null
		
	# converts 'Yaw' into "Rotation.Y" 
	func translateStreamName( name : String ):
		if name == "@last":
			if not last_added_stream_name:
				push_error( "@last is not valid" )
			return last_added_stream_name
		if name == "Yaw":
			return "%s.Y" % FlowData.AttrRotation
		if name == "Pitch":
			return "%s.X" % FlowData.AttrRotation
		if name == "Roll":
			return "%s.Z" % FlowData.AttrRotation
		if name.begins_with( "$" ) and not streams.has( name ):
			var alias := FlowData.resolveSelectorAlias( name )
			if alias != "":
				return alias
		return name
		
	func getSubStreamIndex(  sub_comp : String ):
		var sc_up = sub_comp.to_upper()
		if sc_up == "X" or sc_up == "R":
			return 0
		elif sc_up == "Y" or sc_up == "G":
			return 1
		elif sc_up == "Z" or sc_up == "B":
			return 2
		elif sc_up == "W" or sc_up == "A":
			return 3
		return -1
	
	## Number of addressable components (.x/.y/.z/.w, .r/.g/.b/.a) of a stream type.
	static func _componentCount( data_type : DataType ) -> int:
		match data_type:
			DataType.Vector:
				return 3
			DataType.Color, DataType.Vector4, DataType.Quaternion:
				return 4
			DataType.Vector2:
				return 2
		return 0

	func getSubStream( stream : Dictionary, sub_comp : String ):
		var subcomp_idx = getSubStreamIndex( sub_comp )
		if subcomp_idx == -1:
			push_error( "Invalid sub_stream name %s" % sub_comp )
			return null
		if _componentCount( stream.data_type ) == 0:
			push_error( "getSubStream.Parent stream must be of type Vector, Vector2, Vector4, Quaternion or Color" )
			return null
		if stream.data_type == DataType.Vector and subcomp_idx == 3:
			push_error( "Vector parent does not support W/A component" )
			return null
		if subcomp_idx >= _componentCount( stream.data_type ):
			push_error( "%s parent does not support component %s" % [ FlowData._data_type_label( stream.data_type ), sub_comp ] )
			return null
		var big_container = stream.container
		var new_container = PackedFloat32Array()
		new_container.resize( big_container.size() )
		for idx in range( big_container.size() ):
			new_container[idx] = big_container[idx][ subcomp_idx ]
		return {
			"data_type" : DataType.Float,
			"container" : new_container,
			"name" : "%s.%s" % [ stream.name, sub_comp ]
		}
		
	func setSubStream( stream : Dictionary, sub_comp : String, sub_container  ):
		var subcomp_idx = getSubStreamIndex( sub_comp )
		if subcomp_idx == -1:
			return "Invalid sub stream name %s" % sub_comp
		if _componentCount( stream.data_type ) == 0:
			return "setSubStream.Parent stream must be of type Vector, Vector2, Vector4, Quaternion or Color"
		if stream.data_type == DataType.Vector and subcomp_idx == 3:
			return "Vector parent does not support W/A component"
		if subcomp_idx >= _componentCount( stream.data_type ):
			return "%s parent does not support component %s" % [ FlowData._data_type_label( stream.data_type ), sub_comp ]
		var big_container = stream.container
		if sub_container.size() != big_container.size():
			return "Container sizes do not match (%d vs %d)" % [sub_container.size(), big_container.size()]
		#print( "big_container %s[%d] << %s" % [ big_container, subcomp_idx, sub_container ])
		# Because we are mutating the container (part of it), we need to create
		# a new copy of the original and insert it as the new current container
		# Fixes bug expresion updating position.y and refreshing
		big_container = big_container.duplicate()
		for idx in range( big_container.size() ):
			var item = big_container[idx]
			item[subcomp_idx] = sub_container[idx]
			big_container[idx] = item
		stream.container = big_container
		
	func findStream( name : String ):
		# Per-data attribute selector (UE @Data). "@data.<attr>" returns a
		# synthetic length-1 broadcast stream sourced from data_attrs, so the
		# value reads as a constant for every point under the broadcast rules.
		if name.length() > DataAttrPrefix.length() and name.begins_with( DataAttrPrefix ):
			var attr_name := name.substr( DataAttrPrefix.length() )
			var rec = data_attrs.get( attr_name, null )
			if rec == null:
				return null
			var bcast = newContainerOfType( rec.data_type )
			if bcast == null:
				return null
			bcast.resize( 1 )
			writeValue( bcast, 0, rec.value, rec.data_type )
			return {
				"data_type" : rec.data_type,
				"container" : bcast,
				"name" : name
			}

		name = translateStreamName( name )

		var name_lower := name.to_lower()
		if name_lower == "front" or name_lower == "up" or name_lower == "right":
			var rot_stream = streams.get(AttrRotation, null)
			if rot_stream != null:
				var eulers = rot_stream.container
				var new_container := PackedVector3Array()
				new_container.resize(eulers.size())
				for idx in range(eulers.size()):
					var basis := FlowData.eulerToBasis(eulers[idx])
					match name_lower:
						"front":
							new_container[idx] = -basis.z
						"up":
							new_container[idx] = basis.y
						"right":
							new_container[idx] = basis.x
				return {
					"data_type": DataType.Vector,
					"container": new_container,
					"name": name
				}
			return null
		
		if name == "index":
			var new_container = PackedInt32Array()
			new_container.resize( size() )
			for idx in range( new_container.size() ):
				new_container[idx] = idx
			return {
				"data_type" : DataType.Int,
				"container" : new_container,
				"name" : "Index"
			}
			
		var parts = name.split( "." )
		if parts.size() == 2:
			#print( "findStream(%s) => %s (Streams:%s)" % [ name, parts, streams])
			var s0 = findStream( parts[0] )
			if s0 == null:
				push_error( "Failed to find stream root %s" % parts[0] )
				return null
			#print( "searching (%s) in %s" % [ parts[1], s0])
			return getSubStream( s0, parts[1] )
		elif parts.size() > 2:
			return null
		return streams.get( name, null )
	
	func registerStream( name : String, container, data_type : DataType = FlowData.DataType.Invalid ):
		if not name:
			print( "registerStream empty name!. Container size:", container.size() )
			push_error("registerStream name can't be empty of data_type %d" % [ data_type ] )
			return null
		if container == null:
			push_error("registerStream. Can't register a null container with name %s" %  name )
			return null
		# Per-data attribute selector (UE @Data). "@data.<attr>" writes into
		# data_attrs instead of creating a per-point stream. The container is
		# read as a broadcast: element 0 (if any) is stored as the data value.
		if name.length() > DataAttrPrefix.length() and name.begins_with( DataAttrPrefix ):
			var attr_name := name.substr( DataAttrPrefix.length() )
			if data_type == FlowData.DataType.Invalid:
				data_type = _inferContainerType( container )
			if data_type == FlowData.DataType.Invalid:
				return "Invalid container type"
			if container.size() > 1:
				# Semantics unchanged this round (element 0 wins), but a
				# multi-element write is almost always a bug upstream.
				push_warning( "registerStream('%s'): per-data attribute got %d elements; only element 0 is kept" % [ name, container.size() ] )
			var value = container[0] if container.size() > 0 else null
			data_attrs[ attr_name ] = { "value" : value, "data_type" : data_type }
			last_added_stream_name = name
			return null
		name = translateStreamName( name )
		var parts = name.split( "." )
		if parts.size() == 2:
			var s0 = streams.get( parts[0], null )
			if s0 == null:
				return "Failed to find stream %s" % parts[0] 
			return setSubStream( s0, parts[1], container )
		elif parts.size() > 2:
			return "Too many '.' in stream name"
		else:
			if data_type == FlowData.DataType.Invalid:
				data_type = _inferContainerType( container )

			if data_type == FlowData.DataType.Invalid:
				print( "Invalid data type ", name, " Container:", container)
				return "Invalid container type"

			# Canonical attributes have one fixed type (CANONICAL_ATTRIBUTE_TYPES).
			var canonical_error := FlowData.canonical_type_error( name, data_type )
			if canonical_error != "":
				push_error( "registerStream: " + canonical_error )
				return canonical_error

			# A container that is not the declared type's storage is refused when
			# either side is an extended type (Vector2, Vector4, Transform, Int64,
			# Double), so a mistyped stream fails here instead of downstream.
			if not containerMatchesType( container, data_type ):
				var mismatch := "registerStream: '%s' declared %s but the container is a %s; registration refused" % [
					name, FlowData._data_type_label( data_type ), type_string( typeof( container ) ) ]
				if isExtendedType( data_type ) or isExtendedType( _inferContainerType( container ) ):
					push_error( mismatch )
					return mismatch
				# Historical types keep registering (third-party nodes may rely on
				# it) but no longer silently.
				push_warning( mismatch.replace( "; registration refused", "" ) )

			if streams.has(name) and streams[name].data_type != data_type:
				push_warning("Stream name conflict: '%s' already exists with data_type %d, overwriting with data_type %d" % [name, streams[name].data_type, data_type])

			# Stream-length invariant (engine-hardening). Once a Data carries
			# points, every per-point stream must be either size()==point count
			# or a length-1 broadcast. A registration of any other non-empty
			# length silently corrupts downstream per-point reads, so warn
			# clearly. We measure against the established point count size()
			# (which ignores the stream being (re)written when it replaces an
			# existing one). Exempt: empty containers (register-empty-then-fill
			# idiom) and broadcast (size 1). Warn-only — never hard-error — to
			# avoid breaking legitimate mid-construction build-up idioms.
			var point_count : int = size()
			if point_count > 0 and container.size() > 1 and container.size() != point_count:
				# size() can equal the stream being overwritten; recompute the
				# point count from the *other* streams so an overwrite of the
				# very first stream doesn't false-positive against itself.
				var other_count := 0
				for existing_name in streams:
					if existing_name == name:
						continue
					var existing_size : int = streams[existing_name].container.size()
					if existing_size > 1:
						other_count = existing_size
						break
				if other_count > 0 and container.size() != other_count:
					push_warning("registerStream: stream '%s' has %d elements but this Data holds %d points — per-point streams must match the point count or be length 1 (broadcast). Downstream per-point reads may be corrupted." % [name, container.size(), other_count])

			streams[ name ] = {
				"container" : container,
				"name" : name,
				"data_type" : data_type
			}
		last_added_stream_name = name
		#print( "Registered stream %s : %s " % [ name, streams[ name ] ])
		return null
	
	func addStream( name : String, data_type : DataType):
		if not name:
			push_error("addStream: name can't be empty" )
			return null
		var sz := size()
		var new_container = newContainerOfType(data_type)
		if sz:
			new_container.resize( sz )
		registerStream( name, new_container, data_type )
		return new_container
	
	func delStream( name : String):
		if streams.has( name ):
			streams.erase( name )
		
	func cloneStream( name : String ):
		var prev_stream = findStream( name )
		if not prev_stream:
			push_error("cloneStream: Data does not have a stream named %s" % name )
			return null
		var new_container
		match prev_stream.data_type:
			DataType.Bool:
				new_container = PackedByteArray( prev_stream.container )
			DataType.Int:
				new_container = PackedInt32Array( prev_stream.container )
			DataType.Float:
				new_container = PackedFloat32Array( prev_stream.container )
			DataType.Vector:
				new_container = PackedVector3Array( prev_stream.container )
				#print( "Duped container vec3 %s %s" % [ name, new_container ])
			DataType.Color:
				new_container = PackedColorArray( prev_stream.container )
			DataType.Quaternion:
				new_container = PackedVector4Array( prev_stream.container )
			DataType.String:
				new_container = PackedStringArray( prev_stream.container )
			DataType.Vector2:
				new_container = PackedVector2Array( prev_stream.container )
			DataType.Vector4:
				new_container = PackedVector4Array( prev_stream.container )
			DataType.Int64:
				new_container = PackedInt64Array( prev_stream.container )
			DataType.Double:
				new_container = PackedFloat64Array( prev_stream.container )
			_:  # Resource, NodeMesh, NodePath, Transform (Array containers keep their element type)
				new_container = prev_stream.container.duplicate()	
		prev_stream.container = new_container
		return new_container
		
	func filteredStream( old_stream : Dictionary, indices : PackedInt32Array ):
		var new_size : int = indices.size()
		var source_container = old_stream.container
		if size() > 1 and source_container.size() == 1:
			return source_container.duplicate()
		match old_stream.data_type:
			
			DataType.Bool:
				var old_container : PackedByteArray = old_stream.container
				var new_container := PackedByteArray( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Int:
				var old_container : PackedInt32Array = old_stream.container
				var new_container := PackedInt32Array( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Float:
				var old_container : PackedFloat32Array = old_stream.container
				var new_container := PackedFloat32Array( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Vector:
				var old_container : PackedVector3Array = old_stream.container
				var new_container := PackedVector3Array(  )		
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Color:
				var old_container : PackedColorArray = old_stream.container
				var new_container := PackedColorArray( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

			DataType.Quaternion:
				var old_container : PackedVector4Array = old_stream.container
				var new_container := PackedVector4Array( )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

			DataType.String:
				var old_container : PackedStringArray = old_stream.container
				var new_container : PackedStringArray
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
				
			DataType.Resource:
				var old_container : Array[ Resource ] = old_stream.container
				var new_container : Array[ Resource ] = []
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
			DataType.NodeMesh:
				var old_container : Array = old_stream.container
				var new_container : Array = []
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container
			DataType.NodePath:
				var old_container : Array = old_stream.container
				var new_container : Array = []
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

			DataType.Vector2:
				var old_container : PackedVector2Array = old_stream.container
				var new_container := PackedVector2Array()
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

			DataType.Vector4:
				var old_container : PackedVector4Array = old_stream.container
				var new_container := PackedVector4Array()
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

			DataType.Transform:
				var old_container : Array = old_stream.container
				var new_container : Array = newContainerOfType( DataType.Transform )
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

			DataType.Int64:
				var old_container : PackedInt64Array = old_stream.container
				var new_container := PackedInt64Array()
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

			DataType.Double:
				var old_container : PackedFloat64Array = old_stream.container
				var new_container := PackedFloat64Array()
				new_container.resize( new_size )
				for idx in range( new_size ):
					new_container[idx] = old_container[ indices[idx] ]
				return new_container

		push_error( "filteredStream: stream '%s' has unsupported data_type %d" % [ old_stream.get( "name", "" ), old_stream.data_type ] )
		return null

	func duplicate() -> Data:
		var s := Data.new()
		for name in streams:
			s.streams[name] = streams[name].duplicate()
			s.streams[name]["container"] = streams[name]["container"].duplicate()
		s.last_added_stream_name = last_added_stream_name
		s.copy_meta_from( self )
		return s

	# Schema-preserving, row-empty clone: every stream is present with the same
	# name and DataType but zero elements (unlike filter([]), which keeps
	# broadcast/length-1 streams), plus tags/data_attrs/kind carried over. Used by
	# nodes that route a whole set elsewhere and must still emit the input's schema
	# on the other output (e.g. branch), so downstream merges/filters see the
	# expected streams instead of a bare empty Data.
	func emptyLike() -> Data:
		var s := Data.new()
		for old_stream in streams.values():
			var new_container = newContainerOfType( old_stream.data_type )
			s.registerStream( old_stream.name, new_container, old_stream.data_type )
		s.copy_meta_from( self )
		return s

	func filter( indices : PackedInt32Array ) -> Data:
		var new_data := Data.new()
		for old_stream in streams.values():
			var new_container = filteredStream( old_stream, indices )
			new_data.registerStream( old_stream.name, new_container, old_stream.data_type )
		# Tags, per-data attributes, kind and shape are domain-level metadata, not
		# per-point: filtering the point set does not change them.
		new_data.copy_meta_from( self )
		return new_data

	func dump( title : String ):
		print( "== %s (%d streams) ==" % [title, streams.size()] )
		for stream in streams.values():
			print( "%s (%s) %d elems" % [ stream.name, stream.data_type, stream.container.size() ] )
			for data in stream.container:
				print( "  %s" % str(data ))

	func addCommonStreams( num_points : int ):
		
		# Initialize with zeros
		var spos = addStream( FlowData.AttrPosition, FlowData.DataType.Vector )
		spos.resize( num_points )
		var srot = addStream( FlowData.AttrRotation, FlowData.DataType.Vector )
		srot.resize( num_points )
		
		# Initialize with ones
		var ssizes : PackedVector3Array = addStream( FlowData.AttrSize, FlowData.DataType.Vector )
		ssizes.resize( num_points )
		var init_value := Vector3.ONE
		for idx : int in range( num_points ):
			ssizes[idx] = init_value

	func getVector3Container( stream_name : StringName ) -> PackedVector3Array:
		var container = getContainerChecked( stream_name, DataType.Vector )
		if container == null:
			container = PackedVector3Array()
		return container

	## Register per-point bounds (UE BoundsMin/BoundsMax parity) from full extents,
	## as a box centered on each point: bounds_min = -extent/2, bounds_max = +extent/2.
	## Generators use this to record a sample's spatial extent (spacing, segment
	## length, surface size) WITHOUT inflating AttrSize — which would otherwise be
	## applied as a Transform scale and stretch spawned meshes. Leave AttrSize unit.
	func setSymmetricBounds( extents : PackedVector3Array ):
		var n := extents.size()
		var bmin := PackedVector3Array()
		var bmax := PackedVector3Array()
		bmin.resize( n )
		bmax.resize( n )
		for i in range( n ):
			var h : Vector3 = extents[i] * 0.5
			bmin[i] = -h
			bmax[i] = h
		registerStream( AttrBoundsMin, bmin, DataType.Vector )
		registerStream( AttrBoundsMax, bmax, DataType.Vector )

	## Per-point bounds resolution (UE PCG BoundsMin/BoundsMax parity).
	##
	## Returns a Dictionary with two PackedVector3Array entries, "min" and "max",
	## holding the LOCAL-space (relative to each point's position) min/max corners
	## of the point's bounds box, one entry per point.
	##
	## Resolution order:
	##  - When BOTH `bounds_min` and `bounds_max` streams are present, they are
	##    used directly (asymmetric bounds preserved). Broadcast (length-1) streams
	##    are honored via bcast_idx.
	##  - Otherwise bounds are derived symmetrically from `size` EXACTLY as the
	##    native broadphase does today: min = -size*0.5, max = +size*0.5. When
	##    `size` is missing, Vector3.ONE is assumed (matching existing fallbacks).
	##
	## This keeps every existing graph byte-for-byte identical: with no bounds
	## streams, "max"-"min" == size and the box center stays on the point.
	func getEffectiveBounds() -> Dictionary:
		var n := size()
		var out_min := PackedVector3Array()
		var out_max := PackedVector3Array()
		out_min.resize( n )
		out_max.resize( n )

		var has_bounds : bool = streams.has( AttrBoundsMin ) and streams.has( AttrBoundsMax )
		if has_bounds:
			var bmin : PackedVector3Array = getVector3Container( AttrBoundsMin )
			var bmax : PackedVector3Array = getVector3Container( AttrBoundsMax )
			# Defensive: if either container is empty/malformed, fall back to size.
			if bmin.size() >= 1 and bmax.size() >= 1:
				for i in range( n ):
					out_min[i] = bmin[ FlowData.bcast_idx( bmin.size(), i ) ]
					out_max[i] = bmax[ FlowData.bcast_idx( bmax.size(), i ) ]
				return { "min": out_min, "max": out_max }

		# Symmetric fallback from `size` — identical to today's center ± size*0.5.
		var sizes : PackedVector3Array = getVector3Container( AttrSize )
		var half := Vector3( 0.5, 0.5, 0.5 )
		for i in range( n ):
			var s : Vector3 = Vector3.ONE
			if sizes.size() >= 1:
				s = sizes[ FlowData.bcast_idx( sizes.size(), i ) ]
			var h : Vector3 = s * half
			out_min[i] = -h
			out_max[i] = h
		return { "min": out_min, "max": out_max }

	## Per-point steepness (UE $Steepness parity). Returns a PackedFloat32Array of
	## length `size()`. When the `steepness` stream is absent, every entry is 1.0
	## (binary box — hard edge), preserving current behavior. Values are clamped
	## to 0..1. Broadcast (length-1) streams are honored.
	func getEffectiveSteepness() -> PackedFloat32Array:
		var n := size()
		var out := PackedFloat32Array()
		out.resize( n )
		var src = getContainerChecked( AttrSteepness, DataType.Float )
		if src == null or src.size() == 0:
			out.fill( 1.0 )
			return out
		var typed : PackedFloat32Array = src
		for i in range( n ):
			out[i] = clampf( typed[ FlowData.bcast_idx( typed.size(), i ) ], 0.0, 1.0 )
		return out

	func getVector4Container( stream_name : StringName ) -> PackedVector4Array:
		var container = getContainerChecked( stream_name, DataType.Quaternion )
		if container == null:
			container = PackedVector4Array()
		return container

	func getTransformsStream() -> TransformsStream:
		# Position and size are always required. Rotation can come from either the
		# Euler `rotation` stream (default) or the optional `rotation_quat`
		# quaternion stream. The quaternion stream WINS when present.
		var has_quat : bool = streams.has(AttrRotationQuat)
		if not (streams.has(AttrPosition) and streams.has(AttrSize)):
			return null
		if not (streams.has(AttrRotation) or has_quat):
			return null
		var trs := TransformsStream.new()
		trs.positions = getVector3Container( AttrPosition )
		trs.sizes = getVector3Container( AttrSize )
		if trs.positions.is_empty() or trs.sizes.is_empty():
			return null
		if trs.sizes.size() != trs.positions.size():
			return null

		if has_quat:
			# Quaternion path wins over Euler when rotation_quat is present.
			trs.quats = getVector4Container( AttrRotationQuat )
			if trs.quats.is_empty() or trs.quats.size() != trs.positions.size():
				return null
			trs.use_quats = true
			# Keep eulers populated too (derived from the quats) so consumers that
			# read trs.eulers directly still get a consistent value.
			var derived_eulers := PackedVector3Array()
			derived_eulers.resize( trs.quats.size() )
			for i in range( trs.quats.size() ):
				derived_eulers[i] = FlowData.quatToEuler( FlowData.vec4ToQuat( trs.quats[i] ) )
			trs.eulers = derived_eulers
			return trs

		# Euler path: unchanged from the historical behavior.
		trs.eulers = getVector3Container( AttrRotation )
		if trs.eulers.is_empty():
			return null
		if trs.sizes.size() == trs.eulers.size():
			return trs
		return null
