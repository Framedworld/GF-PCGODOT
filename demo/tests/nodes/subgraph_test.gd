# subgraph_test.gd
class_name SubgraphTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const SubgraphNode = preload("res://addons/flow_nodes_editor/nodes/subgraph.gd")
const SubgraphSettings = preload("res://addons/flow_nodes_editor/nodes/subgraph_settings.gd")

## inner graph: input x (Float, default 1.0) -> output "result"
func _echo_graph(default_value := 1.0) -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("x", FlowData.DataType.Float, default_value) \
		.node("in_x", "input_x", {"name": "x", "data_type": FlowData.DataType.Float}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_x", 0, "out", 0) \
		.build()

func _make(graph: FlowGraphResource, overrides := {}) -> FlowNodeBase:
	var node = SubgraphNode.new()
	node.name = "test_subgraph"
	var s = SubgraphSettings.new()
	s.graph = graph
	s.param_overrides = overrides.duplicate()
	node.settings = s
	return auto_free(node)

func _run(node, inputs: Array, owner: FlowGraphNode3D = null) -> void:
	node.inputs = inputs
	var ctx = TestGraph.make_ctx(owner)
	node.preExecute(ctx)
	node.execute(ctx)

func _out(node, port := 0):
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	return bulk[port]

func _x(data):
	var values = TestGraph.stream_values(data, "x")
	if values == null or values.size() == 0:
		return null
	return values[0]


func test_meta_ports_come_from_in_and_out_params() -> void:
	var inner = TestGraph.new() \
		.in_param("a", FlowData.DataType.Float) \
		.in_param("b", FlowData.DataType.Vector) \
		.out_param("first", FlowData.DataType.Float) \
		.out_param("second", FlowData.DataType.Int) \
		.build()
	var node = _make(inner)
	var meta = node.getMeta()
	assert_array(meta.ins.map(func(p): return p.label)).is_equal(["a", "b"])
	assert_array(meta.outs.map(func(p): return p.label)).is_equal(["first", "second"])

func test_meta_outputs_fall_back_to_output_nodes_without_out_params() -> void:
	var node = _make(_echo_graph())
	var meta = node.getMeta()
	assert_array(meta.outs.map(func(p): return p.label)).is_equal(["result"])

func test_wired_input_reaches_the_inner_graph() -> void:
	var node = _make(_echo_graph())
	_run(node, [TestGraph.float_data("x", [5.0])])
	assert_str(node.err).is_empty()
	assert_float(_x(_out(node))).is_equal(5.0)

func test_param_override_used_when_input_not_wired() -> void:
	var node = _make(_echo_graph(), {"x": 7.0})
	_run(node, [null])
	assert_str(node.err).is_empty()
	assert_float(_x(_out(node))).is_equal(7.0)

func test_wired_input_beats_param_override() -> void:
	var node = _make(_echo_graph(), {"x": 7.0})
	_run(node, [TestGraph.float_data("x", [5.0])])
	assert_float(_x(_out(node))).is_equal(5.0)

func test_graph_default_used_without_wire_or_override() -> void:
	var node = _make(_echo_graph(2.5))
	_run(node, [null])
	assert_str(node.err).is_empty()
	assert_float(_x(_out(node))).is_equal(2.5)

func test_graph_default_is_shadowed_by_owner_args_with_the_same_name() -> void:
	# Current behaviour: input.gd reads ctx.owner.args for ANY graph in the
	# evaluation tree, so a root component arg named like a nested graph's
	# input overrides that nested graph's default.
	var owner : FlowGraphNode3D = auto_free(FlowGraphNode3D.new())
	owner.args = {"x": 42.0}
	var node = _make(_echo_graph(2.5))
	_run(node, [null], owner)
	assert_float(_x(_out(node))).is_equal(42.0)

func test_int_and_vector_overrides_are_written_with_the_param_type() -> void:
	var inner = TestGraph.new() \
		.in_param("n", FlowData.DataType.Int, 1) \
		.in_param("v", FlowData.DataType.Vector, Vector3.ZERO) \
		.node("in_n", "input_n", {"name": "n", "data_type": FlowData.DataType.Int}) \
		.node("in_v", "input_v", {"name": "v", "data_type": FlowData.DataType.Vector}) \
		.node("out_n", "output", {"name": "n_out"}) \
		.node("out_v", "output", {"name": "v_out"}) \
		.link("in_n", 0, "out_n", 0) \
		.link("in_v", 0, "out_v", 0) \
		.build()
	var node = _make(inner, {"n": 3, "v": Vector3(1, 2, 3)})
	_run(node, [null, null])
	var meta_outs = node.getMeta().outs.map(func(p): return p.label)
	var n_port = meta_outs.find("n_out")
	var v_port = meta_outs.find("v_out")
	var n_stream = _out(node, n_port).findStream("n")
	var v_stream = _out(node, v_port).findStream("v")
	assert_int(n_stream.data_type).is_equal(FlowData.DataType.Int)
	assert_int(n_stream.container[0]).is_equal(3)
	assert_vector(v_stream.container[0]).is_equal(Vector3(1, 2, 3))

func test_outputs_are_emitted_in_out_params_order() -> void:
	var inner = TestGraph.new() \
		.out_param("second") \
		.out_param("first") \
		.node("g1", "grid", {"x": 1, "y": 1, "z": 1}) \
		.node("g2", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("out_first", "output", {"name": "first"}) \
		.node("out_second", "output", {"name": "second"}) \
		.link("g1", 0, "out_first", 0) \
		.link("g2", 0, "out_second", 0) \
		.build()
	var node = _make(inner)
	_run(node, [])
	assert_int(_out(node, 0).size()).is_equal(2)
	assert_int(_out(node, 1).size()).is_equal(1)

func test_missing_outputs_set_error_and_emit_empty_data() -> void:
	var inner = TestGraph.new() \
		.out_param("present") \
		.out_param("absent") \
		.node("g", "grid", {"x": 2, "y": 1, "z": 2}) \
		.node("out", "output", {"name": "present"}) \
		.link("g", 0, "out", 0) \
		.build()
	var node = _make(inner)
	_run(node, [])
	assert_str(node.err).contains("absent")
	assert_str(node.err).not_contains("present,")
	assert_int(_out(node, 0).size()).is_equal(4)
	assert_object(_out(node, 1)).is_not_null()
	assert_int(_out(node, 1).size()).is_equal(0)

func test_error_when_no_graph() -> void:
	var node = _make(null)
	_run(node, [])
	assert_str(node.err).contains("No graph")
	assert_array(node.generated_bulks).is_empty()

func test_nested_evaluation_depth_is_parent_depth_plus_one() -> void:
	TestGraph.register_probes()
	var inner = TestGraph.new() \
		.node("spy", "test_probe_final") \
		.build()
	var node = _make(inner)
	node.inputs = []
	var ctx = TestGraph.make_ctx()
	ctx.set_meta("flow_eval_depth", 4)
	node.preExecute(ctx)
	node.execute(ctx)
	var depths = TestGraph.probe().exec_log.map(func(e): return e.depth)
	TestGraph.unregister_probes()
	assert_array(depths).is_equal([5])
