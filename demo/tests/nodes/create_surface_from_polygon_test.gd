# create_surface_from_polygon_test.gd
class_name CreateSurfaceFromPolygonTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const CreateSurfaceFromPolygonNode = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_polygon.gd")
const CreateSurfaceFromPolygonSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_polygon_settings.gd")

func _make_polygon(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> CreateSurfaceFromPolygonNode:
	var node = CreateSurfaceFromPolygonNode.new()
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
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_basic_square_polygon_xz() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.XZ
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.out_point_count_attribute = "surface_point_count"

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(4, 0, 0),
		Vector3(4, 0, 4),
		Vector3(0, 0, 4),
	])
	var node = _run([_make_polygon(pts)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_float(area_stream.container[0]).is_equal_approx(16.0, 0.01)
	var count_stream = out.findStream("surface_point_count")
	assert_object(count_stream).is_not_null()
	assert_int(count_stream.container[0]).is_equal(4)

func test_output_position_is_aabb_center() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.XZ
	s.out_area_attribute = ""
	s.out_perimeter_attribute = ""
	s.out_point_count_attribute = ""

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(2, 0, 0),
		Vector3(2, 0, 6),
		Vector3(0, 0, 6),
	])
	var node = _run([_make_polygon(pts)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var center: Vector3 = pos_stream.container[0]
	assert_float(center.x).is_equal_approx(1.0, 0.01)
	assert_float(center.z).is_equal_approx(3.0, 0.01)
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_bool(rot_stream.container[0].is_equal_approx(Vector3.ZERO)).is_true()

func test_perimeter_triangle() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.XZ
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.out_point_count_attribute = "surface_point_count"

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(3, 0, 0),
		Vector3(0, 0, 4),
	])
	var node = _run([_make_polygon(pts)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_float(area_stream.container[0]).is_equal_approx(6.0, 0.01)
	var perim_stream = out.findStream("surface_perimeter")
	assert_object(perim_stream).is_not_null()
	assert_float(perim_stream.container[0]).is_equal_approx(12.0, 0.01)

func test_plane_xy() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.XY
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = ""
	s.out_point_count_attribute = ""

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(2, 0, 0),
		Vector3(2, 2, 0),
		Vector3(0, 2, 0),
	])
	var node = _run([_make_polygon(pts)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_float(area_stream.container[0]).is_equal_approx(4.0, 0.01)

func test_plane_yz() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.YZ
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = ""
	s.out_point_count_attribute = ""

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(0, 3, 0),
		Vector3(0, 3, 3),
		Vector3(0, 0, 3),
	])
	var node = _run([_make_polygon(pts)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_float(area_stream.container[0]).is_equal_approx(9.0, 0.01)

func test_missing_input_error() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_fewer_than_three_points_error() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.XZ

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
	])
	var node = _run([_make_polygon(pts)], s)
	assert_str(node.err).is_not_empty()

func test_group_attribute_splits_into_multiple_surfaces() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.XZ
	s.group_attribute = "group_id"
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = ""
	s.out_point_count_attribute = "surface_point_count"

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(2, 0, 0),
		Vector3(2, 0, 2),
		Vector3(0, 0, 2),
		Vector3(10, 0, 0),
		Vector3(14, 0, 0),
		Vector3(14, 0, 4),
		Vector3(10, 0, 4),
	])
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, pts, FlowDataScript.DataType.Vector)
	d.registerStream("group_id", PackedInt32Array([0, 0, 0, 0, 1, 1, 1, 1]), FlowDataScript.DataType.Int)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_float(area_stream.container[0]).is_equal_approx(4.0, 0.01)
	assert_float(area_stream.container[1]).is_equal_approx(16.0, 0.01)

func test_optional_output_attributes_suppressed_when_empty_string() -> void:
	var s = CreateSurfaceFromPolygonSettings.new()
	s.plane = CreateSurfaceFromPolygonSettings.ePlane.XZ
	s.out_area_attribute = ""
	s.out_perimeter_attribute = ""
	s.out_point_count_attribute = ""

	var pts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(4, 0, 0),
		Vector3(4, 0, 4),
		Vector3(0, 0, 4),
	])
	var node = _run([_make_polygon(pts)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("surface_area")).is_null()
	assert_object(out.findStream("surface_perimeter")).is_null()
	assert_object(out.findStream("surface_point_count")).is_null()
