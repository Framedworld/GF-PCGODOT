# golden_graphs_test.gd
# Golden-output harness: evaluates every graph under GRAPH_DIRS / GRAPH_FILES
# (FlowGraphResource .tres files, and every FlowGraphNode3D inside .tscn
# scenes) and compares a per-node summary of every stream against
# baseline.json. See tests/golden/README.md.
#
#   Compare:     godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
#                    --ignoreHeadlessMode -a res://tests/golden
#   Regenerate:  FLOW_GOLDEN_UPDATE=1 <same command>
#   Other dirs:  FLOW_GOLDEN_GRAPH_DIRS="res://my_graphs,res://levels/forest.tscn"
#   Other file:  FLOW_GOLDEN_BASELINE="res://tests/golden/my_baseline.json"
#   Tolerance sidecar only (baseline.json untouched, must match exactly):
#                FLOW_GOLDEN_UPDATE_TOLERANCE=1 <same command>
#   Policy:      FLOW_GOLDEN_TOLERANCE=strict | noise (see golden_tolerance.gd)
class_name GoldenGraphsTest extends GdUnitTestSuite

## Directories scanned recursively (a game project vendoring this harness
## points these at its own graphs, or sets FLOW_GOLDEN_GRAPH_DIRS).
const GRAPH_DIRS : Array[String] = ["res://graphs", "res://demos"]
## Individual graph / scene files evaluated in addition to GRAPH_DIRS.
const GRAPH_FILES : Array[String] = ["res://graph00.tres", "res://graph02_curves.tres"]
const BASELINE_PATH := "res://tests/golden/baseline.json"
const BASELINE_FORMAT := 1

## GDExtension classes some stock nodes need (difference, self_pruning,
## distance, relax, sample_spline, point_neighborhood, sort, substract).
const NATIVE_CLASSES : Array[String] = ["GDKdTree", "GDRTree", "GDStreamUtils"]

## Maximum differences reported per graph (the first one is the earliest
## drifting node in node-name order; see the full list by regenerating into a
## scratch file with FLOW_GOLDEN_BASELINE and diffing).
const MAX_DIFFS_PER_GRAPH := 12

static var _cache : Dictionary = {}


# --- log capture ---------------------------------------------------------------

## Collects script errors and node errors (FlowNodeBase.setError pushes
## "Node.Err <node> : <message>") raised while a graph evaluates, so they can be
## recorded in the baseline instead of failing the test run.
class CaptureLogger extends Logger:
	var active := false
	var script_errors : Array = []
	var node_errors : Array = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if not active:
			return
		var message := rationale if not rationale.is_empty() else code
		if error_type == ERROR_TYPE_SCRIPT:
			script_errors.append(message)
		elif error_type == ERROR_TYPE_ERROR and message.begins_with("Node.Err "):
			node_errors.append(message.substr("Node.Err ".length()))

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func begin() -> void:
		script_errors = []
		node_errors = []
		active = true

	func end() -> Dictionary:
		active = false
		return { "script_errors": _unique_sorted(script_errors), "node_errors": _unique_sorted(node_errors) }

	static func _unique_sorted(items: Array) -> Array:
		var seen := {}
		for item in items:
			seen[str(item)] = true
		var result := seen.keys()
		result.sort()
		return result


# --- configuration -------------------------------------------------------------

static func is_update_mode() -> bool:
	return OS.get_environment("FLOW_GOLDEN_UPDATE") == "1"

## Regenerate only the tolerance sidecar (baseline_tolerance.json); refused
## unless this run matches baseline.json exactly.
static func is_tolerance_update_mode() -> bool:
	return OS.get_environment("FLOW_GOLDEN_UPDATE_TOLERANCE") == "1"

static func baseline_path() -> String:
	var env := OS.get_environment("FLOW_GOLDEN_BASELINE").strip_edges()
	return env if not env.is_empty() else BASELINE_PATH

