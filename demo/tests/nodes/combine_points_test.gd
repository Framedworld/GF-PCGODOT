# combine_points_test.gd
class_name CombinePointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const CombinePointsNode = preload("res://addons/flow_nodes_editor/nodes/combine_points.gd")
const CombinePointsSettings = preload("res://addons/flow_nodes_editor/nodes/combine_points_settings.gd")

func _make_point_data(positions: PackedVector3Array, sizes: PackedVector3Array = PackedVector3Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, PackedVector3Array(), FlowDataScript.DataType.Vector)
	if sizes.size() > 0:
		d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _run(input: FlowData.Data) -> CombinePointsNode:
	var node = CombinePointsNode.new()
	node.name = "test_combine_points"
	node.settings = CombinePointsSettings.new()
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: CombinePointsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_null_input_returns_empty_data() -> void:
	var node = _run(null)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_empty_data_returns_empty_data() -> void:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(0)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_missing_position_stream_sets_error() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("color", PackedColorArray([Color(1, 0, 0)]), FlowDataScript.DataType.Color)
	var node = _run(d)
	assert_str(node.err).is_not_empty()
	node.free()

func test_single_point_no_size() -> void:
	var positions = PackedVector3Array([Vector3(2.0, 4.0, 6.0)])
	var d = _make_point_data(positions)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(2.0, 4.0, 6.0)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3.ZERO]))
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_array(rot_stream.container).is_equal(PackedVector3Array([Vector3.ZERO]))
	node.free()

func test_multiple_points_no_size_computes_aabb_center() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		Vector3(0.0, 6.0, 0.0),
		Vector3(0.0, 0.0, 4.0)
	])
	var d = _make_point_data(positions)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(5.0, 3.0, 2.0)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(10.0, 6.0, 4.0)]))
	node.free()

func test_points_with_sizes_expand_bounds() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0)
	])
	var sizes = PackedVector3Array([
		Vector3(2.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0)
	])
	var d = _make_point_data(positions, sizes)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	# min_pos = (-1,0,0), max_pos = (11,0,0) => center=(5,0,0), size=(12,0,0)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(5.0, 0.0, 0.0)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(12.0, 0.0, 0.0)]))
	node.free()

func test_broadcast_size_stream() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(4.0, 0.0, 0.0)
	])
	var sizes = PackedVector3Array([Vector3(2.0, 2.0, 2.0)])
	var d = _make_point_data(positions, sizes)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	# point 0: pos=(0,0,0) size=(2,2,2) => min=(-1,-1,-1) max=(1,1,1)
	# point 1: pos=(4,0,0) size=(2,2,2) broadcast => min=(3,-1,-1) max=(5,1,1)
	# combined min=(-1,-1,-1) max=(5,1,1) => center=(2,0,0) size=(6,2,2)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(2.0, 0.0, 0.0)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(6.0, 2.0, 2.0)]))
	node.free()

func test_non_spatial_stream_carries_first_point_value() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0)
	])
	var d = _make_point_data(positions)
	d.registerStream("density", PackedFloat32Array([0.9, 0.5, 0.1]), FlowDataScript.DataType.Float)
	d.registerStream("color", PackedColorArray([Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]), FlowDataScript.DataType.Color)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(1)
	assert_float(density_stream.container[0]).is_equal_approx(0.9, 0.001)
	var color_stream = out.findStream("color")
	assert_object(color_stream).is_not_null()
	assert_int(color_stream.container.size()).is_equal(1)
	assert_array(color_stream.container).is_equal(PackedColorArray([Color(1, 0, 0)]))
	node.free()

func test_single_point_with_size_center_and_size_correct() -> void:
	var positions = PackedVector3Array([Vector3(5.0, 10.0, 15.0)])
	var sizes = PackedVector3Array([Vector3(4.0, 6.0, 8.0)])
	var d = _make_point_data(positions, sizes)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	# min = (5-2, 10-3, 15-4) = (3, 7, 11), max = (5+2, 10+3, 15+4) = (7, 13, 19)
	# center = (5, 10, 15), size = (4, 6, 8)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(5.0, 10.0, 15.0)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(4.0, 6.0, 8.0)]))
	node.free()

func test_output_rotation_always_zero() -> void:
	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0)])
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, PackedVector3Array([Vector3(45.0, 90.0, 30.0), Vector3(10.0, 20.0, 0.0)]), FlowDataScript.DataType.Vector)
	var node = _run(d)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_array(rot_stream.container).is_equal(PackedVector3Array([Vector3.ZERO]))
	node.free()
