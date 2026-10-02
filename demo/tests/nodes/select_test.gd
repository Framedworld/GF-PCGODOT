# select_test.gd
class_name SelectTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SelectNode = preload("res://addons/flow_nodes_editor/nodes/select.gd")
const SelectSettings = preload("res://addons/flow_nodes_editor/nodes/select_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> SelectNode:
	var node = SelectNode.new()
	node.name = "test_select_node"
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

func test_static_select_a_floats() -> void:
	var s = SelectSettings.new()
	s.select_b = false
	var data_a = _make_data("pos", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var data_b = _make_data("pos", PackedFloat32Array([10.0, 20.0, 30.0]), FlowDataScript.DataType.Float)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_a)

func test_static_select_b_floats() -> void:
	var s = SelectSettings.new()
	s.select_b = true
	var data_a = _make_data("pos", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var data_b = _make_data("pos", PackedFloat32Array([10.0, 20.0, 30.0]), FlowDataScript.DataType.Float)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_b)

func test_static_select_a_vectors() -> void:
	var s = SelectSettings.new()
	s.select_b = false
	var data_a = _make_data("pts", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	var data_b = _make_data("pts", PackedVector3Array([Vector3(9, 8, 7)]), FlowDataScript.DataType.Vector)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_a)

func test_attribute_select_b_via_bool_true() -> void:
	var s = SelectSettings.new()
	s.select_b = false
	s.use_attribute = true
	s.attribute_name = "flag"
	var data_a = _make_data("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	data_a.registerStream("flag", PackedByteArray([1]), FlowDataScript.DataType.Bool)
	var data_b = _make_data("val", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_b)

func test_attribute_select_a_via_bool_false() -> void:
	var s = SelectSettings.new()
	s.select_b = true
	s.use_attribute = true
	s.attribute_name = "flag"
	var data_a = _make_data("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	data_a.registerStream("flag", PackedByteArray([0]), FlowDataScript.DataType.Bool)
	var data_b = _make_data("val", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_a)

func test_attribute_select_via_truthy_string() -> void:
	var s = SelectSettings.new()
	s.select_b = false
	s.use_attribute = true
	s.attribute_name = "pick"
	var data_a = _make_data("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	data_a.registerStream("pick", PackedStringArray(["yes"]), FlowDataScript.DataType.String)
	var data_b = _make_data("val", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_b)

func test_attribute_select_via_float_one() -> void:
	var s = SelectSettings.new()
	s.select_b = false
	s.use_attribute = true
	s.attribute_name = "flag"
	var data_a = _make_data("val", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	data_a.registerStream("flag", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var data_b = _make_data("val", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_b)

func test_attribute_falls_back_to_input_b_when_a_missing() -> void:
	var s = SelectSettings.new()
	s.select_b = false
	s.use_attribute = true
	s.attribute_name = "flag"
	var data_b = _make_data("val", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	data_b.registerStream("flag", PackedByteArray([1]), FlowDataScript.DataType.Bool)
	var node = _run([null, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_b)

func test_missing_both_inputs_returns_empty_data() -> void:
	var s = SelectSettings.new()
	s.select_b = false
	var node = _run([null, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_only_input_b_connected_select_b_true() -> void:
	var s = SelectSettings.new()
	s.select_b = true
	var data_b = _make_data("pts", PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)]), FlowDataScript.DataType.Vector)
	var node = _run([null, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_b)

func test_only_input_a_connected_select_b_true_returns_empty() -> void:
	var s = SelectSettings.new()
	s.select_b = true
	var data_a = _make_data("pts", PackedVector3Array([Vector3(1, 0, 0)]), FlowDataScript.DataType.Vector)
	var node = _run([data_a, null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_attribute_name_empty_uses_static_select_b() -> void:
	var s = SelectSettings.new()
	s.select_b = true
	s.use_attribute = true
	s.attribute_name = ""
	var data_a = _make_data("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var data_b = _make_data("val", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var node = _run([data_a, data_b], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_equal(data_b)
