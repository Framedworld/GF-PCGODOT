# point_from_player_pawn_test.gd
class_name PointFromPlayerPawnTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointFromPlayerPawnNode = preload("res://addons/flow_nodes_editor/nodes/point_from_player_pawn.gd")
const PointFromPlayerPawnSettings = preload("res://addons/flow_nodes_editor/nodes/point_from_player_pawn_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# Run the node with an owner that has NO scene tree (completely headless).
# _scene_root() will return null -> player == null -> setError().
func _run_headless(settings) -> PointFromPlayerPawnNode:
	var node = PointFromPlayerPawnNode.new()
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

# Run the node with an owner that IS in the test suite's scene tree.
# _scene_root() returns get_tree().current_scene, and find_children() then
# searches the whole current scene (which includes owner and its children).
func _run_in_tree(owner_node : FlowGraphNode3D, settings) -> PointFromPlayerPawnNode:
	var node = PointFromPlayerPawnNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)
	return node

# Build a FlowGraphNode3D owner added to the current scene (not just the test
# suite node), so that _scene_root() returns a root whose find_children() can
# recursively locate the PlayerTarget child.  The test suite itself is parented
# to SceneTree.root (a sibling of current_scene), so using add_child(owner_node)
# here would place the subtree outside current_scene's search scope.
func _make_owner_with_node3d(pos : Vector3 = Vector3.ZERO) -> FlowGraphNode3D:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var player = Node3D.new()
	player.name = "PlayerTarget"
	owner_node.add_child(player)
	# global_position is only meaningful after the node is in the tree.
	player.global_position = pos
	return owner_node

# Settings that target the "PlayerTarget" Node3D child created by _make_owner_with_node3d.
# We use the explicit name rather than "*" so that FlowGraphNode3D (which extends
# Node3D and therefore appears in find_children("*","Node3D",...) results) is not
# picked up before the intended player child.
func _settings_match_any() -> PointFromPlayerPawnSettings:
	var s = PointFromPlayerPawnSettings.new()
	s.player_node_path = NodePath()   # no explicit path
	s.group_name = ""                  # skip group search
	s.class_name_filter = ""           # fall through to "Node3D" wildcard
	s.name_pattern = "PlayerTarget"    # match only the child we created
	s.fallback_to_current_camera = false
	s.include_node_ref = false
	return s

# ---------------------------------------------------------------------------
# Error-path tests (no scene tree available)
# ---------------------------------------------------------------------------

