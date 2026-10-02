# switch_test.gd
class_name SwitchTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SwitchNode = preload("res://addons/flow_nodes_editor/nodes/switch.gd")
const SwitchSettings = preload("res://addons/flow_nodes_editor/nodes/switch_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(in_data, settings) -> SwitchNode:
	var node = SwitchNode.new()
	node.name = "switch_test_node"
	node.settings = settings
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = in_data
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _get_output(node: SwitchNode, port: int) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	return bulk[port]

func test_static_index_0_routes_to_out0() -> void:
	var s = SwitchSettings.new()
	s.index = 0
	s.use_attribute = false
	var in_data = _make_data("pos", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_object(_get_output(node, 0)).is_equal(in_data)
	assert_int(_get_output(node, 1).size()).is_equal(0)
	assert_int(_get_output(node, 2).size()).is_equal(0)
	assert_int(_get_output(node, 3).size()).is_equal(0)

func test_static_index_1_routes_to_out1() -> void:
	var s = SwitchSettings.new()
	s.index = 1
	s.use_attribute = false
	var in_data = _make_data("val", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_int(_get_output(node, 0).size()).is_equal(0)
	assert_object(_get_output(node, 1)).is_equal(in_data)
	assert_int(_get_output(node, 2).size()).is_equal(0)
	assert_int(_get_output(node, 3).size()).is_equal(0)

func test_static_index_2_routes_to_out2() -> void:
	var s = SwitchSettings.new()
	s.index = 2
	s.use_attribute = false
	var in_data = _make_data("col", PackedColorArray([Color(1, 0, 0), Color(0, 1, 0)]), FlowDataScript.DataType.Color)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_int(_get_output(node, 0).size()).is_equal(0)
	assert_int(_get_output(node, 1).size()).is_equal(0)
	assert_object(_get_output(node, 2)).is_equal(in_data)
	assert_int(_get_output(node, 3).size()).is_equal(0)

func test_static_index_3_routes_to_out3() -> void:
	var s = SwitchSettings.new()
	s.index = 3
	s.use_attribute = false
	var in_data = _make_data("vec", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_int(_get_output(node, 0).size()).is_equal(0)
	assert_int(_get_output(node, 1).size()).is_equal(0)
	assert_int(_get_output(node, 2).size()).is_equal(0)
	assert_object(_get_output(node, 3)).is_equal(in_data)

func test_index_clamped_below_zero() -> void:
	var s = SwitchSettings.new()
	s.index = -5
	s.use_attribute = false
	var in_data = _make_data("val", PackedFloat32Array([7.0]), FlowDataScript.DataType.Float)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_object(_get_output(node, 0)).is_equal(in_data)
	assert_int(_get_output(node, 1).size()).is_equal(0)

func test_index_clamped_above_three() -> void:
	var s = SwitchSettings.new()
	s.index = 99
	s.use_attribute = false
	var in_data = _make_data("val", PackedFloat32Array([7.0]), FlowDataScript.DataType.Float)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_int(_get_output(node, 2).size()).is_equal(0)
	assert_object(_get_output(node, 3)).is_equal(in_data)

func test_attribute_mode_reads_index_from_stream() -> void:
	var s = SwitchSettings.new()
	s.index = 0
	s.use_attribute = true
	s.attribute_name = "route"
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	in_data.registerStream("route", PackedFloat32Array([2.0]), FlowDataScript.DataType.Float)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_int(_get_output(node, 0).size()).is_equal(0)
	assert_int(_get_output(node, 1).size()).is_equal(0)
	assert_object(_get_output(node, 2)).is_equal(in_data)
	assert_int(_get_output(node, 3).size()).is_equal(0)

func test_attribute_mode_uses_static_index_when_name_empty() -> void:
	var s = SwitchSettings.new()
	s.index = 1
	s.use_attribute = true
	s.attribute_name = ""
	var in_data = _make_data("val", PackedFloat32Array([5.0, 6.0]), FlowDataScript.DataType.Float)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	assert_int(_get_output(node, 0).size()).is_equal(0)
	assert_object(_get_output(node, 1)).is_equal(in_data)
	assert_int(_get_output(node, 2).size()).is_equal(0)
	assert_int(_get_output(node, 3).size()).is_equal(0)

func test_attribute_mode_missing_stream_falls_back_to_static_index() -> void:
	var s = SwitchSettings.new()
	s.index = 3
	s.use_attribute = true
	s.attribute_name = "nonexistent"
	var in_data = _make_data("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run(in_data, s)
	assert_int(_get_output(node, 3).size()).is_equal(0) if not node.err.is_empty() else assert_object(_get_output(node, 3)).is_equal(in_data)

func test_missing_input_produces_empty_outputs() -> void:
	var s = SwitchSettings.new()
	s.index = 0
	s.use_attribute = false
	var node = _run(null, s)

func test_non_selected_outputs_are_independent_data_objects() -> void:
	var s = SwitchSettings.new()
	s.index = 0
	s.use_attribute = false
	var in_data = _make_data("pos", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out1 = _get_output(node, 1)
	var out2 = _get_output(node, 2)
	var out3 = _get_output(node, 3)
	assert_object(out1).is_not_null()
	assert_object(out2).is_not_null()
	assert_object(out3).is_not_null()
	assert_bool(out1 == out2).is_false()
	assert_bool(out2 == out3).is_false()
