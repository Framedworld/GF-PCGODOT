# get_variable_test.gd
class_name GetVariableTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GetVariableNode = preload("res://addons/flow_nodes_editor/nodes/get_variable.gd")
const GetVariableSettings = preload("res://addons/flow_nodes_editor/nodes/get_variable_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(settings, variables: Dictionary) -> GetVariableNode:
	var node = GetVariableNode.new()
	node.name = "test_get_variable"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	ctx.variables = variables
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_retrieves_float_variable() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "my_floats"
	var stored = _make_data("value", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run(s, {"my_floats": stored})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))

func test_retrieves_vector_variable() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "positions"
	var stored = _make_data("position", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var node = _run(s, {"positions": stored})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("position")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)

func test_retrieves_int_variable() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "counters"
	var stored = _make_data("count", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run(s, {"counters": stored})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([10, 20, 30]))

func test_retrieves_color_variable() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "palette"
	var stored = _make_data("color", PackedColorArray([Color.RED, Color.GREEN]), FlowDataScript.DataType.Color)
	var node = _run(s, {"palette": stored})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)

func test_error_when_variable_name_is_empty() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = ""
	var stored = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run(s, {"some_var": stored})
	assert_str(node.err).is_not_empty()

func test_error_when_variable_name_is_whitespace_only() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "   "
	var stored = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run(s, {"   ": stored})
	assert_str(node.err).is_not_empty()

func test_error_when_variable_not_in_context() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "missing_var"
	var node = _run(s, {})
	assert_str(node.err).is_not_empty()

func test_error_when_variable_name_missing_from_non_empty_context() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "wanted"
	var other = _make_data("value", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	var node = _run(s, {"other_var": other})
	assert_str(node.err).is_not_empty()

func test_output_is_same_data_object() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "shared"
	var stored = _make_data("density", PackedFloat32Array([0.5, 0.75]), FlowDataScript.DataType.Float)
	var node = _run(s, {"shared": stored})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_same(stored)

func test_multiple_streams_preserved() -> void:
	var s = GetVariableSettings.new()
	s.variable_name = "rich_data"
	var stored := FlowDataScript.Data.new()
	stored.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	stored.registerStream("density", PackedFloat32Array([0.1, 0.9]), FlowDataScript.DataType.Float)
	stored.registerStream("seed", PackedInt32Array([42, 99]), FlowDataScript.DataType.Int)
	var node = _run(s, {"rich_data": stored})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("position")).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("seed")).is_not_null()
