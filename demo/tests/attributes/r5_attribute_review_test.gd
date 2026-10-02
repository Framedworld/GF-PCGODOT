# r5_attribute_review_test.gd
# Adversarial review (WP13-R5) of the attribute-type nodes: numeric edge cases,
# broadcast streams, string formatting and transform inversion.
class_name R5AttributeReviewTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const CompareNode = preload("res://addons/flow_nodes_editor/nodes/compare_op.gd")
const CompareSettings = preload("res://addons/flow_nodes_editor/nodes/compare_op_settings.gd")
const StringNode = preload("res://addons/flow_nodes_editor/nodes/attribute_string_op.gd")
const StringSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_string_op_settings.gd")
const CopyNode = preload("res://addons/flow_nodes_editor/nodes/copy_attribute.gd")
const CopySettings = preload("res://addons/flow_nodes_editor/nodes/copy_attribute_settings.gd")
const TransformNode = preload("res://addons/flow_nodes_editor/nodes/transform_op.gd")
const TransformSettings = preload("res://addons/flow_nodes_editor/nodes/transform_op_settings.gd")
const ExpressionNode = preload("res://addons/flow_nodes_editor/nodes/expression.gd")
const ExpressionSettings = preload("res://addons/flow_nodes_editor/nodes/expression_settings.gd")
const FilterNode = preload("res://addons/flow_nodes_editor/nodes/filter.gd")
const FilterSettings = preload("res://addons/flow_nodes_editor/nodes/filter_settings.gd")
const MergeAttrsNode = preload("res://addons/flow_nodes_editor/nodes/merge_attributes.gd")
const MergeAttrsSettings = preload("res://addons/flow_nodes_editor/nodes/merge_attributes_settings.gd")

var D = FlowDataScript.DataType

func _bools(r: Dictionary, stream := "compare") -> Array:
	return H.values(r.out, stream).map(func(v): return v == 1)

func _cmp(op: int, a: String, b: String) -> Object:
	var s = CompareSettings.new()
	s.operation = op
	s.in_nameA = a
	s.in_nameB = b
	return s

# --- compare_op ---------------------------------------------------------------

func test_compare_int_attribute_with_fractional_constant() -> void:
	# 1 >= 1.5 is false; the constant must not be truncated to the Int type of A.
	var d = H.data({"a": [PackedInt32Array([1, 2]), D.Int]})
	var s = _cmp(CompareSettings.eOperation.GreaterOrEqual, "a", "")
	s.use_constant_b = true
	s.constant_b = "1.5"
	var r = H.exec(CompareNode, s, [d])
	assert_str(r.err).is_empty()
	assert_array(_bools(r)).is_equal([false, true])
	s.operation = CompareSettings.eOperation.Equal
	s.tolerance = 0.0
	assert_array(_bools(H.exec(CompareNode, s, [d]))).is_equal([false, false])

func test_compare_nan_is_never_equal() -> void:
	var nan_v : float = sqrt(-1.0)
	var d = H.data({"a": [PackedFloat64Array([nan_v, 1.0]), D.Double], "b": [PackedFloat64Array([nan_v, nan_v]), D.Double]})
	var r = H.exec(CompareNode, _cmp(CompareSettings.eOperation.Equal, "a", "b"), [d])
	assert_array(_bools(r)).is_equal([false, false])

func test_compare_broadcast_b_stream() -> void:
	var d = H.data({
		"a": [PackedFloat32Array([1.0, 2.0, 3.0]), D.Float],
		"b": [PackedFloat32Array([2.0]), D.Float],
	})
	var r = H.exec(CompareNode, _cmp(CompareSettings.eOperation.Less, "a", "b"), [d])
	assert_str(r.err).is_empty()
	assert_array(_bools(r)).is_equal([true, false, false])

# --- attribute_string_op --------------------------------------------------------

func _str(op: int, a: String) -> Object:
	var s = StringSettings.new()
	s.operation = op
	s.in_nameA = a
	s.out_name = "out"
	return s

func test_format_does_not_expand_tokens_inside_values() -> void:
	var d = H.data({
		"a": [PackedStringArray(["{index}", "{1}", "plain"]), D.String],
		"b": [PackedStringArray(["X", "Y", "{0}"]), D.String],
	})
	var s = _str(StringSettings.eOperation.Format, "a")
	s.in_nameB = "b"
	s.format_pattern = "{0}|{1}"
	var r = H.exec(StringNode, s, [d])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "out")).is_equal(["{index}|X", "{1}|Y", "plain|{0}"])

