# r4_collision_empty_mesh_test.gd
# Review R4: build_collision_shape documents "empty when the mesh yields no
# shape". For a mesh without geometry (no surface, or surfaces without
# vertices: a placeholder ArrayMesh, a mesh still being built) the Convex mode
# returned a ConvexPolygonShape3D without points, after the engine errors
# "Convex shape cleaning failed" and "Failed to build convex hull", and the
# Box mode returned a 1 mm box at the origin. Both then became colliders.
class_name R4CollisionEmptyMeshTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")

func _modes() -> Array:
	return [
		FlowMeshSpawnEntry.eCollisionMode.BoxFromBounds,
		FlowMeshSpawnEntry.eCollisionMode.Convex,
		FlowMeshSpawnEntry.eCollisionMode.Trimesh,
	]

func test_mesh_without_surfaces_yields_no_shape() -> void:
	var empty := ArrayMesh.new()
	for mode in _modes():
		assert_dict(FlowSpawnUtil.build_collision_shape(empty, mode)).is_empty()

func test_regular_meshes_still_yield_shapes() -> void:
	for mesh in [BoxMesh.new(), PlaneMesh.new(), SphereMesh.new()]:
		for mode in _modes():
			var info := FlowSpawnUtil.build_collision_shape(mesh, mode)
			assert_dict(info).contains_keys(["shape", "offset"])

func test_spawn_meshes_entry_with_empty_mesh_builds_no_collider() -> void:
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	auto_free(owner)
	var e := S.entry(ArrayMesh.new())
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.Convex
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd").new()
	var entries : Array[FlowMeshSpawnEntry] = [e]
	s.mesh_entries = entries
	s.use_vertex_colors = false
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd").new()
	node.name = "meshes"
	node.settings = s
	S.run(node, S.points(3), owner)
	var mmis := S.spawned(owner)
	assert_int(mmis.size()).is_equal(1)
	for c in mmis[0].get_children():
		assert_bool(c is CollisionObject3D).is_false()
