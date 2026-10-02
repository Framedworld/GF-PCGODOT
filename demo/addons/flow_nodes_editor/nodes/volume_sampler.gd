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
		"tooltip" : "Samples points inside incoming point volumes (Volume Sampler alias).\nVolume data (Get Volume Data, composites, splines) is sampled on a voxel grid of 'voxel_size'.",
	}

## Spatial data input: voxel centres inside the shape (UE Volume Sampler), on a
## world-anchored grid of voxel_size, kept where the shape's density is > 0.
func _execute_shape( ctx : FlowData.EvaluationContext, in_data : FlowData.Data ) -> void:
	var opts := {
		"voxel_size": getSettingValue( ctx, "voxel_size", Vector3.ONE ),
		"apply_density": bool( getSettingValue( ctx, "apply_density_to_points", true ) ),
		"max_candidates": int( getSettingValue( ctx, "max_candidates", FlowSpatial.DEFAULT_MAX_CANDIDATES ) ),
		"seed": effective_seed(),
	}
	var errors : Array = []
	var out := FlowSpatial.sample_volume( in_data.shape, opts, errors )
	if errors.size() > 0:
		setError( errors[0] )
	out.tags = in_data.tags.duplicate()
	out.data_attrs = in_data.data_attrs.duplicate( true )
	set_output( 0, out )

func execute( ctx : FlowData.EvaluationContext ):
	var shaped = inputs[0] if inputs.size() > 0 else null
	if shaped is FlowData.Data and shaped.shape != null:
		_execute_shape( ctx, shaped )
		return
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
