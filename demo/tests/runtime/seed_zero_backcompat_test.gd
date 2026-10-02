# seed_zero_backcompat_test.gd
#
# Back-compat guard for the P0 runtime API (docs/RUNTIME_API_P0.md): with
# seed == 0, no overrides and no new calls, every shipped graph must produce
# byte-identical output.
#
# seed_zero_baseline.json was generated on the commit *before* the runtime API
# landed, by running this suite with FLOW_WRITE_SEED0_BASELINE=1. Baseline mode
# uses only the legacy calling convention (hand-built EvaluationContext fed to
# the evaluator), which exists on both sides of the change. Compare mode then
# checks the legacy path (every node's bulks, the outputs and the generated
# scene content), FlowNodeIO.evaluate() and FlowGraphNode3D.generate()
# (outputs and generated scene content) against the same hashes.
#
# Two sets are covered:
#   - every FlowGraphResource under res://graphs, res://demos and the project
#     root, evaluated against a bare owner;
#   - every demo scene under res://demos, instantiated in the tree (so scan,
#     ray-cast and physics nodes see real scene content) with previously saved
#     generated content stripped first.
#
# The hashes are byte-exact, so they only reproduce on the platform that
# generated them (Linux x86_64). Elsewhere a mismatch passes as PLATFORM_NOISE,
# with a printed warning, only if every entry point still agrees bit for bit
# with the legacy path in the same process and the golden harness's tolerance
# comparison accepts the same graphs (see _judge() and
# tests/golden/golden_tolerance.gd). FLOW_GOLDEN_TOLERANCE=strict|noise
# overrides the platform rule.
class_name SeedZeroBackcompatTest extends GdUnitTestSuite

const Hasher = preload("res://tests/runtime/graph_output_hasher.gd")
const BASELINE_PATH := "res://tests/runtime/seed_zero_baseline.json"
const FLOW_NODES_IO_PATH := "res://addons/flow_nodes_editor/flow_nodes_io.gd"

const MODE_LEGACY := "legacy evaluate_graph"
const MODE_EVALUATE := "FlowNodeIO.evaluate"
const MODE_GENERATE := "FlowGraphNode3D.generate"


func _available_modes() -> Array:
	var modes := [MODE_LEGACY]
	for method in (load(FLOW_NODES_IO_PATH) as Script).get_script_method_list():
		if method.name == "evaluate":
			modes.append(MODE_EVALUATE)
			break
	var probe := FlowGraphNode3D.new()
	if probe.has_method("generate"):
		modes.append(MODE_GENERATE)
	probe.free()
	return modes


# Evaluate `graph` for `flow_node` through one of the three entry points.
# Returns { "outputs": Dictionary, "nodes": String }; "nodes" (the hash of every
# node's generated bulks) is only observable on the legacy path.
func _run(mode : String, flow_node : FlowGraphNode3D, graph : FlowGraphResource, args : Dictionary) -> Dictionary:
	match mode:
		MODE_LEGACY:
			# The pre-runtime-API convention every game used.
			var ctx = FlowData.EvaluationContext.new()
			ctx.owner = flow_node
			ctx.eval_id = 0
			ctx.gedit_nodes_by_name = {}
			ctx.runtime_params = {}
			var res := Hasher.evaluate_with_node_hashes(graph, args.duplicate(), ctx)
			return { "outputs": res.outputs, "nodes": res.nodes.hex_encode() }
		MODE_EVALUATE:
			var outputs = (load(FLOW_NODES_IO_PATH) as Script).call("evaluate", graph, args.duplicate(), 0, {}, flow_node)
			return { "outputs": outputs, "nodes": "" }
		MODE_GENERATE:
			flow_node.graph = graph
			flow_node.args = args.duplicate()
			flow_node.set("seed", 0)
			return { "outputs": flow_node.call("generate"), "nodes": "" }
	return { "outputs": {}, "nodes": "" }


# Returns { "result": "<outputs>:<generated>", "nodes": "<per-node hash>" }.
func _hash_graph_resource(mode : String, graph : FlowGraphResource) -> Dictionary:
	var owner_node := FlowGraphNode3D.new()
	owner_node.graph = null
	add_child(owner_node)
	var run := _run(mode, owner_node, graph, {})
	var result := Hasher.combine(Hasher.hash_outputs(run.outputs), Hasher.hash_generated(owner_node))
	remove_child(owner_node)
	owner_node.free()
	return { "result": result, "nodes": run.nodes }


