# load_alembic_file_test.gd
class_name LoadAlembicFileTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const LoadAlembicFileNode = preload("res://addons/flow_nodes_editor/nodes/load_alembic_file.gd")
const LoadAlembicFileSettings = preload("res://addons/flow_nodes_editor/nodes/points_from_imported_scene_settings.gd")

# A committed BoxMesh .tres — a real Mesh resource on disk that loads headlessly.
const UNIT_CUBE_PATH = "res://addons/flow_nodes_editor/resources/unit_cube.tres"

func _run(settings) -> LoadAlembicFileNode:
	var node = LoadAlembicFileNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
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

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_empty_asset_path_sets_error() -> void:
	var s = LoadAlembicFileSettings.new()
	s.asset_path = ""
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_nonexistent_asset_path_sets_error() -> void:
	var s = LoadAlembicFileSettings.new()
	s.asset_path = "res://nonexistent_file_that_does_not_exist.abc"
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_whitespace_only_path_sets_error() -> void:
	# strip_edges() is called in execute(), so "   " becomes "" → same error branch
	var s = LoadAlembicFileSettings.new()
	s.asset_path = "   "
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# Happy-path tests using the committed unit_cube.tres (BoxMesh, 1x1x1)
# ---------------------------------------------------------------------------

func test_mesh_resource_emits_one_point() -> void:
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	s.use_mesh_bounds = true
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# A single Mesh resource always produces exactly one point
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	node.free()

func test_mesh_resource_position_at_aabb_center() -> void:
	# BoxMesh default is 1x1x1 → AABB position=(-0.5,-0.5,-0.5), size=(1,1,1)
	# center = aabb.position + aabb.size * 0.5 = (0,0,0)
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	s.use_mesh_bounds = true
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	var pos = pos_stream.container[0]
	assert_bool(pos.is_equal_approx(Vector3.ZERO)).is_true()
	node.free()

func test_mesh_resource_rotation_is_zero() -> void:
	# Mesh branch always writes Vector3.ZERO for rotation
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var rot_stream = out.findStream("rotation")
	assert_object(rot_stream).is_not_null()
	var rot = rot_stream.container[0]
	assert_bool(rot.is_equal_approx(Vector3.ZERO)).is_true()
	node.free()

func test_mesh_resource_size_from_bounds() -> void:
	# BoxMesh 1x1x1 → aabb.size = (1,1,1); use_mesh_bounds=true picks that
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	s.use_mesh_bounds = true
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream("size")
	assert_object(size_stream).is_not_null()
	var sz = size_stream.container[0]
	# AABB size of a default 1×1×1 BoxMesh should be (1,1,1)
	assert_bool(sz.is_equal_approx(Vector3.ONE)).is_true()
	node.free()

func test_mesh_resource_size_from_fallback_when_bounds_disabled() -> void:
	# When use_mesh_bounds=false the fallback_size is used instead
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	s.use_mesh_bounds = false
	s.fallback_size = Vector3(2.0, 3.0, 4.0)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream("size")
	assert_object(size_stream).is_not_null()
	var sz = size_stream.container[0]
	assert_bool(sz.is_equal_approx(Vector3(2.0, 3.0, 4.0))).is_true()
	node.free()

func test_mesh_resource_optional_streams_present_by_default() -> void:
	# By default include_mesh_resource, include_source_name, include_source_path are all true
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# mesh stream
	var mesh_stream = out.findStream(s.mesh_attribute)
	assert_object(mesh_stream).is_not_null()
	assert_int(mesh_stream.container.size()).is_equal(1)
	# source_node_name stream — for a Mesh asset the file basename is used
	var name_stream = out.findStream(s.source_name_attribute)
	assert_object(name_stream).is_not_null()
	assert_int(name_stream.container.size()).is_equal(1)
	assert_str(name_stream.container[0]).is_not_empty()
	# source_path stream
	var path_stream = out.findStream(s.source_path_attribute)
	assert_object(path_stream).is_not_null()
	assert_str(path_stream.container[0]).is_equal(UNIT_CUBE_PATH)
	node.free()

func test_mesh_resource_source_name_is_filename() -> void:
	# For a bare Mesh (not PackedScene), source name = path.get_file()
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var name_stream = out.findStream(s.source_name_attribute)
	assert_object(name_stream).is_not_null()
	assert_str(name_stream.container[0]).is_equal(UNIT_CUBE_PATH.get_file())
	node.free()

func test_optional_streams_absent_when_disabled() -> void:
	# When all three optional stream flags are off, those streams must not appear
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream(s.mesh_attribute)).is_null()
	assert_object(out.findStream(s.source_name_attribute)).is_null()
	assert_object(out.findStream(s.source_path_attribute)).is_null()
	node.free()

func test_output_always_has_position_rotation_size_streams() -> void:
	# Core spatial streams are registered regardless of optional flag settings
	var s = LoadAlembicFileSettings.new()
	s.asset_path = UNIT_CUBE_PATH
	s.include_mesh_resource = false
	s.include_source_name = false
	s.include_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out.findStream("position")).is_not_null()
	assert_object(out.findStream("rotation")).is_not_null()
	assert_object(out.findStream("size")).is_not_null()
	node.free()