static func configured_sources() -> Array:
	var env := OS.get_environment("FLOW_GOLDEN_GRAPH_DIRS").strip_edges()
	var sources := []
	if not env.is_empty():
		for part in env.replace(";", ",").split(",", false):
			sources.append(part.strip_edges())
		return sources
	sources.append_array(GRAPH_DIRS)
	sources.append_array(GRAPH_FILES)
	return sources

static func native_available() -> bool:
	for cls in NATIVE_CLASSES:
		if not ClassDB.class_exists(cls):
			return false
	return true


# --- discovery -----------------------------------------------------------------

static func discover_files() -> Array:
	var files := {}
	for source in configured_sources():
		if DirAccess.dir_exists_absolute(source):
			for f in _list_recursive(source):
				files[f] = true
		elif ResourceLoader.exists(source):
			files[source] = true
		else:
			push_warning("golden: graph source '%s' does not exist" % source)
	var result := files.keys()
	result.sort()
	return result

static func _list_recursive(dir_path: String) -> Array:
	var result := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	if dir.file_exists(".gdignore"):
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				result.append_array(_list_recursive(full))
		elif entry.get_extension() in ["tres", "res", "tscn", "scn"]:
			result.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return result

## Every node template used by `graph`, including nested subgraph/loop graphs.
static func collect_templates(graph: FlowGraphResource, into: Dictionary = {}, visited: Dictionary = {}) -> Dictionary:
	if graph == null or visited.has(graph.get_instance_id()):
		return into
	visited[graph.get_instance_id()] = true
	for n_data in graph.data.get("nodes", []):
		into[str(n_data.get("template", ""))] = true
		var settings = n_data.get("settings", {})
		if settings is Dictionary:
			var nested = settings.get("graph", null)
			if nested is FlowGraphResource:
				collect_templates(nested, into, visited)
	return into

## Returns "" when the graph can be evaluated here, else the skip reason.
static func skip_reason(graph: FlowGraphResource) -> String:
	var unknown := []
	var needs_native := []
	var native_ok := native_available()
	var templates := collect_templates(graph).keys()
	templates.sort()
	for template in templates:
		var script_path := FlowNodeRegistry.get_node_script_path(template)
		if script_path.is_empty():
			unknown.append(template)
			continue
		if not native_ok and _script_uses_native(script_path):
			needs_native.append(template)
	if not unknown.is_empty():
		return "unknown node templates (register their node directory first): %s" % ", ".join(unknown)
	if not needs_native.is_empty():
		return "native library (libflow GDExtension) not loaded; needed by: %s" % ", ".join(needs_native)
	return ""

static func _script_uses_native(script_path: String) -> bool:
	var text := FileAccess.get_file_as_string(script_path)
	for cls in NATIVE_CLASSES:
		if text.contains(cls):
			return true
	return false


# --- evaluation ----------------------------------------------------------------

## Evaluates every discovered graph once and returns { key: entry }.
func evaluate_all() -> Dictionary:
	var logger := CaptureLogger.new()
	OS.add_logger(logger)
	var entries := {}
	for path in discover_files():
		entries.merge(evaluate_source(self, path, logger), true)
	OS.remove_logger(logger)
	_clear_gdunit_script_errors()
	return entries

## Evaluates one discovered source file (a graph resource, or every
## FlowGraphNode3D of a scene, in tree order) under `parent` and returns
## { key: entry }. Shared with the seed-zero suite's platform-noise fallback.
static func evaluate_source(parent: Node, path: String, logger: CaptureLogger) -> Dictionary:
	var ext : String = path.get_extension()
	if ext == "tscn" or ext == "scn":
		return _evaluate_scene(parent, path, logger)
	var res = ResourceLoader.load(path)
	if res is FlowGraphResource:
		return { path: _evaluate_resource(parent, res, logger) }
	return {}

