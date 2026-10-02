# mesh_spawn_entries_test.gd
# Spawn Meshes with FlowMeshSpawnEntry descriptors (WP3): selectors, grouping
# by render key, render settings, per-instance custom data, collision modes,
# spawn parents from attributes, .tres round trip.
#
# Headless caveat: the dummy RenderingServer keeps no MultiMesh instance data,
# so per-instance transforms/custom data are asserted only when
# multimesh_readback_supported(); instance counts, meshes, flags, materials,
# node properties and collision shapes are always asserted.
class_name MeshSpawnEntriesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const SpawnMeshesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd")
const SpawnMeshesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	add_child(_owner)

func _make(entries : Array, node_name := "spawner") -> Node:
	var s = SpawnMeshesSettings.new()
	var typed : Array[FlowMeshSpawnEntry] = []
	for e in entries:
		typed.append(e)
	s.mesh_entries = typed
	var node = SpawnMeshesNode.new()
	node.name = node_name
	node.settings = s
	return auto_free(node)

func _mmis(parent : Node = null) -> Array:
	return S.spawned(parent if parent != null else _owner, MultiMeshInstance3D)

func _count_by_mesh(mmis : Array) -> Dictionary:
	var counts := {}
	for mmi in mmis:
		counts[mmi.multimesh.mesh] = counts.get(mmi.multimesh.mesh, 0) + mmi.multimesh.instance_count
	return counts

# --- selectors ---------------------------------------------------------------

func test_weighted_selection_never_picks_zero_weight_entries() -> void:
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var node = _make([S.entry(a, 0.0), S.entry(b, 1.0)])
	S.run(node, S.points(25), _owner)
	assert_str(node.err).is_empty()
	var counts = _count_by_mesh(_mmis())
	assert_int(counts.size()).is_equal(1)
	assert_int(counts[b]).is_equal(25)

func test_weighted_selection_follows_weights_roughly() -> void:
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var node = _make([S.entry(a, 3.0), S.entry(b, 1.0)])
	S.run(node, S.points(400), _owner)
	var counts = _count_by_mesh(_mmis())
	assert_int(counts[a] + counts[b]).is_equal(400)
	# 75% expected; generous bounds, the pick is a seeded hash, not a sampler.
	assert_int(counts[a]).is_between(240, 360)

func test_weighted_picks_are_deterministic_and_stable_per_point() -> void:
	var entries := [S.entry(BoxMesh.new()), S.entry(SphereMesh.new()), S.entry(CylinderMesh.new())]
	var node = _make(entries)
	var data := S.points(40)
	var picks = FlowSpawnUtil.select_entries(node, data, entries, FlowSpawnUtil.eEntrySelection.Weighted, "", 777)
	var again = FlowSpawnUtil.select_entries(node, data, entries, FlowSpawnUtil.eEntrySelection.Weighted, "", 777)
	assert_array(Array(again)).is_equal(Array(picks))
	# Dropping points does not change the pick of the points that remain.
	var keep := PackedInt32Array([3, 7, 21, 39])
	var sub = FlowSpawnUtil.select_entries(node, data.filter(keep), entries, FlowSpawnUtil.eEntrySelection.Weighted, "", 777)
	for i in range(keep.size()):
		assert_int(sub[i]).is_equal(picks[keep[i]])
	# A different node seed changes at least one pick.
	var other = FlowSpawnUtil.select_entries(node, data, entries, FlowSpawnUtil.eEntrySelection.Weighted, "", 778)
	assert_bool(Array(other) != Array(picks)).is_true()

func test_weighted_picks_follow_the_point_seed_stream() -> void:
	var entries := [S.entry(BoxMesh.new()), S.entry(SphereMesh.new())]
	var node = _make(entries)
	var data := S.points(30)
	var seeds := PackedInt32Array()
	for i in range(30):
		seeds.append(1000 + (i % 3))
	data.registerStream(FlowData.AttrSeed, seeds, FlowData.DataType.Int)
	var picks = FlowSpawnUtil.select_entries(node, data, entries, FlowSpawnUtil.eEntrySelection.Weighted, "", 5)
	for i in range(3, 30):
		assert_int(picks[i]).is_equal(picks[i % 3])

