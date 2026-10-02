# flow_executor_test.gd
# FlowCompiledGraph caching and invalidation, FlowExecutor modes (synchronous,
# time-sliced, threaded) and its extension points (node_filter, preseeded),
# and the RefCounted element contract.
class_name FlowExecutorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")


# Four independent branches of pure nodes joined by a merge, plus a variable
# round trip, so threaded mode has parallel work and ordering constraints.
func _branchy_graph() -> FlowGraphResource:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 4, "y": 1, "z": 5, "random_seed": 3})
	b.node("merge", "merge")
	b.node("out", "output", {"name": "result"})
	b.node("out_var", "output", {"name": "from_var"})
	for i in range(4):
		var a := "attr_%d" % i
		var m := "math_%d" % i
		var f := "filter_%d" % i
		b.node(a, "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": 0.2 * (i + 1)})
		b.node(m, "math_op", {"operation": 1, "in_nameA": "density", "in_nameB": "w", "out_name": "density"})
		b.node(f, "density_filter", {"lower_bound": 0.0, "upper_bound": 0.5})
		b.link("grid", 0, a, 0)
		b.link(a, 0, m, 0)
		b.link(a, 0, m, 1)
		b.link(m, 0, f, 0)
		b.link(f, 0, "merge", 0)
	b.node("set", "set_variable", {"variable_name": "kept"})
	b.node("get", "get_variable", {"variable_name": "kept"})
	b.link("filter_2", 0, "set", 0)
	b.link("get", 0, "out_var", 0)
	b.link("merge", 0, "out", 0)
	return b.build()

static func _summaries(outputs: Dictionary) -> Dictionary:
	var result := {}
	for key in outputs:
		result[str(key)] = FlowNodeIO.snapshot_summarize_data(outputs[key])
	return JSON.parse_string(JSON.stringify(result, "", true))

func _ctx(options := {}) -> FlowData.EvaluationContext:
	var ctx := TestGraph.make_ctx()
	for option in options:
		ctx.set_meta(option, options[option])
	return ctx


# --- elements ------------------------------------------------------------------------

func test_elements_are_refcounted_and_ui_shims_are_noops_without_a_widget() -> void:
	var element := FlowNodeBase.new()
	assert_bool(element is RefCounted).is_true()
	assert_object(element.get_widget()).is_null()
	assert_object(element.getEditor()).is_null()
	element.initFromScript()
	element.setupDrawDebug()
	element.refreshFromSettings()
	element.setActivity(0.5)
	element.setExecTime(10)
	element.name = "plain"
	assert_str(String(element.name)).is_equal("plain")


func test_evaluation_releases_every_element() -> void:
	var graph := _branchy_graph()
	var ev = FlowNodeIO.begin_evaluation(graph, {}, _ctx(), {}, 0)
	var refs := []
	for node in ev._instances.values():
		refs.append(weakref(node))
	ev.run_to_completion()
	ev = null
	for ref in refs:
		assert_object(ref.get_ref()).is_null()


# --- FlowCompiledGraph ----------------------------------------------------------------

func test_compiled_graph_is_cached_per_graph() -> void:
	var graph := _branchy_graph()
	var first := FlowCompiledGraph.for_graph(graph)
	var count := FlowCompiledGraph.compile_count
	var second := FlowCompiledGraph.for_graph(graph)
	assert_object(second).is_same(first)
	assert_int(FlowCompiledGraph.compile_count).is_equal(count)
	FlowNodeIO.evaluate_graph(graph, {}, _ctx(), {}, 0)
	FlowNodeIO.evaluate_graph(graph, {}, _ctx(), {}, 0)
	assert_int(FlowCompiledGraph.compile_count).is_equal(count)
	assert_bool(first.ordered).is_true()
	assert_int(first.execution_order.size()).is_greater(0)
	assert_int(first.finals.size()).is_greater(0)
	assert_int(first.output_nodes.size()).is_equal(2)


func test_compiled_graph_follows_graph_data_changes() -> void:
	var graph := _branchy_graph()
	var first := FlowCompiledGraph.for_graph(graph)
	var before : int = _summaries(FlowNodeIO.evaluate_graph(graph, {}, _ctx(), {}, 0))["result"]["size"]
	# In-place edit of the saved settings: same dictionary, new content.
	for n_data in graph.data.nodes:
		if n_data.name == &"grid":
			n_data.settings["x"] = 8
	var second := FlowCompiledGraph.for_graph(graph)
	assert_object(second).is_not_same(first)
	var after : int = _summaries(FlowNodeIO.evaluate_graph(graph, {}, _ctx(), {}, 0))["result"]["size"]
	assert_int(after).is_greater(before)
	# A new dictionary.
	graph.data = graph.data.duplicate(true)
	assert_object(FlowCompiledGraph.for_graph(graph)).is_not_same(second)


