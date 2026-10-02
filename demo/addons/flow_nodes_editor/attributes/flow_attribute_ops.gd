@tool
class_name FlowAttributeOps
extends RefCounted

## Shared helpers for the attribute-type nodes (attribute_cast, compare_op,
## vector_op, transform_op, trig_op, bitwise_op, attribute_string_op,
## copy_attribute, make/break_transform_attribute, merge_attributes, ...).
##
## Values are read per point as Variants (broadcast-aware) and written back
## through FlowData.Data.newContainerOfType / writeValue, so every DataType,
## including the extended ones (Vector2, Vector4, Transform, Int64, Double),
## goes through one code path.

## Output selector meaning "the input (source) attribute" (UE @Source).
const SOURCE_SELECTOR := "@Source"

enum eFloatToInt {
	## Toward zero, like a C++ static_cast (UE behaviour). 2.7 -> 2, -2.7 -> -2.
	Truncate,
	## Nearest integer, halves away from zero. 2.5 -> 3, -2.5 -> -3.
	Round,
	## Toward negative infinity. -2.1 -> -3.
	Floor,
	## Toward positive infinity. 2.1 -> 3.
	Ceil,
}

enum eIntOverflow {
	## Keep the low 32 bits (two's complement wrap), like a C++ static_cast.
	Wrap,
	## Clamp to the 32-bit range [-2147483648, 2147483647].
	Clamp,
}

enum eVectorToScalar {
	## Refuse the cast (UE behaviour: a vector does not narrow to a scalar).
	Error,
	## Keep the first component (x / r).
	FirstComponent,
	## Use the vector length.
	Length,
}

const INT32_MIN := -2147483648
const INT32_MAX := 2147483647

# --- Type classes ----------------------------------------------------------------

static func is_source_selector( selector : String ) -> bool:
	return selector.strip_edges().to_lower() == SOURCE_SELECTOR.to_lower()

## Output attribute name: "@Source" (any case) or "" resolve to `source_name`.
static func resolve_output_name( out_name : String, source_name : String ) -> String:
	var trimmed := out_name.strip_edges()
	if trimmed == "" or is_source_selector( trimmed ):
		return source_name
	return trimmed

static func type_label( data_type : int ) -> String:
	var key = FlowData.DataType.find_key( data_type )
	return String( key ) if key != null else str( data_type )

static func is_numeric_type( data_type : int ) -> bool:
	return data_type == FlowData.DataType.Bool or data_type == FlowData.DataType.Int \
		or data_type == FlowData.DataType.Float or data_type == FlowData.DataType.Int64 \
		or data_type == FlowData.DataType.Double

static func is_integer_type( data_type : int ) -> bool:
	return data_type == FlowData.DataType.Int or data_type == FlowData.DataType.Int64

static func is_real_type( data_type : int ) -> bool:
	return data_type == FlowData.DataType.Float or data_type == FlowData.DataType.Double

## Component count of a vector-like type, 0 for anything else.
static func vector_width( data_type : int ) -> int:
	match data_type:
		FlowData.DataType.Vector2:
			return 2
		FlowData.DataType.Vector:
			return 3
		FlowData.DataType.Vector4, FlowData.DataType.Color, FlowData.DataType.Quaternion:
			return 4
	return 0

static func is_object_type( data_type : int ) -> bool:
	return data_type == FlowData.DataType.Resource or data_type == FlowData.DataType.NodeMesh \
		or data_type == FlowData.DataType.NodePath

## Numeric promotion used when two numeric operands meet (Bool < Int < Int64,
## Float < Double; any integer with any real gives the real side, and Int64
## with Float gives Double so no integer bits are lost silently).
static func promote_numeric( a : int, b : int ) -> int:
	if a == b:
		return a
	var D := FlowData.DataType
	if a == D.Bool:
		return b
	if b == D.Bool:
		return a
	if a == D.Double or b == D.Double:
		return D.Double
	if ( a == D.Int64 and b == D.Float ) or ( a == D.Float and b == D.Int64 ):
		return D.Double
	if a == D.Float or b == D.Float:
		return D.Float
	if a == D.Int64 or b == D.Int64:
		return D.Int64
	return D.Int

# --- Reading -----------------------------------------------------------------------

## The stream dictionary for `selector` in `data`, or null, without the
## push_error noise findStream emits for absent component roots.
static func find_stream( data : FlowData.Data, selector : String ):
	if data == null or selector.strip_edges() == "":
		return null
	return data._findStreamQuiet( selector.strip_edges() )

