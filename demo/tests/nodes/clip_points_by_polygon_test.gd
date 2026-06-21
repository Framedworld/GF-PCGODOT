# clip_points_by_polygon_test.gd
class_name ClipPointsByPolygonTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ClipPointsByPolygonNode = preload("res://addons/flow_nodes_editor/nodes/clip_points_by_polygon.gd")
const ClipPointsByPolygonSettings = preload("res://addons/flow_nodes_editor/nodes/clip_points_by_polygon_settings.gd")

func _make_points(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	return d

func _make_polygon_points(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> ClipPointsByPolygonNode:
	var node = ClipPointsByPolygonNode.new()
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

func _make_settings(plane: int = ClipPointsByPolygonSettings.ePlane.XZ, keep_inside: bool = true) -> ClipPointsByPolygonSettings:
	var s = ClipPointsByPolygonSettings.new()
	s.plane = plane
	s.keep_inside = keep_inside
	return s

# A square polygon on XZ plane centered at origin, side 4 (from -2 to +2 on X and Z)
func _square_xz_polygon() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(-2.0, 0.0, -2.0),
		Vector3( 2.0, 0.0, -2.0),
		Vector3( 2.0, 0.0,  2.0),
		Vector3(-2.0, 0.0,  2.0),
	])

func test_keep_inside_xz_plane() -> void:
	var points := _make_points(PackedVector3Array([
		Vector3(0.0, 5.0, 0.0),
		Vector3(3.0, 5.0, 3.0),
		Vector3(1.0, 0.0, 1.0),
		Vector3(-1.5, 0.0, -1.5),
		Vector3(2.5, 0.0, 2.5),
	]))
	var polygon := _make_polygon_points(_square_xz_polygon())
	var s := _make_settings(ClipPointsByPolygonSettings.ePlane.XZ, true)
	var node := _run([points, polygon], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(3)
	assert_bool(Vector3(0.0, 5.0, 0.0) in pos).is_true()
	assert_bool(Vector3(1.0, 0.0, 1.0) in pos).is_true()
	assert_bool(Vector3(-1.5, 0.0, -1.5) in pos).is_true()
	node.free()

func test_keep_outside_xz_plane() -> void:
	var points := _make_points(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(3.0, 0.0, 3.0),
		Vector3(5.0, 0.0, 5.0),
	]))
	var polygon := _make_polygon_points(_square_xz_polygon())
	var s := _make_settings(ClipPointsByPolygonSettings.ePlane.XZ, false)
	var node := _run([points, polygon], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(2)
	assert_bool(Vector3(3.0, 0.0, 3.0) in pos).is_true()
	assert_bool(Vector3(5.0, 0.0, 5.0) in pos).is_true()
	node.free()

func test_keep_inside_xy_plane() -> void:
	var square_xy := PackedVector3Array([
		Vector3(-2.0, -2.0, 0.0),
		Vector3( 2.0, -2.0, 0.0),
		Vector3( 2.0,  2.0, 0.0),
		Vector3(-2.0,  2.0, 0.0),
	])
	var points := _make_points(PackedVector3Array([
		Vector3(0.0, 0.0, 99.0),
		Vector3(3.0, 3.0, 0.0),
		Vector3(1.0, 1.0, 50.0),
	]))
	var polygon := _make_polygon_points(square_xy)
	var s := _make_settings(ClipPointsByPolygonSettings.ePlane.XY, true)
	var node := _run([points, polygon], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(2)
	node.free()

func test_keep_inside_yz_plane() -> void:
	var square_yz := PackedVector3Array([
		Vector3(0.0, -2.0, -2.0),
		Vector3(0.0,  2.0, -2.0),
		Vector3(0.0,  2.0,  2.0),
		Vector3(0.0, -2.0,  2.0),
	])
	var points := _make_points(PackedVector3Array([
		Vector3(99.0, 0.0, 0.0),
		Vector3(0.0, 3.0, 3.0),
		Vector3(50.0, 1.0, 1.0),
	]))
	var polygon := _make_polygon_points(square_yz)
	var s := _make_settings(ClipPointsByPolygonSettings.ePlane.YZ, true)
	var node := _run([points, polygon], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(2)
	node.free()

func test_empty_points_passes_through() -> void:
	var empty_points := FlowDataScript.Data.new()
	var s := _make_settings()
	var node := _run([empty_points, null], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_missing_points_input_error() -> void:
	var s := _make_settings()
	var node := _run([null, null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_no_polygon_provided_error() -> void:
	var points := _make_points(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 1.0),
	]))
	var s := _make_settings()
	var node := _run([points, null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_points_missing_position_stream_error() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("color", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)
	var polygon := _make_polygon_points(_square_xz_polygon())
	var s := _make_settings()
	var node := _run([d, polygon], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_additional_streams_preserved() -> void:
	var positions := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(3.0, 0.0, 3.0),
		Vector3(1.0, 0.0, 1.0),
	])
	var colors := PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	d.registerStream("color", colors, FlowDataScript.DataType.Color)
	var polygon := _make_polygon_points(_square_xz_polygon())
	var s := _make_settings(ClipPointsByPolygonSettings.ePlane.XZ, true)
	var node := _run([d, polygon], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(2)
	var color_stream = out.findStream("color")
	assert_object(color_stream).is_not_null()
	assert_int(color_stream.container.size()).is_equal(2)
	node.free()

func test_polygon_with_fewer_than_three_points_error() -> void:
	var points := _make_points(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 1.0),
	]))
	var too_small_polygon := _make_polygon_points(PackedVector3Array([
		Vector3(-1.0, 0.0, -1.0),
		Vector3( 1.0, 0.0, -1.0),
	]))
	var s := _make_settings()
	var node := _run([points, too_small_polygon], s)
	assert_str(node.err).is_not_empty()
	node.free()
