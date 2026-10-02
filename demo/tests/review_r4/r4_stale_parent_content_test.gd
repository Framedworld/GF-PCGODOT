# r4_stale_parent_content_test.gd
# Review R4: a spawner cleared (or pooled) its previous content only under the
# parents it uses in the CURRENT run. When the points stopped referencing a
# parent (spawn_parent_attribute values moved, spawn_parent_path edited), the
# content spawned there by the previous generation stayed in the scene next to
# the new content until cleanup(). The spawner now also clears under the
# parents of the content its component recorded for it.
class_name R4StaleParentContentTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")

var _owner : FlowGraphNode3D
var _a : Node3D
var _b : Node3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "StaleOwner"
	_owner.generate_on_ready = false
	add_child(_owner)
	_a = Node3D.new()
	_a.name = "A"
	_owner.add_child(_a)
	_b = Node3D.new()
	_b.name = "B"
	_owner.add_child(_b)

func _points_with_parents(parents : Array) -> FlowData.Data:
	var d := S.points(parents.size())
	d.registerStream("parent", Array(parents, TYPE_OBJECT, "Node", null), FlowData.DataType.NodePath)
	return d

func _scene() -> PackedScene:
	var root := Node3D.new()
	root.name = "Crate"
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed

func _node(template : String, reuse : bool) -> FlowNodeBase:
	var s = load("res://addons/flow_nodes_editor/nodes/%s_settings.gd" % template).new()
	match template:
		"spawn_nodes":
			s.node_class = "Node3D"
		"spawn_scenes":
			s.scene = _scene()
		"spawn_meshes":
			s.mesh = BoxMesh.new()
			s.use_vertex_colors = false
	s.reuse_instances = reuse
	s.spawn_parent_attribute = "parent"
	var node = load("res://addons/flow_nodes_editor/nodes/%s.gd" % template).new()
	node.name = "spawner"
	node.settings = s
	return node

func _check_attribute_parent_move(template : String, reuse : bool) -> void:
	var node = _node(template, reuse)
	S.run(node, _points_with_parents([_a, _b, _a, _b]), _owner)
	assert_int(S.spawned(_b).size()).is_greater(0)
	S.run(node, _points_with_parents([_a, _a, _a, _a]), _owner)
	assert_str(node.err).is_empty()
	assert_int(S.spawned(_b).size()).override_failure_message("%s reuse=%s left content under B" % [template, reuse]).is_equal(0)
	assert_int(S.spawned(_a).size()).is_greater(0)

func test_spawn_nodes_parent_attribute_move() -> void:
	_check_attribute_parent_move("spawn_nodes", false)

func test_spawn_nodes_parent_attribute_move_pooled() -> void:
	_check_attribute_parent_move("spawn_nodes", true)

func test_spawn_scenes_parent_attribute_move() -> void:
	_check_attribute_parent_move("spawn_scenes", false)

func test_spawn_meshes_parent_attribute_move() -> void:
	_check_attribute_parent_move("spawn_meshes", false)

func test_spawn_meshes_parent_attribute_move_pooled() -> void:
	_check_attribute_parent_move("spawn_meshes", true)

func test_spawn_parent_path_edit() -> void:
	var s = load("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd").new()
	s.node_class = "Node3D"
	s.spawn_parent_path = "A"
	var node = load("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd").new()
	node.name = "spawner"
	node.settings = s
	S.run(node, S.points(3), _owner)
	assert_int(S.spawned(_a).size()).is_equal(3)
	s.spawn_parent_path = "B"
	S.run(node, S.points(3), _owner)
	assert_int(S.spawned(_a).size()).is_equal(0)
	assert_int(S.spawned(_b).size()).is_equal(3)

func test_other_spawner_content_under_the_old_parent_is_kept() -> void:
	var first = _node("spawn_nodes", false)
	var other = _node("spawn_nodes", false)
	other.name = "other_spawner"
	S.run(first, _points_with_parents([_b, _b]), _owner)
	S.run(other, _points_with_parents([_b]), _owner)
	S.run(first, _points_with_parents([_a, _a]), _owner)
	var left := S.spawned(_b)
	assert_int(left.size()).is_equal(1)
	assert_str(str(left[0].get_meta("flow_owner").node)).is_equal("other_spawner")
