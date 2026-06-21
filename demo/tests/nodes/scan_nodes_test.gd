# scan_nodes_test.gd
class_name ScanNodesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ScanNodesNode = preload("res://addons/flow_nodes_editor/nodes/scan_nodes.gd")
const ScanNodesSettings = preload("res://addons/flow_nodes_editor/nodes/scan_nodes_settings.gd")

# Build an owner parented under this (non-Node3D) suite so it becomes its
# own scene root. The node scans exactly the descendants we attach.
func _make_owner() -> FlowGraphNode3D:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	return owner_node

func _run(owner_node, settings) -> ScanNodesNode:
	var node = ScanNodesNode.new()
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
# Error path: null owner must not crash and must produce empty output
# ---------------------------------------------------------------------------
func test_null_owner_returns_empty_output() -> void:
	var s = ScanNodesSettings.new()
	var node = ScanNodesNode.new()
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
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(0)
	node.free()

# ---------------------------------------------------------------------------
# Basic: empty scene produces zero-point output
# ---------------------------------------------------------------------------
func test_empty_scene_zero_points() -> void:
	var owner_node = _make_owner()
	var s = ScanNodesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(0)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Core: two Node3D children at known positions are collected
# ---------------------------------------------------------------------------
func test_collects_node3d_children_and_positions() -> void:
	var owner_node = _make_owner()
	var a = Node3D.new()
	a.position = Vector3(1.0, 2.0, 3.0)
	owner_node.add_child(a)
	var b = Node3D.new()
	b.position = Vector3(4.0, 5.0, 6.0)
	owner_node.add_child(b)

	var s = ScanNodesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Core: output point count matches non-FlowGraphNode3D Node3D children
# ---------------------------------------------------------------------------
func test_output_point_count_matches_child_count() -> void:
	var owner_node = _make_owner()
	for i in range(5):
		owner_node.add_child(Node3D.new())

	var s = ScanNodesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(5)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# filter_by_class_name: only nodes of the specified class are returned
# ---------------------------------------------------------------------------
func test_filter_by_class_name_meshinstance() -> void:
	var owner_node = _make_owner()
	# Two MeshInstance3D children
	for i in range(2):
		var mi = MeshInstance3D.new()
		owner_node.add_child(mi)
	# Two plain Node3D children (should be excluded)
	for i in range(3):
		owner_node.add_child(Node3D.new())

	var s = ScanNodesSettings.new()
	s.filter_by_class_name = "MeshInstance3D"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# filter_by_name: wildcard name filter selects matching nodes only
# ---------------------------------------------------------------------------
func test_filter_by_name_wildcard() -> void:
	var owner_node = _make_owner()
	var keep_a = Node3D.new()
	keep_a.name = "target_one"
	owner_node.add_child(keep_a)
	var keep_b = Node3D.new()
	keep_b.name = "target_two"
	owner_node.add_child(keep_b)
	var skip = Node3D.new()
	skip.name = "other_node"
	owner_node.add_child(skip)

	var s = ScanNodesSettings.new()
	s.filter_by_name = "target_*"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# recursive = false: only direct children are collected, not grandchildren
# ---------------------------------------------------------------------------
func test_non_recursive_only_direct_children() -> void:
	var owner_node = _make_owner()
	# Direct child
	var direct = Node3D.new()
	owner_node.add_child(direct)
	# Intermediate node with a nested child — should be ignored when non-recursive
	var mid = Node3D.new()
	owner_node.add_child(mid)
	var nested = Node3D.new()
	mid.add_child(nested)

	var s = ScanNodesSettings.new()
	s.recursive = false
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	# direct + mid = 2 (mid itself is a direct child Node3D); nested is NOT collected
	assert_int(spos.size()).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# recursive = true: grandchildren are included
# ---------------------------------------------------------------------------
func test_recursive_includes_nested_nodes() -> void:
	var owner_node = _make_owner()
	var mid = Node3D.new()
	owner_node.add_child(mid)
	var nested = Node3D.new()
	mid.add_child(nested)

	var s = ScanNodesSettings.new()
	s.recursive = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	# mid + nested = 2
	assert_int(spos.size()).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# group_name: only nodes in the specified group are collected
# ---------------------------------------------------------------------------
func test_group_name_filter() -> void:
	var owner_node = _make_owner()
	var in_group = Node3D.new()
	owner_node.add_child(in_group)
	in_group.add_to_group("my_group")
	# Two nodes NOT in the group
	for i in range(2):
		owner_node.add_child(Node3D.new())

	var s = ScanNodesSettings.new()
	s.group_name = "my_group"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(1)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# import_metadata: float metadata appears as a custom stream sized to n points
