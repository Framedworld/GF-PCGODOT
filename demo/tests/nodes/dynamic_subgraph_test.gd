# dynamic_subgraph_test.gd
# WP8 (docs/_round2/WP8.md): `graph_attribute` on loop and subgraph. The graph
# of each loop iteration or subgraph entry is named by a String path or a
# FlowGraphResource attribute, resolved through ResourceLoader and the
# compiled-graph cache; unusable graphs give an error naming the iteration
# (or entry) and the loop skips or stops per on_graph_error.
class_name DynamicSubgraphTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const LoopNode = preload("res://addons/flow_nodes_editor/nodes/loop.gd")
const LoopSettings = preload("res://addons/flow_nodes_editor/nodes/loop_settings.gd")
const SubgraphNode = preload("res://addons/flow_nodes_editor/nodes/subgraph.gd")
const SubgraphSettings = preload("res://addons/flow_nodes_editor/nodes/subgraph_settings.gd")

const DIR := "user://wp8_dynamic_subgraph"

var _path_a := ""
var _path_b := ""
var _path_bad := ""


func before() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_path_a = DIR + "/body_a.tres"
	_path_b = DIR + "/body_b.tres"
	_path_bad = DIR + "/body_bad.tres"
	assert_int(ResourceSaver.save(_tag_body(1), _path_a)).is_equal(OK)
	assert_int(ResourceSaver.save(_tag_body(2), _path_b)).is_equal(OK)
	# No "item" input: not usable as a loop body.
	var bad : FlowGraphResource = TestGraph.new() \
		.in_param("other", FlowData.DataType.Vector) \
		.node("out", "output", {"name": "result"}) \
		.build()
	assert_int(ResourceSaver.save(bad, _path_bad)).is_equal(OK)

func after() -> void:
	for path in [_path_a, _path_b, _path_bad]:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(DIR)


# --- helpers -------------------------------------------------------------------------

## item -> add_attribute "tag" = `tag` -> output "result".
static func _tag_body(tag: int) -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("tag", "add_attribute", {"name": "tag", "data_type": FlowData.DataType.Int, "cte_int": tag}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "tag", 0) \
		.link("tag", 0, "out", 0) \
		.build()

func _points(n: int) -> FlowData.Data:
	var positions := []
	for i in range(n):
		positions.append(Vector3(i, 0, 0))
	return TestGraph.points(positions)

func _with_paths(paths: Array) -> FlowData.Data:
	var d := _points(paths.size())
	d.registerStream("g", PackedStringArray(paths), FlowData.DataType.String)
	return d

func _loop(default_graph: FlowGraphResource, extra := {}) -> FlowNodeBase:
	var node = LoopNode.new()
	node.name = "dyn_loop"
	node.node_template = "loop"
	var s = LoopSettings.new()
	s.graph = default_graph
	s.graph_attribute = "g"
	for key in extra:
		s.set(key, extra[key])
	node.settings = s
	return node

func _run(node: FlowNodeBase, inputs: Array) -> FlowData.EvaluationContext:
	var ctx := FlowNodeIO.make_context()
	FlowNodeIO.start_error_log(ctx)
	node.inputs = inputs
	node.preExecute(ctx)
	node.execute(ctx)
	return ctx

func _out(node, port := 0, bulk := 0):
	if bulk >= node.generated_bulks.size():
		return null
	var b : Array = node.generated_bulks[bulk]
	return b[port] if port < b.size() else null

func _tags(data) -> Array:
	var values = TestGraph.stream_values(data, "tag")
	return Array(values) if values != null else []


# --- loop ------------------------------------------------------------------------------

func test_loop_runs_the_graph_named_by_a_resource_attribute() -> void:
	var a := _tag_body(1)
	var b := _tag_body(2)
	var d := _points(3)
	var graphs : Array[Resource] = [a, b, a]
	d.registerStream("g", graphs, FlowData.DataType.Resource)
	var node := _loop(null)
	_run(node, [d])
	assert_str(node.err).is_empty()
	assert_array(_tags(_out(node))).is_equal([1, 2, 1])

