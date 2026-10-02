# r4_spawn_session_test.gd
# Review R4: a spawner must only clear content from EARLIER generations, never
# content it (or another call of the same graph node) spawned earlier in the
# same generation. Before the fix, a spawner fed two bulks kept only the last
# bulk, and a spawner inside a loop body kept only the last iteration.
class_name R4SpawnSessionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SessionOwner"
	_owner.generate_on_ready = false
	add_child(_owner)

func _live_content(parent : Node) -> Array:
	var out := []
	for c in parent.get_children():
		if c.has_meta("flow_owner") and not c.is_queued_for_deletion():
			out.append(c)
	return out

func _two_bulk_graph(template : String, settings : Dictionary) -> FlowGraphResource:
	return TestGraph.new() \
		.node("g1", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("g2", "grid", {"x": 3, "y": 1, "z": 1, "origin": Vector3(0, 0, 5)}) \
		.node("spawn", template, settings) \
		.link("g1", 0, "spawn", 0) \
		.link("g2", 0, "spawn", 0) \
		.build()

func _loop_graph(iterations : int) -> FlowGraphResource:
	var body : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("spawn", "spawn_nodes", {"node_class": "Node3D"}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "spawn", 0) \
		.link("spawn", 0, "out", 0) \
		.build()
	return TestGraph.new() \
		.node("grid", "grid", {"x": iterations, "y": 1, "z": 1}) \
		.node("loop", "loop", {"graph": body}) \
		.node("o", "output", {"name": "r"}) \
		.link("grid", 0, "loop", 0) \
		.link("loop", 0, "o", 0) \
		.build()

func test_two_bulks_into_spawn_nodes_keep_both_bulks() -> void:
	_owner.graph = _two_bulk_graph("spawn_nodes", {"node_class": "Node3D"})
	_owner.generate()
	assert_array(_owner.last_errors).is_empty()
	assert_int(_live_content(_owner).size()).is_equal(5)
	# A second generation replaces (not accumulates) the content.
	_owner.generate()
	assert_int(_live_content(_owner).size()).is_equal(5)

func test_two_bulks_into_spawn_scenes_keep_both_bulks() -> void:
	var root := Node3D.new()
	root.name = "Crate"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	_owner.graph = _two_bulk_graph("spawn_scenes", {"scene": packed})
	_owner.generate()
	assert_int(_live_content(_owner).size()).is_equal(5)
	_owner.generate()
	assert_int(_live_content(_owner).size()).is_equal(5)

func test_two_bulks_into_spawn_meshes_keep_both_bulks() -> void:
	_owner.graph = _two_bulk_graph("spawn_meshes", {"mesh": BoxMesh.new(), "use_vertex_colors": false})
	_owner.generate()
	var mmis := _live_content(_owner)
	assert_int(mmis.size()).is_equal(2)
	var total := 0
	for m in mmis:
		total += m.multimesh.instance_count
	assert_int(total).is_equal(5)
	_owner.generate()
	assert_int(_live_content(_owner).size()).is_equal(2)

func test_two_bulks_with_pooling_keep_both_bulks() -> void:
	_owner.graph = _two_bulk_graph("spawn_nodes", {"node_class": "Node3D", "reuse_instances": true})
	_owner.generate()
	assert_int(_live_content(_owner).size()).is_equal(5)
	var first := _live_content(_owner).map(func(n): return n.get_instance_id())
	_owner.generate()
	var second := _live_content(_owner)
	assert_int(second.size()).is_equal(5)
	# Content of the earlier generation is still reused.
	var reused := 0
	for n in second:
		if first.has(n.get_instance_id()):
			reused += 1
	assert_int(reused).is_greater(0)

func test_spawner_in_loop_body_keeps_every_iteration() -> void:
	_owner.graph = _loop_graph(3)
	_owner.generate()
	assert_array(_owner.last_errors).is_empty()
	assert_int(_live_content(_owner).size()).is_equal(3)
	_owner.generate()
	assert_int(_live_content(_owner).size()).is_equal(3)
	_owner.graph = _loop_graph(2)
	_owner.generate()
	assert_int(_live_content(_owner).size()).is_equal(2)
	_owner.cleanup()
	assert_int(_live_content(_owner).size()).is_equal(0)

func test_spawner_in_loop_body_keeps_every_iteration_async() -> void:
	_owner.graph = _loop_graph(3)
	_owner.async_generation = true
	_owner.generate_async()
	_owner._finish_async_now(true)
	assert_int(_live_content(_owner).size()).is_equal(3)

func test_direct_element_runs_still_clear_between_runs() -> void:
	# An element run twice by hand (no executor session) keeps today's
	# behaviour: the second run replaces the first.
	var S = load("res://tests/spawn/spawn_test_support.gd")
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd").new()
	node.name = "spawn"
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd").new()
	s.node_class = "Node3D"
	node.settings = s
	S.run(node, S.points(3), _owner)
	S.run(node, S.points(2), _owner)
	assert_int(_live_content(_owner).size()).is_equal(2)
