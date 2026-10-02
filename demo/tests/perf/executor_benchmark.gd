extends SceneTree

## Executor benchmark (docs/PARITY_ROUND2.md WP1 acceptance). A script, not a
## test: run from demo/ with
##
##   godot --headless --path . -s res://tests/perf/executor_benchmark.gd
##
## Optional environment: FLOW_BENCH_REPEATS (default 200), FLOW_BENCH_SUB_REPEATS
## (default 50).
##
## Scenarios (owner-less FlowNodeIO.evaluate, the runtime path):
##   A. a 47-node graph of trivial nodes (grid, add_attribute, math_op,
##      expression, density_filter, merge, output) over 50 points, evaluated
##      FLOW_BENCH_REPEATS times;
##   B. the same graph used as a subgraph four times in one evaluation (the
##      "dress pass" shape), evaluated FLOW_BENCH_SUB_REPEATS times.
## Each scenario reports the mean wall time per evaluation. When the round-2
## executor is present, A and B are also measured in threaded mode and with
## FlowOutputCache on, and a third scenario shows threaded mode on compute-bound
## branches:
##   C. grid of 900 points -> 4 independent branches (jitter, relax x5) -> merge,
##      sequential vs threaded.
##
## "before" numbers are the ones this script printed for the pre-round code
## (commit and machine in BEFORE_NOTE); they are constants because the old
## evaluator no longer exists after the change. Re-measure them by checking out
## that commit and running this script.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const BEFORE_NOTE := "base commit 17c4524 (pre-round evaluator), Godot 4.6 headless, 4-core Xeon 2.8 GHz build container; median of 4 runs"
## Mean ms per evaluation measured on the pre-round code; -1 = not recorded.
const BEFORE_A_MS := 32.8
const BEFORE_B_MS := 137.5

const POINTS_X := 5
const POINTS_Z := 10
const BRANCHES := 4

var _nodes : Array = []
var _links : Array = []


func _initialize() -> void:
	var repeats := int(OS.get_environment("FLOW_BENCH_REPEATS")) if OS.has_environment("FLOW_BENCH_REPEATS") else 200
	var sub_repeats := int(OS.get_environment("FLOW_BENCH_SUB_REPEATS")) if OS.has_environment("FLOW_BENCH_SUB_REPEATS") else 50
	var graph := build_graph()
	var parent := build_subgraph_parent(graph, 4)
	print("executor_benchmark: graph nodes = %d, points = %d" % [graph.data.nodes.size(), POINTS_X * POINTS_Z])
	_sanity_check(graph, parent)

	var a_ms := _measure(graph, repeats)
	var b_ms := _measure(parent, sub_repeats)
	print("")
	print("A. 47-node graph x %d evaluations" % repeats)
	_report(BEFORE_A_MS, a_ms)
	print("B. same graph as subgraph x4, %d evaluations" % sub_repeats)
	_report(BEFORE_B_MS, b_ms)

	if ResourceLoader.exists("res://addons/flow_nodes_editor/executor/flow_executor.gd"):
		var executor_class = load("res://addons/flow_nodes_editor/executor/flow_executor.gd")
		var pooled_before : int = executor_class.pooled_element_count
		var a_threaded := _measure(graph, repeats, false, true)
		var b_threaded := _measure(parent, sub_repeats, false, true)
		print("")
		print("Threaded mode (FlowGraphNode3D.threaded, %d worker threads available):" % OS.get_processor_count())
		print("A.")
		_report(BEFORE_A_MS, a_threaded)
		print("B.")
		_report(BEFORE_B_MS, b_threaded)
		print("   (%d elements ran on WorkerThreadPool)" % (executor_class.pooled_element_count - pooled_before))

		var heavy := build_heavy_graph()
		var c_seq := _measure(heavy, 5)
		var c_threaded := _measure(heavy, 5, false, true)
		print("C. compute-bound branches (relax): sequential %8.3f ms/eval, threaded %8.3f ms/eval, x%.2f" % [c_seq, c_threaded, c_seq / c_threaded])

	var cache = _output_cache_class()
	if cache != null:
		cache.clear()
		var a_cached := _measure(graph, repeats, true)
		var hits_a : int = cache.hits
		cache.clear()
		var b_cached := _measure(parent, sub_repeats, true)
		var hits_b : int = cache.hits
		print("")
		print("With FlowOutputCache on (same inputs every run, so every cacheable node hits after the first run):")
		print("A. (%d hits)" % hits_a)
		_report(BEFORE_A_MS, a_cached)
		print("B. (%d hits)" % hits_b)
		_report(BEFORE_B_MS, b_cached)
		cache.clear()
	print("")
	print("before: %s" % BEFORE_NOTE)
	quit(0)


func _report(before_ms: float, after_ms: float) -> void:
	if before_ms > 0.0:
		print("   before %8.3f ms/eval   after %8.3f ms/eval   speedup x%.2f" % [before_ms, after_ms, before_ms / after_ms])
	else:
		print("   %8.3f ms/eval" % after_ms)


