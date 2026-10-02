# loop_modes_test.gd
# WP8 (docs/_round2/WP8.md): loop iteration modes, per-iteration runtime
# parameters, key-derived seeds, Merge / Collection output, feedback in every
# mode, get_loop_index (LoopIteration source) and get_loop_key.
class_name LoopModesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const LoopNode = preload("res://addons/flow_nodes_editor/nodes/loop.gd")
const LoopSettings = preload("res://addons/flow_nodes_editor/nodes/loop_settings.gd")

const POINTS := LoopSettings.IterationMode.Points
const ENTRIES := LoopSettings.IterationMode.Entries
const PARTITIONS := LoopSettings.IterationMode.Partitions
const CHUNKS := LoopSettings.IterationMode.Chunks
const MERGE := LoopSettings.OutputMode.Merge
const COLLECTION := LoopSettings.OutputMode.Collection


func after_test() -> void:
	TestGraph.unregister_probes()


# --- helpers -------------------------------------------------------------------------

func _points(xs: Array) -> FlowData.Data:
	var positions := []
	for x in xs:
		positions.append(Vector3(x, 0, 0))
	return TestGraph.points(positions)

## Points at x = 0..n-1 with an Int "group" stream.
func _grouped(groups: Array, xs: Array = []) -> FlowData.Data:
	if xs.is_empty():
		for i in range(groups.size()):
			xs.append(i)
	var d := _points(xs)
	d.registerStream("group", PackedInt32Array(groups), FlowData.DataType.Int)
	return d

func _xs(data) -> Array:
	var out := []
	var values = TestGraph.stream_values(data, "position")
	if values == null:
		return out
	for v in values:
		out.append(v.x)
	return out

func _ints(data, stream_name: String) -> Array:
	var values = TestGraph.stream_values(data, stream_name)
	return Array(values) if values != null else []

## item -> output "result".
func _passthrough_body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "out", 0) \
		.build()

## item -> get_loop_index (LoopIteration, "it") -> get_loop_key ("key") ->
## add_attribute "count" (cte_int bound to iteration_count) -> output.
func _tagging_body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("idx", "get_loop_index", {"out_name": "it", "source": 1}) \
		.node("key", "get_loop_key", {"out_name": "key"}) \
		.node("count", "add_attribute", {"name": "count", "data_type": FlowData.DataType.Int, "cte_int": -5, "bindings": {"cte_int": "iteration_count"}}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "idx", 0) \
		.link("idx", 0, "key", 0) \
		.link("key", 0, "count", 0) \
		.link("count", 0, "out", 0) \
		.build()