# ---------------------------------------------------------------------------
func test_import_metadata_float_creates_stream() -> void:
	var owner_node = _make_owner()
	var a = Node3D.new()
	a.set_meta("my_weight", 0.5)
	owner_node.add_child(a)
	var b = Node3D.new()
	b.set_meta("my_weight", 1.0)
	owner_node.add_child(b)

	var s = ScanNodesSettings.new()
	s.import_metadata = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# A stream named "my_weight" should exist
	assert_bool(out.hasStream("my_weight")).is_true()
	var stream = out.findStream("my_weight")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# import_metadata: nodes without a given meta key leave the stream slot at default
# (stream is still sized to nsamples because addStream resizes to current point count)
# ---------------------------------------------------------------------------
func test_import_metadata_stream_size_equals_nsamples() -> void:
	var owner_node = _make_owner()
	var with_meta = Node3D.new()
	with_meta.set_meta("tag", 7)
	owner_node.add_child(with_meta)
	# Second node has NO "tag" meta
	owner_node.add_child(Node3D.new())

	var s = ScanNodesSettings.new()
	s.import_metadata = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_bool(out.hasStream("tag")).is_true()
	var stream = out.findStream("tag")
	# Stream was sized to nsamples (2) when added via addStream
	assert_int(stream.container.size()).is_equal(2)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# import_properties: "position" stream can be imported from node property
# ---------------------------------------------------------------------------
func test_import_properties_position() -> void:
	var owner_node = _make_owner()
	var a = Node3D.new()
	a.position = Vector3(3.0, 0.0, 0.0)
	owner_node.add_child(a)

	var s = ScanNodesSettings.new()
	s.import_properties.append("position")
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# A stream named "position" should exist (last path part is the stream name)
	assert_bool(out.hasStream("position")).is_true()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# size_to_bounds with a MeshInstance3D: ssize comes from AABB, not raw scale
# Without size_to_bounds, ssize equals the node's scale (default Vector3.ONE)
# With size_to_bounds and a MeshInstance3D without mesh, AABB is zero → ssize zero
# ---------------------------------------------------------------------------
func test_size_to_bounds_false_gives_scale() -> void:
	var owner_node = _make_owner()
	var mi = MeshInstance3D.new()
	mi.scale = Vector3(2.0, 3.0, 4.0)
	owner_node.add_child(mi)

	var s = ScanNodesSettings.new()
	s.size_to_bounds = false
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var ssize = out.getVector3Container(FlowData.AttrSize)
	assert_int(ssize.size()).is_equal(1)
	# Without size_to_bounds, ssize is the node scale
	assert_bool(ssize[0].is_equal_approx(Vector3(2.0, 3.0, 4.0))).is_true()
	owner_node.free()
	node.free()

func test_size_to_bounds_with_box_mesh() -> void:
	var owner_node = _make_owner()
	var mi = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(2.0, 4.0, 6.0)
	mi.mesh = box
	owner_node.add_child(mi)

	var s = ScanNodesSettings.new()
	s.size_to_bounds = true
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var ssize = out.getVector3Container(FlowData.AttrSize)
	assert_int(ssize.size()).is_equal(1)
	# AABB.size of a BoxMesh equals the mesh size; scale is default ONE so result = box.size
	assert_bool(ssize[0].is_equal_approx(Vector3(2.0, 4.0, 6.0))).is_true()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# position stream: node at a known global position records that position
# ---------------------------------------------------------------------------
func test_position_recorded_correctly() -> void:
	var owner_node = _make_owner()
	# owner_node is added to this (non-spatial) test suite, so global_position
	# equals the local position we set.
	var child = Node3D.new()
	child.position = Vector3(10.0, 20.0, 30.0)
	owner_node.add_child(child)

	var s = ScanNodesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(1)
	assert_bool(spos[0].is_equal_approx(Vector3(10.0, 20.0, 30.0))).is_true()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Non-Node3D children (plain Node, Control) are skipped — they are not Node3D
# ---------------------------------------------------------------------------
func test_non_node3d_children_are_skipped() -> void:
	var owner_node = _make_owner()
	# A plain Node is not a Node3D → must be skipped
	var plain = Node.new()
	owner_node.add_child(plain)
	# One real Node3D
	owner_node.add_child(Node3D.new())

	var s = ScanNodesSettings.new()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(1)
	owner_node.free()
	node.free()