func test_replace_with_empty_pattern_is_identity() -> void:
	var d = H.data({"a": [PackedStringArray(["abc", ""]), D.String]})
	var s = _str(StringSettings.eOperation.Replace, "a")
	s.constant_b = ""
	s.constant_c = "x"
	var r = H.exec(StringNode, s, [d])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "out")).is_equal(["abc", ""])
	s.case_sensitive = false
	r = H.exec(StringNode, s, [d])
	assert_array(H.values(r.out, "out")).is_equal(["abc", ""])

func test_string_ops_on_unicode_and_regex_chars() -> void:
	var d = H.data({"a": [PackedStringArray(["h\u00e9llo.*", "\u65e5\u672c\u8a9e"]), D.String]})
	var s = _str(StringSettings.eOperation.Replace, "a")
	s.constant_b = ".*"
	s.constant_c = "!"
	assert_array(H.values(H.exec(StringNode, s, [d]).out, "out")).is_equal(["h\u00e9llo!", "\u65e5\u672c\u8a9e"])
	s = _str(StringSettings.eOperation.Length, "a")
	assert_array(H.values(H.exec(StringNode, s, [d]).out, "out")).is_equal([7, 3])

# --- copy_attribute ------------------------------------------------------------

func _pts(positions: Array) -> FlowData.Data:
	var c := PackedVector3Array()
	for p in positions:
		c.append(p)
	return H.data({"position": [c, D.Vector]})

func test_copy_unmatched_keeps_broadcast_target_value() -> void:
	var target = _pts([Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(200, 0, 0)])
	target.registerStream("v", PackedFloat32Array([7.0]), D.Float)
	var source = _pts([Vector3(0, 0, 0)])
	source.registerStream("v", PackedFloat32Array([1.0]), D.Float)
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.NearestPoint
	s.source_attribute = "v"
	s.max_distance = 1.0
	var r = H.exec(CopyNode, s, [target, source])
	assert_str(r.err).is_empty()
	# Point 0 matches; points 1 and 2 are unmatched and keep the target's value 7.
	assert_array(H.values(r.out, "v")).is_equal([1.0, 7.0, 7.0])

func test_copy_nearest_with_broadcast_target_position() -> void:
	var target = FlowDataScript.Data.new()
	target.registerStream("id", PackedInt32Array([0, 1, 2]), D.Int)
	target.registerStream("position", PackedVector3Array([Vector3(5, 0, 0)]), D.Vector)
	var source = _pts([Vector3(0, 0, 0), Vector3(5, 0, 0)])
	source.registerStream("v", PackedFloat32Array([1.0, 2.0]), D.Float)
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.NearestPoint
	s.source_attribute = "v"
	var r = H.exec(CopyNode, s, [target, source])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "v")).is_equal([2.0, 2.0, 2.0])

