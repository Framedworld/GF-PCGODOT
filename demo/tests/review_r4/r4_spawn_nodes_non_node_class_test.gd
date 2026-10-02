# r4_spawn_nodes_non_node_class_test.gd
# Review R4: Spawn Nodes with a node_class (or script) that instantiates
# something other than a Node (Resource, RefCounted, a script extending
# Resource) raised a SCRIPT ERROR ("Trying to return value of type Resource
# from a function whose return type is Node") instead of the node's own
# error. It must report "is not a Node3D subclass" and spawn nothing.
class_name R4SpawnNodesNonNodeClassTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "NodesOwner"
	_owner.generate_on_ready = false
	add_child(_owner)

func _run(node_class : String) -> FlowNodeBase:
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd").new()
	s.node_class = node_class
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd").new()
	node.name = "nodes"
	node.settings = s
	S.run(node, S.points(2), _owner)
	return node

func test_resource_class_reports_not_a_node3d() -> void:
	var node = _run("Resource")
	assert_str(node.err).contains("is not a Node3D subclass")
	assert_int(S.spawned(_owner).size()).is_equal(0)

func test_refcounted_class_reports_not_a_node3d() -> void:
	var node = _run("RefCounted")
	assert_str(node.err).contains("is not a Node3D subclass")
	assert_int(S.spawned(_owner).size()).is_equal(0)

func test_resource_script_reports_not_a_node3d() -> void:
	var node = _run("res://addons/flow_nodes_editor/spawn/flow_mesh_spawn_entry.gd")
	assert_str(node.err).contains("is not a Node3D subclass")
	assert_int(S.spawned(_owner).size()).is_equal(0)

func test_plain_node_class_still_reports_not_a_node3d() -> void:
	var node = _run("Node")
	assert_str(node.err).contains("is not a Node3D subclass")
	assert_int(S.spawned(_owner).size()).is_equal(0)
