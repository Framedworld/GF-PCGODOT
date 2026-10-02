@tool
class_name FlowWorldCell
extends RefCounted

## One cell of hierarchical generation: what FlowGraphNode3D.generate_cell()
## needs to evaluate a graph for a single (level, coord).
##
##   level            grid size in world units (a power of two), or 0 for the
##                    Unbounded level (FlowWorldGrid.UNBOUNDED)
##   coord            XZ cell coordinate ((0, 0) on the Unbounded level)
##   bounds           execution bounds: the cell box intersected with the world
##                    bounds (the world bounds on the Unbounded level)
##   hierarchy_level  1 for the coarsest grid level of the graph, increasing
##                    toward finer levels; 0 on the Unbounded level
##   run_nodes        node name -> true: the nodes of this level. Every other
##                    node is skipped, unless it is preseeded.
##   capture_nodes    nodes of this level whose outputs finer cells consume;
##                    their bulks are kept after the run
##   variables        graph variables published by the coarser cells
##                    containing this one, seeded into ctx.variables
##
## Build one with FlowWorldCell.for_graph(); FlowWorld3D does.

var level : int = 0
var coord : Vector2i = Vector2i.ZERO
var bounds : AABB = AABB()
var hierarchy_level : int = 0
var run_nodes : Dictionary = {}
var capture_nodes : Array = []
var variables : Dictionary = {}

## The cell of `graph` at (level, coord) inside `world_bounds`, with the node
## sets from the graph's compiled level plan.
static func for_graph(graph : FlowGraphResource, cell_level : int, cell_coord : Vector2i, world_bounds : AABB) -> FlowWorldCell:
	var cell := FlowWorldCell.new()
	cell.level = cell_level
	cell.coord = cell_coord if cell_level > 0 else Vector2i.ZERO
	cell.bounds = FlowWorldGrid.execution_bounds(cell.coord, cell_level, world_bounds)
	var compiled := FlowCompiledGraph.for_graph(graph)
	if compiled != null:
		cell.hierarchy_level = compiled.hierarchy_index(cell_level)
		var plan := compiled.level_plan(cell_level)
		cell.run_nodes = plan["run"]
		cell.capture_nodes = plan["capture"]
	return cell

## Dictionary key of a cell: Vector3i(level, x, z).
static func key_of(cell_level : int, cell_coord : Vector2i) -> Vector3i:
	return Vector3i(cell_level, cell_coord.x, cell_coord.y)

func key() -> Vector3i:
	return key_of(level, coord)

## Cell size as a float (ctx.grid_size); 0 on the Unbounded level.
func grid_size() -> float:
	return float(level)

## FlowExecutor.node_filter for this cell: runs the nodes of its level only.
func node_filter() -> Callable:
	var nodes := run_nodes
	return func(element) -> bool: return nodes.has(element.name)

## Writes the cell fields into a root evaluation context.
func apply_to_context(ctx : FlowData.EvaluationContext) -> void:
	ctx.bounds = bounds
	ctx.has_bounds = true
	ctx.grid_size = grid_size()
	ctx.cell_coord = coord
	ctx.hierarchy_level = hierarchy_level
	for variable_name in variables:
		ctx.variables[variable_name] = variables[variable_name]

func _to_string() -> String:
	return FlowWorldGrid.cell_name(level, coord)
