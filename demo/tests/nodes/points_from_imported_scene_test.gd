# points_from_imported_scene_test.gd
class_name PointsFromImportedSceneTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointsFromImportedSceneNode = preload("res://addons/flow_nodes_editor/nodes/points_from_imported_scene.gd")
const PointsFromImportedSceneSettings = preload("res://addons/flow_nodes_editor/nodes/points_from_imported_scene_settings.gd")

# Real BoxMesh asset committed in the repo — used as a headless Mesh fixture.
const MESH_PATH = "res://addons/flow_nodes_editor/resources/unit_cube.tres"

func _make_settings(path: String = "") -> PointsFromImportedSceneSettings:
	var s = PointsFromImportedSceneSettings.new()
	s.asset_path = path
	return s

func _run(s: PointsFromImportedSceneSettings) -> PointsFromImportedSceneNode:
	var node = PointsFromImportedSceneNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: PointsFromImportedSceneNode) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_empty_asset_path_sets_error() -> void:
	var s = _make_settings("")
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_nonexistent_asset_path_sets_error() -> void:
	var s = _make_settings("res://this_scene_does_not_exist_at_all.tscn")
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_whitespace_only_path_sets_error() -> void:
	# strip_edges() collapses whitespace to "" — same error as empty
	var s = _make_settings("   ")
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# Mesh-resource branch — uses unit_cube.tres (a BoxMesh, size 1x1x1)
# BoxMesh default AABB: position=(-0.5,-0.5,-0.5), size=(1,1,1)
# center = aabb.position + aabb.size * 0.5 = Vector3.ZERO
# ---------------------------------------------------------------------------

func test_mesh_resource_produces_one_point() -> void:
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowData.AttrPosition)
	assert_int(positions.size()).is_equal(1)
	node.free()

func test_mesh_resource_center_at_aabb_center() -> void:
	# BoxMesh 1x1x1 centered at origin — AABB center == Vector3.ZERO
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var positions = out.getVector3Container(FlowData.AttrPosition)
	assert_bool(positions[0].is_equal_approx(Vector3.ZERO)).is_true()
	node.free()

func test_mesh_resource_rotation_is_zero() -> void:
	# Mesh branch always writes Vector3.ZERO for rotation
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var rotations = out.getVector3Container(FlowData.AttrRotation)
	assert_bool(rotations[0].is_equal_approx(Vector3.ZERO)).is_true()
	node.free()

func test_mesh_resource_size_from_bounds() -> void:
	# use_mesh_bounds=true: size == aabb.size == Vector3(1,1,1) for default BoxMesh
	var s = _make_settings(MESH_PATH)
	s.use_mesh_bounds = true
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var sizes = out.getVector3Container(FlowData.AttrSize)
	assert_bool(sizes[0].is_equal_approx(Vector3.ONE)).is_true()
	node.free()

func test_mesh_resource_size_uses_fallback_when_bounds_disabled() -> void:
	var fallback = Vector3(3.0, 4.0, 5.0)
	var s = _make_settings(MESH_PATH)
	s.use_mesh_bounds = false
	s.fallback_size = fallback
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var sizes = out.getVector3Container(FlowData.AttrSize)
	assert_bool(sizes[0].is_equal_approx(fallback)).is_true()
	node.free()

func test_mesh_resource_include_mesh_resource_stream() -> void:
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = true
	s.mesh_attribute = "mesh"
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var mesh_stream = out.findStream("mesh")
	assert_object(mesh_stream).is_not_null()
	assert_int(mesh_stream.container.size()).is_equal(1)
	assert_object(mesh_stream.container[0]).is_instanceof(BoxMesh)
	node.free()

func test_mesh_resource_blank_mesh_attribute_suppresses_stream() -> void:
	# When mesh_attribute is blank, the stream must NOT be registered
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = true
	s.mesh_attribute = "   "   # strip_edges() → "" → not registered
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# stream name "   " is not "mesh" and blank names aren't registered
	var mesh_stream = out.findStream("   ")
	assert_object(mesh_stream).is_null()
	node.free()

func test_mesh_resource_include_source_name_stream() -> void:
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = false
	s.include_source_name = true
	s.source_name_attribute = "source_node_name"
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var name_stream = out.findStream("source_node_name")
	assert_object(name_stream).is_not_null()
	assert_int(name_stream.container.size()).is_equal(1)
	# source name for a Mesh is path.get_file()
	var expected_name = MESH_PATH.get_file()
	assert_str(name_stream.container[0]).is_equal(expected_name)
	node.free()

func test_mesh_resource_include_source_path_stream() -> void:
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = true
	s.source_path_attribute = "source_path"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var path_stream = out.findStream("source_path")
	assert_object(path_stream).is_not_null()
	assert_int(path_stream.container.size()).is_equal(1)
	assert_str(path_stream.container[0]).is_equal(MESH_PATH)
	node.free()

func test_mesh_resource_all_optional_streams_disabled() -> void:
	# With all optional streams off, only position/rotation/size should exist
	var s = _make_settings(MESH_PATH)
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_bool(out.hasStream(FlowData.AttrPosition)).is_true()
	assert_bool(out.hasStream(FlowData.AttrRotation)).is_true()
	assert_bool(out.hasStream(FlowData.AttrSize)).is_true()
	assert_bool(out.hasStream("mesh")).is_false()
	assert_bool(out.hasStream("source_node_name")).is_false()
	assert_bool(out.hasStream("source_path")).is_false()
	node.free()
