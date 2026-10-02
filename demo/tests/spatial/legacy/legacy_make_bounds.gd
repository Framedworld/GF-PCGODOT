@tool
# FROZEN COPY of res://addons/flow_nodes_editor/nodes/make_bounds.gd at commit 17c4524 (before
# WP2 spatial data). Loaded lazily (this folder is .gdignore-d, like tests/evaluator/probe_nodes) by
# tests/spatial/spatial_legacy_paths_test.gd to prove the
# current node produces byte-identical output for point inputs and default
# settings. Never edit; never register as a template.
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
		"tooltip" : "Generates a single bounding point at center with size.\nUse as the bounds input of nodes like Grid Fill Bounds or Difference.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var out_data := FlowData.Data.new()
	out_data.addCommonStreams(1)
	
	var spos = out_data.getVector3Container(FlowData.AttrPosition)
	var ssize = out_data.getVector3Container(FlowData.AttrSize)
	
	var sz = getSettingValue(ctx, "size", Vector3(48.0, 1.0, 48.0))
	var c = getSettingValue(ctx, "center", Vector3.ZERO)
	
	spos[0] = c
	ssize[0] = sz
	
	set_output(0, out_data)
