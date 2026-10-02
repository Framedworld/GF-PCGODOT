# output_test.gd
class_name OutputTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const OutputNode = preload("res://addons/flow_nodes_editor/nodes/output.gd")
const OutputSettings = preload("res://addons/flow_nodes_editor/nodes/output_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> OutputNode:
	var node = OutputNode.new()
	node.name = "test_output_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: OutputNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func _make_settings(out_name: String = "out_val", dtype: int = FlowData.DataType.Float) -> OutputSettings:
	var s = OutputSettings.new()
	s.name = out_name
	s.data_type = dtype
	return s

func test_float_passthrough_with_named_output() -> void:
	var s = _make_settings("my_output", FlowDataScript.DataType.Float)
	var in_data = _make_data("positions", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var original_stream = out.findStream("positions")
	assert_object(original_stream).is_not_null()
	assert_array(original_stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))
	var named_stream = out.findStream("my_output")
	assert_object(named_stream).is_not_null()
	assert_array(named_stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))

func test_vector_passthrough_with_named_output() -> void:
	var s = _make_settings("my_vectors", FlowDataScript.DataType.Vector)
	var in_data = _make_data("pts", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var original_stream = out.findStream("pts")
	assert_object(original_stream).is_not_null()
	assert_array(original_stream.container).is_equal(PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]))
	var named_stream = out.findStream("my_vectors")
	assert_object(named_stream).is_not_null()
	assert_array(named_stream.container).is_equal(PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]))

func test_int_passthrough_with_named_output() -> void:
	var s = _make_settings("int_result", FlowDataScript.DataType.Int)
	var in_data = _make_data("ids", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var original_stream = out.findStream("ids")
	assert_object(original_stream).is_not_null()
	assert_array(original_stream.container).is_equal(PackedInt32Array([10, 20, 30]))
	var named_stream = out.findStream("int_result")
	assert_object(named_stream).is_not_null()
	assert_array(named_stream.container).is_equal(PackedInt32Array([10, 20, 30]))

func test_color_passthrough_with_named_output() -> void:
	var s = _make_settings("colors_out", FlowDataScript.DataType.Color)
	var in_data = _make_data("col", PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)]), FlowDataScript.DataType.Color)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var original_stream = out.findStream("col")
	assert_object(original_stream).is_not_null()
	assert_array(original_stream.container).is_equal(PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)]))
	var named_stream = out.findStream("colors_out")
	assert_object(named_stream).is_not_null()
	assert_array(named_stream.container).is_equal(PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)]))

func test_named_output_not_duplicated_when_stream_name_matches_settings_name() -> void:
	var s = _make_settings("out_stream", FlowDataScript.DataType.Float)
	var in_data = _make_data("out_stream", PackedFloat32Array([5.0, 6.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var named_stream = out.findStream("out_stream")
	assert_object(named_stream).is_not_null()
	assert_array(named_stream.container).is_equal(PackedFloat32Array([5.0, 6.0]))

func test_multiple_streams_all_copied() -> void:
	var s = _make_settings("result", FlowDataScript.DataType.Float)
	var in_data = FlowDataScript.Data.new()
	in_data.registerStream("floats", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	in_data.registerStream("ints", PackedInt32Array([3, 4]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var float_stream = out.findStream("floats")
	assert_object(float_stream).is_not_null()
	assert_array(float_stream.container).is_equal(PackedFloat32Array([1.0, 2.0]))
	var int_stream = out.findStream("ints")
	assert_object(int_stream).is_not_null()
	assert_array(int_stream.container).is_equal(PackedInt32Array([3, 4]))

func test_no_input_connected_produces_no_output() -> void:
	var s = _make_settings("out_val", FlowDataScript.DataType.Float)
	var node = _run([null], s)
	var out = _output(node)
	assert_object(out).is_null()

func test_single_element_array_passthrough() -> void:
	var s = _make_settings("single_out", FlowDataScript.DataType.Float)
	var in_data = _make_data("val", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var named_stream = out.findStream("single_out")
	assert_object(named_stream).is_not_null()
	assert_array(named_stream.container).is_equal(PackedFloat32Array([42.0]))
