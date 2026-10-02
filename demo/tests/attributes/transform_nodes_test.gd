# transform_nodes_test.gd
# make_transform_attribute, break_transform_attribute and transform_op.
class_name TransformAttributeNodesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const MakeNode = preload("res://addons/flow_nodes_editor/nodes/make_transform_attribute.gd")
const MakeSettings = preload("res://addons/flow_nodes_editor/nodes/make_transform_attribute_settings.gd")
const BreakNode = preload("res://addons/flow_nodes_editor/nodes/break_transform_attribute.gd")
const BreakSettings = preload("res://addons/flow_nodes_editor/nodes/break_transform_attribute_settings.gd")
const OpNode = preload("res://addons/flow_nodes_editor/nodes/transform_op.gd")
const OpSettings = preload("res://addons/flow_nodes_editor/nodes/transform_op_settings.gd")

var D = FlowDataScript.DataType

func _points() -> FlowData.Data:
	return H.data({
		"position": [PackedVector3Array([Vector3(1, 2, 3), Vector3(-4, 0, 2)]), D.Vector],
		"rotation": [PackedVector3Array([Vector3(0, 90, 0), Vector3(30, 45, 10)]), D.Vector],
		"size": [PackedVector3Array([Vector3(2, 2, 2), Vector3(1, 2, 3)]), D.Vector],
	})

func _make(d: FlowData.Data) -> FlowData.Data:
	var r = H.exec(MakeNode, MakeSettings.new(), [d])
	assert_str(r.err).is_empty()
	return r.out

func test_make_transform_from_point_streams() -> void:
	var out = _make(_points())
	assert_int(H.dtype(out, "transform")).is_equal(D.Transform)
	var xf : Transform3D = H.values(out, "transform")[0]
	assert_bool(xf.origin.is_equal_approx(Vector3(1, 2, 3))).is_true()
	# R * S: the local X axis is rotated by the yaw and scaled by 2
	assert_bool((xf.basis * Vector3.RIGHT).is_equal_approx(Vector3(0, 0, -2))).is_true()

func test_make_transform_constants_and_quaternion_rotation() -> void:
	var d = H.data({"q": [PackedVector4Array([FlowDataScript.quatToVec4(Quaternion(Vector3.UP, PI))]), D.Quaternion]})
	var s = MakeSettings.new()
	s.translation_attribute = ""
	s.rotation_attribute = "q"
	s.scale_attribute = ""
	s.default_translation = Vector3(0, 5, 0)
	var r = H.exec(MakeNode, s, [d])
	assert_str(r.err).is_empty()
	var xf : Transform3D = H.values(r.out, "transform")[0]
	assert_bool(xf.origin.is_equal_approx(Vector3(0, 5, 0))).is_true()
	assert_bool((xf.basis * Vector3.RIGHT).is_equal_approx(Vector3(-1, 0, 0))).is_true()

func test_make_transform_wrong_type_fails() -> void:
	var d = H.data({"t": [PackedFloat32Array([1.0]), D.Float]})
	var s = MakeSettings.new()
	s.translation_attribute = "t"
	var r = H.exec(MakeNode, s, [d])
	assert_str(r.err).contains("expected Vector")

func test_break_round_trips_make() -> void:
	var pts = _points()
	var made = _make(pts)
	var s = BreakSettings.new()
	s.out_quaternion = "q"
	var r = H.exec(BreakNode, s, [made])
	assert_str(r.err).is_empty()
	for i in range(2):
		assert_bool((H.values(r.out, "translation")[i] as Vector3).is_equal_approx(H.values(pts, "position")[i])).is_true()
		assert_bool((H.values(r.out, "scale")[i] as Vector3).is_equal_approx(H.values(pts, "size")[i])).override_failure_message("scale %d" % i).is_true()
		var a := FlowDataScript.eulerToQuat(H.values(r.out, "rotator")[i])
		var b := FlowDataScript.eulerToQuat(H.values(pts, "rotation")[i])
		assert_float(absf(a.dot(b))).is_equal_approx(1.0, 1e-4)
	assert_int(H.dtype(r.out, "q")).is_equal(D.Quaternion)

func test_break_requires_a_transform() -> void:
	var s = BreakSettings.new()
	s.in_name = "position"
	assert_str(H.exec(BreakNode, s, [_points()]).err).contains("not a Transform")