func test_copy_unmatched_quaternion_defaults_to_identity() -> void:
	var target = _pts([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	var source = _pts([Vector3(0, 0, 0)])
	source.registerStream("q", PackedVector4Array([Vector4(0, 0.7071068, 0, 0.7071068)]), D.Quaternion)
	var s = CopySettings.new()
	s.mode = CopySettings.eMode.NearestPoint
	s.source_attribute = "q"
	s.max_distance = 1.0
	var r = H.exec(CopyNode, s, [target, source])
	assert_str(r.err).is_empty()
	var q = H.values(r.out, "q")
	assert_vector(q[0]).is_equal(Vector4(0, 0.7071068, 0, 0.7071068))
	# Unmatched: the identity rotation, not the invalid zero quaternion.
	assert_vector(q[1]).is_equal(Vector4(0, 0, 0, 1))

func test_merge_attributes_missing_quaternion_defaults_to_identity() -> void:
	var a = H.data({"q": [PackedVector4Array([Vector4(0, 1, 0, 0)]), D.Quaternion]})
	var b = H.data({"f": [PackedFloat32Array([2.0]), D.Float]})
	var r : Dictionary = MergeAttrsNode.merge_entries([a, b], MergeAttrsSettings.eMode.Append, true)
	assert_bool(r.ok).is_true()
	var q = H.values(r.data, "q")
	assert_vector(q[0]).is_equal(Vector4(0, 1, 0, 0))
	assert_vector(q[1]).is_equal(Vector4(0, 0, 0, 1))

# --- transform_op --------------------------------------------------------------

func _finite_xf(xf: Transform3D) -> bool:
	for k in range(3):
		if not is_finite(xf.origin[k]):
			return false
		for j in range(3):
			if not is_finite(xf.basis[k][j]):
				return false
	return true

func test_invert_zero_scale_transform_stays_finite() -> void:
	var xfs : Array[Transform3D] = [
		Transform3D(Basis.from_scale(Vector3(0, 1, 1)), Vector3(1, 2, 3)),
		Transform3D(Basis.from_scale(Vector3(2, 2, 2)), Vector3(1, 0, 0)),
	]
	var d = H.data({"transform": [xfs, D.Transform]})
	var s = TransformSettings.new()
	s.operation = TransformSettings.eOperation.Invert
	var r = H.exec(TransformNode, s, [d])
	assert_str(r.err).is_empty()
	var out = H.values(r.out, "transform")
	assert_bool(_finite_xf(out[0])).is_true()
	# A regular transform inverts exactly as before.
	assert_bool(out[1].is_equal_approx(xfs[1].affine_inverse())).is_true()

func test_invert_zero_scale_rotated_transform_uses_safe_reciprocal() -> void:
	# UE FTransform::Inverse: rotation inverted, scale by its safe reciprocal
	# (0 stays 0), translation -(inverse * t). Godot's affine_inverse leaves a
	# singular basis untouched instead (and logs an engine error).
	var rot := Basis(Vector3.UP, PI / 2.0)
	var t := Vector3(1, 2, 3)
	var xfs : Array[Transform3D] = [
		Transform3D(rot * Basis.from_scale(Vector3(0, 2, 1)), t),
		Transform3D(Basis.from_scale(Vector3.ZERO), t),
	]
	var d = H.data({"transform": [xfs, D.Transform]})
	var s = TransformSettings.new()
	s.operation = TransformSettings.eOperation.Invert
	var r = H.exec(TransformNode, s, [d])
	assert_str(r.err).is_empty()
	var out = H.values(r.out, "transform")
	var inv_basis := Basis.from_scale(Vector3(0, 0.5, 1)) * rot.transposed()
	var expected := Transform3D(inv_basis, -(inv_basis * t))
	assert_bool(out[0].is_equal_approx(expected)).is_true()
	assert_bool(out[1].is_equal_approx(Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))).is_true()
	# InverseTransformPosition uses the same inverse.
	var d2 = H.data({"transform": [xfs, D.Transform], "p": [PackedVector3Array([Vector3(1, 2, 3), Vector3(1, 2, 3)]), D.Vector]})
	s.operation = TransformSettings.eOperation.InverseTransformPosition
	s.in_nameB = "p"
	s.out_name = "local"
	r = H.exec(TransformNode, s, [d2])
	assert_str(r.err).is_empty()
	var local = H.values(r.out, "local")
	assert_bool(local[0].is_equal_approx(Vector3.ZERO)).is_true()

# --- broadcast streams through the extended old nodes ----------------------------

func test_expression_reads_broadcast_streams() -> void:
	var d = H.data({
		"a": [PackedFloat32Array([1.0, 2.0, 3.0]), D.Float],
		"k": [PackedFloat32Array([10.0]), D.Float],
	})
	var s = ExpressionSettings.new()
	s.expression = "a + k"
	s.out_name = "r"
	var r = H.exec(ExpressionNode, s, [d])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "r")).is_equal([11.0, 12.0, 13.0])

func test_filter_reads_broadcast_a_stream() -> void:
	# A is a length-1 (broadcast) stream on a 3-point Data; B comes from In B.
	var da = H.data({
		"id": [PackedInt32Array([0, 1, 2]), D.Int],
		"a": [PackedFloat32Array([0.5]), D.Float],
	})
	var db = H.data({"b": [PackedFloat32Array([0.0, 1.0, 2.0]), D.Float]})
	var s = FilterSettings.new()
	s.in_nameA = "a"
	s.in_nameB = "b"
	s.condition = FilterSettings.eCondition.Greater
	var node = H.run(FilterNode, s, [da, db])
	assert_str(String(node.err)).is_empty()
	var t = H.output(node, 0)
	var f = H.output(node, 1)
	assert_object(t).is_not_null()
	assert_array(H.values(t, "id")).is_equal([0])
	assert_array(H.values(f, "id")).is_equal([1, 2])
	# IsNull reads A per point too.
	s.condition = FilterSettings.eCondition.IsNull
	node = H.run(FilterNode, s, [da, db])
	assert_str(String(node.err)).is_empty()
	assert_array(H.values(H.output(node, 1), "id")).is_equal([0, 1, 2])

func test_compare_int64_extremes_are_not_equal() -> void:
	# a - b overflows for these pairs; integers must compare exactly.
	var big : int = 0x7fffffffffffffff
	var small : int = -big - 1
	var d = H.data({
		"a": [PackedInt64Array([big, small, small]), D.Int64],
		"b": [PackedInt64Array([-1, 0, big]), D.Int64],
	})
	var r = H.exec(CompareNode, _cmp(CompareSettings.eOperation.Equal, "a", "b"), [d])
	assert_str(r.err).is_empty()
	assert_array(_bools(r)).is_equal([false, false, false])
	r = H.exec(CompareNode, _cmp(CompareSettings.eOperation.NotEqual, "a", "b"), [d])
	assert_array(_bools(r)).is_equal([true, true, true])

