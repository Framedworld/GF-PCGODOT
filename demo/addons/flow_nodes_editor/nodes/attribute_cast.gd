@tool
extends FlowNodeBase

const AttributeCastSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_cast_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Attribute Cast",
		"settings" : AttributeCastSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Converts an attribute to another type (Bool, Int, Int64, Float, Double, Vector2, Vector, Vector4, Color, Quaternion, Transform, String).\n" +
			"Loss rules are explicit: Float to Int truncates toward zero (or rounds/floors/ceils), Int64 to Int wraps (or clamps),\n" +
			"Double to Float rounds to 32-bit precision, narrowing vectors drop trailing components, widening pads with 0 (Color alpha with 1),\n" +
			"a scalar broadcasts to every component, and a vector to a scalar is refused unless Vector To Scalar says otherwise.\n" +
			"Vector <-> Quaternion converts Euler degrees; Transform -> Vector is the translation, Transform -> Quaternion the rotation.",
		"aliases" : ["Attribute Cast", "Cast Attribute", "Convert Attribute"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Cast to %s" % Ops.type_label( settings.output_type )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	var n : int = in_data.size()
	var out_data : FlowData.Data = in_data.duplicate()
	if n == 0:
		set_output( 0, out_data )
		return

	var input_name : String = String( settings.input_attribute ).strip_edges()
	var read := Ops.read_values( in_data, input_name, n, "Input attribute" )
	if not read.ok:
		setError( read.error )
		return
	var out_type : int = settings.output_type
	if out_type == FlowData.DataType.Invalid or not FlowData.DataType.values().has( out_type ):
		setError( "Output type %s is not supported" % Ops.type_label( out_type ) )
		return
	var out_name := Ops.resolve_output_name( settings.output_attribute, read.name )

	var options := {
		"float_to_int": settings.float_to_int,
		"int_overflow": settings.int_overflow,
		"vector_to_scalar": settings.vector_to_scalar,
	}
	var values : Array = []
	values.resize( n )
	for i in range( n ):
		var cast := Ops.cast_value( read.values[i], read.data_type, out_type, options )
		if not cast.ok:
			setError( "Point %d: %s" % [ i, cast.error ] )
			return
		values[i] = cast.value

	var err := Ops.write_stream( out_data, out_name, values, out_type, true )
	if err != "":
		setError( err )
		return
	set_output( 0, out_data )
