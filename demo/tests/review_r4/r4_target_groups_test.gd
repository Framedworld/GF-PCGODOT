# r4_target_groups_test.gd
# Review R4: Create Target Node reuses its container across generations. Groups
# removed from the `groups` setting stayed on the reused container, so
# get_nodes_in_group() kept returning it until cleanup(). Groups the user (or a
# game script) added to the container are not touched.
class_name R4TargetGroupsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "TargetOwner"
	_owner.generate_on_ready = false
	add_child(_owner)

func _node(groups : Array) -> FlowNodeBase:
	var s = load("res://addons/flow_nodes_editor/nodes/create_target_node_settings.gd").new()
	s.node_name = "Props"
	s.groups = PackedStringArray(groups)
	var node = load("res://addons/flow_nodes_editor/nodes/create_target_node.gd").new()
	node.name = "target"
	node.settings = s
	return node

func test_groups_removed_from_settings_leave_the_reused_container() -> void:
	var node = _node(["r4_a", "r4_b"])
	S.run(node, null, _owner)
	var container : Node3D = _owner.get_node("Props")
	assert_bool(container.is_in_group("r4_a")).is_true()
	assert_bool(container.is_in_group("r4_b")).is_true()
	container.add_to_group("r4_user")
	node.settings.groups = PackedStringArray(["r4_b", "r4_c"])
	S.run(node, null, _owner)
	assert_object(_owner.get_node("Props")).is_same(container)
	assert_bool(container.is_in_group("r4_a")).is_false()
	assert_bool(container.is_in_group("r4_b")).is_true()
	assert_bool(container.is_in_group("r4_c")).is_true()
	assert_bool(container.is_in_group("r4_user")).is_true()
	assert_array(get_tree().get_nodes_in_group("r4_a")).is_empty()

func test_group_the_user_added_before_is_kept_when_settings_add_and_drop_it() -> void:
	# A group that was on the container before this node first listed it is
	# not the node's to remove.
	var node = _node([])
	S.run(node, null, _owner)
	var container : Node3D = _owner.get_node("Props")
	container.add_to_group("r4_shared", true)
	node.settings.groups = PackedStringArray(["r4_shared"])
	S.run(node, null, _owner)
	node.settings.groups = PackedStringArray([])
	S.run(node, null, _owner)
	assert_bool(container.is_in_group("r4_shared")).is_true()
