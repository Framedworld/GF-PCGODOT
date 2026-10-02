# difference_test.gd
class_name DifferenceTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DifferenceNode = preload("res://addons/flow_nodes_editor/nodes/difference.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")

func _make_points(positions: PackedVector3Array, sizes: PackedVector3Array = PackedVector3Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	if sizes.size() > 0:
		d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	else:
		var default_sizes := PackedVector3Array()
		default_sizes.resize(positions.size())
		default_sizes.fill(Vector3.ONE)
		d.registerStream(FlowData.AttrSize, default_sizes, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings: DifferenceSettings) -> DifferenceNode:
	var node = DifferenceNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: DifferenceNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func _default_settings(op: int = DifferenceSettings.eOperation.A_Minus_B) -> DifferenceSettings:
	var s = DifferenceSettings.new()
	s.operation = op
	return s

func test_missing_input_a_sets_error() -> void:
	var s = _default_settings()
	var dataB = _make_points(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = _run([null, dataB], s)
	assert_str(node.err).is_not_empty()

func test_missing_input_b_sets_error() -> void:
	var s = _default_settings()
	var dataA = _make_points(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = _run([dataA, null], s)
	assert_str(node.err).is_not_empty()

func test_both_inputs_empty_returns_empty_output() -> void:
	var s = _default_settings()
	var dataA = FlowDataScript.Data.new()
	var dataB = FlowDataScript.Data.new()
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_a_minus_b_empty_a_returns_empty() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.A_Minus_B)
	var dataA = FlowDataScript.Data.new()
	var dataB = _make_points(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_b_minus_a_empty_b_returns_empty() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.B_Minus_A)
	var dataA = _make_points(PackedVector3Array([Vector3(0, 0, 0)]))
	var dataB = FlowDataScript.Data.new()
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_union_empty_a_returns_b() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.Union)
	var posB = PackedVector3Array([Vector3(10, 0, 0), Vector3(20, 0, 0)])
	var dataA = FlowDataScript.Data.new()
	var dataB = _make_points(posB)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

func test_a_minus_b_non_overlapping_keeps_all_a() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.A_Minus_B)
	var posA = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var posB = PackedVector3Array([Vector3(100, 0, 0), Vector3(200, 0, 0)])
	var sizesA = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var sizesB = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var dataA = _make_points(posA, sizesA)
	var dataB = _make_points(posB, sizesB)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

func test_a_minus_b_fully_overlapping_removes_all_a() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.A_Minus_B)
	var pos = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var dataA = _make_points(pos, sizes)
	var dataB = _make_points(pos, sizes)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_b_minus_a_non_overlapping_keeps_all_b() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.B_Minus_A)
	var posA = PackedVector3Array([Vector3(100, 0, 0)])
	var posB = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0)])
	var sizesA = PackedVector3Array([Vector3(1, 1, 1)])
	var sizesB = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var dataA = _make_points(posA, sizesA)
	var dataB = _make_points(posB, sizesB)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

func test_intersection_overlapping_points_returns_overlap_from_a() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.Intersection)
	s.intersection_overlap_source = DifferenceSettings.eOverlapSource.FromA
	var posA = PackedVector3Array([Vector3(0, 0, 0), Vector3(50, 0, 0)])
	var posB = PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	var sizesA = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var sizesB = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var dataA = _make_points(posA, sizesA)
	var dataB = _make_points(posB, sizesB)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(0, 0, 0)]))

func test_intersection_no_overlap_returns_empty() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.Intersection)
	var posA = PackedVector3Array([Vector3(0, 0, 0)])
	var posB = PackedVector3Array([Vector3(100, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var dataA = _make_points(posA, sizes)
	var dataB = _make_points(posB, sizes)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_union_non_overlapping_returns_all_points() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.Union)
	var posA = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var posB = PackedVector3Array([Vector3(100, 0, 0), Vector3(200, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var dataA = _make_points(posA, sizes)
	var dataB = _make_points(posB, sizes)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)

func test_symmetric_difference_non_overlapping_returns_all() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.SymmetricDifference)
	var posA = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var posB = PackedVector3Array([Vector3(100, 0, 0), Vector3(200, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var dataA = _make_points(posA, sizes)
	var dataB = _make_points(posB, sizes)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)

func test_symmetric_difference_fully_overlapping_returns_empty() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.SymmetricDifference)
	var pos = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var dataA = _make_points(pos, sizes)
	var dataB = _make_points(pos, sizes)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_missing_position_stream_sets_error() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.A_Minus_B)
	var dataA := FlowDataScript.Data.new()
	dataA.registerStream("density", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var dataB = _make_points(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_not_empty()

func test_union_overlap_source_from_b_returns_b_points_for_overlaps() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.Union)
	s.union_overlap_source = DifferenceSettings.eOverlapSource.FromB
	var posA = PackedVector3Array([Vector3(0, 0, 0), Vector3(50, 0, 0)])
	var posB = PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, 0)])
	var sizesA = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var sizesB = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var dataA = _make_points(posA, sizesA)
	var dataB = _make_points(posB, sizesB)
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)

func test_symmetric_difference_empty_b_returns_all_a() -> void:
	var s = _default_settings(DifferenceSettings.eOperation.SymmetricDifference)
	var posA = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0)])
	var dataA = _make_points(posA)
	var dataB = FlowDataScript.Data.new()
	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
