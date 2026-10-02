# spawn_nodes_test.gd
# Spawn Nodes against a live scene tree (FlowGraphNode3D owner added to the
# suite). Only the presence of the "flow_owner" meta is asserted; its value
# shape is scheduled to change (RUNTIME_API_P0.md §5).
class_name SpawnNodesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const SpawnNodesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd")
const SpawnNodesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	add_child(_owner)

func _points(n: int) -> FlowData.Data:
	var positions := []
	for i in range(n):
		positions.append(Vector3(i, 1, 0))
	return TestGraph.points(positions)

func _settings(node_class := "Node3D") -> SpawnNodesSettings:
	var s = SpawnNodesSettings.new()
	s.node_class = node_class
	return s

func _make(s, node_name := "spawner") -> FlowNodeBase:
	var node = SpawnNodesNode.new()
	node.name = node_name
	node.settings = s
	return auto_free(node)

func _run(node, input) -> void:
	_run_with_owner(node, input, _owner)

func _run_with_owner(node, input, owner) -> void:
	node.inputs = [input]
	var ctx = TestGraph.make_ctx(owner)
	node.preExecute(ctx)
	node.execute(ctx)

func _spawned(parent: Node = null) -> Array:
	if parent == null:
		parent = _owner
	return parent.get_children().filter(func(c): return c.has_meta("flow_owner") and not c.is_queued_for_deletion())

func _classes(nodes: Array) -> Array:
	return nodes.map(func(n): return n.get_class())


func test_spawns_one_node_per_point_with_transform_and_meta() -> void:
	var node = _make(_settings("Node3D"))
	_run(node, _points(3))
	assert_str(node.err).is_empty()
	var spawned = _spawned()
	assert_int(spawned.size()).is_equal(3)
	for i in range(3):
		var n : Node3D = spawned[i]
		assert_str(n.get_class()).is_equal("Node3D")
		assert_str(str(n.name)).is_equal("Node3D_%04d" % i)
		assert_vector(n.position).is_equal(Vector3(i, 1, 0))
		assert_bool(n.has_meta("flow_owner")).is_true()

func test_output_passes_input_through() -> void:
	var node = _make(_settings())
	var input = _points(2)
	_run(node, input)
	assert_object(node.generated_bulks[0][0]).is_same(input)

func test_clear_previous_instances_removes_own_previous_output() -> void:
	var node = _make(_settings())
	_run(node, _points(2))
	var first = _spawned()
	_run(node, _points(1))
	for n in first:
		assert_bool(n.is_queued_for_deletion()).is_true()
	assert_int(_spawned().size()).is_equal(1)

func test_keeps_previous_instances_when_clear_disabled() -> void:
	var s = _settings()
	s.clear_previous_instances = false
	var node = _make(s)
	_run(node, _points(2))
	_run(node, _points(1))
	assert_int(_spawned().size()).is_equal(3)

func test_clear_does_not_touch_other_spawners_or_plain_children() -> void:
	var plain = Node3D.new()
	_owner.add_child(plain)
	var other = _make(_settings(), "other_spawner")
	_run(other, _points(2))
	var node = _make(_settings())
	_run(node, _points(1))
	_run(node, _points(1))
	assert_bool(plain.is_queued_for_deletion()).is_false()
	assert_int(_spawned().size()).is_equal(3)

func test_class_variants_cycle_by_index() -> void:
	var s = _settings()
	s.node_class_variants = ["Node3D", "Marker3D", " "] as Array[String]
	var node = _make(s)
	_run(node, _points(4))
	# Blank variant entries are dropped, leaving two.
	assert_array(_classes(_spawned())).is_equal(["Node3D", "Marker3D", "Node3D", "Marker3D"])

func test_selector_attribute_picks_variant_modulo() -> void:
	var s = _settings()
	s.node_class_variants = ["Node3D", "Marker3D"] as Array[String]
	s.node_selector_attribute = "kind"
	var input = _points(4)
	input.registerStream("kind", PackedInt32Array([1, 1, 0, 3]), FlowData.DataType.Int)
	var node = _make(s)
	_run(node, input)
	assert_array(_classes(_spawned())).is_equal(["Marker3D", "Marker3D", "Node3D", "Marker3D"])

