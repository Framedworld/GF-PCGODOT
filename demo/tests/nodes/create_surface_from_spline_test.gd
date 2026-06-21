# create_surface_from_spline_test.gd
class_name CreateSurfaceFromSplineTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const CreateSurfaceFromSplineNode = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_spline.gd")
const CreateSurfaceFromSplineSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_spline_settings.gd")

func _make_path_xz(x0: float, z0: float, x1: float, z1: float) -> Path3D:
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(x0, 0.0, z0))
	path.curve.add_point(Vector3(x1, 0.0, z0))
	path.curve.add_point(Vector3(x1, 0.0, z1))
	path.curve.add_point(Vector3(x0, 0.0, z1))
	path.curve.add_point(Vector3(x0, 0.0, z0))
	return path

func _make_path_xy(x0: float, y0: float, x1: float, y1: float) -> Path3D:
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(x0, y0, 0.0))
	path.curve.add_point(Vector3(x1, y0, 0.0))
	path.curve.add_point(Vector3(x1, y1, 0.0))
	path.curve.add_point(Vector3(x0, y1, 0.0))
	path.curve.add_point(Vector3(x0, y0, 0.0))
	return path

func _make_input(paths: Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var nodes: Array[Node] = []
	for p in paths:
		nodes.append(p)
	d.registerStream("node", nodes, FlowDataScript.DataType.NodePath)
	return d

func _run(in_data: FlowData.Data, settings) -> CreateSurfaceFromSplineNode:
	var node = CreateSurfaceFromSplineNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = in_data
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

func test_basic_xz_surface() -> void:
	var path := _make_path_xz(0.0, 0.0, 4.0, 4.0)
	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XZ
	s.minimum_thickness = 0.1
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.include_spline_ref = false

	var node = _run(_make_input([path]), s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(1)

	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_int(sizes.size()).is_equal(1)
	assert_bool(sizes[0].x > 0.0).is_true()
	assert_bool(sizes[0].z > 0.0).is_true()

	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_bool(area_stream.container[0] > 0.0).is_true()

	var perim_stream = out.findStream("surface_perimeter")
	assert_object(perim_stream).is_not_null()
	assert_bool(perim_stream.container[0] > 0.0).is_true()

	node.free()
	path.free()

func test_xy_plane_mode() -> void:
	var path := _make_path_xy(0.0, 0.0, 3.0, 3.0)
	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XY
	s.minimum_thickness = 0.1
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.include_spline_ref = false

	var node = _run(_make_input([path]), s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_bool(area_stream.container[0] > 0.0).is_true()

	node.free()
	path.free()

func test_multiple_paths_produce_multiple_surfaces() -> void:
	var pathA := _make_path_xz(0.0, 0.0, 2.0, 2.0)
	var pathB := _make_path_xz(5.0, 5.0, 8.0, 8.0)
	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XZ
	s.minimum_thickness = 0.1
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.include_spline_ref = false

	var node = _run(_make_input([pathA, pathB]), s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(2)

	var area_stream = out.findStream("surface_area")
	assert_object(area_stream).is_not_null()
	assert_int(area_stream.container.size()).is_equal(2)

	node.free()
	pathA.free()
	pathB.free()

func test_spline_ref_output_included() -> void:
	var path := _make_path_xz(0.0, 0.0, 4.0, 4.0)
	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XZ
	s.minimum_thickness = 0.1
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.include_spline_ref = true
	s.out_spline_attribute = "node"

	var node = _run(_make_input([path]), s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var ref_stream = out.findStream("node")
	assert_object(ref_stream).is_not_null()
	assert_int(ref_stream.container.size()).is_equal(1)
	assert_bool(ref_stream.container[0] == path).is_true()

	node.free()
	path.free()

func test_spline_ref_excluded_when_disabled() -> void:
	var path := _make_path_xz(0.0, 0.0, 4.0, 4.0)
	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XZ
	s.minimum_thickness = 0.1
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.include_spline_ref = false
	s.out_spline_attribute = "node"

	var node = _run(_make_input([path]), s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var ref_stream = out.findStream("node")
	assert_object(ref_stream).is_null()

	node.free()
	path.free()

func test_minimum_thickness_applied() -> void:
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(Vector3(0.0, 0.0, 0.0))
	path.curve.add_point(Vector3(5.0, 0.0, 0.0))
	path.curve.add_point(Vector3(5.0, 0.0, 0.0))

	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XZ
	s.minimum_thickness = 1.0
	s.out_area_attribute = ""
	s.out_perimeter_attribute = ""
	s.include_spline_ref = false

	var node = _run(_make_input([path]), s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_int(sizes.size()).is_equal(1)
	assert_bool(sizes[0].z >= 1.0).is_true()

	node.free()
	path.free()

func test_missing_input_produces_error() -> void:
	var s := CreateSurfaceFromSplineSettings.new()
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_wrong_stream_name_produces_error() -> void:
	var path := _make_path_xz(0.0, 0.0, 4.0, 4.0)
	var d := FlowDataScript.Data.new()
	var nodes: Array[Node] = [path]
	d.registerStream("wrong_stream", nodes, FlowDataScript.DataType.NodePath)

	var s := CreateSurfaceFromSplineSettings.new()
	s.spline_stream_attribute = "node"

	var node = _run(d, s)
	assert_str(node.err).is_not_empty()

	node.free()
	path.free()

func test_empty_stream_produces_empty_output() -> void:
	var d := FlowDataScript.Data.new()
	var nodes: Array[Node] = []
	d.registerStream("node", nodes, FlowDataScript.DataType.NodePath)

	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XZ
	s.minimum_thickness = 0.1
	s.out_area_attribute = "surface_area"
	s.out_perimeter_attribute = "surface_perimeter"
	s.include_spline_ref = false

	var node = _run(d, s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(0)

	node.free()

func test_optional_attributes_suppressed_when_name_empty() -> void:
	var path := _make_path_xz(0.0, 0.0, 4.0, 4.0)
	var s := CreateSurfaceFromSplineSettings.new()
	s.plane = CreateSurfaceFromSplineSettings.ePlane.XZ
	s.minimum_thickness = 0.1
	s.out_area_attribute = ""
	s.out_perimeter_attribute = ""
	s.include_spline_ref = false

	var node = _run(_make_input([path]), s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	assert_object(out.findStream("surface_area")).is_null()
	assert_object(out.findStream("surface_perimeter")).is_null()

	node.free()
	path.free()