func test_attribute_index_selection_clamps() -> void:
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var c := CylinderMesh.new()
	var node = _make([S.entry(a), S.entry(b), S.entry(c)])
	node.settings.entry_selection = FlowSpawnUtil.eEntrySelection.AttributeIndex
	node.settings.entry_attribute = "variant"
	var input := S.points(5)
	input.registerStream("variant", PackedInt32Array([2, 0, 2, 1, 9]), FlowData.DataType.Int)
	S.run(node, input, _owner)
	assert_str(node.err).is_empty()
	var counts = _count_by_mesh(_mmis())
	assert_int(counts[a]).is_equal(1)
	assert_int(counts[b]).is_equal(1)
	assert_int(counts[c]).is_equal(3)

func test_attribute_name_selection_by_string() -> void:
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	b.resource_name = "rock"
	var ea := S.entry(a)
	ea.entry_name = "crate"
	var node = _make([ea, S.entry(b)])
	node.settings.entry_selection = FlowSpawnUtil.eEntrySelection.AttributeName
	node.settings.entry_attribute = "kind"
	var input := S.points(4)
	input.registerStream("kind", PackedStringArray(["rock", "crate", "rock", "nope"]), FlowData.DataType.String)
	S.run(node, input, _owner)
	assert_str(node.err).contains("1 point(s) name no entry")
	var counts = _count_by_mesh(_mmis())
	assert_int(counts[a]).is_equal(1)
	assert_int(counts[b]).is_equal(2)

func test_attribute_name_selection_by_mesh_resource() -> void:
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var node = _make([S.entry(a), S.entry(b)])
	node.settings.entry_selection = FlowSpawnUtil.eEntrySelection.AttributeName
	node.settings.entry_attribute = "mesh"
	var input := S.points(3)
	input.registerStream("mesh", Array([b, b, a], TYPE_OBJECT, "Resource", null), FlowData.DataType.Resource)
	S.run(node, input, _owner)
	assert_str(node.err).is_empty()
	var counts = _count_by_mesh(_mmis())
	assert_int(counts[a]).is_equal(1)
	assert_int(counts[b]).is_equal(2)

func test_cycle_selection() -> void:
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var node = _make([S.entry(a), S.entry(b)])
	node.settings.entry_selection = FlowSpawnUtil.eEntrySelection.Cycle
	S.run(node, S.points(5), _owner)
	var counts = _count_by_mesh(_mmis())
	assert_int(counts[a]).is_equal(3)
	assert_int(counts[b]).is_equal(2)

func test_missing_selector_attribute_is_an_error_and_spawns_nothing() -> void:
	var node = _make([S.entry(BoxMesh.new()), S.entry(SphereMesh.new())])
	node.settings.entry_selection = FlowSpawnUtil.eEntrySelection.AttributeIndex
	node.settings.entry_attribute = "missing"
	S.run(node, S.points(3), _owner)
	assert_str(node.err).contains("missing")
	assert_int(_mmis().size()).is_equal(0)

func test_entries_replace_legacy_mesh_sources() -> void:
	var a := BoxMesh.new()
	var node = _make([S.entry(a)])
	node.settings.mesh_attribute = "not_there"
	node.settings.mesh_variants = [SphereMesh.new()] as Array[Mesh]
	S.run(node, S.points(3), _owner)
	assert_str(node.err).is_empty()
	var counts = _count_by_mesh(_mmis())
	assert_int(counts.size()).is_equal(1)
	assert_int(counts[a]).is_equal(3)

# --- grouping and render settings ------------------------------------------------

func test_entries_sharing_a_render_key_share_one_multimesh() -> void:
	var mesh := BoxMesh.new()
	var e1 := S.entry(mesh)
	var e2 := S.entry(mesh)
	var node = _make([e1, e2])
	node.settings.entry_selection = FlowSpawnUtil.eEntrySelection.Cycle
	S.run(node, S.points(6), _owner)
	var mmis = _mmis()
	assert_int(mmis.size()).is_equal(1)
	assert_int(mmis[0].multimesh.instance_count).is_equal(6)

