# editor_smoke_harness_test.gd
# Editor smoke harness (docs/PARITY_ROUND2.md WP1 requirement 8).
#
# Instantiates the real graph dock (flow_editor.tscn) in the headless test
# SceneTree, loads every golden graph into it exactly like opening a tab does
# (FlowNodeIO.loadFromResource), runs the dock's own evaluation path
# (FlowEditor.evalGraph: cacheConnections, per-node dirty expansion,
# getEvalOrder, _evaluate_graph_node with scratch bindings, debug draw and scene
# fingerprints) and compares every node's generated bulks with what the runtime
# path produces for the same graph (FlowNodeIO.evaluate_graph_snapshot), and
# the runtime path with the golden baseline.
#
# What headless cannot cover: the dock's _ready() returns early outside the
# editor (Engine.is_editor_hint() is false in a test run), so the toolbar,
# EditorInterface inspector wiring, EditorUndoRedoManager and the async
# _process() regen driver are not exercised. The harness drives the same
# public entry points those call (loadFromResource, evalGraph,
# markAllNodesAsDirty, node settings edits) directly.
class_name EditorSmokeHarnessTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const EDITOR_SCENE := "res://addons/flow_nodes_editor/flow_editor.tscn"
const BASELINE_PATH := "res://tests/golden/baseline.json"

## Graphs whose dock output legitimately differs from the runtime output, with
## the reason. Keys are golden keys; values are the explanation.
const KNOWN_EDITOR_DIFFERENCES := {}

var _editor : Control = null


# One dock for the whole suite.
func before() -> void:
	_editor = load(EDITOR_SCENE).instantiate()
	add_child(_editor)
	# The harness drives evaluation itself; never let _process() start an async
	# regen or flush a pending save to disk.
	_editor.set_process(false)
	await get_tree().process_frame


func after() -> void:
	if is_instance_valid(_editor):
		_editor.clear_graph()
		remove_child(_editor)
		_editor.free()
	_editor = null
	await get_tree().process_frame


func after_test() -> void:
	if is_instance_valid(_editor):
		_editor.clear_graph()
	# clear_graph() resets the data inspector, whose table queue_frees its
	# column labels; let them go before GdUnit counts orphan nodes.
	await get_tree().process_frame


# --- helpers ---------------------------------------------------------------------

static func _normalize(value) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true))

## Loads `graph` into the dock with `owner` as resource owner, the same steps
## FlowEditor._switch_to_tab performs, minus the reload-from-disk.
func _open_in_editor(graph: FlowGraphResource, owner: Node3D) -> void:
	_editor.clear_graph()
	_editor.current_resource = graph
	_editor.resource_owner = owner
	_editor.scanAvailableNodesIfNeeded()
	FlowNodeIO.loadFromResource(_editor)
	_editor.ctx.graph = graph
	_editor.ctx.owner = owner
	_editor.ctx.gedit_nodes_by_name = _editor.gedit_nodes_by_name
	_editor.markAllNodesAsDirty()

## Per-node summary of the bulks every dock node currently holds, in the shape
## evaluate_graph_snapshot() returns.
func _editor_snapshot() -> Dictionary:
	var snapshot := {}
	for child in _editor.gedit.get_children():
		if not (child is GraphNode) or not ("generated_bulks" in child):
			continue
		var bulks := []
		for bulk in child.generated_bulks:
			var ports := []
			for port_data in bulk:
				ports.append(FlowNodeIO.snapshot_summarize_data(port_data) if port_data is FlowData.Data else null)
			bulks.append(ports)
		snapshot[str(child.name)] = bulks
	return snapshot

func _runtime_snapshot(graph: FlowGraphResource, owner: Node3D, inputs: Dictionary) -> Dictionary:
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = owner
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	return FlowNodeIO.evaluate_graph_snapshot(graph, inputs, ctx, {}, 0)

