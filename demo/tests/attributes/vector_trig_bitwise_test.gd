# vector_trig_bitwise_test.gd
class_name VectorTrigBitwiseOpTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const VectorNode = preload("res://addons/flow_nodes_editor/nodes/vector_op.gd")
const VectorSettings = preload("res://addons/flow_nodes_editor/nodes/vector_op_settings.gd")
const TrigNode = preload("res://addons/flow_nodes_editor/nodes/trig_op.gd")
const TrigSettings = preload("res://addons/flow_nodes_editor/nodes/trig_op_settings.gd")
const BitwiseNode = preload("res://addons/flow_nodes_editor/nodes/bitwise_op.gd")
const BitwiseSettings = preload("res://addons/flow_nodes_editor/nodes/bitwise_op_settings.gd")

var D = FlowDataScript.DataType

func _vec(op: int, a := "a", b := "b") -> Object:
	var s = VectorSettings.new()
	s.operation = op
	s.in_nameA = a
	s.in_nameB = b
	s.out_name = "r"
	return s

func _vdata() -> FlowData.Data:
	return H.data({
		"a": [PackedVector3Array([Vector3(1, 0, 0), Vector3(3, 4, 0)]), D.Vector],
		"b": [PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 0, 0)]), D.Vector],
		"t": [PackedFloat32Array([0.5, 0.25]), D.Float],
	})

func _r(s, d = null) -> Array:
	var r = H.exec(VectorNode, s, [d if d != null else _vdata()])
	assert_str(r.err).is_empty()
	return H.values(r.out, "r")

func test_scalar_results() -> void:
	var E = VectorSettings.eOperation
	assert_array(_r(_vec(E.Dot))).is_equal([0.0, 3.0])
	assert_array(_r(_vec(E.Length))).is_equal([1.0, 5.0])
	assert_array(_r(_vec(E.LengthSquared))).is_equal([1.0, 25.0])
	assert_float(_r(_vec(E.Distance))[1]).is_equal_approx(sqrt(20.0), 1e-5)
	assert_array(_r(_vec(E.DistanceSquared))).is_equal([2.0, 20.0])
	assert_float(_r(_vec(E.Angle))[0]).is_equal_approx(90.0, 1e-4)
	var r = H.exec(VectorNode, _vec(E.Dot), [_vdata()])
	assert_int(H.dtype(r.out, "r")).is_equal(D.Float)

