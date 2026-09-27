@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Build Rotation From Up Vector",
		"settings" : BuildRotationFromUpNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Computes rotation from an up vector stream or constant and applies it to the points.",
		"aliases" : ["Build Rotation From Up Vector", "Make Rot"],
		"category" : "Spatial",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var axis_val : String = String(settings.axis).strip_edges().to_lower()
	if axis_val not in ["x", "y", "z"]:
		setError("Axis must be one of x/y/z (got '%s')" % settings.axis)
		return

	var out_data : FlowData.Data = in_data.duplicate()
	var num_elems = in_data.size()
	var srot : PackedVector3Array
	if out_data.hasStream(FlowData.AttrRotation):
		srot = out_data.cloneStream(FlowData.AttrRotation)
	else:
		# Input has no rotation stream yet — create one (this node builds rotation from scratch)
		srot = out_data.addStream(FlowData.AttrRotation, FlowData.DataType.Vector)

	var use_constant = settings.use_constant
	var up_const = settings.up_vector_constant
	var attr_name = settings.up_vector_attribute

	var stream_up = null
	var stream_up_size := 0
	if not use_constant and attr_name != "":
		stream_up = in_data.findStream(attr_name)
		if stream_up == null:
			if is_ownerless_preview(ctx):
				var empty_data = FlowData.Data.new()
				set_output(0, empty_data)
				return
			setError("Up vector attribute '%s' not found" % attr_name)
			return
		if stream_up.data_type != FlowData.DataType.Vector:
			setError("Up vector attribute '%s' must be a Vector stream" % attr_name)
			return
		stream_up_size = stream_up.container.size()
		if stream_up_size != num_elems and stream_up_size != 1:
			setError("Up vector attribute '%s' has %d values but input has %d points (expected %d or 1)" % [attr_name, stream_up_size, num_elems, num_elems])
			return

	for i in num_elems:
		var up_vec = up_const
		if stream_up:
			up_vec = stream_up.container[FlowData.bcast_idx(stream_up_size, i)]
		# basisFromNormal already falls back to a safe up when nearly parallel
		var basis = FlowData.basisFromNormal(up_vec, Vector3.UP, axis_val)
		srot[i] = FlowData.basisToEuler(basis)

	out_data.registerStream(FlowData.AttrRotation, srot, FlowData.DataType.Vector)
	set_output(0, out_data)
