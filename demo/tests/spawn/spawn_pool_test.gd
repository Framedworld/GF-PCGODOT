# spawn_pool_test.gd
# FlowSpawnPool (reuse_instances, off by default): spawned MultiMeshInstance3Ds,
# scene roots, nodes and spline segments are reused across regenerations of the
# same component and node. Instance ids stay stable when counts match; excess
# instances are removed, missing ones created, and a mesh/material/scene change
# creates fresh nodes. Cleanup semantics (flow_owner {component, node}, stale
# ids, legacy metas, transient_output) are preserved.
class_name SpawnPoolTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const SpawnScenesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes.gd")
const SpawnScenesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_scenes_settings.gd")
const SpawnMeshesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd")
const SpawnMeshesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd")
const SpawnNodesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd")
const SpawnNodesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	_owner.generate_on_ready = false
	add_child(_owner)

func _scene(root_name : String) -> PackedScene:
	var root := Node3D.new()
	root.name = root_name
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _scenes_node(scene : PackedScene, reuse := true) -> Node:
	var s = SpawnScenesSettings.new()
	s.scene = scene
	s.reuse_instances = reuse
	var node = SpawnScenesNode.new()
	node.name = "scenes"
	node.settings = s
	return auto_free(node)

func _meshes_node(mesh : Mesh, reuse := true) -> Node:
	var s = SpawnMeshesSettings.new()
	s.mesh = mesh
	s.use_vertex_colors = false
	s.reuse_instances = reuse
	var node = SpawnMeshesNode.new()
	node.name = "meshes"
	node.settings = s
	return auto_free(node)

func _shifted(n : int, dx : float) -> FlowData.Data:
	var d := S.points(n)
	var pos : PackedVector3Array = d.getContainerChecked(str(FlowData.AttrPosition), FlowData.DataType.Vector)
	for i in range(n):
		pos[i] += Vector3(dx, 0, 0)
	return d

# --- scenes -------------------------------------------------------------------

func test_pool_is_off_by_default() -> void:
	assert_bool(SpawnScenesSettings.new().reuse_instances).is_false()
	assert_bool(SpawnMeshesSettings.new().reuse_instances).is_false()
	assert_bool(SpawnNodesSettings.new().reuse_instances).is_false()
	var node = _scenes_node(_scene("Crate"), false)
	S.run(node, S.points(3), _owner)
	var first = S.ids(S.spawned(_owner))
	S.run(node, S.points(3), _owner)
	for id in S.ids(S.spawned(_owner)):
		assert_bool(first.has(id)).is_false()
	for child in S.spawned(_owner):
		assert_bool(child.has_meta(FlowSpawnPool.KEY_META)).is_false()

func test_scene_roots_keep_their_instance_ids_when_counts_match() -> void:
	var node = _scenes_node(_scene("Crate"))
	S.run(node, S.points(4), _owner)
	var first = S.spawned(_owner)
	var ids = S.ids(first)
	S.run(node, _shifted(4, 10.0), _owner)
	var second = S.spawned(_owner)
	assert_array(S.ids(second)).is_equal(ids)
	for i in range(4):
		assert_str(str(second[i].name)).is_equal("Scene_%04d" % i)
		assert_vector(second[i].position).is_equal(Vector3(i + 10.0, 0, i * 2))
		assert_bool(second[i].is_queued_for_deletion()).is_false()

func test_scene_pool_shrinks_and_grows() -> void:
	var node = _scenes_node(_scene("Crate"))
	S.run(node, S.points(5), _owner)
	var ids = S.ids(S.spawned(_owner))
	var all_first = S.spawned(_owner)
	# Fewer points: the first three are reused, the excess is removed.
	S.run(node, S.points(3), _owner)
	var shrunk = S.spawned(_owner)
	assert_int(shrunk.size()).is_equal(3)
	assert_array(S.ids(shrunk)).is_equal(ids.slice(0, 3))
	assert_bool(all_first[3].is_queued_for_deletion()).is_true()
	assert_object(all_first[4].get_parent()).is_null()
	# More points: the three are reused, two are created.
	S.run(node, S.points(5), _owner)
	var grown = S.spawned(_owner)
	assert_int(grown.size()).is_equal(5)
	assert_array(S.ids(grown).slice(0, 3)).is_equal(ids.slice(0, 3))
	assert_bool(ids.has(grown[3].get_instance_id())).is_false()
	var names = grown.map(func(n): return str(n.name))
	names.sort()
	assert_array(names).is_equal(["Scene_0000", "Scene_0001", "Scene_0002", "Scene_0003", "Scene_0004"])

