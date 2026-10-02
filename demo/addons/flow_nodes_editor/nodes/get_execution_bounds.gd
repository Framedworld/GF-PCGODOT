@tool
extends FlowNodeBase

# UE PCG parity: Get Actor Data (self, Get Bounds mode) / the partition actor's
# bounds in hierarchical generation. Outputs the bounds the current evaluation
# runs in:
#   - inside FlowWorld3D generation: the cell box intersected with the world
#     bounds (EvaluationContext.bounds); on the Unbounded level the world bounds;
#   - outside world generation: settings.fallback_bounds.
# Shape mode (default): a FlowBoxVolume with no points. Points mode: one point
# at the box centre with size = the box size and bounds_min/bounds_max of
# +/- half of it.
# The optional Dependency input only orders execution and decides the level:
# `grid_size (no input) -> get_execution_bounds` runs per cell of that size.
# Both carry @data attributes: bounds_min, bounds_max (world corners),
# grid_size (0 = Unbounded or no world), cell_x, cell_z, hierarchy_level and
# has_bounds (false outside world generation).

const GetExecutionBoundsSettings = preload("res://addons/flow_nodes_editor/nodes/get_execution_bounds_settings.gd")

func _init():
	meta_node = {
		"title" : "Get Execution Bounds",
		"settings" : GetExecutionBoundsSettings,
		# Execution dependency only (UE "Dependency Only" pin): the data is
		# ignored. Wire a grid_size marker into it to put this node on that
		# marker's level, so it runs per cell; a node with no marker upstream
		# runs once, on the Unbounded level, where it reports the world bounds.
		"ins" : [{ "label" : "Dependency" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Get Actor Bounds", "Get Actor Data", "Get Cell Bounds", "Execution Bounds", "Partition Bounds"],
		"category" : "Spatial",
		"tooltip" : "Bounds of the current generation cell (FlowWorld3D hierarchical generation),\nthe world bounds on the Unbounded level, or fallback_bounds outside world generation.\nShape mode outputs a box volume; Points mode one bounds point.",
	}

## The bounds an evaluation runs in: ctx.bounds inside world generation,
## otherwise `fallback`.
static func bounds_for(ctx, fallback : AABB) -> AABB:
	if ctx != null and ctx.has_bounds:
		return ctx.bounds
	return fallback

# One output however many bulks the Dependency pin carries.
func run( ctx : FlowData.EvaluationContext ):
	execute( ctx )

func execute( ctx : FlowData.EvaluationContext ):
	var fallback : AABB = getSettingValue( ctx, "fallback_bounds", settings.fallback_bounds )
	var aabb := bounds_for( ctx, fallback )
	var out : FlowData.Data
	if settings.output_mode == GetExecutionBoundsSettings.eOutputMode.Shape:
		out = FlowData.Data.from_shape( FlowBoxVolume.from_aabb( aabb, getSettingValue( ctx, "steepness", 1.0 ) ) )
	else:
		out = FlowData.Data.new()
		out.addCommonStreams( 1 )
		out.getVector3Container( FlowData.AttrPosition )[0] = aabb.get_center()
		# Bounds and size both carry the box: legacy bounds consumers (Grid Fill
		# Bounds, the point path of Surface Sampler) read `size`, newer ones
		# bounds_min/bounds_max. Like Make Bounds (Points).
		out.getVector3Container( FlowData.AttrSize )[0] = aabb.size
		out.setSymmetricBounds( PackedVector3Array( [ aabb.size ] ) )
		var density := PackedFloat32Array( [ 1.0 ] )
		out.registerStream( FlowData.AttrDensity, density, FlowData.DataType.Float )
	var in_world : bool = ctx != null and ctx.has_bounds
	out.set_data_attr( "bounds_min", aabb.position, FlowData.DataType.Vector )
	out.set_data_attr( "bounds_max", aabb.end, FlowData.DataType.Vector )
	out.set_data_attr( "grid_size", ctx.grid_size if in_world else 0.0, FlowData.DataType.Float )
	out.set_data_attr( "cell_x", ctx.cell_coord.x if in_world else 0, FlowData.DataType.Int )
	out.set_data_attr( "cell_z", ctx.cell_coord.y if in_world else 0, FlowData.DataType.Int )
	out.set_data_attr( "hierarchy_level", ctx.hierarchy_level if in_world else 0, FlowData.DataType.Int )
	out.set_data_attr( "has_bounds", in_world, FlowData.DataType.Bool )
	set_output( 0, out )
