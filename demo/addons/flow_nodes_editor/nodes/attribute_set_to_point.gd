@tool
extends FlowNodeBase

const AttributeSetToPointNodeSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_set_to_point_settings.gd")

func _init():
	meta_node = {
		"title" : "Attribute Set To Point",
		"settings" : AttributeSetToPointNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Converts attribute rows into point data by providing position/rotation/size streams.\nWith 'Use Defaults When Missing' on, an absent (or mistyped) attribute name falls back to the constant default.",
		"aliases" : ["Attribute Set To Point", "To Point Data"],
		"category" : "Metadata",
	}

func _resolve_vector_stream(in_data : FlowData.Data, attr_name : String, num_points : int, fallback : Vector3, allow_default : bool) -> Dictionary:
	var trimmed = attr_name.strip_edges()
	var stream = in_data.findStream(trimmed) if trimmed != "" else null
	if stream == null:
		if allow_default:
			var container := PackedVector3Array()
			container.resize(num_points)
			for i in range(num_points):
				container[i] = fallback
			return { "ok": true, "container": container }
		return { "ok": false, "error": "Required Vector attribute '%s' not found" % trimmed, "container": PackedVector3Array() }

	if stream.data_type != FlowData.DataType.Vector:
		return { "ok": false, "error": "Attribute '%s' must be a Vector stream" % trimmed, "container": PackedVector3Array() }

	var size = stream.container.size()
	if size != num_points and size != 1:
		return { "ok": false, "error": "Attribute '%s' must have %d values or 1 value (got %d)" % [trimmed, num_points, size], "container": PackedVector3Array() }

	var values : PackedVector3Array = stream.container
	if size == num_points:
		return { "ok": true, "container": values.duplicate() }

	var expanded := PackedVector3Array()
	expanded.resize(num_points)
	for i in range(num_points):
		expanded[i] = values[0]
	return { "ok": true, "container": expanded }

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, _ctx)
	if in_data == null:
		return

	var num_points = in_data.size()
	if num_points == 0:
		set_output(0, in_data.duplicate())
		return

	var allow_default = settings.use_defaults_when_missing

	if settings.transform_attribute_name != "":
		_from_transform(in_data, num_points)
		return

	var pos_result = _resolve_vector_stream(
		in_data,
		settings.position_attribute_name,
		num_points,
		settings.default_position,
		allow_default
	)
	if not pos_result.ok:
		setError(pos_result.error)
		return

	var rot_result = _resolve_vector_stream(
		in_data,
		settings.rotation_attribute_name,
		num_points,
		settings.default_rotation,
		allow_default
	)
	if not rot_result.ok:
		setError(rot_result.error)
		return

	var size_result = _resolve_vector_stream(
		in_data,
		settings.size_attribute_name,
		num_points,
		settings.default_size,
		allow_default
	)
	if not size_result.ok:
		setError(size_result.error)
		return

	var out_data = in_data.duplicate()
	var err = out_data.registerStream(FlowData.AttrPosition, pos_result.container, FlowData.DataType.Vector)
	if err:
		setError(err)
		return

	err = out_data.registerStream(FlowData.AttrRotation, rot_result.container, FlowData.DataType.Vector)
	if err:
		setError(err)
		return

	err = out_data.registerStream(FlowData.AttrSize, size_result.container, FlowData.DataType.Vector)
	if err:
		setError(err)
		return

	set_output(0, out_data)

# Point streams from a Transform attribute (transform_attribute_name).
func _from_transform(in_data : FlowData.Data, num_points : int) -> void:
	var stream = in_data.findStream(settings.transform_attribute_name)
	if stream == null or stream.data_type != FlowData.DataType.Transform:
		setError("Transform attribute '%s' not found or not a Transform" % settings.transform_attribute_name)
		return
	var container = stream.container
	if container.size() != num_points and container.size() != 1:
		setError("Attribute '%s' must have %d values or 1 value (got %d)" % [settings.transform_attribute_name, num_points, container.size()])
		return
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var sizes := PackedVector3Array()
	positions.resize(num_points)
	rotations.resize(num_points)
	sizes.resize(num_points)
	for i in range(num_points):
		var xf : Transform3D = container[FlowData.bcast_idx(container.size(), i)]
		positions[i] = xf.origin
		rotations[i] = FlowData.quatToEuler(xf.basis.get_rotation_quaternion())
		sizes[i] = xf.basis.get_scale()
	var out_data = in_data.duplicate()
	var err = out_data.registerStream(FlowData.AttrPosition, positions, FlowData.DataType.Vector)
	if not err:
		err = out_data.registerStream(FlowData.AttrRotation, rotations, FlowData.DataType.Vector)
	if not err:
		err = out_data.registerStream(FlowData.AttrSize, sizes, FlowData.DataType.Vector)
	if err:
		setError(err)
		return
	set_output(0, out_data)
