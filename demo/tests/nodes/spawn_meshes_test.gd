# spawn_meshes_test.gd
# Spawn Meshes against a live scene tree: a FlowGraphNode3D added to the test
# suite acts as ctx.owner. Only the presence of the "flow_owner" meta is
# asserted (its value shape is scheduled to change, see RUNTIME_API_P0.md §5).
class_name SpawnMeshesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const SpawnMeshesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd")
const SpawnMeshesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	add_child(_owner)

func _points(n: int) -> FlowData.Data:
	var positions := []
	for i in range(n):
		positions.append(Vector3(i, 0, i * 2))
	return TestGraph.points(positions)

func _settings() -> SpawnMeshesSettings:
	var s = SpawnMeshesSettings.new()
	s.use_vertex_colors = true
	return s

func _make(s, node_name := "spawner") -> Node:
	var node = SpawnMeshesNode.new()
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
	var result := []
	for child in parent.get_children():
		if child is MultiMeshInstance3D and child.has_meta("flow_owner") and not child.is_queued_for_deletion():
			result.append(child)
	return result

func _out(node):
	if node.generated_bulks.is_empty():
		return null
	return node.generated_bulks[0][0]

## The headless (dummy) RenderingServer does not store MultiMesh instance
## data, so per-instance transforms/colors can only be read back with a real
## renderer. Instance counts, meshes and flags are always checked.
func _multimesh_readback_supported() -> bool:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	return mm.get_instance_transform(0).origin == Vector3(1, 2, 3)

func _count_by_mesh(mmis: Array) -> Dictionary:
	var counts := {}
	for mmi in mmis:
		counts[mmi.multimesh.mesh] = counts.get(mmi.multimesh.mesh, 0) + mmi.multimesh.instance_count
	return counts


func test_spawns_one_multimesh_with_every_point_transform() -> void:
	var node = _make(_settings())
	var input = _points(3)
	_run(node, input)
	assert_str(node.err).is_empty()
	var mmis = _spawned()
	assert_int(mmis.size()).is_equal(1)
	var mm : MultiMesh = mmis[0].multimesh
	assert_int(mm.instance_count).is_equal(3)
	assert_object(mm.mesh).is_same(node.settings.mesh)
	assert_int(mm.transform_format).is_equal(MultiMesh.TRANSFORM_3D)
	assert_bool(mmis[0].has_meta("flow_owner")).is_true()
	if _multimesh_readback_supported():
		for i in range(3):
			assert_vector(mm.get_instance_transform(i).origin).is_equal(Vector3(i, 0, i * 2))

func test_output_passes_input_through() -> void:
	var node = _make(_settings())
	var input = _points(2)
	_run(node, input)
	assert_object(_out(node)).is_same(input)

func test_clear_previous_instances_removes_own_previous_output() -> void:
	var node = _make(_settings())
	_run(node, _points(2))
	var first = _spawned()
	_run(node, _points(3))
	assert_bool(first[0].is_queued_for_deletion()).is_true()
	var current = _spawned()
	assert_int(current.size()).is_equal(1)
	assert_int(current[0].multimesh.instance_count).is_equal(3)

func test_keeps_previous_instances_when_clear_disabled() -> void:
	var s = _settings()
	s.clear_previous_instances = false
	var node = _make(s)
	_run(node, _points(2))
	_run(node, _points(3))
	assert_int(_spawned().size()).is_equal(2)

func test_clear_does_not_touch_other_spawners_or_plain_children() -> void:
	var plain = Node3D.new()
	_owner.add_child(plain)
	var other = _make(_settings(), "other_spawner")
	_run(other, _points(1))
	var node = _make(_settings())
	_run(node, _points(2))
	_run(node, _points(2))
	assert_bool(plain.is_queued_for_deletion()).is_false()
	assert_int(_spawned().size()).is_equal(2)

func test_variants_cycle_by_point_index() -> void:
	var s = _settings()
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var c := CylinderMesh.new()
	s.mesh_variants = [a, b, c] as Array[Mesh]
	var node = _make(s)
	_run(node, _points(7))
	var counts = _count_by_mesh(_spawned())
	assert_int(counts.size()).is_equal(3)
	assert_int(counts[a]).is_equal(3)
	assert_int(counts[b]).is_equal(2)
	assert_int(counts[c]).is_equal(2)

