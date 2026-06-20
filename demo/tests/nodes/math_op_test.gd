# math_op_test.gd
class_name MathOpTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MathOpNode = preload("res://addons/flow_nodes_editor/nodes/math_op.gd")
const MathOpSettings = preload("res://addons/flow_nodes_editor/nodes/math_op_settings.gd")

func _create_data_with_stream(stream_name: String, values, data_type: int) -> FlowData.Data:
	var data := FlowDataScript.Data.new()
	data.registerStream(stream_name, values, data_type)
	return data

func _run_math_op(in_dataA: FlowData.Data, in_dataB: FlowData.Data, operation: int, in_nameA: String = "A", in_nameB: String = "B", out_name: String = "Result", constant_b: String = "") -> MathOpNode:
	var node = MathOpNode.new()
	node.name = "math_op_test_node"
	node.settings = MathOpSettings.new()
	node.settings.operation = operation
	node.settings.in_nameA = in_nameA
	if constant_b != "":
		node.settings.in_nameB = constant_b
	else:
		node.settings.in_nameB = in_nameB
	node.settings.out_name = out_name
	
	node.inputs = []
	node.inputs.resize(2)
	node.inputs[0] = in_dataA
	node.inputs[1] = in_dataB
	
	var ctx = FlowDataScript.EvaluationContext.new()
	# Instantiate dummy owner to prevent null owner checks causing early exits
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	node.preExecute(ctx)
	node.execute(ctx)
	
	dummy_owner.free()
	return node

func _get_output_data(node: MathOpNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_float_binary_ops() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([2.5, 3.0, 5.5, 2.0]), FlowDataScript.DataType.Float)
	var in_dataB = _create_data_with_stream("B", PackedFloat32Array([1.5, 1.5, 2.0, 3.0]), FlowDataScript.DataType.Float)
	
	# Add
	var node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Add)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("Result")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([4.0, 4.5, 7.5, 5.0]))
	node.free()
	
	# Subtract
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Substract)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 1.5, 3.5, -1.0]))
	node.free()

	# Multiply
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Multiply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([3.75, 4.5, 11.0, 6.0]))
	node.free()

	# Divide
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Divide)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([2.5/1.5, 2.0, 2.75, 2.0/3.0]))
	node.free()

	# Modulo
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Modulo)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 0.0, 1.5, 2.0]))
	node.free()

	# ModuloInt
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.ModuloInt)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([2 % 1, 3 % 1, 5 % 2, 2 % 3]))
	node.free()

	# Pow
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Pow)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([pow(2.5, 1.5), pow(3.0, 1.5), pow(5.5, 2.0), pow(2.0, 3.0)]))
	node.free()

	# Min
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Min)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([1.5, 1.5, 2.0, 2.0]))
	node.free()

	# Max
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Max)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([2.5, 3.0, 5.5, 3.0]))
	node.free()

func test_float_single_argument_ops() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([-2.5, 2.5, -0.5, 4.0]), FlowDataScript.DataType.Float)
	
	# Negate
	var node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Negate)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([2.5, -2.5, 0.5, -4.0]))
	node.free()

	# Absolute
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Absolute)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([2.5, 2.5, 0.5, 4.0]))
	node.free()

	# Saturate
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Saturate)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([0.0, 1.0, 0.0, 1.0]))
	node.free()

	# Floor
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Floor)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([-3.0, 2.0, -1.0, 4.0]))
	node.free()

	# FloorAsInt
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.FloorAsInt)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([-3, 2, -1, 4]))
	node.free()

	# Round
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Round)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([-3.0, 3.0, -1.0, 4.0]))
	node.free()

	# Frac
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Frac)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([0.5, 0.5, 0.5, 0.0]))
	node.free()

	# OneMinus
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.OneMinus)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([3.5, -1.5, 1.5, -3.0]))
	node.free()

	# Sign
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Sign)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([-1.0, 1.0, -1.0, 1.0]))
	node.free()

	# Sqrt
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Sqrt)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([0.0, sqrt(2.5), 0.0, 2.0]))
	node.free()

