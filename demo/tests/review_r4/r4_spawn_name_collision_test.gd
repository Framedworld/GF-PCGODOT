# r4_spawn_name_collision_test.gd
# Review R4: spawned nodes must always get a name that is unique among their
# siblings and never an "@Class@N" auto-name.
#
# When add_child() receives a node whose name is already taken (or a node with
# no name), Godot's fast path names it "@<Class>@<N>" from a process-global
# counter WITHOUT checking the siblings. Scenes saved with such names (a demo
# scene once carried 1873 of them) load them verbatim, and the counter of a new
# session restarts, so a later fast-path name can equal a saved sibling's name.
# The parent then holds two children with one name: lookups by name return the
# wrong node and the parent's name index loses an entry. Spawners hit the fast
# path whenever their canonical name ("Scene_0000", ...) was taken by a
# foreign sibling (a user node, or another component's content in a shared
# parent), and Spawn Meshes always did for its unnamed MultiMeshInstance3Ds.
class_name R4SpawnNameCollisionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "NameOwner"
	_owner.generate_on_ready = false
	add_child(_owner)

## Current value of Godot's auto-name counter (the next fast-path name uses a
## higher number).
func _auto_name_counter() -> int:
	var p := Node.new()
	var a := Node.new()
	a.name = "Probe"
	p.add_child(a)
	var b := Node.new()
	b.name = "Probe"
	p.add_child(b)
	var n := int(str(b.name).get_slice("@", 2))
	p.free()
	return n

## A loaded scene whose root holds `count` children of `cls` saved with the
## auto-names the next `count` fast-path names will use, exactly like content
## saved by an earlier session. Added under `parent` and returned.
func _saved_auto_named_holder(parent : Node, cls : String, count : int) -> Node3D:
	var start := _auto_name_counter() + 1
	var text := "[gd_scene format=3]\n\n[node name=\"Holder\" type=\"Node3D\"]\n\n"
	for k in range(start, start + count):
		text += "[node name=\"@%s@%d\" type=\"%s\" parent=\".\"]\n\n" % [cls, k, cls]
	var path := "user://r4_auto_named_%s.tscn" % cls
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	var packed : PackedScene = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var holder : Node3D = packed.instantiate()
	parent.add_child(holder)
	assert_str(str(holder.get_child(0).name)).is_equal("@%s@%d" % [cls, start])
	return holder

func _assert_unique_child_names(parent : Node) -> void:
	var seen := {}
	for c in parent.get_children():
		var n := str(c.name)
		assert_bool(seen.has(n)).override_failure_message("duplicate sibling name %s" % n).is_false()
		seen[n] = true
		assert_object(parent.get_node_or_null(NodePath(n))).is_same(c)

func _assert_no_auto_names(nodes : Array) -> void:
	for c in nodes:
		assert_bool(str(c.name).begins_with("@")).override_failure_message("auto-name %s" % c.name).is_false()

func _scene(root_name : String) -> PackedScene:
	var root := Node3D.new()
	root.name = root_name
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _scenes_node(parent_path : String, reuse := false) -> FlowNodeBase:
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_scenes_settings.gd").new()
	s.scene = _scene("Crate")
	s.spawn_parent_path = parent_path
	s.reuse_instances = reuse
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_scenes.gd").new()
	node.name = "scenes"
	node.settings = s
	return node

func test_spawn_scenes_name_taken_by_user_node_inside_saved_auto_named_parent() -> void:
	var holder := _saved_auto_named_holder(_owner, "Node3D", 64)
	var user := Node3D.new()
	user.name = "Scene_0000"
	holder.add_child(user)
	var node = _scenes_node("Holder")
	S.run(node, S.points(3), _owner)
	assert_str(node.err).is_empty()
	var spawned := S.spawned(holder)
	assert_int(spawned.size()).is_equal(3)
	_assert_no_auto_names(spawned)
	_assert_unique_child_names(holder)
	assert_int(holder.get_child_count()).is_equal(64 + 1 + 3)
	# Regenerating keeps the parent consistent.
	S.run(node, S.points(3), _owner)
	assert_int(S.spawned(holder).size()).is_equal(3)
	_assert_unique_child_names(holder)

func test_spawn_scenes_pooled_name_taken_by_user_node() -> void:
	var user := Node3D.new()
	user.name = "Scene_0001"
	_owner.add_child(user)
	var node = _scenes_node("", true)
	S.run(node, S.points(3), _owner)
	_assert_no_auto_names(S.spawned(_owner))
	S.run(node, S.points(3), _owner)
	_assert_no_auto_names(S.spawned(_owner))
	_assert_unique_child_names(_owner)
	assert_int(S.spawned(_owner).size()).is_equal(3)

func test_spawn_nodes_name_taken_by_user_node() -> void:
	var holder := _saved_auto_named_holder(_owner, "Node3D", 64)
	var user := Node3D.new()
	user.name = "Node3D_0001"
	holder.add_child(user)
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd").new()
	s.node_class = "Node3D"
	s.spawn_parent_path = "Holder"
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd").new()
	node.name = "nodes"
	node.settings = s
	S.run(node, S.points(3), _owner)
	_assert_no_auto_names(S.spawned(holder))
	_assert_unique_child_names(holder)

func test_spawn_meshes_beside_saved_auto_named_multimeshes() -> void:
	# Content of an earlier session that this run does not clear (clear off),
	# saved with fast-path names.
	var holder := _saved_auto_named_holder(_owner, "MultiMeshInstance3D", 64)
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd").new()
	s.mesh = BoxMesh.new()
	s.use_vertex_colors = false
	s.spawn_parent_path = "Holder"
	s.clear_previous_instances = false
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd").new()
	node.name = "meshes"
	node.settings = s
	S.run(node, S.points(3), _owner)
	S.run(node, S.points(3), _owner)
	assert_int(S.spawned(holder).size()).is_equal(2)
	_assert_no_auto_names(S.spawned(holder))
	_assert_unique_child_names(holder)
	assert_int(holder.get_child_count()).is_equal(64 + 2)

