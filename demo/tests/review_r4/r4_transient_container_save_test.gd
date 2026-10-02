# r4_transient_container_save_test.gd
# Review R4 (coverage, no bug found): content spawned under a parent that is
# not saved with the scene (a Create Target Node container with owner_policy
# Transient, or an unowned runtime node) still receives the scene owner, but
# PackedScene.pack() does not descend into unowned parents, so none of it is
# written to the scene file. Content under a saved container, or under a child
# of an instanced sub-scene, keeps the scene owner and is saved.
class_name R4TransientContainerSaveTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var _scene_root : Node3D
var _owner : FlowGraphNode3D

func before_test() -> void:
	_scene_root = auto_free(Node3D.new())
	_scene_root.name = "Level"
	add_child(_scene_root)
	_owner = FlowGraphNode3D.new()
	_owner.name = "Gen"
	_owner.generate_on_ready = false
	_scene_root.add_child(_owner)
	_owner.owner = _scene_root

func _graph(policy : int) -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 1}) \
		.node("target", "create_target_node", {"node_name": "Props", "owner_policy": policy}) \
		.node("spawn", "spawn_nodes", {"node_class": "Node3D", "spawn_parent_attribute": "@data.target"}) \
		.link("grid", 0, "target", 0) \
		.link("target", 0, "spawn", 0) \
		.build()

func _saved_paths() -> PackedStringArray:
	var packed := PackedScene.new()
	assert_int(packed.pack(_scene_root)).is_equal(OK)
	var state := packed.get_state()
	var out := PackedStringArray()
	for i in range(state.get_node_count()):
		out.append("%s/%s" % [state.get_node_path(i, true), state.get_node_name(i)])
	return out

func test_content_under_a_transient_container_is_not_saved() -> void:
	_owner.graph = _graph(CreateTargetNodeSettings.eOwnerPolicy.Transient)
	_owner.generate()
	assert_array(_owner.last_errors).is_empty()
	var container : Node3D = _owner.get_node("Props")
	assert_object(container.owner).is_null()
	assert_int(S.spawned(container).size()).is_equal(3)
	for p in _saved_paths():
		assert_bool(p.contains("Props")).override_failure_message("saved under the transient container: %s" % p).is_false()

func test_content_under_a_saved_container_is_saved() -> void:
	_owner.graph = _graph(CreateTargetNodeSettings.eOwnerPolicy.FollowComponent)
	_owner.generate()
	var container : Node3D = _owner.get_node("Props")
	assert_object(container.owner).is_same(_scene_root)
	for n in S.spawned(container):
		assert_object(n.owner).is_same(_scene_root)
	var saved := _saved_paths()
	assert_bool(saved.has("./Gen/Props")).is_true()
	assert_int(Array(saved).filter(func(p): return p.begins_with("./Gen/Props/")).size()).is_equal(3)

func test_content_under_an_instanced_sub_scene_child_is_still_owned() -> void:
	# Nodes added under a child of an instanced sub-scene are saved with the
	# outer scene (Godot keeps them as additions to the instance).
	var inner := Node3D.new()
	inner.name = "Room"
	var slot := Node3D.new()
	slot.name = "Slot"
	inner.add_child(slot)
	slot.owner = inner
	var packed := PackedScene.new()
	packed.pack(inner)
	inner.free()
	var room : Node3D = packed.instantiate()
	_scene_root.add_child(room)
	room.owner = _scene_root
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd").new()
	s.node_class = "Node3D"
	s.spawn_parent_path = "../Room/Slot"
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd").new()
	node.name = "spawn"
	node.settings = s
	S.run(node, S.points(2), _owner)
	var spawned := S.spawned(room.get_node("Slot"))
	assert_int(spawned.size()).is_equal(2)
	for n in spawned:
		assert_object(n.owner).is_same(_scene_root)

func test_content_under_an_unowned_runtime_node_is_not_saved() -> void:
	var holder := Node3D.new()
	holder.name = "RuntimeHolder"
	_scene_root.add_child(holder)
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd").new()
	s.node_class = "Node3D"
	s.spawn_parent_path = "../RuntimeHolder"
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd").new()
	node.name = "spawn"
	node.settings = s
	S.run(node, S.points(2), _owner)
	assert_int(S.spawned(holder).size()).is_equal(2)
	for p in _saved_paths():
		assert_bool(p.contains("RuntimeHolder")).override_failure_message("saved under an unsaved parent: %s" % p).is_false()
