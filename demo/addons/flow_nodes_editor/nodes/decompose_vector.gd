@tool
extends FlowNodeBase

const DecomposeVectorNodeSettings = preload("res://addons/flow_nodes_editor/nodes/decompose_vector_settings.gd")

func _init():
	meta_node = {
		"title" : "Decompose Vector",
		"category" : "Metadata",
		"settings" : DecomposeVectorNodeSettings,
		"ins" : [{ "label": "In" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Decomposes a vector attribute into float attributes, one per component:\nVector2 (x, y), Vector3 (x, y, z), Vector4 and Quaternion (x, y, z, w), Color (r, g, b, a into x, y, z, w).",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		if is_ownerless_preview(ctx):
			set_output(0, FlowData.Data.new())
			return
		setError("Input 'In' is not connected")
		return
		
	var out_data : FlowData.Data = in_data.duplicate()
	var size = in_data.size()
	
	var s_in = in_data.findStream(settings.in_attribute)
	if s_in == null:
		if is_ownerless_preview(ctx):
			set_output(0, FlowData.Data.new())
			return
		setError("Input attribute %s not found" % settings.in_attribute)
		return
		
	if s_in.data_type != FlowData.DataType.Vector:
		# Vector2 / Vector4 / Quaternion / Color: per-component floats too.
		if _decompose_other(s_in, out_data, size):
			return
		setError("Input attribute %s is not a Vector3" % settings.in_attribute)
		return
		
	var in_vecs : PackedVector3Array = s_in.container

	var out_x := PackedFloat32Array()
	var out_y := PackedFloat32Array()
	var out_z := PackedFloat32Array()

	out_x.resize(size)
	out_y.resize(size)
	out_z.resize(size)

	for i in range(size):
		# Honor broadcast (length-1) vector streams like the sibling nodes do.
		var v : Vector3 = in_vecs[FlowData.bcast_idx(in_vecs.size(), i)]
		out_x[i] = v.x
		out_y[i] = v.y
		out_z[i] = v.z
		
	if settings.x_attribute != "":
		out_data.registerStream(settings.x_attribute, out_x, FlowData.DataType.Float)
	if settings.y_attribute != "":
		out_data.registerStream(settings.y_attribute, out_y, FlowData.DataType.Float)
	if settings.z_attribute != "":
		out_data.registerStream(settings.z_attribute, out_z, FlowData.DataType.Float)
		
	set_output(0, out_data)

# Decomposes a Vector2, Vector4, Quaternion or Color stream. Returns false for
# any other type (the caller reports the historical error).
func _decompose_other(s_in : Dictionary, out_data : FlowData.Data, size : int) -> bool:
	var width := 0
	match s_in.data_type:
		FlowData.DataType.Vector2:
			width = 2
		FlowData.DataType.Vector4, FlowData.DataType.Quaternion, FlowData.DataType.Color:
			width = 4
	if width == 0:
		return false
	var names := [settings.x_attribute, settings.y_attribute, settings.z_attribute, settings.w_attribute]
	var container = s_in.container
	for k in range(width):
		if String(names[k]) == "":
			continue
		var out := PackedFloat32Array()
		out.resize(size)
		for i in range(size):
			out[i] = container[FlowData.bcast_idx(container.size(), i)][k]
		var err = out_data.registerStream(names[k], out, FlowData.DataType.Float)
		if err:
			setError(err)
			return true
	set_output(0, out_data)
	return true