static func _evaluate_resource(parent: Node, graph: FlowGraphResource, logger: CaptureLogger) -> Dictionary:
	var reason := skip_reason(graph)
	if not reason.is_empty():
		return { "status": "skipped", "reason": reason }
	var owner := FlowGraphNode3D.new()
	owner.name = "GoldenOwner"
	parent.add_child(owner)
	var entry := _evaluate(graph, owner, {}, owner, logger)
	parent.remove_child(owner)
	owner.free()
	return entry

static func _evaluate_scene(parent: Node, path: String, logger: CaptureLogger) -> Dictionary:
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
	# Detach the graphs so entering the tree does not auto-generate.
	var graphs := {}
	for fn in flow_nodes:
		graphs[fn] = fn.graph
		fn.graph = null
	parent.add_child(root)
	for fn in flow_nodes:
		var key := "%s::%s" % [path, str(root.get_path_to(fn))]
		var graph : FlowGraphResource = graphs[fn]
		fn.graph = graph
		if graph == null:
			continue
		var reason := skip_reason(graph)
		if not reason.is_empty():
			entries[key] = { "status": "skipped", "reason": reason }
			continue
		entries[key] = _evaluate(graph, fn, fn.args if fn.args != null else {}, root, logger)
	parent.remove_child(root)
	root.free()
	return entries

static func _evaluate(graph: FlowGraphResource, owner: FlowGraphNode3D, inputs: Dictionary, count_root: Node, logger: CaptureLogger) -> Dictionary:
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = owner
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	var outputs := {}
	logger.begin()
	var nodes := FlowNodeIO.evaluate_graph_snapshot(graph, inputs, ctx, {}, 0, outputs)
	var logs := logger.end()
	var out_summary := {}
	for key in outputs:
		if outputs[key] is FlowData.Data:
			out_summary[str(key)] = FlowNodeIO.snapshot_summarize_data(outputs[key])
	return {
		"status": "ok",
		"outputs": out_summary,
		"spawned": _count_spawned(count_root),
		"nodes": nodes,
		"script_errors": logs.script_errors,
		"node_errors": logs.node_errors,
	}

static func _count_spawned(root: Node) -> int:
	var count := 0
	for n in root.find_children("*", "", true, false):
		if n.has_meta("flow_owner") and not n.is_queued_for_deletion():
			count += 1
	return count

## Script errors raised inside the evaluated graphs are recorded in the
## baseline (e.g. the disabled-node draw_debug bug); drop them from GdUnit's
## monitor so they do not abort the golden test itself.
static func _clear_gdunit_script_errors() -> void:
	var ctx = GdUnitThreadManager.get_current_context()
	if ctx == null:
		return
	var exec_ctx = ctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()

func _cached_run(slot: String) -> Dictionary:
	if not _cache.has(slot):
		_cache[slot] = _normalize(evaluate_all())
	return _cache[slot]


# --- baseline I/O and comparison ------------------------------------------------

## JSON round trip so in-memory results compare equal to a parsed baseline
## (ints become floats, StringNames become Strings, keys are sorted).
static func _normalize(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true))

func _build_baseline(entries: Dictionary) -> Dictionary:
	var skipped := {}
	for key in entries:
		if entries[key].get("status", "") == "skipped":
			skipped[key] = entries[key].get("reason", "")
	return {
		"format": BASELINE_FORMAT,
		"generated_with_native_library": native_available(),
		"float_quantum": FlowNodeIO.SNAPSHOT_FLOAT_QUANTUM,
		"sources": configured_sources(),
		"skipped": skipped,
		"graphs": entries,
	}

func _write_baseline(data: Dictionary) -> void:
	var path := baseline_path()
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_object(f).override_failure_message("golden: cannot write %s" % path).is_not_null()
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t", true) + "\n")
	f.close()
	print("golden: wrote %s (%d graphs, %d skipped)" % [path, data.graphs.size(), data.skipped.size()])

