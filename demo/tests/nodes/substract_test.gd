# substract_test.gd
class_name SubstractTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SubstractNode = preload("res://addons/flow_nodes_editor/nodes/substract.gd")
const SubstractSettings = preload("res://addons/flow_nodes_editor/nodes/substract_settings.gd")

func _make_point_data(positions: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	d.registerStream("size", sizes, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> SubstractNode:
	var node = SubstractNode.new()
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

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_missing_input_a_error() -> void:
	var s = SubstractSettings.new()
	s.operation = SubstractSettings.eOperation.A_Minus_B
	var node = _run([null, null], s)
	assert_str(node.err).is_not_empty()

func test_missing_input_b_error() -> void:
	var s = SubstractSettings.new()
	s.operation = SubstractSettings.eOperation.A_Minus_B
	var posA = PackedVector3Array([Vector3(0, 0, 0)])
	var szA = PackedVector3Array([Vector3(1, 1, 1)])
	var dataA = _make_point_data(posA, szA)
	var node = _run([dataA, null], s)
	assert_str(node.err).is_not_empty()

func test_a_minus_b_removes_overlapping_points() -> void:
	var s = SubstractSettings.new()
	s.operation = SubstractSettings.eOperation.A_Minus_B

	var posA = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(200, 0, 0),
	])
	var szA = PackedVector3Array([
		Vector3(1, 1, 1),
		Vector3(1, 1, 1),
		Vector3(1, 1, 1),
	])

	var posB = PackedVector3Array([Vector3(0, 0, 0)])
	var szB = PackedVector3Array([Vector3(1, 1, 1)])

	var dataA = _make_point_data(posA, szA)
	var dataB = _make_point_data(posB, szB)

	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)

func test_a_intersection_b_keeps_only_overlapping_points() -> void:
	var s = SubstractSettings.new()
	s.operation = SubstractSettings.eOperation.A_Intersection_B

	var posA = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(100, 0, 0),
		Vector3(200, 0, 0),
	])
	var szA = PackedVector3Array([
		Vector3(1, 1, 1),
		Vector3(1, 1, 1),
		Vector3(1, 1, 1),
	])

	var posB = PackedVector3Array([Vector3(0, 0, 0)])
	var szB = PackedVector3Array([Vector3(1, 1, 1)])

	var dataA = _make_point_data(posA, szA)
	var dataB = _make_point_data(posB, szB)

	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)

func test_a_minus_b_no_overlap_returns_all_of_a() -> void:
	var s = SubstractSettings.new()
	s.operation = SubstractSettings.eOperation.A_Minus_B

	var posA = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(10, 0, 0),
	])
	var szA = PackedVector3Array([
		Vector3(1, 1, 1),
		Vector3(1, 1, 1),
	])

	var posB = PackedVector3Array([Vector3(500, 0, 0)])
	var szB = PackedVector3Array([Vector3(1, 1, 1)])

	var dataA = _make_point_data(posA, szA)
	var dataB = _make_point_data(posB, szB)

	var node = _run([dataA, dataB], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
