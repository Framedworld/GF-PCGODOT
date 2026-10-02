# r1_executor_review_test.gd
# Adversarial review (WP13 R1) of the executor and evaluator: FlowExecutor,
# FlowCompiledGraph, FlowOutputCache, FlowNodeTraits, the FlowGraphNode3D
# lifecycle and the element/widget split. Each test pins one failure
# hypothesis; see docs/_round2/WP13-R1.md.
class_name R1ExecutorReviewTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")


func before_test() -> void:
	FlowOutputCache.clear()


func after_test() -> void:
	FlowOutputCache.clear()


static func _summaries(outputs: Dictionary) -> Dictionary:
	var result := {}
	for key in outputs:
		result[str(key)] = FlowNodeIO.snapshot_summarize_data(outputs[key])
	return JSON.parse_string(JSON.stringify(result, "", true))


func _random_graph(x := 3) -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": x, "y": 1, "z": 2, "random_seed": 5}) \
		.node("noise", "attribute_noise", {"target_attribute": "density", "random_seed": 9}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "noise", 0) \
		.link("noise", 0, "out", 0) \
		.build()


# --- FlowCompiledGraph invalidation -------------------------------------------------

# A subgraph edited in place while the parent's compiled graph stays cached.
func test_nested_subgraph_in_place_edit_reaches_the_parent() -> void:
	var inner := _random_graph(2)
	var outer : FlowGraphResource = TestGraph.new() \
		.node("sub", "subgraph", {"graph": inner}) \
		.node("out", "output", {"name": "final"}) \
		.link("sub", 0, "out", 0) \
		.build()
	var first : FlowData.Data = FlowNodeIO.evaluate(outer)["final"]
	assert_int(first.size()).is_equal(4)
	for n_data in inner.data.nodes:
		if n_data.name == &"grid":
			n_data.settings["x"] = 5
	var second : FlowData.Data = FlowNodeIO.evaluate(outer)["final"]
	assert_int(second.size()).is_equal(10)


# --- threaded mode ---------------------------------------------------------------------------

# Nested threaded evaluations: three main-thread loops whose bodies have
# independent failing pure branches (each loop iteration runs its own pool
# batch from the main thread), next to failing pure branches of the outer
# graph. Output and the order of last_errors equal the sequential run, every
# time, with and without the output cache.
func test_nested_threaded_loops_keep_outputs_and_error_order() -> void:
	var body_builder = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("merge", "merge") \
		.node("out", "output", {"name": "result"})
	for i in range(3):
		var bad := "bad_%d" % i
		var ok := "ok_%d" % i
		body_builder.node(bad, "math_op", {"operation": 0, "in_nameA": "missing_%d" % i, "in_nameB": "1", "out_name": "x"})
		body_builder.node(ok, "attribute_noise", {"target_attribute": "density", "random_seed": 20 + i})
		body_builder.link("in_item", 0, bad, 0)
		body_builder.link("in_item", 0, ok, 0)
		body_builder.link(bad, 0, "merge", 0)
		body_builder.link(ok, 0, "merge", 0)
	body_builder.link("merge", 0, "out", 0)
	var body : FlowGraphResource = body_builder.build()
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 2, "y": 1, "z": 2, "random_seed": 4})
	b.node("merge", "merge")
	b.node("out", "output", {"name": "result"})
	for i in range(3):
		var loop := "loop_%d" % i
		var bad := "outer_bad_%d" % i
		b.node(loop, "loop", {"graph": body, "item_input_name": "item", "output_attribute_name": "result"})
		b.node(bad, "math_op", {"operation": 0, "in_nameA": "nope_%d" % i, "in_nameB": "1", "out_name": "x"})
		b.link("grid", 0, loop, 0)
		b.link("grid", 0, bad, 0)
		b.link(loop, 0, "merge", 0)
		b.link(bad, 0, "merge", 0)
	b.link("merge", 0, "out", 0)
	var graph : FlowGraphResource = b.build()
	var seq_out := _summaries(FlowNodeIO.evaluate(graph, {}, 3))
	var seq_errors := FlowNodeIO.last_errors.duplicate(true)
	assert_int(seq_errors.size()).is_greater(30)
	for options in [{ FlowExecutor.THREADED_META: true }, { FlowExecutor.THREADED_META: true, FlowExecutor.OUTPUT_CACHE_META: true }]:
		for run in range(4):
			var ctx := FlowNodeIO.make_context(null, 3)
			for k in options:
				ctx.set_meta(k, options[k])
			var result := FlowNodeIO.evaluate_collecting_errors(graph, {}, ctx)
			assert_dict(_summaries(result.outputs)).is_equal(seq_out)
			assert_array(result.errors).is_equal(seq_errors)


