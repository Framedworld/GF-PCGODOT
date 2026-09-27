# loop_test.gd
class_name LoopTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const LoopNode = preload("res://addons/flow_nodes_editor/nodes/loop.gd")
const LoopSettings = preload("res://addons/flow_nodes_editor/nodes/loop_settings.gd")

func _points(xs: Array) -> FlowData.Data:
	var positions := []
	for x in xs:
		positions.append(Vector3(x, 0, 0))
	return TestGraph.points(positions)

## Body graph: item -> output "result" (plus a per-iteration "tag" stream so the
## concatenation order is visible).
func _passthrough_body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "out", 0) \
		.build()

## Body graph with feedback: result = item, acc = merge(acc, item).
func _feedback_body() -> FlowGraphResource:
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

func _make(graph: FlowGraphResource, output_name := "result", item_name := "item", feedback := "") -> Node:
	var node = LoopNode.new()
	node.name = "test_loop"
	var s = LoopSettings.new()
	s.graph = graph
	s.output_attribute_name = output_name
	s.item_input_name = item_name
	s.feedback_param_name = feedback
	node.settings = s
	return auto_free(node)

func _run(node, inputs: Array) -> void:
	node.inputs = inputs
	var ctx = TestGraph.make_ctx()
	node.preExecute(ctx)
	node.execute(ctx)

func _out(node, port := 0):
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	return bulk[port]

func _positions(data) -> Array:
	return Array(TestGraph.stream_values(data, "position"))


func test_meta_ports_follow_graph_params() -> void:
	var node = _make(_feedback_body(), "result", "item", "acc")
	node.refreshFromSettings()
	var meta = node.getMeta()
	# Stream + every non-item param; out + feedback.
	assert_int(meta.ins.size()).is_equal(2)
	assert_str(meta.ins[1].label).is_equal("acc")
	assert_int(meta.outs.size()).is_equal(2)
	assert_str(meta.outs[0].label).is_equal("result")
	assert_str(meta.outs[1].label).is_equal("acc")

func test_iterates_one_point_at_a_time_and_concatenates_in_order() -> void:
	TestGraph.register_probes()
	var body = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("spy", "test_probe_final") \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "spy", 0) \
		.link("in_item", 0, "out", 0) \
		.build()
	var node = _make(body)
	_run(node, [_points([3, 1, 2])])
	var probe = TestGraph.probe()
	var sizes = probe.exec_log.map(func(e): return e.a_size)
	TestGraph.unregister_probes()
	assert_str(node.err).is_empty()
	assert_array(sizes).is_equal([1, 1, 1])
	assert_array(_positions(_out(node))).is_equal([Vector3(3, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])

func test_concatenates_all_streams_of_each_iteration() -> void:
	var input = _points([0, 1])
	input.registerStream("weight", PackedFloat32Array([0.25, 0.75]), FlowData.DataType.Float)
	var node = _make(_passthrough_body())
	_run(node, [input])
	var out = _out(node)
	assert_int(out.size()).is_equal(2)
	assert_array(Array(TestGraph.stream_values(out, "weight"))).is_equal([0.25, 0.75])
	assert_object(out.findStream("rotation")).is_not_null()
	assert_object(out.findStream("size")).is_not_null()

func test_empty_input_emits_empty_data_without_iterating() -> void:
	var node = _make(_passthrough_body())
	_run(node, [FlowDataScript.Data.new()])
	assert_str(node.err).is_empty()
	var out = _out(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_missing_input_emits_empty_data() -> void:
	var node = _make(_passthrough_body())
	_run(node, [null])
	assert_int(_out(node).size()).is_equal(0)

func test_empty_input_with_feedback_forwards_initial_feedback() -> void:
	var node = _make(_feedback_body(), "result", "item", "acc")
	var initial = _points([9])
	_run(node, [FlowDataScript.Data.new(), initial])
	assert_int(_out(node, 0).size()).is_equal(0)
	assert_object(_out(node, 1)).is_same(initial)

func test_error_when_no_graph() -> void:
	var node = _make(null)
	_run(node, [_points([1])])
	assert_str(node.err).contains("No graph")
	assert_array(node.generated_bulks).is_empty()

func test_error_when_item_input_missing() -> void:
	var node = _make(_passthrough_body(), "result", "not_an_input")
	_run(node, [_points([1])])
	assert_str(node.err).contains("not_an_input")
	assert_array(node.generated_bulks).is_empty()

func test_error_when_output_name_missing() -> void:
	var node = _make(_passthrough_body(), "missing_output")
	_run(node, [_points([1, 2])])
	assert_str(node.err).contains("missing_output")
	# No output is emitted at all in that case.
	assert_array(node.generated_bulks).is_empty()

func test_output_name_must_be_a_plain_output_template() -> void:
	# Current behaviour: only template "output" nodes count; an "output_<name>"
	# template with the right name is not recognised by the loop.
	var body = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.out_param("result", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("out", "output_result", {"name": "result"}) \
		.link("in_item", 0, "out", 0) \
		.build()
	var node = _make(body)
	_run(node, [_points([1])])
	assert_str(node.err).contains("result")

func test_feedback_accumulates_across_iterations() -> void:
	var node = _make(_feedback_body(), "result", "item", "acc")
	var initial = _points([-1])
	_run(node, [_points([1, 2, 3]), initial])
	assert_str(node.err).is_empty()
	assert_array(_positions(_out(node, 0))).is_equal([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	assert_array(_positions(_out(node, 1))).is_equal([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	# The initial feedback Data is duplicated, never mutated.
	assert_int(initial.size()).is_equal(1)

func test_feedback_without_initial_value_starts_empty() -> void:
	var node = _make(_feedback_body(), "result", "item", "acc")
	_run(node, [_points([1, 2])])
	assert_array(_positions(_out(node, 1))).is_equal([Vector3(1, 0, 0), Vector3(2, 0, 0)])

func test_extra_graph_inputs_are_forwarded_to_every_iteration() -> void:
	var body = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.in_param("extra", FlowData.DataType.Float, 0.0) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("in_extra", "input_extra", {"name": "extra", "data_type": FlowData.DataType.Float}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_extra", 0, "out", 0) \
		.build()
	var node = _make(body)
	_run(node, [_points([1, 2]), TestGraph.float_data("extra", [5.0])])
	assert_array(Array(TestGraph.stream_values(_out(node), "extra"))).is_equal([5.0, 5.0])
