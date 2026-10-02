# existing_nodes_new_types_test.gd
# The audited pre-existing nodes with the extended attribute types (Vector2,
# Vector4, Transform, Int64, Double): add_attribute, filter, compose_vector,
# decompose_vector, expression, attribute_set_to_point, point_to_attribute_set,
# attribute_rename, remove_attribute, partition and merge.
class_name ExistingNodesNewTypesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const AddAttributeNode = preload("res://addons/flow_nodes_editor/nodes/add_attribute.gd")
const FilterNode = preload("res://addons/flow_nodes_editor/nodes/filter.gd")
const ComposeNode = preload("res://addons/flow_nodes_editor/nodes/compose_vector.gd")
const ComposeSettings = preload("res://addons/flow_nodes_editor/nodes/compose_vector_settings.gd")
const DecomposeNode = preload("res://addons/flow_nodes_editor/nodes/decompose_vector.gd")
const DecomposeSettings = preload("res://addons/flow_nodes_editor/nodes/decompose_vector_settings.gd")
const ExpressionNode = preload("res://addons/flow_nodes_editor/nodes/expression.gd")
const SetToPointNode = preload("res://addons/flow_nodes_editor/nodes/attribute_set_to_point.gd")
const SetToPointSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_set_to_point_settings.gd")
const PointToSetNode = preload("res://addons/flow_nodes_editor/nodes/point_to_attribute_set.gd")
const PointToSetSettings = preload("res://addons/flow_nodes_editor/nodes/point_to_attribute_set_settings.gd")
const RenameNode = preload("res://addons/flow_nodes_editor/nodes/attribute_rename.gd")
const RenameSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_rename_settings.gd")
const RemoveNode = preload("res://addons/flow_nodes_editor/nodes/remove_attribute.gd")
const PartitionNode = preload("res://addons/flow_nodes_editor/nodes/partition.gd")

var D = FlowDataScript.DataType

func _xf(values: Array):
	var c = FlowDataScript.Data.newContainerOfType(D.Transform)
	c.append_array(values)
	return c

func test_add_attribute_every_new_type() -> void:
	var cases := {
		D.Vector2: ["cte_vector2", Vector2(1, 2), Vector2(1, 2)],
		D.Vector4: ["cte_vector4", Vector4(1, 2, 3, 4), Vector4(1, 2, 3, 4)],
		D.Transform: ["cte_transform", Transform3D(Basis.IDENTITY, Vector3.ONE), Transform3D(Basis.IDENTITY, Vector3.ONE)],
		D.Int64: ["cte_int64", 1 << 40, 1 << 40],
		D.Double: ["cte_double", 0.1, 0.1],
		D.Quaternion: ["cte_quaternion", Quaternion(0, 0, 0, 1), Vector4(0, 0, 0, 1)],
	}
	var input = H.data({"x": [PackedFloat32Array([1, 2]), D.Float]})
	for t in cases:
		var s = AddAttributeNodeSettings.new()
		s.name = "a"
		s.data_type = t
		s.set(cases[t][0], cases[t][1])
		var r = H.exec(AddAttributeNode, s, [input])
		assert_str(r.err).override_failure_message("type %d" % t).is_empty()
		assert_int(H.dtype(r.out, "a")).is_equal(t)
		assert_bool(H.values(r.out, "a") == [cases[t][2], cases[t][2]]).override_failure_message("type %d: %s" % [t, H.values(r.out, "a")]).is_true()
		# per-data domain too
		s.domain = AddAttributeNodeSettings.eDomain.PerData
		var pd = H.exec(AddAttributeNode, s, [input])
		assert_int(H.dtype(pd.out, "@data.a")).is_equal(t)

func test_filter_compares_int64_exactly_and_doubles() -> void:
	var big := (1 << 53) + 1
	var d = H.data({
		"a": [PackedInt64Array([big, 5]), D.Int64],
		"b": [PackedInt64Array([1 << 53, 5]), D.Int64],
		"x": [PackedFloat64Array([0.5, 2.5]), D.Double],
	})
	var s = FilterNodeSettings.new()
	s.in_nameA = "a"
	s.in_nameB = "b"
	s.condition = FilterNodeSettings.eCondition.Equal
	var r = H.exec(FilterNode, s, [d, d])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "a")).is_equal([5])
	assert_array(H.values(r.out1, "a")).is_equal([big])
	var s2 = FilterNodeSettings.new()
	s2.in_nameA = "x"
	s2.in_nameB = "1.0"
	s2.condition = FilterNodeSettings.eCondition.Greater
	var r2 = H.exec(FilterNode, s2, [d])
	assert_str(r2.err).is_empty()
	assert_array(H.values(r2.out, "x")).is_equal([2.5])