func _hash_scene(mode : String, scene_path : String) -> Dictionary:
	var scene : Node = (load(scene_path) as PackedScene).instantiate()
	Hasher.strip_generated(scene)
	var flow_nodes := Hasher.find_flow_nodes(scene)
	var graphs := []
	var args := []
	for flow_node in flow_nodes:
		graphs.append(flow_node.graph)
		args.append(flow_node.args.duplicate() if flow_node.args else {})
		# Suppress generate-on-ready so every mode drives generation itself.
		flow_node.graph = null
	add_child(scene)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var output_hashes := PackedStringArray()
	var node_hashes := PackedStringArray()
	for i in range(flow_nodes.size()):
		if graphs[i] == null:
			continue
		var run := _run(mode, flow_nodes[i], graphs[i], args[i])
		output_hashes.append(Hasher.hash_outputs(run.outputs).hex_encode())
		node_hashes.append(run.nodes)
	var result := "%s:%s" % [",".join(output_hashes), Hasher.hash_generated(scene).hex_encode()]
	remove_child(scene)
	scene.free()
	return { "result": result, "nodes": ",".join(node_hashes) }


func _write_baseline() -> void:
	var baseline := {}
	var graphs := Hasher.collect_graph_resources()
	for key in graphs:
		var first := _hash_graph_resource(MODE_LEGACY, graphs[key])
		var second := _hash_graph_resource(MODE_LEGACY, graphs[key])
		# Output that is not reproducible within one process cannot be pinned;
		# record it so the comparison skips it explicitly.
		baseline[key] = first if first == second else "unstable"
	for scene_path in Hasher.collect_demo_scenes():
		var first : Dictionary = await _hash_scene(MODE_LEGACY, scene_path)
		var second : Dictionary = await _hash_scene(MODE_LEGACY, scene_path)
		baseline[scene_path] = first if first == second else "unstable"
	var file := FileAccess.open(ProjectSettings.globalize_path(BASELINE_PATH), FileAccess.WRITE)
	file.store_string(JSON.stringify(baseline, "\t", true) + "\n")
	file.close()


func _load_baseline() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	return parsed if parsed is Dictionary else {}


# The legacy path must match both the per-node and the result hash; the new
# entry points expose only outputs and generated content, so they match the
# result hash.
func _matches(mode : String, got : Dictionary, expected : Dictionary) -> bool:
	if got.result != expected.result:
		return false
	return mode != MODE_LEGACY or got.nodes == expected.nodes


## Per-key verdict over every mode's hashes. Returns failure lines (empty =
## pass). The byte-exact hashes are the check on the platform that generated
## the baseline. Elsewhere (libm and compiler differences change the last bits
## of sin/cos/atan2 results) a mismatch is accepted as PLATFORM_NOISE, with a
## printed warning, only when
##   (a) every entry point agrees bit for bit with the legacy path in this
##       process (the back-compat property the suite exists for), and
##   (b) the golden harness's tolerance comparison accepts every golden graph
##       of the same source (per-node streams within the float noise budget,
##       see tests/golden/golden_tolerance.gd).
func _judge(key : String, got_by_mode : Dictionary, expected : Dictionary) -> Array:
	var lines := []
	for mode in got_by_mode:
		if not _matches(mode, got_by_mode[mode], expected):
			lines.append("%s [%s]: %s" % [key, mode, _describe_mismatch(mode, got_by_mode[mode], expected)])
	if lines.is_empty():
		return lines
	var sidecar = GoldenTolerance.load_sidecar()
	if not GoldenTolerance.noise_allowed(sidecar):
		lines.append("%s: byte-exact hashes are required on %s (the baseline's platform; %s=noise to allow the tolerance fallback)" % [key, GoldenTolerance.platform_id(), GoldenTolerance.ENV_POLICY])
		return lines
	var legacy : Dictionary = got_by_mode.get(MODE_LEGACY, {})
	for mode in got_by_mode:
		if got_by_mode[mode].result != legacy.get("result"):
			lines.append("%s: %s differs from the legacy path in this process: a real regression, not platform noise" % [key, mode])
			return lines
	var golden := _golden_tolerance_verdict(key, sidecar)
	if not golden.failures.is_empty():
		lines.append("%s: the golden tolerance comparison rejects it too:" % key)
		for f in golden.failures.slice(0, 12):
			lines.append("    " + str(f))
		return lines
	GoldenTolerance.print_noise("seed-zero", golden.noise,
		"%s: byte hashes differ (%s) but every entry point agrees with the legacy path and the golden comparison accepts it (%d stream(s) within the noise budget, the rest exact at 1/1000)"
		% [key, ", ".join(PackedStringArray(got_by_mode.keys())), golden.noise.size()])
	return []


