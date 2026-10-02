# filter_data_by_index_test.gd
class_name FilterDataByIndexTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_index.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_index_settings.gd")

func _settings(spec : String, mode : int = 0, invert : bool = false):
	var s = SettingsScript.new()
	s.selected_indices = spec
	s.mode = mode
	s.invert = invert
	return s

func _ids(data) -> Array:
	return Array(data.container("id")) if data != null and data.hasStream("id") else []

func _line(count : int) -> FlowData.Data:
	var pts := []
	var ids := PackedInt32Array()
	for i in range(count):
		pts.append(Vector3(i, 0, 0))
		ids.append(i)
	return H.points(pts, {"id": ids})

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Filter Data By Index"])
	H.dispose(node)

func test_parse_indices_syntax() -> void:
	var p = NodeScript.parse_indices("0, 2:4, -1", 6)
	assert_str(p.error).is_empty()
	assert_array(Array(p.indices)).is_equal([0, 2, 3, 5])
	assert_array(Array(NodeScript.parse_indices(":2", 5).indices)).is_equal([0, 1])
	assert_array(Array(NodeScript.parse_indices("-2:", 5).indices)).is_equal([3, 4])
	assert_array(Array(NodeScript.parse_indices("1:-1", 5).indices)).is_equal([1, 2, 3])
	assert_array(Array(NodeScript.parse_indices("7, -9", 5).indices)).is_equal([])
	assert_array(Array(NodeScript.parse_indices("4,4,1", 5).indices)).is_equal([1, 4])
	assert_array(Array(NodeScript.parse_indices("", 5).indices)).is_equal([])
	assert_str(NodeScript.parse_indices("a", 5).error).contains("Invalid")
	assert_str(NodeScript.parse_indices("1:2:3", 5).error).contains("Invalid")

func test_points_mode_split_and_invert() -> void:
	var r := H.exec(NodeScript, _settings("0, 3:", 1), [_line(6)])
	assert_str(r.err).is_empty()
	assert_array(_ids(H.port(r, 0))).is_equal([0, 3, 4, 5])
	assert_array(_ids(H.port(r, 1))).is_equal([1, 2])
	var inv := H.exec(NodeScript, _settings("0, 3:", 1, true), [_line(6)])
	assert_array(_ids(H.port(inv, 0))).is_equal([1, 2])

func test_points_mode_keeps_broadcast_and_tags() -> void:
	var d = _line(4)
	d.registerStream("density", PackedFloat32Array([0.5]))
	d.tags = PackedStringArray(["a"])
	var r := H.exec(NodeScript, _settings("-1", 1), [d])
	var out = H.port(r, 0)
	assert_array(_ids(out)).is_equal([3])
	assert_float(out.value_at("density", 0)).is_equal_approx(0.5, 1e-6)
	assert_array(Array(out.tags)).is_equal(["a"])

func test_data_mode_routes_whole_entries_by_bulk_index() -> void:
	var ctx = H.make_ctx()
	var node = NodeScript.new()
	node.name = "under_test"
	node.settings = _settings("1, -1")
	node.preExecute(ctx)
	node.num_connected_bulks = 4
	for i in range(4):
		H.run_bulk(node, [_line(i + 1)], ctx)
	assert_str(node.err).is_empty()
	var inside := []
	for b in range(4):
		inside.append(H.out(node, 0, b).size())
	assert_array(inside).is_equal([0, 2, 0, 4])
	assert_int(H.out(node, 1, 0).size()).is_equal(1)
	assert_int(H.out(node, 1, 1).size()).is_equal(0)
	H.dispose(node)

func test_data_mode_single_entry() -> void:
	var r := H.exec(NodeScript, _settings("0"), [_line(3)])
	assert_int(H.port(r, 0).size()).is_equal(3)
	assert_int(H.port(r, 1).size()).is_equal(0)
	var r2 := H.exec(NodeScript, _settings("0", 0, true), [_line(3)])
	assert_int(H.port(r2, 0).size()).is_equal(0)
	assert_int(H.port(r2, 1).size()).is_equal(3)

func test_empty_input_and_errors() -> void:
	var r := H.exec(NodeScript, _settings("0", 1), [_line(0)])
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 0).size()).is_equal(0)
	assert_str(H.exec(NodeScript, _settings("x"), [_line(2)]).err).contains("Invalid")
	var missing := H.exec(NodeScript, _settings("0"), [null])
	assert_str(missing.err).contains("not connected")
	# Data mode keeps later bulk indices aligned even on a missing entry.
	assert_int(missing.bulks.size()).is_equal(1)

func test_graph_partitions_filtered_by_entry_index() -> void:
	var graph = TestGraph.new() \
		.node("grid", "grid", {"x": 4, "y": 1, "z": 1}) \
		.node("part", "partition", {"attribute_name": "position.x"}) \
		.node("pick", "filter_data_by_index", {"selected_indices": "0, -1"}) \
		.node("keep", "merge") \
		.node("rest", "merge") \
		.node("out_keep", "output", {"name": "kept"}) \
		.node("out_rest", "output", {"name": "rest"}) \
		.link("grid", 0, "part", 0) \
		.link("part", 0, "pick", 0) \
		.link("pick", 0, "keep", 0) \
		.link("pick", 1, "rest", 0) \
		.link("keep", 0, "out_keep", 0) \
		.link("rest", 0, "out_rest", 0) \
		.build()
	var outputs = FlowNodeIO.evaluate(graph)
	assert_array(FlowNodeIO.last_errors).is_empty()
	assert_int(outputs["kept"].size()).is_equal(2)
	assert_int(outputs["rest"].size()).is_equal(2)