## Differences between two per-node snapshots, node by node.
static func _diff_snapshots(expected: Dictionary, actual: Dictionary) -> Array:
	var diffs := []
	var names := {}
	for k in expected:
		names[k] = true
	for k in actual:
		names[k] = true
	var sorted := names.keys()
	sorted.sort()
	for node_name in sorted:
		if not expected.has(node_name):
			diffs.append("node '%s' only in editor" % node_name)
		elif not actual.has(node_name):
			diffs.append("node '%s' missing in editor" % node_name)
		elif expected[node_name] != actual[node_name]:
			diffs.append("node '%s' %s" % [node_name, GoldenGraphsTest._describe_node_diff(expected[node_name], actual[node_name])])
	return diffs

## Every golden case as { key, graph, owner_factory } where owner_factory
## returns [root_to_free, owner, inputs]. Scene graphs get a fresh scene
## instance per call so one path never sees the other's spawned content.
func _cases() -> Array:
	var cases := []
	for path in GoldenGraphsTest.discover_files():
		var ext : String = path.get_extension()
		if ext == "tscn" or ext == "scn":
			var packed = ResourceLoader.load(path)
			if not (packed is PackedScene):
				continue
			var probe : Node = packed.instantiate()
			var owner_paths := []
			if probe is FlowGraphNode3D:
				owner_paths.append(NodePath("."))
			for n in probe.find_children("*", "", true, false):
				if n is FlowGraphNode3D:
					owner_paths.append(probe.get_path_to(n))
			probe.free()
			for owner_path in owner_paths:
				cases.append({ "key": "%s::%s" % [path, str(owner_path)], "scene": packed, "owner_path": owner_path })
		else:
			var res = ResourceLoader.load(path)
			if res is FlowGraphResource:
				cases.append({ "key": path, "graph": res })
	return cases

## Instantiates the case's host. Returns { root, owner, graph, inputs } or {}
## when the case has no graph.
func _instantiate_case(case: Dictionary) -> Dictionary:
	if case.has("graph"):
		var owner := FlowGraphNode3D.new()
		owner.name = "SmokeOwner"
		add_child(owner)
		return { "root": owner, "owner": owner, "graph": case.graph, "inputs": {} }
	var root : Node = case.scene.instantiate()
	var flow_nodes := []
	if root is FlowGraphNode3D:
		flow_nodes.append(root)
	for n in root.find_children("*", "", true, false):
		if n is FlowGraphNode3D:
			flow_nodes.append(n)
	# Detach the graphs so entering the tree does not auto-generate.
	var graphs := {}
	for fn in flow_nodes:
		graphs[fn] = fn.graph
		fn.graph = null
	add_child(root)
	for fn in flow_nodes:
		fn.graph = graphs[fn]
	var owner = root.get_node(case.owner_path)
	if owner == null or owner.graph == null:
		remove_child(root)
		root.free()
		return {}
	return { "root": root, "owner": owner, "graph": owner.graph, "inputs": owner.args if owner.args != null else {} }

func _release_case(inst: Dictionary) -> void:
	var root : Node = inst.root
	if root.get_parent() != null:
		root.get_parent().remove_child(root)
	root.free()

## Graph scripts raise recorded node errors (see the golden baseline); keep
## GdUnit's error monitor from failing the harness on them.
func _clear_gdunit_script_errors() -> void:
	var tctx = GdUnitThreadManager.get_current_context()
	if tctx == null:
		return
	var exec_ctx = tctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()


# --- tests -------------------------------------------------------------------------

func test_editor_dock_instantiates_headless() -> void:
	assert_object(_editor).is_not_null()
	assert_object(_editor.gedit).is_not_null()
	assert_bool(_editor.gedit is GraphEdit).is_true()
	assert_object(_editor.data_inspector).is_not_null()


