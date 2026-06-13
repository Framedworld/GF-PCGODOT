@tool
extends FlowNodeBase

# grid_size — HiGen Grid Size declaration node
#
# PURPOSE
# -------
# Tags the downstream section of a graph with a power-of-two cell size that a
# future FlowGraphNode3D partition mode will use to iterate cells.  Today the
# node is a pure pass-through with a side-effect annotation on the evaluation
# context; it does NOT partition, spawn sub-evaluations, or filter points.
# Graphs that include this node evaluate identically to graphs without it.
#
# ANNOTATION MECHANISM
# --------------------
# The declared cell_size is written to ctx.variables under the reserved key
# GridSizeNodeSettings.CTX_KEY ("__grid_size__cell_size").  A later partition
# scheduler can read that key at the start of FlowGraphNode3D.execute() (or
# after graph evaluation) to know the desired cell size for this graph tier.
# See docs/_roadmap_notes/higen_grid_size.md for the full integration plan.

const GridSizeSettings = preload("res://addons/flow_nodes_editor/nodes/grid_size_settings.gd")

func _init():
	meta_node = {
		"title"    : "Grid Size",
		"settings" : GridSizeSettings,
		"ins"      : [{ "label" : "In", "data_type" : FlowData.DataType.Invalid }],
		"outs"     : [{ "label" : "Out", "data_type" : FlowData.DataType.Invalid }],
		"tooltip"  : (
			"Declares a power-of-two cell size for this section of the graph.\n"
			+ "The annotation is recorded on the evaluation context and is currently\n"
			+ "inert — a future FlowGraphNode3D partition mode will use it to drive\n"
			+ "per-cell evaluation (UE HiGen parity). Data passes through unchanged."
		),
		"category" : "ControlFlow",
		"aliases"  : ["Grid Size", "HiGen", "Partition"],
	}

func getTitle() -> String:
	if settings and settings.label and not settings.label.strip_edges().is_empty():
		return "Grid Size: %s" % settings.label
	return "Grid Size"

func getExposedParams():
	return []

func refreshFromSettings():
	super.refreshFromSettings()
	title = getTitle()

func execute(ctx: FlowData.EvaluationContext):
	# Pass data through unchanged.
	var in_data: FlowData.Data = get_optional_input(0)
	if in_data == null:
		in_data = FlowData.Data.new()

	# Annotate the evaluation context with the declared cell size.
	# Key: GridSizeNodeSettings.CTX_KEY = "__grid_size__cell_size"
	# Value: float — the snapped power-of-two cell size from settings.
	var cell_size: float = 1.0
	if settings:
		cell_size = settings.cell_size
	ctx.variables[GridSizeSettings.CTX_KEY] = cell_size

	set_output(0, in_data)
