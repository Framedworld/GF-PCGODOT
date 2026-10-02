# attribute_cast_test.gd
class_name AttributeCastNodeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")
const CastNode = preload("res://addons/flow_nodes_editor/nodes/attribute_cast.gd")
const CastSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_cast_settings.gd")

var D = FlowDataScript.DataType

func _cast(d: FlowData.Data, input: String, to_type: int, configure: Callable = Callable()) -> Dictionary:
	var s = CastSettings.new()
	s.input_attribute = input
	s.output_type = to_type
	s.output_attribute = "out"
	if configure.is_valid():
		configure.call(s)
	return H.exec(CastNode, s, [d])

func test_float_to_int_truncates_toward_zero_by_default() -> void:
	var d = H.data({"f": [PackedFloat32Array([2.7, -2.7, 0.5]), D.Float]})
	var r = _cast(d, "f", D.Int)
	assert_str(r.err).is_empty()
	assert_int(H.dtype(r.out, "out")).is_equal(D.Int)
	assert_array(H.values(r.out, "out")).is_equal([2, -2, 0])

func test_float_to_int_rounding_modes() -> void:
	var d = H.data({"f": [PackedFloat64Array([2.5, -2.5, -2.1]), D.Double]})
	assert_array(H.values(_cast(d, "f", D.Int, func(s): s.float_to_int = Ops.eFloatToInt.Round).out, "out")).is_equal([3, -3, -2])
	assert_array(H.values(_cast(d, "f", D.Int, func(s): s.float_to_int = Ops.eFloatToInt.Floor).out, "out")).is_equal([2, -3, -3])
	assert_array(H.values(_cast(d, "f", D.Int64, func(s): s.float_to_int = Ops.eFloatToInt.Ceil).out, "out")).is_equal([3, -2, -2])

func test_int64_to_int_wraps_or_clamps() -> void:
	var big := (1 << 32) + 5
	var d = H.data({"i": [PackedInt64Array([big, -(1 << 40)]), D.Int64]})
	assert_array(H.values(_cast(d, "i", D.Int).out, "out")).is_equal([5, 0])
	assert_array(H.values(_cast(d, "i", D.Int, func(s): s.int_overflow = Ops.eIntOverflow.Clamp).out, "out")).is_equal([2147483647, -2147483648])

func test_int_to_int64_and_double_keep_precision() -> void:
	var d = H.data({"i": [PackedInt32Array([2147483647, -7]), D.Int]})
	var r = _cast(d, "i", D.Int64)
	assert_int(H.dtype(r.out, "out")).is_equal(D.Int64)
	assert_array(H.values(r.out, "out")).is_equal([2147483647, -7])
	var r2 = _cast(d, "i", D.Double)
	assert_array(H.values(r2.out, "out")).is_equal([2147483647.0, -7.0])

func test_double_to_float_rounds_to_32_bit() -> void:
	var d = H.data({"x": [PackedFloat64Array([0.1]), D.Double]})
	var r = _cast(d, "x", D.Float)
	assert_int(H.dtype(r.out, "out")).is_equal(D.Float)
	var v : float = H.values(r.out, "out")[0]
	assert_bool(v != 0.1).is_true()	# float32 rounding is visible...
	assert_float(v).is_equal_approx(0.1, 1e-7)	# ...but tiny

func test_numbers_to_bool_and_string() -> void:
	var d = H.data({"f": [PackedFloat32Array([0.0, 0.25, -3.0]), D.Float]})
	assert_array(H.values(_cast(d, "f", D.Bool).out, "out")).is_equal([0, 1, 1])
	var b = H.data({"b": [PackedByteArray([1, 0]), D.Bool]})
	assert_array(H.values(_cast(b, "b", D.String).out, "out")).is_equal(["true", "false"])
	assert_array(H.values(_cast(b, "b", D.Int).out, "out")).is_equal([1, 0])

func test_scalar_broadcasts_to_vectors() -> void:
	var d = H.data({"f": [PackedFloat32Array([2.0]), D.Float]})
	assert_array(H.values(_cast(d, "f", D.Vector2).out, "out")).is_equal([Vector2(2, 2)])
	assert_array(H.values(_cast(d, "f", D.Vector).out, "out")).is_equal([Vector3(2, 2, 2)])
	assert_array(H.values(_cast(d, "f", D.Vector4).out, "out")).is_equal([Vector4(2, 2, 2, 2)])
	assert_array(H.values(_cast(d, "f", D.Color).out, "out")).is_equal([Color(2, 2, 2, 1)])

func test_vector_widening_pads_and_narrowing_drops() -> void:
	var d = H.data({"v": [PackedVector3Array([Vector3(1, 2, 3)]), D.Vector]})
	assert_array(H.values(_cast(d, "v", D.Vector4).out, "out")).is_equal([Vector4(1, 2, 3, 0)])
	assert_array(H.values(_cast(d, "v", D.Vector2).out, "out")).is_equal([Vector2(1, 2)])
	assert_array(H.values(_cast(d, "v", D.Color).out, "out")).is_equal([Color(1, 2, 3, 1)])
	var v4 = H.data({"v": [PackedVector4Array([Vector4(1, 2, 3, 4)]), D.Vector4]})
	assert_array(H.values(_cast(v4, "v", D.Vector).out, "out")).is_equal([Vector3(1, 2, 3)])