func _op(op: int) -> Object:
	var s = OpSettings.new()
	s.operation = op
	s.out_name = "r"
	return s

func test_compose_applies_a_then_b() -> void:
	var a := Transform3D(Basis(Vector3.UP, PI / 2), Vector3.ZERO)
	var b := Transform3D(Basis.IDENTITY, Vector3(10, 0, 0))
	var ca = FlowDataScript.Data.newContainerOfType(D.Transform)
	ca.append(a)
	var d = H.data({"transform": [ca, D.Transform]})
	var s = _op(OpSettings.eOperation.Compose)
	s.use_constant_b = true
	s.constant_b = b
	var r = H.exec(OpNode, s, [d])
	assert_str(r.err).is_empty()
	var c : Transform3D = H.values(r.out, "r")[0]
	# A rotates (1,0,0) to (0,0,-1), then B translates it.
	assert_bool((c * Vector3.RIGHT).is_equal_approx(Vector3(10, 0, -1))).is_true()

func test_invert_lerp_and_vector_ops() -> void:
	var E = OpSettings.eOperation
	var made = _make(_points())
	made.registerStream("p", PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 1, 0)]), D.Vector)
	var inv = H.exec(OpNode, _op(E.Invert), [made])
	var xf : Transform3D = H.values(made, "transform")[1]
	assert_bool((H.values(inv.out, "r")[1] * xf).is_equal_approx(Transform3D.IDENTITY)).is_true()

	var tp = _op(E.TransformPosition)
	tp.in_nameB = "p"
	var moved = H.exec(OpNode, tp, [made])
	assert_int(H.dtype(moved.out, "r")).is_equal(D.Vector)
	assert_bool((H.values(moved.out, "r")[1] as Vector3).is_equal_approx(xf * Vector3(0, 1, 0))).is_true()

	var itp = _op(E.InverseTransformPosition)
	itp.in_nameB = "p"
	assert_bool((H.values(H.exec(OpNode, itp, [made]).out, "r")[1] as Vector3).is_equal_approx(xf.affine_inverse() * Vector3(0, 1, 0))).is_true()

	var td = _op(E.TransformDirection)
	td.in_nameB = "p"
	assert_bool((H.values(H.exec(OpNode, td, [made]).out, "r")[1] as Vector3).is_equal_approx(xf.basis * Vector3(0, 1, 0))).is_true()

	var lerp = _op(E.Lerp)
	lerp.use_constant_b = true
	lerp.constant_b = Transform3D(Basis.IDENTITY, Vector3(100, 0, 0))
	lerp.constant_c = 0.0
	var l0 = H.exec(OpNode, lerp, [made])
	assert_bool((H.values(l0.out, "r")[0] as Transform3D).is_equal_approx(H.values(made, "transform")[0])).is_true()
	lerp.constant_c = 1.0
	var l1 = H.exec(OpNode, lerp, [made])
	assert_bool((H.values(l1.out, "r")[0] as Transform3D).is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(100, 0, 0)))).is_true()

func test_apply_to_points_moves_points() -> void:
	var pts = _points()
	var c = FlowDataScript.Data.newContainerOfType(D.Transform)
	c.append(Transform3D(Basis.IDENTITY, Vector3(0, 10, 0)))
	pts.registerStream("offset", c, D.Transform)
	var s = _op(OpSettings.eOperation.ApplyToPoints)
	s.in_nameA = "offset"
	var r = H.exec(OpNode, s, [pts])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "position")).is_equal([Vector3(1, 12, 3), Vector3(-4, 10, 2)])
	for i in range(2):
		assert_bool((H.values(r.out, "size")[i] as Vector3).is_equal_approx(H.values(pts, "size")[i])).is_true()
		assert_bool((H.values(r.out, "rotation")[i] as Vector3).is_equal_approx(H.values(pts, "rotation")[i])).override_failure_message("rotation %d: %s" % [i, H.values(r.out, "rotation")[i]]).is_true()

func test_transform_op_needs_a_transform() -> void:
	var s = _op(OpSettings.eOperation.Invert)
	s.in_nameA = "position"
	assert_str(H.exec(OpNode, s, [_points()]).err).contains("Transform Op needs")