func _read_baseline() -> Variant:
	var path := baseline_path()
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Human-readable differences between two graph entries, earliest node first.
static func diff_entries(key: String, expected: Dictionary, actual: Dictionary) -> Array:
	var diffs := []
	if expected.get("status") != actual.get("status"):
		return ["%s: status %s -> %s" % [key, expected.get("status"), actual.get("status")]]
	if expected.get("spawned") != actual.get("spawned"):
		diffs.append("%s: spawned children %d -> %d" % [key, int(expected.get("spawned", -1)), int(actual.get("spawned", -1))])
	for field in ["script_errors", "node_errors"]:
		if expected.get(field, []) != actual.get(field, []):
			diffs.append("%s: %s %s -> %s" % [key, field, expected.get(field, []), actual.get(field, [])])
	_diff_named("%s: output" % key, expected.get("outputs", {}), actual.get("outputs", {}), diffs, false)
	_diff_named("%s: node" % key, expected.get("nodes", {}), actual.get("nodes", {}), diffs, true)
	return diffs

static func _diff_named(prefix: String, expected: Dictionary, actual: Dictionary, diffs: Array, is_nodes: bool) -> void:
	var names := {}
	for k in expected:
		names[k] = true
	for k in actual:
		names[k] = true
	var sorted := names.keys()
	sorted.sort()
	for name in sorted:
		if not expected.has(name):
			diffs.append("%s '%s' is new" % [prefix, name])
		elif not actual.has(name):
			diffs.append("%s '%s' disappeared" % [prefix, name])
		elif expected[name] != actual[name]:
			if is_nodes:
				diffs.append("%s '%s' %s" % [prefix, name, _describe_node_diff(expected[name], actual[name])])
			else:
				diffs.append("%s '%s' %s" % [prefix, name, _describe_data_diff(expected[name], actual[name])])

static func _describe_node_diff(expected: Array, actual: Array) -> String:
	if expected.size() != actual.size():
		return "bulk count %d -> %d" % [expected.size(), actual.size()]
	for b in range(expected.size()):
		if expected[b] == actual[b]:
			continue
		if expected[b].size() != actual[b].size():
			return "bulk %d port count %d -> %d" % [b, expected[b].size(), actual[b].size()]
		for p in range(expected[b].size()):
			if expected[b][p] != actual[b][p]:
				return "bulk %d port %d %s" % [b, p, _describe_data_diff(expected[b][p], actual[b][p])]
	return "changed"

static func _describe_data_diff(expected, actual) -> String:
	if expected == null or actual == null:
		return "%s -> %s" % [expected, actual]
	for field in ["size", "kind", "tags", "data_attrs"]:
		if expected.get(field) != actual.get(field):
			return "%s %s -> %s" % [field, expected.get(field), actual.get(field)]
	var exp_streams := {}
	for s in expected.get("streams", []):
		exp_streams[s.name] = s
	var act_streams := {}
	for s in actual.get("streams", []):
		act_streams[s.name] = s
	for name in exp_streams:
		if not act_streams.has(name):
			return "stream '%s' removed" % name
		if exp_streams[name] != act_streams[name]:
			var e = exp_streams[name]
			var a = act_streams[name]
			return "stream '%s' type %d->%d count %d->%d hash %s->%s" % [name, int(e.data_type), int(a.data_type), int(e.count), int(a.count), e.hash, a.hash]
	for name in act_streams:
		if not exp_streams.has(name):
			return "stream '%s' added" % name
	return "changed"


# --- tests -----------------------------------------------------------------------