func test_vector_to_scalar_is_refused_unless_configured() -> void:
	var d = H.data({"v": [PackedVector3Array([Vector3(3, 4, 0)]), D.Vector]})
	var r = _cast(d, "v", D.Float)
	assert_str(r.err).contains("can't be cast")
	assert_object(r.out).is_null()
	assert_array(H.values(_cast(d, "v", D.Float, func(s): s.vector_to_scalar = Ops.eVectorToScalar.Length).out, "out")).is_equal([5.0])
	assert_array(H.values(_cast(d, "v", D.Double, func(s): s.vector_to_scalar = Ops.eVectorToScalar.FirstComponent).out, "out")).is_equal([3.0])

func test_euler_quaternion_and_transform_conversions() -> void:
	var d = H.data({"r": [PackedVector3Array([Vector3(0, 90, 0)]), D.Vector]})
	var q = _cast(d, "r", D.Quaternion)
	assert_int(H.dtype(q.out, "out")).is_equal(D.Quaternion)
	var stored : Vector4 = H.values(q.out, "out")[0]
	var expected := Quaternion(Vector3.UP, PI / 2)
	assert_float(absf(FlowDataScript.vec4ToQuat(stored).dot(expected))).is_equal_approx(1.0, 1e-5)
	# Quaternion back to Euler degrees
	var back = _cast(q.out, "out", D.Vector, func(s): s.output_attribute = "euler")
	assert_float(H.values(back.out, "euler")[0].y).is_equal_approx(90.0, 1e-3)
	# Vector -> Transform is a translation; Transform -> Vector the origin
	var p = H.data({"p": [PackedVector3Array([Vector3(1, 2, 3)]), D.Vector]})
	var xf = _cast(p, "p", D.Transform)
	assert_bool(H.values(xf.out, "out")[0] == Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))).is_true()
	var origin = _cast(xf.out, "out", D.Vector, func(s): s.output_attribute = "o")
	assert_array(H.values(origin.out, "o")).is_equal([Vector3(1, 2, 3)])
	# Transform -> Float is refused
	assert_str(_cast(xf.out, "out", D.Float).err).contains("Transform can only be cast")

func test_strings_parse_or_fail_loudly() -> void:
	var d = H.data({"s": [PackedStringArray(["12", "3.9", "1,2"]), D.String]})
	var r = _cast(d, "s", D.Int)
	assert_str(r.err).contains("Can't parse '1,2'")
	var ok = H.data({"s": [PackedStringArray(["12", "3.9", "-1"]), D.String]})
	assert_array(H.values(_cast(ok, "s", D.Int).out, "out")).is_equal([12, 3, -1])
	assert_array(H.values(_cast(ok, "s", D.Double).out, "out")).is_equal([12.0, 3.9, -1.0])
	var vec = H.data({"s": [PackedStringArray(["1,2,3", "Vector3(4, 5, 6)"]), D.String]})
	assert_array(H.values(_cast(vec, "s", D.Vector).out, "out")).is_equal([Vector3(1, 2, 3), Vector3(4, 5, 6)])

func test_source_output_retypes_in_place_and_respects_canonical_types() -> void:
	var d = H.data({"count": [PackedInt32Array([1, 2]), D.Int]})
	var s = CastSettings.new()
	s.input_attribute = "count"
	s.output_type = D.Int64
	var r = H.exec(CastNode, s, [d])
	assert_str(r.err).is_empty()
	assert_int(H.dtype(r.out, "count")).is_equal(D.Int64)
	# The input is not modified.
	assert_int(d.findStream("count").data_type).is_equal(D.Int)
	# Casting density in place to Double is refused: density is canonically Float.
	var pts = H.data({"density": [PackedFloat32Array([0.5]), D.Float]})
	var s2 = CastSettings.new()
	s2.input_attribute = "$Density"
	s2.output_type = D.Double
	assert_str(H.exec(CastNode, s2, [pts]).err).contains("canonical")

func test_every_type_to_string_and_back_to_itself() -> void:
	var samples := {
		D.Bool: PackedByteArray([1]), D.Int: PackedInt32Array([4]), D.Float: PackedFloat32Array([0.5]),
		D.Vector: PackedVector3Array([Vector3(1, 2, 3)]), D.String: PackedStringArray(["x"]),
		D.Color: PackedColorArray([Color.RED]), D.Quaternion: PackedVector4Array([Vector4(0, 0, 0, 1)]),
		D.Vector2: PackedVector2Array([Vector2(1, 2)]), D.Vector4: PackedVector4Array([Vector4(1, 2, 3, 4)]),
		D.Int64: PackedInt64Array([1 << 40]), D.Double: PackedFloat64Array([0.1]),
	}
	var xf = FlowDataScript.Data.newContainerOfType(D.Transform)
	xf.append(Transform3D.IDENTITY)
	samples[D.Transform] = xf
	for t in samples:
		var d = H.data({"a": [samples[t], t]})
		var same = _cast(d, "a", t)
		assert_str(same.err).override_failure_message("identity cast %d" % t).is_empty()
		assert_bool(H.values(same.out, "out") == H.values(d, "a")).override_failure_message("identity cast %d" % t).is_true()
		var txt = _cast(d, "a", D.String)
		assert_str(txt.err).override_failure_message("to string %d" % t).is_empty()
		assert_int(H.dtype(txt.out, "out")).is_equal(D.String)
