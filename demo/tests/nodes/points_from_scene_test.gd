# points_from_scene_test.gd
class_name PointsFromSceneTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointsFromSceneNode = preload("res://addons/flow_nodes_editor/nodes/points_from_scene.gd")
const PointsFromSceneSettings = preload("res://addons/flow_nodes_editor/nodes/points_from_scene_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Build an owner parented under this suite so its scan scope is 100% deterministic.
func _make_owner() -> FlowGraphNode3D:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	return owner_node

func _run(owner_node, settings) -> PointsFromSceneNode:
	var node = PointsFromSceneNode.new()
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
# Tests
# ---------------------------------------------------------------------------

func test_null_owner_does_not_crash() -> void:
	var s = PointsFromSceneSettings.new()
	var node = PointsFromSceneNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = null
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(0)
	node.free()

func test_empty_owner_produces_zero_points() -> void:
	var owner_node = _make_owner()
	var s = PointsFromSceneSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(0)
	owner_node.free()
	node.free()

func test_collects_node3d_children() -> void:
	var owner_node = _make_owner()
	for i in range(3):
		owner_node.add_child(Node3D.new())
	var s = PointsFromSceneSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(3)
	owner_node.free()
	node.free()

func test_output_streams_exist_position_rotation_size() -> void:
	var owner_node = _make_owner()
	var child = Node3D.new()
	owner_node.add_child(child)
	var s = PointsFromSceneSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out.findStream(FlowData.AttrPosition)).is_not_null()
	assert_object(out.findStream(FlowData.AttrRotation)).is_not_null()
	assert_object(out.findStream(FlowData.AttrSize)).is_not_null()
	owner_node.free()
	node.free()

func test_collects_nested_nodes_when_recursive() -> void:
	var owner_node = _make_owner()
	var mid = Node3D.new()
	owner_node.add_child(mid)
	var nested = Node3D.new()
	mid.add_child(nested)
	var s = PointsFromSceneSettings.new()
	s.recursive = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# both mid and nested are Node3D, so 2 points expected
	assert_int(out.findStream(FlowData.AttrPosition).container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_non_recursive_only_direct_children() -> void:
	var owner_node = _make_owner()
	var direct = Node3D.new()
	owner_node.add_child(direct)
	var mid = Node3D.new()
	owner_node.add_child(mid)
	var nested = Node3D.new()
	mid.add_child(nested)
	var s = PointsFromSceneSettings.new()
	s.recursive = false
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# Only direct children: direct and mid (not nested)
	assert_int(out.findStream(FlowData.AttrPosition).container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_filter_by_class_name() -> void:
	var owner_node = _make_owner()
	# 2 MeshInstance3D, 2 plain Node3D
	for i in range(2):
		var mi = MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		owner_node.add_child(mi)
	for i in range(2):
		owner_node.add_child(Node3D.new())
	var s = PointsFromSceneSettings.new()
	s.filter_by_class_name = "MeshInstance3D"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_int(out.findStream(FlowData.AttrPosition).container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_group_filter() -> void:
	var owner_node = _make_owner()
	for i in range(2):
		var n = Node3D.new()
		owner_node.add_child(n)
		n.add_to_group("pfs_group")
	for i in range(3):
		owner_node.add_child(Node3D.new())
	var s = PointsFromSceneSettings.new()
	s.group_name = "pfs_group"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_int(out.findStream(FlowData.AttrPosition).container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_name_filter_wildcard() -> void:
	var owner_node = _make_owner()
	var named_a = Node3D.new()
	named_a.name = "TargetAlpha"
	owner_node.add_child(named_a)
	var named_b = Node3D.new()
	named_b.name = "TargetBeta"
	owner_node.add_child(named_b)
	var other = Node3D.new()
	other.name = "OtherNode"
	owner_node.add_child(other)
	var s = PointsFromSceneSettings.new()
	s.filter_by_name = "Target*"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_int(out.findStream(FlowData.AttrPosition).container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_import_metadata_creates_stream() -> void:
	var owner_node = _make_owner()
	var child = Node3D.new()
	owner_node.add_child(child)
	child.set_meta("my_float", 3.14)
	var s = PointsFromSceneSettings.new()
	s.import_metadata = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# The meta stream "my_float" must exist
	assert_object(out.findStream("my_float")).is_not_null()
	owner_node.free()
	node.free()

func test_import_property_creates_stream() -> void:
	var owner_node = _make_owner()
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	owner_node.add_child(mi)
	var s = PointsFromSceneSettings.new()
	# Import the "visible" property (a bool, converted to Int stream)
	var import_props: Array[StringName] = [&"visible"]
	s.import_properties = import_props
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out.findStream("visible")).is_not_null()
	owner_node.free()
	node.free()

func test_size_to_bounds_creates_nonzero_size() -> void:
	var owner_node = _make_owner()
	var mi = MeshInstance3D.new()
	mi.mesh = BoxMesh.new()   # default 1x1x1
	owner_node.add_child(mi)
	var s = PointsFromSceneSettings.new()
	s.size_to_bounds = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_int(size_stream.container.size()).is_equal(1)
	# BoxMesh default is 1x1x1, so the bound-derived size must be > 0 on all axes
	var sz = size_stream.container[0] as Vector3
	assert_bool(sz.x > 0.0).is_true()
	assert_bool(sz.y > 0.0).is_true()
	assert_bool(sz.z > 0.0).is_true()
	owner_node.free()
	node.free()

func test_output_point_count_matches_filtered_nodes() -> void:
	var owner_node = _make_owner()
	for i in range(5):
		owner_node.add_child(Node3D.new())
	var s = PointsFromSceneSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var rot_stream = out.findStream(FlowData.AttrRotation)
	var size_stream = out.findStream(FlowData.AttrSize)
	# All three standard streams must have the same count
	assert_int(pos_stream.container.size()).is_equal(5)
	assert_int(rot_stream.container.size()).is_equal(5)
	assert_int(size_stream.container.size()).is_equal(5)
	owner_node.free()
	node.free()
