@tool
extends FlowNodeBase

# UE PCG parity: Cull Points Outside Actor Bounds. Inside FlowWorld3D
# hierarchical generation, keeps the points whose position lies inside the
# current cell's execution bounds (EvaluationContext.bounds), half-open on X and
# Z (min <= p < max) so a point on an edge shared by two cells is kept by
# exactly one of them; Y is closed. This is what de-duplicates a world-aligned
# scatter across cells.
#   use_point_bounds  test the point's bounds box for overlap instead of its
#                     position (straddling points are kept by every cell they
#                     touch)
#   margin            grows (or, negative, shrinks) the bounds first
# Outside world generation (no cell) it passes its input through unchanged.
# Data without a position stream (attribute sets, shape-only data) passes
# through.

const CullSettings = preload("res://addons/flow_nodes_editor/nodes/cull_points_outside_bounds_settings.gd")

func _init():
	meta_node = {
		"title" : "Cull Points Outside Bounds",
		"settings" : CullSettings,
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Cull Points Outside Actor Bounds", "Cull Outside Cell", "Cull Points Outside Cell Bounds"],
		"category" : "Filter",
		"tooltip" : "Keeps the points inside the current generation cell (half-open bounds, FlowWorld3D).\nPasses everything through outside hierarchical generation.",
	}

## Indices of the points of `data` kept by `bounds` (see the header).
static func kept_indices( data : FlowData.Data, bounds : AABB, use_point_bounds : bool ) -> PackedInt32Array:
	var keep := PackedInt32Array()
	var positions := data.getVector3Container( FlowData.AttrPosition )
	var n := positions.size()
	if use_point_bounds:
		var local := data.getEffectiveBounds()
		var mins : PackedVector3Array = local.min
		var maxs : PackedVector3Array = local.max
		for i in range( n ):
			if FlowWorldGrid.overlaps( bounds, positions[i] + mins[i], positions[i] + maxs[i] ):
				keep.append( i )
	else:
		for i in range( n ):
			if FlowWorldGrid.owns( bounds, positions[i] ):
				keep.append( i )
	return keep

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return
	if ctx == null or not ctx.has_bounds:
		set_output( 0, in_data )
		return
	var positions := in_data.getVector3Container( FlowData.AttrPosition )
	if positions.is_empty() or positions.size() != in_data.size():
		set_output( 0, in_data )
		return
	var bounds := FlowWorldGrid.grow( ctx.bounds, float( getSettingValue( ctx, "margin", 0.0 ) ) )
	var keep := kept_indices( in_data, bounds, bool( getSettingValue( ctx, "use_point_bounds", false ) ) )
	if keep.size() == in_data.size():
		set_output( 0, in_data )
	else:
		set_output( 0, in_data.filter( keep ) )