func test_golden_graphs_match_baseline(timeout := 1800000) -> void:
	var entries := _cached_run("first")
	assert_int(entries.size()).override_failure_message("golden: no graphs discovered in %s" % [configured_sources()]).is_greater(0)
	if is_update_mode():
		_write_baseline(_build_baseline(entries))
		_write_tolerance_sidecar(entries)
		return
	var baseline = _read_baseline()
	assert_object(baseline).override_failure_message(
		"golden: %s missing or unreadable; run with FLOW_GOLDEN_UPDATE=1 to create it" % baseline_path()).is_not_null()
	if baseline == null:
		return
	var expected : Dictionary = baseline.get("graphs", {})
	var sidecar = GoldenTolerance.load_sidecar(GoldenTolerance.sidecar_path_for(baseline_path()))
	var failures := []
	var notes := []
	var noise := []
	var keys := {}
	for k in expected:
		keys[k] = true
	for k in entries:
		keys[k] = true
	var sorted := keys.keys()
	sorted.sort()
	for key in sorted:
		if not expected.has(key):
			failures.append("%s: not in baseline (new graph? regenerate with FLOW_GOLDEN_UPDATE=1)" % key)
			continue
		if not entries.has(key):
			failures.append("%s: in baseline but no longer discovered (removed? regenerate)" % key)
			continue
		var exp_entry : Dictionary = expected[key]
		var act_entry : Dictionary = entries[key]
		if act_entry.get("status") == "skipped" and exp_entry.get("status") == "ok":
			notes.append("SKIPPED %s: %s" % [key, act_entry.get("reason", "")])
			continue
		if act_entry.get("status") == "ok" and exp_entry.get("status") == "skipped":
			notes.append("UNVERIFIED %s: baseline was generated without it (%s); regenerate with the native library loaded" % [key, exp_entry.get("reason", "")])
			continue
		var result := GoldenTolerance.compare_entry(key, exp_entry, act_entry, sidecar, _raw_provider)
		var diffs : Array = result.failures
		if diffs.size() > MAX_DIFFS_PER_GRAPH:
			var more := diffs.size() - MAX_DIFFS_PER_GRAPH
			diffs = diffs.slice(0, MAX_DIFFS_PER_GRAPH)
			diffs.append("%s: ... and %d more differences" % [key, more])
		failures.append_array(diffs)
		noise.append_array(result.noise)
	for note in notes:
		print("golden: ", note)
	_clear_gdunit_script_errors()
	GoldenTolerance.print_noise("golden", noise)
	if is_tolerance_update_mode():
		assert_array(failures).override_failure_message(
			"golden: refusing to write the tolerance sidecar: this run does not match %s exactly:\n  %s"
			% [baseline_path(), "\n  ".join(PackedStringArray(failures))]).is_empty()
		assert_array(noise).override_failure_message("golden: refusing to write the tolerance sidecar from a PLATFORM_NOISE run").is_empty()
		if failures.is_empty() and noise.is_empty():
			# Bind every fingerprint to the hashes baseline.json already holds.
			_write_tolerance_sidecar(expected)
		return
	assert_array(failures).override_failure_message(
		"golden: %d difference(s) against %s (if intended, regenerate with FLOW_GOLDEN_UPDATE=1 and review the diff):\n  %s"
		% [failures.size(), baseline_path(), "\n  ".join(PackedStringArray(failures))]).is_empty()


## Re-evaluates one golden key and returns its raw float containers, for the
## tolerance comparison (GoldenTolerance.compare_entry).
func _raw_provider(key: String, addresses: Array) -> Dictionary:
	var captured := GoldenTolerance.capture(self, GoldenTolerance.source_of(key), { key: addresses })
	_clear_gdunit_script_errors()
	return captured.get(key, {})


func _write_tolerance_sidecar(entries: Dictionary) -> void:
	var errors := []
	var data := GoldenTolerance.build_sidecar(self, entries, errors)
	_clear_gdunit_script_errors()
	assert_array(errors).override_failure_message(
		"golden: tolerance sidecar not written; re-evaluation does not reproduce the recorded hashes:\n  %s"
		% "\n  ".join(PackedStringArray(errors.slice(0, 40)))).is_empty()
	if not errors.is_empty():
		return
	var path := GoldenTolerance.sidecar_path_for(baseline_path())
	assert_bool(GoldenTolerance.write_sidecar(path, data)).override_failure_message("golden: cannot write %s" % path).is_true()
	var count := 0
	for key in data.graphs:
		count += data.graphs[key].size()
	print("golden: wrote %s (%d float streams fingerprinted on %s)" % [path, count, data.platform])


