extends SceneTree

## FlowGraphNode3D.cleanup() benchmark (WP11 item 8). A script, not a test:
## run from demo/ with
##
##   godot --headless --path . -s res://tests/perf/cleanup_benchmark.gd
##
## Optional environment: FLOW_BENCH_CELLS (default 200), FLOW_BENCH_POINTS_SIDE
## (default 5, so 25 spawned nodes per component).
##
## Scenario: FLOW_BENCH_CELLS FlowGraphNode3D components under one parent (the
## shape of FlowWorld3D cells), each generating grid -> spawn_nodes (Node3D per
## point) into its own subtree. Then every component is cleaned up in turn and
## the total and mean wall time of cleanup() are printed. Before WP11, each
## cleanup() also walked the parent's whole subtree (every sibling's content),
## so the total grew with the square of the component count.
##
## Measured on the 4-core build container, Godot 4.6 headless, defaults (200
## components, 5000 nodes), three runs each: before WP11 980 / 990 / 1218 ms
## total (median 4.95 ms per component); after 24.1 / 24.6 / 25.0 ms total
## (median 0.123 ms per component).

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var _done := false

func _process(_delta : float) -> bool:
	if not _done:
		_done = true
		_run()
	return true

func _run() -> void:
	var cells := int(OS.get_environment("FLOW_BENCH_CELLS")) if OS.has_environment("FLOW_BENCH_CELLS") else 200
	var side := int(OS.get_environment("FLOW_BENCH_POINTS_SIDE")) if OS.has_environment("FLOW_BENCH_POINTS_SIDE") else 5
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": side, "y": 1, "z": side}) \
		.node("spawn", "spawn_nodes", {"node_class": "Node3D"}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "spawn", 0) \
		.link("spawn", 0, "out", 0) \
		.build()
	var parent := Node3D.new()
	parent.name = "World"
	root.add_child(parent)
	current_scene = parent
	var components : Array[FlowGraphNode3D] = []
	for i in range(cells):
		var c := FlowGraphNode3D.new()
		c.name = "FlowCell_%d" % i
		c.graph = graph
		parent.add_child(c)
		components.append(c)
	var t0 := Time.get_ticks_usec()
	for c in components:
		c.generate()
	var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var spawned := 0
	for c in components:
		spawned += c.get_child_count()
	print("cleanup_benchmark: %d components under one parent, %d spawned nodes in total (generate %.1f ms)" % [cells, spawned, gen_ms])
	t0 = Time.get_ticks_usec()
	for c in components:
		c.cleanup()
	var total_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var left := 0
	for c in components:
		left += c.get_child_count()
	print("cleanup_benchmark: cleanup() of all %d components: total %.2f ms, mean %.3f ms per component (%d nodes left)" % [cells, total_ms, total_ms / cells, left])
	parent.free()
	quit(0)
