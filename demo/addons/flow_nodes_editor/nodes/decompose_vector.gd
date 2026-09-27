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
		"tooltip" : "Decomposes a Vector3 attribute into three float attributes.",
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
