@tool
extends FlowNodeBase

const TrigOpSettings = preload("res://addons/flow_nodes_editor/nodes/trig_op_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Trig Op",
		"settings" : TrigOpSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Trigonometry per point: Sin, Cos, Tan, Asin, Acos, Atan, Atan2 (A = y, B = x), DegToRad, RadToDeg. Angles are radians.\n" +
			"Bool/Int/Float inputs give Float, Int64/Double inputs give Double, Vector2/Vector/Vector4 inputs work per component and keep their type.",
		"aliases" : ["Trig Op", "Attribute Trig Op", "Trigonometry"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Trig %s" % TrigOpSettings.eOperation.keys()[ clampi( settings.operation, 0, TrigOpSettings.eOperation.size() - 1 ) ]

func execute( ctx : FlowData.EvaluationContext ):
	var D := FlowData.DataType
	var E := TrigOpSettings.eOperation
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
	var ta : int = read_a.data_type
	var width := Ops.vector_width( ta )
	var vector_input : bool = ta == D.Vector2 or ta == D.Vector or ta == D.Vector4
	if not Ops.is_numeric_type( ta ) and not vector_input:
		setError( "Input A '%s' is %s; Trig Op needs a number or a Vector2/Vector/Vector4" % [ settings.in_nameA, Ops.type_label( ta ) ] )
		return
	var op : int = settings.operation

	var b_values : Array = []
	var tb : int = D.Float
	if op == E.Atan2:
		if settings.use_constant_b:
			b_values = Ops.constant_values( settings.constant_b, n )
		else:
			var read_b := Ops.read_operand( in_a, get_optional_input( 1 ), settings.in_nameB, n, "Input B" )
			if not read_b.ok:
				setError( read_b.error )
				return
			tb = read_b.data_type
			var b_vector : bool = Ops.vector_width( tb ) > 0
			if not Ops.is_numeric_type( tb ) and not ( b_vector and tb == ta ):
				setError( "Input B '%s' is %s; it must be a number or the same vector type as A" % [ settings.in_nameB, Ops.type_label( tb ) ] )
				return
			b_values = read_b.values

	var out_type : int = ta
	if not vector_input:
		out_type = D.Double if ( ta == D.Int64 or ta == D.Double or tb == D.Double or tb == D.Int64 ) else D.Float
	var results : Array = []
	results.resize( n )
	for i in range( n ):
		if vector_input:
			var comps : Array = Ops._components( read_a.values[i], ta )
			var bcomps : Array = []
			if op == E.Atan2:
				var bv = b_values[i]
				bcomps = Ops._components( bv, ta ) if Ops.vector_width( tb ) > 0 else Ops.constant_values( float( bv ), width )
			var out : Array = []
			for k in range( comps.size() ):
				out.append( _apply( op, float( comps[k] ), float( bcomps[k] ) if op == E.Atan2 else 0.0 ) )
			results[i] = Ops._components_to_value( out, ta )
		else:
			var a := float( read_a.values[i] )
			results[i] = _apply( op, a, float( b_values[i] ) if op == E.Atan2 else 0.0 )
	var out_name := Ops.resolve_output_name( settings.out_name, read_a.name )
	var err := Ops.write_stream( out_data, out_name, results, out_type, out_name == read_a.name )
	if err != "":
		setError( err )
		return
	set_output( 0, out_data )

static func _apply( op : int, a : float, b : float ) -> float:
	var E := TrigOpSettings.eOperation
	match op:
		E.Sin:
			return sin( a )
		E.Cos:
			return cos( a )
		E.Tan:
			return tan( a )
		E.Asin:
			return asin( clampf( a, -1.0, 1.0 ) )
		E.Acos:
			return acos( clampf( a, -1.0, 1.0 ) )
		E.Atan:
			return atan( a )
		E.Atan2:
			return atan2( a, b )
		E.DegToRad:
			return deg_to_rad( a )
		E.RadToDeg:
			return rad_to_deg( a )
	return a
