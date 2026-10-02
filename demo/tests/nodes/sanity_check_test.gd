# sanity_check_test.gd
class_name SanityCheckTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SanityCheckNode = preload("res://addons/flow_nodes_editor/nodes/sanity_check.gd")
const SanityCheckSettings = preload("res://addons/flow_nodes_editor/nodes/sanity_check_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, settings: SanityCheckNodeSettings) -> SanityCheckNode:
	var node = SanityCheckNode.new()
	node.name = "sanity_check_test_node"
	node.settings = settings
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: SanityCheckNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_passthrough_no_attribute_name() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = ""
	s.min_value = 0.0
	s.max_value = 1.0
	var data = _make_data("density", PackedFloat32Array([0.5, 1.5, -0.3]), FlowDataScript.DataType.Float)
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([0.5, 1.5, -0.3]))

func test_float_values_within_range() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "density"
	s.min_value = 0.0
	s.max_value = 1.0
	var data = _make_data("density", PackedFloat32Array([0.0, 0.5, 1.0]), FlowDataScript.DataType.Float)
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([0.0, 0.5, 1.0]))

func test_float_value_below_min_fails() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "density"
	s.min_value = 0.0
	s.max_value = 1.0
	var data = _make_data("density", PackedFloat32Array([0.5, -0.1, 0.8]), FlowDataScript.DataType.Float)
	var node = _run(data, s)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("outside range")

func test_float_value_above_max_fails() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "density"
	s.min_value = 0.0
	s.max_value = 1.0
	var data = _make_data("density", PackedFloat32Array([0.5, 1.001, 0.8]), FlowDataScript.DataType.Float)
	var node = _run(data, s)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("outside range")

func test_int_values_within_range() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "count"
	s.min_value = 0.0
	s.max_value = 10.0
	var data = _make_data("count", PackedInt32Array([0, 5, 10]), FlowDataScript.DataType.Int)
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([0, 5, 10]))

func test_int_value_out_of_range_fails() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "count"
	s.min_value = 0.0
	s.max_value = 10.0
	var data = _make_data("count", PackedInt32Array([0, 11, 5]), FlowDataScript.DataType.Int)
	var node = _run(data, s)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("outside range")

func test_attribute_not_found_fails() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "nonexistent"
	s.min_value = 0.0
	s.max_value = 1.0
	var data = _make_data("density", PackedFloat32Array([0.5]), FlowDataScript.DataType.Float)
	var node = _run(data, s)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("not found")

func test_non_numeric_attribute_fails() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "label"
	s.min_value = 0.0
	s.max_value = 1.0
	var data = _make_data("label", PackedStringArray(["hello", "world"]), FlowDataScript.DataType.String)
	var node = _run(data, s)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("not numeric")

func test_vector_attribute_fails_type_check() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "position"
	s.min_value = 0.0
	s.max_value = 10.0
	var data = _make_data("position", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	var node = _run(data, s)
	assert_str(node.err).is_not_empty()
	assert_str(node.err).contains("not numeric")

func test_missing_input_fails() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "density"
	s.min_value = 0.0
	s.max_value = 1.0
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()

func test_single_element_at_boundary() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "val"
	s.min_value = 5.0
	s.max_value = 5.0
	var data = _make_data("val", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

func test_custom_range_and_attribute_name() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = "temperature"
	s.min_value = -40.0
	s.max_value = 100.0
	var data = _make_data("temperature", PackedFloat32Array([-40.0, 0.0, 37.5, 100.0]), FlowDataScript.DataType.Float)
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("temperature")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([-40.0, 0.0, 37.5, 100.0]))

func test_passthrough_preserves_all_streams() -> void:
	var s = SanityCheckSettings.new()
	s.attribute_name = ""
	var d = FlowDataScript.Data.new()
	d.registerStream("density", PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)
	d.registerStream("position", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("position")).is_not_null()
