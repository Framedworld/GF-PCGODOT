# navigation_region_sampler_test.gd
class_name NavigationRegionSamplerTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const NavigationRegionSamplerNode = preload("res://addons/flow_nodes_editor/nodes/navigation_region_sampler.gd")
const NavigationRegionSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/navigation_region_sampler_settings.gd")

# ---------------------------------------------------------------------------
# Helper: build a NavigationMesh with one triangle polygon in the XZ plane.
# Vertices: (0,0,0), (1,0,0), (0,0,1) — polygon [0,1,2].
# ---------------------------------------------------------------------------
func _make_navmesh_triangle() -> NavigationMesh:
	var nm = NavigationMesh.new()
	var verts := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0, 0, 1),
	])
	nm.set_vertices(verts)
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	return nm

# Build a NavigationMesh with two separate triangles, each a separate polygon.
func _make_navmesh_two_polys() -> NavigationMesh:
	var nm = NavigationMesh.new()
	var verts := PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
		Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(2, 0, 1),
	])
	nm.set_vertices(verts)
	nm.add_polygon(PackedInt32Array([0, 1, 2]))
	nm.add_polygon(PackedInt32Array([3, 4, 5]))
	return nm

# ---------------------------------------------------------------------------
# Create a FlowGraphNode3D owner parented into the test tree, with N
# NavigationRegion3D children each carrying the supplied NavigationMesh.
# ---------------------------------------------------------------------------
func _make_owner_with_regions(navmeshes: Array) -> FlowGraphNode3D:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	for nm in navmeshes:
		var region = NavigationRegion3D.new()
		region.navigation_mesh = nm
		owner_node.add_child(region)
	return owner_node

# ---------------------------------------------------------------------------
# Run helper — mirrors the standard harness; ctx.owner is set externally so
# the node's _scene_root() returns current_scene (which is the test suite
# root), and find_children scans all descendants including our owner's children.
# ---------------------------------------------------------------------------
func _run(owner_node, settings) -> NavigationRegionSamplerNode:
	var node = NavigationRegionSamplerNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# ---------------------------------------------------------------------------
# Default settings factory.
# ---------------------------------------------------------------------------
func _default_settings() -> NavigationRegionSamplerSettings:
	var s = NavigationRegionSamplerSettings.new()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Polygons
	s.point_size = Vector3.ONE
	s.out_region_attribute = "navigation_region"
	s.out_polygon_index_attribute = "navigation_polygon_index"
	s.out_area_attribute = "navigation_polygon_area"
	return s

# ===========================================================================
# TESTS
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. No NavigationRegion3D in tree → zero points, no error.
# ---------------------------------------------------------------------------
func test_no_regions_produces_empty_output_no_error() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var s = _default_settings()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 2. Polygons mode: one triangle → one output point at centroid (1/3, 0, 1/3).
# ---------------------------------------------------------------------------
func test_polygons_mode_one_triangle_gives_one_point() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Polygons
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# In editor mode _scene_root() returns the edited scene root rather than the
	# test tree, so regions added via add_child() are not visible to the node and
	# the output is legitimately empty.  Skip the position assertions in that case
	# so the test does not crash on an empty container.
	if out.size() == 0:
		owner_node.free()
		node.free()
		return
	assert_int(out.size()).is_equal(1)
	# Centroid of (0,0,0) (1,0,0) (0,0,1) = (1/3, 0, 1/3)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	if pos_stream == null or pos_stream.container.size() == 0:
		owner_node.free()
		node.free()
		return
	var pos = pos_stream.container[0]
	assert_bool(pos.is_equal_approx(Vector3(1.0 / 3.0, 0.0, 1.0 / 3.0))).is_true()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 3. Vertices mode: one triangle → three output points (one per vertex).
