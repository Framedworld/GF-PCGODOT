# input_test.gd
class_name InputTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const InputNode = preload("res://addons/flow_nodes_editor/nodes/input.gd")
const InputSettings = preload("res://addons/flow_nodes_editor/nodes/input_settings.gd")

func _make_graph_with_float_param(param_name: String, default_val: float) -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	var param := GraphInputParameter.new()
	param.name = param_name
	param.data_type = FlowData.DataType.Float
	param.cte_float = default_val
	graph.in_params = [param]
	return graph

func _make_graph_with_int_param(param_name: String, default_val: int) -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	var param := GraphInputParameter.new()
	param.name = param_name
	param.data_type = FlowData.DataType.Int
	param.cte_int = default_val
	graph.in_params = [param]
	return graph

func _make_graph_with_vector_param(param_name: String, default_val: Vector3) -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	var param := GraphInputParameter.new()
	param.name = param_name
	param.data_type = FlowData.DataType.Vector
	param.cte_vector = default_val
	graph.in_params = [param]
	return graph

func _run(s: InputNodeSettings, graph: FlowGraphResource, args: Dictionary = {}) -> InputNode:
	var node := InputNode.new()
	node.name = "test_input_node"
	node.settings = s
	node.inputs = []
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	ctx.graph = graph
	for key in args:
		ctx.owner.args[key] = args[key]
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: InputNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_float_default_value() -> void:
	var s := InputSettings.new()
	s.name = "my_float"
	s.data_type = FlowData.DataType.Float
	var graph = _make_graph_with_float_param("my_float", 3.14)
	var node = _run(s, graph)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_float")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(3.14, 0.001)
	node.free()

func test_int_default_value() -> void:
	var s := InputSettings.new()
	s.name = "my_int"
	s.data_type = FlowData.DataType.Int
	var graph = _make_graph_with_int_param("my_int", 42)
	var node = _run(s, graph)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_int")
	assert_object(stream).is_not_null()
	assert_int(stream.container[0]).is_equal(42)
	node.free()

func test_vector_default_value() -> void:
	var s := InputSettings.new()
	s.name = "my_vec"
	s.data_type = FlowData.DataType.Vector
	var graph = _make_graph_with_vector_param("my_vec", Vector3(1.0, 2.0, 3.0))
	var node = _run(s, graph)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_vec")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(1.0, 2.0, 3.0)]))
	node.free()

func test_float_overridden_by_args() -> void:
	var s := InputSettings.new()
	s.name = "speed"
	s.data_type = FlowData.DataType.Float
	var graph = _make_graph_with_float_param("speed", 1.0)
	var node = _run(s, graph, {"speed": 9.5})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("speed")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(9.5, 0.001)
	node.free()

func test_float_overridden_by_flowdata_args() -> void:
	var s := InputSettings.new()
	s.name = "density"
	s.data_type = FlowData.DataType.Float
	var graph = _make_graph_with_float_param("density", 0.0)
	var arg_data := FlowDataScript.Data.new()
	arg_data.registerStream("density", PackedFloat32Array([0.25, 0.5, 0.75]), FlowData.DataType.Float)
	var node = _run(s, graph, {"density": arg_data})
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([0.25, 0.5, 0.75]))
	node.free()

func test_error_no_graph() -> void:
	var s := InputSettings.new()
	s.name = "val"
	s.data_type = FlowData.DataType.Float
	var node := InputNode.new()
	node.name = "test_input_node"
	node.settings = s
	node.inputs = []
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_empty()
	node.free()

func test_error_empty_in_params() -> void:
	var s := InputSettings.new()
	s.name = "val"
	s.data_type = FlowData.DataType.Float
	var graph := FlowGraphResource.new()
	var node = _run(s, graph)
	assert_str(node.err).is_not_empty()
	node.free()

func test_error_param_name_not_found() -> void:
	var s := InputSettings.new()
	s.name = "nonexistent"
	s.data_type = FlowData.DataType.Float
	var graph = _make_graph_with_float_param("other_param", 0.0)
	var node = _run(s, graph)
	assert_str(node.err).is_not_empty()
	node.free()

func test_multiple_params_output_correct_stream() -> void:
	var s := InputSettings.new()
	s.name = "beta"
	s.data_type = FlowData.DataType.Float
	var graph := FlowGraphResource.new()
	var param_a := GraphInputParameter.new()
	param_a.name = "alpha"
	param_a.data_type = FlowData.DataType.Float
	param_a.cte_float = 1.0
	var param_b := GraphInputParameter.new()
	param_b.name = "beta"
	param_b.data_type = FlowData.DataType.Float
	param_b.cte_float = 2.0
	graph.in_params = [param_a, param_b]
	var node = _run(s, graph)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("beta")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(2.0, 0.001)
	node.free()
