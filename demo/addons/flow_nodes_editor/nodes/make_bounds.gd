@tool
extends FlowNodeBase

const MakeBoundsNodeSettings = preload("res://addons/flow_nodes_editor/nodes/make_bounds_settings.gd")

func _init():
	meta_node = {
		"title" : "Make Bounds",
		"settings" : MakeBoundsNodeSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Get Bounds"],
		"category" : "Spatial",
		"tooltip" : "Generates a single bounding point at center with size.\nUse as the bounds input of nodes like Grid Fill Bounds or Difference.\nShape mode outputs the box as volume data instead.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	if settings.output_mode == MakeBoundsNodeSettings.eOutputMode.Shape:
		var box_size : Vector3 = getSettingValue(ctx, "size", Vector3(48.0, 1.0, 48.0))
		var box_center : Vector3 = getSettingValue(ctx, "center", Vector3.ZERO)
		var box := FlowBoxVolume.new(Transform3D(Basis.IDENTITY, box_center), box_size.abs() * 0.5, getSettingValue(ctx, "steepness", 1.0))
		set_output(0, FlowData.Data.from_shape(box))
		return
	var out_data := FlowData.Data.new()
	out_data.addCommonStreams(1)
	
	var spos = out_data.getVector3Container(FlowData.AttrPosition)
	var ssize = out_data.getVector3Container(FlowData.AttrSize)
	
	var sz = getSettingValue(ctx, "size", Vector3(48.0, 1.0, 48.0))
	var c = getSettingValue(ctx, "center", Vector3.ZERO)
	
	spos[0] = c
	ssize[0] = sz
	
	set_output(0, out_data)
