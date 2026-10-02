@tool
extends FlowNodeBase

const ComposeVectorNodeSettings = preload("res://addons/flow_nodes_editor/nodes/compose_vector_settings.gd")

func _init():
	meta_node = {
		"title" : "Compose Vector",
		"settings" : ComposeVectorNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Composes a Vector3 attribute from float attributes or default values.\nNote: the default output attribute is 'size', which overwrites the canonical point size stream.",
		"aliases" : ["Make Vector Attribute"],
		"category" : "Metadata",
	}

func _resolve_component_stream(in_data : FlowData.Data, attr_name : String, num_points : int, label : String) -> Dictionary:
	if attr_name == "":
		return { "ok": true, "stream": null, "size": 0 }
	var stream = in_data.findStream(attr_name)
	if stream == null:
		# Keep the default-component fallback (back-compat), but surface possible typos
		push_warning("Compose Vector: %s attribute '%s' not found — using the default component value" % [label, attr_name])
		return { "ok": true, "stream": null, "size": 0 }
	if stream.data_type != FlowData.DataType.Float and stream.data_type != FlowData.DataType.Int and stream.data_type != FlowData.DataType.Bool \
			and stream.data_type != FlowData.DataType.Int64 and stream.data_type != FlowData.DataType.Double:
		return { "ok": false, "error": "%s attribute '%s' must be a Float/Int/Bool/Int64/Double stream" % [label, attr_name] }
	var size : int = stream.container.size()
	if size != num_points and size != 1:
		return { "ok": false, "error": "%s attribute '%s' has %d values but input has %d points (expected %d or 1)" % [label, attr_name, size, num_points, num_points] }
	return { "ok": true, "stream": stream, "size": size }

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var out_data : FlowData.Data = in_data.duplicate()
	var size = in_data.size()

	var rx = _resolve_component_stream(in_data, settings.x_attribute, size, "X")
	if not rx.ok:
		setError(rx.error)
		return
	var ry = _resolve_component_stream(in_data, settings.y_attribute, size, "Y")
	if not ry.ok:
		setError(ry.error)
		return
	var rz = _resolve_component_stream(in_data, settings.z_attribute, size, "Z")
	if not rz.ok:
		setError(rz.error)
		return

	var output_type : int = settings.output_type
	if output_type != ComposeVectorNodeSettings.eOutputType.Vector:
		_compose_other(in_data, out_data, size, rx, ry, rz, output_type)
		return

	var out_vec := PackedVector3Array()
	out_vec.resize(size)

	for i in range(size):
		var vx = float(rx.stream.container[FlowData.bcast_idx(rx.size, i)]) if rx.stream else settings.default_value.x
		var vy = float(ry.stream.container[FlowData.bcast_idx(ry.size, i)]) if ry.stream else settings.default_value.y
		var vz = float(rz.stream.container[FlowData.bcast_idx(rz.size, i)]) if rz.stream else settings.default_value.z
		out_vec[i] = Vector3(vx, vy, vz)

	var err = out_data.registerStream(settings.out_attribute, out_vec, FlowData.DataType.Vector)
	if err:
		setError(err)
		return

	set_output(0, out_data)

# Vector2 / Vector4 outputs (output_type); the Vector path above is unchanged.
func _compose_other(in_data : FlowData.Data, out_data : FlowData.Data, size : int, rx : Dictionary, ry : Dictionary, rz : Dictionary, output_type : int) -> void:
	var as_v4 : bool = output_type == ComposeVectorNodeSettings.eOutputType.Vector4
	var rw := { "ok": true, "stream": null, "size": 0 }
	if as_v4:
		rw = _resolve_component_stream(in_data, settings.w_attribute, size, "W")
		if not rw.ok:
			setError(rw.error)
			return
	var out_vec = PackedVector4Array() if as_v4 else PackedVector2Array()
	out_vec.resize(size)
	for i in range(size):
		var vx = float(rx.stream.container[FlowData.bcast_idx(rx.size, i)]) if rx.stream else settings.default_value.x
		var vy = float(ry.stream.container[FlowData.bcast_idx(ry.size, i)]) if ry.stream else settings.default_value.y
		if as_v4:
			var vz = float(rz.stream.container[FlowData.bcast_idx(rz.size, i)]) if rz.stream else settings.default_value.z
			var vw = float(rw.stream.container[FlowData.bcast_idx(rw.size, i)]) if rw.stream else settings.default_w
			out_vec[i] = Vector4(vx, vy, vz, vw)
		else:
			out_vec[i] = Vector2(vx, vy)
	var data_type := FlowData.DataType.Vector4 if as_v4 else FlowData.DataType.Vector2
	var err = out_data.registerStream(settings.out_attribute, out_vec, data_type)
	if err:
		setError(err)
		return
	set_output(0, out_data)
