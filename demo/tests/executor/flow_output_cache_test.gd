# flow_output_cache_test.gd
# FlowOutputCache: hits on repeated evaluation, keys that follow settings,
# seed and input content, copies instead of shared objects, replayed errors,
# LRU bound and clear().
class_name FlowOutputCacheTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var _saved_max := 0


func before_test() -> void:
	_saved_max = FlowOutputCache.max_entries
	FlowOutputCache.clear()


func after_test() -> void:
	FlowOutputCache.max_entries = _saved_max
	FlowOutputCache.clear()


func _graph(x := 3, cte := 0.5) -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": x, "y": 1, "z": 2, "random_seed": 5}) \
		.node("attr", "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": cte}) \
		.node("noise", "attribute_noise", {"target_attribute": "density", "random_seed": 9}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "attr", 0) \
		.link("attr", 0, "noise", 0) \
		.link("noise", 0, "out", 0) \
		.build()

func _eval(graph: FlowGraphResource, seed := 0, inputs := {}, cache := true) -> Dictionary:
	var ctx := FlowNodeIO.make_context(null, seed, {})
	if cache:
		ctx.set_meta(FlowExecutor.OUTPUT_CACHE_META, true)
	return FlowNodeIO.evaluate_collecting_errors(graph, inputs, ctx).outputs

static func _summary(outputs: Dictionary) -> Dictionary:
	var result := {}
	for key in outputs:
		result[str(key)] = FlowNodeIO.snapshot_summarize_data(outputs[key])
	return result


func test_second_evaluation_hits_and_matches_uncached_output() -> void:
	var graph := _graph()
	var uncached := _summary(_eval(graph, 0, {}, false))
	assert_int(FlowOutputCache.hits + FlowOutputCache.misses).is_equal(0)
	var first := _summary(_eval(graph))
	assert_int(FlowOutputCache.misses).is_equal(3)
	assert_int(FlowOutputCache.hits).is_equal(0)
	var second := _summary(_eval(graph))
	assert_int(FlowOutputCache.hits).is_equal(3)
	assert_dict(first).is_equal(uncached)
	assert_dict(second).is_equal(uncached)


func test_flow_graph_node_3d_output_cache_option() -> void:
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	host.graph = _graph()
	add_child(host)
	var plain := _summary(host.generate())
	host.output_cache = true
	host.generate()
	var cached := _summary(host.generate())
	assert_int(FlowOutputCache.hits).is_greater(0)
	assert_dict(cached).is_equal(plain)
	remove_child(host)
	host.free()


func test_key_follows_settings_seed_and_inputs() -> void:
	_eval(_graph())
	var hits := FlowOutputCache.hits
	# A different setting upstream changes every downstream key.
	_eval(_graph(4))
	assert_int(FlowOutputCache.hits).is_equal(hits)
	# A different cte changes attr and noise, not grid.
	_eval(_graph(3, 0.75))
	assert_int(FlowOutputCache.hits).is_equal(hits + 1)
	# A graph seed changes the effective seed of every node.
	hits = FlowOutputCache.hits
	_eval(_graph(), 77)
	assert_int(FlowOutputCache.hits).is_equal(hits)
	# Overrides count like saved settings.
	hits = FlowOutputCache.hits
	var ctx := FlowNodeIO.make_context(null, 0, {}, { "attr/cte_float": 0.9 })
	ctx.set_meta(FlowExecutor.OUTPUT_CACHE_META, true)
	var overridden : Dictionary = FlowNodeIO.evaluate_collecting_errors(_graph(), {}, ctx).outputs
	assert_int(FlowOutputCache.hits).is_equal(hits + 1)
	assert_float(overridden["result"].findStream("w").container[0]).is_equal_approx(0.9, 0.0001)


func test_hits_return_copies() -> void:
	var graph := _graph()
	var first : FlowData.Data = _eval(graph)["result"]
	var second : FlowData.Data = _eval(graph)["result"]
	assert_object(second).is_not_same(first)
	# Mutating what a run returned never reaches the cache.
	var w : PackedFloat32Array = first.findStream("w").container
	w.fill(42.0)
	first.streams["w"].container = w
	first.tags.append("mutated")
	var third : FlowData.Data = _eval(graph)["result"]
	assert_float(third.findStream("w").container[0]).is_equal_approx(0.5, 0.0001)
	assert_bool(third.tags.has("mutated")).is_false()


func test_errors_of_cached_elements_are_replayed() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("bad", "math_op", {"operation": 0, "in_nameA": "nope", "in_nameB": "1", "out_name": "x"}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "bad", 0) \
		.link("bad", 0, "out", 0) \
		.build()
	_eval(graph, 0, {}, false)
	var expected := FlowNodeIO.last_errors.duplicate(true)
	assert_int(expected.size()).is_equal(1)
	_eval(graph)
	assert_array(FlowNodeIO.last_errors).is_equal(expected)
	_eval(graph)
	assert_int(FlowOutputCache.hits).is_greater(0)
	assert_array(FlowNodeIO.last_errors).is_equal(expected)


func test_non_cacheable_nodes_are_never_stored() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("set", "set_variable", {"variable_name": "v"}) \
		.node("get", "get_variable", {"variable_name": "v"}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "set", 0) \
		.link("get", 0, "out", 0) \
		.build()
	_eval(graph)
	_eval(graph)
	# Only the grid is cacheable (variables, output are not).
	assert_int(FlowOutputCache.size()).is_equal(1)
	assert_int(FlowOutputCache.hits).is_equal(1)


func test_cache_is_bounded_and_clear_resets_counters() -> void:
	FlowOutputCache.max_entries = 4
	for x in range(1, 8):
		_eval(_graph(x))
	assert_int(FlowOutputCache.size()).is_less_equal(4)
	assert_int(FlowOutputCache.misses).is_greater(0)
	FlowOutputCache.clear()
	assert_int(FlowOutputCache.size()).is_equal(0)
	assert_int(FlowOutputCache.hits).is_equal(0)
	assert_int(FlowOutputCache.misses).is_equal(0)


func test_loop_iterations_hit_the_cache() -> void:
	# The same body graph evaluated per element: identical items hit.
	var body : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("attr", "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": 2.0}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "attr", 0) \
		.link("attr", 0, "out", 0) \
		.build()
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 1, "y": 1, "z": 1}) \
		.node("copy", "duplicate_point", {"iterations": 3, "offset": Vector3.ZERO}) \
		.node("loop", "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result"}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "copy", 0) \
		.link("copy", 0, "loop", 0) \
		.link("loop", 0, "out", 0) \
		.build()
	var uncached := _summary(_eval(graph, 0, {}, false))
	var cached := _summary(_eval(graph))
	assert_dict(cached).is_equal(uncached)