func test_vector_ops() -> void:
	var in_dataA = _create_data_with_stream("A", PackedVector3Array([Vector3(1, 2, 3), Vector3(-1, 0, 1)]), FlowDataScript.DataType.Vector)
	var in_dataB = _create_data_with_stream("B", PackedVector3Array([Vector3(4, 5, 6), Vector3(2, 2, 2)]), FlowDataScript.DataType.Vector)
	var in_dataB_float = _create_data_with_stream("B", PackedFloat32Array([2.0, 3.0]), FlowDataScript.DataType.Float)

	# Vector vs Vector Add
	var node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Add)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(5, 7, 9), Vector3(1, 2, 3)]))
	node.free()

	# Vector vs Vector Subtract
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Substract)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(-3, -3, -3), Vector3(-3, -2, -1)]))
	node.free()

	# Vector vs Vector Multiply
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Multiply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(4, 10, 18), Vector3(-2, 0, 2)]))
	node.free()

	# Vector vs Vector Divide
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Divide)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(0.25, 0.4, 0.5), Vector3(-0.5, 0.0, 0.5)]))
	node.free()

	# Vector vs Float Multiply
	node = _run_math_op(in_dataA, in_dataB_float, MathOpSettings.eOperation.Multiply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(2, 4, 6), Vector3(-3, 0, 3)]))
	node.free()

	# Vector vs Float Divide
	node = _run_math_op(in_dataA, in_dataB_float, MathOpSettings.eOperation.Divide)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(0.5, 1.0, 1.5), Vector3(-1.0/3.0, 0.0, 1.0/3.0)]))
	node.free()

func test_vector_single_argument_ops() -> void:
	var in_dataA = _create_data_with_stream("A", PackedVector3Array([Vector3(1, -2, 3), Vector3(-0.5, 0.5, 1.5)]), FlowDataScript.DataType.Vector)

	# Negate
	var node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Negate)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(-1, 2, -3), Vector3(0.5, -0.5, -1.5)]))
	node.free()

	# Absolute
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Absolute)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(1, 2, 3), Vector3(0.5, 0.5, 1.5)]))
	node.free()

	# Saturate
	node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Saturate)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(1, 0, 1), Vector3(0, 0.5, 1)]))
	node.free()

func test_color_ops() -> void:
	var in_dataA = _create_data_with_stream("A", PackedColorArray([Color(0.75, 0.75, 0.75, 0.75)]), FlowDataScript.DataType.Color)
	var in_dataB = _create_data_with_stream("B", PackedColorArray([Color(0.25, 0.25, 0.25, 0.25)]), FlowDataScript.DataType.Color)
	var in_dataB_float = _create_data_with_stream("B", PackedFloat32Array([2.0]), FlowDataScript.DataType.Float)

	# Color vs Color Add
	var node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Add)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedColorArray([Color(1.0, 1.0, 1.0, 1.0)]))
	node.free()

	# Color vs Color Subtract
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Substract)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedColorArray([Color(0.5, 0.5, 0.5, 0.5)]))
	node.free()

	# Color vs Color Multiply
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Multiply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedColorArray([Color(0.1875, 0.1875, 0.1875, 0.1875)]))
	node.free()

	# Color vs Color Divide
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Divide)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedColorArray([Color(3.0, 3.0, 3.0, 3.0)]))
	node.free()

	# Color vs Float Add
	node = _run_math_op(in_dataA, in_dataB_float, MathOpSettings.eOperation.Add)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedColorArray([Color(2.75, 2.75, 2.75, 2.75)]))
	node.free()

	# Color vs Float Multiply
	node = _run_math_op(in_dataA, in_dataB_float, MathOpSettings.eOperation.Multiply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedColorArray([Color(1.5, 1.5, 1.5, 1.5)]))
	node.free()

func test_int_ops() -> void:
	var in_dataA = _create_data_with_stream("A", PackedInt32Array([10, -5]), FlowDataScript.DataType.Int)
	var in_dataB = _create_data_with_stream("B", PackedInt32Array([3, 2]), FlowDataScript.DataType.Int)

	# Int Add
	var node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Add)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([13, -3]))
	node.free()

	# Int Subtract
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Substract)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([7, -7]))
	node.free()

	# Int Multiply
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Multiply)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([30, -10]))
	node.free()

	# Int Divide
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Divide)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([3, -2]))
	node.free()

	# Int ModuloInt
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.ModuloInt)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([1, -1]))
	node.free()

	# Int Min
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Min)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([3, -5]))
	node.free()

	# Int Max
	node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Max)
	assert_str(node.err).is_empty()
	out = _get_output_data(node)
	stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedInt32Array([10, 2]))
	node.free()

