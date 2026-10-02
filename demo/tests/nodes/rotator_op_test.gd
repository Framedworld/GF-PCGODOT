# rotator_op_test.gd
class_name RotatorOpTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const RotatorOpNode = preload("res://addons/flow_nodes_editor/nodes/rotator_op.gd")
const RotatorOpSettings = preload("res://addons/flow_nodes_editor/nodes/rotator_op_settings.gd")

func _make_euler_data(eulers: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrRotation, eulers, FlowDataScript.DataType.Vector)
	return d

func _make_quat_data(quats: PackedVector4Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrRotationQuat, quats, FlowDataScript.DataType.Quaternion)
	return d

func _run(inputs: Array, settings) -> RotatorOpNode:
	var node = RotatorOpNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_combine_euler_identity() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Combine
	s.operand_euler = Vector3.ZERO
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var eulers = PackedVector3Array([Vector3(0.0, 0.5, 0.0), Vector3(0.0, 0.0, 0.3)])
	var node = _run([_make_euler_data(eulers)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)

func test_invert_euler() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Invert
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var eulers = PackedVector3Array([Vector3(0.0, PI / 2.0, 0.0)])
	var node = _run([_make_euler_data(eulers)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)

func test_lerp_euler_half_alpha() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Lerp
	s.operand_euler = Vector3(0.0, PI, 0.0)
	s.alpha = 0.5
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var eulers = PackedVector3Array([Vector3.ZERO])
	var node = _run([_make_euler_data(eulers)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)

func test_rotate_around_axis_y() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.RotateAroundAxis
	s.axis = Vector3.UP
	s.angle_degrees = 90.0
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var eulers = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, 0.5)])
	var node = _run([_make_euler_data(eulers)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)

func test_output_quaternion_representation() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Invert
	s.representation = RotatorOpSettings.eRepresentation.Quaternion
	var eulers = PackedVector3Array([Vector3(0.0, PI / 4.0, 0.0)])
	var node = _run([_make_euler_data(eulers)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var qstream = out.findStream(FlowDataScript.AttrRotationQuat)
	assert_object(qstream).is_not_null()
	var euler_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(euler_stream).is_null()

func test_input_from_quaternion_stream() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Invert
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var q = Quaternion(Vector3.UP, PI / 2.0)
	var quats = PackedVector4Array([Vector4(q.x, q.y, q.z, q.w)])
	var node = _run([_make_quat_data(quats)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)

func test_empty_input_produces_empty_output() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Combine
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var empty_data = FlowDataScript.Data.new()
	var node = _run([empty_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

func test_missing_rotation_stream_sets_error() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Combine
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var d = FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_rotate_around_zero_axis_sets_error() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.RotateAroundAxis
	s.axis = Vector3.ZERO
	s.angle_degrees = 45.0
	s.representation = RotatorOpSettings.eRepresentation.Euler
	var eulers = PackedVector3Array([Vector3.ZERO])
	var node = _run([_make_euler_data(eulers)], s)
	assert_str(node.err).is_not_empty()

func test_missing_input_sets_error() -> void:
	var s = RotatorOpSettings.new()
	s.operation = RotatorOpSettings.eOperation.Combine
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
