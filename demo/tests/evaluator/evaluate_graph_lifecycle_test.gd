# evaluate_graph_lifecycle_test.gd
# Node-instance freeing and the resumable evaluator (begin_evaluation /
# GraphEvaluation.step / run_to_completion) versus the synchronous
# FlowNodeIO.evaluate_graph.
class_name EvaluateGraphLifecycleTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var Probe

func before_test() -> void:
	TestGraph.register_probes()
	Probe = TestGraph.probe()

func after_test() -> void:
	TestGraph.unregister_probes()


func _real_node_graph() -> FlowGraphResource:
	# Only stock nodes: generator, attribute op, variables, merge and outputs.
	return TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2}) \
		.node("dens", "add_attribute", {"name": "weight", "data_type": FlowData.DataType.Float, "cte_float": 0.5}) \
		.node("set", "set_variable", {"variable_name": "pts"}) \
		.node("get", "get_variable", {"variable_name": "pts"}) \
		.node("merge", "merge") \
		.node("out", "output", {"name": "merged"}) \
		.node("out_grid", "output", {"name": "grid"}) \
		.link("grid", 0, "dens", 0) \
		.link("dens", 0, "set", 0) \
		.link("get", 0, "merge", 0) \
		.link("grid", 0, "merge", 0) \
		.link("merge", 0, "out", 0) \
		.link("grid", 0, "out_grid", 0) \
		.build()


func _summaries(outputs: Dictionary) -> Dictionary:
	var result := {}
	for key in outputs:
		result[str(key)] = FlowNodeIO.snapshot_summarize_data(outputs[key])
	return result


# --- freeing -------------------------------------------------------------------

func test_evaluate_graph_frees_every_probe_instance() -> void:
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("b", "test_probe") \
		.node("unreached", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("a", 0, "b", 0) \
		.link("b", 0, "out", 0) \
		.build()
	var live_before : int = Probe.live_count
	FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	# Three probes were created (including the one that never executed)...
	assert_int(Probe.instances.size()).is_equal(3)
	# ...and none of them survives the evaluation.
	assert_array(Probe.live_instances()).is_empty()
	assert_int(Probe.live_count).is_equal(live_before)


func test_nested_subgraph_and_loop_instances_are_freed() -> void:
	var body = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("body_probe", "test_probe_final") \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "body_probe", 0) \
		.link("in_item", 0, "out", 0) \
		.build()
	var inner = TestGraph.new() \
		.node("grid", "grid", {"x": 5, "y": 1, "z": 1}) \
		.node("inner_probe", "test_probe_final") \
		.node("loop", "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result"}) \
		.node("inner_out", "output", {"name": "result"}) \
		.link("grid", 0, "inner_probe", 0) \
		.link("grid", 0, "loop", 0) \
		.link("loop", 0, "inner_out", 0) \
		.build()
	var graph = TestGraph.new() \
		.node("sub", "subgraph", {"graph": inner}) \
		.node("outer_probe", "test_probe") \
		.node("out", "output", {"name": "final"}) \
		.link("sub", 0, "outer_probe", 0) \
		.link("outer_probe", 0, "out", 0) \
		.build()
	var outputs = FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	# 1 outer + 1 inner + 5 loop-body probes, all freed.
	assert_int(Probe.instances.size()).is_equal(7)
	assert_array(Probe.live_instances()).is_empty()
	assert_int(outputs.get("final").size()).is_equal(1)


func test_stock_node_instances_are_freed_after_finalize() -> void:
	var ev = FlowNodeIO.begin_evaluation(_real_node_graph(), {}, TestGraph.make_ctx(), {}, 0)
	var captured : Array = ev._instances.values()
	assert_int(captured.size()).is_equal(7)
	for node in captured:
		assert_bool(is_instance_valid(node)).is_true()
	ev.run_to_completion()
	for node in captured:
		assert_bool(is_instance_valid(node)).override_failure_message("instance still alive after finalize").is_false()


