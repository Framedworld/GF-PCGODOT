# polygon_operation_test.gd
class_name PolygonOperationTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PolygonOperationNode = preload("res://addons/flow_nodes_editor/nodes/polygon_operation.gd")
const PolygonOperationSettings = preload("res://addons/flow_nodes_editor/nodes/clip_points_by_polygon_settings.gd")

func _make_points(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _make_polygon_points(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> PolygonOperationNode:
	var node = PolygonOperationNode.new()
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

func test_keep_inside_xz_plane() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XZ
	s.keep_inside = true

	var points = _make_points(PackedVector3Array([
		Vector3(0.5, 0.0, 0.5),
		Vector3(5.0, 0.0, 5.0),
		Vector3(0.5, 0.0, -0.5),
	]))

	var poly_pts = _make_polygon_points(PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(-1.0, 0.0, 1.0),
	]))

	var node = _run([points, poly_pts], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)

func test_keep_outside_xz_plane() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XZ
	s.keep_inside = false

	var points = _make_points(PackedVector3Array([
		Vector3(0.5, 0.0, 0.5),
		Vector3(5.0, 0.0, 5.0),
		Vector3(0.5, 0.0, -0.5),
	]))

	var poly_pts = _make_polygon_points(PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(-1.0, 0.0, 1.0),
	]))

	var node = _run([points, poly_pts], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)

func test_xy_plane_clipping() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XY
	s.keep_inside = true

	var points = _make_points(PackedVector3Array([
		Vector3(0.5, 0.5, 99.0),
		Vector3(5.0, 5.0, 0.0),
	]))

	var poly_pts = _make_polygon_points(PackedVector3Array([
		Vector3(-1.0, -1.0, 0.0),
		Vector3(1.0, -1.0, 0.0),
		Vector3(1.0, 1.0, 0.0),
		Vector3(-1.0, 1.0, 0.0),
	]))

	var node = _run([points, poly_pts], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)

func test_yz_plane_clipping() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.YZ
	s.keep_inside = true

	var points = _make_points(PackedVector3Array([
		Vector3(99.0, 0.5, 0.5),
		Vector3(0.0, 5.0, 5.0),
	]))

	var poly_pts = _make_polygon_points(PackedVector3Array([
		Vector3(0.0, -1.0, -1.0),
		Vector3(0.0, 1.0, -1.0),
		Vector3(0.0, 1.0, 1.0),
		Vector3(0.0, -1.0, 1.0),
	]))

	var node = _run([points, poly_pts], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)

func test_missing_points_input_error() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XZ
	s.keep_inside = true

	var node = _run([null, null], s)
	assert_str(node.err).is_not_empty()

func test_empty_points_passthrough() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XZ
	s.keep_inside = true

	var empty_points = FlowDataScript.Data.new()

	var poly_pts = _make_polygon_points(PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(-1.0, 0.0, 1.0),
	]))

	var node = _run([empty_points, poly_pts], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_no_polygon_source_error() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XZ
	s.keep_inside = true
	s.polygon_node_path = NodePath()

	var points = _make_points(PackedVector3Array([
		Vector3(0.5, 0.0, 0.5),
	]))

	var node = _run([points, null], s)
	assert_str(node.err).is_not_empty()

func test_points_without_position_stream_error() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XZ
	s.keep_inside = true

	var bad_points = FlowDataScript.Data.new()
	bad_points.registerStream("color", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)

	var poly_pts = _make_polygon_points(PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(-1.0, 0.0, 1.0),
	]))

	var node = _run([bad_points, poly_pts], s)
	assert_str(node.err).is_not_empty()

func test_all_points_clipped_out() -> void:
	var s = PolygonOperationSettings.new()
	s.plane = PolygonOperationSettings.ePlane.XZ
	s.keep_inside = true

	var points = _make_points(PackedVector3Array([
		Vector3(10.0, 0.0, 10.0),
		Vector3(20.0, 0.0, 20.0),
	]))

	var poly_pts = _make_polygon_points(PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, -1.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(-1.0, 0.0, 1.0),
	]))

	var node = _run([points, poly_pts], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
