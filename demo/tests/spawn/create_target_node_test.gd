# create_target_node_test.gd
# Create Target Node (Unreal's Create Target Actor): named Node3D container with
# groups and owner policy, reference output, reuse across runs, spawners
# parenting under it through spawn_parent_attribute, cleanup semantics.
class_name CreateTargetNodeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const CreateTargetNode = preload("res://addons/flow_nodes_editor/nodes/create_target_node.gd")
const CreateTargetSettings = preload("res://addons/flow_nodes_editor/nodes/create_target_node_settings.gd")
const SpawnNodesNode = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes.gd")
const SpawnNodesSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd")

var _scene_root : Node3D
var _owner : FlowGraphNode3D

func before_test() -> void:
	# A scene root that owns the component, so spawned content has a scene owner.
	_scene_root = auto_free(Node3D.new())
	_scene_root.name = "Level"
	add_child(_scene_root)
	_owner = FlowGraphNode3D.new()
	_owner.name = "SpawnOwner"
	_owner.generate_on_ready = false
	_scene_root.add_child(_owner)
	_owner.owner = _scene_root

func _make(configure : Callable = Callable()) -> FlowNodeBase:
	var s = CreateTargetSettings.new()
	s.node_name = "Props"
	if configure.is_valid():
		configure.call(s)
	var node = CreateTargetNode.new()
	node.name = "target"
	node.settings = s
	return auto_free(node)

func _containers(parent : Node = null) -> Array:
	return S.spawned(parent if parent != null else _owner).filter(func(c): return c.has_meta(&"flow_target_name"))

func test_creates_named_container_with_groups_and_meta() -> void:
	var node = _make(func(s): s.groups = PackedStringArray(["props", "streamed"]))
	S.run(node, null, _owner)
	assert_str(node.err).is_empty()
	var containers = _containers()
	assert_int(containers.size()).is_equal(1)
	var c : Node3D = containers[0]
	assert_str(str(c.name)).is_equal("Props")
	assert_bool(c.is_in_group("props")).is_true()
	assert_bool(c.is_in_group("streamed")).is_true()
	assert_dict(c.get_meta("flow_owner")).contains_key_value("node", "target")
	assert_object(c.owner).is_same(_scene_root)

func test_unconnected_output_is_an_attribute_set_with_the_reference() -> void:
	var node = _make()
	S.run(node, null, _owner)
	var out : FlowData.Data = S.out(node)
	var c = _containers()[0]
	assert_int(out.kind).is_equal(FlowData.Kind.AttrSet)
	assert_int(out.size()).is_equal(1)
	assert_object(out.first("target")).is_same(c)
	assert_object(out.get_data_attr("target")).is_same(c)

func test_connected_input_passes_through_with_a_data_attribute() -> void:
	var node = _make(func(s): s.attribute_name = "parent")
	var input := S.points(3)
	input.tags = PackedStringArray(["keep"])
	S.run(node, input, _owner)
	var out : FlowData.Data = S.out(node)
	assert_object(out).is_not_same(input)
	assert_int(out.size()).is_equal(3)
	assert_array(Array(out.tags)).is_equal(["keep"])
	assert_object(out.value_at("@data.parent", 2)).is_same(_containers()[0])
	# The input itself is not modified.
	assert_bool(input.data_attrs.has("parent")).is_false()

func test_rerun_reuses_the_container() -> void:
	var node = _make()
	S.run(node, null, _owner)
	var first = _containers()[0]
	S.run(node, null, _owner)
	assert_int(_containers().size()).is_equal(1)
	assert_object(_containers()[0]).is_same(first)

func test_transient_owner_policy_and_component_transient_output() -> void:
	var node = _make(func(s): s.owner_policy = CreateTargetSettings.eOwnerPolicy.Transient)
	S.run(node, null, _owner)
	assert_object(_containers()[0].owner).is_null()
	_owner.transient_output = true
	var follow = _make()
	follow.name = "target2"
	S.run(follow, null, _owner)
	var c = S.spawned(_owner).filter(func(n): return n.get_meta("flow_owner").node == "target2")[0]
	assert_object(c.owner).is_null()

func test_parent_path_places_the_container() -> void:
	var holder := Node3D.new()
	holder.name = "Holder"
	_owner.add_child(holder)
	var node = _make(func(s): s.parent_path = "Holder")
	S.run(node, null, _owner)
	assert_int(_containers(holder).size()).is_equal(1)
	assert_int(_containers(_owner).size()).is_equal(0)

func test_owner_less_reports_error_and_passes_input_through() -> void:
	var node = _make()
	var input := S.points(2)
	S.run(node, input, null)
	assert_str(node.err).contains("needs an owner node")
	assert_object(S.out(node)).is_same(input)

func test_spawners_parent_under_the_container_and_cleanup_frees_everything() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", { "x": 3, "y": 1, "z": 1 }) \
		.node("target", "create_target_node", { "node_name": "Lights", "groups": PackedStringArray(["lights"]) }) \
		.node("spawn", "spawn_nodes", { "node_class": "OmniLight3D", "spawn_parent_attribute": "@data.target" }) \
		.link("grid", 0, "target", 0) \
		.link("target", 0, "spawn", 0) \
		.build()
	_owner.graph = graph
	_owner.generate()
	assert_array(_owner.last_errors).is_empty()
	var container : Node3D = _owner.get_node_or_null("Lights")
	assert_object(container).is_not_null()
	var lights = S.spawned(container, OmniLight3D)
	assert_int(lights.size()).is_equal(3)
	assert_object(lights[0].owner).is_same(_scene_root)
	# Second generation: same container, lights replaced under it.
	_owner.generate()
	assert_object(_owner.get_node_or_null("Lights")).is_same(container)
	assert_int(S.spawned(container, OmniLight3D).size()).is_equal(3)
	_owner.cleanup()
	assert_bool(container.is_queued_for_deletion()).is_true()
	assert_object(_owner.get_node_or_null("Lights")).is_null()
