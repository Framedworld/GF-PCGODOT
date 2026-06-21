# compose_vector_test.gd
class_name ComposeVectorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ComposeVectorNode = preload("res://addons/flow_nodes_editor/nodes/compose_vector.gd")
const ComposeVectorSettings = preload("res://addons/flow_nodes_editor/nodes/compose_vector_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> ComposeVectorNode:
	var node = ComposeVectorNode.new()
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

func test_compose_from_three_float_streams() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = "px"
	s.y_attribute = "py"
	s.z_attribute = "pz"
	s.out_attribute = "position"
	s.default_value = Vector3.ZERO

	var d = FlowDataScript.Data.new()
	d.registerStream("px", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	d.registerStream("py", PackedFloat32Array([4.0, 5.0, 6.0]), FlowDataScript.DataType.Float)
	d.registerStream("pz", PackedFloat32Array([7.0, 8.0, 9.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("position")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0].x).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(4.0, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(7.0, 0.001)
	assert_float(stream.container[2].x).is_equal_approx(3.0, 0.001)
	assert_float(stream.container[2].y).is_equal_approx(6.0, 0.001)
	assert_float(stream.container[2].z).is_equal_approx(9.0, 0.001)
	node.free()

func test_all_components_use_default_when_attributes_empty() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = ""
	s.y_attribute = ""
	s.z_attribute = ""
	s.out_attribute = "result"
	s.default_value = Vector3(2.0, 3.0, 4.0)

	var d = FlowDataScript.Data.new()
	d.registerStream("dummy", PackedFloat32Array([0.0, 0.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("result")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_float(stream.container[0].x).is_equal_approx(2.0, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(3.0, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(4.0, 0.001)
	node.free()

func test_mix_stream_and_default_components() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = "xvals"
	s.y_attribute = ""
	s.z_attribute = ""
	s.out_attribute = "mixed"
	s.default_value = Vector3(0.0, 5.0, 9.0)

	var d = FlowDataScript.Data.new()
	d.registerStream("xvals", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("mixed")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0].x).is_equal_approx(10.0, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(5.0, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(9.0, 0.001)
	assert_float(stream.container[1].x).is_equal_approx(20.0, 0.001)
	node.free()

func test_broadcast_scalar_stream_to_all_points() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = "sx"
	s.y_attribute = "sy"
	s.z_attribute = "sz"
	s.out_attribute = "bcast"
	s.default_value = Vector3.ZERO

	var d = FlowDataScript.Data.new()
	d.registerStream("_points", PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]), FlowDataScript.DataType.Vector)
	d.registerStream("sx", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	d.registerStream("sy", PackedFloat32Array([88.0]), FlowDataScript.DataType.Float)
	d.registerStream("sz", PackedFloat32Array([77.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("bcast")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	for i in range(3):
		assert_float(stream.container[i].x).is_equal_approx(99.0, 0.001)
		assert_float(stream.container[i].y).is_equal_approx(88.0, 0.001)
		assert_float(stream.container[i].z).is_equal_approx(77.0, 0.001)
	node.free()

func test_int_stream_accepted_as_component() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = "ix"
	s.y_attribute = ""
	s.z_attribute = ""
	s.out_attribute = "int_vec"
	s.default_value = Vector3.ZERO

	var d = FlowDataScript.Data.new()
	d.registerStream("ix", PackedInt32Array([3, 7, 11]), FlowDataScript.DataType.Int)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("int_vec")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0].x).is_equal_approx(3.0, 0.001)
	assert_float(stream.container[1].x).is_equal_approx(7.0, 0.001)
	assert_float(stream.container[2].x).is_equal_approx(11.0, 0.001)
	node.free()

func test_wrong_type_stream_returns_error() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = "vec_stream"
	s.y_attribute = ""
	s.z_attribute = ""
	s.out_attribute = "out"
	s.default_value = Vector3.ZERO

	var d = FlowDataScript.Data.new()
	d.registerStream("vec_stream", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_size_mismatch_stream_returns_error() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = "xv"
	s.y_attribute = "yv"
	s.z_attribute = ""
	s.out_attribute = "out"
	s.default_value = Vector3.ZERO

	var d = FlowDataScript.Data.new()
	d.registerStream("xv", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	d.registerStream("yv", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_input_returns_error() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = "x"
	s.y_attribute = "y"
	s.z_attribute = "z"
	s.out_attribute = "out"

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_default_out_attribute_is_size() -> void:
	var s = ComposeVectorSettings.new()
	s.x_attribute = ""
	s.y_attribute = ""
	s.z_attribute = ""
	s.default_value = Vector3(1.0, 1.0, 1.0)

	var d = FlowDataScript.Data.new()
	d.registerStream("dummy", PackedFloat32Array([0.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("size")
	assert_object(stream).is_not_null()
	node.free()