## Reads `selector` from `data` as `n` Variants (a length-1 stream broadcasts).
## Bool streams come back as bool; Quaternion streams as Quaternion.
## Returns { ok, values, data_type, name } or { ok = false, error }.
static func read_values( data : FlowData.Data, selector : String, n : int, label : String = "Attribute" ) -> Dictionary:
	var stream = find_stream( data, selector )
	if stream == null:
		return { "ok": false, "error": "%s '%s' not found" % [ label, selector ] }
	var container = stream.container
	var count : int = container.size()
	if n > 0 and count != n and count != 1:
		return { "ok": false, "error": "%s '%s' has %d values but %d are needed (or 1 to broadcast)" % [ label, selector, count, n ] }
	if n > 0 and count == 0:
		return { "ok": false, "error": "%s '%s' is empty" % [ label, selector ] }
	var values : Array = []
	values.resize( n )
	var data_type : int = stream.data_type
	for i in range( n ):
		values[i] = to_variant( container[ FlowData.bcast_idx( count, i ) ], data_type )
	return { "ok": true, "values": values, "data_type": data_type, "name": String( stream.name ) }

## Operand reader shared by the two-input ops (same order as boolean.gd):
## the attribute is looked up in `data_b` (the optional In B input) first and
## then in `data_a`. Returns what read_values returns.
static func read_operand( data_a : FlowData.Data, data_b, selector : String, n : int, label : String ) -> Dictionary:
	if data_b is FlowData.Data and find_stream( data_b, selector ) != null:
		return read_values( data_b, selector, n, label )
	return read_values( data_a, selector, n, label )

## Converts a raw container element to the Variant the ops work with.
static func to_variant( raw, data_type : int ):
	match data_type:
		FlowData.DataType.Bool:
			return bool( raw )
		FlowData.DataType.Quaternion:
			if raw is Vector4:
				return FlowData.vec4ToQuat( raw )
	return raw

## `n` copies of `value`.
static func constant_values( value, n : int ) -> Array:
	var values : Array = []
	values.resize( n )
	values.fill( value )
	return values

## Parses a constant typed as `data_type` from text: numbers, "true"/"false",
## "x,y,z" component lists (a single number broadcasts to every component),
## and any Godot literal str_to_var understands ("Vector3(1, 2, 3)",
## "Transform3D(...)"). Returns { ok, value } or { ok = false, error }.
static func parse_constant( text : String, data_type : int ) -> Dictionary:
	var t := text.strip_edges()
	var D := FlowData.DataType
	match data_type:
		D.String:
			return { "ok": true, "value": text }
		D.Bool:
			var low := t.to_lower()
			if low in [ "true", "1", "yes", "on" ]:
				return { "ok": true, "value": true }
			if low in [ "false", "0", "no", "off", "" ]:
				return { "ok": true, "value": false }
		D.Int, D.Int64:
			if t.is_valid_int():
				return { "ok": true, "value": t.to_int() }
			if t.is_valid_float():
				return { "ok": true, "value": int( t.to_float() ) }
		D.Float, D.Double:
			if t.is_valid_float():
				return { "ok": true, "value": t.to_float() }
		_:
			var width := vector_width( data_type )
			if width > 0:
				var parsed = _parse_components( t, width )
				if parsed != null:
					return { "ok": true, "value": _components_to_value( parsed, data_type ) }
	var literal = str_to_var( t ) if t != "" else null
	if literal != null:
		var cast := cast_value( literal, _variant_type_to_data_type( literal ), data_type, {} )
		if cast.ok:
			return cast
	return { "ok": false, "error": "Can't read '%s' as %s" % [ text, type_label( data_type ) ] }

static func _parse_components( text : String, width : int ):
	var t := text.strip_edges()
	if t.begins_with( "(" ) and t.ends_with( ")" ):
		t = t.substr( 1, t.length() - 2 )
	var parts := t.split( ",", false )
	if parts.size() == 1 and parts[0].strip_edges().is_valid_float():
		var v := parts[0].strip_edges().to_float()
		var out : Array = []
		out.resize( width )
		out.fill( v )
		return out
	if parts.size() != width:
		return null
	var comps : Array = []
	for p in parts:
		var ps := p.strip_edges()
		if not ps.is_valid_float():
			return null
		comps.append( ps.to_float() )
	return comps