func _output_cache_class():
	var path := "res://addons/flow_nodes_editor/executor/flow_output_cache.gd"
	if not ResourceLoader.exists(path):
		return null
	return load(path)


## Mean wall time in ms per FlowNodeIO.evaluate(graph). Warm-up runs first so
## script compilation and first-use caches are not counted.
func _measure(graph: FlowGraphResource, repeats: int, output_cache := false, threaded := false) -> float:
	var params := {}
	if output_cache:
		params["flow_output_cache"] = true
	if threaded:
		params["flow_threaded"] = true
	for i in range(3):
		_evaluate(graph, params)
	var start := Time.get_ticks_usec()
	for i in range(repeats):
		_evaluate(graph, params)
	return float(Time.get_ticks_usec() - start) / 1000.0 / float(maxi(repeats, 1))


## Owner-less FlowNodeIO.evaluate; the executor options are the context meta
## FlowGraphNode3D.threaded / output_cache set (FlowExecutor.THREADED_META,
## OUTPUT_CACHE_META).
func _evaluate(graph: FlowGraphResource, params: Dictionary) -> Dictionary:
	if params.is_empty():
		return FlowNodeIO.evaluate(graph)
	var ctx := FlowNodeIO.make_context(null, 0, {})
	for option in params:
		ctx.set_meta(StringName(option), true)
	return FlowNodeIO.evaluate_collecting_errors(graph, {}, ctx).outputs


func _sanity_check(graph: FlowGraphResource, parent: FlowGraphResource) -> void:
	var out := FlowNodeIO.evaluate(graph)
	var merged = out.get("result", null)
	assert(merged is FlowData.Data)
	print("executor_benchmark: A output points = %d, errors = %d" % [merged.size(), FlowNodeIO.last_errors.size()])
	var pout := FlowNodeIO.evaluate(parent)
	var pmerged = pout.get("result", null)
	print("executor_benchmark: B output points = %d, errors = %d" % [pmerged.size() if pmerged is FlowData.Data else -1, FlowNodeIO.last_errors.size()])


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

func _graph_from_parts(out_params: Array = []) -> FlowGraphResource:
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

## grid -> 4 branches of 11 trivial nodes -> merge -> output = 47 nodes.
func build_graph() -> FlowGraphResource:
	_node("grid", "grid", { "x": POINTS_X, "y": 1, "z": POINTS_Z, "random_seed": 7 })
	_node("merge", "merge")
	_node("out", "output", { "name": "result" })
	for b in range(BRANCHES):
		var prev := "grid"
		var step := 0
		for stage in range(11):
			var node_name := "b%d_%02d" % [b, stage]
			match stage % 4:
				0:
					_node(node_name, "add_attribute", { "name": "w%d" % stage, "data_type": FlowData.DataType.Float, "cte_float": 0.25 * float(b + 1) })
				1:
					_node(node_name, "math_op", { "operation": 1, "in_nameA": "density", "in_nameB": "w%d" % (stage - 1), "out_name": "density" })
				2:
					_node(node_name, "expression", { "expression": "density * 0.5 + 0.25", "out_name": "density" })
				3:
					_node(node_name, "density_filter", { "lower_bound": 0.0, "upper_bound": 1.0 })
			_link(prev, 0, node_name, 0)
			if stage % 4 == 1:
				_link(prev, 0, node_name, 1)
			prev = node_name
			step += 1
		_link(prev, 0, "merge", 0)
	_link("merge", 0, "out", 0)
	return _graph_from_parts()

## grid (900 points) -> 4 branches (transform_points jitter -> relax) -> merge.
func build_heavy_graph() -> FlowGraphResource:
	_node("grid", "grid", { "x": 30, "y": 1, "z": 30 })
	_node("merge", "merge")
	_node("out", "output", { "name": "result" })
	for i in range(4):
		var jitter := "jitter_%d" % i
		var relax := "relax_%d" % i
		_node(jitter, "transform_points", { "offset_min": Vector3(-0.3, 0, -0.3), "offset_max": Vector3(0.3, 0, 0.3), "random_seed": i + 1 })
		_node(relax, "relax", { "num_iterations": 5 })
		_link("grid", 0, jitter, 0)
		_link(jitter, 0, relax, 0)
		_link(relax, 0, "merge", 0)
	_link("merge", 0, "out", 0)
	return _graph_from_parts()

## `count` subgraph nodes running `inner`, merged into one output.
func build_subgraph_parent(inner: FlowGraphResource, count: int) -> FlowGraphResource:
	_node("merge", "merge")
	_node("out", "output", { "name": "result" })
	for i in range(count):
		var node_name := "sub_%d" % i
		_node(node_name, "subgraph", { "graph": inner })
		_link(node_name, 0, "merge", 0)
	_link("merge", 0, "out", 0)
	return _graph_from_parts()
