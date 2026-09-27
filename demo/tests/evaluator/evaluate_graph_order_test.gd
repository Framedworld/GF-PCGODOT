# evaluate_graph_order_test.gd
# Evaluator-level ordering tests for FlowNodeIO.evaluate_graph: linear chains,
# diamonds, multiple finals, unreachable and disabled nodes. Graphs are built in
# code (TestGraph) and use the test-only probe nodes, which log their execution
# order and the inputs they received.
class_name EvaluateGraphOrderTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var Probe

func before_test() -> void:
	TestGraph.register_probes()
	Probe = TestGraph.probe()

func after_test() -> void:
	TestGraph.unregister_probes()

func _eval(graph: FlowGraphResource, inputs: Dictionary = {}) -> Dictionary:
	return FlowNodeIO.evaluate_graph(graph, inputs, TestGraph.make_ctx(), {}, 0)

func _log_entry(node_name: String) -> Dictionary:
	for entry in Probe.exec_log:
		if entry.name == node_name:
			return entry
	return {}

func _count(node_name: String) -> int:
	return Probe.executed_names().count(node_name)


func test_linear_chain_executes_in_dependency_order() -> void:
	# Deliberately declared out of order: the evaluator must sort topologically.
	var graph = TestGraph.new() \
		.node("out", "output", {"name": "result"}) \
		.node("c", "test_probe") \
		.node("b", "test_probe") \
		.node("a", "test_probe") \
		.link("a", 0, "b", 0) \
		.link("b", 0, "c", 0) \
		.link("c", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(Probe.executed_names()).is_equal(["a", "b", "c"])
	assert_bool(outputs.has("result")).is_true()
	assert_array(Array(TestGraph.trail(outputs["result"]))).is_equal(["a", "b", "c"])


func test_linear_chain_with_real_generator() -> void:
	var graph = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 3}) \
		.node("p", "test_probe") \
		.node("out", "output", {"name": "points"}) \
		.link("grid", 0, "p", 0) \
		.link("p", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_int(_log_entry("p").a_size).is_equal(6)
	assert_array(Array(TestGraph.trail(outputs.get("points")))).is_equal(["p"])


func test_diamond_runs_shared_upstream_once_before_both_consumers() -> void:
	var graph = TestGraph.new() \
		.node("out", "output", {"name": "result"}) \
		.node("join", "test_probe") \
		.node("right", "test_probe") \
		.node("left", "test_probe") \
		.node("src", "test_probe") \
		.link("src", 0, "left", 0) \
		.link("src", 0, "right", 0) \
		.link("left", 0, "join", 0) \
		.link("right", 0, "join", 1) \
		.link("join", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	var order : Array = Probe.executed_names()
	assert_int(_count("src")).is_equal(1)
	assert_int(order.find("src")).is_less(order.find("left"))
	assert_int(order.find("src")).is_less(order.find("right"))
	assert_int(order.find("left")).is_less(order.find("join"))
	assert_int(order.find("right")).is_less(order.find("join"))
	var join = _log_entry("join")
	assert_int(join.a_size).is_greater(0)
	assert_int(join.b_size).is_greater(0)
	assert_array(Array(join.a_trail)).is_equal(["src", "left"])
	assert_array(Array(join.b_trail)).is_equal(["src", "right"])
	assert_array(Array(TestGraph.trail(outputs["result"]))).is_equal(["src", "left", "src", "right", "join"])


func test_diamond_into_merge_collects_both_branches() -> void:
	var graph = TestGraph.new() \
		.node("out", "output", {"name": "merged"}) \
		.node("merge", "merge") \
		.node("left", "test_probe") \
		.node("right", "test_probe") \
		.node("src", "grid", {"x": 2, "y": 1, "z": 2}) \
		.link("src", 0, "left", 0) \
		.link("src", 0, "right", 0) \
		.link("left", 0, "merge", 0) \
		.link("right", 0, "merge", 0) \
		.link("merge", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_int(_log_entry("left").a_size).is_equal(4)
	assert_int(_log_entry("right").a_size).is_equal(4)
	assert_bool(outputs.has("merged")).is_true()
	# Each probe emits a one-element trail; merge concatenates both bulks.
	assert_array(Array(TestGraph.trail(outputs["merged"]))).is_equal(["left", "right"])


func test_diamond_into_subgraph_consumer_sees_both_inputs() -> void:
	# A subgraph consumer is what _stabilize_consumer_input_order exists for:
	# it must run after BOTH of its upstream branches.
	var inner = TestGraph.new() \
		.in_param("a", FlowData.DataType.String) \
		.in_param("b", FlowData.DataType.String) \
		.node("in_a", "input_a", {"name": "a", "data_type": FlowData.DataType.String}) \
		.node("in_b", "input_b", {"name": "b", "data_type": FlowData.DataType.String}) \
		.node("inner_join", "test_probe") \
		.node("inner_out", "output", {"name": "joined"}) \
		.link("in_a", 0, "inner_join", 0) \
		.link("in_b", 0, "inner_join", 1) \
		.link("inner_join", 0, "inner_out", 0) \
		.build()
	var graph = TestGraph.new() \
		.node("out", "output", {"name": "result"}) \
		.node("sub", "subgraph", {"graph": inner}) \
		.node("right", "test_probe") \
		.node("left", "test_probe") \
		.node("src", "test_probe") \
		.link("src", 0, "left", 0) \
		.link("src", 0, "right", 0) \
		.link("left", 0, "sub", 0) \
		.link("right", 0, "sub", 1) \
		.link("sub", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	var join = _log_entry("inner_join")
	assert_array(Array(join.a_trail)).is_equal(["src", "left"])
	assert_array(Array(join.b_trail)).is_equal(["src", "right"])
	assert_array(Array(TestGraph.trail(outputs.get("result")))).is_equal(["src", "left", "src", "right", "inner_join"])


func test_multiple_finals_all_execute() -> void:
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("b", "test_probe") \
		.node("side_effect", "test_probe_final") \
		.node("out_a", "output", {"name": "first"}) \
		.node("out_b", "output", {"name": "second"}) \
		.link("a", 0, "out_a", 0) \
		.link("b", 0, "out_b", 0) \
		.link("a", 0, "side_effect", 0) \
		.build()
	var outputs = _eval(graph)
	var order : Array = Probe.executed_names()
	assert_int(_count("a")).is_equal(1)
	assert_int(_count("b")).is_equal(1)
	assert_int(_count("side_effect")).is_equal(1)
	assert_int(order.find("a")).is_less(order.find("side_effect"))
	assert_array(outputs.keys()).contains_exactly_in_any_order(["first", "second"])
	assert_array(Array(TestGraph.trail(outputs["first"]))).is_equal(["a"])
	assert_array(Array(TestGraph.trail(outputs["second"]))).is_equal(["b"])


func test_nodes_not_reaching_a_final_are_not_executed() -> void:
	var graph = TestGraph.new() \
		.node("used", "test_probe") \
		.node("dangling", "test_probe") \
		.node("dangling_child", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("used", 0, "out", 0) \
		.link("dangling", 0, "dangling_child", 0) \
		.build()
	_eval(graph)
	assert_array(Probe.executed_names()).is_equal(["used"])


func test_graph_without_finals_executes_nothing_and_returns_empty() -> void:
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("b", "test_probe") \
		.link("a", 0, "b", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(Probe.executed_names()).is_empty()
	assert_dict(outputs).is_empty()


# Saving `disabled = true` in a graph currently raises a script error while the
# evaluator builds the node: FlowNodeBase.refreshFromSettings() calls
# draw_debug.cleanup_multimesh_direct() and draw_debug is null for evaluator
# instances (node.gd:345). The pass-through semantics are therefore tested by
# flipping `disabled` on the built instances (begin_evaluation) before they run;
# the saved-flag path is documented by the skipped tests below.
func _eval_with_disabled(graph: FlowGraphResource, disabled_names: Array) -> Dictionary:
	var ev = FlowNodeIO.begin_evaluation(graph, {}, TestGraph.make_ctx(), {}, 0)
	for node_name in disabled_names:
		ev._instances[node_name].settings.disabled = true
	return ev.run_to_completion()


func test_disabled_node_passes_input_through() -> void:
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("skipped", "test_probe") \
		.node("c", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("a", 0, "skipped", 0) \
		.link("skipped", 0, "c", 0) \
		.link("c", 0, "out", 0) \
		.build()
	var outputs = _eval_with_disabled(graph, ["skipped"])
	# The disabled probe never runs execute(); executedDisabled forwards input 0.
	assert_array(Probe.executed_names()).is_equal(["a", "c"])
	assert_array(Array(_log_entry("c").a_trail)).is_equal(["a"])
	assert_array(Array(TestGraph.trail(outputs["result"]))).is_equal(["a", "c"])


func test_disabled_real_node_passes_input_data_object_through() -> void:
	# math_op disabled: downstream must receive the exact upstream Data.
	var graph = TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 1}) \
		.node("op", "math_op", {"in_nameA": "position", "in_nameB": "position", "out_name": "position"}) \
		.node("p", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "op", 0) \
		.link("op", 0, "p", 0) \
		.link("p", 0, "out", 0) \
		.build()
	var ev = FlowNodeIO.begin_evaluation(graph, {}, TestGraph.make_ctx(), {}, 0)
	var grid_node = ev._instances["grid"]
	ev._instances["op"].settings.disabled = true
	ev.step(0.0) # grid only
	var grid_out = grid_node.generated_bulks[0][0]
	ev.run_to_completion()
	var seen = _log_entry("p").a_data
	assert_object(seen).is_same(grid_out)
	var pos = TestGraph.stream_values(seen, "position")
	assert_array(Array(pos)).is_equal([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])


func test_disabled_saved_in_graph_passes_input_through(do_skip := true, skip_reason := "BUG node.gd:345: refreshFromSettings() calls draw_debug.cleanup_multimesh_direct() on a null draw_debug for every evaluator-built node saved with disabled=true (script error during _build_evaluation_state)") -> void:
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("skipped", "test_probe", {"disabled": true}) \
		.node("out", "output", {"name": "result"}) \
		.link("a", 0, "skipped", 0) \
		.link("skipped", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(Array(TestGraph.trail(outputs["result"]))).is_equal(["a"])


func test_disabled_output_is_not_an_execution_root(do_skip := true, skip_reason := "BUG node.gd:345: a node saved with disabled=true raises a script error while the evaluator builds it (null draw_debug)") -> void:
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("out", "output", {"name": "result", "disabled": true}) \
		.link("a", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(Probe.executed_names()).is_empty()
	assert_dict(outputs).is_empty()


func test_build_execution_order_is_deterministic_across_runs() -> void:
	var graph = TestGraph.new() \
		.node("out", "output", {"name": "result"}) \
		.node("join", "test_probe") \
		.node("right", "test_probe") \
		.node("left", "test_probe") \
		.node("src", "test_probe") \
		.link("src", 0, "left", 0) \
		.link("src", 0, "right", 0) \
		.link("left", 0, "join", 0) \
		.link("right", 0, "join", 1) \
		.link("join", 0, "out", 0) \
		.build()
	_eval(graph)
	var first : Array = Probe.executed_names()
	Probe.reset_probe_state()
	_eval(graph)
	assert_array(Probe.executed_names()).is_equal(first)


func test_cycle_does_not_hang_and_breaks_at_back_edge() -> void:
	# a -> b -> a is a cycle; the DFS warns and still produces an order.
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("b", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("a", 0, "b", 0) \
		.link("b", 0, "a", 1) \
		.link("b", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_int(_count("a")).is_equal(1)
	assert_int(_count("b")).is_equal(1)
	assert_bool(outputs.has("result")).is_true()
