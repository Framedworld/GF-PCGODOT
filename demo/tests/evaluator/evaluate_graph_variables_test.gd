# evaluate_graph_variables_test.gd
# set_variable / get_variable ordering and publishing through
# FlowNodeIO.evaluate_graph (virtual variable dependencies,
# _stabilize_variable_execution_order, _publish_flow_variables).
class_name EvaluateGraphVariablesTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var Probe

func before_test() -> void:
	TestGraph.register_probes()
	Probe = TestGraph.probe()

func after_test() -> void:
	TestGraph.unregister_probes()

func _log_entry(node_name: String) -> Dictionary:
	for entry in Probe.exec_log:
		if entry.name == node_name:
			return entry
	return {}


func test_getter_declared_before_setter_still_reads_the_value() -> void:
	# The getter comes first in the node list and has no physical wire to the
	# setter; the virtual dependency must schedule the setter (and its upstream)
	# before it.
	var graph = TestGraph.new() \
		.node("out", "output", {"name": "result"}) \
		.node("reader", "test_probe") \
		.node("get", "get_variable", {"variable_name": "v"}) \
		.node("set", "set_variable", {"variable_name": "v"}) \
		.node("src", "test_probe") \
		.link("src", 0, "set", 0) \
		.link("get", 0, "reader", 0) \
		.link("reader", 0, "out", 0) \
		.build()
	var outputs = FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	var order : Array = Probe.executed_names()
	assert_array(order).is_equal(["src", "reader"])
	assert_array(Array(_log_entry("reader").a_trail)).is_equal(["src"])
	assert_array(Array(TestGraph.trail(outputs["result"]))).is_equal(["src", "reader"])


func test_setter_is_executed_only_because_a_getter_reaches_a_final() -> void:
	# Without a getter the setter is not reachable from any final and does not run.
	var graph = TestGraph.new() \
		.node("src", "test_probe") \
		.node("set", "set_variable", {"variable_name": "v"}) \
		.node("other", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("src", 0, "set", 0) \
		.link("other", 0, "out", 0) \
		.build()
	var ctx = TestGraph.make_ctx()
	FlowNodeIO.evaluate_graph(graph, {}, ctx, {}, 0)
	assert_array(Probe.executed_names()).is_equal(["other"])
	assert_bool(ctx.variables.has("v")).is_false()


func test_two_setters_same_variable_both_run_before_getter_and_first_declared_wins() -> void:
	# Current behaviour: _add_virtual_variable_dependencies adds the setters in
	# reverse declaration order, so the FIRST declared setter executes last and
	# its value is what the getter reads.
	var graph = TestGraph.new() \
		.node("src_one", "test_probe") \
		.node("set_one", "set_variable", {"variable_name": "v"}) \
		.node("src_two", "test_probe") \
		.node("set_two", "set_variable", {"variable_name": "v"}) \
		.node("get", "get_variable", {"variable_name": "v"}) \
		.node("reader", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("src_one", 0, "set_one", 0) \
		.link("src_two", 0, "set_two", 0) \
		.link("get", 0, "reader", 0) \
		.link("reader", 0, "out", 0) \
		.build()
	var ev = FlowNodeIO.begin_evaluation(graph, {}, TestGraph.make_ctx(), {}, 0)
	var order := []
	for node in ev._ordered:
		order.append(str(node.name))
	ev.run_to_completion()
	assert_int(order.find("set_one")).is_less(order.find("get"))
	assert_int(order.find("set_two")).is_less(order.find("get"))
	assert_int(order.find("set_two")).is_less(order.find("set_one"))
	assert_array(Array(_log_entry("reader").a_trail)).is_equal(["src_one"])


func test_variables_are_published_to_the_parent_context() -> void:
	var graph = TestGraph.new() \
		.node("src", "test_probe") \
		.node("set", "set_variable", {"variable_name": "shared"}) \
		.node("get", "get_variable", {"variable_name": "shared"}) \
		.node("out", "output", {"name": "result"}) \
		.link("src", 0, "set", 0) \
		.link("get", 0, "out", 0) \
		.build()
	var ctx = TestGraph.make_ctx()
	FlowNodeIO.evaluate_graph(graph, {}, ctx, {}, 0)
	assert_bool(ctx.variables.has("shared")).is_true()
	assert_array(Array(TestGraph.trail(ctx.variables["shared"]))).is_equal(["src"])
	# Mirrored into runtime_params for expression-style consumers.
	assert_bool(ctx.runtime_params.has("mapgen_variables")).is_true()
	assert_bool(ctx.runtime_params["mapgen_variables"].has("shared")).is_true()


func test_parent_variables_are_visible_to_getters() -> void:
	var graph = TestGraph.new() \
		.node("get", "get_variable", {"variable_name": "from_parent"}) \
		.node("reader", "test_probe_final") \
		.link("get", 0, "reader", 0) \
		.build()
	var ctx = TestGraph.make_ctx()
	var parent_value = TestGraph.float_data("value", [4.0, 5.0])
	ctx.variables["from_parent"] = parent_value
	FlowNodeIO.evaluate_graph(graph, {}, ctx, {}, 0)
	# get_variable hands out the stored Data object itself (no copy).
	assert_object(_log_entry("reader").a_data).is_same(parent_value)


func test_missing_variable_yields_empty_data() -> void:
	var graph = TestGraph.new() \
		.node("get", "get_variable", {"variable_name": "never_set"}) \
		.node("reader", "test_probe") \
		.node("out", "output", {"name": "result"}) \
		.link("get", 0, "reader", 0) \
		.link("reader", 0, "out", 0) \
		.build()
	FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	var entry = _log_entry("reader")
	assert_int(entry.a_size).is_equal(0)


func test_variable_set_in_subgraph_is_published_to_outer_graph() -> void:
	var inner = TestGraph.new() \
		.node("inner_src", "test_probe") \
		.node("inner_set", "set_variable", {"variable_name": "from_inner"}) \
		.node("inner_get", "get_variable", {"variable_name": "from_inner"}) \
		.node("inner_out", "output", {"name": "ignored"}) \
		.link("inner_src", 0, "inner_set", 0) \
		.link("inner_get", 0, "inner_out", 0) \
		.build()
	var graph = TestGraph.new() \
		.node("sub", "subgraph", {"graph": inner}) \
		.build()
	var ctx = TestGraph.make_ctx()
	FlowNodeIO.evaluate_graph(graph, {}, ctx, {}, 0)
	assert_bool(ctx.variables.has("from_inner")).is_true()
	assert_array(Array(TestGraph.trail(ctx.variables["from_inner"]))).is_equal(["inner_src"])