func test_constant_b_fallback() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([2.5, 3.0]), FlowDataScript.DataType.Float)

	# B is not connected, but settings.in_nameB = "5.0" (valid float string)
	var node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Add, "A", "", "Result", "5.0")
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([7.5, 8.0]))
	node.free()

func test_broadcast_b() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([2.5, 3.0, 4.0]), FlowDataScript.DataType.Float)
	var in_dataB = _create_data_with_stream("B", PackedFloat32Array([2.0]), FlowDataScript.DataType.Float)

	# Multiply where B has only 1 element
	var node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Multiply)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	var stream = out.findStream("Result")
	assert_array(stream.container).is_equal(PackedFloat32Array([5.0, 6.0, 8.0]))
	node.free()

func test_zero_division_modulo_errors() -> void:
	var in_dataA_float = _create_data_with_stream("A", PackedFloat32Array([2.5]), FlowDataScript.DataType.Float)
	var in_dataB_float_zero = _create_data_with_stream("B", PackedFloat32Array([0.0]), FlowDataScript.DataType.Float)

	# Float divide by zero
	var node = _run_math_op(in_dataA_float, in_dataB_float_zero, MathOpSettings.eOperation.Divide)
	assert_str(node.err).is_equal("Division by zero")
	node.free()

	# Float modulo by zero
	node = _run_math_op(in_dataA_float, in_dataB_float_zero, MathOpSettings.eOperation.Modulo)
	assert_str(node.err).is_equal("Modulo by zero")
	node.free()

	# Int modulo by zero
	var in_dataA_int = _create_data_with_stream("A", PackedInt32Array([5]), FlowDataScript.DataType.Int)
	var in_dataB_int_zero = _create_data_with_stream("B", PackedInt32Array([0]), FlowDataScript.DataType.Int)
	node = _run_math_op(in_dataA_int, in_dataB_int_zero, MathOpSettings.eOperation.ModuloInt)
	assert_str(node.err).is_equal("Modulo by zero")
	node.free()

	# Vector divide by zero
	var in_dataA_vec = _create_data_with_stream("A", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	var in_dataB_vec_zero = _create_data_with_stream("B", PackedVector3Array([Vector3(1, 0, 1)]), FlowDataScript.DataType.Vector)
	node = _run_math_op(in_dataA_vec, in_dataB_vec_zero, MathOpSettings.eOperation.Divide)
	assert_str(node.err).is_equal("Division by zero")
	node.free()

func test_incompatible_types_error() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([2.5]), FlowDataScript.DataType.Float)
	var in_dataB = _create_data_with_stream("B", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)

	var node = _run_math_op(in_dataA, in_dataB, MathOpSettings.eOperation.Add)
	assert_str(node.err).contains("incompatible/unsupported data types")
	node.free()

func test_single_argument_unsupported_type() -> void:
	var in_dataA = _create_data_with_stream("A", PackedStringArray(["hello"]), FlowDataScript.DataType.String)
	var node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Negate)
	assert_str(node.err).contains("unsupported data type for single-argument operation")
	node.free()

func test_vector_single_arg_unsupported() -> void:
	var in_dataA = _create_data_with_stream("A", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	var node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Floor)
	assert_str(node.err).contains("not supported as single-argument yet")
	node.free()

func test_input_a_missing() -> void:
	var node = MathOpNode.new()
	node.name = "math_op_test_node"
	node.settings = MathOpSettings.new()
	node.settings.in_nameA = "A"
	node.settings.out_name = "Result"
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).contains("Input A not connected")
	dummy_owner.free()
	node.free()

func test_stream_a_not_found() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run_math_op(in_dataA, null, MathOpSettings.eOperation.Negate, "NonExistent")
	assert_str(node.err).contains("Input A NonExistent not found")
	node.free()