func test_scene_change_creates_fresh_instances() -> void:
	var node = _scenes_node(_scene("Crate"))
	S.run(node, S.points(2), _owner)
	var old = S.spawned(_owner)
	node.settings.scene = _scene("Barrel")
	S.run(node, S.points(2), _owner)
	var now = S.spawned(_owner)
	assert_int(now.size()).is_equal(2)
	for n in now:
		assert_bool(S.ids(old).has(n.get_instance_id())).is_false()
	for n in old:
		assert_bool(n.is_queued_for_deletion()).is_true()

func test_pool_never_takes_other_spawners_or_plain_children() -> void:
	var plain := Node3D.new()
	plain.name = "Plain"
	_owner.add_child(plain)
	var other = _scenes_node(_scene("Crate"))
	other.name = "other"
	S.run(other, S.points(2), _owner)
	var other_ids = S.ids(S.spawned(_owner))
	var node = _scenes_node(_scene("Crate"))
	S.run(node, S.points(2), _owner)
	S.run(node, S.points(2), _owner)
	assert_bool(plain.is_queued_for_deletion()).is_false()
	var by_node = S.spawned(_owner).filter(func(n): return n.get_meta("flow_owner").node == "other")
	assert_array(S.ids(by_node)).is_equal(other_ids)
	assert_int(S.spawned(_owner).size()).is_equal(4)

func test_stale_component_content_is_reused_and_reclaimed() -> void:
	var scene := _scene("Crate")
	var node = _scenes_node(scene)
	var saved = scene.instantiate()
	saved.name = "Scene_0000"
	saved.set_meta("flow_owner", { "component": 0, "node": "scenes" })
	saved.set_meta(FlowSpawnPool.KEY_META, "scene|" + FlowSpawnPool.resource_key(scene))
	_owner.add_child(saved)
	var legacy := Node3D.new()
	legacy.set_meta("flow_owner", "scenes")
	_owner.add_child(legacy)
	S.run(node, S.points(1), _owner)
	var now = S.spawned(_owner)
	assert_int(now.size()).is_equal(1)
	assert_object(now[0]).is_same(saved)
	assert_int(int(saved.get_meta("flow_owner").component)).is_equal(_owner.get_instance_id())
	# The legacy String-meta node has no pool key: freed, never reused.
	assert_bool(legacy.is_queued_for_deletion()).is_true()

func test_reused_nodes_follow_transient_output() -> void:
	var root := Node3D.new()
	root.name = "Level"
	add_child(root)
	var comp := FlowGraphNode3D.new()
	comp.name = "Comp"
	comp.generate_on_ready = false
	root.add_child(comp)
	comp.owner = root
	var node = _scenes_node(_scene("Crate"))
	S.run(node, S.points(2), comp)
	var spawned = S.spawned(comp)
	assert_object(spawned[0].owner).is_same(root)
	comp.transient_output = true
	S.run(node, S.points(2), comp)
	assert_array(S.ids(S.spawned(comp))).is_equal(S.ids(spawned))
	assert_object(spawned[0].owner).is_null()
	root.queue_free()

# --- meshes ---------------------------------------------------------------------

func test_multimesh_instances_are_reused_and_resized() -> void:
	var mesh := BoxMesh.new()
	var node = _meshes_node(mesh)
	S.run(node, S.points(3), _owner)
	var mmi = S.spawned(_owner, MultiMeshInstance3D)[0]
	var mm : MultiMesh = mmi.multimesh
	S.run(node, S.points(3), _owner)
	var again = S.spawned(_owner, MultiMeshInstance3D)
	assert_int(again.size()).is_equal(1)
	assert_object(again[0]).is_same(mmi)
	assert_object(again[0].multimesh).is_same(mm)
	S.run(node, S.points(7), _owner)
	again = S.spawned(_owner, MultiMeshInstance3D)
	assert_object(again[0]).is_same(mmi)
	assert_int(mmi.multimesh.instance_count).is_equal(7)

