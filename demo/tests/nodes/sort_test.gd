# sort_test.gd
class_name SortTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SortNode = preload("res://addons/flow_nodes_editor/nodes/sort.gd")
const SortSettings = preload("res://addons/flow_nodes_editor/nodes/sort_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, sort_by: String, descending: bool = false) -> SortNode:
	var node = SortNode.new()
	node.name = "test_sort_node"
	var s = SortNodeSettings.new()
	s.sort_by = sort_by
	s.sort_descending = descending
	node.settings = s
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: SortNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_sort_floats_ascending() -> void:
	var d = _make_data("value", PackedFloat32Array([3.0, 1.0, 4.0, 1.5, 2.0]), FlowDataScript.DataType.Float)
	d.registerStream("label", PackedFloat32Array([30.0, 10.0, 40.0, 15.0, 20.0]), FlowDataScript.DataType.Float)
	var node = _run(d, "value", false)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 1.5, 2.0, 3.0, 4.0]))
	var label_stream = out.findStream("label")
	assert_object(label_stream).is_not_null()
	assert_array(label_stream.container).is_equal(PackedFloat32Array([10.0, 15.0, 20.0, 30.0, 40.0]))

func test_sort_floats_descending() -> void:
	var d = _make_data("value", PackedFloat32Array([3.0, 1.0, 4.0, 1.5, 2.0]), FlowDataScript.DataType.Float)
	var node = _run(d, "value", true)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([4.0, 3.0, 2.0, 1.5, 1.0]))

func test_sort_ints_ascending() -> void:
	var d = _make_data("idx", PackedInt32Array([5, 2, 8, 1, 3]), FlowDataScript.DataType.Int)
	var node = _run(d, "idx", false)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("idx")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([1, 2, 3, 5, 8]))

func test_sort_ints_descending() -> void:
	var d = _make_data("idx", PackedInt32Array([5, 2, 8, 1, 3]), FlowDataScript.DataType.Int)
	var node = _run(d, "idx", true)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("idx")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([8, 5, 3, 2, 1]))

func test_sort_strings_ascending() -> void:
	var d = _make_data("name", PackedStringArray(["banana", "apple", "cherry", "avocado"]), FlowDataScript.DataType.String)
	var node = _run(d, "name", false)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("name")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedStringArray(["apple", "avocado", "banana", "cherry"]))

func test_sort_strings_descending() -> void:
	var d = _make_data("name", PackedStringArray(["banana", "apple", "cherry", "avocado"]), FlowDataScript.DataType.String)
	var node = _run(d, "name", true)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("name")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedStringArray(["cherry", "banana", "avocado", "apple"]))

func test_single_element() -> void:
	var d = _make_data("value", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	var node = _run(d, "value", false)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([42.0]))

func test_empty_array() -> void:
	var d = _make_data("value", PackedFloat32Array([]), FlowDataScript.DataType.Float)
	var node = _run(d, "value", false)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([]))

func test_error_missing_input() -> void:
	var node = _run(null, "value", false)
	assert_str(node.err).is_not_empty()

func test_error_stream_not_found() -> void:
	var d = _make_data("value", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run(d, "nonexistent_stream", false)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("nonexistent_stream")

func test_error_unsupported_type() -> void:
	var d = _make_data("pos", PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 1, 0)]), FlowDataScript.DataType.Vector)
	var node = _run(d, "pos", false)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("Unsupported sort data type")

func test_all_streams_reordered() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("priority", PackedInt32Array([3, 1, 2]), FlowDataScript.DataType.Int)
	d.registerStream("label", PackedStringArray(["c", "a", "b"]), FlowDataScript.DataType.String)
	d.registerStream("weight", PackedFloat32Array([30.0, 10.0, 20.0]), FlowDataScript.DataType.Float)
	var node = _run(d, "priority", false)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_array(out.findStream("priority").container).is_equal(PackedInt32Array([1, 2, 3]))
	assert_array(out.findStream("label").container).is_equal(PackedStringArray(["a", "b", "c"]))
	assert_array(out.findStream("weight").container).is_equal(PackedFloat32Array([10.0, 20.0, 30.0]))
