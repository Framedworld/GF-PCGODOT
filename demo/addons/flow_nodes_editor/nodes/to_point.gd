@tool
extends FlowNodeBase

# UE PCG parity: To Point / Make Concrete. Samples the spatial shape of each
# input Data with its default sampler (splines along the curve, surfaces on a
# world-anchored jittered grid, volumes on a voxel grid; composites by their
# kind). Point data without a shape passes through unchanged. Tags and @data
# attributes are kept; the output is plain points (no shape).

const ToPointSettings = preload("res://addons/flow_nodes_editor/nodes/to_point_settings.gd")

func _init():
	meta_node = {
		"title" : "To Point",
		"settings" : ToPointSettings,
		"aliases" : ["To Point", "Make Concrete", "Collapse", "Spatial To Point"],
		"category" : "Spatial",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Converts spatial data (spline, surface, volume, composite) to points with its default sampling.\nPoint data passes through unchanged.",
	}

## The sampler settings this node passes to FlowSpatial.to_points().
func sampling_settings( ctx : FlowData.EvaluationContext ) -> Dictionary:
	return {
		"interval": float( getSettingValue( ctx, "spline_interval", 1.0 ) ),
		"points_per_square_meter": float( getSettingValue( ctx, "points_per_square_meter", 0.1 ) ),
		"point_extents": getSettingValue( ctx, "point_extents", Vector3.ONE ),
		"looseness": float( getSettingValue( ctx, "looseness", 1.0 ) ),
		"point_steepness": float( getSettingValue( ctx, "point_steepness", 0.5 ) ),
		"voxel_size": getSettingValue( ctx, "voxel_size", Vector3.ONE ),
		"apply_density": bool( getSettingValue( ctx, "apply_density", true ) ),
		"keep_zero_density": bool( getSettingValue( ctx, "keep_zero_density", false ) ),
		"max_candidates": int( getSettingValue( ctx, "max_candidates", FlowSpatial.DEFAULT_MAX_CANDIDATES ) ),
		"seed": effective_seed(),
	}

## Samples `shape` with `opts`, routing composites and leaves through the
## error-reporting samplers. Returns [Data, error_message].
static func sample_shape( shape : FlowSpatial, opts : Dictionary ) -> Array:
	var errors : Array = []
	var out : FlowData.Data
	match shape.get_kind():
		FlowData.Kind.Spline:
			out = shape.to_points( opts )
		FlowData.Kind.Surface:
			out = FlowSpatial.sample_surface( shape, opts, errors )
		_:
			out = FlowSpatial.sample_volume( shape, opts, errors )
	return [ out, errors[0] if errors.size() > 0 else "" ]

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	if in_data.shape == null:
		set_output( 0, in_data )
		return
	var res := sample_shape( in_data.shape, sampling_settings( ctx ) )
	if res[1] != "":
		setError( res[1] )
	var out : FlowData.Data = res[0]
	out.tags = in_data.tags.duplicate()
	out.data_attrs = in_data.data_attrs.duplicate( true )
	set_output( 0, out )
