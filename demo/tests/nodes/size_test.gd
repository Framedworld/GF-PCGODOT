# size_test.gd
class_name SizeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SizeNode = preload("res://addons/flow_nodes_editor/nodes/size.gd")
const SizeSettings = preload("res://addons/flow_nodes_editor/nodes/size_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, out_name: String = "count") -> SizeNode:
	var node = SizeNode.new()
	node.name = "size_test_node"
	node.settings = SizeSettings.new()
	node.settings.out_name = out_name
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = input
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: SizeNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_float_stream_returns_correct_size() -> void:
	# Not "position": canonical attributes only register with their own type.
	var input = _make_data("value", PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0]), FlowDataScript.DataType.Float)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Int)
	assert_array(stream.container).is_equal(PackedInt32Array([5]))

func test_vector_stream_returns_correct_size() -> void:
	var input = _make_data("position", PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]), FlowDataScript.DataType.Vector)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([3]))

func test_int_stream_returns_correct_size() -> void:
	var input = _make_data("id", PackedInt32Array([10, 20, 30, 40]), FlowDataScript.DataType.Int)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([4]))

func test_color_stream_returns_correct_size() -> void:
	var input = _make_data("color", PackedColorArray([Color(1, 0, 0), Color(0, 1, 0)]), FlowDataScript.DataType.Color)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([2]))

func test_single_element_input() -> void:
	var input = _make_data("value", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([1]))

func test_large_array_size() -> void:
	var values = PackedFloat32Array()
	values.resize(500)
	var input = _make_data("value", values, FlowDataScript.DataType.Float)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([500]))

func test_custom_output_stream_name() -> void:
	var input = _make_data("value", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run(input, "point_count")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("point_count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([3]))

func test_output_stream_is_int_type() -> void:
	var input = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Int)
	assert_int(stream.container.size()).is_equal(1)

func test_missing_input_sets_error() -> void:
	var node = SizeNode.new()
	node.name = "size_test_node"
	node.settings = SizeSettings.new()
	node.settings.out_name = "count"
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_not_empty()
	dummy.free()