func test_different_material_shadow_layers_or_gi_split_groups() -> void:
	var mesh := BoxMesh.new()
	var base := S.entry(mesh)
	var with_mat := S.entry(mesh)
	with_mat.material_override = StandardMaterial3D.new()
	var no_shadow := S.entry(mesh)
	no_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var layer2 := S.entry(mesh)
	layer2.render_layers = 2
	var gi_dyn := S.entry(mesh)
	gi_dyn.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	var vis := S.entry(mesh)
	vis.visibility_range_end = 50.0
	var node = _make([base, with_mat, no_shadow, layer2, gi_dyn, vis])
	node.settings.entry_selection = FlowSpawnUtil.eEntrySelection.Cycle
	S.run(node, S.points(12), _owner)
	var mmis = _mmis()
	assert_int(mmis.size()).is_equal(6)
	for mmi in mmis:
		assert_int(mmi.multimesh.instance_count).is_equal(2)

func test_render_settings_are_applied_to_the_multimesh_instance() -> void:
	var e := S.entry(BoxMesh.new())
	var mat := StandardMaterial3D.new()
	e.material_override = mat
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	e.visibility_range_begin = 2.0
	e.visibility_range_begin_margin = 0.5
	e.visibility_range_end = 80.0
	e.visibility_range_end_margin = 4.0
	e.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	e.render_layers = 5
	e.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var node = _make([e])
	S.run(node, S.points(3), _owner)
	var mmi : MultiMeshInstance3D = _mmis()[0]
	assert_object(mmi.material_override).is_same(mat)
	assert_int(mmi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_float(mmi.visibility_range_begin).is_equal(2.0)
	assert_float(mmi.visibility_range_begin_margin).is_equal(0.5)
	assert_float(mmi.visibility_range_end).is_equal(80.0)
	assert_float(mmi.visibility_range_end_margin).is_equal(4.0)
	assert_int(mmi.visibility_range_fade_mode).is_equal(GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF)
	assert_int(mmi.layers).is_equal(5)
	assert_int(mmi.gi_mode).is_equal(GeometryInstance3D.GI_MODE_DISABLED)
	assert_bool(mmi.has_meta("flow_owner")).is_true()
	assert_dict(mmi.get_meta("flow_owner")).contains_key_value("node", "spawner")

func test_vertex_colour_material_only_without_entry_material() -> void:
	var plain := S.entry(BoxMesh.new())
	var node = _make([plain])
	var input := S.points(2)
	input.registerStream("color", PackedColorArray([Color.RED, Color.BLUE]), FlowData.DataType.Color)
	S.run(node, input, _owner)
	var mmi : MultiMeshInstance3D = _mmis()[0]
	assert_bool(mmi.multimesh.use_colors).is_true()
	assert_bool(mmi.material_override.vertex_color_use_as_albedo).is_true()

func test_transforms_reach_the_multimesh_when_readable() -> void:
	var node = _make([S.entry(BoxMesh.new())])
	S.run(node, S.points(3), _owner)
	var mm : MultiMesh = _mmis()[0].multimesh
	assert_int(mm.instance_count).is_equal(3)
	assert_int(mm.transform_format).is_equal(MultiMesh.TRANSFORM_3D)
	if S.multimesh_readback_supported():
		for i in range(3):
			assert_vector(mm.get_instance_transform(i).origin).is_equal(Vector3(i, 0, i * 2))

# --- custom data --------------------------------------------------------------------

func test_custom_data_packs_attribute_channels_in_order() -> void:
	var node = _make([S.entry(BoxMesh.new())])
	var data := S.points(2)
	data.registerStream("w", PackedFloat32Array([0.25, 0.5]), FlowData.DataType.Float)
	data.registerStream("v", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowData.DataType.Vector)
	var prepared = FlowSpawnUtil.prepare_custom_data(node, data, PackedStringArray(["w", "v"]))
	assert_that(FlowSpawnUtil.custom_data_at(prepared, 0)).is_equal(Color(0.25, 1, 2, 3))
	assert_that(FlowSpawnUtil.custom_data_at(prepared, 1)).is_equal(Color(0.5, 4, 5, 6))
	# Channels past the fourth are dropped.
	data.registerStream("c", PackedColorArray([Color(0.1, 0.2, 0.3, 0.4)]), FlowData.DataType.Color)
	var overflow = FlowSpawnUtil.prepare_custom_data(node, data, PackedStringArray(["v", "c"]))
	assert_that(FlowSpawnUtil.custom_data_at(overflow, 1)).is_equal(Color(4, 5, 6, 0.1))

func test_custom_data_enables_multimesh_custom_data() -> void:
	var e := S.entry(BoxMesh.new())
	e.custom_data_attributes = PackedStringArray(["w"])
	var node = _make([e])
	var data := S.points(3)
	data.registerStream("w", PackedFloat32Array([0.1, 0.2, 0.3]), FlowData.DataType.Float)
	S.run(node, data, _owner)
	assert_str(node.err).is_empty()
	var mm : MultiMesh = _mmis()[0].multimesh
	assert_bool(mm.use_custom_data).is_true()
	assert_int(mm.instance_count).is_equal(3)
	if S.multimesh_readback_supported():
		assert_float(mm.get_instance_custom_data(2).r).is_equal_approx(0.3, 1e-6)

func test_custom_data_off_without_attributes() -> void:
	var node = _make([S.entry(BoxMesh.new())])
	S.run(node, S.points(2), _owner)
	assert_bool(_mmis()[0].multimesh.use_custom_data).is_false()

func test_missing_custom_data_attribute_is_an_error() -> void:
	var e := S.entry(BoxMesh.new())
	e.custom_data_attributes = PackedStringArray(["nope"])
	var node = _make([e])
	S.run(node, S.points(2), _owner)
	assert_str(node.err).contains("nope")
	assert_int(_mmis().size()).is_equal(0)

# --- collision -----------------------------------------------------------------------

func test_no_collision_by_default() -> void:
	var node = _make([S.entry(BoxMesh.new())])
	S.run(node, S.points(3), _owner)
	assert_int(_mmis()[0].get_child_count()).is_equal(0)

func test_box_collision_shared_body_has_one_shape_owner_per_instance() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2, 4, 6)
	var e := S.entry(mesh)
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.BoxFromBounds
	e.collision_layer = 4
	e.collision_mask = 9
	var node = _make([e])
	S.run(node, S.points(5), _owner)
	var mmi : MultiMeshInstance3D = _mmis()[0]
	assert_int(mmi.get_child_count()).is_equal(1)
	var body = mmi.get_child(0)
	assert_object(body).is_instanceof(FlowInstancedCollision3D)
	assert_int(body.collision_layer).is_equal(4)
	assert_int(body.collision_mask).is_equal(9)
	assert_object(body.shape).is_instanceof(BoxShape3D)
	assert_vector(body.shape.size).is_equal(Vector3(2, 4, 6))
	assert_int(body.instance_shape_count()).is_equal(5)
	assert_int(body.get_shape_owners().size()).is_equal(5)
	for i in range(5):
		var owner_id : int = body.get_shape_owners()[i]
		assert_object(body.shape_owner_get_shape(owner_id, 0)).is_same(body.shape)
		assert_vector(body.shape_owner_get_transform(owner_id).origin).is_equal(Vector3(i, 0, i * 2))
		assert_int(body.shape_owner_index(owner_id)).is_equal(i)

