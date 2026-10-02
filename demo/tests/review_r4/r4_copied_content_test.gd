# r4_copied_content_test.gd
# Review R4: generated content copied together with its component (editor
# duplicate, Node.duplicate(), or a scene packed and instanced again while the
# original component is still alive) carries a flow_owner meta naming the
# ORIGINAL component, which is still a live object. Before the fix neither the
# copy's spawners nor its cleanup() recognised that content, so every
# regeneration of the copy added a second set of nodes (with "@Node3D@N" auto
# names, because the copied names were taken).
class_name R4CopiedContentTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var _host : Node3D
var _owner : FlowGraphNode3D

func before_test() -> void:
	_host = auto_free(Node3D.new())
	_host.name = "Host"
	add_child(_host)
	_owner = FlowGraphNode3D.new()
	_owner.name = "Original"
	_owner.generate_on_ready = false
	_host.add_child(_owner)
	_owner.owner = _host

func _graph(reuse := false) -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 1}) \
		.node("spawn", "spawn_nodes", {"node_class": "Node3D", "reuse_instances": reuse}) \
		.link("grid", 0, "spawn", 0) \
		.build()

func _live_content(parent : Node) -> Array:
	var out := []
	for c in parent.get_children():
		if c.has_meta("flow_owner") and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _assert_unique_child_names(parent : Node) -> void:
	for c in parent.get_children():
		assert_bool(str(c.name).begins_with("@")).override_failure_message("auto-name %s" % c.name).is_false()
		assert_object(parent.get_node_or_null(NodePath(str(c.name)))).is_same(c)

func test_duplicated_component_regenerates_without_duplicates() -> void:
	_owner.graph = _graph()
	_owner.generate()
	var copy : FlowGraphNode3D = _owner.duplicate()
	copy.name = "Copy"
	_host.add_child(copy)
	assert_int(_live_content(copy).size()).is_equal(3)
	copy.generate()
	assert_int(_live_content(copy).size()).is_equal(3)
	_assert_unique_child_names(copy)
	# The original keeps its own content.
	assert_int(_live_content(_owner).size()).is_equal(3)

func test_duplicated_component_cleanup_frees_copied_content() -> void:
	_owner.graph = _graph()
	_owner.generate()
	var copy : FlowGraphNode3D = _owner.duplicate()
	copy.name = "Copy"
	_host.add_child(copy)
	copy.cleanup()
	assert_int(_live_content(copy).size()).is_equal(0)
	assert_int(_live_content(_owner).size()).is_equal(3)

func test_duplicated_component_with_pooling() -> void:
	_owner.graph = _graph(true)
	_owner.generate()
	var copy : FlowGraphNode3D = _owner.duplicate()
	copy.name = "Copy"
	_host.add_child(copy)
	var copied := _live_content(copy).map(func(n): return n.get_instance_id())
	copy.generate()
	var now := _live_content(copy)
	assert_int(now.size()).is_equal(3)
	# Pooling takes the copied nodes over instead of adding new ones.
	for n in now:
		assert_bool(copied.has(n.get_instance_id())).is_true()
	assert_int(_live_content(_owner).size()).is_equal(3)

func test_packed_and_reinstanced_scene_regenerates_without_duplicates() -> void:
	_owner.graph = _graph()
	_owner.generate()
	for c in _owner.get_children():
		c.owner = _host
	var packed := PackedScene.new()
	assert_int(packed.pack(_host)).is_equal(OK)
	var instance : Node3D = auto_free(packed.instantiate())
	add_child(instance)
	var comp : FlowGraphNode3D = instance.get_node("Original")
	assert_int(_live_content(comp).size()).is_equal(3)
	comp.generate()
	assert_int(_live_content(comp).size()).is_equal(3)
	_assert_unique_child_names(comp)
	comp.cleanup()
	assert_int(_live_content(comp).size()).is_equal(0)
	assert_int(_live_content(_owner).size()).is_equal(3)

func test_live_foreign_component_content_outside_own_subtree_is_kept() -> void:
	# Content another live component spawned (and recorded) under a shared
	# parent is still that component's: a second component with a spawner of
	# the same name leaves it alone.
	var shared := Node3D.new()
	shared.name = "Shared"
	_host.add_child(shared)
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("spawn", "spawn_nodes", {"node_class": "Node3D", "spawn_parent_path": "../Shared"}) \
		.link("grid", 0, "spawn", 0) \
		.build()
	_owner.graph = graph
	var other := FlowGraphNode3D.new()
	other.name = "Other"
	other.generate_on_ready = false
	_host.add_child(other)
	other.graph = graph
	_owner.generate()
	other.generate()
	assert_int(_live_content(shared).size()).is_equal(4)
	_owner.generate()
	assert_int(_live_content(shared).size()).is_equal(4)
	_assert_unique_child_names(shared)
	other.cleanup()
	assert_int(_live_content(shared).size()).is_equal(2)
