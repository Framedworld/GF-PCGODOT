# boolean_test.gd
class_name BooleanTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const BooleanNode = preload("res://addons/flow_nodes_editor/nodes/boolean.gd")
const BooleanSettings = preload("res://addons/flow_nodes_editor/nodes/boolean_settings.gd")

func _create_data_with_stream(stream_name: String, values, data_type: int) -> FlowData.Data:
	var data := FlowDataScript.Data.new()
	data.registerStream(stream_name, values, data_type)
	return data

func _run_boolean(in_dataA: FlowData.Data, in_dataB: FlowData.Data, operation: int, in_nameA: String = "A", in_nameB: String = "B", out_name: String = "bool_out", use_constant_b := false, constant_b := false) -> BooleanNode:
	var node = BooleanNode.new()
	node.name = "boolean_test_node"
	node.settings = BooleanSettings.new()
	node.settings.operation = operation
	node.settings.in_nameA = in_nameA
	node.settings.in_nameB = in_nameB
	node.settings.out_name = out_name
	node.settings.use_constant_b = use_constant_b
	node.settings.constant_b = constant_b
	
	node.inputs = []
	node.inputs.resize(2)
	node.inputs[0] = in_dataA
	node.inputs[1] = in_dataB
	
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	node.preExecute(ctx)
	node.execute(ctx)
	
	dummy_owner.free()
	return node

func _get_output_data(node: BooleanNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_binary_boolean_ops() -> void:
	var in_dataA = _create_data_with_stream("A", PackedByteArray([1, 1, 0, 0]), FlowDataScript.DataType.Bool)
	var in_dataB = _create_data_with_stream("B", PackedByteArray([1, 0, 1, 0]), FlowDataScript.DataType.Bool)

	# AND
	var node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.And)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 0, 0, 0]))
	node.free()

	# OR
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Or)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 1, 1, 0]))
	node.free()

	# XOR
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Xor)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([0, 1, 1, 0]))
	node.free()

	# IMPLY
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Imply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 0, 1, 1]))
	node.free()

	# NAND
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Nand)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([0, 1, 1, 1]))
	node.free()

	# NIMPLY
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Nimply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([0, 1, 0, 0]))
	node.free()

	# NOR
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Nor)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([0, 0, 0, 1]))
	node.free()

	# XNOR
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Xnor)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 0, 0, 1]))
	node.free()

func test_unary_boolean_op() -> void:
	var in_dataA = _create_data_with_stream("A", PackedByteArray([1, 0]), FlowDataScript.DataType.Bool)

	# NOT
	var node = _run_boolean(in_dataA, null, BooleanSettings.eOperation.Not)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([0, 1]))
	node.free()

func test_constant_b_logic() -> void:
	var in_dataA = _create_data_with_stream("A", PackedByteArray([1, 0]), FlowDataScript.DataType.Bool)

	# AND with constant B = false
	var node = _run_boolean(in_dataA, null, BooleanSettings.eOperation.And, "A", "B", "bool_out", true, false)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([0, 0]))
	node.free()

	# OR with constant B = true
	node = _run_boolean(in_dataA, null, BooleanSettings.eOperation.Or, "A", "B", "bool_out", true, true)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 1]))
	node.free()

func test_fallback_literal_b() -> void:
	var in_dataA = _create_data_with_stream("A", PackedByteArray([1, 0]), FlowDataScript.DataType.Bool)

	# B is not connected, but in_nameB = "true" (literal fallback)
	var node = _run_boolean(in_dataA, null, BooleanSettings.eOperation.And, "A", "true")
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 0]))
	node.free()

	# B is not connected, but in_nameB = "false" (literal fallback)
	node = _run_boolean(in_dataA, null, BooleanSettings.eOperation.Or, "A", "false")
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 0]))
	node.free()

func test_fallback_same_input_a() -> void:
	# Single input data holds both streams "A" and "B"
	var in_dataA := FlowDataScript.Data.new()
	in_dataA.registerStream("A", PackedByteArray([1, 0]), FlowDataScript.DataType.Bool)
	in_dataA.registerStream("Other", PackedByteArray([0, 1]), FlowDataScript.DataType.Bool)

	# in_nameB is set to "Other", B port not connected. Should read from "Other" stream of A
	var node = _run_boolean(in_dataA, null, BooleanSettings.eOperation.Or, "A", "Other")
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 1]))
	node.free()

func test_broadcast_and_errors() -> void:
	var in_dataA = _create_data_with_stream("A", PackedByteArray([1, 0, 1]), FlowDataScript.DataType.Bool)
	var in_dataB = _create_data_with_stream("B", PackedByteArray([0]), FlowDataScript.DataType.Bool)

	# Broadcast B (size 1) AND A (size 3)
	var node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.Or)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("bool_out")
	assert_array(stream.container).is_equal(PackedByteArray([1, 0, 1]))
	node.free()

	# Mismatched sizes (no broadcast)
	var in_dataB_mismatch = _create_data_with_stream("B", PackedByteArray([0, 0]), FlowDataScript.DataType.Bool)
	node = _run_boolean(in_dataA, in_dataB_mismatch, BooleanSettings.eOperation.And)
	assert_str(node.err).contains("Input sizes from A and B don't match")
	node.free()

	# Missing stream A
	node = _run_boolean(in_dataA, in_dataB, BooleanSettings.eOperation.And, "NonExistent")
	assert_str(node.err).contains("Input A NonExistent not found")
	node.free()
