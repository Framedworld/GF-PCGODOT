@tool
extends FlowNodeBase

const RemoveDuplicatesSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_remove_duplicates_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Attribute Remove Duplicates",
		"settings" : RemoveDuplicatesSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Keeps the first entry of every distinct value (or combination of values) of the listed attributes,\n" +
			"in input order, and removes the later repeats. Values compare exactly, for every attribute type.",
		"aliases" : ["Attribute Remove Duplicates", "Remove Duplicates", "Unique"],
		"category" : "Metadata",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	var n : int = in_data.size()
	if n == 0:
		set_output( 0, in_data.duplicate() )
		return
	if settings.attribute_names.is_empty():
		setError( "List at least one attribute" )
		return
	var columns : Array = []
	for attr in settings.attribute_names:
		var read := Ops.read_values( in_data, attr, n, "Attribute" )
		if not read.ok:
			setError( read.error )
			return
		columns.append( read.values )
	var seen := {}
	var keep := PackedInt32Array()
	for i in range( n ):
		var key : Array = []
		for col in columns:
			var v = col[i]
			# Objects compare by identity; everything else by value.
			key.append( v.get_instance_id() if v is Object and is_instance_valid( v ) else v )
		if seen.has( key ):
			continue
		seen[key] = true
		keep.append( i )
	set_output( 0, in_data.filter( keep ) )