func test_box_collision_offsets_by_the_mesh_bounds_centre() -> void:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 2, 0)])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var info := FlowSpawnUtil.build_collision_shape(mesh, FlowMeshSpawnEntry.eCollisionMode.BoxFromBounds)
	assert_vector(info.offset.origin).is_equal_approx(Vector3(1, 1, 0), Vector3(1e-4, 1e-4, 1e-4))
	assert_float(info.shape.size.z).is_equal_approx(0.001, 1e-6)

func test_convex_collision_per_instance_creates_a_body_per_instance_sharing_the_shape() -> void:
	var e := S.entry(BoxMesh.new())
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.Convex
	e.collision_bodies = FlowMeshSpawnEntry.eCollisionBodies.PerInstance
	var node = _make([e])
	S.run(node, S.points(3), _owner)
	var mmi : MultiMeshInstance3D = _mmis()[0]
	assert_int(mmi.get_child_count()).is_equal(3)
	var first_shape = null
	for i in range(3):
		var body = mmi.get_child(i)
		assert_object(body).is_instanceof(StaticBody3D)
		assert_str(str(body.name)).is_equal("Collision_%04d" % i)
		assert_vector(body.position).is_equal(Vector3(i, 0, i * 2))
		var cs : CollisionShape3D = body.get_node("Shape")
		assert_object(cs.shape).is_instanceof(ConvexPolygonShape3D)
		if first_shape == null:
			first_shape = cs.shape
		assert_object(cs.shape).is_same(first_shape)