## result = item; acc = merge(acc, item).
func _feedback_body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.in_param("acc", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("in_acc", "input_acc", {"name": "acc", "data_type": FlowData.DataType.Vector}) \
		.node("grow", "merge") \
		.node("out_result", "output", {"name": "result"}) \
		.node("out_acc", "output", {"name": "acc"}) \
		.link("in_acc", 0, "grow", 0) \
		.link("in_item", 0, "grow", 0) \
		.link("in_item", 0, "out_result", 0) \
		.link("grow", 0, "out_acc", 0) \
		.build()

## item -> attribute_random "r" (seed-dependent) -> output.
func _random_body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("rand", "attribute_random", {"attribute_name": "r", "min_value": 0.0, "max_value": 1000.0, "random_seed": 99}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "rand", 0) \
		.link("rand", 0, "out", 0) \
		.build()

func _make(graph: FlowGraphResource, mode := POINTS, output_mode := MERGE, extra := {}) -> FlowNodeBase:
	var node = LoopNode.new()
	node.name = "test_loop"
	node.node_template = "loop"
	var s = LoopSettings.new()
	s.graph = graph
	s.item_input_name = "item"
	s.output_attribute_name = "result"
	s.iteration_mode = mode
	s.output_mode = output_mode
	for key in extra:
		s.set(key, extra[key])
	node.settings = s
	return node

## Runs `node` the way the executor does (preExecute + run), with every Data
## of `entries` arriving as its own entry (bulk) on the Stream pin and `extra`
## (an Array of Data or null) on pins 1.. of the first entry.
func _run_entries(node: FlowNodeBase, entries: Array, extra: Array = [], ctx: FlowData.EvaluationContext = null) -> void:
	if ctx == null:
		ctx = TestGraph.make_ctx()
	var src := FlowNodeBase.new()
	src.name = &"src"
	for entry in entries:
		src.generated_bulks.append([entry])
	src.num_generated_bulks = entries.size()
	var instances := { &"src": src }
	node.deps.clear()
	node.deps.append({ "from_node": &"src", "from_port": 0, "to_node": node.name, "to_port": 0 })
	for i in range(extra.size()):
		var x := FlowNodeBase.new()
		x.name = StringName("x%d" % i)
		x.generated_bulks.append([extra[i]])
		x.num_generated_bulks = 1
		instances[x.name] = x
		node.deps.append({ "from_node": x.name, "from_port": 0, "to_node": node.name, "to_port": i + 1 })
	ctx.gedit_nodes_by_name = instances
	node.preExecute(ctx)
	node.run(ctx)

func _bulk(node, i: int, port := 0):
	if i >= node.generated_bulks.size():
		return null
	var bulk : Array = node.generated_bulks[i]
	return bulk[port] if port < bulk.size() else null

func _eval(graph: FlowGraphResource, inputs: Dictionary, seed := 0) -> Dictionary:
	return FlowNodeIO.evaluate(graph, inputs, seed)


# --- Points (historical) ------------------------------------------------------------

func test_points_mode_is_the_default_and_matches_today() -> void:
	var s := LoopSettings.new()
	assert_int(s.iteration_mode).is_equal(POINTS)
	assert_int(s.output_mode).is_equal(MERGE)
	assert_str(s.graph_attribute).is_empty()
	var node := _make(_passthrough_body())
	_run_entries(node, [_points([3, 1, 2])])
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(1)
	assert_array(_xs(_bulk(node, 0))).is_equal([3.0, 1.0, 2.0])

func test_points_mode_runs_once_per_input_entry() -> void:
	# Points, Partitions and Chunks keep the per-entry execution: two entries
	# give two merged output entries, and the iteration index restarts.
	var node := _make(_tagging_body())
	_run_entries(node, [_points([1, 2]), _points([5, 6, 7])])
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(2)
	assert_array(_ints(_bulk(node, 0), "it")).is_equal([0, 1])
	assert_array(_ints(_bulk(node, 1), "it")).is_equal([0, 1, 2])
	assert_array(_ints(_bulk(node, 1), "count")).is_equal([3, 3, 3])

func test_points_mode_iteration_params() -> void:
	var node := _make(_tagging_body())
	_run_entries(node, [_points([4, 5, 6])])
	var out = _bulk(node, 0)
	assert_array(_ints(out, "it")).is_equal([0, 1, 2])
	assert_array(_ints(out, "key")).is_equal([0, 1, 2])
	assert_array(_ints(out, "count")).is_equal([3, 3, 3])


# --- Entries --------------------------------------------------------------------------

func test_entries_mode_iterates_every_entry_of_the_pin_once() -> void:
	TestGraph.register_probes()
	var body : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("spy", "test_probe_final") \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "spy", 0) \
		.link("in_item", 0, "out", 0) \
		.build()
	var node := _make(body, ENTRIES)
	_run_entries(node, [_points([1, 2]), _points([3]), _points([4, 5, 6])])
	var sizes = TestGraph.probe().exec_log.map(func(e): return e.a_size)
	assert_str(node.err).is_empty()
	assert_array(sizes).is_equal([2, 1, 3])
	# Merge: one output entry with every iteration's points in order.
	assert_int(node.generated_bulks.size()).is_equal(1)
	assert_array(_xs(_bulk(node, 0))).is_equal([1.0, 2.0, 3.0, 4.0, 5.0, 6.0])