func test_loop_runs_the_graph_named_by_a_path_per_partition() -> void:
	var d := _with_paths([_path_b, _path_a, _path_b])
	d.registerStream("group", PackedInt32Array([5, 1, 5]), FlowData.DataType.Int)
	var node := _loop(null, {"iteration_mode": LoopSettings.IterationMode.Partitions, "partition_attribute": "group"})
	_run(node, [d])
	assert_str(node.err).is_empty()
	# Partition 1 (path a) first, then partition 5 (path b).
	assert_array(_tags(_out(node))).is_equal([1, 2, 2])

func test_empty_path_falls_back_to_the_default_graph() -> void:
	var node := _loop(_tag_body(7))
	_run(node, [_with_paths(["", _path_a])])
	assert_str(node.err).is_empty()
	assert_array(_tags(_out(node))).is_equal([7, 1])

func test_missing_graph_reports_the_iteration_and_skips_it() -> void:
	var node := _loop(null)
	var ctx := _run(node, [_with_paths([_path_a, DIR + "/nope.tres", _path_b])])
	var errors : Array = ctx.get_meta(FlowNodeBase.ERROR_LOG_META)
	assert_int(errors.size()).is_equal(1)
	assert_str(errors[0].message).is_equal("Loop iteration 1 (key 1): graph not found: %s/nope.tres" % DIR)
	assert_array(_tags(_out(node))).is_equal([1, 2])

func test_stop_policy_runs_no_further_iterations() -> void:
	var node := _loop(null, {"on_graph_error": LoopSettings.GraphErrorPolicy.Stop})
	_run(node, [_with_paths([_path_a, DIR + "/nope.tres", _path_b])])
	assert_str(node.err).contains("Loop iteration 1 (key 1)")
	assert_array(_tags(_out(node))).is_equal([1])

func test_unusable_graph_values_report_clear_errors() -> void:
	# Not a FlowGraphResource, a body without the item input, and an absent
	# attribute.
	var node := _loop(null)
	var ctx := _run(node, [_with_paths(["res://icon.svg", _path_bad])])
	var messages : Array = ctx.get_meta(FlowNodeBase.ERROR_LOG_META).map(func(e): return e.message)
	assert_int(messages.size()).is_equal(2)
	assert_str(messages[0]).is_equal("Loop iteration 0 (key 0): res://icon.svg is not a FlowGraphResource")
	assert_str(messages[1]).is_equal("Loop iteration 1 (key 1): Loop graph does not have input parameter: item (%s)" % _path_bad)
	assert_int(_out(node).size()).is_equal(0)
	var no_attr := _loop(null)
	_run(no_attr, [_points(1)])
	assert_str(no_attr.err).is_equal("Loop iteration 0 (key 0): attribute 'g' not found")

func test_static_errors_are_unchanged_without_graph_attribute() -> void:
	var node := _loop(null, {"graph_attribute": ""})
	_run(node, [_points(1)])
	assert_str(node.err).is_equal("No graph assigned to Loop")

func test_resolved_graphs_are_compiled_once() -> void:
	var paths := []
	for i in range(60):
		paths.append(_path_a if i % 2 == 0 else _path_b)
	var input := _with_paths(paths)
	var node := _loop(null)
	var before := FlowCompiledGraph.compile_count
	_run(node, [input])
	assert_str(node.err).is_empty()
	assert_int(_tags(_out(node)).size()).is_equal(60)
	# Two distinct graphs over 60 iterations: at most one compile each.
	assert_int(FlowCompiledGraph.compile_count - before).is_less_equal(2)
	# While the caller keeps the graphs loaded, further runs compile nothing.
	var keep_a = load(_path_a)
	var keep_b = load(_path_b)
	_run(_loop(null), [input])
	var warm := FlowCompiledGraph.compile_count
	for i in range(3):
		_run(_loop(null), [input])
	assert_int(FlowCompiledGraph.compile_count).is_equal(warm)
	assert_object(keep_a).is_not_null()
	assert_object(keep_b).is_not_null()

func test_dynamic_loop_in_a_graph_with_feedback() -> void:
	var body : FlowGraphResource = TestGraph.new() \
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
	var d := _points(3)
	var graphs : Array[Resource] = [body, body, body]
	d.registerStream("g", graphs, FlowData.DataType.Resource)
	# The interface (default) graph declares the feedback input and output.
	var node := _loop(body, {"feedback_param_name": "acc"})
	_run(node, [d, null])
	assert_str(node.err).is_empty()
	assert_int(_out(node, 1).size()).is_equal(3)