func test_trimesh_collision() -> void:
	var e := S.entry(BoxMesh.new())
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.Trimesh
	var node = _make([e])
	S.run(node, S.points(2), _owner)
	var body = _mmis()[0].get_child(0)
	assert_object(body.shape).is_instanceof(ConcavePolygonShape3D)
	assert_int(body.shape.get_faces().size()).is_equal(36)

func test_collision_bodies_get_the_scene_owner_and_are_cleared_with_the_multimesh() -> void:
	var e := S.entry(BoxMesh.new())
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.BoxFromBounds
	var node = _make([e])
	S.run(node, S.points(2), _owner)
	var first : MultiMeshInstance3D = _mmis()[0]
	var body = first.get_child(0)
	assert_object(body.owner).is_same(first.owner)
	S.run(node, S.points(2), _owner)
	assert_bool(first.is_queued_for_deletion()).is_true()
	assert_int(_mmis().size()).is_equal(1)

func test_shared_collision_body_survives_pack_and_instantiate() -> void:
	var body := FlowInstancedCollision3D.new()
	var transforms : Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(1, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(0, 0, 5))]
	body.setup(BoxShape3D.new(), transforms)
	var packed := PackedScene.new()
	assert_int(packed.pack(body)).is_equal(OK)
	body.free()
	var restored = packed.instantiate()
	assert_int(restored.get_shape_owners().size()).is_equal(2)
	assert_vector(restored.shape_owner_get_transform(restored.get_shape_owners()[1]).origin).is_equal(Vector3(0, 0, 5))
	restored.free()

func test_tens_of_thousands_of_instances_stay_two_nodes_with_shared_collision() -> void:
	var e := S.entry(BoxMesh.new())
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.BoxFromBounds
	var node = _make([e])
	var n := 20000
	var data := FlowData.Data.new()
	data.addCommonStreams(n)
	var pos : PackedVector3Array = data.getContainerChecked(str(FlowData.AttrPosition), FlowData.DataType.Vector)
	for i in range(n):
		pos[i] = Vector3(i % 200, 0, i / 200)
	var t0 := Time.get_ticks_msec()
	S.run(node, data, _owner)
	var elapsed := Time.get_ticks_msec() - t0
	assert_str(node.err).is_empty()
	var mmis = _mmis()
	assert_int(mmis.size()).is_equal(1)
	assert_int(mmis[0].multimesh.instance_count).is_equal(n)
	assert_int(mmis[0].get_child_count()).is_equal(1)
	assert_int(mmis[0].get_child(0).get_shape_owners().size()).is_equal(n)
	prints("WP3: 20000 instances with shared box collision in %d ms" % elapsed)
	assert_int(elapsed).is_less(30000)

# --- spawn parents ----------------------------------------------------------------

