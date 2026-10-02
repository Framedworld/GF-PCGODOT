@tool
extends FlowNodeBase

const CompareOpSettings = preload("res://addons/flow_nodes_editor/nodes/compare_op_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Compare Op",
		"settings" : CompareOpSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Compares two attributes (or an attribute and a constant) per point and writes a Bool attribute.\n" +
			"Operators: == != > >= < <=. Numbers compare across Bool/Int/Int64/Float/Double (integers exactly, reals within Tolerance for == and !=).\n" +
			"Strings compare lexicographically (optionally case-insensitive). Vectors compare per component (all or any) or by length.\n" +
			"Transforms and objects support == and != only. Unlike Filter, the points are not split: use the Bool with Filter or Branch.",
		"aliases" : ["Compare Op", "Attribute Compare Op", "Compare"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Compare (%s)" % CompareOpSettings.eOperation.keys()[ clampi( settings.operation, 0, CompareOpSettings.eOperation.size() - 1 ) ]

func execute( ctx : FlowData.EvaluationContext ):
	var in_a : FlowData.Data = require_input( 0, ctx, "Input A" )
	if in_a == null:
		return
	var n : int = in_a.size()
	var out_data : FlowData.Data = in_a.duplicate()
	if n == 0:
		set_output( 0, out_data )
		return
	var read_a := Ops.read_values( in_a, settings.in_nameA, n, "Input A" )
	if not read_a.ok:
		setError( read_a.error )
		return
	var read_b : Dictionary
	if settings.use_constant_b:
		# A fractional constant against an integer A stays a real number:
		# parsing "1.5" as Int would truncate it and make 1 >= "1.5" true.
		var b_type : int = read_a.data_type
		var text : String = settings.constant_b.strip_edges()
		if Ops.is_integer_type( b_type ) and not text.is_valid_int() and text.is_valid_float():
			b_type = FlowData.DataType.Double
		var parsed := Ops.parse_constant( settings.constant_b, b_type )
		if not parsed.ok:
			setError( "Constant B: %s" % parsed.error )
			return
		read_b = { "ok": true, "values": Ops.constant_values( parsed.value, n ), "data_type": b_type }
	else:
		read_b = Ops.read_operand( in_a, get_optional_input( 1 ), settings.in_nameB, n, "Input B" )
		if not read_b.ok:
			setError( read_b.error )
			return

	var results : Array = []
	results.resize( n )
	for i in range( n ):
		var r := compare( read_a.values[i], read_a.data_type, read_b.values[i], read_b.data_type,
			settings.operation, settings.tolerance, settings.vector_mode, settings.case_sensitive )
		if not r.ok:
			setError( r.error )
			return
		results[i] = r.value
	var err := Ops.write_stream( out_data, settings.out_name, results, FlowData.DataType.Bool )
	if err != "":
		setError( err )
		return
	set_output( 0, out_data )

## Compares one pair of values. Returns { ok, value : bool } or { ok = false, error }.
static func compare( a, ta : int, b, tb : int, op : int, tolerance : float, vector_mode : int, case_sensitive : bool ) -> Dictionary:
	var D := FlowData.DataType
	var E := CompareOpSettings.eOperation
	var is_eq_op : bool = op == E.Equal or op == E.NotEqual

	if Ops.is_numeric_type( ta ) and Ops.is_numeric_type( tb ):
		var both_int : bool = not Ops.is_real_type( ta ) and not Ops.is_real_type( tb )
		var av = int( a ) if both_int else float( a )
		var bv = int( b ) if both_int else float( b )
		return { "ok": true, "value": _relation( av, bv, op, tolerance ) }

	if ta == D.String and tb == D.String:
		var sa : String = a if case_sensitive else String( a ).to_lower()
		var sb : String = b if case_sensitive else String( b ).to_lower()
		return { "ok": true, "value": _relation( sa, sb, op, -1.0 ) }

	var wa := Ops.vector_width( ta )
	var wb := Ops.vector_width( tb )
	if wa > 0 and ( wb > 0 or Ops.is_numeric_type( tb ) ):
		var ca := _components( a, ta )
		var cb : Array
		if wb > 0:
			cb = _components( b, tb )
			if cb.size() != ca.size():
				return { "ok": false, "error": "Can't compare %s with %s (different component counts)" % [ Ops.type_label( ta ), Ops.type_label( tb ) ] }
		else:
			cb = Ops.constant_values( float( b ), ca.size() )
		if vector_mode == CompareOpSettings.eVectorMode.Length:
			return { "ok": true, "value": _relation( _len( ca ), _len( cb ), op, tolerance ) }
		var any_mode : bool = vector_mode == CompareOpSettings.eVectorMode.AnyComponent
		var rel_op : int = E.Equal if op == E.NotEqual else op
		var combined : bool = not any_mode
		for k in range( ca.size() ):
			var r := _relation( float( ca[k] ), float( cb[k] ), rel_op, tolerance )
			combined = ( combined or r ) if any_mode else ( combined and r )
		return { "ok": true, "value": ( not combined ) if op == E.NotEqual else combined }

	if ta == D.Transform and tb == D.Transform:
		if not is_eq_op:
			return { "ok": false, "error": "Transforms only support == and !=" }
		var eq := _transform_equal( a, b, tolerance )
		return { "ok": true, "value": eq if op == E.Equal else not eq }

	if Ops.is_object_type( ta ) and Ops.is_object_type( tb ):
		if not is_eq_op:
			return { "ok": false, "error": "Objects only support == and !=" }
		var same : bool = a == b
		return { "ok": true, "value": same if op == E.Equal else not same }

	return { "ok": false, "error": "Can't compare %s with %s" % [ Ops.type_label( ta ), Ops.type_label( tb ) ] }

static func _relation( a, b, op : int, tolerance : float ) -> bool:
	var E := CompareOpSettings.eOperation
	match op:
		E.Equal:
			# Integers compare exactly: a - b can overflow for Int64 values.
			if tolerance >= 0.0 and not ( a is String ) and not ( a is int and b is int ):
				return absf( float( a - b ) ) <= tolerance
			return a == b
		E.NotEqual:
			return not _relation( a, b, E.Equal, tolerance )
		E.Greater:
			return a > b
		E.GreaterOrEqual:
			return a >= b
		E.Less:
			return a < b
		E.LessOrEqual:
			return a <= b
	return false

static func _components( v, t : int ) -> Array:
	match t:
		FlowData.DataType.Vector2:
			return [ v.x, v.y ]
		FlowData.DataType.Vector:
			return [ v.x, v.y, v.z ]
		FlowData.DataType.Color:
			return [ v.r, v.g, v.b, v.a ]
	return [ v.x, v.y, v.z, v.w ]

static func _len( c : Array ) -> float:
	var s := 0.0
	for x in c:
		s += float( x ) * float( x )
	return sqrt( s )

static func _transform_equal( a : Transform3D, b : Transform3D, tolerance : float ) -> bool:
	for axis in range( 3 ):
		for k in range( 3 ):
			if absf( a.basis[axis][k] - b.basis[axis][k] ) > tolerance:
				return false
	for k in range( 3 ):
		if absf( a.origin[k] - b.origin[k] ) > tolerance:
			return false
	return true