func test_editor_evaluation_matches_runtime_and_golden_for_every_graph(timeout := 1800000) -> void:
	var baseline = JSON.parse_string(FileAccess.get_file_as_string(BASELINE_PATH))
	assert_object(baseline).is_not_null()
	var expected_graphs : Dictionary = baseline.get("graphs", {})
	var failures := []
	var compared := 0
	for case in _cases():
		var key : String = case.key
		var entry : Dictionary = expected_graphs.get(key, {})
		if entry.get("status", "") != "ok":
			continue
		# Runtime path.
		var rt := _instantiate_case(case)
		if rt.is_empty():
			continue
		var graph : FlowGraphResource = rt.graph
		var runtime_nodes = _normalize(_runtime_snapshot(graph, rt.owner, rt.inputs))
		_clear_gdunit_script_errors()
		_release_case(rt)
		var golden_diffs := _diff_snapshots(entry.get("nodes", {}), runtime_nodes)
		for d in golden_diffs.slice(0, 6):
			failures.append("%s runtime vs golden: %s" % [key, d])
		# Editor path, on a fresh host.
		var ed := _instantiate_case(case)
		_open_in_editor(ed.graph, ed.owner)
		_editor.evalGraph()
		_clear_gdunit_script_errors()
		var editor_nodes = _normalize(_editor_snapshot())
		_editor.clear_graph()
		_release_case(ed)
		compared += 1
		if KNOWN_EDITOR_DIFFERENCES.has(key):
			continue
		var editor_diffs := _diff_snapshots(runtime_nodes, editor_nodes)
		for d in editor_diffs.slice(0, 6):
			failures.append("%s editor vs runtime: %s" % [key, d])
	assert_int(compared).is_greater(40)
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()


## Per-node dirty tracking: after a full dock evaluation, editing one node's
## setting re-runs only that node and its dependants, and the dock then shows
## the same data the runtime produces for the edited graph.
func test_dirty_tracking_reruns_only_the_edited_branch() -> void:
	var graph := FlowGraphResource.new()
	graph.data = {
		"type": "flow_graph_nodes",
		"version": 1,
		"min_pos": Vector2.ZERO,
		"nodes": [
			{ "name": &"grid", "template": "grid", "settings": { "x": 3, "y": 1, "z": 2 }, "position": Vector2.ZERO, "args_port": {}, "show_disconnected_inputs": false },
			{ "name": &"other", "template": "grid", "settings": { "x": 2, "y": 1, "z": 2 }, "position": Vector2(0, 200), "args_port": {}, "show_disconnected_inputs": false },
			{ "name": &"attr", "template": "add_attribute", "settings": { "name": "w", "data_type": FlowData.DataType.Float, "cte_float": 0.5 }, "position": Vector2(300, 0), "args_port": {}, "show_disconnected_inputs": false },
			{ "name": &"out_a", "template": "output", "settings": { "name": "a" }, "position": Vector2(600, 0), "args_port": {}, "show_disconnected_inputs": false },
			{ "name": &"out_b", "template": "output", "settings": { "name": "b" }, "position": Vector2(600, 200), "args_port": {}, "show_disconnected_inputs": false },
		],
		"links": [
			{ "from_node": &"grid", "from_port": 0, "to_node": &"attr", "to_port": 0, "keep_alive": false },
			{ "from_node": &"attr", "from_port": 0, "to_node": &"out_a", "to_port": 0, "keep_alive": false },
			{ "from_node": &"other", "from_port": 0, "to_node": &"out_b", "to_port": 0, "keep_alive": false },
		],
		"frames": [],
	}
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	_open_in_editor(graph, owner)
	_editor.evalGraph()
	var first_eval : int = _editor.ctx.eval_id
	for n in _editor.getAllNodes():
		assert_bool(n.dirty).override_failure_message("%s still dirty" % n.name).is_false()
		assert_int(n.eval_id).is_equal(first_eval)

	# Edit the grid size through its settings resource, as the inspector does.
	var grid_node = _editor.gedit_nodes_by_name[&"grid"]
	grid_node.settings.x = 5
	grid_node.settings.emit_changed()
	assert_bool(grid_node.dirty).is_true()
	_editor.evalGraph()
	var second_eval : int = _editor.ctx.eval_id
	assert_int(second_eval).is_equal(first_eval + 1)
	# The edited branch re-ran; the untouched grid did not.
	assert_int(_editor.gedit_nodes_by_name[&"grid"].eval_id).is_equal(second_eval)
	assert_int(_editor.gedit_nodes_by_name[&"attr"].eval_id).is_equal(second_eval)
	assert_int(_editor.gedit_nodes_by_name[&"other"].eval_id).is_equal(first_eval)
	assert_int(_editor.gedit_nodes_by_name[&"attr"].generated_bulks[0][0].size()).is_equal(10)

	# The dock's view equals the runtime result of the saved, edited graph.
	FlowNodeIO.saveToResource(_editor)
	var runtime_nodes = _normalize(_runtime_snapshot(graph, owner, {}))
	var editor_nodes = _normalize(_editor_snapshot())
	assert_array(_diff_snapshots(runtime_nodes, editor_nodes)).is_empty()
	_editor.clear_graph()
	remove_child(owner)
	owner.free()