func test_spawn_parent_attribute_groups_points_by_parent() -> void:
	var left := Node3D.new()
	left.name = "Left"
	_owner.add_child(left)
	var right := Node3D.new()
	right.name = "Right"
	_owner.add_child(right)
	var node = _make([S.entry(BoxMesh.new())])
	node.settings.spawn_parent_attribute = "parent"
	var data := S.points(5)
	data.registerStream("parent", PackedStringArray(["Left", "Right", "Left", "Left", "Right"]), FlowData.DataType.String)
	S.run(node, data, _owner)
	assert_str(node.err).is_empty()
	assert_int(_mmis(left)[0].multimesh.instance_count).is_equal(3)
	assert_int(_mmis(right)[0].multimesh.instance_count).is_equal(2)
	assert_int(_mmis(_owner).size()).is_equal(0)
	# Second run clears under both parents.
	S.run(node, data, _owner)
	assert_int(_mmis(left).size()).is_equal(1)
	assert_int(_mmis(right).size()).is_equal(1)

func test_spawn_parent_attribute_unresolved_falls_back_with_error() -> void:
	var node = _make([S.entry(BoxMesh.new())])
	node.settings.spawn_parent_attribute = "parent"
	var data := S.points(2)
	data.registerStream("parent", PackedStringArray(["Nope", "Nope"]), FlowData.DataType.String)
	S.run(node, data, _owner)
	assert_str(node.err).contains("2 point(s)")
	assert_int(_mmis(_owner).size()).is_equal(1)

# --- owner-less -------------------------------------------------------------------

func test_entries_owner_less_reports_error_and_passes_input_through() -> void:
	var node = _make([S.entry(BoxMesh.new())])
	var input := S.points(2)
	S.run(node, input, null)
	assert_str(node.err).contains("needs an owner node")
	assert_object(S.out(node)).is_same(input)

# --- serialisation --------------------------------------------------------------

func test_entries_round_trip_through_a_graph_tres_and_evaluate() -> void:
	var mat := StandardMaterial3D.new()
	var e := FlowMeshSpawnEntry.new()
	e.mesh = BoxMesh.new()
	e.entry_name = "crate"
	e.weight = 2.5
	e.material_override = mat
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.render_layers = 3
	e.custom_data_attributes = PackedStringArray(["density"])
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.Convex
	e.collision_layer = 8
	var entries : Array[FlowMeshSpawnEntry] = [e]
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", { "x": 2, "y": 1, "z": 1 }) \
		.node("spawn", "spawn_meshes", { "mesh_entries": entries, "use_vertex_colors": false }) \
		.link("grid", 0, "spawn", 0) \
		.build()
	var path := "user://wp3_mesh_entries_graph.tres"
	assert_int(ResourceSaver.save(graph, path)).is_equal(OK)
	var loaded : FlowGraphResource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var saved_entries = loaded.data.nodes[1].settings.mesh_entries
	assert_int(saved_entries.size()).is_equal(1)
	var r = saved_entries[0]
	assert_object(r).is_instanceof(FlowMeshSpawnEntry)
	assert_str(r.entry_name).is_equal("crate")
	assert_float(r.weight).is_equal(2.5)
	assert_object(r.material_override).is_instanceof(StandardMaterial3D)
	assert_int(r.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(r.render_layers).is_equal(3)
	assert_array(Array(r.custom_data_attributes)).is_equal(["density"])
	assert_int(r.collision_mode).is_equal(FlowMeshSpawnEntry.eCollisionMode.Convex)
	assert_int(r.collision_layer).is_equal(8)
	# The reloaded graph evaluates (grid emits density, used as custom data).
	FlowNodeIO.evaluate(loaded, {}, 0, {}, _owner)
	assert_array(FlowNodeIO.last_errors).is_empty()
	var mmis = _mmis()
	assert_int(mmis.size()).is_equal(1)
	assert_int(mmis[0].multimesh.instance_count).is_equal(2)
	assert_bool(mmis[0].multimesh.use_custom_data).is_true()
	assert_int(mmis[0].layers).is_equal(3)
	assert_object(mmis[0].get_child(0)).is_instanceof(FlowInstancedCollision3D)