func test_outputs_outlive_the_freed_instances() -> void:
	var outputs = FlowNodeIO.evaluate_graph(_real_node_graph(), {}, TestGraph.make_ctx(), {}, 0)
	assert_int(outputs["grid"].size()).is_equal(6)
	# merge(get_variable(pts), grid) = 6 + 6 points
	assert_int(outputs["merged"].size()).is_equal(12)
	assert_array(Array(TestGraph.stream_values(outputs["merged"], "weight"))).is_equal([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


# --- resumable evaluation ------------------------------------------------------

func test_step_by_step_produces_identical_outputs_to_evaluate_graph() -> void:
	var graph = _real_node_graph()
	var sync_ctx = TestGraph.make_ctx()
	var sync_outputs = FlowNodeIO.evaluate_graph(graph, {}, sync_ctx, {}, 0)

	var step_ctx = TestGraph.make_ctx()
	var ev = FlowNodeIO.begin_evaluation(graph, {}, step_ctx, {}, 0)
	var total : int = ev.node_count()
	assert_int(total).is_greater(0)
	var steps := 0
	while not ev.is_done():
		# A zero budget still guarantees one node of progress per call.
		ev.step(0.0)
		steps += 1
		if not ev.is_done():
			assert_int(ev.progress()).is_equal(steps)
	assert_int(steps).is_equal(total)
	assert_dict(_summaries(ev.outputs)).is_equal(_summaries(sync_outputs))
	assert_array(step_ctx.variables.keys()).is_equal(sync_ctx.variables.keys())


func test_run_to_completion_matches_evaluate_graph() -> void:
	var graph = _real_node_graph()
	var sync_outputs = FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	var ev = FlowNodeIO.begin_evaluation(graph, {}, TestGraph.make_ctx(), {}, 0)
	var outputs = ev.run_to_completion()
	assert_bool(ev.is_done()).is_true()
	assert_dict(_summaries(outputs)).is_equal(_summaries(sync_outputs))


func test_run_to_completion_finalizes_exactly_once() -> void:
	var graph = _real_node_graph()
	var ctx = TestGraph.make_ctx()
	var ev = FlowNodeIO.begin_evaluation(graph, {}, ctx, {}, 0)
	ev.step(0.0)
	var first = ev.run_to_completion()
	assert_bool(ctx.variables.has("pts")).is_true()
	# If finalize ran again it would re-publish the variables into ctx.
	ctx.variables.clear()
	var second = ev.run_to_completion()
	assert_bool(ev.step(0.0)).is_true()
	assert_object(second).is_same(first)
	assert_bool(ctx.variables.is_empty()).is_true()
	assert_int(ev.progress()).is_equal(ev.node_count())


func test_step_returns_false_until_the_last_node() -> void:
	var graph = _real_node_graph()
	var ev = FlowNodeIO.begin_evaluation(graph, {}, TestGraph.make_ctx(), {}, 0)
	var results := []
	while not ev.is_done():
		results.append(ev.step(0.0))
	assert_bool(results.back()).is_true()
	for i in range(results.size() - 1):
		assert_bool(results[i]).is_false()
	# outputs are only populated once done
	assert_bool(ev.outputs.has("merged")).is_true()


func test_outputs_are_empty_before_the_evaluation_finishes() -> void:
	var ev = FlowNodeIO.begin_evaluation(_real_node_graph(), {}, TestGraph.make_ctx(), {}, 0)
	ev.step(0.0)
	assert_bool(ev.is_done()).is_false()
	assert_dict(ev.outputs).is_empty()
	ev.run_to_completion()


func test_probe_graph_step_and_sync_execute_same_order() -> void:
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
	FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	var sync_order : Array = Probe.executed_names()
	Probe.reset_probe_state()
	var ev = FlowNodeIO.begin_evaluation(graph, {}, TestGraph.make_ctx(), {}, 0)
	while not ev.is_done():
		ev.step(0.0)
	assert_array(Probe.executed_names()).is_equal(sync_order)
	assert_array(Probe.live_instances()).is_empty()