func test_randomized_variants_respect_zero_weights() -> void:
	var s = _settings()
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	s.mesh_variants = [a, b] as Array[Mesh]
	s.mesh_variant_weights = [0.0, 1.0] as Array[float]
	s.randomize_mesh_variants = true
	var node = _make(s)
	_run(node, _points(10))
	var counts = _count_by_mesh(_spawned())
	assert_int(counts.size()).is_equal(1)
	assert_int(counts[b]).is_equal(10)

func test_randomized_variants_are_deterministic() -> void:
	var s = _settings()
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	s.mesh_variants = [a, b] as Array[Mesh]
	s.randomize_mesh_variants = true
	s.clear_previous_instances = true
	var node = _make(s)
	_run(node, _points(20))
	var first = _count_by_mesh(_spawned())
	_run(node, _points(20))
	var second = _count_by_mesh(_spawned())
	assert_dict(second).is_equal(first)
	assert_int(first.get(a, 0) + first.get(b, 0)).is_equal(20)

func test_int_selector_picks_variant_by_index_and_clamps() -> void:
	var s = _settings()
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var c := CylinderMesh.new()
	s.mesh_variants = [a, b, c] as Array[Mesh]
	s.mesh_selector_attribute = "variant"
	var input = _points(5)
	input.registerStream("variant", PackedInt32Array([2, 0, 2, 1, 9]), FlowData.DataType.Int)
	var node = _make(s)
	_run(node, input)
	var counts = _count_by_mesh(_spawned())
	assert_int(counts[a]).is_equal(1)
	assert_int(counts[b]).is_equal(1)
	assert_int(counts[c]).is_equal(3)

func test_float_selector_uses_weights() -> void:
	var s = _settings()
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	s.mesh_variants = [a, b] as Array[Mesh]
	s.mesh_variant_weights = [1.0, 1.0] as Array[float]
	s.mesh_selector_attribute = "pick"
	var input = _points(4)
	input.registerStream("pick", PackedFloat32Array([0.0, 1.0, 0.4, 0.6]), FlowData.DataType.Float)
	var node = _make(s)
	_run(node, input)
	var counts = _count_by_mesh(_spawned())
	assert_int(counts[a]).is_equal(2)
	assert_int(counts[b]).is_equal(2)

func test_selector_of_wrong_type_is_an_error() -> void:
	var s = _settings()
	s.mesh_variants = [BoxMesh.new(), SphereMesh.new()] as Array[Mesh]
	s.mesh_selector_attribute = "pick"
	var input = _points(2)
	input.registerStream("pick", PackedStringArray(["a", "b"]), FlowData.DataType.String)
	var node = _make(s)
	_run(node, input)
	assert_str(node.err).contains("must be Int or Float")
	assert_int(_spawned().size()).is_equal(0)

func test_mesh_attribute_selects_mesh_per_point() -> void:
	var s = _settings()
	s.mesh_attribute = "mesh"
	var a := BoxMesh.new()
	var b := SphereMesh.new()
	var input = _points(3)
	input.registerStream("mesh", Array([a, b, a], TYPE_OBJECT, "Resource", null), FlowData.DataType.Resource)
	var node = _make(s)
	_run(node, input)
	var counts = _count_by_mesh(_spawned())
	assert_int(counts[a]).is_equal(2)
	assert_int(counts[b]).is_equal(1)

func test_missing_mesh_attribute_is_an_error() -> void:
	var s = _settings()
	s.mesh_attribute = "not_there"
	var node = _make(s)
	_run(node, _points(2))
	assert_str(node.err).contains("not_there")
	assert_int(_spawned().size()).is_equal(0)

func test_mesh_attribute_of_wrong_type_is_an_error() -> void:
	var s = _settings()
	s.mesh_attribute = "weight"
	var input = _points(2)
	input.registerStream("weight", PackedFloat32Array([1, 2]), FlowData.DataType.Float)
	var node = _make(s)
	_run(node, input)
	assert_str(node.err).contains("Resource")

