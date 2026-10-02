# property_overrides_test.gd
# Attribute-driven spawn (Unreal's Spawn Actor property overrides):
# property_overrides on spawn_scenes, spawn_nodes and apply_on_actor map a
# point attribute to a node property path (nested properties, child paths,
# %unique names) with type coercion, applied after instancing.
class_name PropertyOverridesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const SpawnScenesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes.gd")
const SpawnScenesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes_settings.gd")
const SpawnNodesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd")
const SpawnNodesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd")
const ApplyOnActorNode = preload("res://addons/flow_nodes_editor/nodes/apply_on_actor.gd")
const ApplyOnActorSettings = preload("res://addons/flow_nodes_editor/nodes/apply_on_actor_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	add_child(_owner)

## Root "Unit" (script with `hp` set to 5 in _ready), child "Light"
## (OmniLight3D) and unique-named "%Mesh" with a per-instance material.
func _unit_scene() -> PackedScene:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar hp : int = 1\nvar ready_ran := false\nfunc _ready():\n\thp = 5\n\tready_ran = true\n"
	script.reload()
	var root := Node3D.new()
	root.name = "Unit"
	root.set_script(script)
	var light := OmniLight3D.new()
	light.name = "Light"
	root.add_child(light)
	light.owner = root
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var mat := StandardMaterial3D.new()
	mat.resource_local_to_scene = true
	mesh.material_override = mat
	root.add_child(mesh)
	mesh.owner = root
	mesh.unique_name_in_owner = true
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _scenes_node(overrides : Dictionary) -> Node:
	var s = SpawnScenesSettings.new()
	s.scene = _unit_scene()
	s.property_overrides = overrides
	var node = SpawnScenesNode.new()
	node.name = "scenes"
	node.settings = s
	return auto_free(node)

func _input3() -> FlowData.Data:
	var d := S.points(3)
	d.registerStream("energy", PackedInt32Array([1, 2, 3]), FlowData.DataType.Int)
	d.registerStream("tint", PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]), FlowData.DataType.Vector)
	d.registerStream("height", PackedFloat32Array([0.5, 1.5, 2.5]), FlowData.DataType.Float)
	d.registerStream("hp", PackedFloat32Array([7.9, 8.2, 9.0]), FlowData.DataType.Float)
	d.registerStream("on", PackedByteArray([1, 0, 1]), FlowData.DataType.Bool)
	return d

func test_scene_overrides_child_nested_unique_and_root_paths() -> void:
	var node = _scenes_node({
		"energy": "Light:light_energy",
		"tint": "%Mesh:material_override:albedo_color",
		"height": "position:y",
		"hp": "hp",
		"on": "Light:visible",
	})
	S.run(node, _input3(), _owner)
	assert_str(node.err).is_empty()
	var units = S.spawned(_owner)
	assert_int(units.size()).is_equal(3)
	var colors := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1)]
	for i in range(3):
		var unit = units[i]
		assert_bool(unit.ready_ran).is_true()
		# Applied after _ready: the attribute wins, Float truncated to int.
		assert_int(unit.hp).is_equal([7, 8, 9][i])
		assert_float(unit.get_node("Light").light_energy).is_equal(float(i + 1))
		assert_bool(unit.get_node("Light").visible).is_equal(i != 1)
		assert_that(unit.get_node("Mesh").material_override.albedo_color).is_equal(colors[i])
		# position.x/z come from the point; only y is overridden.
		assert_vector(unit.position).is_equal(Vector3(i, [0.5, 1.5, 2.5][i], i * 2))

func test_unresolved_path_is_reported_once_and_spawning_continues() -> void:
	var node = _scenes_node({ "energy": "Nope:light_energy", "height": "Light:not_a_property" })
	S.run(node, _input3(), _owner)
	assert_str(node.err).contains("does not resolve")
	assert_str(node.err).contains("and 1 more")
	assert_int(S.spawned(_owner).size()).is_equal(3)

func test_missing_attribute_is_reported_and_others_still_apply() -> void:
	var node = _scenes_node({ "nope": "Light:light_energy", "height": "position:y" })
	S.run(node, _input3(), _owner)
	assert_str(node.err).contains("'nope' not found")
	var units = S.spawned(_owner)
	assert_int(units.size()).is_equal(3)
	assert_float(units[2].position.y).is_equal(2.5)

func test_attribute_size_mismatch_is_an_error_and_spawns_nothing() -> void:
	var node = _scenes_node({ "short": "Light:light_energy" })
	var d := _input3()
	d.registerStream("short", PackedFloat32Array([1, 2]), FlowData.DataType.Float)
	S.run(node, d, _owner)
	assert_str(node.err).contains("must have 3 values")
	assert_int(S.spawned(_owner).size()).is_equal(0)