# Threaded mode runs elements known to log outside setError one at a time
# (FlowNodeTraits.LOGGING_TEMPLATES, WP11 item 5), because Godot calls script
# Loggers on the raising thread. The list came from what the conformance
# fixtures happened to trigger; a threadable stock node whose own script calls
# push_warning / push_error must be on it too.
func test_threadable_templates_that_push_warnings_are_serialized() -> void:
	var missing := []
	for template in FlowNodeTraits.TABLE:
		var row : Array = FlowNodeTraits.TABLE[template]
		if row[0]:
			continue   # main thread anyway
		var script_path := FlowNodeRegistry.get_node_script_path(template)
		if script_path.is_empty():
			continue
		var source := FileAccess.get_file_as_string(script_path)
		var previous := ""
		var logs := false
		for raw_line in source.split("\n"):
			var line : String = raw_line.strip_edges()
			if line.begins_with("#"):
				continue
			var hash_at := line.find("#")
			if hash_at >= 0 and line.count("\"", 0, hash_at) % 2 == 0:
				line = line.substr(0, hash_at).strip_edges()
			if (line.contains("push_warning(") or line.contains("push_error(")) \
					and not line.contains("settings.trace") and not previous.contains("settings.trace"):
				logs = true
				break
			if not line.is_empty():
				previous = line
		if logs and not FlowNodeTraits.LOGGING_TEMPLATES.has(template):
			missing.append(template)
	missing.sort()
	assert_array(missing).override_failure_message("threadable templates that push warnings but run concurrently: %s" % [missing]).is_empty()


# --- lifecycle ---------------------------------------------------------------------------

func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))

# Repeated evaluations in every mode must not grow the ObjectDB.
func test_repeated_evaluations_do_not_grow_the_object_db() -> void:
	var inner := _random_graph(2)
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 3, "y": 1, "z": 3, "random_seed": 3})
	b.node("sub", "subgraph", {"graph": inner})
	b.node("merge", "merge")
	b.node("set", "set_variable", {"variable_name": "v"})
	b.node("get", "get_variable", {"variable_name": "v"})
	b.node("out", "output", {"name": "result"})
	b.link("grid", 0, "set", 0)
	b.link("get", 0, "merge", 0)
	b.link("sub", 0, "merge", 0)
	b.link("merge", 0, "out", 0)
	var graph : FlowGraphResource = b.build()
	var modes := [
		{},
		{ FlowExecutor.THREADED_META: true },
		{ FlowExecutor.OUTPUT_CACHE_META: true },
	]
	for options in modes:
		# Warm up (compiled graph, traits and cache entries are created once).
		for i in range(5):
			var ctx := FlowNodeIO.make_context(null)
			for k in options:
				ctx.set_meta(k, options[k])
			FlowNodeIO.evaluate_collecting_errors(graph, {}, ctx)
		var before := _object_count()
		for i in range(200):
			var ctx := FlowNodeIO.make_context(null)
			for k in options:
				ctx.set_meta(k, options[k])
			FlowNodeIO.evaluate_collecting_errors(graph, {}, ctx)
		assert_int(_object_count() - before).override_failure_message(
			"ObjectDB grew by %d over 200 evaluations with %s" % [_object_count() - before, options]).is_less_equal(2)
	# Time-sliced.
	for i in range(3):
		FlowNodeIO.begin_evaluation(graph, {}, FlowNodeIO.make_context(null), {}, 0).run_to_completion()
	var before_sliced := _object_count()
	for i in range(200):
		var ev = FlowNodeIO.begin_evaluation(graph, {}, FlowNodeIO.make_context(null), {}, 0)
		while not ev.step(0.0):
			pass
	assert_int(_object_count() - before_sliced).is_less_equal(2)


