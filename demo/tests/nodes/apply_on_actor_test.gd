# apply_on_actor_test.gd
# Apply On Actor against a live scene tree (FlowGraphNode3D owner added to the
# suite; targets are Node3D children of it).
class_name ApplyOnActorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const ApplyOnActorNode = preload("res://addons/flow_nodes_editor/nodes/apply_on_actor.gd")
const ApplyOnActorSettings = preload("res://addons/flow_nodes_editor/nodes/apply_on_actor_settings.gd")

const GROUP := "flow_apply_on_actor_test_group"

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "ApplyOwner"
	add_child(_owner)

func _target(target_name: String, in_group := false) -> Node3D:
	var t := Node3D.new()
	t.name = target_name
	var child := Node3D.new()
	child.name = "Child"
	t.add_child(child)
	_owner.add_child(t)
	if in_group:
		t.add_to_group(GROUP)
	return t

func _points(positions: Array) -> FlowData.Data:
	return TestGraph.points(positions)

func _node_stream(nodes: Array) -> Array:
	var arr := Array([], TYPE_OBJECT, "Node", null)
	for n in nodes:
		arr.append(n)
	return arr

func _settings(mode: int) -> Resource:
	var s = ApplyOnActorSettings.new()
	s.target_mode = mode
	return s

func _make(s) -> FlowNodeBase:
	var node = ApplyOnActorNode.new()
	node.name = "apply"
	node.settings = s
	return auto_free(node)

func _run(node, input) -> void:
	_run_with_owner(node, input, _owner)

func _run_with_owner(node, input, owner) -> void:
	node.inputs = [input]
	var ctx = TestGraph.make_ctx(owner)
	node.preExecute(ctx)
	node.execute(ctx)

## Path to `target` from the root apply_on_actor resolves NodePaths against.
func _path_from_scene_root(target: Node) -> NodePath:
	var tree := get_tree()
	var root : Node = tree.current_scene if tree.current_scene else _owner
	return root.get_path_to(target)


func test_node_stream_targets_receive_transforms_and_attributes() -> void:
	var t0 = _target("T0")
	var t1 = _target("T1")
	var s = _settings(ApplyOnActorSettings.eTargetMode.FromNodeStream)
	s.apply_transform_to_node3d = true
	s.assign_attributes = {"visible": "shown"}
	var input = _points([Vector3(1, 0, 0), Vector3(0, 0, 5)])
	input.registerStream("node", _node_stream([t0, t1]), FlowData.DataType.NodePath)
	input.registerStream("shown", PackedByteArray([0, 1]), FlowData.DataType.Bool)
	var node = _make(s)
	_run(node, input)
	assert_str(node.err).is_empty()
	assert_vector(t0.global_position).is_equal(Vector3(1, 0, 0))
	assert_vector(t1.global_position).is_equal(Vector3(0, 0, 5))
	assert_bool(t0.visible).is_false()
	assert_bool(t1.visible).is_true()

func test_output_passes_input_through() -> void:
	var t0 = _target("T0")
	var input = _points([Vector3.ZERO])
	input.registerStream("node", _node_stream([t0]), FlowData.DataType.NodePath)
	var node = _make(_settings(ApplyOnActorSettings.eTargetMode.FromNodeStream))
	_run(node, input)
	assert_object(node.generated_bulks[0][0]).is_same(input)

func test_transform_not_applied_unless_enabled() -> void:
	var t0 = _target("T0")
	t0.position = Vector3(7, 7, 7)
	var input = _points([Vector3(1, 0, 0)])
	input.registerStream("node", _node_stream([t0]), FlowData.DataType.NodePath)
	var node = _make(_settings(ApplyOnActorSettings.eTargetMode.FromNodeStream))
	_run(node, input)
	assert_vector(t0.position).is_equal(Vector3(7, 7, 7))

func test_group_targets_are_reused_cyclically_last_write_wins() -> void:
	var t0 = _target("G0", true)
	var t1 = _target("G1", true)
	var s = _settings(ApplyOnActorSettings.eTargetMode.Group)
	s.group_name = GROUP
	s.apply_transform_to_node3d = true
	var node = _make(s)
	_run(node, _points([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)]))
	assert_str(node.err).is_empty()
	var by_name := {str(t0.name): t0.global_position, str(t1.name): t1.global_position}
	# 3 points over 2 targets: one target received points 0 and 2 (keeps 2).
	assert_array(by_name.values()).contains_exactly_in_any_order([Vector3(3, 0, 0), Vector3(2, 0, 0)])