static func _components_to_value( comps : Array, data_type : int ):
	var D := FlowData.DataType
	match data_type:
		D.Vector2:
			return Vector2( comps[0], comps[1] )
		D.Vector:
			return Vector3( comps[0], comps[1], comps[2] )
		D.Vector4:
			return Vector4( comps[0], comps[1], comps[2], comps[3] )
		D.Color:
			return Color( comps[0], comps[1], comps[2], comps[3] )
		D.Quaternion:
			return Quaternion( comps[0], comps[1], comps[2], comps[3] )
	return null

## DataType a Variant would be stored as (Vector4 values map to Vector4 here,
## unlike FlowData's inference which maps them to Quaternion).
static func _variant_type_to_data_type( value ) -> int:
	var D := FlowData.DataType
	match typeof( value ):
		TYPE_BOOL: return D.Bool
		TYPE_INT: return D.Int64
		TYPE_FLOAT: return D.Double
		TYPE_STRING, TYPE_STRING_NAME: return D.String
		TYPE_VECTOR2, TYPE_VECTOR2I: return D.Vector2
		TYPE_VECTOR3, TYPE_VECTOR3I: return D.Vector
		TYPE_VECTOR4, TYPE_VECTOR4I: return D.Vector4
		TYPE_COLOR: return D.Color
		TYPE_QUATERNION: return D.Quaternion
		TYPE_TRANSFORM3D, TYPE_BASIS: return D.Transform
	if value is Resource:
		return D.Resource
	if value is Node:
		return D.NodeMesh
	return D.Invalid

# --- Writing -----------------------------------------------------------------------

## A container of `data_type` holding `values` (written through writeValue, so
## Bool becomes 0/1 bytes and Quaternion/Vector4 values are stored as Vector4).
static func make_container( values : Array, data_type : int ):
	var container = FlowData.Data.newContainerOfType( data_type )
	if container == null:
		return null
	container.resize( values.size() )
	for i in range( values.size() ):
		FlowData.Data.writeValue( container, i, values[i], data_type )
	return container

## Registers `values` as stream `name` of `data_type` in `out_data`. When
## `replace_type` is set and a stream of that name exists with another type it
## is removed first (an intended retype, e.g. a cast in place) instead of
## overwritten with a conflict warning. Returns "" or the error.
static func write_stream( out_data : FlowData.Data, name : String, values : Array, data_type : int, replace_type : bool = false ) -> String:
	if name.strip_edges() == "":
		return "Output attribute name can't be empty"
	var container = make_container( values, data_type )
	if container == null:
		return "Can't create a %s container" % type_label( data_type )
	if replace_type and out_data.streams.has( name ) and out_data.streams[name].data_type != data_type:
		var canonical := FlowData.canonical_type_error( name, data_type )
		if canonical != "":
			return canonical
		out_data.delStream( name )
	var err = out_data.registerStream( name, container, data_type )
	return "" if err == null else str( err )

# --- Casting -----------------------------------------------------------------------

