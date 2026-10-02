# WP11 item 8: FlowGraphNode3D.cleanup() finds content outside its own subtree
# through the spawn parents of the content it recorded, instead of walking the
# parent's (or owner's) whole subtree, so a cell's cleanup no longer scans every
# sibling cell's content.
class_name ScopedCleanupTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var _root : Node3D

func before_test() -> void:
	_root = auto_free(Node3D.new())
	_root.name = "World"
	add_child(_root)

func _graph(spawn_parent_path := "", side := 3) -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": side, "y": 1, "z": side}) \
		.node("spawn", "spawn_nodes", {"node_class": "Node3D", "spawn_parent_path": spawn_parent_path}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "spawn", 0) \
		.link("spawn", 0, "out", 0) \
		.build()

func _component(g : FlowGraphResource, parent : Node, component_name : String) -> FlowGraphNode3D:
	var c := FlowGraphNode3D.new()
	c.name = component_name
	c.generate_on_ready = false
	c.graph = g
	parent.add_child(c)
	return c

func _tagged(parent : Node) -> Array:
	return parent.get_children().filter(func(n): return n.has_meta("flow_owner") and not n.is_queued_for_deletion())

func test_cell_cleanup_does_not_visit_sibling_content() -> void:
	var cells : Array[FlowGraphNode3D] = []
	for i in range(20):
		var c := _component(_graph(), _root, "FlowCell_%d" % i)
		c.generate()
		cells.append(c)
	assert_int(_tagged(cells[7]).size()).is_equal(9)
	cells[7].cleanup()
	assert_int(_tagged(cells[7]).size()).is_equal(0)
	assert_int(_tagged(cells[8]).size()).is_equal(9)
	# Its own 9 nodes plus nothing from the 19 siblings (171 nodes).
	assert_int(cells[7].last_cleanup_visits).is_less_equal(9)

func test_content_under_an_external_spawn_parent_is_cleaned() -> void:
	var shared := Node3D.new()
	shared.name = "Shared"
	_root.add_child(shared)
	var a := _component(_graph("../Shared"), _root, "A")
	var b := _component(_graph("../Shared"), _root, "B")
	a.generate()
	b.generate()
	assert_int(_tagged(shared).size()).is_equal(18)
	a.cleanup()
	var left := _tagged(shared)
	assert_int(left.size()).is_equal(9)
	for n in left:
		assert_int(int(n.get_meta("flow_owner").component)).is_equal(b.get_instance_id())
	# Unrelated nodes elsewhere are never visited: only Shared's 18 children.
	assert_int(a.last_cleanup_visits).is_less_equal(18)
	b.cleanup()
	assert_int(_tagged(shared).size()).is_equal(0)

func test_untracked_content_falls_back_to_the_scene_scan() -> void:
	# A third-party spawner that stamps flowOwnerMeta(ctx) itself, without
	# tagFlowContent: its component falls back to the pre-WP11 scan once.
	var shared := Node3D.new()
	shared.name = "Elsewhere"
	_root.add_child(shared)
	var c := _component(_graph(), _root, "C")
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path("spawn_nodes")).new()
	element.name = "custom"
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = c
	var manual := Node3D.new()
	manual.set_meta("flow_owner", element.flowOwnerMeta(ctx))
	shared.add_child(manual)
	c.cleanup()
	assert_int(_tagged(shared).size()).is_equal(0)

func test_records_are_released_after_cleanup() -> void:
	var c := _component(_graph(), _root, "D")
	c.generate()
	c.generate()
	c.cleanup()
	assert_int(c.recorded_content_count()).is_equal(0)
	c.generate()
	assert_int(c.recorded_content_count()).is_greater(0)