func test_node_path_mode_applies_every_point_to_the_single_target() -> void:
	var t0 = _target("Single")
	var s = _settings(ApplyOnActorSettings.eTargetMode.NodePath)
	s.target_node_path = _path_from_scene_root(t0)
	s.apply_transform_to_node3d = true
	var node = _make(s)
	_run(node, _points([Vector3(1, 0, 0), Vector3(4, 0, 0)]))
	assert_str(node.err).is_empty()
	assert_vector(t0.global_position).is_equal(Vector3(4, 0, 0))

func test_target_child_path_redirects_assignment() -> void:
	var t0 = _target("T0")
	var s = _settings(ApplyOnActorSettings.eTargetMode.FromNodeStream)
	s.target_child_path = NodePath("Child")
	s.assign_attributes = {"visible": "shown"}
	var input = _points([Vector3.ZERO])
	input.registerStream("node", _node_stream([t0]), FlowData.DataType.NodePath)
	input.registerStream("shown", PackedByteArray([0]), FlowData.DataType.Bool)
	var node = _make(s)
	_run(node, input)
	assert_bool(t0.get_node("Child").visible).is_false()
	assert_bool(t0.visible).is_true()

func test_short_attribute_stream_skips_out_of_range_points() -> void:
	var t0 = _target("T0")
	var t1 = _target("T1")
	var t2 = _target("T2")
	var s = _settings(ApplyOnActorSettings.eTargetMode.FromNodeStream)
	s.assign_attributes = {"visible": "shown"}
	var input = _points([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	input.registerStream("node", _node_stream([t0, t1, t2]), FlowData.DataType.NodePath)
	input.registerStream("shown", PackedByteArray([0, 0]), FlowData.DataType.Bool)
	var node = _make(s)
	_run(node, input)
	assert_bool(t0.visible).is_false()
	assert_bool(t1.visible).is_false()
	assert_bool(t2.visible).is_true()

func test_no_targets_is_an_error() -> void:
	var s = _settings(ApplyOnActorSettings.eTargetMode.Group)
	s.group_name = "no_such_group_for_flow_tests"
	var node = _make(s)
	_run(node, _points([Vector3.ZERO]))
	assert_str(node.err).contains("No target nodes")

func test_target_stream_of_wrong_type_is_an_error() -> void:
	var input = _points([Vector3.ZERO])
	input.registerStream("node", PackedStringArray(["T0"]), FlowData.DataType.String)
	var node = _make(_settings(ApplyOnActorSettings.eTargetMode.FromNodeStream))
	_run(node, input)
	assert_str(node.err).is_not_empty()

func test_target_stream_without_live_nodes_is_an_error() -> void:
	var input = _points([Vector3.ZERO])
	input.registerStream("node", _node_stream([null]), FlowData.DataType.NodePath)
	var node = _make(_settings(ApplyOnActorSettings.eTargetMode.FromNodeStream))
	_run(node, input)
	# The specific "contains no live Node references" error is reported first
	# and then overwritten by the generic "No target nodes found" (err keeps
	# only the last message).
	assert_str(node.err).contains("No target nodes")

func test_empty_input_passes_through() -> void:
	var node = _make(_settings(ApplyOnActorSettings.eTargetMode.FromNodeStream))
	var input = FlowDataScript.Data.new()
	_run(node, input)
	assert_object(node.generated_bulks[0][0]).is_same(input)

func test_unconnected_input_is_an_error() -> void:
	var node = _make(_settings(ApplyOnActorSettings.eTargetMode.FromNodeStream))
	_run(node, null)
	assert_str(node.err).contains("not connected")

func test_null_owner_with_scene_targets_sets_error_without_crashing() -> void:
	var t0 = _target("Single")
	var s = _settings(ApplyOnActorSettings.eTargetMode.NodePath)
	s.target_node_path = _path_from_scene_root(t0)
	s.apply_transform_to_node3d = true
	var node = _make(s)
	_run_with_owner(node, _points([Vector3(9, 9, 9)]), null)
	assert_str(node.err).is_not_empty()
	assert_vector(t0.global_position).is_equal(Vector3.ZERO)