func test_entries_mode_params_and_key_attribute() -> void:
	var a := _points([1])
	a.set_data_attr("room", "kitchen")
	var b := _points([2, 3])
	b.set_data_attr("room", "hall")
	var node := _make(_tagging_body(), ENTRIES)
	_run_entries(node, [a, b])
	var out = _bulk(node, 0)
	assert_array(_ints(out, "it")).is_equal([0, 1, 1])
	assert_array(_ints(out, "key")).is_equal([0, 1, 1])
	assert_array(_ints(out, "count")).is_equal([2, 2, 2])
	# key_attribute: the entry's per-data attribute is its key.
	var keyed := _make(_tagging_body(), ENTRIES, MERGE, {"key_attribute": "room"})
	_run_entries(keyed, [a, b])
	assert_array(Array(TestGraph.stream_values(_bulk(keyed, 0), "key"))).is_equal(["kitchen", "hall", "hall"])

func test_entries_mode_passes_per_data_attributes_as_params() -> void:
	# A binding reads the entry's per-data attribute "level" by name.
	var body : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("lvl", "add_attribute", {"name": "lvl", "data_type": FlowData.DataType.Int, "cte_int": -1, "bindings": {"cte_int": "level"}}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "lvl", 0) \
		.link("lvl", 0, "out", 0) \
		.build()
	var a := _points([1])
	a.set_data_attr("level", 3)
	var b := _points([2])
	b.set_data_attr("level", 8)
	var node := _make(body, ENTRIES)
	_run_entries(node, [a, b])
	assert_array(_ints(_bulk(node, 0), "lvl")).is_equal([3, 8])

func test_entries_mode_with_execute_only_sees_one_entry() -> void:
	# Called without run() (no upstream elements), the connected Data is the
	# only entry.
	var node := _make(_tagging_body(), ENTRIES)
	node.inputs = [_points([1, 2, 3])]
	var ctx := TestGraph.make_ctx()
	node.preExecute(ctx)
	node.execute(ctx)
	assert_array(_ints(_bulk(node, 0), "it")).is_equal([0, 0, 0])
	assert_array(_ints(_bulk(node, 0), "count")).is_equal([1, 1, 1])

func test_entries_mode_from_a_partition_node_in_a_graph() -> void:
	# partition emits one entry per value; the Entries loop sees all of them.
	var graph : FlowGraphResource = TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("part", "partition", {"attribute_name": "group"}) \
		.node("loop", "loop", {"graph": _tagging_body(), "item_input_name": "item", "output_attribute_name": "result", "iteration_mode": ENTRIES}) \
		.node("out", "output", {"name": "looped"}) \
		.link("in_pts", 0, "part", 0) \
		.link("part", 0, "loop", 0) \
		.link("loop", 0, "out", 0) \
		.build()
	var outputs := _eval(graph, {"pts": _grouped([7, 7, 4, 7, 4])})
	assert_array(FlowNodeIO.last_errors).is_empty()
	var out = outputs.get("looped")
	# partition keeps first-seen order: group 7 (x 0, 1, 3), then 4 (x 2, 4).
	assert_array(_xs(out)).is_equal([0.0, 1.0, 3.0, 2.0, 4.0])
	assert_array(_ints(out, "it")).is_equal([0, 0, 0, 1, 1])
	assert_array(_ints(out, "count")).is_equal([2, 2, 2, 2, 2])


# --- Partitions ------------------------------------------------------------------------

func test_partitions_are_sorted_by_key_and_keep_point_order() -> void:
	var node := _make(_tagging_body(), PARTITIONS, COLLECTION, {"partition_attribute": "group"})
	_run_entries(node, [_grouped([3, 1, 3, 2, 1])])
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(3)
	assert_array(_xs(_bulk(node, 0))).is_equal([1.0, 4.0])
	assert_array(_xs(_bulk(node, 1))).is_equal([3.0])
	assert_array(_xs(_bulk(node, 2))).is_equal([0.0, 2.0])
	assert_array(_ints(_bulk(node, 2), "key")).is_equal([3, 3])
	assert_array(_ints(_bulk(node, 2), "it")).is_equal([2, 2])
	assert_array(_ints(_bulk(node, 0), "count")).is_equal([3, 3])
	# The partition value is a per-data attribute of the iteration's data.
	assert_int(_bulk(node, 1).get_data_attr("group")).is_equal(2)