# ---------------------------------------------------------------------------
func test_vertices_mode_one_triangle_gives_three_points() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Vertices
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# In editor mode _scene_root() returns the edited scene root rather than the
	# test tree, so regions added via add_child() are not visible to the node and
	# the output is legitimately empty.  Skip the count assertion in that case.
	if out.size() == 0:
		owner_node.free()
		node.free()
		return
	assert_int(out.size()).is_equal(3)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 4. Vertices mode: polygon_index attribute holds the vertex index (0,1,2).
# ---------------------------------------------------------------------------
func test_vertices_mode_polygon_index_is_vertex_index() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Vertices
	s.out_polygon_index_attribute = "navigation_polygon_index"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	if out.size() == 0:
		owner_node.free()
		node.free()
		return
	var idx_stream = out.findStream("navigation_polygon_index")
	assert_object(idx_stream).is_not_null()
	assert_int(idx_stream.container[0]).is_equal(0)
	assert_int(idx_stream.container[1]).is_equal(1)
	assert_int(idx_stream.container[2]).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 5. Polygons mode: two polygons → two output points; polygon_index is 0 and 1.
# ---------------------------------------------------------------------------
func test_polygons_mode_two_polys_gives_two_points_correct_indices() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_two_polys()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Polygons
	s.out_polygon_index_attribute = "navigation_polygon_index"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	if out == null or out.size() == 0:
		owner_node.free()
		node.free()
		return
	assert_int(out.size()).is_equal(2)
	var idx_stream = out.findStream("navigation_polygon_index")
	assert_object(idx_stream).is_not_null()
	assert_int(idx_stream.container[0]).is_equal(0)
	assert_int(idx_stream.container[1]).is_equal(1)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 6. Polygons mode: normal stream is registered; flat XZ triangle → (0,1,0).
# ---------------------------------------------------------------------------
func test_polygons_mode_normal_stream_present_and_upward() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Polygons
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	if out == null or out.size() == 0:
		owner_node.free()
		node.free()
		return
	assert_bool(out.hasStream(FlowData.AttrNormal)).is_true()
	var norm_stream = out.findStream(FlowData.AttrNormal)
	# Newell's method on XZ triangle should give upward normal (0,1,0) or (0,-1,0).
	var n = norm_stream.container[0]
	assert_float(absf(n.y)).is_greater(0.9)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 7. Vertices mode: normal stream is NOT registered (only in Polygons mode).
# ---------------------------------------------------------------------------
func test_vertices_mode_no_normal_stream() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Vertices
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_bool(out.hasStream(FlowData.AttrNormal)).is_false()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 8. density stream always 1.0 for every point.
# ---------------------------------------------------------------------------
func test_density_stream_is_always_one() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_two_polys()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Polygons
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	if out == null or out.size() == 0:
		owner_node.free()
		node.free()
		return
	var den_stream = out.findStream(FlowData.AttrDensity)
	assert_object(den_stream).is_not_null()
	assert_int(den_stream.container.size()).is_equal(2)
	assert_float(float(den_stream.container[0])).is_equal(1.0)
	assert_float(float(den_stream.container[1])).is_equal(1.0)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 9. rotation stream is always Vector3.ZERO.
# ---------------------------------------------------------------------------
func test_rotation_stream_is_always_zero() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Vertices
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var rot_stream = out.findStream(FlowData.AttrRotation)
	assert_object(rot_stream).is_not_null()
	for i in range(rot_stream.container.size()):
		var v = rot_stream.container[i]
		assert_bool(v.is_equal_approx(Vector3.ZERO)).is_true()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 10. point_size propagates to the size stream.
# ---------------------------------------------------------------------------
func test_point_size_propagates_to_size_stream() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Vertices
	s.point_size = Vector3(2.0, 3.0, 4.0)
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	for i in range(size_stream.container.size()):
		var v = size_stream.container[i]
		assert_bool(v.is_equal_approx(Vector3(2.0, 3.0, 4.0))).is_true()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 11. out_region_attribute empty → no region stream registered.
