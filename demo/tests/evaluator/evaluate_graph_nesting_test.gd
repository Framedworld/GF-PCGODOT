# evaluate_graph_nesting_test.gd
# Output collection (by name and via out_params), nested subgraphs, loops with
# a feedback parameter and the recursion guard of FlowNodeIO.evaluate_graph.
class_name EvaluateGraphNestingTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var Probe

func before_test() -> void:
	TestGraph.register_probes()
	Probe = TestGraph.probe()

func after_test() -> void:
	TestGraph.unregister_probes()

func _eval(graph: FlowGraphResource, inputs: Dictionary = {}) -> Dictionary:
	return FlowNodeIO.evaluate_graph(graph, inputs, TestGraph.make_ctx(), {}, 0)

func _entries(node_name: String) -> Array:
	return Probe.exec_log.filter(func(e): return e.name == node_name)


# --- output collection -----------------------------------------------------

func test_named_output_node_is_collected_by_its_name() -> void:
	var graph = TestGraph.new() \
		.node("p", "test_probe") \
		.node("out", "output", {"name": "points"}) \
		.link("p", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(outputs.keys()).is_equal(["points"])
	assert_array(Array(TestGraph.trail(outputs["points"]))).is_equal(["p"])


func test_output_template_with_name_suffix_is_collected() -> void:
	# "output_<name>" templates (editor-registered per out_param) resolve to output.gd.
	var graph = TestGraph.new() \
		.out_param("density", FlowData.DataType.Float) \
		.node("p", "test_probe") \
		.node("out", "output_density", {"name": "density"}) \
		.link("p", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(outputs.keys()).is_equal(["density"])


func test_named_output_listed_in_out_params_is_collected() -> void:
	var graph = TestGraph.new() \
		.out_param("a") \
		.out_param("b") \
		.node("pa", "test_probe") \
		.node("pb", "test_probe") \
		.node("out_a", "output", {"name": "a"}) \
		.node("out_b", "output", {"name": "b"}) \
		.link("pa", 0, "out_a", 0) \
		.link("pb", 0, "out_b", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(outputs.keys()).contains_exactly_in_any_order(["a", "b"])
	assert_array(Array(TestGraph.trail(outputs["a"]))).is_equal(["pa"])
	assert_array(Array(TestGraph.trail(outputs["b"]))).is_equal(["pb"])


func test_generic_multi_port_output_maps_ports_to_out_params() -> void:
	# A single "output" node left at the default name "out_val" is the
	# multi-port Outputs node: port i is published as out_params[i].name.
	var graph = TestGraph.new() \
		.out_param("first") \
		.out_param("second") \
		.node("p1", "test_probe") \
		.node("p2", "test_probe") \
		.node("outs", "output", {"name": "out_val"}) \
		.link("p1", 0, "outs", 0) \
		.link("p2", 0, "outs", 1) \
		.build()
	var outputs = _eval(graph)
	assert_array(outputs.keys()).contains_exactly_in_any_order(["first", "second"])
	assert_array(Array(TestGraph.trail(outputs["first"]))).is_equal(["p1"])
	assert_array(Array(TestGraph.trail(outputs["second"]))).is_equal(["p2"])


func test_named_output_not_in_out_params_falls_back_to_port_mapping() -> void:
	# Current behaviour: a template "output" whose name is NOT in a non-empty
	# out_params list is treated as the generic multi-port node, so its port 0
	# is published under out_params[0].name.
	var graph = TestGraph.new() \
		.out_param("declared") \
		.node("p", "test_probe") \
		.node("out", "output", {"name": "undeclared"}) \
		.link("p", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(outputs.keys()).is_equal(["declared"])


# --- nested subgraphs ------------------------------------------------------

func _inner_passthrough_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.String) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.String}) \
		.node("inner_probe", "test_probe") \
		.node("inner_out", "output", {"name": "result"}) \
		.link("in_item", 0, "inner_probe", 0) \
		.link("inner_probe", 0, "inner_out", 0) \
		.build()


func test_subgraph_output_is_collected_by_name_in_outer_graph() -> void:
	var inner = _inner_passthrough_graph()
	var graph = TestGraph.new() \
		.node("src", "test_probe") \
		.node("sub", "subgraph", {"graph": inner}) \
		.node("out", "output", {"name": "final"}) \
		.link("src", 0, "sub", 0) \
		.link("sub", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(Array(TestGraph.trail(outputs.get("final")))).is_equal(["src", "inner_probe"])
	assert_int(_entries("inner_probe")[0].depth).is_equal(1)


func test_subgraph_outputs_follow_out_params_order() -> void:
	var inner = TestGraph.new() \
		.out_param("second") \
		.out_param("first") \
		.node("p_first", "test_probe") \
		.node("p_second", "test_probe") \
		.node("out_first", "output", {"name": "first"}) \
		.node("out_second", "output", {"name": "second"}) \
		.link("p_first", 0, "out_first", 0) \
		.link("p_second", 0, "out_second", 0) \
		.build()
	var graph = TestGraph.new() \
		.node("sub", "subgraph", {"graph": inner}) \
		.node("out0", "output", {"name": "port0"}) \
		.node("out1", "output", {"name": "port1"}) \
		.link("sub", 0, "out0", 0) \
		.link("sub", 1, "out1", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(Array(TestGraph.trail(outputs["port0"]))).is_equal(["p_second"])
	assert_array(Array(TestGraph.trail(outputs["port1"]))).is_equal(["p_first"])


func test_two_level_nesting_tracks_depth_and_collects_outputs() -> void:
	var inner = _inner_passthrough_graph()
	var middle = TestGraph.new() \
		.in_param("item", FlowData.DataType.String) \
		.node("mid_in", "input_item", {"name": "item", "data_type": FlowData.DataType.String}) \
		.node("mid_probe", "test_probe") \
		.node("mid_sub", "subgraph", {"graph": inner}) \
		.node("mid_out", "output", {"name": "result"}) \
		.link("mid_in", 0, "mid_probe", 0) \
		.link("mid_probe", 0, "mid_sub", 0) \
		.link("mid_sub", 0, "mid_out", 0) \
		.build()
	var graph = TestGraph.new() \
		.node("src", "test_probe") \
		.node("sub", "subgraph", {"graph": middle}) \
		.node("out", "output", {"name": "final"}) \
		.link("src", 0, "sub", 0) \
		.link("sub", 0, "out", 0) \
		.build()
	var outputs = _eval(graph)
	assert_array(Array(TestGraph.trail(outputs.get("final")))).is_equal(["src", "mid_probe", "inner_probe"])
	assert_int(_entries("src")[0].depth).is_equal(0)
	assert_int(_entries("mid_probe")[0].depth).is_equal(1)
	assert_int(_entries("inner_probe")[0].depth).is_equal(2)


# --- recursion guard ---------------------------------------------------------

func test_recursion_guard_stops_self_referencing_subgraph_after_depth_20() -> void:
	var graph = TestGraph.new() \
		.node("p", "test_probe_final") \
		.node("self_sub", "subgraph", {}) \
		.build()
	# Make the subgraph node point at its own graph.
	graph.data["nodes"][1]["settings"]["graph"] = graph
	var outputs = _eval(graph)
	var depths : Array = _entries("p").map(func(e): return e.depth)
	# Depths 0..20 run; the call at depth 21 is refused by evaluate_graph.
	assert_int(depths.size()).is_equal(21)
	assert_int(depths.min()).is_equal(0)
	assert_int(depths.max()).is_equal(20)
	assert_dict(outputs).is_empty()
	# Break the self reference so the resource can be released.
	graph.data = {}


func test_evaluate_graph_refuses_depth_above_20() -> void:
	var graph = TestGraph.new() \
		.node("p", "test_probe_final") \
		.build()
	assert_dict(FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 21)).is_empty()
	assert_array(Probe.executed_names()).is_empty()
	FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 20)
	assert_array(Probe.executed_names()).is_equal(["p"])


func test_begin_evaluation_returns_null_above_depth_20() -> void:
	var graph = TestGraph.new() \
		.node("p", "test_probe_final") \
		.build()
	assert_object(FlowNodeIO.begin_evaluation(graph, {}, TestGraph.make_ctx(), {}, 21)).is_null()


# --- loops -------------------------------------------------------------------

func _loop_body_with_feedback() -> FlowGraphResource:
	# item: the current element; acc: the feedback value from the previous
	# iteration. result = item, acc_out = merge(acc, item).
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.in_param("acc", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("in_acc", "input_acc", {"name": "acc", "data_type": FlowData.DataType.Vector}) \
		.node("grow", "merge") \
		.node("out_result", "output", {"name": "result"}) \
		.node("out_acc", "output", {"name": "acc"}) \
		.link("in_acc", 0, "grow", 0) \
		.link("in_item", 0, "grow", 0) \
		.link("in_item", 0, "out_result", 0) \
		.link("grow", 0, "out_acc", 0) \
		.build()


func test_loop_with_feedback_param_accumulates_across_iterations() -> void:
	var body = _loop_body_with_feedback()
	var graph = TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.in_param("seed_acc", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("in_seed", "input_seed_acc", {"name": "seed_acc", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result", "feedback_param_name": "acc"}) \
		.node("out_items", "output", {"name": "items"}) \
		.node("out_acc", "output", {"name": "acc_final"}) \
		.link("in_pts", 0, "loop", 0) \
		.link("in_seed", 0, "loop", 1) \
		.link("loop", 0, "out_items", 0) \
		.link("loop", 1, "out_acc", 0) \
		.build()
	var pts = TestGraph.points([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	var seed_acc = TestGraph.points([Vector3(-1, 0, 0)])
	var outputs = _eval(graph, {"pts": pts, "seed_acc": seed_acc})
	assert_object(outputs.get("items")).is_not_null()
	assert_array(Array(TestGraph.stream_values(outputs["items"], "position"))).is_equal([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	assert_object(outputs.get("acc_final")).is_not_null()
	assert_array(Array(TestGraph.stream_values(outputs["acc_final"], "position"))).is_equal([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	# The feedback input Data given to the loop is not mutated.
	assert_int(seed_acc.size()).is_equal(1)


func test_loop_body_runs_once_per_element_at_depth_one() -> void:
	var body = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("body_probe", "test_probe_final") \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "body_probe", 0) \
		.link("in_item", 0, "out", 0) \
		.build()
	var graph = TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result"}) \
		.node("out", "output", {"name": "looped"}) \
		.link("in_pts", 0, "loop", 0) \
		.link("loop", 0, "out", 0) \
		.build()
	var pts = TestGraph.points([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(4, 0, 0)])
	_eval(graph, {"pts": pts})
	var entries = _entries("body_probe")
	assert_int(entries.size()).is_equal(4)
	for e in entries:
		assert_int(e.a_size).is_equal(1)
		assert_int(e.depth).is_equal(1)
