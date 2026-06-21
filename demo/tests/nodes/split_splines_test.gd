# split_splines_test.gd
class_name SplitSplinesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SplitSplinesNode = preload("res://addons/flow_nodes_editor/nodes/split_splines.gd")
const SplitSplinesSettings = preload("res://addons/flow_nodes_editor/nodes/split_splines_settings.gd")

func _make_spline_data(paths: Array, stream_name: String = "node") -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, paths, FlowDataScript.DataType.NodePath)
	return d

func _run(inputs: Array, settings: SplitSplinesSettings) -> SplitSplinesNode:
	var node = SplitSplinesNode.new()
	node.name = "test_split_splines"
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

func _make_line_path(from: Vector3, to: Vector3) -> Path3D:
	var path = Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(from)
	path.curve.add_point(to)
	return path

func test_missing_input_returns_error() -> void:
	var s = SplitSplinesSettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_wrong_stream_name_returns_error() -> void:
	var path = _make_line_path(Vector3.ZERO, Vector3(10, 0, 0))
	var d := FlowDataScript.Data.new()
	d.registerStream("wrong_name", [path], FlowDataScript.DataType.NodePath)
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()
	path.free()

func test_basic_line_produces_segments() -> void:
	var path = _make_line_path(Vector3.ZERO, Vector3(10, 0, 0))
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 1.0
	s.include_spline_ref = false
	var node = _run([_make_spline_data([path])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_bool(positions.size() > 0).is_true()
	var rotations = out.getVector3Container(FlowDataScript.AttrRotation)
	assert_int(rotations.size()).is_equal(positions.size())
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_int(sizes.size()).is_equal(positions.size())
	node.free()
	path.free()

func test_segment_centers_are_midpoints() -> void:
	var path = _make_line_path(Vector3.ZERO, Vector3(10, 0, 0))
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 10.0
	s.include_spline_ref = false
	s.out_start_attribute = "segment_start"
	s.out_end_attribute = "segment_end"
	var node = _run([_make_spline_data([path])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_bool(positions.size() > 0).is_true()
	var start_stream = out.findStream("segment_start")
	assert_object(start_stream).is_not_null()
	var end_stream = out.findStream("segment_end")
	assert_object(end_stream).is_not_null()
	for i in range(positions.size()):
		var expected_center = (start_stream.container[i] + end_stream.container[i]) * 0.5
		assert_bool(positions[i].is_equal_approx(expected_center)).is_true()
	node.free()
	path.free()

func test_optional_index_streams() -> void:
	var path = _make_line_path(Vector3.ZERO, Vector3(5, 0, 0))
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 1.0
	s.include_spline_ref = false
	s.out_segment_index_attribute = "segment_index"
	s.out_spline_index_attribute = "spline_index"
	var node = _run([_make_spline_data([path])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var seg_stream = out.findStream("segment_index")
	assert_object(seg_stream).is_not_null()
	var spl_stream = out.findStream("spline_index")
	assert_object(spl_stream).is_not_null()
	for idx in seg_stream.container:
		assert_bool(idx >= 0).is_true()
	for idx in spl_stream.container:
		assert_int(idx).is_equal(0)
	node.free()
	path.free()

func test_multiple_splines_spline_index_increments() -> void:
	var path0 = _make_line_path(Vector3.ZERO, Vector3(4, 0, 0))
	var path1 = _make_line_path(Vector3(10, 0, 0), Vector3(14, 0, 0))
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 2.0
	s.include_spline_ref = false
	s.out_spline_index_attribute = "spline_index"
	var node = _run([_make_spline_data([path0, path1])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var spl_stream = out.findStream("spline_index")
	assert_object(spl_stream).is_not_null()
	var has_zero := false
	var has_one := false
	for idx in spl_stream.container:
		if idx == 0:
			has_zero = true
		if idx == 1:
			has_one = true
	assert_bool(has_zero).is_true()
	assert_bool(has_one).is_true()
	node.free()
	path0.free()
	path1.free()

func test_include_spline_ref_outputs_node_stream() -> void:
	var path = _make_line_path(Vector3.ZERO, Vector3(6, 0, 0))
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 2.0
	s.include_spline_ref = true
	s.out_spline_attribute = "node"
	var node = _run([_make_spline_data([path])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var ref_stream = out.findStream("node")
	assert_object(ref_stream).is_not_null()
	assert_bool(ref_stream.container.size() > 0).is_true()
	for ref in ref_stream.container:
		assert_bool(ref == path).is_true()
	node.free()
	path.free()

func test_empty_spline_list_produces_no_output_segments() -> void:
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 1.0
	s.include_spline_ref = false
	var node = _run([_make_spline_data([])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(0)
	node.free()

func test_segment_size_xy_applied_to_size_stream() -> void:
	var path = _make_line_path(Vector3.ZERO, Vector3(10, 0, 0))
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 5.0
	s.segment_size_xy = Vector2(3.0, 7.0)
	s.include_spline_ref = false
	var node = _run([_make_spline_data([path])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_bool(sizes.size() > 0).is_true()
	for sz in sizes:
		assert_float(sz.x).is_equal_approx(3.0, 0.001)
		assert_float(sz.y).is_equal_approx(7.0, 0.001)
		assert_bool(sz.z > 0.0).is_true()
	node.free()
	path.free()

func test_suppressed_optional_streams_not_registered() -> void:
	var path = _make_line_path(Vector3.ZERO, Vector3(5, 0, 0))
	var s = SplitSplinesSettings.new()
	s.spline_stream_attribute = "node"
	s.uniform_interval = 1.0
	s.include_spline_ref = false
	s.out_start_attribute = ""
	s.out_end_attribute = ""
	s.out_segment_index_attribute = ""
	s.out_spline_index_attribute = ""
	var node = _run([_make_spline_data([path])], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("segment_start")).is_null()
	assert_object(out.findStream("segment_end")).is_null()
	assert_object(out.findStream("segment_index")).is_null()
	assert_object(out.findStream("spline_index")).is_null()
	node.free()
	path.free()