## Converts `value` (read from a `from_type` stream) to `to_type`.
## Options: float_to_int (eFloatToInt), int_overflow (eIntOverflow),
## vector_to_scalar (eVectorToScalar). Returns { ok, value } or { ok = false, error }.
## The full rule table is in docs/_round2/WP4a.md (Attribute Cast).
static func cast_value( value, from_type : int, to_type : int, options : Dictionary ) -> Dictionary:
	var D := FlowData.DataType
	var float_to_int : int = options.get( "float_to_int", eFloatToInt.Truncate )
	var int_overflow : int = options.get( "int_overflow", eIntOverflow.Wrap )
	var vector_to_scalar : int = options.get( "vector_to_scalar", eVectorToScalar.Error )

	if from_type == D.Bool:
		value = bool( value )
	elif from_type == D.Quaternion and value is Vector4:
		value = FlowData.vec4ToQuat( value )

	if to_type == D.String:
		return _ok( _value_to_string( value, from_type ) )

	if from_type == to_type:
		return _ok( value )

	# Objects only convert to String (above) or to themselves.
	if is_object_type( from_type ) or is_object_type( to_type ):
		if is_object_type( from_type ) and is_object_type( to_type ):
			return _ok( value )
		return _err( "%s can't be cast to %s" % [ type_label( from_type ), type_label( to_type ) ] )

	if from_type == D.String:
		return _cast_from_string( String( value ), to_type, options )

	# Scalar source
	if is_numeric_type( from_type ):
		var num = value
		if num is bool:
			num = 1 if num else 0
		match to_type:
			D.Bool:
				return _ok( num != 0 )
			D.Int:
				return _ok( _to_int32( _real_to_int( num, float_to_int ), int_overflow ) )
			D.Int64:
				return _ok( _real_to_int( num, float_to_int ) )
			D.Float, D.Double:
				return _ok( float( num ) )
			D.Vector2:
				return _ok( Vector2( num, num ) )
			D.Vector:
				return _ok( Vector3( num, num, num ) )
			D.Vector4:
				return _ok( Vector4( num, num, num, num ) )
			D.Color:
				return _ok( Color( num, num, num, 1.0 ) )
		return _err( "%s can't be cast to %s" % [ type_label( from_type ), type_label( to_type ) ] )

	# Transform source
	if from_type == D.Transform:
		var xf : Transform3D = value
		match to_type:
			D.Vector:
				return _ok( xf.origin )
			D.Quaternion:
				return _ok( xf.basis.orthonormalized().get_rotation_quaternion() )
		return _err( "Transform can only be cast to Vector (translation), Quaternion (rotation) or String, not %s" % type_label( to_type ) )

	# Vector-like source (Vector2, Vector, Vector4, Color, Quaternion)
	var width := vector_width( from_type )
	if width > 0:
		if to_type == D.Transform:
			if from_type == D.Vector:
				return _ok( Transform3D( Basis.IDENTITY, value ) )
			if from_type == D.Quaternion:
				return _ok( Transform3D( Basis( value ), Vector3.ZERO ) )
			return _err( "%s can't be cast to Transform (only Vector and Quaternion can)" % type_label( from_type ) )
		# Rotation semantics between Euler degrees and quaternions.
		if from_type == D.Quaternion and to_type == D.Vector:
			return _ok( FlowData.quatToEuler( value ) )
		if from_type == D.Vector and to_type == D.Quaternion:
			return _ok( FlowData.eulerToQuat( value ) )
		if to_type == D.Quaternion and from_type != D.Vector4 and from_type != D.Color:
			return _err( "%s can't be cast to Quaternion (use Vector for Euler degrees, or Vector4)" % type_label( from_type ) )
		var comps := _components( value, from_type )
		if is_numeric_type( to_type ):
			match vector_to_scalar:
				eVectorToScalar.FirstComponent:
					return cast_value( comps[0], D.Double, to_type, options )
				eVectorToScalar.Length:
					return cast_value( _length( comps ), D.Double, to_type, options )
			return _err( "%s can't be cast to the scalar %s (set Vector To Scalar to First Component or Length)" % [ type_label( from_type ), type_label( to_type ) ] )
		var out_width := vector_width( to_type )
		if out_width > 0:
			var out : Array = []
			for i in range( out_width ):
				if i < comps.size():
					out.append( comps[i] )
				else:
					out.append( 1.0 if ( to_type == D.Color and i == 3 ) else 0.0 )
			return _ok( _components_to_value( out, to_type ) )
	return _err( "%s can't be cast to %s" % [ type_label( from_type ), type_label( to_type ) ] )

static func _ok( value ) -> Dictionary:
	return { "ok": true, "value": value }

static func _err( message : String ) -> Dictionary:
	return { "ok": false, "error": message }

static func _components( value, data_type : int ) -> Array:
	match data_type:
		FlowData.DataType.Vector2:
			return [ value.x, value.y ]
		FlowData.DataType.Vector:
			return [ value.x, value.y, value.z ]
		FlowData.DataType.Color:
			return [ value.r, value.g, value.b, value.a ]
	return [ value.x, value.y, value.z, value.w ]

static func _length( comps : Array ) -> float:
	var sq := 0.0
	for c in comps:
		sq += c * c
	return sqrt( sq )

static func _real_to_int( num, mode : int ) -> int:
	if num is int:
		return num
	var f := float( num )
	if is_nan( f ):
		return 0
	match mode:
		eFloatToInt.Round:
			f = roundf( f )
		eFloatToInt.Floor:
			f = floorf( f )
		eFloatToInt.Ceil:
			f = ceilf( f )
		_:
			f = floorf( f ) if f >= 0.0 else ceilf( f )
	# Keep inside the 64-bit range before converting (int() of an out of range
	# float is undefined).
	if f >= 9.2233720368547758e18:
		return 9223372036854775807
	if f <= -9.2233720368547758e18:
		return -9223372036854775807 - 1
	return int( f )

