# branch_test.gd
class_name BranchTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const BranchNode = preload("res://addons/flow_nodes_editor/nodes/branch.gd")
const BranchSettings = preload("res://addons/flow_nodes_editor/nodes/branch_settings.gd")

func _create_data_with_stream(stream_name: String, values, data_type: int) -> FlowData.Data:
	var data := FlowDataScript.Data.new()
	data.registerStream(stream_name, values, data_type)
	return data

func _run_branch(in_data: FlowData.Data, branch_value: bool, use_attribute := false, attribute_name := "") -> BranchNode:
	var node = BranchNode.new()
	node.name = "branch_test_node"
	node.settings = BranchSettings.new()
	node.settings.branch_value = branch_value
	node.settings.use_attribute = use_attribute
	node.settings.attribute_name = attribute_name
	
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = in_data
	
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	node.preExecute(ctx)
	node.execute(ctx)
	
	dummy_owner.free()
	return node

func _get_output_data(node: BranchNode, port: int) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	return bulk[port]

func test_static_branch_true() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	# Static branch true -> Output A gets input, Output B gets empty schema
	var node = _run_branch(in_data, true)
	assert_str(node.err).is_empty()
	var out_a = _get_output_data(node, 0)
	var out_b = _get_output_data(node, 1)

	assert_object(out_a).is_equal(in_data)
	assert_int(out_b.size()).is_equal(0)
	assert_object(out_b.findStream("val")).is_not_null() # Schema preserved
	node.free()

func test_static_branch_false() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	# Static branch false -> Output A gets empty schema, Output B gets input
	var node = _run_branch(in_data, false)
	assert_str(node.err).is_empty()
	var out_a = _get_output_data(node, 0)
	var out_b = _get_output_data(node, 1)

	assert_int(out_a.size()).is_equal(0)
	assert_object(out_b).is_equal(in_data)
	node.free()

func test_attribute_branch_bool() -> void:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	
	# Try true attribute
	in_data.registerStream("cond", PackedByteArray([1]), FlowDataScript.DataType.Bool)
	var node = _run_branch(in_data, false, true, "cond")
	assert_str(node.err).is_empty()
	assert_object(_get_output_data(node, 0)).is_equal(in_data)
	node.free()

	# Try false attribute
	in_data.registerStream("cond", PackedByteArray([0]), FlowDataScript.DataType.Bool)
	node = _run_branch(in_data, true, true, "cond")
	assert_str(node.err).is_empty()
	assert_object(_get_output_data(node, 1)).is_equal(in_data)
	node.free()

func test_attribute_branch_truthy_string() -> void:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	
	# "yes" is truthy
	in_data.registerStream("cond", PackedStringArray(["yes"]), FlowDataScript.DataType.String)
	var node = _run_branch(in_data, false, true, "cond")
	assert_str(node.err).is_empty()
	assert_object(_get_output_data(node, 0)).is_equal(in_data)
	node.free()

	# "no" is falsy
	in_data.registerStream("cond", PackedStringArray(["no"]), FlowDataScript.DataType.String)
	node = _run_branch(in_data, true, true, "cond")
	assert_str(node.err).is_empty()
	assert_object(_get_output_data(node, 1)).is_equal(in_data)
	node.free()

func test_attribute_missing_error() -> void:
	var in_data = _create_data_with_stream("val", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)

	# Use attribute with non-existent stream -> Should throw error
	var node = _run_branch(in_data, true, true, "NonExistent")
	assert_str(node.err).contains("Attribute 'NonExistent' not found")
	node.free()
