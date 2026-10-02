@tool
extends FlowNodeBase

const BreakTransformSettings = preload("res://addons/flow_nodes_editor/nodes/break_transform_attribute_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Break Transform Attribute",
		"settings" : BreakTransformSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Splits a Transform attribute into translation (Vector), rotation (Euler degrees and/or Quaternion) and scale (Vector).\n" +
			"Inverse of Make Transform Attribute for transforms without shear. Leave an output name empty to skip it;\n" +
			"write to position / rotation / size to set the point transform.",
		"aliases" : ["Break Transform Attribute", "Break Transform"],
		"category" : "Metadata",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var D := FlowData.DataType
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	var n : int = in_data.size()
	var out_data : FlowData.Data = in_data.duplicate()
	if n == 0:
		set_output( 0, out_data )
		return
	var read := Ops.read_values( in_data, settings.in_name, n, "Transform attribute" )
	if not read.ok:
		setError( read.error )
		return
	if read.data_type != D.Transform:
		setError( "Attribute '%s' is %s, not a Transform (Attribute Cast or Make Transform Attribute can make one)" % [ settings.in_name, Ops.type_label( read.data_type ) ] )
		return
	var translations : Array = []
	var rotations : Array = []
	var quats : Array = []
	var scales : Array = []
	for i in range( n ):
		var parts := Ops.break_transform( read.values[i] )
		translations.append( parts.translation )
		rotations.append( parts.rotation )
		quats.append( parts.quaternion )
		scales.append( parts.scale )
	var outputs := [
		[ settings.out_translation, translations, D.Vector ],
		[ settings.out_rotation, rotations, D.Vector ],
		[ settings.out_quaternion, quats, D.Quaternion ],
		[ settings.out_scale, scales, D.Vector ],
	]
	for o in outputs:
		var out_name : String = String( o[0] ).strip_edges()
		if out_name == "":
			continue
		var err := Ops.write_stream( out_data, out_name, o[1], o[2] )
		if err != "":
			setError( err )
			return
	set_output( 0, out_data )