func test_golden_graphs_are_deterministic(timeout := 1800000) -> void:
	# A second, independent evaluation (fresh owners and scene instances) must
	# produce exactly the same snapshot; otherwise the baseline cannot be stable.
	var first := _cached_run("first")
	var second := _cached_run("second")
	var failures := []
	for key in first:
		if not second.has(key):
			failures.append("%s: missing in second run" % key)
			continue
		var diffs := diff_entries(key, first[key], second[key])
		if not diffs.is_empty():
			failures.append_array(diffs.slice(0, MAX_DIFFS_PER_GRAPH))
	assert_array(failures).override_failure_message(
		"golden: non-deterministic graphs:\n  %s" % "\n  ".join(PackedStringArray(failures))).is_empty()


## The tolerance sidecar must describe this baseline: every fingerprint is
## bound to the exact hash baseline.json holds for that stream, and every float
## stream of every compared graph has one.
func test_tolerance_sidecar_matches_baseline() -> void:
	if is_update_mode() or is_tolerance_update_mode():
		return
	var baseline = _read_baseline()
	if baseline == null:
		return
	var sidecar = GoldenTolerance.load_sidecar(GoldenTolerance.sidecar_path_for(baseline_path()))
	assert_object(sidecar).override_failure_message(
		"golden: %s missing; run with FLOW_GOLDEN_UPDATE_TOLERANCE=1 to create it" % GoldenTolerance.sidecar_path_for(baseline_path())).is_not_null()
	if sidecar == null:
		return
	assert_int(int(sidecar.get("format", 0))).is_equal(GoldenTolerance.FORMAT)
	assert_float(float(sidecar.get("quantum", 0.0))).is_equal(GoldenTolerance.QUANTUM)
	assert_str(str(sidecar.get("platform", ""))).is_not_empty()
	var stale := []
	var fingerprinted := 0
	for key in sidecar.get("graphs", {}):
		var entry = baseline.get("graphs", {}).get(key, null)
		if not (entry is Dictionary) or entry.get("status") != "ok":
			stale.append("%s: not an evaluated graph in the baseline" % key)
			continue
		var fps : Dictionary = sidecar.graphs[key]
		for address in fps:
			fingerprinted += 1
			var expected_hash := GoldenTolerance.summary_hash(entry, address)
			if expected_hash != str(fps[address].get("e", "")):
				stale.append("%s: fingerprint for hash %s, baseline has %s" % [GoldenTolerance.describe_address(key, address), fps[address].get("e", ""), expected_hash])
	for key in baseline.get("graphs", {}):
		if baseline.graphs[key].get("status") == "ok" and not sidecar.get("graphs", {}).has(key):
			stale.append("%s: no fingerprints" % key)
	assert_int(fingerprinted).is_greater(100)
	assert_array(stale).override_failure_message(
		"golden: tolerance sidecar is stale (regenerate with FLOW_GOLDEN_UPDATE_TOLERANCE=1):\n  %s"
		% "\n  ".join(PackedStringArray(stale.slice(0, 40)))).is_empty()


func test_baseline_records_native_library_state() -> void:
	if is_update_mode():
		return
	var baseline = _read_baseline()
	if baseline == null:
		return
	assert_int(int(baseline.get("format", 0))).is_equal(BASELINE_FORMAT)
	if not native_available():
		print("golden: native library not loaded; graphs needing it are skipped (baseline generated_with_native_library=%s)" % baseline.get("generated_with_native_library"))