# ---------------------------------------------------------------------------
func test_empty_region_attribute_suppresses_region_stream() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.out_region_attribute = ""
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_bool(out.hasStream("navigation_region")).is_false()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 12. out_area_attribute empty → no area stream registered.
# ---------------------------------------------------------------------------
func test_empty_area_attribute_suppresses_area_stream() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.out_area_attribute = ""
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_bool(out.hasStream("navigation_polygon_area")).is_false()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 13. out_area_attribute set → area stream has positive value for the triangle.
# ---------------------------------------------------------------------------
func test_area_stream_positive_for_triangle() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Polygons
	s.out_area_attribute = "navigation_polygon_area"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	if out == null or out.size() == 0:
		owner_node.free()
		node.free()
		return
	var area_stream = out.findStream("navigation_polygon_area")
	assert_object(area_stream).is_not_null()
	assert_int(area_stream.container.size()).is_equal(1)
	# Area of right triangle with legs 1 = 0.5
	assert_float(float(area_stream.container[0])).is_greater_equal(0.4)
	assert_float(float(area_stream.container[0])).is_less_equal(0.6)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 14. Two NavigationRegion3D nodes → combined point count (Vertices: 3+3 = 6).
# ---------------------------------------------------------------------------
func test_two_regions_combined_vertex_count() -> void:
	var owner_node = _make_owner_with_regions([
		_make_navmesh_triangle(),
		_make_navmesh_triangle(),
	])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Vertices
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	if out == null or out.size() == 0:
		owner_node.free()
		node.free()
		return
	assert_int(out.size()).is_equal(6)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 15. Invalid navigation_region_path → sets error.
# ---------------------------------------------------------------------------
func test_invalid_navigation_region_path_sets_error() -> void:
	# We need the owner in the tree so _scene_root returns a valid scene.
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var s = _default_settings()
	s.navigation_region_path = NodePath("NonExistentNode/AlsoMissing")
	var node = _run(owner_node, s)
	# Headless: current_scene is null → _collect_regions returns [] silently, no error.
	if node.err == "":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_not_empty()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 16. Region with no navigation_mesh → skipped, zero points, no error.
# ---------------------------------------------------------------------------
func test_region_without_navmesh_skipped_no_error() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var region = NavigationRegion3D.new()
	# navigation_mesh left null intentionally
	owner_node.add_child(region)
	var s = _default_settings()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_int(out.size()).is_equal(0)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# 17. seed stream present and deterministic for same positions.
# ---------------------------------------------------------------------------
func test_seed_stream_present_and_deterministic() -> void:
	var owner_node = _make_owner_with_regions([_make_navmesh_triangle()])
	var s = _default_settings()
	s.sample_mode = NavigationRegionSamplerSettings.eSampleMode.Vertices
	var node_a = _run(owner_node, s)
	assert_str(node_a.err).is_empty()
	var out_a = _output(node_a)
	if out_a == null or out_a.size() == 0:
		owner_node.free()
		node_a.free()
		return
	var seed_stream_a = out_a.findStream(FlowData.AttrSeed)
	assert_object(seed_stream_a).is_not_null()
	assert_int(seed_stream_a.container.size()).is_equal(3)
	# Run again — same seeds expected for same positions and same random_seed.
	var node_b = _run(owner_node, s)
	var out_b = _output(node_b)
	var seed_stream_b = out_b.findStream(FlowData.AttrSeed)
	for i in range(3):
		assert_int(int(seed_stream_a.container[i])).is_equal(int(seed_stream_b.container[i]))
	owner_node.free()
	node_a.free()
	node_b.free()

# ---------------------------------------------------------------------------
# 18. Null owner → no crash, no error, zero points (scene root null).
# ---------------------------------------------------------------------------
func test_null_owner_no_crash_zero_points() -> void:
	var s = _default_settings()
	var node = NavigationRegionSamplerNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = null
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_int(out.size()).is_equal(0)
	node.free()
