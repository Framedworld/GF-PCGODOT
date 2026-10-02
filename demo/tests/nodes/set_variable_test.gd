# set_variable_test.gd
class_name SetVariableTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SetVariableNode = preload("res://addons/flow_nodes_editor/nodes/set_variable.gd")
const SetVariableSettings = preload("res://addons/flow_nodes_editor/nodes/set_variable_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> SetVariableNode:
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _run_with_ctx(inputs: Array, settings) -> Array:
	var node = SetVariableNode.new()
	node.name = "test_set_variable_ctx"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return [node, ctx]

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_stores_float_data_in_variable() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "my_floats"
	var in_data = _make_data("value", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = s
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_bool(ctx.variables.has("my_floats")).is_true()
	assert_object(ctx.variables["my_floats"]).is_same(in_data)
	dummy.free()

func test_passthrough_output_unchanged() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "pass_through"
	var in_data = _make_data("density", PackedFloat32Array([0.1, 0.5, 0.9]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_same(in_data)

func test_stores_vector_data_in_variable() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "positions"
	var in_data = _make_data("position", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = s
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_bool(ctx.variables.has("positions")).is_true()
	var stored = ctx.variables["positions"]
	var stream = stored.findStream("position")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	dummy.free()

func test_stores_int_data_in_variable() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "counters"
	var in_data = _make_data("count", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = s
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_bool(ctx.variables.has("counters")).is_true()
	var stored = ctx.variables["counters"]
	var stream = stored.findStream("count")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([10, 20, 30]))
	dummy.free()

func test_stores_color_data_in_variable() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "palette"
	var in_data = _make_data("color", PackedColorArray([Color.RED, Color.GREEN, Color.BLUE]), FlowDataScript.DataType.Color)
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = s
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_bool(ctx.variables.has("palette")).is_true()
	var stored = ctx.variables["palette"]
	var stream = stored.findStream("color")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	dummy.free()

func test_error_when_variable_name_is_empty() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = ""
	var in_data = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()

func test_error_when_variable_name_is_whitespace_only() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "   "
	var in_data = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()

func test_no_input_creates_empty_data_and_stores_it() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "empty_var"
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = s
	node.inputs = [null]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_bool(ctx.variables.has("empty_var")).is_true()
	assert_object(ctx.variables["empty_var"]).is_not_null()
	dummy.free()

func test_no_input_passthrough_output_is_not_null() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "empty_out"
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

func test_multiple_streams_stored_and_passed_through() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "rich_data"
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	in_data.registerStream("density", PackedFloat32Array([0.1, 0.9]), FlowDataScript.DataType.Float)
	in_data.registerStream("seed", PackedInt32Array([42, 99]), FlowDataScript.DataType.Int)
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = s
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_bool(ctx.variables.has("rich_data")).is_true()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("position")).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("seed")).is_not_null()
	dummy.free()

func test_overwrites_existing_variable_in_context() -> void:
	var s = SetVariableSettings.new()
	s.variable_name = "my_var"
	var old_data = _make_data("old", PackedFloat32Array([9.9]), FlowDataScript.DataType.Float)
	var new_data = _make_data("new", PackedFloat32Array([1.1, 2.2]), FlowDataScript.DataType.Float)
	var node = SetVariableNode.new()
	node.name = "test_set_variable"
	node.settings = s
	node.inputs = [new_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	ctx.variables["my_var"] = old_data
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	assert_object(ctx.variables["my_var"]).is_same(new_data)
	dummy.free()
