@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Bounds Modifier",
		"settings" : BoundsModifierNodeSettings,
		"ins" : [{ "label": "In" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Modifies the size/bounds property on points in the provided point data.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input 'In' is not connected")
		return
		
	var out_data : FlowData.Data = in_data.duplicate()
	if not out_data.hasStream(FlowData.AttrSize):
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide a size stream")
		return
	var ssizes = out_data.cloneStream(FlowData.AttrSize)
	if ssizes == null:
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide a size stream")
		return
	
	var mode = settings.mode
	var b_min = settings.bounds_min
	var b_max = settings.bounds_max
	var size_val = b_max - b_min
	if size_val.x < 0: size_val.x = -size_val.x
	if size_val.y < 0: size_val.y = -size_val.y
	if size_val.z < 0: size_val.z = -size_val.z
	
	for i in ssizes.size():
		if mode == BoundsModifierNodeSettings.eMode.Set:
			ssizes[i] = size_val
		elif mode == BoundsModifierNodeSettings.eMode.Add:
			ssizes[i] += size_val
		elif mode == BoundsModifierNodeSettings.eMode.Multiply:
			ssizes[i] = ssizes[i] * size_val
			
	out_data.registerStream(FlowData.AttrSize, ssizes, FlowData.DataType.Vector)
	set_output(0, out_data)