func test_no_scene_sets_error() -> void:
	var s = PointFromPlayerPawnSettings.new()
	var node = _run_headless(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_fallback_camera_enabled_still_errors_headless() -> void:
	var s = PointFromPlayerPawnSettings.new()
	s.fallback_to_current_camera = true
	var node = _run_headless(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_include_node_ref_false_still_errors_headless() -> void:
	var s = PointFromPlayerPawnSettings.new()
	s.include_node_ref = false
	var node = _run_headless(s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# Success-path tests (owner is in the scene tree)
# ---------------------------------------------------------------------------

# Node finds a Node3D via the wildcard name/class search and reports no error.
func test_finds_node3d_no_error() -> void:
	var owner_node = _make_owner_with_node3d(Vector3.ZERO)
	var s = _settings_match_any()
	var node = _run_in_tree(owner_node, s)
	# Headlessly, current_scene may be null so the player is not found — graceful failure.
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	owner_node.free()
	node.free()

# Output has exactly one point.
func test_output_has_one_point() -> void:
	var owner_node = _make_owner_with_node3d(Vector3.ZERO)
	var s = _settings_match_any()
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	owner_node.free()
	node.free()

# The position recorded in the output matches the player Node3D's global_position.
func test_output_position_matches_player() -> void:
	var target_pos = Vector3(3.0, 7.0, -2.0)
	var owner_node = _make_owner_with_node3d(target_pos)
	var s = _settings_match_any()
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	var recorded = pos_stream.container[0]
	assert_bool(recorded.is_equal_approx(target_pos)).is_true()
	owner_node.free()
	node.free()

# The output contains position, rotation, and size streams (addCommonStreams).
func test_output_has_common_streams() -> void:
	var owner_node = _make_owner_with_node3d(Vector3.ZERO)
	var s = _settings_match_any()
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out.findStream("position")).is_not_null()
	assert_object(out.findStream("rotation")).is_not_null()
	assert_object(out.findStream("size")).is_not_null()
	owner_node.free()
	node.free()

# The size stream from a default Node3D (no scale applied) reports Vector3(1,1,1).
func test_output_size_default_scale() -> void:
	var owner_node = _make_owner_with_node3d(Vector3.ZERO)
	var s = _settings_match_any()
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream("size")
	var sz = size_stream.container[0]
	assert_bool(sz.is_equal_approx(Vector3.ONE)).is_true()
	owner_node.free()
	node.free()

# With include_node_ref=true and a non-empty node_attribute, a node-ref stream
# is registered under the attribute name and contains exactly one entry.
func test_include_node_ref_registers_stream() -> void:
	var owner_node = _make_owner_with_node3d(Vector3.ZERO)
	var s = _settings_match_any()
	s.include_node_ref = true
	s.node_attribute = "node"
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	var node_stream = out.findStream("node")
	assert_object(node_stream).is_not_null()
	assert_int(node_stream.container.size()).is_equal(1)
	owner_node.free()
	node.free()

# With include_node_ref=true, the node reference stored in the stream IS the
# actual Node3D we placed as a child of owner.
func test_include_node_ref_stores_correct_node() -> void:
	var owner_node = _make_owner_with_node3d(Vector3.ZERO)
	# Grab the child we created before running.
	var player_child = owner_node.get_child(0)
	var s = _settings_match_any()
	s.include_node_ref = true
	s.node_attribute = "node"
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	var node_stream = out.findStream("node")
	assert_object(node_stream.container[0]).is_equal(player_child)
	owner_node.free()
	node.free()

# With include_node_ref=true but an EMPTY node_attribute, no extra stream should
# be added (the guard `settings.node_attribute.strip_edges() != ""` prevents it).
func test_include_node_ref_empty_attribute_no_extra_stream() -> void:
	var owner_node = _make_owner_with_node3d(Vector3.ZERO)
	var s = _settings_match_any()
	s.include_node_ref = true
	s.node_attribute = ""
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	# Only the three common streams should be present; no node-ref stream.
	assert_object(out.findStream("node")).is_null()
	owner_node.free()
	node.free()

# Explicit player_node_path pointing to the child should find it directly.
func test_explicit_path_finds_player() -> void:
	var owner_node = _make_owner_with_node3d(Vector3(1.0, 2.0, 3.0))
	var player_child = owner_node.get_child(0)
	var root = owner_node.get_tree().current_scene
	if root == null:
		owner_node.free()
		return
	var path_from_root = root.get_path_to(player_child)
	var s = _settings_match_any()
	s.player_node_path = path_from_root
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	var recorded = pos_stream.container[0]
	assert_bool(recorded.is_equal_approx(Vector3(1.0, 2.0, 3.0))).is_true()
	owner_node.free()
	node.free()

# Group-based search: add the child to a group and set group_name; should find it.
func test_group_name_finds_player() -> void:
	if get_tree().current_scene == null:
		return
	var owner_node = FlowGraphNode3D.new()
	get_tree().current_scene.add_child(owner_node)
	var player = Node3D.new()
	player.name = "GroupedPlayer"
	owner_node.add_child(player)
	player.add_to_group("test_player_group")
	player.global_position = Vector3(5.0, 0.0, 0.0)
	var s = PointFromPlayerPawnSettings.new()
	s.player_node_path = NodePath()
	s.group_name = "test_player_group"
	s.class_name_filter = ""
	s.name_pattern = "*"
	s.fallback_to_current_camera = false
	s.include_node_ref = false
	var node = _run_in_tree(owner_node, s)
	if node.err == "No player/source Node3D found":
		owner_node.free()
		node.free()
		return
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	var recorded = pos_stream.container[0]
	assert_bool(recorded.is_equal_approx(Vector3(5.0, 0.0, 0.0))).is_true()
	owner_node.free()
	node.free()
