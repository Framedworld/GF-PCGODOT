@tool
extends FlowNodeBase

const AttributeSelectSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_select_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Attribute Select",
		"settings" : AttributeSelectSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }, { "label" : "Point" }],
		"tooltip" : "Selects the entry with the Min, Max or Median value of an attribute (vectors by an axis, length or a custom axis).\n" +
			"Out: a one-entry attribute set with the selected value and its index. Point: the selected entry of the input with all its attributes.\n" +
			"Ties keep the first entry.",
		"aliases" : ["Attribute Select", "Select Attribute"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Select %s" % AttributeSelectSettings.eOperation.keys()[ clampi( settings.operation, 0, AttributeSelectSettings.eOperation.size() - 1 ) ]

func _key( value, data_type : int ):
	var D := FlowData.DataType
	var A := AttributeSelectSettings.eAxis
	if data_type == D.String:
		return value
	if Ops.is_numeric_type( data_type ):
		return int( value ) if not Ops.is_real_type( data_type ) else float( value )
	var width := Ops.vector_width( data_type )
	if width == 0:
		return null
	var comps : Array = Ops._components( value, data_type )
	match settings.axis:
		A.Length:
			return Ops._length( comps )
		A.CustomAxis:
			var ax : Vector4 = settings.custom_axis
			var axv := [ ax.x, ax.y, ax.z, ax.w ]
			var s := 0.0
			for k in range( comps.size() ):
				s += comps[k] * axv[k]
			return s
	var idx : int = settings.axis
	if idx >= width:
		return null
	return comps[idx]

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	var n : int = in_data.size()
	if n == 0:
		set_output( 0, FlowData.Data.new() )
		set_output( 1, in_data.duplicate() )
		return
	var read := Ops.read_values( in_data, settings.input_attribute, n, "Input attribute" )
	if not read.ok:
		setError( read.error )
		return
	var keys : Array = []
	for i in range( n ):
		var k = _key( read.values[i], read.data_type )
		if k == null:
			setError( "Attribute '%s' (%s) can't be selected on axis %s" % [ settings.input_attribute, Ops.type_label( read.data_type ), AttributeSelectSettings.eAxis.keys()[settings.axis] ] )
			return
		keys.append( k )
	var order : Array = range( n )
	# Stable: equal keys keep their original order, so ties pick the first entry.
	order.sort_custom( func( a, b ): return keys[a] < keys[b] or ( keys[a] == keys[b] and a < b ) )
	var selected : int
	match settings.operation:
		AttributeSelectSettings.eOperation.Min:
			selected = order[0]
		AttributeSelectSettings.eOperation.Max:
			# First of the entries sharing the maximum key.
			var max_key = keys[ order[n - 1] ]
			selected = order[n - 1]
			for i in range( n ):
				if keys[i] == max_key:
					selected = i
					break
		_:
			selected = order[ ( n - 1 ) >> 1 ]

	var out_set := FlowData.Data.new()
	out_set.tags = in_data.tags.duplicate()
	out_set.kind = FlowData.Kind.AttrSet
	var out_name := Ops.resolve_output_name( settings.output_attribute, read.name )
	var err := Ops.write_stream( out_set, out_name, [ read.values[selected] ], read.data_type )
	if err == "" and settings.index_attribute.strip_edges() != "":
		err = Ops.write_stream( out_set, settings.index_attribute.strip_edges(), [ selected ], FlowData.DataType.Int )
	if err != "":
		setError( err )
		return
	set_output( 0, out_set )
	set_output( 1, in_data.filter( PackedInt32Array( [ selected ] ) ) )