func test_compose_vector2_vector4_and_wide_components() -> void:
	var d = H.data({
		"px": [PackedFloat64Array([1.5]), D.Double],
		"py": [PackedInt64Array([2]), D.Int64],
		"pw": [PackedFloat32Array([4]), D.Float],
	})
	var s = ComposeSettings.new()
	s.x_attribute = "px"
	s.y_attribute = "py"
	s.out_attribute = "v2"
	s.output_type = ComposeSettings.eOutputType.Vector2
	var r = H.exec(ComposeNode, s, [d])
	assert_str(r.err).is_empty()
	assert_int(H.dtype(r.out, "v2")).is_equal(D.Vector2)
	assert_array(H.values(r.out, "v2")).is_equal([Vector2(1.5, 2)])
	s.output_type = ComposeSettings.eOutputType.Vector4
	s.w_attribute = "pw"
	s.out_attribute = "v4"
	s.default_value = Vector3(0, 0, 3)
	var r4 = H.exec(ComposeNode, s, [d])
	assert_int(H.dtype(r4.out, "v4")).is_equal(D.Vector4)
	assert_array(H.values(r4.out, "v4")).is_equal([Vector4(1.5, 2, 3, 4)])
	# Default output type is unchanged (Vector3)
	var s3 = ComposeSettings.new()
	s3.x_attribute = "px"
	s3.out_attribute = "v3"
	assert_int(H.dtype(H.exec(ComposeNode, s3, [d]).out, "v3")).is_equal(D.Vector)

func test_decompose_vector2_vector4_color() -> void:
	var d = H.data({
		"uv": [PackedVector2Array([Vector2(1, 2)]), D.Vector2],
		"v4": [PackedVector4Array([Vector4(1, 2, 3, 4)]), D.Vector4],
		"c": [PackedColorArray([Color(0.5, 0.25, 0, 1)]), D.Color],
	})
	var s = DecomposeSettings.new()
	s.in_attribute = "uv"
	var r = H.exec(DecomposeNode, s, [d])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "x")).is_equal([1.0])
	assert_array(H.values(r.out, "y")).is_equal([2.0])
	assert_bool(r.out.hasStream("z")).is_false()
	s.in_attribute = "v4"
	assert_array(H.values(H.exec(DecomposeNode, s, [d]).out, "w")).is_equal([4.0])
	s.in_attribute = "c"
	assert_array(H.values(H.exec(DecomposeNode, s, [d]).out, "x")).is_equal([0.5])
	var bad = H.data({"s": [PackedStringArray(["x"]), D.String]})
	s.in_attribute = "s"
	assert_str(H.exec(DecomposeNode, s, [bad]).err).contains("not a Vector3")

func _expr(expression: String, out_name: String = "r") -> Object:
	var s = ExpressionNodeSettings.new()
	s.expression = expression
	s.out_name = out_name
	return s

func test_expression_new_result_types() -> void:
	var d = H.data({"position": [PackedVector3Array([Vector3(1, 2, 3)]), D.Vector], "size": [PackedVector3Array([Vector3(2, 2, 2)]), D.Vector]})
	var cases := {
		"Vector2(position.x, position.y)": [D.Vector2, Vector2(1, 2)],
		"Vector4(1, 2, 3, 4)": [D.Vector4, Vector4(1, 2, 3, 4)],
		"Quaternion(0, 0, 0, 1)": [D.Quaternion, Vector4(0, 0, 0, 1)],
		"Transform3D(Basis(), position)": [D.Transform, Transform3D(Basis(), Vector3(1, 2, 3))],
	}
	for expression in cases:
		var r = H.exec(ExpressionNode, _expr(expression), [d])
		assert_str(r.err).override_failure_message(expression).is_empty()
		assert_int(H.dtype(r.out, "r")).override_failure_message(expression).is_equal(cases[expression][0])
		assert_bool(H.values(r.out, "r")[0] == cases[expression][1]).override_failure_message(expression).is_true()

func test_expression_keeps_wide_numeric_output_types() -> void:
	var d = H.data({"n": [PackedInt64Array([1 << 40]), D.Int64], "w": [PackedFloat64Array([0.1]), D.Double]})
	var r = H.exec(ExpressionNode, _expr("n + 1", "n"), [d])
	assert_int(H.dtype(r.out, "n")).is_equal(D.Int64)
	assert_array(H.values(r.out, "n")).is_equal([(1 << 40) + 1])
	var rw = H.exec(ExpressionNode, _expr("w * 3.0", "w"), [d])
	assert_int(H.dtype(rw.out, "w")).is_equal(D.Double)
	assert_bool(H.values(rw.out, "w")[0] == 0.1 * 3.0).is_true()

func test_expression_resolves_ue_aliases() -> void:
	var d = H.data({"size": [PackedVector3Array([Vector3(2, 3, 4)]), D.Vector], "bounds_min": [PackedVector3Array([Vector3(-1, -1, -1)]), D.Vector]})
	var r = H.exec(ExpressionNode, _expr("$Scale.y + $BoundsMin.x"), [d])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "r")).is_equal([2.0])

