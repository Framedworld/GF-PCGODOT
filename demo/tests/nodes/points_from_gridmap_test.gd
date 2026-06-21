# points_from_gridmap_test.gd
class_name PointsFromGridmapTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointsFromGridmapNode = preload("res://addons/flow_nodes_editor/nodes/points_from_gridmap.gd")
const PointsFromGridmapSettings = preload("res://addons/flow_nodes_editor/nodes/points_from_gridmap_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# Build a minimal MeshLibrary with one item (id 0) so GridMap can have cells.
func _make_mesh_library() -> MeshLibrary:
	var lib = MeshLibrary.new()
	lib.create_item(0)
	lib.set_item_name(0, "TestItem")
	lib.set_item_mesh(0, BoxMesh.new())
	return lib

# Create a FlowGraphNode3D owner added to the test suite, with a GridMap child
# that has `cell_count` cells placed at positions (i, 0, 0) with item 0.
func _make_owner_with_gridmap(cell_count: int) -> FlowGraphNode3D:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var gm = GridMap.new()
	gm.mesh_library = _make_mesh_library()
	owner_node.add_child(gm)
	for i in range(cell_count):
		gm.set_cell_item(Vector3i(i, 0, 0), 0)
	return owner_node

func _run_with_owner(owner_node, settings) -> PointsFromGridmapNode:
	var node = PointsFromGridmapNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)
	return node

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# null owner → no crash, no error, empty output
func test_null_owner_produces_empty_output() -> void:
	var s = PointsFromGridmapSettings.new()
	var node = PointsFromGridmapNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = null
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	node.free()

# owner with no GridMap child → no error, output is empty
func test_no_gridmap_in_scene_produces_empty_output() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	# Add a plain Node3D (not a GridMap) to make sure it's ignored
	owner_node.add_child(Node3D.new())
	var s = PointsFromGridmapSettings.new()
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# Output data is created; position stream must be size 0
	if out != null:
		var pos = out.getVector3Container(FlowData.AttrPosition)
		assert_int(pos.size()).is_equal(0)
	owner_node.free()
	node.free()

# GridMap with 3 cells → output has exactly 3 points
func test_three_cells_produce_three_points() -> void:
	var owner_node = _make_owner_with_gridmap(3)
	var s = PointsFromGridmapSettings.new()
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(3)
	owner_node.free()
	node.free()

# size stream matches cell_size of the GridMap
func test_size_stream_matches_gridmap_cell_size() -> void:
	var owner_node = _make_owner_with_gridmap(2)
	# Grab the GridMap to check its cell_size
	var gm = owner_node.get_child(0) as GridMap
	var expected_size : Vector3 = gm.cell_size
	var s = PointsFromGridmapSettings.new()
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sizes = out.getVector3Container(FlowData.AttrSize)
	assert_int(sizes.size()).is_equal(2)
	for i in range(sizes.size()):
		assert_bool(sizes[i].is_equal_approx(expected_size)).is_true()
	owner_node.free()
	node.free()

# cell attribute stream is written by default (out_cell_attribute = "grid_cell")
func test_cell_attribute_stream_is_present() -> void:
	var owner_node = _make_owner_with_gridmap(2)
	var s = PointsFromGridmapSettings.new()
	# Default out_cell_attribute is "grid_cell"
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var cell_stream = out.findStream("grid_cell")
	assert_object(cell_stream).is_not_null()
	assert_int(cell_stream.container.size()).is_equal(2)
	owner_node.free()
	node.free()

# item_id stream is written when include_item_id = true
func test_item_id_stream_present_when_enabled() -> void:
	var owner_node = _make_owner_with_gridmap(2)
	var s = PointsFromGridmapSettings.new()
	s.include_item_id = true
	# Default out_item_id_attribute = "grid_item_id"
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var id_stream = out.findStream("grid_item_id")
	assert_object(id_stream).is_not_null()
	assert_int(id_stream.container.size()).is_equal(2)
	# All cells were placed with item 0
	for i in range(id_stream.container.size()):
		assert_int(id_stream.container[i]).is_equal(0)
	owner_node.free()
	node.free()

# item_id stream is absent when include_item_id = false
func test_item_id_stream_absent_when_disabled() -> void:
	var owner_node = _make_owner_with_gridmap(2)
	var s = PointsFromGridmapSettings.new()
	s.include_item_id = false
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var id_stream = out.findStream("grid_item_id")
	assert_object(id_stream).is_null()
	owner_node.free()
	node.free()

# gridmap_ref stream present when include_gridmap_ref = true
func test_gridmap_ref_stream_present_when_enabled() -> void:
	var owner_node = _make_owner_with_gridmap(2)
	var s = PointsFromGridmapSettings.new()
	s.include_gridmap_ref = true
	# Default out_gridmap_attribute = "gridmap_node"
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var ref_stream = out.findStream("gridmap_node")
	assert_object(ref_stream).is_not_null()
	assert_int(ref_stream.container.size()).is_equal(2)
	var gm = owner_node.get_child(0)
	for i in range(ref_stream.container.size()):
		assert_object(ref_stream.container[i]).is_equal(gm)
	owner_node.free()
	node.free()

