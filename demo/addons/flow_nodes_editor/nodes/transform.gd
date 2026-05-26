@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Transform",
		"settings" : TransformNodeSettings,
		"ins" : [{ "label": "In" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Applies the random translation/rotation/scale to each point",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input 'In' is not connected")
		return null
	var out_data : FlowData.Data = in_data.duplicate()
	if not out_data.hasStream(FlowData.AttrPosition) or not out_data.hasStream(FlowData.AttrRotation) or not out_data.hasStream(FlowData.AttrSize):
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide position, rotation, and size streams")
		return
	var spos = out_data.cloneStream( FlowData.AttrPosition )
	var srot = out_data.cloneStream( FlowData.AttrRotation )
	var ssizes = out_data.cloneStream( FlowData.AttrSize )
	if spos == null or srot == null or ssizes == null:
		if Engine.is_editor_hint() and ctx.owner == null:
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide position, rotation, and size streams")
		return
	var offset_min : Vector3 = getSettingValue( ctx, "offset_min" )
	var offset_max : Vector3 = getSettingValue( ctx, "offset_max" )
	var rotation_min : Vector3 = getSettingValue( ctx, "rotation_min" )
	var rotation_max : Vector3 = getSettingValue( ctx, "rotation_max" )
	var scale_min : Vector3 = getSettingValue( ctx, "scale_min" )
	var scale_max : Vector3 = getSettingValue( ctx, "scale_max" )
	var uniform_scale : bool = getSettingValue( ctx, "uniform_scale" )
	var rotation_local_space : bool = getSettingValue( ctx, "rotation_local_space" )
	for i in spos.size():
		var amount_pos = Vector3( rng.randf(), rng.randf(), rng.randf() )
		var basis := FlowData.eulerToBasis( srot[i] )
		spos[i] += basis * (offset_min + ( offset_max - offset_min ) * amount_pos)
		var amount_rot = Vector3( rng.randf(), rng.randf(), rng.randf() )
		if rotation_local_space:
			var delta_rot = rotation_min + ( rotation_max - rotation_min ) * amount_rot
			srot[i] = FlowData.basisToEuler( basis * FlowData.eulerToBasis( delta_rot ) )
		else:
			srot[i] += rotation_min + ( rotation_max - rotation_min ) * amount_rot
		if uniform_scale:
			var amount_scale = rng.randf()
			ssizes[i] *= scale_min.x + ( scale_max.x - scale_min.x ) * amount_scale
		else:
			var amount_scale = Vector3( rng.randf(), rng.randf(), rng.randf() )
			ssizes[i] *= scale_min + ( scale_max - scale_min ) * amount_scale
	set_output( 0, out_data )