# generate() called again from a `generated` handler.
func test_generate_reentrant_from_generated_signal() -> void:
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	host.graph = _random_graph()
	add_child(host)
	var calls := [0]
	var handler := func(_outputs):
		calls[0] += 1
		if calls[0] == 1:
			host.generate()
	host.generated.connect(handler)
	var outputs := host.generate()
	assert_int(calls[0]).is_equal(2)
	assert_bool(host.is_generating()).is_false()
	assert_int(outputs["result"].size()).is_equal(6)
	assert_int(host.last_outputs["result"].size()).is_equal(6)
	host.generated.disconnect(handler)
	remove_child(host)
	host.free()


func _spawning_host() -> FlowGraphNode3D:
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	host.graph = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 2}) \
		.node("target", "create_target_node", {"node_name": "Spawned"}) \
		.node("noise", "attribute_noise", {"target_attribute": "density", "random_seed": 9}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "target", 0) \
		.link("target", 0, "noise", 0) \
		.link("noise", 0, "out", 0) \
		.build()
	host.frame_budget_ms = 0.0
	return host

# A component that leaves the tree in the middle of an async generation must
# not run its spawners while leaving: content added to a node from its
# _exit_tree() enters the tree and is never told it left, so it stays
# "inside" a tree its parent is no longer in. The run is suspended and
# resumes when the component is back in the tree.
func test_async_generation_does_not_spawn_while_leaving_the_tree() -> void:
	var host := _spawning_host()
	add_child(host)
	host.generate_async()
	host._async_eval.step(0.0)   # grid only; create_target_node not run yet
	assert_bool(host.is_generating()).is_true()
	var emitted := [0]
	host.generated.connect(func(_o): emitted[0] += 1)
	remove_child(host)
	assert_bool(host.is_inside_tree()).is_false()
	for child in host.find_children("*", "", true, false):
		assert_bool(child.is_inside_tree()).override_failure_message("%s still inside the tree" % child.name).is_false()
	# Back in the tree, the run finishes from _process and emits generated.
	add_child(host)
	for i in range(20):
		if not host.is_generating():
			break
		await get_tree().process_frame
	assert_bool(host.is_generating()).is_false()
	assert_int(emitted[0]).is_equal(1)
	assert_int(host.last_outputs["result"].size()).is_equal(4)
	var spawned := host.find_children("Spawned*", "", false, false)
	assert_int(spawned.size()).is_equal(1)
	assert_bool(spawned[0].is_inside_tree()).is_true()
	remove_child(host)
	host.free()


# Freeing a component mid-run releases the evaluation's elements.
func test_async_generation_released_when_component_is_freed() -> void:
	var host := _spawning_host()
	add_child(host)
	host.generate_async()
	host._async_eval.step(0.0)
	var refs := []
	for element in host._async_eval._instances.values():
		refs.append(weakref(element))
	assert_int(refs.size()).is_equal(4)
	host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(is_instance_valid(host)).is_false()
	for ref in refs:
		assert_object(ref.get_ref()).is_null()


# --- bindings and overrides ----------------------------------------------------------------

class ErrorCapture extends Logger:
	var messages : Array = []
	var _lock := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		_lock.lock()
		messages.append(rationale if not rationale.is_empty() else code)
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func matching(text: String) -> Array:
		_lock.lock()
		var found := messages.filter(func(m): return str(m).contains(text))
		_lock.unlock()
		return found


