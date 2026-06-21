# grid_connect_points_test.gd
class_name GridConnectPointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GridConnectPointsNode = preload("res://addons/flow_nodes_editor/nodes/grid_connect_points.gd")
const GridConnectPointsSettings = preload("res://addons/flow_nodes_editor/nodes/grid_connect_points_settings.gd")

func _make_position_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(input: FlowData.Data, settings: GridConnectPointsNodeSettings) -> GridConnectPointsNode:
	var node = GridConnectPointsNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: GridConnectPointsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func _default_settings() -> GridConnectPointsNodeSettings:
	var s := GridConnectPointsNodeSettings.new()
	s.cell_size = Vector3.ONE
	s.axis_order = GridConnectPointsNodeSettings.eAxisOrder.XThenZ
	s.include_input_points = true
	s.deduplicate_cells = true
	s.path_index_attribute = "path_index"
	return s

func test_basic_x_then_z_path() -> void:
	var s := _default_settings()
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 3)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	var out_positions = pos_stream.container as PackedVector3Array
	assert_bool(out_positions.size() > 0).is_true()
	assert_array(out_positions).contains([Vector3(0, 0, 0)])
	assert_array(out_positions).contains([Vector3(2, 0, 3)])
	node.free()

func test_z_then_x_axis_order() -> void:
	var s := _default_settings()
	s.axis_order = GridConnectPointsNodeSettings.eAxisOrder.ZThenX
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 2)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var out_positions = pos_stream.container as PackedVector3Array
	assert_bool(out_positions.size() > 0).is_true()
	assert_array(out_positions).contains([Vector3(0, 0, 1)])
	assert_array(out_positions).contains([Vector3(0, 0, 2)])
	assert_array(out_positions).contains([Vector3(1, 0, 2)])
	assert_array(out_positions).contains([Vector3(2, 0, 2)])
	node.free()

func test_x_then_z_walk_order_intermediate_cells() -> void:
	var s := _default_settings()
	s.axis_order = GridConnectPointsNodeSettings.eAxisOrder.XThenZ
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 2)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var out_positions = pos_stream.container as PackedVector3Array
	assert_array(out_positions).contains([Vector3(1, 0, 0)])
	assert_array(out_positions).contains([Vector3(2, 0, 0)])
	assert_array(out_positions).contains([Vector3(2, 0, 1)])
	node.free()

func test_include_input_points_false() -> void:
	var s := _default_settings()
	s.include_input_points = false
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var out_positions = pos_stream.container as PackedVector3Array
	assert_bool(out_positions.has(Vector3(0, 0, 0))).is_false()
	assert_bool(out_positions.has(Vector3(2, 0, 0))).is_true()
	assert_bool(out_positions.has(Vector3(1, 0, 0))).is_true()
	node.free()

func test_deduplicate_cells_false_produces_overlap() -> void:
	var s := _default_settings()
	s.deduplicate_cells = false
	s.include_input_points = true
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 0)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.size() >= 2).is_true()
	node.free()

func test_path_index_attribute_written() -> void:
	var s := _default_settings()
	s.path_index_attribute = "seg"
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 2)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var idx_stream = out.findStream("seg")
	assert_object(idx_stream).is_not_null()
	var idx_arr = idx_stream.container as PackedInt32Array
	assert_bool(idx_arr.size() > 0).is_true()
	assert_bool(idx_arr.has(0)).is_true()
	assert_bool(idx_arr.has(1)).is_true()
	node.free()

func test_path_index_attribute_empty_string_skipped() -> void:
	var s := _default_settings()
	s.path_index_attribute = ""
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var idx_stream = out.findStream("path_index")
	assert_object(idx_stream).is_null()
	node.free()

func test_single_point_with_include_input_points() -> void:
	var s := _default_settings()
	s.include_input_points = true
	var positions := PackedVector3Array([Vector3(3, 0, 5)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var out_positions = pos_stream.container as PackedVector3Array
	assert_array(out_positions).contains([Vector3(3, 0, 5)])
	node.free()

func test_single_point_without_include_input_points() -> void:
	var s := _default_settings()
	s.include_input_points = false
	var positions := PackedVector3Array([Vector3(3, 0, 5)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_custom_cell_size() -> void:
	var s := _default_settings()
	s.cell_size = Vector3(2.0, 1.0, 2.0)
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var out_positions = pos_stream.container as PackedVector3Array
	assert_array(out_positions).contains([Vector3(2, 0, 0)])
	assert_array(out_positions).contains([Vector3(4, 0, 0)])
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	var size_arr = size_stream.container as PackedVector3Array
	for i in range(size_arr.size()):
		assert_float(size_arr[i].x).is_equal_approx(2.0, 0.0001)
		assert_float(size_arr[i].z).is_equal_approx(2.0, 0.0001)
	node.free()

func test_missing_input_error() -> void:
	var s := _default_settings()
	var node := _run(null, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_input_missing_position_stream_error() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("some_other", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var s := _default_settings()
	var node := _run(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_collinear_x_path_no_duplicates() -> void:
	# [0,0,0] -> [3,0,0] -> [5,0,0] with dedup=true, include_input=true
	# Segment 0: start(0,0,0), walk x: (1,0,0),(2,0,0),(3,0,0) => 4 cells
	# Segment 1: walk x from (3,0,0): (4,0,0),(5,0,0) => 2 new cells
	# Total = 6
	var s := _default_settings()
	s.deduplicate_cells = true
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(5, 0, 0)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var out_positions = pos_stream.container as PackedVector3Array
	assert_int(out_positions.size()).is_equal(6)
	node.free()

func test_y_axis_not_walked() -> void:
	# [0,0,0] -> [0,5,0]: Y differs but is never walked.
	# With include_input=true: appends start (0,0,0), walks X (no diff), walks Z (no diff),
	# then current(0,0,0) != end_cell(0,5,0) so appends end_cell(0,5,0). Output = 2.
	var s := _default_settings()
	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 5, 0)])
	var node := _run(_make_position_data(positions), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var out_positions = pos_stream.container as PackedVector3Array
	assert_int(out_positions.size()).is_equal(2)
	node.free()
