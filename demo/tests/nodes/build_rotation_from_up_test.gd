# build_rotation_from_up_test.gd
class_name BuildRotationFromUpTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const BuildRotationFromUpNode = preload("res://addons/flow_nodes_editor/nodes/build_rotation_from_up.gd")
const BuildRotationFromUpSettings = preload("res://addons/flow_nodes_editor/nodes/build_rotation_from_up_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _make_point_data(count: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var positions := PackedVector3Array()
	for i in count:
		positions.append(Vector3(float(i), 0.0, 0.0))
	d.registerStream(FlowDataScript.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _make_point_data_with_normal(count: int, normals: PackedVector3Array) -> FlowData.Data:
	var d := _make_point_data(count)
	d.registerStream("normal", normals, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> BuildRotationFromUpNode:
	var node = BuildRotationFromUpNode.new()
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

func test_constant_up_vector_z_axis() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = true
	s.up_vector_constant = Vector3.UP
	s.axis = "z"

	var in_data := _make_point_data(3)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(3)

func test_constant_up_vector_x_axis() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = true
	s.up_vector_constant = Vector3(0.0, 1.0, 0.0)
	s.axis = "x"

	var in_data := _make_point_data(2)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(2)

func test_constant_up_vector_y_axis() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = true
	s.up_vector_constant = Vector3(1.0, 0.0, 0.0)
	s.axis = "y"

	var in_data := _make_point_data(4)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(4)

func test_attribute_up_vector_per_point() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = false
	s.up_vector_attribute = "normal"
	s.axis = "z"

	var normals := PackedVector3Array([
		Vector3(0.0, 1.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
	])
	var in_data := _make_point_data_with_normal(3, normals)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(3)

func test_attribute_broadcast_single_normal() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = false
	s.up_vector_attribute = "normal"
	s.axis = "z"

	var in_data := _make_point_data(5)
	var single_normal := PackedVector3Array([Vector3(0.0, 1.0, 0.0)])
	in_data.registerStream("normal", single_normal, FlowDataScript.DataType.Vector)

	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(5)

func test_existing_rotation_stream_is_overwritten() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = true
	s.up_vector_constant = Vector3.UP
	s.axis = "z"

	var in_data := _make_point_data(2)
	var old_rots := PackedVector3Array([Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0)])
	in_data.registerStream(FlowDataScript.AttrRotation, old_rots, FlowDataScript.DataType.Vector)

	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(2)

func test_missing_input_error() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = true
	s.axis = "z"

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_invalid_axis_error() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = true
	s.up_vector_constant = Vector3.UP
	s.axis = "w"

	var in_data := _make_point_data(2)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()

func test_missing_attribute_error() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = false
	s.up_vector_attribute = "nonexistent_attr"
	s.axis = "z"

	var in_data := _make_point_data(3)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()

func test_wrong_attribute_type_error() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = false
	s.up_vector_attribute = "up_f"
	s.axis = "z"

	var in_data := _make_point_data(2)
	var float_vals := PackedFloat32Array([1.0, 2.0])
	in_data.registerStream("up_f", float_vals, FlowDataScript.DataType.Float)

	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()

func test_attribute_size_mismatch_error() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = false
	s.up_vector_attribute = "normal"
	s.axis = "z"

	var in_data := _make_point_data(4)
	var wrong_normals := PackedVector3Array([Vector3.UP, Vector3.RIGHT])
	in_data.registerStream("normal", wrong_normals, FlowDataScript.DataType.Vector)

	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()

func test_single_point_constant() -> void:
	var s = BuildRotationFromUpSettings.new()
	s.use_constant = true
	s.up_vector_constant = Vector3(0.0, 0.0, 1.0)
	s.axis = "z"

	var in_data := _make_point_data(1)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(1)
