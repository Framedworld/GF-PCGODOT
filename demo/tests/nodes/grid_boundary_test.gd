# grid_boundary_test.gd
class_name GridBoundaryTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GridBoundaryNode = preload("res://addons/flow_nodes_editor/nodes/grid_boundary.gd")
const GridBoundarySettings = preload("res://addons/flow_nodes_editor/nodes/grid_boundary_settings.gd")

func _make_cell_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(positions.size())
	var spos = d.getVector3Container(FlowData.AttrPosition)
	for i in range(positions.size()):
		spos[i] = positions[i]
	return d

func _run(input, settings: GridBoundarySettings) -> GridBoundaryNode:
	var node = GridBoundaryNode.new()
	node.name = "test_grid_boundary"
	node.settings = settings
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _get_output(node: GridBoundaryNode, port: int) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	var data = bulk[port]
	if data == null:
		return null
	return data

func test_missing_input_sets_error() -> void:
	var s = GridBoundarySettings.new()
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_input_produces_empty_outputs() -> void:
	var d = _make_cell_data(PackedVector3Array())
	var s = GridBoundarySettings.new()
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	var corners = _get_output(node, 1)
	var all = _get_output(node, 2)
	assert_object(edges).is_not_null()
	assert_object(corners).is_not_null()
	assert_object(all).is_not_null()
	assert_int(edges.size()).is_equal(0)
	assert_int(corners.size()).is_equal(0)
	assert_int(all.size()).is_equal(0)
	node.free()

func test_single_cell_generates_four_edges() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	assert_int(edges.size()).is_equal(4)
	var corners = _get_output(node, 1)
	assert_object(corners).is_not_null()
	assert_int(corners.size()).is_equal(0)
	var all = _get_output(node, 2)
	assert_object(all).is_not_null()
	assert_int(all.size()).is_equal(4)
	node.free()

func test_single_cell_with_corners_enabled() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.include_corners = true
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	assert_int(edges.size()).is_equal(4)
	var corners = _get_output(node, 1)
	assert_object(corners).is_not_null()
	assert_int(corners.size()).is_greater(0)
	var all = _get_output(node, 2)
	assert_object(all).is_not_null()
	assert_int(all.size()).is_equal(edges.size() + corners.size())
	node.free()

func test_two_adjacent_cells_share_no_inner_edge() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	assert_int(edges.size()).is_equal(6)
	node.free()

func test_two_cells_different_y_each_get_full_perimeter() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 0)]))
	var s = GridBoundarySettings.new()
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	assert_int(edges.size()).is_equal(8)
	node.free()

func test_all_output_is_union_of_edges_and_corners() -> void:
	var positions = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0, 0, 1)
	])
	var d = _make_cell_data(positions)
	var s = GridBoundarySettings.new()
	s.include_corners = true
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	var corners = _get_output(node, 1)
	var all = _get_output(node, 2)
	assert_object(all).is_not_null()
	assert_int(all.size()).is_equal(edges.size() + corners.size())
	node.free()

func test_normal_attribute_stream_present_when_named() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.normal_attribute = "boundary_normal"
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	var normal_stream = edges.findStream("boundary_normal")
	assert_object(normal_stream).is_not_null()
	assert_int(normal_stream.container.size()).is_equal(edges.size())
	node.free()

func test_type_attribute_stream_present_when_named() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.type_attribute = "boundary_type"
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	var type_stream = edges.findStream("boundary_type")
	assert_object(type_stream).is_not_null()
	assert_int(type_stream.container.size()).is_equal(edges.size())
	node.free()

func test_normal_attribute_absent_when_empty_string() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.normal_attribute = ""
	s.type_attribute = ""
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	var normal_stream = edges.findStream("boundary_normal")
	assert_object(normal_stream).is_null()
	node.free()

func test_custom_cell_size_affects_edge_positions() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.cell_size = Vector3(2.0, 1.0, 2.0)
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	assert_int(edges.size()).is_equal(4)
	var positions = edges.getVector3Container(FlowData.AttrPosition)
	var found_offset = false
	for p in positions:
		if absf(p.x) > 0.9 or absf(p.z) > 0.9:
			found_offset = true
			break
	assert_bool(found_offset).is_true()
	node.free()

func test_wall_height_setting_applied_to_size() -> void:
	var d = _make_cell_data(PackedVector3Array([Vector3(0, 0, 0)]))
	var s = GridBoundarySettings.new()
	s.wall_height = 3.0
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	var sizes = edges.getVector3Container(FlowData.AttrSize)
	assert_object(sizes).is_not_null()
	var all_correct_height = true
	for sz in sizes:
		if not is_equal_approx(sz.y, 3.0):
			all_correct_height = false
			break
	assert_bool(all_correct_height).is_true()
	node.free()

func test_large_grid_no_errors() -> void:
	var positions = PackedVector3Array()
	for z in range(6):
		for x in range(6):
			positions.append(Vector3(x, 0, z))
	var d = _make_cell_data(positions)
	var s = GridBoundarySettings.new()
	s.include_corners = true
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	assert_int(edges.size()).is_greater(0)
	var corners = _get_output(node, 1)
	assert_object(corners).is_not_null()
	assert_int(corners.size()).is_greater(0)
	node.free()

func test_duplicate_positions_deduplicated() -> void:
	var d = _make_cell_data(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)
	]))
	var s = GridBoundarySettings.new()
	s.include_corners = false
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var edges = _get_output(node, 0)
	assert_object(edges).is_not_null()
	assert_int(edges.size()).is_equal(4)
	node.free()
