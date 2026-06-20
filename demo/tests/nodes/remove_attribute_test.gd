# remove_attribute_test.gd
class_name RemoveAttributeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const RemoveAttributeNode = preload("res://addons/flow_nodes_editor/nodes/remove_attribute.gd")
const RemoveAttributeSettings = preload("res://addons/flow_nodes_editor/nodes/remove_attribute_settings.gd")

func _create_test_data() -> FlowData.Data:
	var data := FlowDataScript.Data.new()
	data.registerStream("val1", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	data.registerStream("val2", PackedInt32Array([10, 20]), FlowDataScript.DataType.Int)
	data.registerStream("val3", PackedStringArray(["a", "b"]), FlowDataScript.DataType.String)
	return data

func _run_remove_attribute(in_data: FlowData.Data, names: Array[String], keep_selected_attributes := false) -> RemoveAttributeNode:
	var node = RemoveAttributeNode.new()
	node.name = "remove_attribute_test_node"
	node.settings = RemoveAttributeSettings.new()
	node.settings.names = names
	node.settings.keep_selected_attributes = keep_selected_attributes
	
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

func _get_output_data(node: RemoveAttributeNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_remove_selected_attributes() -> void:
	var in_data = _create_test_data()

	# Remove val1 and val3
	var node = _run_remove_attribute(in_data, ["val1", "val3"])
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	
	assert_object(out.findStream("val2")).is_not_null()
	assert_object(out.findStream("val1")).is_null()
	assert_object(out.findStream("val3")).is_null()
	node.free()

func test_keep_selected_attributes() -> void:
	var in_data = _create_test_data()

	# Keep only val2
	var node = _run_remove_attribute(in_data, ["val2"], true)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)

	assert_object(out.findStream("val2")).is_not_null()
	assert_object(out.findStream("val1")).is_null()
	assert_object(out.findStream("val3")).is_null()
	node.free()

func test_remove_nonexistent_attribute() -> void:
	var in_data = _create_test_data()

	# Attempt to remove non-existent attribute should not trigger error
	var node = _run_remove_attribute(in_data, ["NonExistent"])
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)

	assert_object(out.findStream("val1")).is_not_null()
	assert_object(out.findStream("val2")).is_not_null()
	assert_object(out.findStream("val3")).is_not_null()
	node.free()

func test_remove_system_attributes() -> void:
	var in_data = _create_test_data()
	in_data.addCommonStreams(2) # Adds position, rotation, size

	# Remove position and size
	var node = _run_remove_attribute(in_data, [str(FlowDataScript.AttrPosition), str(FlowDataScript.AttrSize)])
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)

	assert_object(out.findStream(str(FlowDataScript.AttrRotation))).is_not_null()
	assert_object(out.findStream(str(FlowDataScript.AttrPosition))).is_null()
	assert_object(out.findStream(str(FlowDataScript.AttrSize))).is_null()
	node.free()