# --- subgraph --------------------------------------------------------------------------

## x (Float) -> output "result" (the interface graph).
static func _echo_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("x", FlowData.DataType.Float, 1.0) \
		.node("in_x", "input_x", {"name": "x", "data_type": FlowData.DataType.Float}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_x", 0, "out", 0) \
		.build()

## x -> add_attribute "tag" = 3 -> output "result" (same interface).
static func _tagging_echo() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("x", FlowData.DataType.Float, 1.0) \
		.node("in_x", "input_x", {"name": "x", "data_type": FlowData.DataType.Float}) \
		.node("tag", "add_attribute", {"name": "tag", "data_type": FlowData.DataType.Int, "cte_int": 3}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_x", 0, "tag", 0) \
		.link("tag", 0, "out", 0) \
		.build()

func _subgraph(default_graph: FlowGraphResource, attribute := "g") -> FlowNodeBase:
	var node = SubgraphNode.new()
	node.name = "dyn_subgraph"
	node.node_template = "subgraph"
	var s = SubgraphSettings.new()
	s.graph = default_graph
	s.graph_attribute = attribute
	node.settings = s
	return node

func _graph_data(value) -> FlowData.Data:
	var d := FlowData.Data.new()
	if value is Resource:
		var arr : Array[Resource] = [value]
		d.registerStream("g", arr, FlowData.DataType.Resource)
	else:
		d.registerStream("g", PackedStringArray([value]), FlowData.DataType.String)
	return d

func test_subgraph_gains_a_graph_pin() -> void:
	var node := _subgraph(_echo_graph())
	assert_array(node.getMeta().ins.map(func(p): return p.label)).is_equal(["x", "Graph"])
	assert_array(node.getMeta().outs.map(func(p): return p.label)).is_equal(["result"])
	node.settings.graph_attribute = ""
	assert_array(node.getMeta().ins.map(func(p): return p.label)).is_equal(["x"])

func test_subgraph_runs_the_graph_named_on_the_graph_pin() -> void:
	var node := _subgraph(_echo_graph())
	_run(node, [TestGraph.float_data("x", [5.0]), _graph_data(_tagging_echo())])
	assert_str(node.err).is_empty()
	var out = _out(node)
	assert_array(_tags(out)).is_equal([3])
	assert_float(TestGraph.stream_values(out, "x")[0]).is_equal(5.0)

func test_subgraph_resolves_a_path_and_falls_back_to_the_default() -> void:
	var tagging := _tagging_echo()
	var path := DIR + "/echo_tag.tres"
	assert_int(ResourceSaver.save(tagging, path)).is_equal(OK)
	var node := _subgraph(_echo_graph())
	_run(node, [TestGraph.float_data("x", [2.0]), _graph_data(path)])
	assert_str(node.err).is_empty()
	assert_array(_tags(_out(node))).is_equal([3])
	# Unconnected Graph pin: the default graph runs.
	var plain := _subgraph(_echo_graph())
	_run(plain, [TestGraph.float_data("x", [2.0]), null])
	assert_str(plain.err).is_empty()
	assert_array(_tags(_out(plain))).is_empty()
	DirAccess.remove_absolute(path)

func test_subgraph_missing_graph_reports_the_entry() -> void:
	var node := _subgraph(_echo_graph())
	_run(node, [TestGraph.float_data("x", [2.0]), _graph_data(DIR + "/nope.tres")])
	assert_str(node.err).is_equal("Subgraph entry 0: graph not found: %s/nope.tres" % DIR)
	# Every declared output still gets (empty) data.
	assert_int(_out(node).size()).is_equal(0)
	var no_default := _subgraph(null)
	_run(no_default, [null])
	assert_str(no_default.err).is_equal("Subgraph entry 0: Graph input not connected and no default graph assigned")

func test_subgraph_without_graph_attribute_keeps_its_errors() -> void:
	var node := _subgraph(null, "")
	_run(node, [])
	assert_str(node.err).is_equal("No graph assigned to Subgraph node 'Subgraph'")
