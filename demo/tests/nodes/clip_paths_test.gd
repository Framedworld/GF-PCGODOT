# clip_paths_test.gd
class_name ClipPathsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ClipPathsNode = preload("res://addons/flow_nodes_editor/nodes/clip_paths.gd")
const ClipPathsSettings = preload("res://addons/flow_nodes_editor/nodes/clip_points_by_polygon_settings.gd")

func _make_points(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _make_polygon_points(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> ClipPathsNode:
	var node = ClipPathsNode.new()
	node.name = "test_clip_paths"
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
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_clips_points_inside_polygon_xz() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XZ
	s.keep_inside = true

	var polygon := PackedVector3Array([
		Vector3(-10, 0, -10),
		Vector3(10, 0, -10),
		Vector3(10, 0, 10),
		Vector3(-10, 0, 10),
	])
	var polygon_data := _make_polygon_points(polygon)

	var points := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(5, 0, 5),
		Vector3(20, 0, 20),
		Vector3(-20, 0, -20),
	])
	var points_data := _make_points(points)

	var node = _run([points_data, polygon_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)

func test_clips_points_outside_polygon() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XZ
	s.keep_inside = false

	var polygon := PackedVector3Array([
		Vector3(-5, 0, -5),
		Vector3(5, 0, -5),
		Vector3(5, 0, 5),
		Vector3(-5, 0, 5),
	])
	var polygon_data := _make_polygon_points(polygon)

	var points := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(3, 0, 3),
		Vector3(20, 0, 20),
		Vector3(-20, 0, -20),
	])
	var points_data := _make_points(points)

	var node = _run([points_data, polygon_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)

func test_empty_points_passthrough() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XZ
	s.keep_inside = true

	var polygon := PackedVector3Array([
		Vector3(-10, 0, -10),
		Vector3(10, 0, -10),
		Vector3(10, 0, 10),
		Vector3(-10, 0, 10),
	])
	var polygon_data := _make_polygon_points(polygon)

	var empty_points := FlowDataScript.Data.new()
	var node = _run([empty_points, polygon_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_missing_points_input_error() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XZ
	s.keep_inside = true

	var node = _run([null, null], s)
	assert_str(node.err).is_not_empty()

func test_no_position_stream_error() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XZ
	s.keep_inside = true

	var bad_points := FlowDataScript.Data.new()
	bad_points.registerStream("color", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)

	var polygon := PackedVector3Array([
		Vector3(-10, 0, -10),
		Vector3(10, 0, -10),
		Vector3(10, 0, 10),
		Vector3(-10, 0, 10),
	])
	var polygon_data := _make_polygon_points(polygon)

	var node = _run([bad_points, polygon_data], s)
	assert_str(node.err).is_not_empty()

func test_no_polygon_input_and_no_path_setting_error() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XZ
	s.keep_inside = true
	s.polygon_node_path = NodePath()

	var points := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(5, 0, 5),
	])
	var points_data := _make_points(points)

	var node = _run([points_data, null], s)
	assert_str(node.err).is_not_empty()

func test_clip_on_xy_plane() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XY
	s.keep_inside = true

	var polygon := PackedVector3Array([
		Vector3(-10, -10, 0),
		Vector3(10, -10, 0),
		Vector3(10, 10, 0),
		Vector3(-10, 10, 0),
	])
	var polygon_data := _make_polygon_points(polygon)

	var points := PackedVector3Array([
		Vector3(0, 0, 999),
		Vector3(5, 5, -999),
		Vector3(50, 50, 0),
	])
	var points_data := _make_points(points)

	var node = _run([points_data, polygon_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)

func test_clip_on_yz_plane() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.YZ
	s.keep_inside = true

	var polygon := PackedVector3Array([
		Vector3(0, -10, -10),
		Vector3(0, 10, -10),
		Vector3(0, 10, 10),
		Vector3(0, -10, 10),
	])
	var polygon_data := _make_polygon_points(polygon)

	var points := PackedVector3Array([
		Vector3(999, 0, 0),
		Vector3(-999, 5, 5),
		Vector3(0, 50, 50),
	])
	var points_data := _make_points(points)

	var node = _run([points_data, polygon_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)

func test_all_points_outside_polygon_returns_empty() -> void:
	var s = ClipPathsSettings.new()
	s.plane = ClipPathsSettings.ePlane.XZ
	s.keep_inside = true

	var polygon := PackedVector3Array([
		Vector3(-1, 0, -1),
		Vector3(1, 0, -1),
		Vector3(1, 0, 1),
		Vector3(-1, 0, 1),
	])
	var polygon_data := _make_polygon_points(polygon)

	var points := PackedVector3Array([
		Vector3(100, 0, 100),
		Vector3(-100, 0, -100),
		Vector3(200, 0, 0),
	])
	var points_data := _make_points(points)

	var node = _run([points_data, polygon_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(0)
