# merge_gather_test.gd
# merge_attributes (merge_entries + through the evaluator) and gather.
class_name MergeAttributesGatherTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const MergeAttrNode = preload("res://addons/flow_nodes_editor/nodes/merge_attributes.gd")
const MergeAttrSettings = preload("res://addons/flow_nodes_editor/nodes/merge_attributes_settings.gd")
const GatherNode = preload("res://addons/flow_nodes_editor/nodes/gather.gd")

var D = FlowDataScript.DataType

func test_append_unions_attributes_and_promotes_numeric_types() -> void:
	var a = H.data({"v": [PackedInt32Array([1, 2]), D.Int], "name": [PackedStringArray(["a", "b"]), D.String]})
	a.tags = PackedStringArray(["x"])
	a.set_data_attr("level", 1)
	var b = H.data({"v": [PackedFloat64Array([0.5]), D.Double], "uv": [PackedVector2Array([Vector2(1, 2)]), D.Vector2]})
	b.tags = PackedStringArray(["x", "y"])
	b.set_data_attr("level", 2)
	var r = MergeAttrNode.merge_entries([a, b], MergeAttrSettings.eMode.Append, true)
	assert_bool(r.ok).is_true()
	var out : FlowData.Data = r.data
	assert_int(out.size()).is_equal(3)
	assert_int(H.dtype(out, "v")).is_equal(D.Double)
	assert_array(H.values(out, "v")).is_equal([1.0, 2.0, 0.5])
	assert_array(H.values(out, "name")).is_equal(["a", "b", ""])
	assert_int(H.dtype(out, "uv")).is_equal(D.Vector2)
	assert_array(H.values(out, "uv")).is_equal([Vector2.ZERO, Vector2.ZERO, Vector2(1, 2)])
	assert_array(Array(out.tags)).is_equal(["x", "y"])
	assert_int(out.get_data_attr("level")).is_equal(2)

func test_append_type_clash_fails_without_promotion() -> void:
	var a = H.data({"v": [PackedInt32Array([1]), D.Int]})
	var b = H.data({"v": [PackedFloat32Array([0.5]), D.Float]})
	assert_bool(MergeAttrNode.merge_entries([a, b], MergeAttrSettings.eMode.Append, false).ok).is_false()
	var s = H.data({"v": [PackedStringArray(["x"]), D.String]})
	var r = MergeAttrNode.merge_entries([a, s], MergeAttrSettings.eMode.Append, true)
	assert_bool(r.ok).is_false()
	assert_str(r.error).contains("'v'")

func test_append_int_and_int64_gives_int64() -> void:
	var a = H.data({"v": [PackedInt32Array([1]), D.Int]})
	var b = H.data({"v": [PackedInt64Array([1 << 40]), D.Int64]})
	var r = MergeAttrNode.merge_entries([a, b], MergeAttrSettings.eMode.Append, true)
	assert_int(H.dtype(r.data, "v")).is_equal(D.Int64)
	assert_array(H.values(r.data, "v")).is_equal([1, 1 << 40])

func test_by_index_joins_columns() -> void:
	var a = H.data({"x": [PackedFloat32Array([1, 2]), D.Float]})
	var xf = FlowDataScript.Data.newContainerOfType(D.Transform)
	xf.append(Transform3D.IDENTITY)
	var b = H.data({"t": [xf, D.Transform], "x": [PackedFloat32Array([9]), D.Float]})
	var r = MergeAttrNode.merge_entries([a, b], MergeAttrSettings.eMode.ByIndex, true)
	assert_bool(r.ok).is_true()
	assert_int(r.data.size()).is_equal(2)
	assert_array(H.values(r.data, "x")).is_equal([9.0, 9.0])	# later input wins
	assert_int(H.dtype(r.data, "t")).is_equal(D.Transform)
	assert_int(H.values(r.data, "t").size()).is_equal(2)
	var c = H.data({"y": [PackedFloat32Array([1, 2, 3]), D.Float]})
	assert_bool(MergeAttrNode.merge_entries([a, c], MergeAttrSettings.eMode.ByIndex, true).ok).is_false()

func _feed_graph(final_template: String, final_settings: Dictionary) -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("a", D.Float) \
		.in_param("b", D.Float) \
		.in_param("c", D.Float) \
		.node("in_a", "input_a", {"name": "a", "data_type": D.Float}) \
		.node("in_b", "input_b", {"name": "b", "data_type": D.Float}) \
		.node("in_c", "input_c", {"name": "c", "data_type": D.Float}) \
		.node("gather", "gather") \
		.node("final", final_template, final_settings) \
		.node("out", "output", {"name": "result"}) \
		.link("in_a", 0, "gather", 0) \
		.link("in_b", 0, "gather", 0) \
		.link("in_c", 0, "gather", 1) \
		.link("gather", 0, "final", 0) \
		.link("final", 0, "out", 0) \
		.build()

func _inputs() -> Dictionary:
	var a = H.data({"v": [PackedFloat32Array([1, 2]), D.Float]})
	a.tags = PackedStringArray(["first"])
	var b = H.data({"v": [PackedFloat32Array([3]), D.Float], "w": [PackedInt64Array([7]), D.Int64]})
	var c = H.data({"v": [PackedFloat32Array([100]), D.Float]})
	return {"a": a, "b": b, "c": c}

func test_gather_forwards_entries_in_order_and_ignores_dependency_pin() -> void:
	var graph = _feed_graph("merge", {})
	var outputs = FlowNodeIO.evaluate_graph(graph, _inputs(), TestGraph.make_ctx(), {}, 0)
	var result : FlowData.Data = outputs.get("result")
	assert_object(result).is_not_null()
	# a then b, never the dependency-only c
	assert_array(H.values(result, "v")).is_equal([1.0, 2.0, 3.0])

func test_gather_then_merge_attributes() -> void:
	var graph = _feed_graph("merge_attributes", {})
	var outputs = FlowNodeIO.evaluate_graph(graph, _inputs(), TestGraph.make_ctx(), {}, 0)
	var result : FlowData.Data = outputs.get("result")
	assert_object(result).is_not_null()
	assert_array(H.values(result, "v")).is_equal([1.0, 2.0, 3.0])
	assert_int(H.dtype(result, "w")).is_equal(D.Int64)
	assert_array(H.values(result, "w")).is_equal([0, 0, 7])
	assert_array(Array(result.tags)).is_equal(["first"])

func test_gather_keeps_each_entry_separate() -> void:
	var node = GatherNode.new()
	node.settings = NodeSettings.new()
	var ctx = FlowDataScript.EvaluationContext.new()
	node.preExecute(ctx)
	var ins = _inputs()
	for entry in [ins.a, ins.b]:
		node.inputs = [entry, ins.c]
		node.execute(ctx)
	assert_int(node.generated_bulks.size()).is_equal(2)
	assert_object(node.generated_bulks[0][0]).is_same(ins.a)
	assert_object(node.generated_bulks[1][0]).is_same(ins.b)
	H.dispose(node)
