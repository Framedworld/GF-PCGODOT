# attribute_random_test.gd
class_name AttributeRandomTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const AttributeRandomNode = preload("res://addons/flow_nodes_editor/nodes/attribute_random.gd")
const AttributeRandomSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_random_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, settings: AttributeRandomNodeSettings) -> AttributeRandomNode:
	var node = AttributeRandomNode.new()
	node.name = "attr_random_test_node"
	node.settings = settings
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: AttributeRandomNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func _make_settings(attr_name: String = "my_attr", dtype: int = AttributeRandomSettings.eType.Float, min_val: float = 0.0, max_val: float = 1.0, use_index: bool = false) -> AttributeRandomSettings:
	var s = AttributeRandomSettings.new()
	s.attribute_name = attr_name
	s.data_type = dtype
	s.min_value = min_val
	s.max_value = max_val
	s.use_index_as_value = use_index
	s.random_seed = 12345
	return s

func test_float_random_output_correct_size() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("rand_f", AttributeRandomSettings.eType.Float, 0.0, 1.0)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("rand_f")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)

func test_float_random_values_in_range() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), Vector3(3,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("rf", AttributeRandomSettings.eType.Float, 2.0, 5.0)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("rf")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	for i in range(stream.container.size()):
		assert_float(stream.container[i]).is_greater_equal(2.0)
		assert_float(stream.container[i]).is_less_equal(5.0)

func test_int_random_values_in_range() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("ri", AttributeRandomSettings.eType.Int, 10.0, 20.0)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("ri")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	for i in range(stream.container.size()):
		assert_int(stream.container[i]).is_greater_equal(10)
		assert_int(stream.container[i]).is_less_equal(20)

func test_use_index_as_value_float() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), Vector3(3,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("idx_f", AttributeRandomSettings.eType.Float, 0.0, 1.0, true)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("idx_f")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([0.0, 1.0, 2.0, 3.0]))

func test_use_index_as_value_int() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("idx_i", AttributeRandomSettings.eType.Int, 0.0, 1.0, true)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("idx_i")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([0, 1, 2]))

func test_min_max_swapped_still_works() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("swap", AttributeRandomSettings.eType.Float, 5.0, 2.0)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("swap")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	for i in range(stream.container.size()):
		assert_float(stream.container[i]).is_greater_equal(2.0)
		assert_float(stream.container[i]).is_less_equal(5.0)

func test_deterministic_with_seed_stream() -> void:
	var pos = PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)])
	var seeds = PackedInt32Array([111, 222, 333])
	var in_data = FlowDataScript.Data.new()
	in_data.registerStream("pos", pos, FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowData.AttrSeed, seeds, FlowDataScript.DataType.Int)
	var s = _make_settings("det_f", AttributeRandomSettings.eType.Float, 0.0, 1.0)
	s.random_seed = 99999
	var node1 = _run(in_data, s)
	assert_str(node1.err).is_empty()
	var out1 = _output(node1)
	var stream1 = out1.findStream("det_f")
	var result1 := PackedFloat32Array(stream1.container)

	var in_data2 = FlowDataScript.Data.new()
	in_data2.registerStream("pos", pos, FlowDataScript.DataType.Vector)
	in_data2.registerStream(FlowData.AttrSeed, seeds, FlowDataScript.DataType.Int)
	var s2 = _make_settings("det_f", AttributeRandomSettings.eType.Float, 0.0, 1.0)
	s2.random_seed = 99999
	var node2 = _run(in_data2, s2)
	assert_str(node2.err).is_empty()
	var out2 = _output(node2)
	var stream2 = out2.findStream("det_f")
	assert_array(stream2.container).is_equal(result1)

func test_empty_attribute_name_error() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("", AttributeRandomSettings.eType.Float, 0.0, 1.0)
	var node = _run(in_data, s)
	assert_str(node.err).is_not_empty()

func test_missing_input_error() -> void:
	var s = _make_settings("rf", AttributeRandomSettings.eType.Float, 0.0, 1.0)
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()

func test_single_point_float() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(5,5,5)]), FlowDataScript.DataType.Vector)
	var s = _make_settings("single", AttributeRandomSettings.eType.Float, -1.0, 1.0)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("single")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_greater_equal(-1.0)
	assert_float(stream.container[0]).is_less_equal(1.0)

func test_preserves_existing_streams() -> void:
	var in_data = FlowDataScript.Data.new()
	in_data.registerStream("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,1,1)]), FlowDataScript.DataType.Vector)
	in_data.registerStream("weight", PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)
	var s = _make_settings("new_attr", AttributeRandomSettings.eType.Float, 0.0, 1.0)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("pos")
	assert_object(pos_stream).is_not_null()
	var weight_stream = out.findStream("weight")
	assert_object(weight_stream).is_not_null()
	var new_stream = out.findStream("new_attr")
	assert_object(new_stream).is_not_null()
	assert_int(new_stream.container.size()).is_equal(2)
