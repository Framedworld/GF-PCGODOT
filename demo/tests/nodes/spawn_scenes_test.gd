# spawn_scenes_test.gd
# Spawn Scenes against a live scene tree (FlowGraphNode3D owner added to the
# suite). PackedScenes are built in code. Only the presence of the
# "flow_owner" meta is asserted (value shape changes per RUNTIME_API_P0.md §5).
class_name SpawnScenesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const SpawnScenesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes.gd")
const SpawnScenesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	add_child(_owner)

## A PackedScene whose root is `root_class` named `root_name`, with a
## "Child" Node3D so assign_target_path can be exercised.
func _scene(root_name: String, root_class := "Node3D") -> PackedScene:
	var root : Node = ClassDB.instantiate(root_class)
	root.name = root_name
	if root is Node3D:
		var child := Node3D.new()
		child.name = "Child"
		root.add_child(child)
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _points(n: int) -> FlowData.Data:
	var positions := []
	for i in range(n):
		positions.append(Vector3(0, 0, i))
	return TestGraph.points(positions)

func _settings(scene: PackedScene = null) -> SpawnScenesSettings:
	var s = SpawnScenesSettings.new()
	s.scene = scene
	return s

func _make(s, node_name := "spawner") -> FlowNodeBase:
	var node = SpawnScenesNode.new()
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


func test_spawns_one_scene_instance_per_point() -> void:
	var node = _make(_settings(_scene("Crate")))
	_run(node, _points(3))
	assert_str(node.err).is_empty()
	var spawned = _spawned()
	assert_int(spawned.size()).is_equal(3)
	for i in range(3):
		assert_str(str(spawned[i].name)).is_equal("Scene_%04d" % i)
		assert_vector(spawned[i].position).is_equal(Vector3(0, 0, i))
		assert_object(spawned[i].get_node_or_null("Child")).is_not_null()
		assert_bool(spawned[i].has_meta("flow_owner")).is_true()

func test_output_passes_input_through() -> void:
	var node = _make(_settings(_scene("Crate")))
	var input = _points(1)
	_run(node, input)
	assert_object(node.generated_bulks[0][0]).is_same(input)

func test_clear_previous_instances_removes_own_previous_output() -> void:
	var node = _make(_settings(_scene("Crate")))
	_run(node, _points(2))
	var first = _spawned()
	_run(node, _points(1))
	for n in first:
		assert_bool(n.is_queued_for_deletion()).is_true()
	assert_int(_spawned().size()).is_equal(1)

func test_keeps_previous_instances_when_clear_disabled() -> void:
	var s = _settings(_scene("Crate"))
	s.clear_previous_instances = false
	var node = _make(s)
	_run(node, _points(2))
	_run(node, _points(2))
	assert_int(_spawned().size()).is_equal(4)

func test_clear_does_not_touch_other_spawners() -> void:
	var other = _make(_settings(_scene("Barrel")), "other_spawner")
	_run(other, _points(2))
	var node = _make(_settings(_scene("Crate")))
	_run(node, _points(1))
	_run(node, _points(1))
	assert_int(_spawned().size()).is_equal(3)

func _scene_with_marker(marker: String) -> PackedScene:
	var root := Node3D.new()
	root.name = "Root"
	var m := Node3D.new()
	m.name = "Marker"
	m.set_meta("variant", marker)
	root.add_child(m)
	m.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _variant_of(n: Node) -> String:
	var marker = n.get_node_or_null("Marker")
	return str(marker.get_meta("variant")) if marker else "?"

func test_variants_cycle_by_index() -> void:
	var s = _settings()
	s.scene_variants = [_scene_with_marker("a"), _scene_with_marker("b")] as Array[PackedScene]
	var node = _make(s)
	_run(node, _points(3))
	assert_array(_spawned().map(_variant_of)).is_equal(["a", "b", "a"])

func test_int_selector_picks_variant_and_clamps() -> void:
	var s = _settings()
	s.scene_variants = [_scene_with_marker("a"), _scene_with_marker("b")] as Array[PackedScene]
	s.scene_selector_attribute = "pick"
	var input = _points(3)
	input.registerStream("pick", PackedInt32Array([1, 0, 5]), FlowData.DataType.Int)
	var node = _make(s)
	_run(node, input)
	assert_array(_spawned().map(_variant_of)).is_equal(["b", "a", "b"])

func test_randomized_variants_respect_zero_weights() -> void:
	var s = _settings()
	s.scene_variants = [_scene_with_marker("a"), _scene_with_marker("b")] as Array[PackedScene]
	s.scene_variant_weights = [1.0, 0.0] as Array[float]
	s.randomize_scene_variants = true
	var node = _make(s)
	_run(node, _points(6))
	assert_array(_spawned().map(_variant_of)).is_equal(["a", "a", "a", "a", "a", "a"])

func test_scene_attribute_selects_scene_per_point() -> void:
	var a = _scene_with_marker("a")
	var b = _scene_with_marker("b")
	var s = _settings()
	s.scene_attribute = "prefab"
	var input = _points(3)
	input.registerStream("prefab", Array([b, a, b], TYPE_OBJECT, "Resource", null), FlowData.DataType.Resource)
	var node = _make(s)
	_run(node, input)
	assert_array(_spawned().map(_variant_of)).is_equal(["b", "a", "b"])

func test_missing_scene_attribute_is_an_error() -> void:
	var s = _settings(_scene("Crate"))
	s.scene_attribute = "not_there"
	var node = _make(s)
	_run(node, _points(2))
	assert_str(node.err).contains("not_there")
	assert_int(_spawned().size()).is_equal(0)

func test_assign_attributes_and_target_path() -> void:
	var s = _settings(_scene("Crate"))
	s.assign_target_path = "Child"
	s.assign_attributes = {"visible": "shown"}
	var input = _points(2)
	input.registerStream("shown", PackedByteArray([0, 1]), FlowData.DataType.Bool)
	var node = _make(s)
	_run(node, input)
	var spawned = _spawned()
	assert_bool(spawned[0].get_node("Child").visible).is_false()
	assert_bool(spawned[1].get_node("Child").visible).is_true()
	# The root itself is untouched.
	assert_bool(spawned[0].visible).is_true()

func test_non_node3d_scene_root_is_an_error() -> void:
	var node = _make(_settings(_scene("Plain", "Node")))
	_run(node, _points(2))
	assert_str(node.err).contains("not a Node3D")
	assert_int(_spawned().size()).is_equal(0)

func test_no_scene_source_is_an_error() -> void:
	var node = _make(_settings(null))
	_run(node, _points(2))
	assert_str(node.err).contains("No scene source")

func test_empty_input_passes_through_without_spawning() -> void:
	var node = _make(_settings(_scene("Crate")))
	var input = FlowDataScript.Data.new()
	_run(node, input)
	assert_object(node.generated_bulks[0][0]).is_same(input)
	assert_int(_spawned().size()).is_equal(0)

func test_unconnected_input_is_an_error() -> void:
	var node = _make(_settings(_scene("Crate")))
	_run(node, null)
	assert_str(node.err).contains("not connected")

func test_null_owner_sets_error_without_crashing() -> void:
	var node = _make(_settings(_scene("Crate")))
	_run_with_owner(node, _points(2), null)
	assert_str(node.err).is_not_empty()
	assert_int(_spawned().size()).is_equal(0)
