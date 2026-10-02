# get_points_count_test.gd
class_name GetPointsCountTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GetPointsCountNode = preload("res://addons/flow_nodes_editor/nodes/get_points_count.gd")
# No separate settings file — uses SizeNodeSettings loaded by the node itself

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, out_name: String = "count") -> GetPointsCountNode:
	var node = GetPointsCountNode.new()
	node.name = "get_points_count_test_node"
	node.settings = SizeNodeSettings.new()
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

func _output(node: GetPointsCountNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_float_stream_returns_correct_count() -> void:
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

func test_vector_stream_returns_correct_count() -> void:
	var input = _make_data("position", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)]), FlowDataScript.DataType.Vector)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([3]))

func test_int_stream_returns_correct_count() -> void:
	var input = _make_data("value", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([3]))

func test_color_stream_returns_correct_count() -> void:
	var input = _make_data("color", PackedColorArray([Color(1, 0, 0), Color(0, 1, 0)]), FlowDataScript.DataType.Color)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([2]))

func test_single_element_input() -> void:
	var input = _make_data("value", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([1]))

func test_large_array_count() -> void:
	var values = PackedFloat32Array()
	values.resize(1000)
	var input = _make_data("value", values, FlowDataScript.DataType.Float)
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([1000]))

func test_custom_output_stream_name() -> void:
	var input = _make_data("value", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run(input, "my_count")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([3]))

func test_missing_input_sets_error() -> void:
	var node = GetPointsCountNode.new()
	node.name = "get_points_count_test_node"
	node.settings = SizeNodeSettings.new()
	node.settings.out_name = "count"
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_not_empty()
	dummy.free()
