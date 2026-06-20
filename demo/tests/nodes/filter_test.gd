# filter_test.gd
class_name FilterTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FilterNode = preload("res://addons/flow_nodes_editor/nodes/filter.gd")
const FilterSettings = preload("res://addons/flow_nodes_editor/nodes/filter_settings.gd")

func _create_data_with_stream(stream_name: String, values, data_type: int) -> FlowData.Data:
	var data := FlowDataScript.Data.new()
	data.registerStream(stream_name, values, data_type)
	return data

func _run_filter(in_dataA: FlowData.Data, in_dataB: FlowData.Data, condition: int, in_nameA: String = "A", in_nameB: String = "B", threshold: float = 0.1) -> FilterNode:
	var node = FilterNode.new()
	node.name = "filter_test_node"
	node.settings = FilterSettings.new()
	node.settings.condition = condition
	node.settings.in_nameA = in_nameA
	node.settings.in_nameB = in_nameB
	node.settings.threshold = threshold
	
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

func _get_output_data(node: FilterNode, port: int) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	return bulk[port]

func test_numeric_comparisons() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([1.0, 2.0, 3.0, 4.0]), FlowDataScript.DataType.Float)
	var in_dataB = _create_data_with_stream("B", PackedFloat32Array([3.0, 2.0, 1.0, 4.0]), FlowDataScript.DataType.Float)

	# Equal
	var node = _run_filter(in_dataA, in_dataB, FilterSettings.eCondition.Equal)
	assert_str(node.err).is_empty()
	var out_t = _get_output_data(node, 0)
	var out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedFloat32Array([2.0, 4.0]))
	assert_array(out_f.findStream("A").container).is_equal(PackedFloat32Array([1.0, 3.0]))
	node.free()

	# Greater
	node = _run_filter(in_dataA, in_dataB, FilterSettings.eCondition.Greater)
	assert_str(node.err).is_empty()
	out_t = _get_output_data(node, 0)
	out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedFloat32Array([3.0]))
	assert_array(out_f.findStream("A").container).is_equal(PackedFloat32Array([1.0, 2.0, 4.0]))
	node.free()

	# Less Or Equal
	node = _run_filter(in_dataA, in_dataB, FilterSettings.eCondition.LessOrEqual)
	assert_str(node.err).is_empty()
	out_t = _get_output_data(node, 0)
	out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedFloat32Array([1.0, 2.0, 4.0]))
	assert_array(out_f.findStream("A").container).is_equal(PackedFloat32Array([3.0]))
	node.free()

	# AlmostEqual (threshold 1.5)
	node = _run_filter(in_dataA, in_dataB, FilterSettings.eCondition.AlmostEqual, "A", "B", 1.5)
	assert_str(node.err).is_empty()
	out_t = _get_output_data(node, 0)
	out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedFloat32Array([2.0, 4.0]))
	assert_array(out_f.findStream("A").container).is_equal(PackedFloat32Array([1.0, 3.0]))
	node.free()

func test_logical_comparisons() -> void:
	var in_dataA = _create_data_with_stream("A", PackedByteArray([1, 1, 0, 0]), FlowDataScript.DataType.Bool)
	var in_dataB = _create_data_with_stream("B", PackedByteArray([1, 0, 1, 0]), FlowDataScript.DataType.Bool)

	# AND
	var node = _run_filter(in_dataA, in_dataB, FilterSettings.eCondition.LogicalAND)
	assert_str(node.err).is_empty()
	var out_t = _get_output_data(node, 0)
	var out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedByteArray([1]))
	assert_array(out_f.findStream("A").container).is_equal(PackedByteArray([1, 0, 0]))
	node.free()

	# XOR
	node = _run_filter(in_dataA, in_dataB, FilterSettings.eCondition.LogicalXOR)
	assert_str(node.err).is_empty()
	out_t = _get_output_data(node, 0)
	out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedByteArray([1, 0]))
	assert_array(out_f.findStream("A").container).is_equal(PackedByteArray([1, 0]))
	node.free()

func test_unary_isnull() -> void:
	# Resourcelist having some nulls and non-nulls
	var res1 = Resource.new()
	var in_dataA := FlowDataScript.Data.new()
	var res_array: Array[Resource] = [res1, null, null]
	in_dataA.registerStream("A", res_array, FlowDataScript.DataType.Resource)

	# IsNull
	var node = _run_filter(in_dataA, null, FilterSettings.eCondition.IsNull)
	assert_str(node.err).is_empty()
	var out_t = _get_output_data(node, 0)
	var out_f = _get_output_data(node, 1)
	assert_int(out_t.size()).is_equal(2) # index 1, 2 are null
	assert_int(out_f.size()).is_equal(1) # index 0 is not null
	node.free()

func test_constant_fallback() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([1.0, 3.0, 5.0]), FlowDataScript.DataType.Float)

	# Compare against constant "3.0"
	var node = _run_filter(in_dataA, null, FilterSettings.eCondition.Greater, "A", "3.0")
	assert_str(node.err).is_empty()
	var out_t = _get_output_data(node, 0)
	var out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedFloat32Array([5.0]))
	assert_array(out_f.findStream("A").container).is_equal(PackedFloat32Array([1.0, 3.0]))
	node.free()

func test_broadcast_filter() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([1.0, 3.0, 5.0]), FlowDataScript.DataType.Float)
	var in_dataB = _create_data_with_stream("B", PackedFloat32Array([2.5]), FlowDataScript.DataType.Float)

	# Greater against broadcasted B (size 1)
	var node = _run_filter(in_dataA, in_dataB, FilterSettings.eCondition.Greater)
	assert_str(node.err).is_empty()
	var out_t = _get_output_data(node, 0)
	var out_f = _get_output_data(node, 1)
	assert_array(out_t.findStream("A").container).is_equal(PackedFloat32Array([3.0, 5.0]))
	assert_array(out_f.findStream("A").container).is_equal(PackedFloat32Array([1.0]))
	node.free()

func test_error_handling() -> void:
	var in_dataA = _create_data_with_stream("A", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var in_dataB_mismatch = _create_data_with_stream("B", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)

	# Mismatched sizes
	var node = _run_filter(in_dataA, in_dataB_mismatch, FilterSettings.eCondition.Equal)
	assert_str(node.err).contains("do not match")
	node.free()

	# String type comparison error (non-numeric)
	var in_dataA_str = _create_data_with_stream("A", PackedStringArray(["a", "b"]), FlowDataScript.DataType.String)
	var in_dataB_str = _create_data_with_stream("B", PackedStringArray(["a", "c"]), FlowDataScript.DataType.String)
	node = _run_filter(in_dataA_str, in_dataB_str, FilterSettings.eCondition.Greater)
	assert_str(node.err).contains("must have int/float type")
	node.free()
