# snap_to_grid_test.gd
class_name SnapToGridTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SnapToGridNode = preload("res://addons/flow_nodes_editor/nodes/snap_to_grid.gd")
const SnapToGridSettings = preload("res://addons/flow_nodes_editor/nodes/snap_to_grid_settings.gd")

func _make_point_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _make_full_transform_data(positions: PackedVector3Array, rotations: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> SnapToGridNode:
	var node = SnapToGridNode.new()
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

func test_snap_position_default_grid() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true
	s.snap_rotation = false
	s.snap_scale = false
	s.grid_size = Vector3(2.0, 2.0, 2.0)

	var positions := PackedVector3Array([
		Vector3(1.1, 3.7, -0.9),
		Vector3(5.0, 6.3, 2.8),
	])
	var in_data := _make_point_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
	var snapped: PackedVector3Array = pos_stream.container
	assert_float(snapped[0].x).is_equal_approx(2.0, 0.001)
	assert_float(snapped[0].y).is_equal_approx(4.0, 0.001)
	assert_float(snapped[0].z).is_equal_approx(0.0, 0.001)
	assert_float(snapped[1].x).is_equal_approx(6.0, 0.001)
	assert_float(snapped[1].y).is_equal_approx(6.0, 0.001)
	assert_float(snapped[1].z).is_equal_approx(2.0, 0.001)
	node.free()

func test_snap_position_non_uniform_grid() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true
	s.snap_rotation = false
	s.snap_scale = false
	s.grid_size = Vector3(5.0, 10.0, 3.0)

	var positions := PackedVector3Array([
		Vector3(7.0, 14.0, 7.0),
	])
	var in_data := _make_point_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var snapped: PackedVector3Array = pos_stream.container
	assert_float(snapped[0].x).is_equal_approx(5.0, 0.001)
	assert_float(snapped[0].y).is_equal_approx(10.0, 0.001)
	assert_float(snapped[0].z).is_equal_approx(6.0, 0.001)
	node.free()

func test_snap_rotation_uses_rotation_grid() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = false
	s.snap_rotation = true
	s.snap_scale = false
	s.grid_size = Vector3(2.0, 2.0, 2.0)
	s.rotation_grid_size = Vector3(45.0, 45.0, 45.0)

	var positions := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var rotations := PackedVector3Array([
		Vector3(22.0, 67.0, 10.0),
		Vector3(91.0, 200.0, -20.0),
	])
	var sizes := PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var in_data := _make_full_transform_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(2)
	var snapped: PackedVector3Array = rot_stream.container
	assert_float(snapped[0].x).is_equal_approx(0.0, 0.001)
	assert_float(snapped[0].y).is_equal_approx(45.0, 0.001)
	assert_float(snapped[0].z).is_equal_approx(0.0, 0.001)
	assert_float(snapped[1].x).is_equal_approx(90.0, 0.001)
	assert_float(snapped[1].y).is_equal_approx(180.0, 0.001)
	node.free()

func test_snap_scale_uses_scale_grid() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = false
	s.snap_rotation = false
	s.snap_scale = true
	s.grid_size = Vector3(2.0, 2.0, 2.0)
	s.scale_grid_size = Vector3(0.5, 0.5, 0.5)

	var positions := PackedVector3Array([Vector3.ZERO])
	var rotations := PackedVector3Array([Vector3.ZERO])
	var sizes := PackedVector3Array([Vector3(1.3, 2.7, 0.9)])
	var in_data := _make_full_transform_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var size_stream = out.findStream(FlowDataScript.AttrSize)
	assert_object(size_stream).is_not_null()
	var snapped: PackedVector3Array = size_stream.container
	assert_float(snapped[0].x).is_equal_approx(1.5, 0.001)
	assert_float(snapped[0].y).is_equal_approx(2.5, 0.001)
	assert_float(snapped[0].z).is_equal_approx(1.0, 0.001)
	node.free()

func test_rotation_grid_falls_back_to_grid_size_when_zero() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = false
	s.snap_rotation = true
	s.snap_scale = false
	s.grid_size = Vector3(90.0, 90.0, 90.0)
	s.rotation_grid_size = Vector3.ZERO

	var positions := PackedVector3Array([Vector3.ZERO])
	var rotations := PackedVector3Array([Vector3(45.0, 45.0, 45.0)])
	var sizes := PackedVector3Array([Vector3.ONE])
	var in_data := _make_full_transform_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	var snapped: PackedVector3Array = rot_stream.container
	assert_float(snapped[0].x).is_equal_approx(90.0, 0.001)
	assert_float(snapped[0].y).is_equal_approx(90.0, 0.001)
	assert_float(snapped[0].z).is_equal_approx(90.0, 0.001)
	node.free()

func test_snap_all_three_simultaneously() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true
	s.snap_rotation = true
	s.snap_scale = true
	s.grid_size = Vector3(1.0, 1.0, 1.0)
	s.rotation_grid_size = Vector3(30.0, 30.0, 30.0)
	s.scale_grid_size = Vector3(0.25, 0.25, 0.25)

	var positions := PackedVector3Array([Vector3(1.6, 2.4, 3.9)])
	var rotations := PackedVector3Array([Vector3(20.0, 50.0, 80.0)])
	var sizes := PackedVector3Array([Vector3(1.1, 2.3, 0.6)])
	var in_data := _make_full_transform_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var snapped_pos: PackedVector3Array = pos_stream.container
	assert_float(snapped_pos[0].x).is_equal_approx(2.0, 0.001)
	assert_float(snapped_pos[0].y).is_equal_approx(2.0, 0.001)
	assert_float(snapped_pos[0].z).is_equal_approx(4.0, 0.001)

	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	var snapped_rot: PackedVector3Array = rot_stream.container
	assert_float(snapped_rot[0].x).is_equal_approx(30.0, 0.001)
	assert_float(snapped_rot[0].y).is_equal_approx(60.0, 0.001)
	assert_float(snapped_rot[0].z).is_equal_approx(90.0, 0.001)

	var size_stream = out.findStream(FlowDataScript.AttrSize)
	assert_object(size_stream).is_not_null()
	var snapped_sz: PackedVector3Array = size_stream.container
	assert_float(snapped_sz[0].x).is_equal_approx(1.0, 0.001)
	assert_float(snapped_sz[0].y).is_equal_approx(2.25, 0.001)
	assert_float(snapped_sz[0].z).is_equal_approx(0.5, 0.001)
	node.free()

func test_missing_input_error() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_position_stream_error() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true
	s.snap_rotation = false
	s.snap_scale = false

	var d := FlowDataScript.Data.new()
	d.registerStream("custom", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_rotation_stream_error() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = false
	s.snap_rotation = true
	s.snap_scale = false

	var in_data := _make_point_data(PackedVector3Array([Vector3.ZERO]))
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_size_stream_error() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = false
	s.snap_rotation = false
	s.snap_scale = true

	var in_data := _make_point_data(PackedVector3Array([Vector3.ZERO]))
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_single_point_snaps_correctly() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true
	s.snap_rotation = false
	s.snap_scale = false
	s.grid_size = Vector3(3.0, 3.0, 3.0)

	var positions := PackedVector3Array([Vector3(1.0, 1.0, 1.0)])
	var in_data := _make_point_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	var snapped: PackedVector3Array = pos_stream.container
	assert_float(snapped[0].x).is_equal_approx(0.0, 0.001)
	assert_float(snapped[0].y).is_equal_approx(0.0, 0.001)
	assert_float(snapped[0].z).is_equal_approx(0.0, 0.001)
	node.free()

func test_zero_step_axis_leaves_value_unchanged() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true
	s.snap_rotation = false
	s.snap_scale = false
	s.grid_size = Vector3(2.0, 0.0, 2.0)

	var positions := PackedVector3Array([Vector3(1.1, 7.777, 1.9)])
	var in_data := _make_point_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var snapped: PackedVector3Array = pos_stream.container
	assert_float(snapped[0].x).is_equal_approx(2.0, 0.001)
	assert_float(snapped[0].y).is_equal_approx(7.777, 0.001)
	assert_float(snapped[0].z).is_equal_approx(2.0, 0.001)
	node.free()

func test_input_data_is_not_modified_in_place() -> void:
	var s = SnapToGridSettings.new()
	s.snap_position = true
	s.snap_rotation = false
	s.snap_scale = false
	s.grid_size = Vector3(2.0, 2.0, 2.0)

	var positions := PackedVector3Array([Vector3(1.1, 3.7, -0.9)])
	var in_data := _make_point_data(positions)
	var original_stream = in_data.findStream(FlowDataScript.AttrPosition)
	var original_x: float = original_stream.container[0].x

	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var still_original = in_data.findStream(FlowDataScript.AttrPosition)
	assert_float(still_original.container[0].x).is_equal_approx(original_x, 0.001)
	node.free()