func test_attribute_set_to_point_from_transform() -> void:
	var xf := Transform3D(Basis.from_euler(Vector3(0, PI / 2, 0)) * Basis.from_scale(Vector3(2, 2, 2)), Vector3(5, 0, 0))
	var d = H.data({"t": [_xf([xf]), D.Transform]})
	var s = SetToPointSettings.new()
	s.transform_attribute_name = "t"
	var r = H.exec(SetToPointNode, s, [d])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "position")).is_equal([Vector3(5, 0, 0)])
	assert_bool((H.values(r.out, "size")[0] as Vector3).is_equal_approx(Vector3(2, 2, 2))).is_true()
	assert_float(H.values(r.out, "rotation")[0].y).is_equal_approx(90.0, 1e-3)

func test_point_to_attribute_set_rename_remove_keep_new_types() -> void:
	var d = H.data({
		"position": [PackedVector3Array([Vector3.ONE, Vector3.ZERO]), D.Vector],
		"rotation": [PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), D.Vector],
		"size": [PackedVector3Array([Vector3.ONE, Vector3.ONE]), D.Vector],
		"t": [_xf([Transform3D.IDENTITY, Transform3D.IDENTITY]), D.Transform],
		"n": [PackedInt64Array([1 << 40, 3]), D.Int64],
	})
	var ps = PointToSetSettings.new()
	ps.drop_point_transform_streams = true
	ps.preserve_transforms_as_attributes = true
	var set_r = H.exec(PointToSetNode, ps, [d])
	assert_str(set_r.err).is_empty()
	assert_int(H.dtype(set_r.out, "t")).is_equal(D.Transform)
	assert_array(H.values(set_r.out, "n")).is_equal([1 << 40, 3])
	var rs = RenameSettings.new()
	rs.from_name = "n"
	rs.to_name = "big"
	var ren = H.exec(RenameNode, rs, [d])
	assert_int(H.dtype(ren.out, "big")).is_equal(D.Int64)
	var rm = RemoveAttributeNodeSettings.new()
	var names : Array[String] = ["t"]
	rm.names = names
	var rem = H.exec(RemoveNode, rm, [d])
	assert_bool(rem.out.hasStream("t")).is_false()
	assert_bool(rem.out.hasStream("n")).is_true()

func test_partition_on_new_types() -> void:
	var d = H.data({
		"k": [PackedVector2Array([Vector2(1, 0), Vector2(0, 1), Vector2(1, 0)]), D.Vector2],
		"n": [PackedInt64Array([1 << 40, 2, 1 << 40]), D.Int64],
	})
	var s = PartitionNodeSettings.new()
	s.attribute_name = "k"
	var r = H.exec(PartitionNode, s, [d])
	assert_str(r.err).is_empty()
	assert_int(r.bulks.size()).is_equal(2)
	assert_array(H.values(r.bulks[0][0], "n")).is_equal([1 << 40, 1 << 40])
	assert_int(H.dtype(r.bulks[0][0], "@data.k")).is_equal(D.Vector2)
	s.attribute_name = "n"
	var rn = H.exec(PartitionNode, s, [d])
	assert_int(rn.bulks.size()).is_equal(2)
	assert_int(rn.bulks[0][0].get_data_attr("n")).is_equal(1 << 40)

func test_merge_appends_new_types_through_the_evaluator() -> void:
	var a = H.data({"t": [_xf([Transform3D.IDENTITY]), D.Transform], "n": [PackedInt64Array([1 << 40]), D.Int64]})
	var b = H.data({"t": [_xf([Transform3D(Basis.IDENTITY, Vector3.ONE)]), D.Transform], "uv": [PackedVector2Array([Vector2(1, 2)]), D.Vector2]})
	var graph = TestGraph.new() \
		.in_param("a", D.Float) \
		.in_param("b", D.Float) \
		.node("in_a", "input_a", {"name": "a", "data_type": D.Float}) \
		.node("in_b", "input_b", {"name": "b", "data_type": D.Float}) \
		.node("merge", "merge") \
		.node("out", "output", {"name": "result"}) \
		.link("in_a", 0, "merge", 0) \
		.link("in_b", 0, "merge", 0) \
		.link("merge", 0, "out", 0) \
		.build()
	var outputs = FlowNodeIO.evaluate_graph(graph, {"a": a, "b": b}, TestGraph.make_ctx(), {}, 0)
	var result : FlowData.Data = outputs.get("result")
	assert_object(result).is_not_null()
	assert_int(H.dtype(result, "t")).is_equal(D.Transform)
	assert_bool(H.values(result, "t") == [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3.ONE)]).is_true()
	assert_array(H.values(result, "n")).is_equal([1 << 40, 0])
	assert_array(H.values(result, "uv")).is_equal([Vector2.ZERO, Vector2(1, 2)])