func test_partitions_by_string_float_and_vector() -> void:
	var d := _points([0, 1, 2, 3])
	d.registerStream("kind", PackedStringArray(["tree", "bush", "tree", "anvil"]), FlowData.DataType.String)
	d.registerStream("w", PackedFloat32Array([0.5, -2.0, 0.5, 10.0]), FlowData.DataType.Float)
	d.registerStream("cell", PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]), FlowData.DataType.Vector)
	var by_kind := _make(_tagging_body(), PARTITIONS, COLLECTION, {"partition_attribute": "kind"})
	_run_entries(by_kind, [d])
	assert_array(range(3).map(func(i): return _xs(_bulk(by_kind, i)))).is_equal([[3.0], [1.0], [0.0, 2.0]])
	assert_array(Array(TestGraph.stream_values(_bulk(by_kind, 2), "key"))).is_equal(["tree", "tree"])
	var by_w := _make(_tagging_body(), PARTITIONS, COLLECTION, {"partition_attribute": "w"})
	_run_entries(by_w, [d])
	assert_array(range(3).map(func(i): return _xs(_bulk(by_w, i)))).is_equal([[1.0], [0.0, 2.0], [3.0]])
	var by_cell := _make(_tagging_body(), PARTITIONS, COLLECTION, {"partition_attribute": "cell"})
	_run_entries(by_cell, [d])
	assert_array(range(3).map(func(i): return _xs(_bulk(by_cell, i)))).is_equal([[3.0], [1.0], [0.0, 2.0]])

func test_partition_by_per_data_attribute_is_one_partition() -> void:
	var d := _points([0, 1])
	d.set_data_attr("biome", "desert")
	var node := _make(_tagging_body(), PARTITIONS, COLLECTION, {"partition_attribute": "@data.biome"})
	_run_entries(node, [d])
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(1)
	assert_array(Array(TestGraph.stream_values(_bulk(node, 0), "key"))).is_equal(["desert", "desert"])

func test_partition_attribute_errors() -> void:
	var missing := _make(_passthrough_body(), PARTITIONS, MERGE, {"partition_attribute": "nope"})
	_run_entries(missing, [_points([1])])
	assert_str(missing.err).is_equal("Loop partition attribute not found in input: nope")
	assert_array(missing.generated_bulks).is_empty()
	var unset := _make(_passthrough_body(), PARTITIONS)
	_run_entries(unset, [_points([1])])
	assert_str(unset.err).is_equal("Loop Partitions mode needs a partition_attribute")

func test_partition_value_param_is_bindable() -> void:
	var body : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("g", "add_attribute", {"name": "g2", "data_type": FlowData.DataType.Int, "cte_int": -1, "bindings": {"cte_int": "group"}}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "g", 0) \
		.link("g", 0, "out", 0) \
		.build()
	var node := _make(body, PARTITIONS, MERGE, {"partition_attribute": "group"})
	_run_entries(node, [_grouped([5, 2, 5])])
	assert_array(_ints(_bulk(node, 0), "g2")).is_equal([2, 5, 5])


# --- Chunks ----------------------------------------------------------------------------

func test_chunks_cut_consecutive_points_and_the_last_may_be_short() -> void:
	var node := _make(_tagging_body(), CHUNKS, COLLECTION, {"chunk_size": 2})
	_run_entries(node, [_points([0, 1, 2, 3, 4])])
	assert_str(node.err).is_empty()
	assert_int(node.generated_bulks.size()).is_equal(3)
	assert_array(_xs(_bulk(node, 0))).is_equal([0.0, 1.0])
	assert_array(_xs(_bulk(node, 1))).is_equal([2.0, 3.0])
	assert_array(_xs(_bulk(node, 2))).is_equal([4.0])
	assert_array(_ints(_bulk(node, 2), "key")).is_equal([2])
	assert_array(_ints(_bulk(node, 1), "count")).is_equal([3, 3])

func test_chunk_size_is_at_least_one() -> void:
	var s := LoopSettings.new()
	s.chunk_size = 0
	assert_int(s.chunk_size).is_equal(1)