func test_randomized_variants_are_deterministic() -> void:
	var s = _settings()
	s.node_class_variants = ["Node3D", "Marker3D", "Path3D"] as Array[String]
	s.randomize_node_variants = true
	var node = _make(s)
	_run(node, _points(12))
	var first = _classes(_spawned())
	_run(node, _points(12))
	assert_array(_classes(_spawned())).is_equal(first)

func test_assign_attributes_sets_properties_from_streams() -> void:
	var s = _settings("OmniLight3D")
	s.assign_attributes = {"light_energy": "energy", "visible": "shown"}
	var input = _points(3)
	input.registerStream("energy", PackedFloat32Array([0.5, 1.5, 2.5]), FlowData.DataType.Float)
	input.registerStream("shown", PackedByteArray([1]), FlowData.DataType.Bool)
	var node = _make(s)
	_run(node, input)
	var spawned = _spawned()
	assert_float(spawned[0].light_energy).is_equal_approx(0.5, 0.0001)
	assert_float(spawned[2].light_energy).is_equal_approx(2.5, 0.0001)
	for n in spawned:
		assert_bool(n.visible).is_true()

func test_assign_attribute_size_mismatch_is_an_error() -> void:
	var s = _settings("OmniLight3D")
	s.assign_attributes = {"light_energy": "energy"}
	var input = _points(3)
	input.registerStream("energy", PackedFloat32Array([0.5, 1.5]), FlowData.DataType.Float)
	var node = _make(s)
	_run(node, input)
	assert_str(node.err).contains("energy")
	assert_int(_spawned().size()).is_equal(0)

func test_assign_target_path_targets_a_child_of_the_spawned_node() -> void:
	# Current behaviour: the assign target child is resolved right after spawn,
	# so only children created by the class itself can be targeted; a missing
	# child silently falls back to the spawned node.
	var s = _settings("Node3D")
	s.assign_target_path = "DoesNotExist"
	s.assign_attributes = {"visible": "shown"}
	var input = _points(1)
	input.registerStream("shown", PackedByteArray([0]), FlowData.DataType.Bool)
	var node = _make(s)
	_run(node, input)
	assert_bool(_spawned()[0].visible).is_false()

func test_non_node3d_class_is_an_error() -> void:
	var node = _make(_settings("Node"))
	_run(node, _points(2))
	assert_str(node.err).contains("not a Node3D")
	assert_int(_spawned().size()).is_equal(0)

func test_unknown_class_is_an_error() -> void:
	var node = _make(_settings("NoSuchClassAnywhere"))
	_run(node, _points(2))
	assert_str(node.err).contains("NoSuchClassAnywhere")

func test_selector_of_wrong_type_is_an_error() -> void:
	var s = _settings()
	s.node_class_variants = ["Node3D", "Marker3D"] as Array[String]
	s.node_selector_attribute = "kind"
	var input = _points(2)
	input.registerStream("kind", PackedStringArray(["a", "b"]), FlowData.DataType.String)
	var node = _make(s)
	_run(node, input)
	assert_str(node.err).contains("must be Int or Float")

func test_spawn_parent_path_places_nodes_under_that_node() -> void:
	var holder = Node3D.new()
	holder.name = "Holder"
	_owner.add_child(holder)
	var s = _settings()
	s.spawn_parent_path = "Holder"
	var node = _make(s)
	_run(node, _points(2))
	assert_int(_spawned(holder).size()).is_equal(2)

func test_empty_input_passes_through_without_spawning() -> void:
	var node = _make(_settings())
	var input = FlowDataScript.Data.new()
	_run(node, input)
	assert_object(node.generated_bulks[0][0]).is_same(input)
	assert_int(_spawned().size()).is_equal(0)

func test_unconnected_input_is_an_error() -> void:
	var node = _make(_settings())
	_run(node, null)
	assert_str(node.err).contains("not connected")

func test_null_owner_sets_error_without_crashing() -> void:
	var node = _make(_settings())
	_run_with_owner(node, _points(2), null)
	assert_str(node.err).is_not_empty()
	assert_int(_spawned().size()).is_equal(0)
