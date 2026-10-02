# attribute_rename_test.gd
class_name AttributeRenameTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const AttributeRenameNode = preload("res://addons/flow_nodes_editor/nodes/attribute_rename.gd")
const AttributeRenameSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_rename_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> AttributeRenameNode:
	var node = AttributeRenameNode.new()
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

func test_rename_float_stream() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "temperature"
	s.to_name = "heat"
	var d = _make_data("temperature", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("heat")).is_true()
	assert_bool(out.hasStream("temperature")).is_false()
	var stream = out.findStream("heat")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))

func test_rename_int_stream() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "count"
	s.to_name = "total"
	var d = _make_data("count", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("total")).is_true()
	assert_bool(out.hasStream("count")).is_false()
	var stream = out.findStream("total")
	assert_array(stream.container).is_equal(PackedInt32Array([10, 20, 30]))

func test_rename_vector_stream() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "velocity"
	s.to_name = "speed_vec"
	var d = _make_data("velocity", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("speed_vec")).is_true()
	assert_bool(out.hasStream("velocity")).is_false()

func test_rename_color_stream() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "tint"
	s.to_name = "color_out"
	var d = _make_data("tint", PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)]), FlowDataScript.DataType.Color)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("color_out")).is_true()
	assert_bool(out.hasStream("tint")).is_false()

func test_same_name_passthrough() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "attr"
	s.to_name = "attr"
	var d = _make_data("attr", PackedFloat32Array([5.0, 6.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("attr")).is_true()

func test_missing_input_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "x"
	s.to_name = "y"
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_empty_from_name_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = ""
	s.to_name = "output"
	var d = _make_data("attr", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_empty_to_name_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "attr"
	s.to_name = ""
	var d = _make_data("attr", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_missing_stream_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "nonexistent"
	s.to_name = "output"
	var d = _make_data("attr", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_reserved_destination_index_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "attr"
	s.to_name = "index"
	var d = _make_data("attr", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_reserved_destination_front_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "attr"
	s.to_name = "front"
	var d = _make_data("attr", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_reserved_destination_dot_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "attr"
	s.to_name = "pos.x"
	var d = _make_data("attr", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_overwrite_existing_enabled() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "src"
	s.to_name = "dst"
	s.overwrite_existing = true
	var d = FlowDataScript.Data.new()
	d.registerStream("src", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)
	d.registerStream("dst", PackedFloat32Array([99.0, 99.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("dst")).is_true()
	assert_bool(out.hasStream("src")).is_false()
	var stream = out.findStream("dst")
	assert_array(stream.container).is_equal(PackedFloat32Array([10.0, 20.0]))

func test_overwrite_existing_disabled_error() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "src"
	s.to_name = "dst"
	s.overwrite_existing = false
	var d = FlowDataScript.Data.new()
	d.registerStream("src", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)
	d.registerStream("dst", PackedFloat32Array([99.0, 99.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_single_element_array() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "solo"
	s.to_name = "renamed_solo"
	var d = _make_data("solo", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("renamed_solo")).is_true()
	var stream = out.findStream("renamed_solo")
	assert_array(stream.container).is_equal(PackedFloat32Array([42.0]))

func test_whitespace_trimmed_names() -> void:
	var s = AttributeRenameSettings.new()
	s.from_name = "  myattr  "
	s.to_name = "  newattr  "
	var d = _make_data("myattr", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("newattr")).is_true()
