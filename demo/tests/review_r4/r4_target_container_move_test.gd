# r4_target_container_move_test.gd
# Review R4: Create Target Node looks for its previous container only under
# the current parent and name. After parent_path or node_name was edited, the
# previous generation's container stayed in the scene (with its groups, so
# get_nodes_in_group() still found it) next to the new one until cleanup().
class_name R4TargetContainerMoveTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "TargetOwner"
	_owner.generate_on_ready = false
	add_child(_owner)
	var holder := Node3D.new()
	holder.name = "Holder"
	_owner.add_child(holder)

func _node() -> FlowNodeBase:
	var s = load("res://addons/flow_nodes_editor/nodes/create_target_node_settings.gd").new()
	s.node_name = "Props"
	s.groups = PackedStringArray(["r4_props"])
	var node = load("res://addons/flow_nodes_editor/nodes/create_target_node.gd").new()
	node.name = "target"
	node.settings = s
	return node

func test_parent_path_edit_replaces_the_container() -> void:
	var node = _node()
	S.run(node, null, _owner)
	assert_object(_owner.get_node_or_null("Props")).is_not_null()
	node.settings.parent_path = "Holder"
	S.run(node, null, _owner)
	assert_int(S.spawned(_owner).filter(func(n): return n.has_meta("flow_target_name")).size()).is_equal(0)
	assert_object(_owner.get_node_or_null("Holder/Props")).is_not_null()
	assert_int(get_tree().get_nodes_in_group("r4_props").filter(func(n): return not n.is_queued_for_deletion()).size()).is_equal(1)

func test_node_name_edit_replaces_the_container() -> void:
	var node = _node()
	S.run(node, null, _owner)
	node.settings.node_name = "Lights"
	S.run(node, null, _owner)
	assert_object(_owner.get_node_or_null("Props")).is_null()
	assert_object(_owner.get_node_or_null("Lights")).is_not_null()

func test_same_settings_keep_the_container() -> void:
	var node = _node()
	S.run(node, null, _owner)
	var first : Node = _owner.get_node("Props")
	S.run(node, null, _owner)
	assert_object(_owner.get_node("Props")).is_same(first)
	assert_bool(first.is_queued_for_deletion()).is_false()

func test_user_node_with_the_same_name_is_untouched() -> void:
	var user := Node3D.new()
	user.name = "Lights"
	_owner.add_child(user)
	var node = _node()
	S.run(node, null, _owner)
	node.settings.node_name = "Other"
	S.run(node, null, _owner)
	assert_object(_owner.get_node_or_null("Lights")).is_same(user)
	assert_bool(user.is_queued_for_deletion()).is_false()
