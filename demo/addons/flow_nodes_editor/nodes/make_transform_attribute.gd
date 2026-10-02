@tool
extends FlowNodeBase

const MakeTransformSettings = preload("res://addons/flow_nodes_editor/nodes/make_transform_attribute_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Make Transform Attribute",
		"settings" : MakeTransformSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Builds a Transform attribute from translation, rotation and scale attributes (or constants).\n" +
			"Composition is UE's: scale, then rotate, then translate (basis = R * S).\n" +
			"Rotation reads Euler degrees from a Vector attribute, or a Quaternion / Vector4 attribute.\n" +
			"The defaults (position, rotation, size) turn each point's transform into an attribute.",
		"aliases" : ["Make Transform Attribute", "Make Transform"],
		"category" : "Metadata",
	}

func _read_or_default( in_data : FlowData.Data, attr : String, n : int, fallback, label : String, allowed : Array ) -> Dictionary:
	if attr.strip_edges() == "":
		return { "ok": true, "values": Ops.constant_values( fallback, n ), "data_type": FlowData.DataType.Vector }
	var read := Ops.read_values( in_data, attr, n, label )
	if not read.ok:
		return read
	if not allowed.has( read.data_type ):
		return { "ok": false, "error": "%s '%s' is %s; expected %s" % [ label, attr, Ops.type_label( read.data_type ), " or ".join( allowed.map( func( t ): return Ops.type_label( t ) ) ) ] }
	return read

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
	var t := _read_or_default( in_data, settings.translation_attribute, n, settings.default_translation, "Translation", [ D.Vector ] )
	if not t.ok:
		setError( t.error )
		return
	var r := _read_or_default( in_data, settings.rotation_attribute, n, settings.default_rotation, "Rotation", [ D.Vector, D.Quaternion, D.Vector4 ] )
	if not r.ok:
		setError( r.error )
		return
	var s := _read_or_default( in_data, settings.scale_attribute, n, settings.default_scale, "Scale", [ D.Vector ] )
	if not s.ok:
		setError( s.error )
		return
	var results : Array = []
	results.resize( n )
	for i in range( n ):
		var rot = r.values[i]
		if r.data_type == D.Vector4:
			rot = FlowData.vec4ToQuat( rot )
		results[i] = Ops.make_transform( t.values[i], rot, s.values[i] )
	var err := Ops.write_stream( out_data, settings.out_name, results, D.Transform )
	if err != "":
		setError( err )
		return
	set_output( 0, out_data )
