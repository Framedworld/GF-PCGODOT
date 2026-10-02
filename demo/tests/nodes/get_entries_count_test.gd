# get_entries_count_test.gd
class_name GetEntriesCountTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GetEntriesCountNode = preload("res://addons/flow_nodes_editor/nodes/get_entries_count.gd")
const SizeNodeSettings = preload("res://addons/flow_nodes_editor/nodes/size_settings.gd")


func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d


func _run(inputs: Array, settings) -> GetEntriesCountNode:
	var node = GetEntriesCountNode.new()
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


func test_count_float_stream() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "count"
	var values = PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var node = _run([_make_data("pts", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_int(stream.container[0]).is_equal(5)


func test_count_vector_stream() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "count"
	var values = PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)])
	var node = _run([_make_data("pts", values, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.container[0]).is_equal(3)


func test_count_int_stream() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "count"
	var values = PackedInt32Array([10, 20, 30, 40, 50, 60, 70])
	var node = _run([_make_data("vals", values, FlowDataScript.DataType.Int)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.container[0]).is_equal(7)


func test_count_color_stream() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "count"
	var values = PackedColorArray([Color.RED, Color.GREEN])
	var node = _run([_make_data("colors", values, FlowDataScript.DataType.Color)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.container[0]).is_equal(2)


func test_single_element_input() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "count"
	var values = PackedFloat32Array([42.0])
	var node = _run([_make_data("single", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.container[0]).is_equal(1)


func test_custom_output_stream_name() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "my_count"
	var values = PackedFloat32Array([1.0, 2.0, 3.0])
	var node = _run([_make_data("pts", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var default_stream = out.findStream("count")
	assert_object(default_stream).is_null()
	var custom_stream = out.findStream("my_count")
	assert_object(custom_stream).is_not_null()
	assert_int(custom_stream.container[0]).is_equal(3)


func test_output_is_int_type() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "count"
	var values = PackedFloat32Array([1.0, 2.0, 3.0, 4.0])
	var node = _run([_make_data("pts", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Int)
	assert_bool(stream.container is PackedInt32Array).is_true()


func test_missing_input_sets_error() -> void:
	var s = SizeNodeSettings.new()
	s.out_name = "count"
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
