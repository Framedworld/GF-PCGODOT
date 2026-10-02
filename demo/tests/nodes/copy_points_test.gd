# copy_points_test.gd
class_name CopyPointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const CopyPointsNode = preload("res://addons/flow_nodes_editor/nodes/copy_points.gd")
const CopyNodeSettings = preload("res://addons/flow_nodes_editor/nodes/copy_settings.gd")

func _make_point_data(positions: PackedVector3Array, rotations: PackedVector3Array = PackedVector3Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	if rotations.size() > 0:
		d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	else:
		var rots := PackedVector3Array()
		rots.resize(positions.size())
		d.registerStream(FlowData.AttrRotation, rots, FlowDataScript.DataType.Vector)
	var sizes := PackedVector3Array()
	sizes.resize(positions.size())
	sizes.fill(Vector3.ONE)
	d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> CopyPointsNode:
	var node = CopyPointsNode.new()
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

func test_linear_copy_basic() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.LinearCopies
	s.num_copies = 3

	var positions = PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(6)

func test_linear_copy_single_element() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.LinearCopies
	s.num_copies = 4

	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_int(pos_stream.container.size()).is_equal(4)

func test_linear_copy_zero_copies_returns_empty() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.LinearCopies
	s.num_copies = 0

	var positions = PackedVector3Array([Vector3(1, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_linear_copy_with_translation_offset() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.LinearCopies
	s.num_copies = 2
	s.translation = Vector3(10, 0, 0)

	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_int(pos_stream.container.size()).is_equal(2)
	assert_float(pos_stream.container[0].x).is_equal_approx(0.0, 0.001)
	assert_float(pos_stream.container[1].x).is_equal_approx(10.0, 0.001)

func test_linear_copy_generates_copy_id() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.LinearCopies
	s.num_copies = 3
	s.generate_copy_id = "copy_index"

	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var id_stream = out.findStream("copy_index")
	assert_object(id_stream).is_not_null()
	assert_int(id_stream.container.size()).is_equal(3)
	assert_int(id_stream.container[0]).is_equal(0)
	assert_int(id_stream.container[1]).is_equal(1)
	assert_int(id_stream.container[2]).is_equal(2)

func test_source_to_targets_basic() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.SourceToTargets
	s.combine_source_with_target_transform = false
	s.inherit_target_scale = false

	var src_positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var source = _make_point_data(src_positions)

	var tgt_positions = PackedVector3Array([Vector3(5, 0, 0), Vector3(10, 0, 0), Vector3(15, 0, 0)])
	var targets = _make_point_data(tgt_positions)

	var node = _run([source, targets], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)

func test_source_to_targets_missing_targets_errors() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.SourceToTargets

	var src_positions = PackedVector3Array([Vector3(0, 0, 0)])
	var source = _make_point_data(src_positions)

	var node = _run([source, null], s)
	assert_str(node.err).is_not_empty()

func test_missing_source_input_errors() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.LinearCopies
	s.num_copies = 2

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_source_to_targets_cycle_selection() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.SourceToTargets
	s.source_selection = CopyNodeSettings.eSourceSelection.Cycle
	s.combine_source_with_target_transform = false
	s.inherit_target_scale = false

	var src_positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var source = _make_point_data(src_positions)

	var tgt_positions = PackedVector3Array([Vector3(5, 0, 0), Vector3(10, 0, 0), Vector3(15, 0, 0), Vector3(20, 0, 0)])
	var targets = _make_point_data(tgt_positions)

	var node = _run([source, targets], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)

func test_source_to_targets_random_deterministic_selection() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.SourceToTargets
	s.source_selection = CopyNodeSettings.eSourceSelection.RandomDeterministic
	s.random_seed = 42
	s.combine_source_with_target_transform = false
	s.inherit_target_scale = false

	var src_positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var source = _make_point_data(src_positions)

	var tgt_positions = PackedVector3Array([Vector3(5, 0, 0), Vector3(10, 0, 0), Vector3(15, 0, 0)])
	var targets = _make_point_data(tgt_positions)

	var node = _run([source, targets], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)

func test_source_to_targets_preserves_extra_streams() -> void:
	var s = CopyNodeSettings.new()
	s.mode = CopyNodeSettings.eMode.SourceToTargets
	s.combine_source_with_target_transform = false
	s.inherit_target_scale = false

	var source = _make_point_data(PackedVector3Array([Vector3(0, 0, 0)]))
	source.registerStream("density", PackedFloat32Array([0.5]), FlowDataScript.DataType.Float)

	var targets = _make_point_data(PackedVector3Array([Vector3(5, 0, 0), Vector3(10, 0, 0)]))

	var node = _run([source, targets], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(2)
