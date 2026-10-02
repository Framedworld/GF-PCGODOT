# self_pruning_test.gd
class_name SelfPruningTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SelfPruningNode = preload("res://addons/flow_nodes_editor/nodes/self_pruning.gd")
const SelfPruningSettings = preload("res://addons/flow_nodes_editor/nodes/self_pruning_settings.gd")

func _make_point_data(positions: PackedVector3Array, sizes: PackedVector3Array = PackedVector3Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	if sizes.size() > 0:
		d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings: SelfPruningSettings) -> SelfPruningNode:
	var node = SelfPruningNode.new()
	node.name = "self_pruning_test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: SelfPruningNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_null_input_sets_error() -> void:
	var s = SelfPruningSettings.new()
	s.mode = SelfPruningSettings.ePruneMode.BoundsOverlap
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_well_separated_points_all_kept() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
		Vector3(0.0, 100.0, 0.0),
	])
	var sizes = PackedVector3Array([
		Vector3.ONE,
		Vector3.ONE,
		Vector3.ONE,
	])
	var s = SelfPruningSettings.new()
	s.mode = SelfPruningSettings.ePruneMode.BoundsOverlap
	s.keep_self_intersections = false
	var node = _run([_make_point_data(positions, sizes)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)

func test_overlapping_points_pruned() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.1, 0.0, 0.0),
		Vector3(0.2, 0.0, 0.0),
	])
	var sizes = PackedVector3Array([
		Vector3(2.0, 2.0, 2.0),
		Vector3(2.0, 2.0, 2.0),
		Vector3(2.0, 2.0, 2.0),
	])
	var s = SelfPruningSettings.new()
	s.mode = SelfPruningSettings.ePruneMode.BoundsOverlap
	s.keep_self_intersections = false
	var node = _run([_make_point_data(positions, sizes)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_less(3)

func test_grid_cell_prune_removes_duplicates() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.2, 0.0, 0.0),
		Vector3(50.0, 0.0, 0.0),
	])
	var s = SelfPruningSettings.new()
	s.mode = SelfPruningSettings.ePruneMode.GridCell
	s.cell_size = 1.0
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)

func test_grid_cell_prune_invalid_cell_size_sets_error() -> void:
	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var s = SelfPruningSettings.new()
	s.mode = SelfPruningSettings.ePruneMode.GridCell
	s.cell_size = 0.0
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_not_empty()

func test_output_preserves_other_streams() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
	])
	var sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var d = _make_point_data(positions, sizes)
	d.registerStream("density", PackedFloat32Array([0.9, 0.7]), FlowDataScript.DataType.Float)
	var s = SelfPruningSettings.new()
	s.mode = SelfPruningSettings.ePruneMode.BoundsOverlap
	s.keep_self_intersections = false
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(2)
