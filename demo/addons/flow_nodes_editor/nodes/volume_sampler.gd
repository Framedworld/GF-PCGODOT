@tool
extends "res://addons/flow_nodes_editor/nodes/sample_points.gd"

const VolumeSamplerNodeSettings = preload("res://addons/flow_nodes_editor/nodes/volume_sampler_settings.gd")

func _init():
	meta_node = {
		"title" : "Volume Sampler",
		"settings" : VolumeSamplerNodeSettings,
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Volume Sampler"],
		"category" : "Sampler",
		"tooltip" : "Samples points inside incoming point volumes (Volume Sampler alias).",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var bulks_before := num_generated_bulks
	super.execute( ctx )
	if num_generated_bulks <= bulks_before:
		return
	# Sampler parity: make sure the generated points carry density + seed
	# streams even if the shared Sample Points implementation didn't add them.
	var bulk : Array = generated_bulks[num_generated_bulks - 1]
	var out_data : FlowData.Data = bulk[0] if bulk.size() > 0 else null
	if out_data == null or out_data.size() == 0:
		return
	var num_points := out_data.size()
	if not out_data.hasStream(FlowData.AttrDensity):
		var sdensity := PackedFloat32Array()
		sdensity.resize(num_points)
		sdensity.fill(1.0)
		out_data.registerStream(FlowData.AttrDensity, sdensity, FlowData.DataType.Float)
	if not out_data.hasStream(FlowData.AttrSeed):
		var spos := out_data.getVector3Container(FlowData.AttrPosition)
		if spos.size() == num_points:
			var node_seed : int = effective_seed()
			var sseed := PackedInt32Array()
			sseed.resize(num_points)
			for i in range(num_points):
				sseed[i] = FlowData.point_seed(spos[i], node_seed)
			out_data.registerStream(FlowData.AttrSeed, sseed, FlowData.DataType.Int)
