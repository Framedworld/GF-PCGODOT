# r5_loop_review_test.gd
# Adversarial review (WP13-R5) of loop and subgraph: key ordering, merge of
# broadcast streams, chunk sizes and the recursion guard of dynamic graphs.
class_name R5LoopReviewTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const LoopNode = preload("res://addons/flow_nodes_editor/nodes/loop.gd")
const LoopSettings = preload("res://addons/flow_nodes_editor/nodes/loop_settings.gd")

const PARTITIONS := LoopSettings.IterationMode.Partitions
const CHUNKS := LoopSettings.IterationMode.Chunks
const MERGE := LoopSettings.OutputMode.Merge

func _passthrough_body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "out", 0) \
		.build()

func _make(graph: FlowGraphResource, mode: int, extra := {}) -> FlowNodeBase:
	var node = LoopNode.new()
	node.name = "test_loop"
	node.node_template = "loop"
	var s = LoopSettings.new()
	s.graph = graph
	s.item_input_name = "item"
	s.output_attribute_name = "result"
	s.iteration_mode = mode
	s.output_mode = MERGE
	for key in extra:
		s.set(key, extra[key])
	node.settings = s
	return node

func _run(node: FlowNodeBase, data: FlowData.Data) -> void:
	var ctx := TestGraph.make_ctx()
	var src := FlowNodeBase.new()
	src.name = &"src"
	src.generated_bulks.append([data])
	src.num_generated_bulks = 1
	node.deps.clear()
	node.deps.append({ "from_node": &"src", "from_port": 0, "to_node": node.name, "to_port": 0 })
	ctx.gedit_nodes_by_name = { &"src": src }
	node.preExecute(ctx)
	node.run(ctx)

func _out(node: FlowNodeBase):
	if node.generated_bulks.is_empty():
		return null
	return node.generated_bulks[0][0]

func _values(data, stream_name: String) -> Array:
	var v = TestGraph.stream_values(data, stream_name)
	return Array(v) if v != null else []

func _points_with_broadcast(n: int) -> FlowData.Data:
	var positions := []
	for i in range(n):
		positions.append(Vector3(i, 0, 0))
	var d := TestGraph.points(positions)
	d.registerStream("k", PackedFloat32Array([7.0]), FlowData.DataType.Float)
	d.registerStream("group", PackedInt32Array([0, 1, 0, 1]), FlowData.DataType.Int)
	return d

# --- key ordering ------------------------------------------------------------------

func _sorted_text(keys: Array) -> String:
	var copy := keys.duplicate()
	copy.sort_custom(LoopNode.key_less)
	return var_to_str(copy)

func test_key_order_with_nan_does_not_depend_on_input_order() -> void:
	var nan_v : float = sqrt(-1.0)
	var a := [3.0, nan_v, 1.0, -INF, 2.0, INF]
	var expected := _sorted_text(a)
	var permutations := [
		[nan_v, 2.0, 1.0, INF, 3.0, -INF],
		[1.0, 3.0, 2.0, nan_v, -INF, INF],
		[INF, -INF, 3.0, 2.0, 1.0, nan_v],
	]
	for p in permutations:
		assert_str(_sorted_text(p)).is_equal(expected)
	# NaN is ordered after every number, numbers stay ascending.
	assert_str(expected).is_equal(var_to_str([-INF, 1.0, 2.0, 3.0, INF, nan_v]))

# --- Merge output with broadcast streams ---------------------------------------------

func test_chunks_merge_expands_broadcast_streams() -> void:
	var node := _make(_passthrough_body(), CHUNKS, {"chunk_size": 2})
	_run(node, _points_with_broadcast(4))
	assert_str(node.err).is_empty()
	var out = _out(node)
	assert_array(_values(out, "k")).is_equal([7.0, 7.0, 7.0, 7.0])
	assert_array(_values(out, "group")).is_equal([0, 1, 0, 1])

func test_partitions_merge_expands_broadcast_streams() -> void:
	var node := _make(_passthrough_body(), PARTITIONS, {"partition_attribute": "group"})
	_run(node, _points_with_broadcast(4))
	assert_str(node.err).is_empty()
	var out = _out(node)
	assert_array(_values(out, "k")).is_equal([7.0, 7.0, 7.0, 7.0])
	assert_array(_values(out, "group")).is_equal([0, 0, 1, 1])

func test_chunk_size_edge_values() -> void:
	for size in [0, -3, 1, 4, 100]:
		var node := _make(_passthrough_body(), CHUNKS, {"chunk_size": size})
		_run(node, _points_with_broadcast(4))
		assert_str(node.err).is_empty()
		assert_int(_values(_out(node), "position").size()).is_equal(4)

# --- recursion guard ---------------------------------------------------------------