# --- Output modes ----------------------------------------------------------------------

func test_collection_output_drives_a_downstream_node_once_per_iteration() -> void:
	TestGraph.register_probes()
	var graph : FlowGraphResource = TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph": _passthrough_body(), "item_input_name": "item", "output_attribute_name": "result", "iteration_mode": CHUNKS, "chunk_size": 2, "output_mode": COLLECTION}) \
		.node("after", "test_probe_final") \
		.link("in_pts", 0, "loop", 0) \
		.link("loop", 0, "after", 0) \
		.build()
	_eval(graph, {"pts": _points([0, 1, 2, 3, 4])})
	var seen = TestGraph.probe().exec_log.filter(func(e): return e.name == "after").map(func(e): return _xs(e.a_data))
	assert_array(seen).is_equal([[0.0, 1.0], [2.0, 3.0], [4.0]])

func test_merge_output_drives_a_downstream_node_once() -> void:
	TestGraph.register_probes()
	var graph : FlowGraphResource = TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph": _passthrough_body(), "item_input_name": "item", "output_attribute_name": "result", "iteration_mode": CHUNKS, "chunk_size": 2}) \
		.node("after", "test_probe_final") \
		.link("in_pts", 0, "loop", 0) \
		.link("loop", 0, "after", 0) \
		.build()
	_eval(graph, {"pts": _points([0, 1, 2, 3, 4])})
	var seen = TestGraph.probe().exec_log.filter(func(e): return e.name == "after").map(func(e): return _xs(e.a_data))
	assert_array(seen).is_equal([[0.0, 1.0, 2.0, 3.0, 4.0]])

func test_collection_with_no_iterations_emits_one_empty_entry() -> void:
	var node := _make(_passthrough_body(), POINTS, COLLECTION)
	_run_entries(node, [FlowData.Data.new()])
	assert_int(node.generated_bulks.size()).is_equal(1)
	assert_int(_bulk(node, 0).size()).is_equal(0)


# --- Feedback in every mode -------------------------------------------------------------

func test_feedback_accumulates_in_every_mode() -> void:
	for mode in [POINTS, ENTRIES, PARTITIONS, CHUNKS]:
		var node := _make(_feedback_body(), mode, MERGE, {"feedback_param_name": "acc", "partition_attribute": "group", "chunk_size": 2})
		var entries := [_grouped([1, 2, 1], [1, 2, 3])]
		if mode == ENTRIES:
			entries = [_grouped([1], [1]), _grouped([2, 1], [2, 3])]
		_run_entries(node, entries, [_points([-1])])
		assert_str(node.err).is_empty()
		var acc = _bulk(node, 0, 1)
		var expected := [-1.0, 1.0, 2.0, 3.0]
		if mode == PARTITIONS:
			expected = [-1.0, 1.0, 3.0, 2.0]   # group 1 (x 1, 3) before group 2
		assert_array(_xs(acc)).override_failure_message("mode %d" % mode).is_equal(expected)

func test_collection_carries_the_running_feedback_per_entry() -> void:
	var node := _make(_feedback_body(), CHUNKS, COLLECTION, {"feedback_param_name": "acc", "chunk_size": 1})
	_run_entries(node, [_points([1, 2, 3])])
	assert_int(node.generated_bulks.size()).is_equal(3)
	assert_array(_xs(_bulk(node, 0, 1))).is_equal([1.0])
	assert_array(_xs(_bulk(node, 1, 1))).is_equal([1.0, 2.0])
	assert_array(_xs(_bulk(node, 2, 1))).is_equal([1.0, 2.0, 3.0])


# --- Seeds -----------------------------------------------------------------------------

func test_iteration_seed_formula() -> void:
	# Int keys keep the historical hash([seed, index]) & 0x7fffffff.
	for i in [0, 1, 7, 123]:
		assert_int(LoopNode.iteration_seed(42, i)).is_equal(int(hash([42, i]) & 0x7fffffff))
	assert_int(LoopNode.iteration_seed(0, 5)).is_equal(0)
	assert_int(LoopNode.iteration_seed(0, "tree")).is_equal(0)
	assert_int(LoopNode.iteration_seed(42, "tree")).is_equal(FlowNodeBase.derive_seed(42, int(hash("tree") & 0x7fffffff)))
	assert_int(LoopNode.key_seed(2.5)).is_equal(int(hash(var_to_str(2.5)) & 0x7fffffff))
	assert_int(LoopNode.key_seed(true)).is_equal(1)

