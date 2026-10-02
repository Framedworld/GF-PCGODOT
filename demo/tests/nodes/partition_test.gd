# partition_test.gd
class_name PartitionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PartitionNode = preload("res://addons/flow_nodes_editor/nodes/partition.gd")
const PartitionSettings = preload("res://addons/flow_nodes_editor/nodes/partition_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, settings) -> PartitionNode:
	var node = PartitionNode.new()
	node.name = "test_partition_node"
	node.settings = settings
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _default_settings(attr: String = "category") -> PartitionNodeSettings:
	var s = PartitionNodeSettings.new()
	s.attribute_name = attr
	s.out_partition_attribute = ""
	return s

func test_partition_int_three_groups() -> void:
	var data = _make_data("category", PackedInt32Array([1, 2, 1, 3, 2, 1]), FlowDataScript.DataType.Int)
	var s = _default_settings("category")
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(3)
	var total_points = 0
	for bulk in node.generated_bulks:
		var out_data: FlowData.Data = bulk[0]
		assert_object(out_data).is_not_null()
		total_points += out_data.size()
	assert_int(total_points).is_equal(6)

func test_partition_float_two_groups() -> void:
	var data = _make_data("weight", PackedFloat32Array([1.0, 2.0, 1.0, 2.0]), FlowDataScript.DataType.Float)
	var s = _default_settings("weight")
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(2)
	var sizes: Array = []
	for bulk in node.generated_bulks:
		sizes.append(bulk[0].size())
	sizes.sort()
	assert_array(sizes).is_equal([2, 2])

func test_partition_group_sizes_match_values() -> void:
	var data = _make_data("group", PackedInt32Array([0, 0, 0, 1, 1]), FlowDataScript.DataType.Int)
	var s = _default_settings("group")
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(2)
	var sizes: Array = []
	for bulk in node.generated_bulks:
		sizes.append(bulk[0].size())
	sizes.sort()
	assert_array(sizes).is_equal([2, 3])

func test_partition_preserves_other_streams() -> void:
	var data = FlowDataScript.Data.new()
	data.registerStream("tag", PackedInt32Array([1, 2, 1]), FlowDataScript.DataType.Int)
	data.registerStream("value", PackedFloat32Array([10.0, 20.0, 30.0]), FlowDataScript.DataType.Float)
	var s = _default_settings("tag")
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(2)
	for bulk in node.generated_bulks:
		var out_data: FlowData.Data = bulk[0]
		assert_object(out_data.findStream("tag")).is_not_null()
		assert_object(out_data.findStream("value")).is_not_null()

func test_partition_out_partition_attribute() -> void:
	var data = _make_data("color", PackedInt32Array([1, 2, 1]), FlowDataScript.DataType.Int)
	var s = _default_settings("color")
	s.out_partition_attribute = "partition_id"
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(2)
	for bulk in node.generated_bulks:
		var out_data: FlowData.Data = bulk[0]
		assert_object(out_data.findStream("partition_id")).is_not_null()

func test_partition_data_attr_stamped() -> void:
	var data = _make_data("region", PackedInt32Array([10, 20, 10]), FlowDataScript.DataType.Int)
	var s = _default_settings("region")
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	for bulk in node.generated_bulks:
		var out_data: FlowData.Data = bulk[0]
		var attr_stream = out_data.findStream(FlowData.DataAttrPrefix + "region")
		assert_object(attr_stream).is_not_null()
		assert_int(attr_stream.container.size()).is_equal(1)

func test_partition_single_element() -> void:
	var data = _make_data("type", PackedInt32Array([42]), FlowDataScript.DataType.Int)
	var s = _default_settings("type")
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(1)
	assert_int(node.generated_bulks[0][0].size()).is_equal(1)

func test_partition_all_same_value() -> void:
	var data = _make_data("tier", PackedInt32Array([5, 5, 5, 5]), FlowDataScript.DataType.Int)
	var s = _default_settings("tier")
	var node = _run(data, s)
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(1)
	assert_int(node.generated_bulks[0][0].size()).is_equal(4)

func test_partition_missing_attribute_error() -> void:
	var data = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var s = _default_settings("nonexistent_attr")
	var node = _run(data, s)
	assert_str(node.err).is_not_empty()

func test_partition_missing_input_error() -> void:
	var s = _default_settings("category")
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()
