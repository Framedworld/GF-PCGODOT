# attribute_filter_range_test.gd
class_name AttributeFilterRangeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const AttributeFilterRangeNode = preload("res://addons/flow_nodes_editor/nodes/attribute_filter_range.gd")
const AttributeFilterRangeSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_filter_range_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> AttributeFilterRangeNode:
	var node = AttributeFilterRangeNode.new()
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

func _output(node, port: int = 0) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	if port >= bulk.size(): return null
	return bulk[port]

func test_float_range_splits_inside_outside() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "val"
	s.min_value = 0.0
	s.max_value = 5.0
	s.inclusive_min = true
	s.inclusive_max = true
	var d = _make_data("val", PackedFloat32Array([1.0, 3.0, 5.0, 7.0, 10.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	var inside_stream = inside.findStream("val")
	var outside_stream = outside.findStream("val")
	assert_object(inside_stream).is_not_null()
	assert_object(outside_stream).is_not_null()
	assert_int(inside_stream.container.size()).is_equal(3)
	assert_int(outside_stream.container.size()).is_equal(2)
	node.free()

func test_exclusive_min_max_boundaries() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "v"
	s.min_value = 0.0
	s.max_value = 5.0
	s.inclusive_min = false
	s.inclusive_max = false
	var d = _make_data("v", PackedFloat32Array([0.0, 2.5, 5.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("v")
	var outside_stream = outside.findStream("v")
	assert_int(inside_stream.container.size()).is_equal(1)
	assert_int(outside_stream.container.size()).is_equal(2)
	node.free()

func test_int_stream_filter() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "score"
	s.min_value = 10.0
	s.max_value = 50.0
	s.inclusive_min = true
	s.inclusive_max = true
	var d = _make_data("score", PackedInt32Array([5, 10, 25, 50, 100]), FlowDataScript.DataType.Int)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("score")
	var outside_stream = outside.findStream("score")
	assert_int(inside_stream.container.size()).is_equal(3)
	assert_int(outside_stream.container.size()).is_equal(2)
	node.free()

func test_vector_stream_filters_by_length() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "pos"
	s.min_value = 0.0
	s.max_value = 2.0
	s.inclusive_min = true
	s.inclusive_max = true
	var short_v = Vector3(1.0, 0.0, 0.0)
	var long_v = Vector3(10.0, 10.0, 10.0)
	var arr = PackedVector3Array([short_v, long_v])
	var d = _make_data("pos", arr, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("pos")
	var outside_stream = outside.findStream("pos")
	assert_int(inside_stream.container.size()).is_equal(1)
	assert_int(outside_stream.container.size()).is_equal(1)
	node.free()

func test_absolute_value_mode() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "n"
	s.min_value = 1.0
	s.max_value = 5.0
	s.inclusive_min = true
	s.inclusive_max = true
	s.use_absolute_value = true
	var d = _make_data("n", PackedFloat32Array([-3.0, 2.0, -6.0, 4.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("n")
	var outside_stream = outside.findStream("n")
	assert_int(inside_stream.container.size()).is_equal(3)
	assert_int(outside_stream.container.size()).is_equal(1)
	node.free()

func test_string_match_mode() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "tag"
	s.string_match_mode = true
	s.string_match_values = "red, blue"
	s.case_sensitive = false
	var values: Array[String] = ["red", "green", "Blue", "yellow", "RED"]
	var packed = PackedStringArray(values)
	var d = _make_data("tag", packed, FlowDataScript.DataType.String)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("tag")
	var outside_stream = outside.findStream("tag")
	assert_int(inside_stream.container.size()).is_equal(3)
	assert_int(outside_stream.container.size()).is_equal(2)
	node.free()

func test_string_match_case_sensitive() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "tag"
	s.string_match_mode = true
	s.string_match_values = "red"
	s.case_sensitive = true
	var packed = PackedStringArray(["red", "Red", "RED"])
	var d = _make_data("tag", packed, FlowDataScript.DataType.String)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("tag")
	var outside_stream = outside.findStream("tag")
	assert_int(inside_stream.container.size()).is_equal(1)
	assert_int(outside_stream.container.size()).is_equal(2)
	node.free()

func test_empty_input_data_produces_empty_outputs() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "val"
	s.min_value = 0.0
	s.max_value = 1.0
	var d = FlowDataScript.Data.new()
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	assert_int(inside.size()).is_equal(0)
	assert_int(outside.size()).is_equal(0)
	node.free()

func test_missing_input_sets_error() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "val"
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_attribute_name_sets_error() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = ""
	var d = _make_data("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_attribute_not_found_sets_error() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "nonexistent"
	var d = _make_data("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_string_match_no_values_sets_error() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "tag"
	s.string_match_mode = true
	s.string_match_values = ""
	var packed = PackedStringArray(["red", "blue"])
	var d = _make_data("tag", packed, FlowDataScript.DataType.String)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_inverted_min_max_normalizes_correctly() -> void:
	var s = AttributeFilterRangeSettings.new()
	s.attribute_name = "v"
	s.min_value = 5.0
	s.max_value = 0.0
	s.inclusive_min = true
	s.inclusive_max = true
	var d = _make_data("v", PackedFloat32Array([2.0, 7.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("v")
	var outside_stream = outside.findStream("v")
	assert_int(inside_stream.container.size()).is_equal(1)
	assert_int(outside_stream.container.size()).is_equal(1)
	node.free()
