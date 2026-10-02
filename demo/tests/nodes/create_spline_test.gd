# create_spline_test.gd
class_name CreateSplineTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const CreateSplineNode = preload("res://addons/flow_nodes_editor/nodes/create_spline.gd")
const CreateSplineSettings = preload("res://addons/flow_nodes_editor/nodes/create_spline_settings.gd")

func _make_point_data(positions: PackedVector3Array, rotations: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, in_tree: bool = true) -> CreateSplineNode:
	var node = CreateSplineNode.new()
	node.name = "test_create_spline"
	node.settings = CreateSplineSettings.new()
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	if in_tree:
		add_child(dummy)
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	if in_tree:
		dummy.queue_free()
	else:
		dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_basic_line_three_points() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(10, 0, 0)])
	var rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE])
	var in_data = _make_point_data(positions, rotations, sizes)

	var node = _run([in_data])
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var stream = out.findStream("node")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)

	var path: Path3D = stream.container[0]
	assert_object(path).is_not_null()
	assert_bool(path is Path3D).is_true()
	assert_int(path.curve.point_count).is_equal(3)
	assert_bool(path.curve.get_point_position(0).is_equal_approx(Vector3(0, 0, 0))).is_true()
	assert_bool(path.curve.get_point_position(1).is_equal_approx(Vector3(5, 0, 0))).is_true()
	assert_bool(path.curve.get_point_position(2).is_equal_approx(Vector3(10, 0, 0))).is_true()

func test_tangents_computed_for_middle_points() -> void:
	var positions = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(4, 0, 0),
		Vector3(8, 0, 0),
		Vector3(12, 0, 0)
	])
	var rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE, Vector3.ONE])
	var in_data = _make_point_data(positions, rotations, sizes)

	var node = _run([in_data])
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("node")
	assert_object(stream).is_not_null()

	var path: Path3D = stream.container[0]
	assert_int(path.curve.point_count).is_equal(4)

	var in_tan_first: Vector3 = path.curve.get_point_in(0)
	var out_tan_first: Vector3 = path.curve.get_point_out(0)
	assert_bool(in_tan_first.is_equal_approx(Vector3.ZERO)).is_true()
	assert_bool(out_tan_first.is_equal_approx(Vector3.ZERO)).is_true()

	var in_tan_mid: Vector3 = path.curve.get_point_in(1)
	var out_tan_mid: Vector3 = path.curve.get_point_out(1)
	assert_bool(in_tan_mid.length() > 0.0).is_true()
	assert_bool(out_tan_mid.length() > 0.0).is_true()
	assert_bool(in_tan_mid.is_equal_approx(-out_tan_mid)).is_true()

	var in_tan_last: Vector3 = path.curve.get_point_in(3)
	var out_tan_last: Vector3 = path.curve.get_point_out(3)
	assert_bool(in_tan_last.is_equal_approx(Vector3.ZERO)).is_true()
	assert_bool(out_tan_last.is_equal_approx(Vector3.ZERO)).is_true()

func test_single_point_produces_path_with_one_point() -> void:
	var positions = PackedVector3Array([Vector3(3, 7, -2)])
	var rotations = PackedVector3Array([Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE])
	var in_data = _make_point_data(positions, rotations, sizes)

	var node = _run([in_data])
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("node")
	assert_object(stream).is_not_null()

	var path: Path3D = stream.container[0]
	assert_int(path.curve.point_count).is_equal(1)
	assert_bool(path.curve.get_point_position(0).is_equal_approx(Vector3(3, 7, -2))).is_true()

func test_two_points_endpoints_have_zero_tangents() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 2, 3)])
	var rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var in_data = _make_point_data(positions, rotations, sizes)

	var node = _run([in_data])
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("node")
	assert_object(stream).is_not_null()

	var path: Path3D = stream.container[0]
	assert_int(path.curve.point_count).is_equal(2)
	assert_bool(path.curve.get_point_in(0).is_equal_approx(Vector3.ZERO)).is_true()
	assert_bool(path.curve.get_point_out(0).is_equal_approx(Vector3.ZERO)).is_true()
	assert_bool(path.curve.get_point_in(1).is_equal_approx(Vector3.ZERO)).is_true()
	assert_bool(path.curve.get_point_out(1).is_equal_approx(Vector3.ZERO)).is_true()

func test_missing_input_sets_error() -> void:
	var node = _run([null])
	assert_str(node.err).is_not_empty()

func test_missing_transform_streams_sets_error() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("some_attr", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	var node = _run([d])
	assert_str(node.err).is_not_empty()

func test_no_scene_tree_sets_error() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var in_data = _make_point_data(positions, rotations, sizes)

	var node = _run([in_data], false)
	assert_str(node.err).is_not_empty()

func test_output_registered_as_node_path_stream() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(4, 0, 0)])
	var rotations = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE])
	var in_data = _make_point_data(positions, rotations, sizes)

	var node = _run([in_data])
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var stream = out.findStream("node")
	assert_object(stream).is_not_null()
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.NodePath)
	assert_int(stream.container.size()).is_equal(1)

func test_large_point_cloud_produces_correct_count() -> void:
	var count := 50
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var sizes := PackedVector3Array()
	for i in range(count):
		positions.append(Vector3(i * 1.0, 0, 0))
		rotations.append(Vector3.ZERO)
		sizes.append(Vector3.ONE)
	var in_data = _make_point_data(positions, rotations, sizes)

	var node = _run([in_data])
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("node")
	assert_object(stream).is_not_null()

	var path: Path3D = stream.container[0]
	assert_int(path.curve.point_count).is_equal(count)
	assert_bool(path.curve.get_point_position(0).is_equal_approx(Vector3(0, 0, 0))).is_true()
	assert_bool(path.curve.get_point_position(count - 1).is_equal_approx(Vector3((count - 1) * 1.0, 0, 0))).is_true()