func test_vector_results() -> void:
	var E = VectorSettings.eOperation
	assert_array(_r(_vec(E.Cross))).is_equal([Vector3(0, 0, 1), Vector3(0, 0, -4)])
	assert_array(_r(_vec(E.Normalize))).is_equal([Vector3(1, 0, 0), Vector3(0.6, 0.8, 0)])
	assert_array(_r(_vec(E.Project))).is_equal([Vector3.ZERO, Vector3(3, 0, 0)])
	# Reflect off a floor (normal +Y): the Y component flips
	var refl = _vec(E.Reflect, "a")
	refl.use_constant_b = true
	refl.constant_b = Vector4(0, 1, 0, 0)
	var d = H.data({"a": [PackedVector3Array([Vector3(1, -2, 0)]), D.Vector]})
	assert_array(_r(refl, d)).is_equal([Vector3(1, 2, 0)])
	var lerp = _vec(E.Lerp)
	lerp.in_nameC = "t"
	assert_array(_r(lerp)).is_equal([Vector3(0.5, 0.5, 0), Vector3(2.5, 3, 0)])
	var rot = _vec(E.RotateAroundAxis)
	rot.use_constant_b = true
	rot.constant_b = Vector4(0, 0, 1, 0)
	rot.constant_c = 90.0
	var rotated : Vector3 = _r(rot)[0]
	assert_bool(rotated.is_equal_approx(Vector3(0, 1, 0))).is_true()
	assert_array(_r(_vec(E.ComponentMin))).is_equal([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	assert_array(_r(_vec(E.ComponentMax))).is_equal([Vector3(1, 1, 0), Vector3(3, 4, 0)])

func test_vector2_and_vector4_operands() -> void:
	var E = VectorSettings.eOperation
	var d = H.data({
		"a": [PackedVector2Array([Vector2(3, 4)]), D.Vector2],
		"b": [PackedVector2Array([Vector2(1, 0)]), D.Vector2],
	})
	assert_array(_r(_vec(E.Length), d)).is_equal([5.0])
	assert_array(_r(_vec(E.Cross), d)).is_equal([-4.0])
	var n = H.exec(VectorNode, _vec(E.Normalize), [d])
	assert_int(H.dtype(n.out, "r")).is_equal(D.Vector2)
	var d4 = H.data({"a": [PackedVector4Array([Vector4(1, 1, 1, 1)]), D.Vector4]})
	var dot = _vec(E.Dot, "a")
	dot.use_constant_b = true
	dot.constant_b = Vector4(1, 2, 3, 4)
	assert_array(_r(dot, d4)).is_equal([10.0])
	assert_str(H.exec(VectorNode, _vec(E.Cross, "a", "a"), [d4]).err).contains("Cross")

func test_scalar_b_broadcasts_and_source_output() -> void:
	var E = VectorSettings.eOperation
	var s = _vec(E.ComponentMax, "a", "t")
	s.out_name = "@Source"
	var r = H.exec(VectorNode, s, [_vdata()])
	assert_array(H.values(r.out, "a")).is_equal([Vector3(1, 0.5, 0.5), Vector3(3, 4, 0.25)])

func test_non_vector_a_fails() -> void:
	var r = H.exec(VectorNode, _vec(VectorSettings.eOperation.Length, "t"), [_vdata()])
	assert_str(r.err).contains("Vector Op needs")

func _trig(op: int, a: String) -> Object:
	var s = TrigSettings.new()
	s.operation = op
	s.in_nameA = a
	s.out_name = "r"
	return s

func test_trig_scalars_and_types() -> void:
	var E = TrigSettings.eOperation
	var d = H.data({
		"f": [PackedFloat32Array([0.0, PI / 2]), D.Float],
		"dd": [PackedFloat64Array([1.0]), D.Double],
		"deg": [PackedInt32Array([180]), D.Int],
	})
	var r = H.exec(TrigNode, _trig(E.Sin, "f"), [d])
	assert_int(H.dtype(r.out, "r")).is_equal(D.Float)
	assert_float(H.values(r.out, "r")[1]).is_equal_approx(1.0, 1e-6)
	var rd = H.exec(TrigNode, _trig(E.Acos, "dd"), [d])
	assert_int(H.dtype(rd.out, "r")).is_equal(D.Double)
	assert_float(H.values(rd.out, "r")[0]).is_equal(0.0)
	assert_float(H.values(H.exec(TrigNode, _trig(E.DegToRad, "deg"), [d]).out, "r")[0]).is_equal_approx(PI, 1e-6)
	var at = _trig(E.Atan2, "f")
	at.use_constant_b = true
	at.constant_b = 0.0
	# atan2(y = pi/2, x = 0) = pi/2
	assert_float(H.values(H.exec(TrigNode, at, [d]).out, "r")[1]).is_equal_approx(PI / 2, 1e-6)

func test_trig_vectors_per_component() -> void:
	var d = H.data({"v": [PackedVector3Array([Vector3(0, 90, 180)]), D.Vector]})
	var r = H.exec(TrigNode, _trig(TrigSettings.eOperation.DegToRad, "v"), [d])
	assert_int(H.dtype(r.out, "r")).is_equal(D.Vector)
	assert_bool((H.values(r.out, "r")[0] as Vector3).is_equal_approx(Vector3(0, PI / 2, PI))).is_true()
	var bad = H.data({"s": [PackedStringArray(["x"]), D.String]})
	assert_str(H.exec(TrigNode, _trig(TrigSettings.eOperation.Sin, "s"), [bad]).err).contains("Trig Op needs")

func _bit(op: int, a: String, b: int) -> Object:
	var s = BitwiseSettings.new()
	s.operation = op
	s.in_nameA = a
	s.constant_b = b
	s.out_name = "r"
	return s

func test_bitwise_ops() -> void:
	var E = BitwiseSettings.eOperation
	var d = H.data({"i": [PackedInt32Array([12, -1]), D.Int]})
	assert_array(H.values(H.exec(BitwiseNode, _bit(E.And, "i", 10), [d]).out, "r")).is_equal([8, 10])
	assert_array(H.values(H.exec(BitwiseNode, _bit(E.Or, "i", 3), [d]).out, "r")).is_equal([15, -1])
	assert_array(H.values(H.exec(BitwiseNode, _bit(E.Xor, "i", 5), [d]).out, "r")).is_equal([9, -6])
	assert_array(H.values(H.exec(BitwiseNode, _bit(E.Not, "i", 0), [d]).out, "r")).is_equal([-13, 0])
	assert_array(H.values(H.exec(BitwiseNode, _bit(E.ShiftLeft, "i", 2), [d]).out, "r")).is_equal([48, -4])
	assert_array(H.values(H.exec(BitwiseNode, _bit(E.ShiftRight, "i", 2), [d]).out, "r")).is_equal([3, -1])

func test_bitwise_int32_wraps_int64_keeps_bits() -> void:
	var E = BitwiseSettings.eOperation
	var d = H.data({"i": [PackedInt32Array([1]), D.Int], "j": [PackedInt64Array([1]), D.Int64]})
	var r32 = H.exec(BitwiseNode, _bit(E.ShiftLeft, "i", 33), [d])
	assert_int(H.dtype(r32.out, "r")).is_equal(D.Int)
	assert_array(H.values(r32.out, "r")).is_equal([0])
	var r64 = H.exec(BitwiseNode, _bit(E.ShiftLeft, "j", 33), [d])
	assert_int(H.dtype(r64.out, "r")).is_equal(D.Int64)
	assert_array(H.values(r64.out, "r")).is_equal([1 << 33])
	var forced = _bit(E.ShiftLeft, "i", 33)
	forced.output_type = BitwiseSettings.eOutputType.Int64
	assert_array(H.values(H.exec(BitwiseNode, forced, [d]).out, "r")).is_equal([1 << 33])

func test_bitwise_rejects_reals() -> void:
	var d = H.data({"f": [PackedFloat32Array([1.0]), D.Float]})
	assert_str(H.exec(BitwiseNode, _bit(BitwiseSettings.eOperation.And, "f", 1), [d]).err).contains("cast it first")