func test_compiled_graph_follows_node_registry_changes() -> void:
	var graph := _branchy_graph()
	var first := FlowCompiledGraph.for_graph(graph)
	FlowNodeRegistry.register_node_directory(TestGraph.PROBE_DIR)
	var second := FlowCompiledGraph.for_graph(graph)
	FlowNodeRegistry.unregister_node_directory(TestGraph.PROBE_DIR)
	assert_object(second).is_not_same(first)


func test_compiled_graph_lives_and_dies_with_its_graph() -> void:
	var graph := _branchy_graph()
	FlowNodeIO.evaluate_graph(graph, {}, _ctx(), {}, 0)
	var compiled_ref : WeakRef = weakref(FlowCompiledGraph.for_graph(graph))
	# (assert_bool, not assert_object: an object assertion keeps its value alive)
	assert_bool(compiled_ref.get_ref() != null).is_true()
	graph = null
	assert_bool(compiled_ref.get_ref() == null).is_true()


func test_each_run_gets_fresh_elements_and_settings() -> void:
	var graph := _branchy_graph()
	var ev1 = FlowNodeIO.begin_evaluation(graph, {}, _ctx(), {}, 0)
	var ev2 = FlowNodeIO.begin_evaluation(graph, {}, _ctx(), {}, 0)
	for node_name in ev1._instances:
		assert_object(ev2._instances[node_name]).is_not_same(ev1._instances[node_name])
		assert_object(ev2._instances[node_name].settings).is_not_same(ev1._instances[node_name].settings)
	ev1.run_to_completion()
	ev2.run_to_completion()


func test_overrides_do_not_leak_into_later_runs() -> void:
	var graph := _branchy_graph()
	var plain := _summaries(FlowNodeIO.evaluate(graph))
	var overridden := _summaries(FlowNodeIO.evaluate(graph, {}, 0, {}, null, { "grid/x": 9 }))
	assert_dict(overridden).is_not_equal(plain)
	assert_dict(_summaries(FlowNodeIO.evaluate(graph))).is_equal(plain)


func test_binding_that_changes_the_order_orders_that_run_itself() -> void:
	# A $param binding disables a branch's filter: that run must not use the
	# compiled order (computed with the saved, enabled settings).
	var graph := _branchy_graph()
	for n_data in graph.data.nodes:
		if n_data.name == &"filter_1":
			n_data.settings["bindings"] = { "disabled": "$off" }
	var enabled := _summaries(FlowNodeIO.evaluate(graph))
	var disabled := _summaries(FlowNodeIO.evaluate(graph, {}, 0, { "off": true }))
	assert_dict(disabled).is_not_equal(enabled)
	assert_dict(_summaries(FlowNodeIO.evaluate(graph))).is_equal(enabled)


# --- modes ------------------------------------------------------------------------------

func test_synchronous_time_sliced_and_threaded_give_identical_outputs() -> void:
	var graph := _branchy_graph()
	var sync := _summaries(FlowNodeIO.evaluate_graph(graph, {}, _ctx(), {}, 0))
	var ev = FlowNodeIO.begin_evaluation(graph, {}, _ctx(), {}, 0)
	while not ev.step(0.0):
		pass
	var sliced := _summaries(ev.outputs)
	var pooled_before := FlowExecutor.pooled_element_count
	var threaded := _summaries(FlowNodeIO.evaluate_graph(graph, {}, _ctx({ FlowExecutor.THREADED_META: true }), {}, 0))
	assert_dict(sliced).is_equal(sync)
	assert_dict(threaded).is_equal(sync)
	# The four branches ran on the pool.
	assert_int(FlowExecutor.pooled_element_count - pooled_before).is_greater_equal(4)


