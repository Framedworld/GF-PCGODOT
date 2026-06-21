# transform_points_test.gd
class_name TransformPointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TransformPointsNode = preload("res://addons/flow_nodes_editor/nodes/transform_points.gd")
const TransformNodeSettings = preload("res://addons/flow_nodes_editor/nodes/transform_settings.gd")

func _make_point_data(positions: PackedVector3Array, rotations: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _make_settings(offset_min := Vector3.ZERO, offset_max := Vector3.ZERO, rotation_min := Vector3.ZERO, rotation_max := Vector3.ZERO, scale_min := Vector3.ONE, scale_max := Vector3.ONE, uniform_scale := true, rotation_local_space := false) -> TransformNodeSettings:
	var s := TransformNodeSettings.new()
	s.offset_min = offset_min
	s.offset_max = offset_max
	s.rotation_min = rotation_min
	s.rotation_max = rotation_max
	s.scale_min = scale_min
	s.scale_max = scale_max
	s.uniform_scale = uniform_scale
	s.rotation_local_space = rotation_local_space
	return s

func _run(input: FlowData.Data, settings: TransformNodeSettings) -> TransformPointsNode:
	var node := TransformPointsNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [input]
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: TransformPointsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_identity_no_offset_no_rotation_no_scale() -> void:
	var positions := PackedVector3Array([Vector3(1, 2, 3), Vector3(-5, 0, 10)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 45, 0)])
	var sizes := PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 2, 2)])
	var input := _make_point_data(positions, rotations, sizes)
	var s := _make_settings()
	var node = _run(input, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(positions)
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_array(rot_stream.container).is_equal(rotations)
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(sizes)
	node.free()

func test_deterministic_fixed_offset() -> void:
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 0)])
	var sizes := PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var input := _make_point_data(positions, rotations, sizes)
	var fixed_offset := Vector3(5, 3, 1)
	var s := _make_settings(fixed_offset, fixed_offset)
	var node = _run(input, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var expected := PackedVector3Array([Vector3(5, 3, 1), Vector3(15, 3, 1)])
	assert_array(pos_stream.container).is_equal(expected)
	node.free()

func test_deterministic_fixed_rotation_world_space() -> void:
	var positions := PackedVector3Array([Vector3(0, 0, 0)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0)])
	var sizes := PackedVector3Array([Vector3(1, 1, 1)])
	var input := _make_point_data(positions, rotations, sizes)
	var fixed_rot := Vector3(0, 90, 0)
	var s := _make_settings(Vector3.ZERO, Vector3.ZERO, fixed_rot, fixed_rot, Vector3.ONE, Vector3.ONE, true, false)
	var node = _run(input, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_array(rot_stream.container).is_equal(PackedVector3Array([Vector3(0, 90, 0)]))
	node.free()

func test_deterministic_uniform_scale() -> void:
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 1, 1)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 0)])
	var sizes := PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 2, 2)])
	var input := _make_point_data(positions, rotations, sizes)
	var fixed_scale := Vector3(3, 3, 3)
	var s := _make_settings(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, fixed_scale, fixed_scale, true)
	var node = _run(input, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(3, 3, 3), Vector3(6, 6, 6)]))
	node.free()

func test_deterministic_non_uniform_scale() -> void:
	var positions := PackedVector3Array([Vector3(0, 0, 0)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0)])
	var sizes := PackedVector3Array([Vector3(2, 4, 6)])
	var input := _make_point_data(positions, rotations, sizes)
	var fixed_scale := Vector3(2, 0.5, 3)
	var s := _make_settings(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, fixed_scale, fixed_scale, false)
	var node = _run(input, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(4, 2, 18)]))
	node.free()

func test_missing_input_error() -> void:
	var s := _make_settings()
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_position_stream_error() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrRotation, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3.ONE]), FlowDataScript.DataType.Vector)
	var s := _make_settings()
	var node = _run(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_preserves_extra_streams() -> void:
	var positions := PackedVector3Array([Vector3(1, 0, 0)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0)])
	var sizes := PackedVector3Array([Vector3(1, 1, 1)])
	var d := _make_point_data(positions, rotations, sizes)
	d.registerStream("density", PackedFloat32Array([0.75]), FlowDataScript.DataType.Float)
	d.registerStream("custom_color", PackedColorArray([Color.RED]), FlowDataScript.DataType.Color)
	var s := _make_settings()
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_array(density_stream.container).is_equal(PackedFloat32Array([0.75]))
	var color_stream = out.findStream("custom_color")
	assert_object(color_stream).is_not_null()
	assert_array(color_stream.container).is_equal(PackedColorArray([Color.RED]))
	node.free()

func test_single_point() -> void:
	var positions := PackedVector3Array([Vector3(0, 0, 0)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0)])
	var sizes := PackedVector3Array([Vector3(1, 1, 1)])
	var input := _make_point_data(positions, rotations, sizes)
	var s := _make_settings(Vector3(1, 0, 0), Vector3(1, 0, 0))
	var node = _run(input, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(1, 0, 0)]))
	node.free()

func test_random_seed_determinism() -> void:
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(10, 0, 0)])
	var rotations := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)])
	var sizes := PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var s1 := TransformNodeSettings.new()
	s1.offset_min = Vector3(-1, -1, -1)
	s1.offset_max = Vector3(1, 1, 1)
	s1.rotation_min = Vector3(-45, -45, -45)
	s1.rotation_max = Vector3(45, 45, 45)
	s1.scale_min = Vector3(0.5, 0.5, 0.5)
	s1.scale_max = Vector3(2, 2, 2)
	s1.uniform_scale = true
	s1.random_seed = 99999
	var s2 := TransformNodeSettings.new()
	s2.offset_min = s1.offset_min
	s2.offset_max = s1.offset_max
	s2.rotation_min = s1.rotation_min
	s2.rotation_max = s1.rotation_max
	s2.scale_min = s1.scale_min
	s2.scale_max = s1.scale_max
	s2.uniform_scale = s1.uniform_scale
	s2.random_seed = 99999
	var node1 = _run(_make_point_data(positions, rotations, sizes), s1)
	var node2 = _run(_make_point_data(positions, rotations, sizes), s2)
	assert_str(node1.err).is_empty()
	assert_str(node2.err).is_empty()
	var out1 = _output(node1)
	var out2 = _output(node2)
	assert_object(out1).is_not_null()
	assert_object(out2).is_not_null()
	var pos1 = out1.findStream(FlowData.AttrPosition)
	var pos2 = out2.findStream(FlowData.AttrPosition)
	assert_array(pos1.container).is_equal(pos2.container)
	node1.free()
	node2.free()