func _partition_graph(body: FlowGraphResource) -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result", "iteration_mode": PARTITIONS, "partition_attribute": "group"}) \
		.node("out", "output", {"name": "looped"}) \
		.link("in_pts", 0, "loop", 0) \
		.link("loop", 0, "out", 0) \
		.build()

## x -> r of the merged loop output.
func _r_by_x(data) -> Dictionary:
	var result := {}
	var xs := _xs(data)
	var rs = TestGraph.stream_values(data, "r")
	for i in range(xs.size()):
		result[xs[i]] = rs[i]
	return result

func test_removing_a_partition_leaves_the_others_unchanged() -> void:
	var graph := _partition_graph(_random_body())
	var full := _r_by_x(_eval(graph, {"pts": _grouped([1, 1, 2, 3, 3], [0, 1, 2, 3, 4])}, 42).looped)
	var without_2 := _r_by_x(_eval(graph, {"pts": _grouped([1, 1, 3, 3], [0, 1, 3, 4])}, 42).looped)
	for x in [0.0, 1.0, 3.0, 4.0]:
		assert_float(without_2[x]).is_equal(full[x])
	# The graph seed does reach the iterations.
	var other_seed := _r_by_x(_eval(graph, {"pts": _grouped([1, 1, 2, 3, 3], [0, 1, 2, 3, 4])}, 7).looped)
	assert_bool(other_seed[0.0] != full[0.0]).is_true()

func test_index_keys_reshuffle_but_partition_keys_do_not() -> void:
	# The same removal in Chunks mode (key = chunk index) moves the third
	# chunk to index 1, so its seed and values change: keys matter.
	var body := _random_body()
	var graph : FlowGraphResource = TestGraph.new() \
		.in_param("pts", FlowData.DataType.Vector) \
		.node("in_pts", "input_pts", {"name": "pts", "data_type": FlowData.DataType.Vector}) \
		.node("loop", "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result", "iteration_mode": CHUNKS, "chunk_size": 1}) \
		.node("out", "output", {"name": "looped"}) \
		.link("in_pts", 0, "loop", 0) \
		.link("loop", 0, "out", 0) \
		.build()
	var full := _r_by_x(_eval(graph, {"pts": _points([0, 1, 2])}, 42).looped)
	var shifted := _r_by_x(_eval(graph, {"pts": _points([0, 2])}, 42).looped)
	assert_float(shifted[0.0]).is_equal(full[0.0])
	assert_bool(shifted[2.0] != full[2.0]).is_true()

func test_graph_seed_zero_keeps_legacy_node_seeds() -> void:
	# With seed 0 every iteration runs with graph seed 0: the body's nodes use
	# their own random_seed, exactly as evaluating the body directly.
	var body := _random_body()
	var input := _grouped([1, 2, 1], [0, 1, 2])
	var looped := _r_by_x(_eval(_partition_graph(body), {"pts": input}, 0).looped)
	var part_1 := input.filter(PackedInt32Array([0, 2]))
	var part_2 := input.filter(PackedInt32Array([1]))
	var direct := _r_by_x(_eval(body, {"item": part_1}, 0).result)
	direct.merge(_r_by_x(_eval(body, {"item": part_2}, 0).result))
	assert_dict(looped).is_equal(direct)


# --- Key ordering ------------------------------------------------------------------------