func test_spawn_meshes_entries_beside_saved_auto_named_multimeshes() -> void:
	var holder := _saved_auto_named_holder(_owner, "MultiMeshInstance3D", 64)
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd").new()
	var entries : Array[FlowMeshSpawnEntry] = [S.entry(BoxMesh.new())]
	s.mesh_entries = entries
	s.use_vertex_colors = false
	s.spawn_parent_path = "Holder"
	s.clear_previous_instances = false
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd").new()
	node.name = "meshes"
	node.settings = s
	S.run(node, S.points(3), _owner)
	S.run(node, S.points(3), _owner)
	_assert_no_auto_names(S.spawned(holder))
	_assert_unique_child_names(holder)

func test_spawn_meshes_default_names_unchanged_without_saved_auto_names() -> void:
	# Back-compat: with no auto-named sibling, the MultiMeshInstance3D keeps
	# Godot's auto-name, as before (the seed-zero hashes depend on it).
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd").new()
	s.mesh = BoxMesh.new()
	s.use_vertex_colors = false
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd").new()
	node.name = "meshes"
	node.settings = s
	S.run(node, S.points(3), _owner)
	var mmis := S.spawned(_owner)
	assert_int(mmis.size()).is_equal(1)
	assert_str(str(mmis[0].name)).starts_with("@MultiMeshInstance3D@")

func test_spawn_spline_mesh_name_taken_by_user_node() -> void:
	var path := Path3D.new()
	path.name = "Path"
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, 4))
	curve.add_point(Vector3(0, 0, 8))
	path.curve = curve
	_owner.add_child(path)
	var user := MeshInstance3D.new()
	user.name = "SplineMesh_0000"
	_owner.add_child(user)
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_spline_mesh_settings.gd").new()
	s.mesh = BoxMesh.new()
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_spline_mesh.gd").new()
	node.name = "spline"
	node.settings = s
	var d := FlowData.Data.new()
	d.registerStream("node", Array([path], TYPE_OBJECT, "Node", null), FlowData.DataType.NodePath)
	S.run(node, d, _owner)
	assert_str(node.err).is_empty()
	assert_int(S.spawned(_owner).size()).is_equal(2)
	_assert_no_auto_names(S.spawned(_owner))
	_assert_unique_child_names(_owner)

func test_create_target_node_name_taken_by_user_node() -> void:
	var user := Node3D.new()
	user.name = "Lights"
	_owner.add_child(user)
	var s = load("res://addons/flow_nodes_editor/nodes/create_target_node_settings.gd").new()
	s.node_name = "Lights"
	var node = load("res://addons/flow_nodes_editor/nodes/create_target_node.gd").new()
	node.name = "target"
	node.settings = s
	S.run(node, null, _owner)
	S.run(node, null, _owner)
	var containers := S.spawned(_owner)
	assert_int(containers.size()).is_equal(1)
	_assert_no_auto_names(containers)
	_assert_unique_child_names(_owner)
	assert_object(_owner.get_node("Lights")).is_same(user)

func test_two_components_sharing_a_parent_get_unique_names() -> void:
	var shared := Node3D.new()
	shared.name = "Shared"
	add_child(shared)
	auto_free(shared)
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 1}) \
		.node("spawn", "spawn_nodes", {"node_class": "Node3D", "spawn_parent_path": "../Shared"}) \
		.link("grid", 0, "spawn", 0) \
		.build()
	var a := FlowGraphNode3D.new()
	a.name = "A"
	a.generate_on_ready = false
	a.graph = graph
	add_child(a)
	auto_free(a)
	var b := FlowGraphNode3D.new()
	b.name = "B"
	b.generate_on_ready = false
	b.graph = graph
	add_child(b)
	auto_free(b)
	a.generate()
	b.generate()
	a.generate()
	b.generate()
	assert_int(S.spawned(shared).size()).is_equal(6)
	_assert_no_auto_names(S.spawned(shared))
	_assert_unique_child_names(shared)

func test_create_spline_beside_saved_auto_named_paths() -> void:
	# Create Spline added its Path3D unnamed (fast-path auto-name) and renamed
	# it afterwards; the transient auto-name could replace a saved sibling in
	# the parent's name index for good.
	var holder := _saved_auto_named_holder(_owner, "Path3D", 64)
	# The saved auto-named paths sit directly under the component, where
	# Create Spline spawns.
	for c in holder.get_children():
		holder.remove_child(c)
		_owner.add_child(c)
		assert_str(str(c.name)).starts_with("@Path3D@")
	var before := _owner.get_child_count()
	var node = load("res://addons/flow_nodes_editor/nodes/create_spline.gd").new()
	node.name = "spline"
	node.settings = load("res://addons/flow_nodes_editor/nodes/create_spline_settings.gd").new()
	var ctx := TestGraph.make_ctx(_owner)
	node.inputs = [S.points(3)]
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	_assert_unique_child_names(_owner)
	assert_int(_owner.get_child_count()).is_equal(before + 1)
	var listed := 0
	for c in _owner.get_children():
		listed += 1
	assert_int(listed).is_equal(before + 1)
	var paths := S.spawned(_owner)
	assert_int(paths.size()).is_equal(1)
	assert_str(str(paths[0].name)).is_equal("Spline")
