# expression_test.gd
class_name ExpressionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ExpressionNode = preload("res://addons/flow_nodes_editor/nodes/expression.gd")
const ExpressionSettings = preload("res://addons/flow_nodes_editor/nodes/expression_settings.gd")

func _create_data_with_stream(stream_name: String, values, data_type: int) -> FlowData.Data:
	var data := FlowDataScript.Data.new()
	data.registerStream(stream_name, values, data_type)
	return data

func _run_expression(in_dataA: FlowData.Data, expr_str: String, out_name: String = "expr", expose_arrays := false, args := {}) -> ExpressionNode:
	var node = ExpressionNode.new()
	node.name = "expression_test_node"
	node.settings = ExpressionSettings.new()
	node.settings.expression = expr_str
	node.settings.out_name = out_name
	node.settings.expose_arrays = expose_arrays
	node.settings.args = args
	
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = in_dataA
	
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	node.preExecute(ctx)
	node.execute(ctx)
	
	dummy_owner.free()
	return node

func _get_output_data(node: ExpressionNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_basic_expression() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)

	# val * 2.0 + 5.0
	var node = _run_expression(in_data, "val * 2.0 + 5.0")
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("expr")
	assert_array(stream.container).is_equal(PackedFloat32Array([7.0, 9.0, 11.0]))

func test_ue_built_in_attributes() -> void:
	var in_data = _create_data_with_stream("position", PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 5, 0)]), FlowDataScript.DataType.Vector)

	# UE Sigil style "$position.x + $Index"
	# $position.x is mapped to position.x (which gets evaluated as the x component of Vector3)
	var node = _run_expression(in_data, "$position.x + $Index")
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("expr")
	# index 0: 1.0 + 0 = 1.0; index 1: 2.0 + 1 = 3.0
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 3.0]))

func test_expression_args() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)

	# custom argument multiplier = 5.0
	var node = _run_expression(in_data, "val * multiplier", "expr", false, {"multiplier": 5.0})
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("expr")
	assert_array(stream.container).is_equal(PackedFloat32Array([50.0, 100.0]))

func test_expose_arrays() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)

	# With expose_arrays true, must use val[Index] to access index-based elements
	var node = _run_expression(in_data, "val[Index] * 10.0", "expr", true)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("expr")
	assert_array(stream.container).is_equal(PackedFloat32Array([10.0, 20.0, 30.0]))

func test_expression_parse_error() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)

	# Invalid expression syntax
	var node = _run_expression(in_data, "val + * 2.0")
	assert_str(node.err).contains("parsing expression")

# ---------------------------------------------------------------------------
# Numeric coercion into an existing Bool/Int/Float stream
# ---------------------------------------------------------------------------

func test_int_result_into_existing_float_stream_keeps_float() -> void:
	var in_data = _create_data_with_stream("rank", PackedFloat32Array([1.5, 2.5, 3.5]), FlowDataScript.DataType.Float)
	var holder := {}
	# `Index` is an int result; writing it into the Float `rank` must not retype
	# the stream (and must not warn about a name conflict).
	await assert_error(func(): holder.node = _run_expression(in_data, "Index * 2", "rank")).is_success()
	var node = holder.node
	assert_str(node.err).is_empty()
	var stream = _get_output_data(node).findStream("rank")
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Float)
	assert_array(Array(stream.container)).is_equal([0.0, 2.0, 4.0])

func test_float_result_into_existing_int_stream_keeps_int() -> void:
	var in_data = _create_data_with_stream("count", PackedInt32Array([1, 2, 3]), FlowDataScript.DataType.Int)
	var node = _run_expression(in_data, "count * 1.5", "count")
	var stream = _get_output_data(node).findStream("count")
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Int)
	assert_array(Array(stream.container)).is_equal([1, 3, 4])

func test_numeric_result_into_existing_bool_stream_keeps_bool() -> void:
	var in_data = _create_data_with_stream("flag", PackedByteArray([1, 1, 1]), FlowDataScript.DataType.Bool)
	var node = _run_expression(in_data, "Index", "flag")
	var stream = _get_output_data(node).findStream("flag")
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Bool)
	assert_array(Array(stream.container)).is_equal([0, 1, 1])

func test_non_numeric_mismatch_still_retypes_with_warning() -> void:
	var in_data = _create_data_with_stream("rank", PackedFloat32Array([1.5, 2.5]), FlowDataScript.DataType.Float)
	var holder := {}
	await assert_error(func(): holder.node = _run_expression(in_data, "str(Index)", "rank")) \
		.is_push_warning("Stream name conflict: 'rank' already exists with data_type 2, overwriting with data_type 4")
	var stream = _get_output_data(holder.node).findStream("rank")
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.String)
	assert_array(Array(stream.container)).is_equal(["0", "1"])

func test_numeric_result_into_new_stream_uses_result_type() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run_expression(in_data, "Index", "fresh")
	assert_int(_get_output_data(node).findStream("fresh").data_type).is_equal(FlowDataScript.DataType.Int)
