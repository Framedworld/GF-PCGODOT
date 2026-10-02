@tool
extends FlowNodeBase

const BitwiseOpSettings = preload("res://addons/flow_nodes_editor/nodes/bitwise_op_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Bitwise Op",
		"settings" : BitwiseOpSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Bitwise And, Or, Xor, Not, ShiftLeft, ShiftRight on Bool/Int/Int64 attributes, computed in 64 bits.\n" +
			"The result is Int64 when either operand is Int64, else Int (keeping the low 32 bits); Output Type forces one.\n" +
			"Shift amounts are clamped to 0..63.",
		"aliases" : ["Bitwise Op", "Attribute Bitwise Op"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Bitwise %s" % BitwiseOpSettings.eOperation.keys()[ clampi( settings.operation, 0, BitwiseOpSettings.eOperation.size() - 1 ) ]

static func _is_int_like( t : int ) -> bool:
	return t == FlowData.DataType.Bool or t == FlowData.DataType.Int or t == FlowData.DataType.Int64

func execute( ctx : FlowData.EvaluationContext ):
	var D := FlowData.DataType
	var E := BitwiseOpSettings.eOperation
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
	if not _is_int_like( read_a.data_type ):
		setError( "Input A '%s' is %s; Bitwise Op needs Bool, Int or Int64 (cast it first)" % [ settings.in_nameA, Ops.type_label( read_a.data_type ) ] )
		return
	var op : int = settings.operation
	var b_values : Array = []
	var tb : int = D.Int
	if op != E.Not:
		if settings.use_constant_b:
			b_values = Ops.constant_values( int( settings.constant_b ), n )
		else:
			var read_b := Ops.read_operand( in_a, get_optional_input( 1 ), settings.in_nameB, n, "Input B" )
			if not read_b.ok:
				setError( read_b.error )
				return
			if not _is_int_like( read_b.data_type ):
				setError( "Input B '%s' is %s; Bitwise Op needs Bool, Int or Int64" % [ settings.in_nameB, Ops.type_label( read_b.data_type ) ] )
				return
			tb = read_b.data_type
			b_values = read_b.values

	var out_type : int
	match settings.output_type:
		BitwiseOpSettings.eOutputType.Int:
			out_type = D.Int
		BitwiseOpSettings.eOutputType.Int64:
			out_type = D.Int64
		_:
			out_type = D.Int64 if ( read_a.data_type == D.Int64 or tb == D.Int64 ) else D.Int
	var results : Array = []
	results.resize( n )
	for i in range( n ):
		var a : int = int( read_a.values[i] )
		var b : int = int( b_values[i] ) if op != E.Not else 0
		var r : int
		match op:
			E.And:
				r = a & b
			E.Or:
				r = a | b
			E.Xor:
				r = a ^ b
			E.Not:
				r = ~a
			E.ShiftLeft:
				r = a << clampi( b, 0, 63 )
			E.ShiftRight:
				r = a >> clampi( b, 0, 63 )
		if out_type == D.Int:
			r = Ops._to_int32( r, Ops.eIntOverflow.Wrap )
		results[i] = r
	var out_name := Ops.resolve_output_name( settings.out_name, read_a.name )
	var err := Ops.write_stream( out_data, out_name, results, out_type, out_name == read_a.name )
	if err != "":
		setError( err )
		return
	set_output( 0, out_data )