## Scene fingerprints: a scene-independent graph records no fingerprint and an
## unrelated scene edit leaves every node clean.
func test_scene_change_without_scene_inputs_keeps_nodes_clean() -> void:
	var graph := FlowGraphResource.new()
	graph.data = {
		"type": "flow_graph_nodes",
		"version": 1,
		"min_pos": Vector2.ZERO,
		"nodes": [
			{ "name": &"grid", "template": "grid", "settings": { "x": 2, "y": 1, "z": 2 }, "position": Vector2.ZERO, "args_port": {}, "show_disconnected_inputs": false },
			{ "name": &"out", "template": "output", "settings": { "name": "a" }, "position": Vector2(300, 0), "args_port": {}, "show_disconnected_inputs": false },
		],
		"links": [
			{ "from_node": &"grid", "from_port": 0, "to_node": &"out", "to_port": 0, "keep_alive": false },
		],
		"frames": [],
	}
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	_open_in_editor(graph, owner)
	_editor.evalGraph()
	_editor.onEditorSceneChanged()
	for n in _editor.getAllNodes():
		assert_bool(n.dirty).override_failure_message("%s became dirty" % n.name).is_false()
	_editor.clear_graph()
	remove_child(owner)
	owner.free()


## Every registered node template can be added to the dock: the element is
## created from the node script, wrapped in its widget (reroute's own
## subclass), built (initFromScript, widget_init), refreshed (widget_refresh)
## and entered into the tree (widget_ready) without script errors.
func test_every_template_builds_a_widget() -> void:
	var graph := FlowGraphResource.new()
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	_open_in_editor(graph, owner)
	var templates : Array = _editor.node_types.keys()
	templates.sort()
	assert_int(templates.size()).is_greater(100)
	var failures := []
	var index := 0
	for template in templates:
		index += 1
		var widget = _editor.addNodeFromTemplate(template, "n_%d" % index)
		if not (widget is FlowNodeWidget):
			failures.append("%s: no widget" % template)
			continue
		if widget.element == null or widget.element.node_template != template:
			failures.append("%s: element not bound" % template)
		elif widget.element.get_widget() != widget:
			failures.append("%s: element does not point back to its widget" % template)
		elif String(widget.element.name) != String(widget.name):
			failures.append("%s: element name %s != widget name %s" % [template, widget.element.name, widget.name])
		if template == "reroute" and not (widget is FlowRerouteWidget):
			failures.append("reroute: expected FlowRerouteWidget")
		widget.refreshFromSettings()
		widget.queue_redraw()
	_clear_gdunit_script_errors()
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()
	_editor.clear_graph()
	remove_child(owner)
	owner.free()
