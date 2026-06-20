extends SceneTree

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const BranchNode = preload("res://addons/flow_nodes_editor/nodes/branch.gd")
const BranchSettings = preload("res://addons/flow_nodes_editor/nodes/branch_settings.gd")
const ExpressionNode = preload("res://addons/flow_nodes_editor/nodes/expression.gd")
const ExpressionSettings = preload("res://addons/flow_nodes_editor/nodes/expression_settings.gd")
const OutputNode = preload("res://addons/flow_nodes_editor/nodes/output.gd")
const OutputSettings = preload("res://addons/flow_nodes_editor/nodes/output_settings.gd")
const PointToAttributeSetNode = preload("res://addons/flow_nodes_editor/nodes/point_to_attribute_set.gd")
const PointToAttributeSetSettings = preload("res://addons/flow_nodes_editor/nodes/point_to_attribute_set_settings.gd")
const RemoveAttributeNode = preload("res://addons/flow_nodes_editor/nodes/remove_attribute.gd")
const RemoveAttributeSettings = preload("res://addons/flow_nodes_editor/nodes/remove_attribute_settings.gd")


func _init() -> void:
	var passed := true
	passed = _test_expression_writes_bool_stream_as_bytes() and passed
	passed = _test_expression_reads_ue_system_attribute_name() and passed
	passed = _test_branch_unselected_output_keeps_empty_schema() and passed
	passed = _test_point_to_attribute_set_preserves_transforms_without_nil_return_error() and passed
	passed = _test_remove_attribute_keep_selected_preserves_system_streams() and passed
	passed = _test_output_accepts_empty_schema() and passed

	if not passed:
		push_error("FlowCommonNodeRegressionTest failed.")
		quit(1)
		return
	quit(0)


func _test_expression_writes_bool_stream_as_bytes() -> bool:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("value", PackedInt32Array([0, 1, 2]), FlowDataScript.DataType.Int)

	var node = ExpressionNode.new()
	node.name = "expression"
	node.settings = ExpressionSettings.new()
	node.settings.expression = "Index == 1"
	node.settings.out_name = "is_middle"
	node.deps = _empty_connections()
	node.dependants = _empty_connections()
	node.inputs = [in_data]

	_execute_node(node)

	var out_data = _get_output(node, 0)
	var passed := _expect_byte_stream(
		out_data,
		"is_middle",
		PackedByteArray([0, 1, 0]),
		"Expression should write bool results as 0/1 bytes"
	)
	node.free()
	return passed


func _test_expression_reads_ue_system_attribute_name() -> bool:
	var in_data := FlowDataScript.Data.new()
	in_data.addCommonStreams(2)
	var positions : PackedVector3Array = in_data.getContainerChecked(str(FlowDataScript.AttrPosition), FlowDataScript.DataType.Vector)
	positions[0] = Vector3(2.0, 0.0, 0.0)
	positions[1] = Vector3(10.0, 0.0, 0.0)

	var node = ExpressionNode.new()
	node.name = "expression"
	node.settings = ExpressionSettings.new()
	node.settings.expression = "$Position.x + $Index"
	node.settings.out_name = "position_plus_index"
	node.deps = _empty_connections()
	node.dependants = _empty_connections()
	node.inputs = [in_data]

	_execute_node(node)

	var out_data = _get_output(node, 0)
	var passed := _expect_float_stream(
		out_data,
		"position_plus_index",
		PackedFloat32Array([2.0, 11.0]),
		"Expression should read UE-style built-in attributes"
	)
	node.free()
	return passed