func test_broadcast_and_data_attribute_overrides() -> void:
	var node = _scenes_node({ "one": "Light:light_energy", "shared": "Light:light_indirect_energy" })
	var d := _input3()
	d.registerStream("one", PackedFloat32Array([4.0]), FlowData.DataType.Float)
	d.set_data_attr("shared", 0.25)
	S.run(node, d, _owner)
	assert_str(node.err).is_empty()
	for unit in S.spawned(_owner):
		assert_float(unit.get_node("Light").light_energy).is_equal(4.0)
		assert_float(unit.get_node("Light").light_indirect_energy).is_equal(0.25)

func test_spawn_nodes_overrides_with_coercion() -> void:
	var s = SpawnNodesSettings.new()
	s.node_class = "OmniLight3D"
	s.property_overrides = { "tint": "light_color", "energy": "light_energy", "height": ":position:y" }
	var node = SpawnNodesNode.new()
	node.name = "nodes"
	node.settings = s
	auto_free(node)
	S.run(node, _input3(), _owner)
	assert_str(node.err).is_empty()
	var lights = S.spawned(_owner)
	assert_int(lights.size()).is_equal(3)
	assert_that(lights[1].light_color).is_equal(Color(0, 1, 0))
	assert_float(lights[2].light_energy).is_equal(3.0)
	assert_float(lights[0].position.y).is_equal(0.5)

func test_apply_on_actor_overrides_resolve_from_the_actor() -> void:
	var targets := []
	for i in range(3):
		var unit = _unit_scene().instantiate()
		unit.name = "Target%d" % i
		_owner.add_child(unit)
		targets.append(unit)
	var s = ApplyOnActorSettings.new()
	s.target_child_path = NodePath("Light")
	s.property_overrides = { "energy": "Light:light_energy", "hp": "hp" }
	var node = ApplyOnActorNode.new()
	node.name = "apply"
	node.settings = s
	auto_free(node)
	var d := _input3()
	d.registerStream("node", Array(targets, TYPE_OBJECT, "Node", null), FlowData.DataType.NodePath)
	S.run(node, d, _owner)
	assert_str(node.err).is_empty()
	for i in range(3):
		assert_float(targets[i].get_node("Light").light_energy).is_equal(float(i + 1))
		assert_int(targets[i].hp).is_equal([7, 8, 9][i])

func test_resolve_property_target_forms() -> void:
	var root = _unit_scene().instantiate()
	add_child(root)
	var t := FlowSpawnUtil.resolve_property_target(root, "hp")
	assert_object(t[0]).is_same(root)
	assert_str(str(t[1])).is_equal("hp")
	t = FlowSpawnUtil.resolve_property_target(root, "position:x")
	assert_object(t[0]).is_same(root)
	t = FlowSpawnUtil.resolve_property_target(root, ":position:x")
	assert_object(t[0]).is_same(root)
	t = FlowSpawnUtil.resolve_property_target(root, "Light:light_energy")
	assert_object(t[0]).is_same(root.get_node("Light"))
	t = FlowSpawnUtil.resolve_property_target(root, "%Mesh:material_override:albedo_color")
	assert_object(t[0]).is_same(root.get_node("Mesh"))
	assert_str(str(t[1])).is_equal("material_override:albedo_color")
	assert_array(FlowSpawnUtil.resolve_property_target(root, "Light:nope")).is_empty()
	assert_array(FlowSpawnUtil.resolve_property_target(root, "Missing:visible")).is_empty()
	root.queue_free()

func test_coerce_value_rules() -> void:
	var cases := [
		[1.9, TYPE_INT, 1],
		[3, TYPE_FLOAT, 3.0],
		[0, TYPE_BOOL, false],
		[2.0, TYPE_BOOL, true],
		[Vector3(1, 2, 3), TYPE_COLOR, Color(1, 2, 3)],
		[Color(0.1, 0.2, 0.3, 0.4), TYPE_VECTOR3, Vector3(0.1, 0.2, 0.3)],
		[2.0, TYPE_VECTOR3, Vector3(2, 2, 2)],
		[Vector3(1, 2, 3), TYPE_VECTOR2, Vector2(1, 2)],
		[Vector4(0, 0, 0, 1), TYPE_QUATERNION, Quaternion.IDENTITY],
		[5, TYPE_STRING, "5"],
		["a/b", TYPE_NODE_PATH, NodePath("a/b")],
		[Vector3(1.4, 2.6, -1.5), TYPE_VECTOR3I, Vector3i(1, 3, -2)],
	]
	for c in cases:
		var r := FlowSpawnUtil.coerce_value(c[0], c[1])
		assert_bool(r.ok).is_true()
		assert_that(r.value).is_equal(c[2])
	var euler := FlowSpawnUtil.coerce_value(Vector3(0, 90, 0), TYPE_BASIS)
	assert_vector(euler.value * Vector3(1, 0, 0)).is_equal_approx(Vector3(0, 0, -1), Vector3(1e-5, 1e-5, 1e-5))
	assert_bool(FlowSpawnUtil.coerce_value("text", TYPE_VECTOR3).ok).is_false()
	assert_bool(FlowSpawnUtil.coerce_value(Vector3.ONE, TYPE_INT).ok).is_false()
