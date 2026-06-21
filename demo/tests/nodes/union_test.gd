# union_test.gd
class_name UnionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const UnionNode = preload("res://addons/flow_nodes_editor/nodes/union.gd")
const DifferenceNodeSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")

func _make_point_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> UnionNode:
	var node = UnionNode.new()
	node.name = "test_union"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_union_non_overlapping_combines_all_points() -> void:
	var posA := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	var posB := PackedVector3Array([Vector3(100, 0, 0), Vector3(200, 0, 0)])
	var s = DifferenceNodeSettings.new()
	var node = _run([_make_point_data(posA), _make_point_data(posB)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(4)
	node.free()

func test_union_with_overlapping_points_keeps_expected_count() -> void:
	var posA := PackedVector3Array([Vector3(0, 0, 0)])
	var posB := PackedVector3Array([Vector3(0, 0, 0)])
	var s = DifferenceNodeSettings.new()
	var node = _run([_make_point_data(posA), _make_point_data(posB)], s)
	auto_free(node)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	node.free()

func test_union_empty_input_b_returns_a() -> void:
	var posA := PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	var posB := PackedVector3Array()
	var s = DifferenceNodeSettings.new()
	var node = _run([_make_point_data(posA), _make_point_data(posB)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
	node.free()

func test_union_empty_input_a_returns_b() -> void:
	var posA := PackedVector3Array()
	var posB := PackedVector3Array([Vector3(7, 8, 9)])
	var s = DifferenceNodeSettings.new()
	var node = _run([_make_point_data(posA), _make_point_data(posB)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	node.free()

func test_union_null_inputs_report_error() -> void:
	var s = DifferenceNodeSettings.new()
	var node = _run([null, null], s)
	assert_str(node.err).is_not_empty()
	node.free()