func test_color_attribute_is_applied_per_instance() -> void:
	var s = _settings()
	var input = _points(3)
	input.registerStream("color", PackedColorArray([Color.RED, Color.GREEN, Color.BLUE]), FlowData.DataType.Color)
	var node = _make(s)
	_run(node, input)
	var mmi : MultiMeshInstance3D = _spawned()[0]
	assert_bool(mmi.multimesh.use_colors).is_true()
	if _multimesh_readback_supported():
		assert_that(mmi.multimesh.get_instance_color(0)).is_equal(Color.RED)
		assert_that(mmi.multimesh.get_instance_color(1)).is_equal(Color.GREEN)
		assert_that(mmi.multimesh.get_instance_color(2)).is_equal(Color.BLUE)
	assert_object(mmi.material_override).is_not_null()
	assert_bool(mmi.material_override.vertex_color_use_as_albedo).is_true()

func test_broadcast_color_applies_to_every_instance() -> void:
	var s = _settings()
	var input = _points(3)
	input.registerStream("color", PackedColorArray([Color.YELLOW]), FlowData.DataType.Color)
	var node = _make(s)
	_run(node, input)
	var mm : MultiMesh = _spawned()[0].multimesh
	assert_bool(mm.use_colors).is_true()
	assert_int(mm.instance_count).is_equal(3)
	if _multimesh_readback_supported():
		for i in range(3):
			assert_that(mm.get_instance_color(i)).is_equal(Color.YELLOW)

func test_colors_ignored_when_vertex_colors_disabled() -> void:
	var s = _settings()
	s.use_vertex_colors = false
	var input = _points(2)
	input.registerStream("color", PackedColorArray([Color.RED, Color.GREEN]), FlowData.DataType.Color)
	var node = _make(s)
	_run(node, input)
	var mmi : MultiMeshInstance3D = _spawned()[0]
	assert_bool(mmi.multimesh.use_colors).is_false()
	assert_object(mmi.material_override).is_null()

func test_color_attribute_size_mismatch_is_an_error() -> void:
	var s = _settings()
	var input = _points(3)
	input.registerStream("color", PackedColorArray([Color.RED, Color.GREEN]), FlowData.DataType.Color)
	var node = _make(s)
	_run(node, input)
	assert_str(node.err).contains("color")
	assert_int(_spawned().size()).is_equal(0)

func test_spawn_parent_path_places_instances_under_that_node() -> void:
	var holder = Node3D.new()
	holder.name = "Holder"
	_owner.add_child(holder)
	var s = _settings()
	s.spawn_parent_path = "Holder"
	var node = _make(s)
	_run(node, _points(2))
	assert_str(node.err).is_empty()
	assert_int(_spawned(holder).size()).is_equal(1)
	assert_int(_spawned(_owner).size()).is_equal(0)

func test_invalid_spawn_parent_path_errors_and_falls_back_to_owner() -> void:
	var s = _settings()
	s.spawn_parent_path = "Nope/Missing"
	var node = _make(s)
	_run(node, _points(2))
	assert_str(node.err).contains("Nope/Missing")
	assert_int(_spawned(_owner).size()).is_equal(1)

func test_no_mesh_source_is_an_error() -> void:
	var s = _settings()
	s.mesh = null
	var node = _make(s)
	_run(node, _points(2))
	assert_str(node.err).contains("No mesh source")
	assert_int(_spawned().size()).is_equal(0)

func test_empty_input_passes_through_without_spawning() -> void:
	var node = _make(_settings())
	var input = FlowDataScript.Data.new()
	_run(node, input)
	assert_object(_out(node)).is_same(input)
	assert_int(_spawned().size()).is_equal(0)

func test_unconnected_input_is_an_error() -> void:
	var node = _make(_settings())
	_run(node, null)
	assert_str(node.err).contains("not connected")

func test_null_owner_sets_error_without_crashing() -> void:
	var node = _make(_settings())
	_run_with_owner(node, _points(3), null)
	assert_str(node.err).is_not_empty()
	assert_int(_spawned().size()).is_equal(0)
