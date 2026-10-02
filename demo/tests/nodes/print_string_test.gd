# print_string_test.gd
class_name PrintStringTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PrintStringNode = preload("res://addons/flow_nodes_editor/nodes/print_string.gd")
const PrintStringSettings = preload("res://addons/flow_nodes_editor/nodes/print_string_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, prefix: String = "Log:", attr: String = "") -> PrintStringNode:
	var node = PrintStringNode.new()
	node.name = "test_node"
	var s = PrintStringSettings.new()
	s.prefix_message = prefix
	s.attribute_to_print = attr
	node.settings = s
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: PrintStringNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_passthrough_no_attribute_floats() -> void:
	var d = _make_data("P", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("P")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))

func test_passthrough_with_attribute_floats() -> void:
	var d = _make_data("density", PackedFloat32Array([0.1, 0.5, 0.9]), FlowDataScript.DataType.Float)
	var node = _run(d, "Debug:", "density")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([0.1, 0.5, 0.9]))

func test_passthrough_with_attribute_vectors() -> void:
	var d = _make_data("normal", PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 0, 0)]), FlowDataScript.DataType.Vector)
	var node = _run(d, "Log:", "normal")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("normal")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 0, 0)]))

func test_passthrough_with_attribute_ints() -> void:
	var d = _make_data("id", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run(d, "Info:", "id")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("id")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([10, 20, 30]))

func test_passthrough_with_attribute_colors() -> void:
	var d = _make_data("color", PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)]), FlowDataScript.DataType.Color)
	var node = _run(d, "Log:", "color")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)]))

func test_missing_stream_still_passes_through() -> void:
	var d = _make_data("P", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run(d, "Log:", "nonexistent_attr")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("P")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0]))

func test_large_stream_truncated_print_still_passes_through() -> void:
	var values = PackedFloat32Array()
	values.resize(150)
	for i in range(150):
		values[i] = float(i)
	var d = _make_data("big", values, FlowDataScript.DataType.Float)
	var node = _run(d, "Log:", "big")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("big")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(150)

func test_single_element_stream() -> void:
	var d = _make_data("val", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	var node = _run(d, "Log:", "val")
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("val")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([42.0]))

func test_missing_input_sets_error() -> void:
	var node = PrintStringNode.new()
	node.name = "test_node"
	var s = PrintStringSettings.new()
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_not_empty()
	dummy.free()
