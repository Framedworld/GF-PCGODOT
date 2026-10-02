extends SceneTree

## Loop benchmark (docs/PARITY_ROUND2.md WP8). A script, not a test: run from
## demo/ with
##
##   godot --headless --path . -s res://tests/perf/loop_benchmark.gd
##
## Optional environment: FLOW_BENCH_REPEATS (default 10).
##
## Scenario: grid of 100 points -> loop (100 iterations, Points mode, Merge)
## over a 20-node body graph (input, 18 trivial attribute nodes, output) ->
## output, evaluated owner-less through FlowNodeIO.evaluate FLOW_BENCH_REPEATS
## times. Reports the mean wall time per evaluation and per iteration. When the
## WP8 loop modes are present it also measures the same work in Chunks mode
## (10 iterations of 10 points) and Partitions mode (10 partitions), and the
## dynamic-subgraph path (graph_attribute naming the body for every point).
##
## The script only uses APIs that exist on the pre-round code too
## (FlowNodeIO.evaluate, graph data dictionaries), so the "before" figures are
## measured by running this same file on an older checkout.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const POINTS_X := 10
const POINTS_Z := 10
const BODY_STAGES := 18

var _nodes : Array = []
var _links : Array = []


func _initialize() -> void:
	var repeats := int(OS.get_environment("FLOW_BENCH_REPEATS")) if OS.has_environment("FLOW_BENCH_REPEATS") else 10
	var body := build_body()
	var graph := build_loop_graph(body, {})
	print("loop_benchmark: body nodes = %d, iterations = %d" % [body.data.nodes.size(), POINTS_X * POINTS_Z])
	var out := FlowNodeIO.evaluate(graph)
	var merged = out.get("result", null)
	print("loop_benchmark: output points = %d, errors = %d" % [merged.size() if merged is FlowData.Data else -1, FlowNodeIO.last_errors.size()])

	var ms := _measure(graph, repeats)
	print("")
	print("Points mode, 100 iterations x 20-node body, %d evaluations:" % repeats)
	print("   %8.3f ms/eval   %6.3f ms/iteration" % [ms, ms / float(POINTS_X * POINTS_Z)])

	var has_modes : bool = "iteration_mode" in load("res://addons/flow_nodes_editor/nodes/loop_settings.gd").new()
	if has_modes:
		var chunks := build_loop_graph(body, { "iteration_mode": 3, "chunk_size": 10 })
		var chunk_ms := _measure(chunks, repeats)
		print("Chunks mode (10 iterations of 10 points):")
		print("   %8.3f ms/eval   %6.3f ms/iteration" % [chunk_ms, chunk_ms / 10.0])
		var parts := build_loop_graph(body, { "iteration_mode": 2, "partition_attribute": "bucket" }, true)
		var part_ms := _measure(parts, repeats)
		print("Partitions mode (10 partitions of 10 points):")
		print("   %8.3f ms/eval   %6.3f ms/iteration" % [part_ms, part_ms / 10.0])
		var compiled_class = load("res://addons/flow_nodes_editor/executor/flow_compiled_graph.gd")
		var compiles_before : int = compiled_class.compile_count
		var dynamic := build_loop_graph(body, { "graph_attribute": "body_graph" }, false, true)
		var dyn_ms := _measure(dynamic, repeats)
		print("Points mode with graph_attribute (Resource attribute per point):")
		print("   %8.3f ms/eval   %6.3f ms/iteration   (%d graph compiles over %d evaluations)" % [dyn_ms, dyn_ms / float(POINTS_X * POINTS_Z), compiled_class.compile_count - compiles_before, repeats + 3])
	quit(0)


## Mean wall time in ms per FlowNodeIO.evaluate(graph), after warm-up runs.
func _measure(graph: FlowGraphResource, repeats: int) -> float:
	for i in range(3):
		FlowNodeIO.evaluate(graph)
	var start := Time.get_ticks_usec()
	for i in range(repeats):
		FlowNodeIO.evaluate(graph)
	return float(Time.get_ticks_usec() - start) / 1000.0 / float(maxi(repeats, 1))


# --- graph construction --------------------------------------------------------------

func _node(node_name: String, template: String, settings: Dictionary = {}) -> void:
	_nodes.append({
		"name": StringName(node_name),
		"template": template,
		"settings": settings,
		"position": Vector2.ZERO,
		"args_port": {},
		"show_disconnected_inputs": false,
	})

func _link(from_node: String, from_port: int, to_node: String, to_port: int) -> void:
	_links.append({
		"from_node": StringName(from_node),
		"from_port": from_port,
		"to_node": StringName(to_node),
		"to_port": to_port,
		"keep_alive": false,
	})

func _graph_from_parts() -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	graph.data = {
		"type": "flow_graph_nodes",
		"version": 1,
		"min_pos": Vector2.ZERO,
		"nodes": _nodes,
		"links": _links,
		"frames": [],
	}
	_nodes = []
	_links = []
	return graph

## input "item" -> 18 trivial nodes (add_attribute / math_op pairs) -> output
## "result" = 20 nodes.
func build_body() -> FlowGraphResource:
	_node("in_item", "input_item", { "name": "item", "data_type": FlowData.DataType.Vector })
	var prev := "in_item"
	for stage in range(BODY_STAGES):
		var node_name := "s%02d" % stage
		if stage % 2 == 0:
			_node(node_name, "add_attribute", { "name": "w%d" % stage, "data_type": FlowData.DataType.Float, "cte_float": 0.5 })
		else:
			_node(node_name, "math_op", { "operation": 2, "in_nameA": "w%d" % (stage - 1), "in_nameB": "0.98", "out_name": "w%d" % (stage - 1) })
		_link(prev, 0, node_name, 0)
		prev = node_name
	_node("out", "output", { "name": "result" })
	_link(prev, 0, "out", 0)
	var graph := _graph_from_parts()
	var param := GraphInputParameter.new()
	param.name = "item"
	param.data_type = FlowData.DataType.Vector
	var params : Array[GraphInputParameter] = [param]
	graph.in_params = params
	return graph

## grid (100 points) [-> bucket / graph attributes] -> loop(body) -> output.
func build_loop_graph(body: FlowGraphResource, loop_settings: Dictionary, with_bucket := false, with_graph_attr := false) -> FlowGraphResource:
	_node("grid", "grid", { "x": POINTS_X, "y": 1, "z": POINTS_Z, "random_seed": 7 })
	var prev := "grid"
	if with_bucket:
		# bucket = index % 10 via get_loop_index (point enumeration) and math_op ModuloInt.
		_node("idx", "get_loop_index", { "out_name": "bucket" })
		_node("mod", "math_op", { "operation": 10, "in_nameA": "bucket", "in_nameB": "10", "out_name": "bucket" })
		_link(prev, 0, "idx", 0)
		_link("idx", 0, "mod", 0)
		prev = "mod"
	if with_graph_attr:
		_node("gattr", "add_attribute", { "name": "body_graph", "data_type": FlowData.DataType.Resource, "cte_resource": body })
		_link(prev, 0, "gattr", 0)
		prev = "gattr"
	var settings := { "graph": body, "item_input_name": "item", "output_attribute_name": "result" }
	settings.merge(loop_settings, true)
	_node("loop", "loop", settings)
	_link(prev, 0, "loop", 0)
	_node("out", "output", { "name": "result" })
	_link("loop", 0, "out", 0)
	return _graph_from_parts()
