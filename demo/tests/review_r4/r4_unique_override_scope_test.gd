# r4_unique_override_scope_test.gd
# Review R4: a "%Unique" property override path is scoped to the spawned
# instance (docs/_round2/WP3.md). Godot's "%Name" lookup falls back to the
# node's OWNER scene when the node itself owns no such unique node, and the
# spawners give every spawned root the scene owner. Before the fix an instance
# without %Light silently wrote every point's value into the %Light of the
# scene that contains the generator.
class_name R4UniqueOverrideScopeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")

var _scene_root : Node3D
var _owner : FlowGraphNode3D
var _scene_light : OmniLight3D

func before_test() -> void:
	_scene_root = auto_free(Node3D.new())
	_scene_root.name = "Level"
	add_child(_scene_root)
	_owner = FlowGraphNode3D.new()
	_owner.name = "Gen"
	_owner.generate_on_ready = false
	_scene_root.add_child(_owner)
	_owner.owner = _scene_root
	_scene_light = OmniLight3D.new()
	_scene_light.name = "Light"
	_scene_root.add_child(_scene_light)
	_scene_light.owner = _scene_root
	_scene_light.unique_name_in_owner = true
	_scene_light.light_energy = 1.0

func _packed(with_light : bool) -> PackedScene:
	var root := Node3D.new()
	root.name = "Lamp"
	if with_light:
		var l := OmniLight3D.new()
		l.name = "Light"
		root.add_child(l)
		l.owner = root
		l.unique_name_in_owner = true
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _run(scene : PackedScene, overrides : Dictionary) -> FlowNodeBase:
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_scenes_settings.gd").new()
	s.scene = scene
	s.property_overrides = overrides
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_scenes.gd").new()
	node.name = "lamps"
	node.settings = s
	var d := S.points(2)
	d.registerStream("energy", PackedFloat32Array([7.0, 9.0]), FlowData.DataType.Float)
	S.run(node, d, _owner)
	return node

func test_spawned_instances_are_owned_by_the_scene() -> void:
	# Precondition of the bug: spawned roots get the scene owner.
	var node = _run(_packed(true), {})
	var spawned := S.spawned(_owner)
	assert_int(spawned.size()).is_equal(2)
	assert_object(spawned[0].owner).is_same(_scene_root)

func test_unique_path_missing_in_instance_does_not_reach_the_scene() -> void:
	var node = _run(_packed(false), {"energy": "%Light:light_energy"})
	assert_float(_scene_light.light_energy).is_equal(1.0)
	assert_str(node.err).contains("%Light:light_energy")

func test_unique_path_inside_instance_still_resolves() -> void:
	var node = _run(_packed(true), {"energy": "%Light:light_energy"})
	assert_str(node.err).is_empty()
	var spawned := S.spawned(_owner)
	assert_float(spawned[0].get_node("Light").light_energy).is_equal(7.0)
	assert_float(spawned[1].get_node("Light").light_energy).is_equal(9.0)
	assert_float(_scene_light.light_energy).is_equal(1.0)

func test_resolve_property_target_scopes_unique_names() -> void:
	var lamp : Node = _packed(false).instantiate()
	_scene_root.add_child(lamp)
	lamp.owner = _scene_root
	assert_array(FlowSpawnUtil.resolve_property_target(lamp, "%Light:light_energy")).is_empty()
	# Unscoped (Apply On Actor) keeps Godot's lookup.
	assert_array(FlowSpawnUtil.resolve_property_target(lamp, "%Light:light_energy", false)).is_not_empty()
	lamp.queue_free()

func test_apply_on_actor_keeps_godot_unique_lookup_for_scene_targets() -> void:
	# Apply On Actor targets live in the scene: "%Light" from a plain target
	# resolves in the target's owner scene, as Godot does (unchanged).
	var target := Node3D.new()
	target.name = "Marker"
	_scene_root.add_child(target)
	target.owner = _scene_root
	var s = load("res://addons/flow_nodes_editor/nodes/apply_on_actor_settings.gd").new()
	s.target_mode = s.eTargetMode.FromNodeStream
	s.property_overrides = {"energy": "%Light:light_energy"}
	var node = load("res://addons/flow_nodes_editor/nodes/apply_on_actor.gd").new()
	node.name = "apply"
	node.settings = s
	var d := S.points(1)
	d.registerStream("energy", PackedFloat32Array([5.0]), FlowData.DataType.Float)
	d.registerStream(s.target_stream_attribute, Array([target], TYPE_OBJECT, "Node", null), FlowData.DataType.NodePath)
	S.run(node, d, _owner)
	assert_str(node.err).is_empty()
	assert_float(_scene_light.light_energy).is_equal(5.0)
