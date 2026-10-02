# executor_modes_golden_test.gd
# The golden set (tests/golden/baseline.json) evaluated with the optional
# executor modes: threaded (FlowGraphNode3D.threaded) and the output cache
# (FlowGraphNode3D.output_cache). Every per-node stream hash, output, spawn
# count and node error must equal the sequential, uncached baseline.
class_name ExecutorModesGoldenTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const BASELINE_PATH := "res://tests/golden/baseline.json"


## GoldenGraphsTest.CaptureLogger made thread-safe: in threaded mode Godot
## calls loggers from worker threads too (engine warnings raised inside node
## code), so this capture serializes its arrays.
class ThreadSafeCaptureLogger extends GoldenGraphsTest.CaptureLogger:
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		super._log_error(function, file, line, code, rationale, editor_notify, error_type, script_backtraces)
		_mutex.unlock()


func _baseline() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	return parsed.get("graphs", {}) if parsed is Dictionary else {}


## Evaluates every golden graph like GoldenGraphsTest does, with `options`
## (EvaluationContext meta) set on the root context. Returns { key: entry }.
func _evaluate_all(options: Dictionary) -> Dictionary:
	var logger := ThreadSafeCaptureLogger.new()
	OS.add_logger(logger)
	var entries := {}
	for path in GoldenGraphsTest.discover_files():
		var ext : String = path.get_extension()
		if ext == "tscn" or ext == "scn":
			entries.merge(_evaluate_scene(path, logger, options), true)
		else:
			var res = ResourceLoader.load(path)
			if res is FlowGraphResource:
				entries[path] = _evaluate_resource(res, logger, options)
	OS.remove_logger(logger)
	_clear_gdunit_script_errors()
	return GoldenGraphsTest._normalize(entries)

func _evaluate_resource(graph: FlowGraphResource, logger, options: Dictionary) -> Dictionary:
	var reason := GoldenGraphsTest.skip_reason(graph)
	if not reason.is_empty():
		return { "status": "skipped", "reason": reason }
	var owner := FlowGraphNode3D.new()
	owner.name = "GoldenOwner"
	add_child(owner)
	var entry := _evaluate(graph, owner, {}, owner, logger, options)
	remove_child(owner)
	owner.free()
	return entry

func _evaluate_scene(path: String, logger, options: Dictionary) -> Dictionary:
	var entries := {}
	var packed = ResourceLoader.load(path)
	if not (packed is PackedScene):
		return entries
	var root : Node = packed.instantiate()
	var flow_nodes := []
	if root is FlowGraphNode3D:
		flow_nodes.append(root)
	for n in root.find_children("*", "", true, false):
		if n is FlowGraphNode3D:
			flow_nodes.append(n)
	if flow_nodes.is_empty():
		root.free()
		return entries
	var graphs := {}
	for fn in flow_nodes:
		graphs[fn] = fn.graph
		fn.graph = null
	add_child(root)
	for fn in flow_nodes:
		var key := "%s::%s" % [path, str(root.get_path_to(fn))]
		var graph : FlowGraphResource = graphs[fn]
		fn.graph = graph
		if graph == null:
			continue
		var reason := GoldenGraphsTest.skip_reason(graph)
		if not reason.is_empty():
			entries[key] = { "status": "skipped", "reason": reason }
			continue
		entries[key] = _evaluate(graph, fn, fn.args if fn.args != null else {}, root, logger, options)
	remove_child(root)
	root.free()
	return entries

func _evaluate(graph: FlowGraphResource, owner: FlowGraphNode3D, inputs: Dictionary, count_root: Node, logger, options: Dictionary) -> Dictionary:
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = owner
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	for option in options:
		ctx.set_meta(option, options[option])
	var outputs := {}
	logger.begin()
	var nodes := FlowNodeIO.evaluate_graph_snapshot(graph, inputs, ctx, {}, 0, outputs)
	var logs : Dictionary = logger.end()
	var out_summary := {}
	for key in outputs:
		if outputs[key] is FlowData.Data:
			out_summary[str(key)] = FlowNodeIO.snapshot_summarize_data(outputs[key])
	return {
		"status": "ok",
		"outputs": out_summary,
		"spawned": GoldenGraphsTest._count_spawned(count_root),
		"nodes": nodes,
		"script_errors": logs.script_errors,
		"node_errors": logs.node_errors,
	}

func _clear_gdunit_script_errors() -> void:
	var tctx = GdUnitThreadManager.get_current_context()
	if tctx == null:
		return
	var exec_ctx = tctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()

func _diff_against_baseline(entries: Dictionary) -> Array:
	var expected := _baseline()
	var failures := []
	var compared := 0
	for key in expected:
		var exp_entry : Dictionary = expected[key]
		if exp_entry.get("status") != "ok":
			continue
		if not entries.has(key):
			failures.append("%s: not evaluated" % key)
			continue
		if entries[key].get("status") != "ok":
			continue
		compared += 1
		failures.append_array(GoldenGraphsTest.diff_entries(key, exp_entry, entries[key]).slice(0, 8))
	if compared < 40:
		failures.append("only %d graphs compared" % compared)
	return failures


# --- tests -------------------------------------------------------------------------

func test_threaded_mode_matches_golden_baseline(timeout := 1800000) -> void:
	var entries := _evaluate_all({ FlowExecutor.THREADED_META: true })
	var failures := _diff_against_baseline(entries)
	assert_array(failures).override_failure_message("threaded vs golden:\n  " + "\n  ".join(PackedStringArray(failures))).is_empty()


func test_output_cache_matches_golden_baseline_cold_and_warm(timeout := 1800000) -> void:
	FlowOutputCache.clear()
	var cold := _evaluate_all({ FlowExecutor.OUTPUT_CACHE_META: true })
	var cold_failures := _diff_against_baseline(cold)
	assert_array(cold_failures).override_failure_message("cache (cold) vs golden:\n  " + "\n  ".join(PackedStringArray(cold_failures))).is_empty()
	var misses_after_cold := FlowOutputCache.misses
	assert_int(misses_after_cold).is_greater(0)
	var warm := _evaluate_all({ FlowExecutor.OUTPUT_CACHE_META: true })
	var warm_failures := _diff_against_baseline(warm)
	assert_array(warm_failures).override_failure_message("cache (warm) vs golden:\n  " + "\n  ".join(PackedStringArray(warm_failures))).is_empty()
	# The second pass over unchanged graphs hits the cache.
	assert_int(FlowOutputCache.hits).is_greater(0)
	FlowOutputCache.clear()


func test_threaded_with_output_cache_matches_golden_baseline(timeout := 1800000) -> void:
	FlowOutputCache.clear()
	var options := { FlowExecutor.THREADED_META: true, FlowExecutor.OUTPUT_CACHE_META: true }
	var first := _evaluate_all(options)
	var second := _evaluate_all(options)
	var failures := _diff_against_baseline(first)
	failures.append_array(_diff_against_baseline(second))
	assert_array(failures).override_failure_message("threaded + cache vs golden:\n  " + "\n  ".join(PackedStringArray(failures))).is_empty()
	FlowOutputCache.clear()