func _test_branch_unselected_output_keeps_empty_schema() -> bool:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("id", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	in_data.registerStream("shared", PackedStringArray(["constant"]), FlowDataScript.DataType.String)

	var node = BranchNode.new()
	node.name = "branch"
	node.settings = BranchSettings.new()
	node.settings.branch_value = true
	node.deps = _empty_connections()
	node.dependants = _empty_connections()
	node.inputs = [in_data]

	_execute_node(node)

	var selected_data = _get_output(node, 0)
	var unselected_data = _get_output(node, 1)
	var passed := (
		_expect(selected_data == in_data, "Selected branch should forward the input data")
		and _expect(unselected_data != null, "Unselected branch should emit data")
		and _expect(unselected_data.size() == 0, "Unselected branch should have zero rows")
		and _expect_empty_stream(unselected_data, "id", FlowDataScript.DataType.Int)
		and _expect_empty_stream(unselected_data, "shared", FlowDataScript.DataType.String)
	)
	node.free()
	return passed


func _test_point_to_attribute_set_preserves_transforms_without_nil_return_error() -> bool:
	var in_data := FlowDataScript.Data.new()
	in_data.addCommonStreams(1)

	var node = PointToAttributeSetNode.new()
	node.name = "point_to_attribute_set"
	node.settings = PointToAttributeSetSettings.new()
	node.settings.drop_point_transform_streams = true
	node.settings.preserve_transforms_as_attributes = true
	node.deps = _empty_connections()
	node.dependants = _empty_connections()
	node.inputs = [in_data]

	_execute_node(node)

	var out_data = _get_output(node, 0)
	var passed := (
		_expect(out_data != null, "Point To Attribute Set should emit output")
		and _expect(out_data.findStream(str(FlowDataScript.AttrPosition)) == null, "$Position stream should be dropped")
		and _expect(out_data.findStream(str(FlowDataScript.AttrRotation)) == null, "$Rotation stream should be dropped")
		and _expect(out_data.findStream(str(FlowDataScript.AttrSize)) == null, "$Scale stream should be dropped")
		and _expect_stream_size(out_data, "point_position", FlowDataScript.DataType.Vector, 1)
		and _expect_stream_size(out_data, "point_rotation", FlowDataScript.DataType.Vector, 1)
		and _expect_stream_size(out_data, "point_size", FlowDataScript.DataType.Vector, 1)
	)
	node.free()
	return passed


func _test_remove_attribute_keep_selected_preserves_system_streams() -> bool:
	var in_data := FlowDataScript.Data.new()
	in_data.addCommonStreams(1)
	in_data.registerStream("coast_width", PackedFloat32Array([40.0]), FlowDataScript.DataType.Float)

	var node = RemoveAttributeNode.new()
	node.name = "remove_attribute"
	node.settings = RemoveAttributeSettings.new()
	node.settings.keep_selected_attributes = true
	var keep_names: Array[String] = [
		str(FlowDataScript.AttrPosition),
		"coast_width",
	]
	node.settings.names = keep_names
	node.deps = _empty_connections()
	node.dependants = _empty_connections()
	node.inputs = [in_data]

	_execute_node(node)

	var out_data = _get_output(node, 0)
	var passed := (
		_expect(out_data != null, "Remove Attributes should emit output")
		and _expect_stream_size(out_data, str(FlowDataScript.AttrPosition), FlowDataScript.DataType.Vector, 1)
		and _expect_stream_size(out_data, "coast_width", FlowDataScript.DataType.Float, 1)
		and _expect(out_data.findStream(str(FlowDataScript.AttrRotation)) == null, "$Rotation should be removed")
	)
	node.free()
	return passed


func _test_output_accepts_empty_schema() -> bool:
	var in_data := FlowDataScript.Data.new()

	var node = OutputNode.new()
	node.name = "output"
	node.settings = OutputSettings.new()
	node.settings.name = "out_val"
	node.deps = _empty_connections()
	node.dependants = _empty_connections()
	node.inputs = [in_data]

	_execute_node(node)

	var out_data = _get_output(node, 0)
	var passed := (
		_expect(out_data != null, "Output should emit empty schema data")
		and _expect(out_data.streams.size() == 0, "Output empty schema should have no streams")
	)
	node.free()
	return passed


func _execute_node(node) -> void:
	var ctx = FlowDataScript.EvaluationContext.new()
	node.preExecute(ctx)
	node.execute(ctx)


func _get_output(node, port : int):
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	return bulk[port]


func _empty_connections() -> Array[Dictionary]:
	return []


func _expect_empty_stream(data, stream_name : String, data_type : int) -> bool:
	return _expect_stream_size(data, stream_name, data_type, 0)


func _expect_stream_size(data, stream_name : String, data_type : int, expected_size : int) -> bool:
	if not _expect(data != null, "Missing data for stream '%s'" % stream_name):
		return false
	var stream = data.findStream(stream_name)
	if not _expect(stream != null, "Missing stream '%s'" % stream_name):
		return false
	return (
		_expect(stream.data_type == data_type, "Stream '%s' has type %d" % [stream_name, stream.data_type])
		and _expect(stream.container.size() == expected_size, "Stream '%s' should have %d values" % [stream_name, expected_size])
	)


func _expect_byte_stream(data, stream_name : String, expected : PackedByteArray, message : String) -> bool:
	if not _expect(data != null, "%s: missing output" % message):
		return false
	var stream = data.findStream(stream_name)
	if not _expect(stream != null, "%s: missing stream '%s'" % [message, stream_name]):
		return false
	if not _expect(stream.data_type == FlowDataScript.DataType.Bool, "%s: expected Bool stream" % message):
		return false
	if not _expect(stream.container.size() == expected.size(), "%s: expected %d values" % [message, expected.size()]):
		return false
	for i in range(expected.size()):
		if not _expect(int(stream.container[i]) == int(expected[i]), "%s: index %d got %s" % [message, i, stream.container[i]]):
			return false
	return true


func _expect_float_stream(data, stream_name : String, expected : PackedFloat32Array, message : String) -> bool:
	if not _expect(data != null, "%s: missing output" % message):
		return false
	var stream = data.findStream(stream_name)
	if not _expect(stream != null, "%s: missing stream '%s'" % [message, stream_name]):
		return false
	if not _expect(stream.data_type == FlowDataScript.DataType.Float, "%s: expected Float stream" % message):
		return false
	if not _expect(stream.container.size() == expected.size(), "%s: expected %d values" % [message, expected.size()]):
		return false
	for i in range(expected.size()):
		if not _expect(is_equal_approx(float(stream.container[i]), expected[i]), "%s: index %d got %s" % [message, i, stream.container[i]]):
			return false
	return true


func _expect(condition : bool, message : String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