# item_id_filter = 0 keeps only item-0 cells; item_id_filter = 1 keeps none
func test_item_id_filter_excludes_non_matching_cells() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var gm = GridMap.new()
	var lib = _make_mesh_library()
	# Add a second item (id 1) to the library
	lib.create_item(1)
	lib.set_item_name(1, "OtherItem")
	lib.set_item_mesh(1, BoxMesh.new())
	gm.mesh_library = lib
	owner_node.add_child(gm)
	gm.set_cell_item(Vector3i(0, 0, 0), 0)
	gm.set_cell_item(Vector3i(1, 0, 0), 0)
	gm.set_cell_item(Vector3i(2, 0, 0), 1)  # different item

	var s = PointsFromGridmapSettings.new()
	s.item_id_filter = 0  # only keep item 0
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(2)
	owner_node.free()
	node.free()

# item_id_filter = -1 means no filter; all cells are kept
func test_item_id_filter_minus_one_keeps_all_cells() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var gm = GridMap.new()
	var lib = _make_mesh_library()
	lib.create_item(1)
	lib.set_item_name(1, "OtherItem")
	lib.set_item_mesh(1, BoxMesh.new())
	gm.mesh_library = lib
	owner_node.add_child(gm)
	gm.set_cell_item(Vector3i(0, 0, 0), 0)
	gm.set_cell_item(Vector3i(1, 0, 0), 1)

	var s = PointsFromGridmapSettings.new()
	s.item_id_filter = -1  # no filter
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(pos.size()).is_equal(2)
	owner_node.free()
	node.free()

# y_offset shifts all generated positions upward by the given amount
func test_y_offset_shifts_positions() -> void:
	var owner_node = _make_owner_with_gridmap(1)
	var gm = owner_node.get_child(0) as GridMap

	# Run once without offset
	var s_base = PointsFromGridmapSettings.new()
	s_base.y_offset = 0.0
	var node_base = _run_with_owner(owner_node, s_base)
	assert_str(node_base.err).is_empty()
	var out_base = _output(node_base)
	var pos_base = out_base.getVector3Container(FlowData.AttrPosition)
	var base_y : float = pos_base[0].y
	node_base.free()

	# Run again with offset
	var s_off = PointsFromGridmapSettings.new()
	s_off.y_offset = 5.0
	var node_off = _run_with_owner(owner_node, s_off)
	assert_str(node_off.err).is_empty()
	var out_off = _output(node_off)
	var pos_off = out_off.getVector3Container(FlowData.AttrPosition)
	assert_float(pos_off[0].y).is_equal_approx(base_y + 5.0, 0.001)
	owner_node.free()
	node_off.free()

# gridmap_path set to a valid GridMap node → only that GridMap is used
func test_gridmap_path_targets_specific_gridmap() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)

	var gm_a = GridMap.new()
	gm_a.name = "GridA"
	gm_a.mesh_library = _make_mesh_library()
	owner_node.add_child(gm_a)
	gm_a.set_cell_item(Vector3i(0, 0, 0), 0)
	gm_a.set_cell_item(Vector3i(1, 0, 0), 0)

	var gm_b = GridMap.new()
	gm_b.name = "GridB"
	gm_b.mesh_library = _make_mesh_library()
	owner_node.add_child(gm_b)
	gm_b.set_cell_item(Vector3i(5, 0, 0), 0)

	var s = PointsFromGridmapSettings.new()
	s.gridmap_path = "GridA"
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	# Only GridA's 2 cells, not GridB's 1 cell
	assert_int(pos.size()).is_equal(2)
	owner_node.free()
	node.free()

# gridmap_path pointing to a non-existent node → error is set
func test_gridmap_path_invalid_sets_error() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var s = PointsFromGridmapSettings.new()
	s.gridmap_path = "NonExistentGrid"
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_not_empty()
	owner_node.free()
	node.free()

# empty out_cell_attribute → cell stream is NOT written
func test_empty_cell_attribute_name_skips_stream() -> void:
	var owner_node = _make_owner_with_gridmap(1)
	var s = PointsFromGridmapSettings.new()
	s.out_cell_attribute = ""
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# "grid_cell" was the default; clearing it means no stream by that name
	var cell_stream = out.findStream("grid_cell")
	assert_object(cell_stream).is_null()
	owner_node.free()
	node.free()

# output position/rotation/size streams have equal sizes
func test_common_streams_have_consistent_sizes() -> void:
	var owner_node = _make_owner_with_gridmap(4)
	var s = PointsFromGridmapSettings.new()
	var node = _run_with_owner(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos = out.getVector3Container(FlowData.AttrPosition)
	var rot = out.getVector3Container(FlowData.AttrRotation)
	var sz  = out.getVector3Container(FlowData.AttrSize)
	assert_int(pos.size()).is_equal(4)
	assert_int(rot.size()).is_equal(4)
	assert_int(sz.size()).is_equal(4)
	owner_node.free()
	node.free()
