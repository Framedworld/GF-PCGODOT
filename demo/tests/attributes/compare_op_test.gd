# compare_op_test.gd
class_name CompareOpNodeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const CompareNode = preload("res://addons/flow_nodes_editor/nodes/compare_op.gd")
const CompareSettings = preload("res://addons/flow_nodes_editor/nodes/compare_op_settings.gd")

var D = FlowDataScript.DataType
var E = CompareSettings.eOperation

func _settings(op: int, a: String, b: String) -> Object:
	var s = CompareSettings.new()
	s.operation = op
	s.in_nameA = a
	s.in_nameB = b
	return s

func _bools(r: Dictionary) -> Array:
	return H.values(r.out, "compare").map(func(v): return v == 1)

func test_numeric_operators() -> void:
	var d = H.data({
		"a": [PackedFloat32Array([1.0, 2.0, 3.0]), D.Float],
		"b": [PackedInt32Array([2, 2, 2]), D.Int],
	})
	assert_array(_bools(H.exec(CompareNode, _settings(E.Equal, "a", "b"), [d]))).is_equal([false, true, false])
	assert_array(_bools(H.exec(CompareNode, _settings(E.NotEqual, "a", "b"), [d]))).is_equal([true, false, true])
	assert_array(_bools(H.exec(CompareNode, _settings(E.Greater, "a", "b"), [d]))).is_equal([false, false, true])
	assert_array(_bools(H.exec(CompareNode, _settings(E.GreaterOrEqual, "a", "b"), [d]))).is_equal([false, true, true])
	assert_array(_bools(H.exec(CompareNode, _settings(E.Less, "a", "b"), [d]))).is_equal([true, false, false])
	assert_array(_bools(H.exec(CompareNode, _settings(E.LessOrEqual, "a", "b"), [d]))).is_equal([true, true, false])
	assert_int(H.dtype(H.exec(CompareNode, _settings(E.Less, "a", "b"), [d]).out, "compare")).is_equal(D.Bool)

func test_tolerance_applies_to_equality() -> void:
	var d = H.data({"a": [PackedFloat32Array([1.0, 1.05]), D.Float]})
	var s = _settings(E.Equal, "a", "")
	s.use_constant_b = true
	s.constant_b = "1"
	s.tolerance = 0.1
	assert_array(_bools(H.exec(CompareNode, s, [d]))).is_equal([true, true])
	s.tolerance = 0.01
	assert_array(_bools(H.exec(CompareNode, s, [d]))).is_equal([true, false])

func test_int64_compares_exactly() -> void:
	var big := (1 << 53) + 1
	var d = H.data({
		"a": [PackedInt64Array([big]), D.Int64],
		"b": [PackedInt64Array([1 << 53]), D.Int64],
	})
	var s = _settings(E.Equal, "a", "b")
	s.tolerance = 0.0
	assert_array(_bools(H.exec(CompareNode, s, [d]))).is_equal([false])
	assert_array(_bools(H.exec(CompareNode, _settings(E.Greater, "a", "b"), [d]))).is_equal([true])

func test_strings_lexicographic_and_case() -> void:
	var d = H.data({
		"a": [PackedStringArray(["apple", "Pear", "kiwi"]), D.String],
		"b": [PackedStringArray(["banana", "pear", "kiwi"]), D.String],
	})
	assert_array(_bools(H.exec(CompareNode, _settings(E.Less, "a", "b"), [d]))).is_equal([true, true, false])
	assert_array(_bools(H.exec(CompareNode, _settings(E.Equal, "a", "b"), [d]))).is_equal([false, false, true])
	var s = _settings(E.Equal, "a", "b")
	s.case_sensitive = false
	assert_array(_bools(H.exec(CompareNode, s, [d]))).is_equal([false, true, true])

func test_vector_modes() -> void:
	var d = H.data({
		"a": [PackedVector3Array([Vector3(1, 2, 3), Vector3(5, 0, 0)]), D.Vector],
		"b": [PackedVector3Array([Vector3(1, 2, 3.00001), Vector3(0, 1, 0)]), D.Vector],
	})
	assert_array(_bools(H.exec(CompareNode, _settings(E.Equal, "a", "b"), [d]))).is_equal([true, false])
	assert_array(_bools(H.exec(CompareNode, _settings(E.NotEqual, "a", "b"), [d]))).is_equal([false, true])
	var any = _settings(E.Greater, "a", "b")
	any.vector_mode = CompareSettings.eVectorMode.AnyComponent
	assert_array(_bools(H.exec(CompareNode, any, [d]))).is_equal([false, true])
	var all = _settings(E.Greater, "a", "b")
	assert_array(_bools(H.exec(CompareNode, all, [d]))).is_equal([false, false])
	var length = _settings(E.Greater, "a", "b")
	length.vector_mode = CompareSettings.eVectorMode.Length
	assert_array(_bools(H.exec(CompareNode, length, [d]))).is_equal([false, true])

func test_vector_against_constant_and_vector2() -> void:
	var d = H.data({"uv": [PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.5, 2)]), D.Vector2]})
	var s = _settings(E.LessOrEqual, "uv", "")
	s.use_constant_b = true
	s.constant_b = "1"
	assert_array(_bools(H.exec(CompareNode, s, [d]))).is_equal([true, false])

func test_b_from_second_input() -> void:
	var a = H.data({"v": [PackedFloat32Array([1, 5]), D.Float]})
	var b = H.data({"limit": [PackedFloat32Array([3]), D.Float]})
	assert_array(_bools(H.exec(CompareNode, _settings(E.Greater, "v", "limit"), [a, b]))).is_equal([false, true])

func test_transform_equality_only() -> void:
	var c = FlowDataScript.Data.newContainerOfType(D.Transform)
	c.append(Transform3D.IDENTITY)
	var d = H.data({"t": [c, D.Transform]})
	assert_array(_bools(H.exec(CompareNode, _settings(E.Equal, "t", "t"), [d]))).is_equal([true])
	assert_str(H.exec(CompareNode, _settings(E.Less, "t", "t"), [d]).err).contains("only support")

func test_incompatible_types_fail_loudly() -> void:
	var d = H.data({
		"s": [PackedStringArray(["1"]), D.String],
		"f": [PackedFloat32Array([1.0]), D.Float],
	})
	var r = H.exec(CompareNode, _settings(E.Equal, "s", "f"), [d])
	assert_str(r.err).contains("Can't compare")
	assert_object(r.out).is_null()

func test_aliases_as_operands() -> void:
	var d = H.data({"density": [PackedFloat32Array([0.2, 0.8]), D.Float]})
	var s = _settings(E.Greater, "$Density", "")
	s.use_constant_b = true
	s.constant_b = "0.5"
	assert_array(_bools(H.exec(CompareNode, s, [d]))).is_equal([false, true])
