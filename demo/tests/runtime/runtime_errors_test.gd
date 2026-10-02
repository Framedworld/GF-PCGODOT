# runtime_errors_test.gd
# Node errors reported to runtime callers: FlowNodeIO.last_errors and
# FlowGraphNode3D.last_errors collect every setError() raised during a top-level
# evaluation, nested subgraph and loop evaluations included.
class_name RuntimeErrorsTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

const BAD_MESSAGE := "Input 'In' not connected"


# match_and_set with only Attributes wired (In left open): require_input
# raises BAD_MESSAGE. The node feeds the output so it is on the execution path.
func _failing_graph(bad_name: String = "bad") -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 2, "z": 1}) \
		.node(bad_name, "match_and_set") \
		.node("out", "output", {"name": "result"}) \
		.node("grid_out", "output", {"name": "grid"}) \
		.link("grid", 0, bad_name, 1) \
		.link(bad_name, 0, "out", 0) \
		.link("grid", 0, "grid_out", 0) \
		.build()


func _clean_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 2, "z": 1}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "out", 0) \
		.build()


func _entry(node_name: String, template: String, message: String) -> Dictionary:
	return { "node": node_name, "template": template, "message": message }


func test_evaluate_records_node_errors() -> void:
	var outputs := FlowNodeIO.evaluate(_failing_graph())
	assert_bool(outputs.has("grid")).is_true()
	assert_array(FlowNodeIO.last_errors).is_equal([ _entry("bad", "match_and_set", BAD_MESSAGE) ])


func test_last_errors_reset_per_top_level_evaluate() -> void:
	FlowNodeIO.evaluate(_failing_graph())
	assert_int(FlowNodeIO.last_errors.size()).is_equal(1)
	FlowNodeIO.evaluate(_clean_graph())
	assert_array(FlowNodeIO.last_errors).is_empty()
	FlowNodeIO.evaluate(null)
	assert_array(FlowNodeIO.last_errors).is_empty()


func test_subgraph_errors_are_included() -> void:
	var graph: FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "z": 1}) \
		.node("top_bad", "match_and_set") \
		.node("top_out", "output", {"name": "top"}) \
		.node("sub", "subgraph", {"graph": _failing_graph("inner_bad")}) \
		.node("out", "output", {"name": "final"}) \
		.link("grid", 0, "top_bad", 1) \
		.link("top_bad", 0, "top_out", 0) \
		.link("sub", 0, "out", 0) \
		.build()
	FlowNodeIO.evaluate(graph)
	var errors := FlowNodeIO.last_errors
	# The subgraph node itself also reports the output its graph did not produce.
	assert_int(errors.size()).is_equal(3)
	assert_bool(errors.has(_entry("top_bad", "match_and_set", BAD_MESSAGE))).is_true()
	assert_bool(errors.has(_entry("inner_bad", "match_and_set", BAD_MESSAGE))).is_true()
	assert_bool(errors.has(_entry("sub", "subgraph", "Missing outputs: result"))).is_true()


func test_loop_iteration_errors_are_included() -> void:
	var body: FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("body_bad", "match_and_set") \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "body_bad", 1) \
		.link("body_bad", 0, "out", 0) \
		.build()
	var graph: FlowGraphResource = TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result"}) \
		.node("out", "output", {"name": "looped"}) \
		.link("in_pts", 0, "loop", 0) \
		.link("loop", 0, "out", 0) \
		.build()
	var pts := TestGraph.points([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	FlowNodeIO.evaluate(graph, {"pts": pts})
	assert_array(FlowNodeIO.last_errors).is_equal([
		_entry("body_bad", "match_and_set", BAD_MESSAGE),
		_entry("body_bad", "match_and_set", BAD_MESSAGE),
		_entry("body_bad", "match_and_set", BAD_MESSAGE),
	])


func test_flow_graph_node_generate_exposes_last_errors() -> void:
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	host.graph = _failing_graph()
	add_child(host)
	var seen_in_signal := []
	host.generated.connect(func(_outputs): seen_in_signal.append(host.last_errors.duplicate()))
	host.generate()
	var expected := [ _entry("bad", "match_and_set", BAD_MESSAGE) ]
	assert_array(host.last_errors).is_equal(expected)
	assert_array(FlowNodeIO.last_errors).is_equal(expected)
	assert_array(seen_in_signal).is_equal([expected])
	host.graph = _clean_graph()
	host.generate()
	assert_array(host.last_errors).is_empty()
	host.queue_free()


func test_flow_graph_node_generate_async_exposes_last_errors() -> void:
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	host.graph = _failing_graph()
	add_child(host)
	host.generate_async()
	# Finish the in-flight evaluation synchronously and emit `generated`.
	host._finish_async_now(true)
	assert_array(host.last_errors).is_equal([ _entry("bad", "match_and_set", BAD_MESSAGE) ])
	host.queue_free()


func test_hand_built_context_records_nothing() -> void:
	# evaluate_graph with a context that carries no error log (legacy callers,
	# the editor) is unchanged: the node still reports err, nothing is collected.
	FlowNodeIO.evaluate(_clean_graph())
	FlowNodeIO.evaluate_graph(_failing_graph(), {}, TestGraph.make_ctx(), {}, 0)
	assert_array(FlowNodeIO.last_errors).is_empty()
