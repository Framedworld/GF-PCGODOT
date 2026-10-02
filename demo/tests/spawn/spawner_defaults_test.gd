# spawner_defaults_test.gd
# Back-compat for WP3: with none of the new settings touched, spawn_meshes,
# spawn_scenes and spawn_nodes produce exactly the nodes they produced before
# (names, counts, classes, properties and meta), and the new settings default
# to off. A spawned node carries only the `flow_owner` meta and keeps the
# engine defaults for every property the spawner did not set before.
class_name SpawnerDefaultsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const SpawnScenesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes.gd")
const SpawnScenesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes_settings.gd")
const SpawnMeshesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd")
const SpawnMeshesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd")
const SpawnNodesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd")
const SpawnNodesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd")
const ApplyOnActorSettings = preload("res://addons/flow_nodes_editor/nodes/apply_on_actor_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	add_child(_owner)

func _expect_only_flow_owner_meta(node : Node, node_name : String) -> void:
	assert_array(Array(node.get_meta_list())).is_equal([&"flow_owner"])
	assert_dict(node.get_meta("flow_owner")).is_equal({ "component": _owner.get_instance_id(), "node": node_name })

func test_new_settings_default_to_off() -> void:
	var m = SpawnMeshesSettings.new()
	assert_array(m.mesh_entries).is_empty()
	assert_str(m.spawn_parent_attribute).is_empty()
	assert_bool(m.reuse_instances).is_false()
	var sc = SpawnScenesSettings.new()
	assert_dict(sc.property_overrides).is_empty()
	assert_str(sc.spawn_parent_attribute).is_empty()
	assert_bool(sc.reuse_instances).is_false()
	var n = SpawnNodesSettings.new()
	assert_dict(n.property_overrides).is_empty()
	assert_str(n.spawn_parent_attribute).is_empty()
	assert_bool(n.reuse_instances).is_false()
	assert_dict(ApplyOnActorSettings.new().property_overrides).is_empty()

func test_default_spawn_meshes_output_is_unchanged() -> void:
	var s = SpawnMeshesSettings.new()
	var node = SpawnMeshesNode.new()
	node.name = "meshes"
	node.settings = s
	auto_free(node)
	var input := S.points(3)
	S.run(node, input, _owner)
	assert_str(node.err).is_empty()
	var mmis = S.spawned(_owner)
	assert_int(mmis.size()).is_equal(1)
	var mmi : MultiMeshInstance3D = mmis[0]
	assert_object(mmi).is_instanceof(MultiMeshInstance3D)
	_expect_only_flow_owner_meta(mmi, "meshes")
	assert_int(mmi.get_child_count()).is_equal(0)
	# Engine defaults everywhere the spawner never wrote.
	var fresh := MultiMeshInstance3D.new()
	assert_object(mmi.material_override).is_null()
	assert_int(mmi.cast_shadow).is_equal(fresh.cast_shadow)
	assert_int(mmi.layers).is_equal(fresh.layers)
	assert_int(mmi.gi_mode).is_equal(fresh.gi_mode)
	assert_float(mmi.visibility_range_end).is_equal(fresh.visibility_range_end)
	assert_bool(mmi.transform == Transform3D.IDENTITY).is_true()
	fresh.free()
	var mm := mmi.multimesh
	assert_object(mm.mesh).is_same(s.mesh)
	assert_int(mm.instance_count).is_equal(3)
	assert_bool(mm.use_colors).is_false()
	assert_bool(mm.use_custom_data).is_false()
	assert_object(S.out(node)).is_same(input)

func test_default_spawn_scenes_output_is_unchanged() -> void:
	var root := Node3D.new()
	root.name = "Crate"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	var s = SpawnScenesSettings.new()
	s.scene = packed
	var node = SpawnScenesNode.new()
	node.name = "scenes"
	node.settings = s
	auto_free(node)
	S.run(node, S.points(3), _owner)
	var spawned = S.spawned(_owner)
	assert_int(spawned.size()).is_equal(3)
	for i in range(3):
		assert_str(str(spawned[i].name)).is_equal("Scene_%04d" % i)
		_expect_only_flow_owner_meta(spawned[i], "scenes")
		assert_vector(spawned[i].position).is_equal(Vector3(i, 0, i * 2))
		assert_int(spawned[i].get_index()).is_equal(i)

func test_default_spawn_nodes_output_is_unchanged() -> void:
	var s = SpawnNodesSettings.new()
	var node = SpawnNodesNode.new()
	node.name = "nodes"
	node.settings = s
	auto_free(node)
	S.run(node, S.points(2), _owner)
	var spawned = S.spawned(_owner)
	assert_int(spawned.size()).is_equal(2)
	var fresh := OmniLight3D.new()
	for i in range(2):
		assert_object(spawned[i]).is_instanceof(OmniLight3D)
		assert_str(str(spawned[i].name)).is_equal("OmniLight3D_%04d" % i)
		_expect_only_flow_owner_meta(spawned[i], "nodes")
		assert_float(spawned[i].light_energy).is_equal(fresh.light_energy)
	fresh.free()

func test_spawners_keep_no_exit_tree_hook() -> void:
	# The element/widget split gives elements no _exit_tree; the dead stubs are gone.
	for script in [SpawnMeshesNode, SpawnScenesNode, SpawnNodesNode]:
		var names = script.get_script_method_list().map(func(m): return m.name)
		assert_bool(names.has("_exit_tree") and script.source_code.contains("func _exit_tree")).is_false()
