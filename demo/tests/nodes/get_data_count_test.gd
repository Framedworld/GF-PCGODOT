# get_data_count_test.gd
class_name GetDataCountTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GetDataCountNode = preload("res://addons/flow_nodes_editor/nodes/get_data_count.gd")
# No separate settings file


func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d


func _make_settings(out_name: String = "count") -> SizeNodeSettings:
	var s := SizeNodeSettings.new()
	s.out_name = out_name
	return s


func _run(inputs: Array, settings) -> GetDataCountNode:
	var node = GetDataCountNode.new()
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
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]


func test_count_float_stream() -> void:
	var s := _make_settings("count")
	var node := _run([
		_make_data("pts", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([3]))


func test_count_vector_stream() -> void:
	var s := _make_settings("count")
	var node := _run([
		_make_data("pos", PackedVector3Array([Vector3.ONE, Vector3.ZERO, Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([4]))


func test_count_int_stream() -> void:
	var s := _make_settings("count")
	var node := _run([
		_make_data("ids", PackedInt32Array([10, 20, 30, 40, 50]), FlowDataScript.DataType.Int)
	], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([5]))


func test_count_color_stream() -> void:
	var s := _make_settings("count")
	var node := _run([
		_make_data("col", PackedColorArray([Color.RED, Color.GREEN]), FlowDataScript.DataType.Color)
	], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([2]))


func test_count_single_element() -> void:
	var s := _make_settings("count")
	var node := _run([
		_make_data("val", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([1]))


func test_count_large_array() -> void:
	var values := PackedFloat32Array()
	for i in range(1000):
		values.append(float(i))
	var s := _make_settings("count")
	var node := _run([
		_make_data("big", values, FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([1000]))


func test_custom_output_stream_name() -> void:
	var s := _make_settings("my_count")
	var node := _run([
		_make_data("pts", PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0, 6.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([6]))
	var missing = out.findStream("count")
	assert_object(missing).is_null()


func test_missing_input_error() -> void:
	var s := _make_settings("count")
	var node := _run([null], s)
	assert_str(node.err).is_not_empty()