func test_threaded_mode_keeps_error_order_and_variables() -> void:
	# Pure nodes that fail in independent branches, a main-thread node that
	# fails, and a variable written in one branch and read in another.
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 2, "y": 1, "z": 2})
	b.node("out", "output", {"name": "result"})
	b.node("merge", "merge")
	for i in range(4):
		var m := "bad_%d" % i
		b.node(m, "math_op", {"operation": 0, "in_nameA": "missing_%d" % i, "in_nameB": "1", "out_name": "x"})
		b.link("grid", 0, m, 0)
		b.link(m, 0, "merge", 0)
	b.node("get_missing", "get_variable", {"variable_name": "never_set"})
	b.link("get_missing", 0, "merge", 0)
	b.link("merge", 0, "out", 0)
	var graph : FlowGraphResource = b.build()
	FlowNodeIO.evaluate(graph)
	var sequential_errors := FlowNodeIO.last_errors.duplicate(true)
	var ctx := FlowNodeIO.make_context(null)
	ctx.set_meta(FlowExecutor.THREADED_META, true)
	FlowNodeIO.evaluate_collecting_errors(graph, {}, ctx)
	var threaded_errors := FlowNodeIO.last_errors.duplicate(true)
	assert_int(sequential_errors.size()).is_equal(5)
	assert_array(threaded_errors).is_equal(sequential_errors)
	# Variables written by a main-thread set_variable are read in order.
	var vgraph := _branchy_graph()
	var seq_var := _summaries(FlowNodeIO.evaluate_graph(vgraph, {}, _ctx(), {}, 0))
	var thr_var := _summaries(FlowNodeIO.evaluate_graph(vgraph, {}, _ctx({ FlowExecutor.THREADED_META: true }), {}, 0))
	assert_dict(thr_var["from_var"]).is_equal(seq_var["from_var"])


func test_threaded_mode_from_flow_graph_node_3d() -> void:
	var graph := _branchy_graph()
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	host.graph = graph
	add_child(host)
	var sequential := _summaries(host.generate())
	host.threaded = true
	var threaded := _summaries(host.generate())
	assert_dict(threaded).is_equal(sequential)
	remove_child(host)
	host.free()


# --- extension points ---------------------------------------------------------------------

func test_node_filter_skips_elements() -> void:
	var graph := _branchy_graph()
	var executor := FlowExecutor.new()
	executor.node_filter = func(element): return element.name != &"filter_2"
	assert_bool(executor.begin(graph, {}, _ctx(), {}, 0)).is_true()
	var skipped = executor.state["instances"][&"filter_2"]
	var outputs := executor.run()
	assert_array(skipped.generated_bulks).is_empty()
	var full : FlowData.Data = FlowNodeIO.evaluate_graph(graph, {}, _ctx(), {}, 0)["result"]
	# filter_2 kept 20 of the 40 merged points.
	assert_int(outputs["result"].size()).is_equal(full.size() - 20)


func test_preseeded_bulks_replace_execution() -> void:
	var graph := _branchy_graph()
	var seed_data := TestGraph.points([Vector3(1, 2, 3)])
	var executor := FlowExecutor.new()
	executor.preseeded = { &"grid": [[seed_data]] }
	assert_bool(executor.begin(graph, {}, _ctx(), {}, 0)).is_true()
	var grid_element = executor.state["instances"][&"grid"]
	var outputs := executor.run()
	assert_int(grid_element.generated_bulks.size()).is_equal(1)
	assert_object(grid_element.generated_bulks[0][0]).is_same(seed_data)
	# One point flows through the four branches (the filters keep it or not).
	assert_int(outputs["result"].size()).is_less_equal(4)


func test_preseeded_and_filter_work_in_threaded_mode() -> void:
	var graph := _branchy_graph()
	var executor := FlowExecutor.new()
	executor.mode = FlowExecutor.Mode.THREADED
	executor.preseeded = { &"grid": [[TestGraph.points([Vector3.ZERO, Vector3.ONE])]] }
	executor.node_filter = func(element): return element.name != &"attr_3"
	assert_bool(executor.begin(graph, {}, _ctx(), {}, 0)).is_true()
	var outputs := executor.run()
	var sequential := FlowExecutor.new()
	sequential.preseeded = executor.preseeded
	sequential.node_filter = executor.node_filter
	sequential.begin(graph, {}, _ctx(), {}, 0)
	assert_dict(_summaries(outputs)).is_equal(_summaries(sequential.run()))


func test_recursion_guard() -> void:
	var executor := FlowExecutor.new()
	assert_bool(executor.begin(_branchy_graph(), {}, _ctx(), {}, 21)).is_false()
	assert_dict(FlowNodeIO.evaluate_graph(_branchy_graph(), {}, _ctx(), {}, 21)).is_empty()
	assert_object(FlowNodeIO.begin_evaluation(_branchy_graph(), {}, _ctx(), {}, 21)).is_null()