## Which part of the hashes differs, with both values.
func _describe_mismatch(mode : String, got : Dictionary, expected : Dictionary) -> String:
	var parts := []
	if got.result != expected.result:
		var g : String = got.result
		var e : String = expected.result
		var gi := g.rfind(":")
		var ei := e.rfind(":")
		if g.substr(0, gi) != e.substr(0, ei):
			parts.append("outputs hash %s -> %s" % [e.substr(0, ei), g.substr(0, gi)])
		if g.substr(gi + 1) != e.substr(ei + 1):
			parts.append("generated-content hash %s -> %s" % [e.substr(ei + 1), g.substr(gi + 1)])
	if mode == MODE_LEGACY and got.nodes != expected.nodes:
		parts.append("per-node bulks hash %s -> %s" % [expected.nodes, got.nodes])
	return "; ".join(PackedStringArray(parts))


## Golden comparison (with the tolerance fallback) of every golden graph that
## comes from seed-zero key `key` (a graph resource, or a scene's components).
func _golden_tolerance_verdict(key : String, sidecar) -> Dictionary:
	var golden = JSON.parse_string(FileAccess.get_file_as_string(GoldenGraphsTest.BASELINE_PATH))
	var expected : Dictionary = golden.get("graphs", {}) if golden is Dictionary else {}
	var golden_keys := []
	for gkey in expected:
		if (gkey == key or gkey.begins_with(key + "::")) and expected[gkey].get("status") == "ok":
			golden_keys.append(gkey)
	if golden_keys.is_empty():
		return { "failures": ["%s is not covered by the golden baseline, so platform noise cannot be told from a regression" % key], "noise": [] }
	var logger := GoldenGraphsTest.CaptureLogger.new()
	OS.add_logger(logger)
	var entries = GoldenGraphsTest._normalize(GoldenGraphsTest.evaluate_source(self, key, logger))
	OS.remove_logger(logger)
	_clear_gdunit_script_errors()
	var failures := []
	var noise := []
	for gkey in golden_keys:
		if not entries.has(gkey):
			failures.append("%s: not evaluated" % gkey)
			continue
		var result := GoldenTolerance.compare_entry(gkey, expected[gkey], entries[gkey], sidecar, _raw_provider)
		failures.append_array(result.failures)
		noise.append_array(result.noise)
	return { "failures": failures, "noise": noise }


func _raw_provider(key : String, addresses : Array) -> Dictionary:
	var captured := GoldenTolerance.capture(self, GoldenTolerance.source_of(key), { key: addresses })
	_clear_gdunit_script_errors()
	return captured.get(key, {})


func _clear_gdunit_script_errors() -> void:
	var tctx = GdUnitThreadManager.get_current_context()
	if tctx == null:
		return
	var exec_ctx = tctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()


func test_graph_resources_match_seed_zero_baseline() -> void:
	if OS.get_environment("FLOW_WRITE_SEED0_BASELINE") == "1":
		await _write_baseline()
		return
	var baseline := _load_baseline()
	var graphs := Hasher.collect_graph_resources()
	assert_int(graphs.size()).is_greater(10)
	var got := {}
	for mode in _available_modes():
		for key in graphs:
			assert_bool(baseline.has(key)).override_failure_message("no baseline for %s" % key).is_true()
			if not (baseline.get(key) is Dictionary):
				continue
			if not got.has(key):
				got[key] = {}
			got[key][mode] = _hash_graph_resource(mode, graphs[key])
	var failures := []
	for key in got:
		failures.append_array(_judge(key, got[key], baseline[key]))
	assert_array(failures).override_failure_message("seed-zero: %d mismatch line(s):\n  %s" % [failures.size(), "\n  ".join(PackedStringArray(failures))]).is_empty()


func test_demo_scenes_match_seed_zero_baseline() -> void:
	if OS.get_environment("FLOW_WRITE_SEED0_BASELINE") == "1":
		return
	var baseline := _load_baseline()
	var scenes := Hasher.collect_demo_scenes()
	assert_int(scenes.size()).is_greater(20)
	var got := {}
	for mode in _available_modes():
		for scene_path in scenes:
			assert_bool(baseline.has(scene_path)).override_failure_message("no baseline for %s" % scene_path).is_true()
			if not (baseline.get(scene_path) is Dictionary):
				continue
			if not got.has(scene_path):
				got[scene_path] = {}
			got[scene_path][mode] = await _hash_scene(mode, scene_path)
	var failures := []
	for scene_path in got:
		failures.append_array(_judge(scene_path, got[scene_path], baseline[scene_path]))
	assert_array(failures).override_failure_message("seed-zero: %d mismatch line(s):\n  %s" % [failures.size(), "\n  ".join(PackedStringArray(failures))]).is_empty()