func test_mesh_change_creates_a_fresh_multimesh_instance() -> void:
	var node = _meshes_node(BoxMesh.new())
	S.run(node, S.points(3), _owner)
	var old = S.spawned(_owner, MultiMeshInstance3D)[0]
	node.settings.mesh = SphereMesh.new()
	S.run(node, S.points(3), _owner)
	var now = S.spawned(_owner, MultiMeshInstance3D)
	assert_int(now.size()).is_equal(1)
	assert_object(now[0]).is_not_same(old)
	assert_bool(old.is_queued_for_deletion()).is_true()

func test_variant_groups_reuse_by_mesh_and_drop_the_unused_one() -> void:
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var node = _meshes_node(a)
	node.settings.mesh_variants = [a, b] as Array[Mesh]
	S.run(node, S.points(4), _owner)
	var by_mesh := {}
	for m in S.spawned(_owner, MultiMeshInstance3D):
		by_mesh[m.multimesh.mesh] = m
	node.settings.mesh_variants = [a] as Array[Mesh]
	S.run(node, S.points(4), _owner)
	var now = S.spawned(_owner, MultiMeshInstance3D)
	assert_int(now.size()).is_equal(1)
	assert_object(now[0]).is_same(by_mesh[a])
	assert_int(now[0].multimesh.instance_count).is_equal(4)
	assert_bool(by_mesh[b].is_queued_for_deletion()).is_true()

func test_entry_material_change_creates_fresh_and_collision_is_rebuilt_on_reuse() -> void:
	var e := S.entry(BoxMesh.new())
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.BoxFromBounds
	var node = _meshes_node(null)
	node.settings.mesh_entries = [e] as Array[FlowMeshSpawnEntry]
	S.run(node, S.points(2), _owner)
	var mmi = S.spawned(_owner, MultiMeshInstance3D)[0]
	S.run(node, S.points(6), _owner)
	assert_object(S.spawned(_owner, MultiMeshInstance3D)[0]).is_same(mmi)
	var bodies = mmi.get_children().filter(func(c): return not c.is_queued_for_deletion())
	assert_int(bodies.size()).is_equal(1)
	assert_int(bodies[0].get_shape_owners().size()).is_equal(6)
	e.material_override = StandardMaterial3D.new()
	S.run(node, S.points(6), _owner)
	var now = S.spawned(_owner, MultiMeshInstance3D)
	assert_int(now.size()).is_equal(1)
	assert_object(now[0]).is_not_same(mmi)
	assert_object(now[0].material_override).is_same(e.material_override)

# --- nodes ------------------------------------------------------------------------

func test_spawned_nodes_are_reused_per_class() -> void:
	var s = SpawnNodesSettings.new()
	s.node_class = "OmniLight3D"
	s.reuse_instances = true
	var node = SpawnNodesNode.new()
	node.name = "nodes"
	node.settings = s
	auto_free(node)
	S.run(node, S.points(3), _owner)
	var ids = S.ids(S.spawned(_owner))
	S.run(node, S.points(3), _owner)
	assert_array(S.ids(S.spawned(_owner))).is_equal(ids)
	s.node_class = "SpotLight3D"
	S.run(node, S.points(3), _owner)
	var now = S.spawned(_owner)
	assert_int(now.size()).is_equal(3)
	for n in now:
		assert_object(n).is_instanceof(SpotLight3D)
		assert_bool(ids.has(n.get_instance_id())).is_false()

# --- through a component ----------------------------------------------------------

func test_component_generate_twice_reuses_and_regenerate_recreates() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", { "x": 2, "y": 1, "z": 2 }) \
		.node("spawn", "spawn_meshes", { "use_vertex_colors": false, "reuse_instances": true }) \
		.link("grid", 0, "spawn", 0) \
		.build()
	_owner.graph = graph
	_owner.generate()
	var first = S.spawned(_owner, MultiMeshInstance3D)
	assert_int(first.size()).is_equal(1)
	_owner.generate()
	assert_array(S.ids(S.spawned(_owner, MultiMeshInstance3D))).is_equal(S.ids(first))
	# regenerate() = cleanup() + generate(): cleanup frees everything, so the
	# pool has nothing to reuse (documented).
	_owner.regenerate()
	var after = S.spawned(_owner, MultiMeshInstance3D)
	assert_int(after.size()).is_equal(1)
	assert_object(after[0]).is_not_same(first[0])
