# subdivide_segment_test.gd
class_name SubdivideSegmentTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SubdivideSegmentNode = preload("res://addons/flow_nodes_editor/nodes/subdivide_segment.gd")
const SubdivideSegmentSettings = preload("res://addons/flow_nodes_editor/nodes/subdivide_segment_settings.gd")

func _make_segments_data(starts: PackedVector3Array, ends: PackedVector3Array, start_attr: String = "segment_start", end_attr: String = "segment_end") -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(start_attr, starts, FlowDataScript.DataType.Vector)
	d.registerStream(end_attr, ends, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> SubdivideSegmentNode:
	var node = SubdivideSegmentNode.new()
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

func test_segments_mode_target_count() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.segment_start_attribute = "segment_start"
	s.segment_end_attribute = "segment_end"
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 4
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = "segment_index"
	s.out_t_start_attribute = "t_start"
	s.out_t_end_attribute = "t_end"

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(8, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(4)

	var len_stream = out.findStream("length")
	assert_object(len_stream).is_not_null()
	assert_int(len_stream.container.size()).is_equal(4)
	assert_float(len_stream.container[0]).is_equal_approx(2.0, 0.001)
	assert_float(len_stream.container[3]).is_equal_approx(2.0, 0.001)

	var idx_stream = out.findStream("segment_index")
	assert_object(idx_stream).is_not_null()
	assert_int(idx_stream.container[0]).is_equal(0)
	assert_int(idx_stream.container[3]).is_equal(3)

	var t_start_stream = out.findStream("t_start")
	assert_object(t_start_stream).is_not_null()
	assert_float(t_start_stream.container[0]).is_equal_approx(0.0, 0.001)

	var t_end_stream = out.findStream("t_end")
	assert_object(t_end_stream).is_not_null()
	assert_float(t_end_stream.container[3]).is_equal_approx(1.0, 0.001)


func test_segments_mode_module_lengths_stretch() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.MODULE_LENGTHS
	s.fit_mode = SubdivideSegmentSettings.eFitMode.STRETCH
	s.module_lengths = PackedFloat32Array([1.0, 2.0])
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = "segment_index"
	s.out_t_start_attribute = "t_start"
	s.out_t_end_attribute = "t_end"

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(9, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_bool(pos_stream.container.size() > 0).is_true()

	var len_stream = out.findStream("length")
	assert_object(len_stream).is_not_null()
	var total_len: float = 0.0
	for l in len_stream.container:
		total_len += l
	assert_float(total_len).is_equal_approx(9.0, 0.01)


func test_segments_mode_module_lengths_clip() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.MODULE_LENGTHS
	s.fit_mode = SubdivideSegmentSettings.eFitMode.CLIP
	s.module_lengths = PackedFloat32Array([3.0])
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(10, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var len_stream = out.findStream("length")
	assert_object(len_stream).is_not_null()
	assert_int(len_stream.container.size()).is_equal(3)
	for l in len_stream.container:
		assert_float(l).is_equal_approx(3.0, 0.001)

	assert_object(out.findStream("segment_index")).is_null()
	assert_object(out.findStream("t_start")).is_null()
	assert_object(out.findStream("t_end")).is_null()


func test_segments_mode_module_lengths_pad_ends() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.MODULE_LENGTHS
	s.fit_mode = SubdivideSegmentSettings.eFitMode.PAD_ENDS
	s.module_lengths = PackedFloat32Array([3.0])
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(10, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var len_stream = out.findStream("length")
	assert_object(len_stream).is_not_null()
	assert_int(len_stream.container.size()).is_equal(4)
	assert_float(len_stream.container[0]).is_equal_approx(3.0, 0.001)
	assert_float(len_stream.container[1]).is_equal_approx(3.0, 0.001)
	assert_float(len_stream.container[2]).is_equal_approx(3.0, 0.001)
	assert_float(len_stream.container[3]).is_equal_approx(1.0, 0.001)


func test_multiple_spans_produce_cumulative_points() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 2
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = "segment_index"
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	var ends := PackedVector3Array([Vector3(4, 0, 0), Vector3(16, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(4)

	var idx_stream = out.findStream("segment_index")
	assert_object(idx_stream).is_not_null()
	assert_int(idx_stream.container[0]).is_equal(0)
	assert_int(idx_stream.container[1]).is_equal(1)
	assert_int(idx_stream.container[2]).is_equal(0)
	assert_int(idx_stream.container[3]).is_equal(1)


func test_point_centers_are_correct() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 2
	s.out_length_attribute = ""
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(10, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
	assert_float(pos_stream.container[0].x).is_equal_approx(2.5, 0.001)
	assert_float(pos_stream.container[1].x).is_equal_approx(7.5, 0.001)


func test_missing_input_errors() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 2
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_missing_vector_streams_errors() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.segment_start_attribute = "seg_start"
	s.segment_end_attribute = "seg_end"
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 2
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var d := FlowDataScript.Data.new()
	d.registerStream("wrong_stream", PackedVector3Array([Vector3(0, 0, 0)]), FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_empty_module_lengths_errors() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.MODULE_LENGTHS
	s.fit_mode = SubdivideSegmentSettings.eFitMode.CLIP
	s.module_lengths = PackedFloat32Array([])
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(10, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)
	assert_str(node.err).is_not_empty()

func test_cross_section_size_written_to_output() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 1
	s.cross_section_size = Vector2(3.0, 5.0)
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(6, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	# UE parity: scale stays unit; the cross-section (x/y) and sub-segment length
	# (z) extent is recorded in bounds so spawned meshes aren't stretched.
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_int(size_stream.container.size()).is_equal(1)
	assert_float(size_stream.container[0].x).is_equal_approx(1.0, 0.001)
	assert_float(size_stream.container[0].y).is_equal_approx(1.0, 0.001)
	assert_float(size_stream.container[0].z).is_equal_approx(1.0, 0.001)

	var bmin = out.getVector3Container(FlowData.AttrBoundsMin)
	var bmax = out.getVector3Container(FlowData.AttrBoundsMax)
	assert_int(bmin.size()).is_equal(1)
	var ext = bmax[0] - bmin[0]
	assert_float(ext.x).is_equal_approx(3.0, 0.001)
	assert_float(ext.y).is_equal_approx(5.0, 0.001)
	assert_float(ext.z).is_equal_approx(6.0, 0.001)


func test_density_and_seed_streams_present() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 3
	s.out_length_attribute = ""
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(0, 0, 0)])
	var ends := PackedVector3Array([Vector3(6, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var density_stream = out.findStream(FlowData.AttrDensity)
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(3)
	for v in density_stream.container:
		assert_float(v).is_equal_approx(1.0, 0.001)

	var seed_stream = out.findStream(FlowData.AttrSeed)
	assert_object(seed_stream).is_not_null()
	assert_int(seed_stream.container.size()).is_equal(3)


func test_degenerate_zero_length_span_produces_no_points() -> void:
	var s = SubdivideSegmentSettings.new()
	s.input_mode = SubdivideSegmentSettings.eInputMode.SEGMENTS
	s.subdivide_mode = SubdivideSegmentSettings.eSubdivideMode.TARGET_COUNT
	s.target_count = 4
	s.out_length_attribute = "length"
	s.out_segment_index_attribute = ""
	s.out_t_start_attribute = ""
	s.out_t_end_attribute = ""

	var starts := PackedVector3Array([Vector3(5, 0, 0)])
	var ends := PackedVector3Array([Vector3(5, 0, 0)])
	var node = _run([_make_segments_data(starts, ends)], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(0)