func test_self_referencing_dynamic_loop_reports_the_recursion_guard() -> void:
	# The body loops over its own item with graph_attribute "g", and every item
	# carries the body itself in "g": an unbounded recursion.
	var body : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph_attribute": "g", "item_input_name": "item", "output_attribute_name": "result"}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "loop", 0) \
		.link("loop", 0, "out", 0) \
		.build()
	var item := TestGraph.points([Vector3.ZERO])
	var graphs : Array[Resource] = [body]
	item.registerStream("g", graphs, FlowData.DataType.Resource)
	FlowNodeIO.evaluate(body, {"item": item})
	var messages := PackedStringArray()
	for e in FlowNodeIO.last_errors:
		messages.append(String(e.get("message", "")))
	var text := "\n".join(messages)
	assert_str(text).contains("maximum nesting depth")
	# Break the reference cycle data -> graph so nothing leaks.
	item.delStream("g")

func test_self_referencing_subgraph_reports_the_recursion_guard() -> void:
	var g : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("sub", "subgraph", {}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "sub", 0) \
		.link("sub", 0, "out", 0) \
		.build()
	for n in g.data["nodes"]:
		if n["name"] == &"sub":
			n["settings"]["graph"] = g
	FlowNodeIO.evaluate(g, {"item": TestGraph.points([Vector3.ZERO])})
	var messages := PackedStringArray()
	for e in FlowNodeIO.last_errors:
		messages.append(String(e.get("message", "")))
	assert_str("\n".join(messages)).contains("maximum nesting depth")
	# Break the graph -> settings -> graph cycle.
	for n in g.data["nodes"]:
		if n["name"] == &"sub":
			n["settings"].erase("graph")

# --- Merge of results whose attribute types differ ----------------------------------------

func _typed_body(data_type: int) -> FlowGraphResource:
	var settings := {"name": "v", "data_type": data_type, "cte_int": 3, "cte_float": 0.5, "cte_string": "s"}
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("add", "add_attribute", settings) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "add", 0) \
		.link("add", 0, "out", 0) \
		.build()

func test_merge_survives_results_with_different_attribute_types() -> void:
	# Two dynamic bodies write "v" as Int and as String. Merging must not hit a
	# script error (append_array of mismatched packed arrays): every point is
	# still emitted and the first type wins.
	var d := TestGraph.points([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var graphs : Array[Resource] = [_typed_body(FlowData.DataType.Int), _typed_body(FlowData.DataType.String), _typed_body(FlowData.DataType.Int)]
	d.registerStream("g", graphs, FlowData.DataType.Resource)
	var node = LoopNode.new()
	node.name = "dyn_loop"
	node.node_template = "loop"
	var s = LoopSettings.new()
	s.graph_attribute = "g"
	s.item_input_name = "item"
	s.output_attribute_name = "result"
	node.settings = s
	_run(node, d)
	var out = _out(node)
	assert_object(out).is_not_null()
	assert_int(_values(out, "position").size()).is_equal(3)
	assert_int(out.streams["v"].data_type).is_equal(FlowData.DataType.Int)
	assert_array(_values(out, "v")).is_equal([3, 0, 3])
	# Numeric types convert to the first type (Float 0.5 into Int gives 0).
	var numeric : Array[Resource] = [_typed_body(FlowData.DataType.Float), _typed_body(FlowData.DataType.Int), _typed_body(FlowData.DataType.Float)]
	d.registerStream("g", numeric, FlowData.DataType.Resource)
	node = LoopNode.new()
	node.name = "dyn_loop"
	node.node_template = "loop"
	node.settings = s
	_run(node, d)
	out = _out(node)
	assert_int(out.streams["v"].data_type).is_equal(FlowData.DataType.Float)
	assert_array(_values(out, "v")).is_equal([0.5, 3.0, 0.5])
	d.delStream("g")

# --- partition keys of the extended types --------------------------------------------

func test_int64_partition_value_keeps_its_bits_in_the_data_attribute() -> void:
	var big : int = 1 << 40
	var d := TestGraph.points([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	d.registerStream("big", PackedInt64Array([big + 1, big, big + 1]), FlowData.DataType.Int64)
	var node := _make(_passthrough_body(), PARTITIONS, {"partition_attribute": "big"})
	var built : Dictionary = node.build_iterations(d, [])
	assert_str(built.error).is_empty()
	var its : Array = built.iterations
	assert_int(its.size()).is_equal(2)
	assert_int(its[0].key).is_equal(big)
	assert_int(its[0].item.get_data_attr("big")).is_equal(big)
	assert_int(its[1].item.get_data_attr("big")).is_equal(big + 1)
	assert_int(its[0].item.data_attrs["big"].data_type).is_equal(FlowData.DataType.Int64)
	assert_int(its[1].attrs["big"]).is_equal(big + 1)

func test_double_partition_value_keeps_its_precision() -> void:
	var v : float = 0.1234567890123
	var d := TestGraph.points([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	d.registerStream("dbl", PackedFloat64Array([v, v]), FlowData.DataType.Double)
	var node := _make(_passthrough_body(), PARTITIONS, {"partition_attribute": "dbl"})
	var its : Array = node.build_iterations(d, []).iterations
	assert_int(its.size()).is_equal(1)
	assert_float(its[0].item.get_data_attr("dbl")).is_equal(v)
