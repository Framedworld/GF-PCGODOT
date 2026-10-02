# r4_pool_multimesh_reset_test.gd
# Review R4: a pooled MultiMeshInstance3D must render like a fresh one. The
# reused MultiMesh resource kept its visible_instance_count (Godot keeps it
# across instance_count changes), so after a game script had limited it, the
# regenerated instances beyond that count were never drawn; the reused node
# also kept a transform or visibility changed since the previous generation,
# which moves or hides every instance. A fresh MultiMeshInstance3D has
# visible_instance_count -1, an identity transform and is visible.
class_name R4PoolMultimeshResetTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "PoolOwner"
	_owner.generate_on_ready = false
	add_child(_owner)

func _meshes_node(entries : bool) -> FlowNodeBase:
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_meshes_settings.gd").new()
	if entries:
		var list : Array[FlowMeshSpawnEntry] = [S.entry(BoxMesh.new())]
		s.mesh_entries = list
	else:
		s.mesh = BoxMesh.new()
	s.use_vertex_colors = false
	s.reuse_instances = true
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_meshes.gd").new()
	node.name = "meshes"
	node.settings = s
	return node

func _tamper_and_regenerate(entries : bool) -> void:
	var node = _meshes_node(entries)
	S.run(node, S.points(4), _owner)
	var mmi : MultiMeshInstance3D = S.spawned(_owner)[0]
	mmi.multimesh.visible_instance_count = 1
	mmi.position = Vector3(5, 0, 0)
	mmi.visible = false
	S.run(node, S.points(6), _owner)
	var again : MultiMeshInstance3D = S.spawned(_owner)[0]
	assert_object(again).is_same(mmi)
	assert_int(again.multimesh.instance_count).is_equal(6)
	assert_int(again.multimesh.visible_instance_count).is_equal(-1)
	assert_object(again.transform).is_equal(Transform3D.IDENTITY)
	assert_bool(again.visible).is_true()

func test_legacy_path_reused_multimesh_is_reset() -> void:
	_tamper_and_regenerate(false)

func test_entries_path_reused_multimesh_is_reset() -> void:
	_tamper_and_regenerate(true)