func test_key_ordering() -> void:
	var keys := [3, 1.5, -2, true, "b", "a", Vector3(1, 0, 0), Vector3(0, 5, 0), 1]
	keys.sort_custom(LoopNode.key_less)
	# Numbers numerically (true == 1; ties by Variant type id: bool, int,
	# float), then the rest by their text form.
	assert_array(keys.slice(0, 5)).is_equal([-2, true, 1, 1.5, 3])
	var rest := keys.slice(5).map(func(k): return LoopNode.key_string(k))
	var sorted_rest := rest.duplicate()
	sorted_rest.sort()
	assert_array(rest).is_equal(sorted_rest)
	assert_bool(LoopNode.key_less(Vector3(0, 5, 0), Vector3(1, 0, 0))).is_true()
	assert_bool(LoopNode.key_less("a", "b")).is_true()
	assert_bool(LoopNode.key_less(2, 2)).is_false()


# --- get_loop_index / get_loop_key ---------------------------------------------------------

func test_get_loop_index_and_key_outside_a_loop() -> void:
	var idx = load("res://addons/flow_nodes_editor/nodes/get_loop_index.gd").new()
	idx.name = "idx"
	idx.settings = load("res://addons/flow_nodes_editor/nodes/get_loop_index_settings.gd").new()
	idx.settings.source = 1
	var ctx := TestGraph.make_ctx()
	idx.inputs = [null]
	idx.preExecute(ctx)
	idx.execute(ctx)
	assert_str(idx.err).contains("Not inside a Loop iteration")
	var out = _bulk(idx, 0)
	assert_array(_ints(out, "loop_index")).is_equal([-1])
	# Inside a loop iteration (runtime param present) with no input: a scalar.
	var ctx2 := TestGraph.make_ctx()
	ctx2.runtime_params = {"iteration_index": 4}
	idx.settings.start_index = 10
	idx.preExecute(ctx2)
	idx.execute(ctx2)
	assert_str(idx.err).is_empty()
	assert_array(_ints(_bulk(idx, 0), "loop_index")).is_equal([14])
	# Editor preview without owner: silent.
	var preview := TestGraph.make_ctx()
	preview.preview = true
	var key = load("res://addons/flow_nodes_editor/nodes/get_loop_key.gd").new()
	key.name = "key"
	key.settings = load("res://addons/flow_nodes_editor/nodes/get_loop_key_settings.gd").new()
	key.inputs = [_points([1, 2])]
	key.preExecute(preview)
	key.execute(preview)
	assert_str(key.err).is_empty()
	assert_array(_ints(_bulk(key, 0), "loop_key")).is_equal([-1, -1])

func test_get_loop_index_points_source_is_unchanged() -> void:
	var idx = load("res://addons/flow_nodes_editor/nodes/get_loop_index.gd").new()
	idx.name = "idx"
	idx.settings = load("res://addons/flow_nodes_editor/nodes/get_loop_index_settings.gd").new()
	assert_int(idx.settings.source).is_equal(0)
	var ctx := TestGraph.make_ctx()
	ctx.runtime_params = {"iteration_index": 9}
	idx.inputs = [_points([1, 2, 3])]
	idx.preExecute(ctx)
	idx.execute(ctx)
	assert_array(_ints(_bulk(idx, 0), "loop_index")).is_equal([0, 1, 2])

func test_loop_index_and_key_in_every_mode() -> void:
	var cases := [
		[POINTS, {}, [0, 1, 2, 3], [0, 1, 2, 3]],
		[CHUNKS, {"chunk_size": 3}, [0, 0, 0, 1], [0, 0, 0, 1]],
		[PARTITIONS, {"partition_attribute": "group"}, [1, 0, 1, 0], [9, 4, 9, 4]],
	]
	for case in cases:
		var node := _make(_tagging_body(), case[0], MERGE, case[1])
		_run_entries(node, [_grouped([9, 4, 9, 4])])
		var out = _bulk(node, 0)
		# Merge order: iteration by iteration.
		var it_by_x := {}
		var key_by_x := {}
		var xs := _xs(out)
		for i in range(xs.size()):
			it_by_x[int(xs[i])] = _ints(out, "it")[i]
			key_by_x[int(xs[i])] = _ints(out, "key")[i]
		assert_array(range(4).map(func(x): return it_by_x[x])).override_failure_message("mode %d" % case[0]).is_equal(case[2])
		assert_array(range(4).map(func(x): return key_by_x[x])).override_failure_message("mode %d" % case[0]).is_equal(case[3])
