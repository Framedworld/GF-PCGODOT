# intersection_test.gd
class_name IntersectionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const IntersectionNode = preload("res://addons/flow_nodes_editor/nodes/intersection.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")

func _make_point_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array) -> IntersectionNode:
	var node = IntersectionNode.new()
	node.name = "test_intersection"
	var s = DifferenceSettings.new()
	node.settings = s
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

func test_overlapping_points_returned() -> void:
	var posA := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
	])
	var posB := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
	])
	var dataA := _make_point_data(posA)
	dataA.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0)]), FlowDataScript.DataType.Vector)
	var dataB := _make_point_data(posB)
	dataB.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3(1.0, 1.0, 1.0)]), FlowDataScript.DataType.Vector)

	var node = _run([dataA, dataB])
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(PackedVector3Array(pos_stream.container)).is_equal(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))

func test_no_overlap_returns_empty() -> void:
	var posA := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
	])
	var posB := PackedVector3Array([
		Vector3(100.0, 0.0, 0.0),
	])
	var dataA := _make_point_data(posA)
	dataA.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3(1.0, 1.0, 1.0)]), FlowDataScript.DataType.Vector)
	var dataB := _make_point_data(posB)
	dataB.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3(1.0, 1.0, 1.0)]), FlowDataScript.DataType.Vector)

	var node = _run([dataA, dataB])
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_multiple_overlapping_points() -> void:
	var posA := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(5.0, 0.0, 0.0),
		Vector3(50.0, 0.0, 0.0),
	])
	var posB := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(5.0, 0.0, 0.0),
	])
	var dataA := _make_point_data(posA)
	dataA.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0)]), FlowDataScript.DataType.Vector)
	var dataB := _make_point_data(posB)
	dataB.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0)]), FlowDataScript.DataType.Vector)

	var node = _run([dataA, dataB])
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

func test_empty_input_a_returns_empty() -> void:
	var posA := PackedVector3Array()
	var posB := PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var dataA := _make_point_data(posA)
	var dataB := _make_point_data(posB)
	dataB.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3(1.0, 1.0, 1.0)]), FlowDataScript.DataType.Vector)

	var node = _run([dataA, dataB])
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_null_inputs_produce_error() -> void:
	var node = _run([null, null])
	assert_str(node.err).is_not_empty()
