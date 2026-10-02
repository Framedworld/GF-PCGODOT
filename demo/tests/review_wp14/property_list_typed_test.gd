# property_list_typed_test.gd
# WP14-S: every _get_property_list() override in the addon returns a typed
# Array[Dictionary] (Godot 4.7 logs "should return Array[Dictionary]" for an
# untyped Array) and the properties it exposes are unchanged. The expected
# entries below are a snapshot of get_property_list() taken with the old
# untyped implementations on Godot 4.6 and 4.7.1 (both produced the same list).
class_name PropertyListTypedTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FlowWorldScript = preload("res://addons/flow_nodes_editor/world/flow_world_3d.gd")
const FlowNodeScript = preload("res://addons/flow_nodes_editor/flow_node.gd")

const WORLD_SNAPSHOT := [
	{ "name": "generate_all_cells", "class_name": &"", "type": TYPE_CALLABLE, "hint": 39, "hint_string": "Generate All", "usage": 4 },
	{ "name": "cleanup_all_cells", "class_name": &"", "type": TYPE_CALLABLE, "hint": 39, "hint_string": "Cleanup All", "usage": 4 },
]
const NODE_SNAPSHOT := [
	{ "name": "refresh_inputs", "class_name": &"", "type": TYPE_CALLABLE, "hint": 39, "hint_string": "Refresh Inputs", "usage": 6 },
]

func _assert_typed(list) -> void:
	assert_bool(list is Array).is_true()
	assert_bool(list.is_typed()).is_true()
	assert_int(list.get_typed_builtin()).is_equal(TYPE_DICTIONARY)

# The snapshot entries are the last properties of the object, in order, and
# match the old list key for key.
func _assert_snapshot(obj : Object, snapshot : Array) -> void:
	var full : Array = obj.get_property_list()
	assert_int(full.size()).is_greater_equal(snapshot.size())
	var tail : Array = full.slice(full.size() - snapshot.size())
	for i in snapshot.size():
		var expected : Dictionary = snapshot[i]
		var got : Dictionary = tail[i]
		assert_str(str(got.name)).is_equal(expected.name)
		for key in expected:
			assert_that(got.get(key)).override_failure_message(
				"%s.%s: expected %s, got %s" % [expected.name, key, expected[key], got.get(key)]).is_equal(expected[key])
	# Each snapshot name appears exactly once.
	for expected in snapshot:
		var count := 0
		for p in full:
			if str(p.name) == expected.name:
				count += 1
		assert_int(count).is_equal(1)

func test_flow_world_3d_property_list_is_typed() -> void:
	var w = FlowWorldScript.new()
	_assert_typed(w._get_property_list())
	w.free()

func test_flow_world_3d_property_list_unchanged() -> void:
	var w = FlowWorldScript.new()
	_assert_snapshot(w, WORLD_SNAPSHOT)
	# The tool buttons still resolve to the bound callables.
	assert_bool(w.get("generate_all_cells") is Callable).is_true()
	assert_bool(w.get("cleanup_all_cells") is Callable).is_true()
	w.free()

func test_flow_graph_node_3d_property_list_is_typed() -> void:
	var n = FlowNodeScript.new()
	_assert_typed(n._get_property_list())
	n.free()

func test_flow_graph_node_3d_property_list_unchanged() -> void:
	var n = FlowNodeScript.new()
	_assert_snapshot(n, NODE_SNAPSHOT)
	assert_bool(n.get("refresh_inputs") is Callable).is_true()
	n.free()
