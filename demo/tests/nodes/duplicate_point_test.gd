# duplicate_point_test.gd
class_name DuplicatePointTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DuplicatePointNode = preload("res://addons/flow_nodes_editor/nodes/duplicate_point.gd")
const DuplicatePointSettings = preload("res://addons/flow_nodes_editor/nodes/duplicate_point_settings.gd")

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

func _run(inputs: Array, settings) -> DuplicatePointNode:
	var node = DuplicatePointNode.new()
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

func test_basic_duplicate_one_iteration() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 1
	s.offset = Vector3(0, 1, 0)
	s.offset_relative = false

	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(4)

func test_world_space_offset_applied_correctly() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 1
	s.offset = Vector3(0, 5, 0)
	s.offset_relative = false

	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_int(pos_stream.container.size()).is_equal(2)
	assert_float(pos_stream.container[0].y).is_equal_approx(0.0, 0.001)
	assert_float(pos_stream.container[1].y).is_equal_approx(5.0, 0.001)

func test_multiple_iterations_output_size() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 3
	s.offset = Vector3(1, 0, 0)
	s.offset_relative = false

	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 1)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_int(pos_stream.container.size()).is_equal(8)

func test_multiple_iterations_offset_accumulates() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 2
	s.offset = Vector3(10, 0, 0)
	s.offset_relative = false

	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_int(pos_stream.container.size()).is_equal(3)
	assert_float(pos_stream.container[0].x).is_equal_approx(0.0, 0.001)
	assert_float(pos_stream.container[1].x).is_equal_approx(10.0, 0.001)
	assert_float(pos_stream.container[2].x).is_equal_approx(20.0, 0.001)

func test_extra_attribute_streams_are_duplicated() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 1
	s.offset = Vector3(0, 1, 0)
	s.offset_relative = false

	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var source = _make_point_data(positions)
	source.registerStream("density", PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(4)
	assert_float(density_stream.container[0]).is_equal_approx(0.5, 0.001)
	assert_float(density_stream.container[1]).is_equal_approx(0.8, 0.001)
	assert_float(density_stream.container[2]).is_equal_approx(0.5, 0.001)
	assert_float(density_stream.container[3]).is_equal_approx(0.8, 0.001)

func test_rotation_and_size_preserved_in_duplicates() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 1
	s.offset = Vector3(0, 2, 0)
	s.offset_relative = false

	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var rotations = PackedVector3Array([Vector3(0, 1.5708, 0)])
	var source = _make_point_data(positions, rotations)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(2)
	assert_float(rot_stream.container[0].y).is_equal_approx(1.5708, 0.001)
	assert_float(rot_stream.container[1].y).is_equal_approx(1.5708, 0.001)

func test_iterations_clamped_to_minimum_one() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 0
	s.offset = Vector3(0, 1, 0)
	s.offset_relative = false

	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var source = _make_point_data(positions)

	var node = _run([source], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_int(pos_stream.container.size()).is_equal(2)

func test_missing_input_errors() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 1
	s.offset = Vector3(0, 1, 0)

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_input_without_required_streams_errors() -> void:
	var s = DuplicatePointSettings.new()
	s.iterations = 1

	var d := FlowDataScript.Data.new()
	d.registerStream("density", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
