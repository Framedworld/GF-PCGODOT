# debug_test.gd
class_name DebugNodeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const DebugNode = preload("res://addons/flow_nodes_editor/nodes/debug.gd")

func _make() -> FlowNodeBase:
	var node = DebugNode.new()
	node.name = "debug"
	node.settings = NodeSettings.new()
	return auto_free(node)

func _run(node, inputs: Array) -> void:
	node.inputs = inputs
	var ctx = TestGraph.make_ctx()
	node.preExecute(ctx)
	node.execute(ctx)


func test_meta_is_final_single_in_single_out() -> void:
	var meta = _make().getMeta()
	assert_bool(meta.get("is_final", false)).is_true()
	assert_int(meta.ins.size()).is_equal(1)
	assert_int(meta.outs.size()).is_equal(1)

func test_passes_input_through_unchanged() -> void:
	var node = _make()
	var input = TestGraph.points([Vector3(1, 2, 3)])
	_run(node, [input])
	assert_str(node.err).is_empty()
	assert_object(node.generated_bulks[0][0]).is_same(input)

func test_forces_debug_enabled_on_its_settings() -> void:
	# Current behaviour: execute() mutates its own settings resource.
	var node = _make()
	assert_bool(node.settings.debug_enabled).is_false()
	_run(node, [TestGraph.points([Vector3.ZERO])])
	assert_bool(node.settings.debug_enabled).is_true()

func test_null_input_is_forwarded_as_null() -> void:
	var node = _make()
	_run(node, [null])
	assert_int(node.generated_bulks.size()).is_equal(1)
	assert_object(node.generated_bulks[0][0]).is_null()

func test_debug_node_is_an_execution_root_in_evaluate_graph() -> void:
	TestGraph.register_probes()
	var graph = TestGraph.new() \
		.node("src", "test_probe") \
		.node("dbg", "debug") \
		.link("src", 0, "dbg", 0) \
		.build()
	var outputs = FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	var executed = TestGraph.probe().executed_names()
	TestGraph.unregister_probes()
	assert_array(executed).is_equal(["src"])
	assert_dict(outputs).is_empty()

func test_unconnected_debug_node_in_graph_does_not_crash() -> void:
	var graph = TestGraph.new() \
		.node("dbg", "debug") \
		.build()
	var outputs = FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	assert_dict(outputs).is_empty()

func test_debug_does_not_mutate_the_saved_graph_settings() -> void:
	var graph = TestGraph.new() \
		.node("dbg", "debug", {"debug_enabled": false}) \
		.build()
	FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0)
	assert_bool(graph.data["nodes"][0]["settings"]["debug_enabled"]).is_false()
