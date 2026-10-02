@tool
extends FlowNodeBase

# UE PCG parity: Get Attribute From Point Index. Reads one point's attribute
# value and publishes it three ways: a one-row attribute set ("Attribute Set",
# Unreal's attribute pin), the point itself ("Point", Unreal's point pin) and
# the input with the value stored as a per-data attribute ("Out", read back
# downstream with "@data.<name>").

func _init():
	meta_node = {
		"title" : "Get Attribute From Point Index",
		"settings" : GetAttributeFromPointIndexNodeSettings,
		"aliases" : ["Get Attribute From Point Index", "Get Attribute from Point Index", "Point Attribute At Index", "Read Point Attribute"],
		"category" : "Metadata",
		"pure" : true,
		"main_thread" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Attribute Set" }, { "label" : "Point" }, { "label" : "Out" }],
		"tooltip" : "Reads 'input_attribute' of the point at 'index' (negative counts from the end).\nAttribute Set: a one-row attribute set holding the value as 'output_attribute'.\nPoint: that single point with all its attributes.\nOut: the input unchanged plus the value as the per-data attribute @data.<output_attribute>.\nA missing attribute or an index outside the input is an error (outputs are then empty / the input).",
	}

## Output attribute name derived from a resolved stream name.
static func derive_output_name( stream_name : String ) -> String:
	var out_name := stream_name
	if out_name.begins_with( FlowData.DataAttrPrefix ):
		out_name = out_name.substr( FlowData.DataAttrPrefix.length() )
	return out_name.replace( ".", "_" )

func _emit_empty( in_data : FlowData.Data ) -> void:
	set_output( 0, FlowData.Data.new() )
	set_output( 1, in_data.filter( PackedInt32Array() ) )
	set_output( 2, in_data )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		if num_generated_bulks > 0 and generated_bulks[num_generated_bulks - 1].size() == 1:
			set_output( 1, FlowData.Data.new() )
			set_output( 2, FlowData.Data.new() )
		return

	var attr : String = String( getSettingValue( ctx, "input_attribute", settings.input_attribute ) ).strip_edges()
	if attr == "":
		setError( "Input attribute is empty" )
		_emit_empty( in_data )
		return
	if attr == "@last" and in_data.last_added_stream_name == "":
		setError( "Input has no @last attribute" )
		_emit_empty( in_data )
		return
	var stream = in_data.findStream( attr )
	if stream == null:
		setError( "Attribute '%s' not found" % attr )
		_emit_empty( in_data )
		return

	var n := in_data.size()
	var count : int = stream.container.size() if attr.begins_with( FlowData.DataAttrPrefix ) and n == 0 else n
	var idx : int = int( getSettingValue( ctx, "index", settings.index ) )
	var resolved := idx + count if idx < 0 else idx
	if resolved < 0 or resolved >= count:
		setError( "Index %d is out of range for %d points" % [ idx, count ] )
		_emit_empty( in_data )
		return

	var out_name : String = String( settings.output_attribute ).strip_edges()
	if out_name == "":
		out_name = derive_output_name( String( stream.name ) )
	var data_type : FlowData.DataType = stream.data_type
	var canonical_error := FlowData.canonical_type_error( out_name, data_type )
	if canonical_error != "":
		setError( canonical_error )
		_emit_empty( in_data )
		return

	var value = stream.container[ FlowData.bcast_idx( stream.container.size(), resolved ) ]
	if data_type == FlowData.DataType.Bool:
		value = bool( value )

	var attr_set := FlowData.Data.scalar( out_name, value, data_type )
	attr_set.kind = FlowData.Kind.AttrSet
	attr_set.tags = in_data.tags.duplicate()

	var point : FlowData.Data = in_data.filter( PackedInt32Array( [ resolved ] ) ) if n > 0 else in_data.filter( PackedInt32Array() )

	var out_data : FlowData.Data = in_data.duplicate()
	out_data.set_data_attr( out_name, value, data_type )

	set_output( 0, attr_set )
	set_output( 1, point )
	set_output( 2, out_data )
