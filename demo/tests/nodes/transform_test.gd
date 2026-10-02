# transform_test.gd
class_name TransformTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TransformNode = preload("res://addons/flow_nodes_editor/nodes/transform.gd")
const TransformSettings = preload("res://addons/flow_nodes_editor/nodes/transform_settings.gd")

func _make_point_data(positions: PackedVector3Array, rotations: PackedVector3Array = PackedVector3Array(), sizes: PackedVector3Array = PackedVector3Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	if rotations.size() == positions.size():
		d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	else:
		var rots := PackedVector3Array()
		rots.resize(positions.size())
		d.registerStream(FlowData.AttrRotation, rots, FlowDataScript.DataType.Vector)
	if sizes.size() == positions.size():
		d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	else:
		var sz := PackedVector3Array()
		sz.resize(positions.size())
		sz.fill(Vector3.ONE)
		d.registerStream(FlowData.AttrSize, sz, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> TransformNode:
	var node = TransformNode.new()
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

func test_no_offset_no_rotation_no_scale_passthrough() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3.ZERO
	s.offset_max = Vector3.ZERO
	s.rotation_min = Vector3.ZERO
	s.rotation_max = Vector3.ZERO
	s.scale_min = Vector3.ONE
	s.scale_max = Vector3.ONE
	s.uniform_scale = false
	s.rotation_local_space = false

	var positions = PackedVector3Array([Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0)])
	var rotations = PackedVector3Array([Vector3(0.0, 45.0, 0.0), Vector3(0.0, 90.0, 0.0)])
	var sizes = PackedVector3Array([Vector3(2.0, 2.0, 2.0), Vector3(3.0, 3.0, 3.0)])
	var data = _make_point_data(positions, rotations, sizes)

	var node = _run([data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_float(pos_stream.container[0].x).is_equal_approx(1.0, 0.001)
	assert_float(pos_stream.container[0].y).is_equal_approx(2.0, 0.001)
	assert_float(pos_stream.container[0].z).is_equal_approx(3.0, 0.001)
	assert_float(pos_stream.container[1].x).is_equal_approx(4.0, 0.001)

	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_float(rot_stream.container[0].y).is_equal_approx(45.0, 0.001)

	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_float(size_stream.container[0].x).is_equal_approx(2.0, 0.001)

func test_translation_offset_within_range() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3(-1.0, -1.0, -1.0)
	s.offset_max = Vector3(1.0, 1.0, 1.0)
	s.rotation_min = Vector3.ZERO
	s.rotation_max = Vector3.ZERO
	s.scale_min = Vector3.ONE
	s.scale_max = Vector3.ONE
	s.uniform_scale = false
	s.rotation_local_space = false

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(5.0, 5.0, 5.0), Vector3(-3.0, 2.0, 1.0)])
	var data = _make_point_data(positions)

	var node = _run([data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(3)

	for i in pos_stream.container.size():
		var orig = positions[i]
		var moved = pos_stream.container[i]
		assert_float(moved.x).is_greater_equal(orig.x - 1.0)
		assert_float(moved.x).is_less_equal(orig.x + 1.0)
		assert_float(moved.y).is_greater_equal(orig.y - 1.0)
		assert_float(moved.y).is_less_equal(orig.y + 1.0)
		assert_float(moved.z).is_greater_equal(orig.z - 1.0)
		assert_float(moved.z).is_less_equal(orig.z + 1.0)

func test_rotation_world_space_within_range() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3.ZERO
	s.offset_max = Vector3.ZERO
	s.rotation_min = Vector3(0.0, -30.0, 0.0)
	s.rotation_max = Vector3(0.0, 30.0, 0.0)
	s.scale_min = Vector3.ONE
	s.scale_max = Vector3.ONE
	s.uniform_scale = false
	s.rotation_local_space = false

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.0, 1.0)])
	var data = _make_point_data(positions)

	var node = _run([data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_int(rot_stream.container.size()).is_equal(2)

	for i in rot_stream.container.size():
		var ry = rot_stream.container[i].y
		assert_float(ry).is_greater_equal(-30.0)
		assert_float(ry).is_less_equal(30.0)

func test_rotation_local_space() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3.ZERO
	s.offset_max = Vector3.ZERO
	s.rotation_min = Vector3(0.0, 10.0, 0.0)
	s.rotation_max = Vector3(0.0, 10.0, 0.0)
	s.scale_min = Vector3.ONE
	s.scale_max = Vector3.ONE
	s.uniform_scale = false
	s.rotation_local_space = true

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var rotations = PackedVector3Array([Vector3(0.0, 45.0, 0.0)])
	var data = _make_point_data(positions, rotations)

	var node_local = _run([data], s)
	assert_str(node_local.err).is_empty()
	var out_local = _output(node_local)
	assert_object(out_local).is_not_null()
	var rot_stream_local = out_local.findStream(FlowData.AttrRotation)
	assert_object(rot_stream_local).is_not_null()

	s.rotation_local_space = false
	var node_world = _run([data], s)
	assert_str(node_world.err).is_empty()
	var out_world = _output(node_world)
	assert_object(out_world).is_not_null()
	var rot_stream_world = out_world.findStream(FlowData.AttrRotation)
	assert_object(rot_stream_world).is_not_null()

	assert_float(rot_stream_world.container[0].y).is_equal_approx(55.0, 0.001)


func test_uniform_scale_within_range() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3.ZERO
	s.offset_max = Vector3.ZERO
	s.rotation_min = Vector3.ZERO
	s.rotation_max = Vector3.ZERO
	s.scale_min = Vector3(0.5, 0.5, 0.5)
	s.scale_max = Vector3(2.0, 2.0, 2.0)
	s.uniform_scale = true
	s.rotation_local_space = false

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0)])
	var sizes = PackedVector3Array([Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0)])
	var data = _make_point_data(positions, PackedVector3Array(), sizes)

	var node = _run([data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_int(size_stream.container.size()).is_equal(3)

	for i in size_stream.container.size():
		var sz = size_stream.container[i]
		assert_float(sz.x).is_equal_approx(sz.y, 0.001)
		assert_float(sz.y).is_equal_approx(sz.z, 0.001)
		assert_float(sz.x).is_greater_equal(0.5)
		assert_float(sz.x).is_less_equal(2.0)

func test_non_uniform_scale_within_range() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3.ZERO
	s.offset_max = Vector3.ZERO
	s.rotation_min = Vector3.ZERO
	s.rotation_max = Vector3.ZERO
	s.scale_min = Vector3(0.5, 1.0, 2.0)
	s.scale_max = Vector3(1.0, 2.0, 4.0)
	s.uniform_scale = false
	s.rotation_local_space = false

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(1.0, 2.0, 3.0)])
	var sizes = PackedVector3Array([Vector3(1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0)])
	var data = _make_point_data(positions, PackedVector3Array(), sizes)

	var node = _run([data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()

	for i in size_stream.container.size():
		var sz = size_stream.container[i]
		assert_float(sz.x).is_greater_equal(0.5)
		assert_float(sz.x).is_less_equal(1.0)
		assert_float(sz.y).is_greater_equal(1.0)
		assert_float(sz.y).is_less_equal(2.0)
		assert_float(sz.z).is_greater_equal(2.0)
		assert_float(sz.z).is_less_equal(4.0)

func test_single_point_transforms() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3(1.0, 0.0, 0.0)
	s.offset_max = Vector3(1.0, 0.0, 0.0)
	s.rotation_min = Vector3(0.0, 0.0, 0.0)
	s.rotation_max = Vector3(0.0, 0.0, 0.0)
	s.scale_min = Vector3(2.0, 2.0, 2.0)
	s.scale_max = Vector3(2.0, 2.0, 2.0)
	s.uniform_scale = false
	s.rotation_local_space = false

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var sizes = PackedVector3Array([Vector3(1.0, 1.0, 1.0)])
	var data = _make_point_data(positions, PackedVector3Array(), sizes)

	var node = _run([data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_float(pos_stream.container[0].x).is_equal_approx(1.0, 0.001)
	assert_float(pos_stream.container[0].y).is_equal_approx(0.0, 0.001)
	assert_float(pos_stream.container[0].z).is_equal_approx(0.0, 0.001)

	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_float(size_stream.container[0].x).is_equal_approx(2.0, 0.001)
	assert_float(size_stream.container[0].y).is_equal_approx(2.0, 0.001)
	assert_float(size_stream.container[0].z).is_equal_approx(2.0, 0.001)

func test_missing_input_error() -> void:
	var s = TransformSettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_missing_position_stream_error() -> void:
	var s = TransformSettings.new()
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrRotation, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSize, PackedVector3Array([Vector3.ONE]), FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_extra_streams_preserved() -> void:
	var s = TransformSettings.new()
	s.offset_min = Vector3.ZERO
	s.offset_max = Vector3.ZERO
	s.rotation_min = Vector3.ZERO
	s.rotation_max = Vector3.ZERO
	s.scale_min = Vector3.ONE
	s.scale_max = Vector3.ONE
	s.uniform_scale = false
	s.rotation_local_space = false

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0)])
	var data = _make_point_data(positions)
	data.registerStream("density", PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)

	var node = _run([data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(2)
	assert_float(density_stream.container[0]).is_equal_approx(0.5, 0.001)
	assert_float(density_stream.container[1]).is_equal_approx(0.8, 0.001)
