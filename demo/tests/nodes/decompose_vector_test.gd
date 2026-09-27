# decompose_vector_test.gd
class_name DecomposeVectorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DecomposeVectorNode = preload("res://addons/flow_nodes_editor/nodes/decompose_vector.gd")
const DecomposeVectorSettings = preload("res://addons/flow_nodes_editor/nodes/decompose_vector_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> DecomposeVectorNode:
	var node = DecomposeVectorNode.new()
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

func test_decompose_basic_vectors() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "position"
	s.x_attribute = "x"
	s.y_attribute = "y"
	s.z_attribute = "z"
	var vecs = PackedVector3Array([Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0)])
	var node = _run([_make_data("position", vecs, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sx = out.findStream("x")
	var sy = out.findStream("y")
	var sz = out.findStream("z")
	assert_object(sx).is_not_null()
	assert_object(sy).is_not_null()
	assert_object(sz).is_not_null()
	assert_array(sx.container).is_equal(PackedFloat32Array([1.0, 4.0]))
	assert_array(sy.container).is_equal(PackedFloat32Array([2.0, 5.0]))
	assert_array(sz.container).is_equal(PackedFloat32Array([3.0, 6.0]))
	node.free()

func test_decompose_single_vector() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "pos"
	s.x_attribute = "px"
	s.y_attribute = "py"
	s.z_attribute = "pz"
	var vecs = PackedVector3Array([Vector3(-1.5, 0.0, 100.0)])
	var node = _run([_make_data("pos", vecs, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_array(out.findStream("px").container).is_equal(PackedFloat32Array([-1.5]))
	assert_array(out.findStream("py").container).is_equal(PackedFloat32Array([0.0]))
	assert_array(out.findStream("pz").container).is_equal(PackedFloat32Array([100.0]))
	node.free()

func test_decompose_preserves_existing_streams() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "vel"
	s.x_attribute = "vx"
	s.y_attribute = "vy"
	s.z_attribute = "vz"
	var d := FlowDataScript.Data.new()
	d.registerStream("vel", PackedVector3Array([Vector3(1.0, 2.0, 3.0)]), FlowDataScript.DataType.Vector)
	d.registerStream("mass", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("mass")).is_not_null()
	assert_object(out.findStream("vx")).is_not_null()
	node.free()

func test_skip_empty_output_attribute_names() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "position"
	s.x_attribute = "x"
	s.y_attribute = ""
	s.z_attribute = "z"
	var vecs = PackedVector3Array([Vector3(1.0, 2.0, 3.0)])
	var node = _run([_make_data("position", vecs, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("x")).is_not_null()
	assert_object(out.findStream("y")).is_null()
	assert_object(out.findStream("z")).is_not_null()
	node.free()

func test_skip_all_empty_output_attribute_names() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "position"
	s.x_attribute = ""
	s.y_attribute = ""
	s.z_attribute = ""
	var vecs = PackedVector3Array([Vector3(1.0, 2.0, 3.0)])
	var node = _run([_make_data("position", vecs, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("x")).is_null()
	assert_object(out.findStream("y")).is_null()
	assert_object(out.findStream("z")).is_null()
	node.free()

func test_missing_input_connection_error() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "position"
	s.x_attribute = "x"
	s.y_attribute = "y"
	s.z_attribute = "z"
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_stream_not_found_error() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "nonexistent"
	s.x_attribute = "x"
	s.y_attribute = "y"
	s.z_attribute = "z"
	var vecs = PackedVector3Array([Vector3(1.0, 2.0, 3.0)])
	var node = _run([_make_data("position", vecs, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_wrong_type_error() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "vec"
	s.x_attribute = "x"
	s.y_attribute = "y"
	s.z_attribute = "z"
	var node = _run([_make_data("vec", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_decompose_large_array() -> void:
	var s = DecomposeVectorSettings.new()
	s.in_attribute = "p"
	s.x_attribute = "x"
	s.y_attribute = "y"
	s.z_attribute = "z"
	var vecs = PackedVector3Array()
	var expected_x = PackedFloat32Array()
	var expected_y = PackedFloat32Array()
	var expected_z = PackedFloat32Array()
	for i in range(1000):
		vecs.append(Vector3(float(i), float(i) * 2.0, float(i) * 3.0))
		expected_x.append(float(i))
		expected_y.append(float(i) * 2.0)
		expected_z.append(float(i) * 3.0)
	var node = _run([_make_data("p", vecs, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_array(out.findStream("x").container).is_equal(expected_x)
	assert_array(out.findStream("y").container).is_equal(expected_y)
	assert_array(out.findStream("z").container).is_equal(expected_z)
	node.free()
