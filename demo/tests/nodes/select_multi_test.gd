# select_multi_test.gd
class_name SelectMultiTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SelectMultiNode = preload("res://addons/flow_nodes_editor/nodes/select_multi.gd")
const SelectMultiSettings = preload("res://addons/flow_nodes_editor/nodes/select_multi_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> SelectMultiNode:
	var node = SelectMultiNode.new()
	node.name = "test_select_multi"
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

func test_static_index_selects_input_0() -> void:
	var s = SelectMultiSettings.new()
	s.index = 0
	s.use_attribute = false
	var d0 = _make_data("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var d1 = _make_data("val", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, d1, null, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(d0)

func test_static_index_selects_input_1() -> void:
	var s = SelectMultiSettings.new()
	s.index = 1
	s.use_attribute = false
	var d0 = _make_data("a", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var d1 = _make_data("b", PackedFloat32Array([2.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, d1, null, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(d1)

func test_static_index_selects_input_2_and_3() -> void:
	var s = SelectMultiSettings.new()
	s.use_attribute = false
	var d0 = _make_data("x", PackedFloat32Array([0.0]), FlowDataScript.DataType.Float)
	var d1 = _make_data("x", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var d2 = _make_data("x", PackedFloat32Array([2.0]), FlowDataScript.DataType.Float)
	var d3 = _make_data("x", PackedFloat32Array([3.0]), FlowDataScript.DataType.Float)

	s.index = 2
	var node2 = _run([d0, d1, d2, d3], s)
	assert_str(node2.err).is_empty()
	assert_object(_output(node2)).is_equal(d2)

	s.index = 3
	var node3 = _run([d0, d1, d2, d3], s)
	assert_str(node3.err).is_empty()
	assert_object(_output(node3)).is_equal(d3)

func test_index_clamped_below_zero() -> void:
	var s = SelectMultiSettings.new()
	s.index = -5
	s.use_attribute = false
	var d0 = _make_data("val", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, null, null, null], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d0)

func test_index_clamped_above_3() -> void:
	var s = SelectMultiSettings.new()
	s.index = 100
	s.use_attribute = false
	var d3 = _make_data("val", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	var node = _run([null, null, null, d3], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d3)

func test_selected_input_not_connected_returns_empty_data() -> void:
	var s = SelectMultiSettings.new()
	s.index = 2
	s.use_attribute = false
	var d0 = _make_data("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, null, null, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_attribute_mode_reads_index_from_first_connected_input() -> void:
	var s = SelectMultiSettings.new()
	s.use_attribute = true
	s.attribute_name = "sel"
	var d0 = _make_data("sel", PackedInt32Array([2]), FlowDataScript.DataType.Int)
	var d1 = _make_data("other", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var d2 = _make_data("result", PackedFloat32Array([999.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, d1, d2, null], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d2)

func test_attribute_mode_fallback_to_static_index_when_attribute_missing() -> void:
	var s = SelectMultiSettings.new()
	s.use_attribute = true
	s.attribute_name = "nonexistent"
	s.index = 1
	var d0 = _make_data("val", PackedFloat32Array([0.0]), FlowDataScript.DataType.Float)
	var d1 = _make_data("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, d1, null, null], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d1)

func test_attribute_mode_empty_attribute_name_uses_static_index() -> void:
	var s = SelectMultiSettings.new()
	s.use_attribute = true
	s.attribute_name = ""
	s.index = 0
	var d0 = _make_data("val", PackedFloat32Array([7.0]), FlowDataScript.DataType.Float)
	var d1 = _make_data("val", PackedFloat32Array([8.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, d1, null, null], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d0)

func test_attribute_mode_float_index_attribute_truncated_to_int() -> void:
	var s = SelectMultiSettings.new()
	s.use_attribute = true
	s.attribute_name = "idx"
	var d0 = _make_data("idx", PackedFloat32Array([1.9]), FlowDataScript.DataType.Float)
	var d1 = _make_data("chosen", PackedFloat32Array([55.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, d1, null, null], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d1)

func test_attribute_mode_skips_inputs_without_attribute_stream() -> void:
	var s = SelectMultiSettings.new()
	s.use_attribute = true
	s.attribute_name = "sel"
	var d0 = _make_data("other", PackedFloat32Array([0.0]), FlowDataScript.DataType.Float)
	var d1 = _make_data("sel", PackedInt32Array([3]), FlowDataScript.DataType.Int)
	var d3 = _make_data("target", PackedFloat32Array([77.0]), FlowDataScript.DataType.Float)
	var node = _run([d0, d1, null, d3], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d3)

func test_all_inputs_null_returns_empty_data() -> void:
	var s = SelectMultiSettings.new()
	s.index = 0
	s.use_attribute = false
	var node = _run([null, null, null, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_vector_data_passthrough() -> void:
	var s = SelectMultiSettings.new()
	s.index = 1
	s.use_attribute = false
	var d0 = _make_data("pos", PackedVector3Array([Vector3(0,0,0)]), FlowDataScript.DataType.Vector)
	var d1 = _make_data("pos", PackedVector3Array([Vector3(1,2,3), Vector3(4,5,6)]), FlowDataScript.DataType.Vector)
	var node = _run([d0, d1, null, null], s)
	assert_str(node.err).is_empty()
	assert_object(_output(node)).is_equal(d1)

func test_color_data_passthrough() -> void:
	var s = SelectMultiSettings.new()
	s.index = 0
	s.use_attribute = false
	var d0 = _make_data("col", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)
	var node = _run([d0, null, null, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(d0)
	var stream = out.findStream("col")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