# A context with overrides but without the override-hit bookkeeping (the
# editor dock's preview context, or a hand-built one) must apply overrides
# without an engine error.
func test_overrides_apply_on_a_context_without_hit_bookkeeping() -> void:
	var element : FlowNodeBase = load("res://addons/flow_nodes_editor/nodes/grid.gd").new()
	element.name = &"grid"
	element.node_template = "grid"
	element.settings = element.getMeta().settings.new()
	var ctx := FlowData.EvaluationContext.new()
	ctx.overrides = { "grid/x": 7 }
	var capture := ErrorCapture.new()
	OS.add_logger(capture)
	var authored = FlowNodeIO.begin_scratch_setting_bindings(element, FlowGraphResource.new(), ctx)
	OS.remove_logger(capture)
	assert_object(authored).is_not_null()
	assert_int(int(element.settings.x)).is_equal(7)
	assert_array(capture.matching("flow_override_hits")).is_empty()
	FlowNodeIO.end_scratch_setting_bindings(element, authored)


# --- public API (docs/RUNTIME_API_P0.md, WP1 requirement 9) ---------------------------------

static func _signature(script: Script, method_name: String) -> Array:
	for m in script.get_script_method_list():
		if m.name == method_name:
			var args := []
			for a in m.args:
				args.append(a.name)
			return [args, m.default_args.size()]
	return []

func test_public_runtime_api_signatures_are_unchanged() -> void:
	var io : Script = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	var comp : Script = load("res://addons/flow_nodes_editor/flow_node.gd")
	var expected := {
		"evaluate_graph": [["graph", "input_data_map", "parent_ctx", "runtime_params", "depth"], 2],
		"begin_evaluation": [["graph", "input_data_map", "parent_ctx", "runtime_params", "depth"], 2],
		"evaluate_graph_snapshot": [["graph", "input_data_map", "parent_ctx", "runtime_params", "depth", "outputs_out"], 3],
		"make_context": [["owner", "seed", "params", "overrides"], 4],
		"evaluate": [["graph", "inputs", "seed", "params", "owner", "overrides"], 5],
	}
	for method_name in expected:
		assert_array(_signature(io, method_name)).override_failure_message("FlowNodeIO.%s changed" % method_name).is_equal(expected[method_name])
	var comp_expected := {
		"generate": [["inputs", "extra_params"], 2],
		"generate_async": [["inputs", "extra_params"], 2],
		"regenerate": [["inputs", "extra_params"], 2],
		"cleanup": [[], 0],
		"is_generating": [[], 0],
		"execute": [[], 0],
	}
	for method_name in comp_expected:
		assert_array(_signature(comp, method_name)).override_failure_message("FlowGraphNode3D.%s changed" % method_name).is_equal(comp_expected[method_name])
	var ev = FlowNodeIO.begin_evaluation(_random_graph(), {}, FlowNodeIO.make_context(null), {}, 0)
	for method_name in ["step", "run_to_completion", "is_done", "progress", "node_count"]:
		assert_bool(ev.has_method(method_name)).is_true()
	assert_bool("outputs" in ev).is_true()
	ev.run_to_completion()
	assert_int(ev.outputs["result"].size()).is_equal(6)


# --- widget delegation ----------------------------------------------------------------------

# The widget forwards unknown members to its element through _get/_set. Godot
# calls a script's _get/_set before the built-in properties, so `script`
# (which every Object has) must not be forwarded: reading it must give the
# widget's own script, and a duplicate of the widget must still be a widget.
func test_widget_does_not_forward_its_script_property() -> void:
	var widget := FlowNodeWidget.new()
	var element : FlowNodeBase = load("res://addons/flow_nodes_editor/nodes/grid.gd").new()
	element.node_template = "grid"
	element.settings = element.getMeta().settings.new()
	widget.element = element
	assert_object(widget.get("script")).is_same(widget.get_script())
	assert_object(element.get_script()).is_not_same(widget.get_script())
	var copy = widget.duplicate()
	assert_object(copy).is_not_null()
	assert_bool(copy is FlowNodeWidget).is_true()
	assert_str(element.get_script().resource_path).is_equal("res://addons/flow_nodes_editor/nodes/grid.gd")
	if copy != null:
		copy.free()
	widget.free()