static func _to_int32( v : int, mode : int ) -> int:
	if v >= INT32_MIN and v <= INT32_MAX:
		return v
	if mode == eIntOverflow.Clamp:
		return clampi( v, INT32_MIN, INT32_MAX )
	var low := v & 0xffffffff
	return low - 0x100000000 if low > INT32_MAX else low

static func _value_to_string( value, from_type : int ) -> String:
	if value == null:
		return ""
	if value is bool:
		return "true" if value else "false"
	if value is Resource:
		return value.resource_path
	if value is Node:
		return String( value.name )
	return str( value )

static func _cast_from_string( text : String, to_type : int, options : Dictionary ) -> Dictionary:
	var D := FlowData.DataType
	var t := text.strip_edges()
	match to_type:
		D.Int, D.Int64:
			var int_value : int
			if t.is_valid_int():
				int_value = t.to_int()
			elif t.is_valid_float():
				int_value = _real_to_int( t.to_float(), options.get( "float_to_int", eFloatToInt.Truncate ) )
			else:
				return _err( "Can't parse '%s' as %s" % [ text, type_label( to_type ) ] )
			if to_type == D.Int:
				int_value = _to_int32( int_value, options.get( "int_overflow", eIntOverflow.Wrap ) )
			return _ok( int_value )
		D.Float, D.Double:
			if t.is_valid_float():
				return _ok( t.to_float() )
			return _err( "Can't parse '%s' as %s" % [ text, type_label( to_type ) ] )
	var parsed := parse_constant( text, to_type )
	if parsed.ok:
		return parsed
	return _err( "Can't parse '%s' as %s" % [ text, type_label( to_type ) ] )

# --- Transforms --------------------------------------------------------------------

## Standard TRS composition (UE FTransform order: scale, then rotate, then
## translate): basis = R * S.
static func make_transform( translation : Vector3, rotation, scale : Vector3 ) -> Transform3D:
	var rot_basis : Basis
	if rotation is Quaternion:
		rot_basis = Basis( rotation )
	else:
		rot_basis = FlowData.eulerToBasis( rotation )
	return Transform3D( rot_basis * Basis.from_scale( scale ), translation )

## The point transform of point `i` built with make_transform from the
## position / rotation (or rotation_quat) / size streams.
static func point_transform( positions, rotations, quats, sizes, i : int ) -> Transform3D:
	var p : Vector3 = positions[ FlowData.bcast_idx( positions.size(), i ) ] if positions != null and positions.size() > 0 else Vector3.ZERO
	var s : Vector3 = sizes[ FlowData.bcast_idx( sizes.size(), i ) ] if sizes != null and sizes.size() > 0 else Vector3.ONE
	var r = Vector3.ZERO
	if quats != null and quats.size() > 0:
		r = FlowData.vec4ToQuat( quats[ FlowData.bcast_idx( quats.size(), i ) ] )
	elif rotations != null and rotations.size() > 0:
		r = rotations[ FlowData.bcast_idx( rotations.size(), i ) ]
	return make_transform( p, r, s )

## { translation : Vector3, rotation : Vector3 (Euler degrees), quaternion, scale }.
static func break_transform( xf : Transform3D ) -> Dictionary:
	var scale := xf.basis.get_scale()
	var q := xf.basis.get_rotation_quaternion()
	return {
		"translation": xf.origin,
		"rotation": FlowData.quatToEuler( q ),
		"quaternion": q,
		"scale": scale,
	}

## The rotation of `xf` as Euler degrees, matching the point `rotation` convention.
static func euler_of( xf : Transform3D ) -> Vector3:
	return FlowData.quatToEuler( xf.basis.get_rotation_quaternion() )

## Lerp between two transforms: translation and scale linearly, rotation by slerp.
static func lerp_transform( a : Transform3D, b : Transform3D, t : float ) -> Transform3D:
	var qa := a.basis.get_rotation_quaternion()
	var qb := b.basis.get_rotation_quaternion()
	var sa := a.basis.get_scale()
	var sb := b.basis.get_scale()
	var q := qa.slerp( qb, t )
	return Transform3D( Basis( q ) * Basis.from_scale( sa.lerp( sb, t ) ), a.origin.lerp( b.origin, t ) )
