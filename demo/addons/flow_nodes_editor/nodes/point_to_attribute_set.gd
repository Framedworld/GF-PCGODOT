@tool
extends FlowNodeBase

const PointToAttributeSetNodeSettings = preload("res://addons/flow_nodes_editor/nodes/point_to_attribute_set_settings.gd")

func _init():
	meta_node = {
		"title" : "Point To Attribute Set",
		"settings" : PointToAttributeSetNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Point To Attribute Set"],
		"category" : "Metadata",
		"tooltip" : "Converts point data to attribute-set style data, optionally removing point transform streams.\nWith 'Drop Point Transform Streams' disabled the node is a plain copy.",
	}

func _clone_stream_container(stream : Dictionary):
	match stream.data_type:
		FlowData.DataType.Bool:
			return PackedByteArray(stream.container)
		FlowData.DataType.Int:
			return PackedInt32Array(stream.container)
		FlowData.DataType.Float:
			return PackedFloat32Array(stream.container)
		FlowData.DataType.Vector:
			return PackedVector3Array(stream.container)
		FlowData.DataType.Color:
			return PackedColorArray(stream.container)
		FlowData.DataType.String:
			return PackedStringArray(stream.container)
		_:
			return stream.container.duplicate()

func _copy_stream_if_present(out_data : FlowData.Data, source_name : StringName, target_name : String) -> String:
	if target_name.strip_edges() == "":
		return ""
	if not out_data.hasStream(source_name):
		return ""
	var source_stream = out_data.streams[source_name]
	var container = _clone_stream_container(source_stream)
	# registerStream returns null on success / an error String on failure; this
	# function's contract is "" == OK, so normalise the null (Godot 4.4+ errors on
	# returning Nil from a String-typed function).
	var err = out_data.registerStream(target_name, container, source_stream.data_type)
	return "" if err == null else str(err)

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, _ctx)
	if in_data == null:
		return

	var out_data = in_data.duplicate()
	if not settings.drop_point_transform_streams:
		set_output(0, out_data)
		return

	if settings.preserve_transforms_as_attributes:
		var err = _copy_stream_if_present(out_data, FlowData.AttrPosition, settings.out_position_attribute_name)
		if err:
			setError(err)
			return
		err = _copy_stream_if_present(out_data, FlowData.AttrRotation, settings.out_rotation_attribute_name)
		if err:
			setError(err)
			return
		err = _copy_stream_if_present(out_data, FlowData.AttrSize, settings.out_size_attribute_name)
		if err:
			setError(err)
			return

	out_data.delStream(FlowData.AttrPosition)
	out_data.delStream(FlowData.AttrRotation)
	out_data.delStream(FlowData.AttrSize)

	set_output(0, out_data)
