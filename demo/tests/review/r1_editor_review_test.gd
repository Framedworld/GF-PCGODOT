# r1_editor_review_test.gd
# Adversarial review (WP13 R1): the editor dock's evaluation path against the
# runtime path for the same component (seed, overrides, params), and partial
# re-evaluation. See docs/_round2/WP13-R1.md.
class_name R1EditorReviewTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const EDITOR_SCENE := "res://addons/flow_nodes_editor/flow_editor.tscn"

var _editor : Control = null


func before() -> void:
	_editor = load(EDITOR_SCENE).instantiate()
	add_child(_editor)
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
	await get_tree().process_frame


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


func _editor_output(node_name: String) -> FlowData.Data:
	var widget = _editor.gedit_nodes_by_name.get(StringName(node_name))
	if widget == null or widget.generated_bulks.is_empty():
		return null
	var bulk = widget.generated_bulks[widget.generated_bulks.size() - 1]
	return bulk[0] if bulk.size() > 0 else null


static func _summary(data) -> Dictionary:
	if not (data is FlowData.Data):
		return {}
	return JSON.parse_string(JSON.stringify(FlowNodeIO.snapshot_summarize_data(data), "", true))


func _seeded_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2, "random_seed": 5}) \
		.node("noise", "attribute_noise", {"target_attribute": "density", "random_seed": 9}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "noise", 0) \
		.link("noise", 0, "out", 0) \
		.build()


# The dock previews a component's graph with that component as owner (spawned
# content goes under it), so what it shows must be what the component
# generates: same graph seed and same per-instance overrides.
func test_editor_preview_matches_component_with_seed_and_overrides() -> void:
	var graph := _seeded_graph()
	var host := FlowGraphNode3D.new()
	host.name = "ReviewOwner"
	host.generate_on_ready = false
	host.graph = graph
	host.seed = 1234
	host.overrides = { "grid/x": 4 }
	add_child(host)
	var runtime : FlowData.Data = host.generate()["result"]
	_open_in_editor(graph, host)
	_editor.evalGraph()
	var preview := _editor_output("out")
	assert_object(preview).is_not_null()
	assert_int(preview.size()).is_equal(runtime.size())
	assert_dict(_summary(preview)).is_equal(_summary(runtime))
	# Changing the component's seed re-evaluates nodes that are otherwise clean.
	host.seed = 99
	var reseeded : FlowData.Data = host.generate()["result"]
	assert_dict(_summary(reseeded)).is_not_equal(_summary(runtime))
	_editor.evalGraph()
	assert_dict(_summary(_editor_output("out"))).is_equal(_summary(reseeded))
	_editor.clear_graph()
	remove_child(host)
	host.free()


class WarningCapture extends Logger:
	var messages : Array = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(rationale if not rationale.is_empty() else code)

	func _log_message(_message: String, _error: bool) -> void:
		pass


# With the component's overrides in the dock context, a nested subgraph
# evaluation must not report the top-level overrides as unmatched: the dock
# runs the top-level nodes itself, so only the whole evaluation tree could
# tell, and the dock never warns (as before, when it had no overrides).
func test_editor_preview_with_overrides_and_subgraph_does_not_warn() -> void:
	var inner : FlowGraphResource = TestGraph.new() \
		.node("inner_grid", "grid", {"x": 1, "y": 1, "z": 1}) \
		.node("out", "output", {"name": "result"}) \
		.link("inner_grid", 0, "out", 0) \
		.build()
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2}) \
		.node("sub", "subgraph", {"graph": inner}) \
		.node("merge", "merge") \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "merge", 0) \
		.link("sub", 0, "merge", 0) \
		.link("merge", 0, "out", 0) \
		.build()
	var host := FlowGraphNode3D.new()
	host.generate_on_ready = false
	host.graph = graph
	host.overrides = { "grid/x": 4 }
	add_child(host)
	var capture := WarningCapture.new()
	OS.add_logger(capture)
	var runtime : FlowData.Data = host.generate()["result"]
	_open_in_editor(graph, host)
	_editor.evalGraph()
	OS.remove_logger(capture)
	var unmatched := capture.messages.filter(func(m): return str(m).contains("matched no node"))
	assert_array(unmatched).is_empty()
	assert_dict(_summary(_editor_output("out"))).is_equal(_summary(runtime))
	_editor.clear_graph()
	remove_child(host)
	host.free()


# Undo and redo replace the dock's nodes with load_graph_state(); the next
# evaluation must show the restored graph, not stale or empty data.
func test_undo_redo_state_reload_reevaluates_the_restored_graph() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2, "random_seed": 5}) \
		.node("attr", "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": 0.25}) \
		.node("noise", "attribute_noise", {"target_attribute": "density", "random_seed": 9}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "attr", 0) \
		.link("attr", 0, "noise", 0) \
		.link("noise", 0, "out", 0) \
		.build()
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	_open_in_editor(graph, owner)
	_editor.evalGraph()
	var original := _editor_snapshot()
	var before : Dictionary = _editor.get_graph_snapshot()
	var grid = _editor.gedit_nodes_by_name[&"grid"]
	grid.settings.x = 5
	grid.settings.emit_changed()
	_editor.evalGraph()
	var after : Dictionary = _editor.get_graph_snapshot()
	var edited := _editor_snapshot()
	assert_dict(edited).is_not_equal(original)
	# Undo.
	_editor.load_graph_state(before)
	_editor.evalGraph()
	assert_dict(_editor_snapshot()).is_equal(original)
	# Redo.
	_editor.load_graph_state(after)
	_editor.evalGraph()
	assert_dict(_editor_snapshot()).is_equal(edited)
	_editor.clear_graph()
	remove_child(owner)
	owner.free()


# A source node added from the menu (or pasted) and wired into the graph has
# never run; the next dock evaluation must run it, not feed its consumer
# nothing.
func test_added_source_node_is_evaluated_once_wired() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2}) \
		.node("merge", "merge") \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "merge", 0) \
		.link("merge", 0, "out", 0) \
		.build()
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	_open_in_editor(graph, owner)
	_editor.evalGraph()
	# addNode() also drives the EditorInterface inspector, which headless lacks;
	# it creates the node through addNodeFromTemplate() like paste and undo do.
	var added = _editor.addNodeFromTemplate("grid", _editor.getNewName("grid"))
	assert_object(added).is_not_null()
	_editor.connect_nodes(added.name, 0, &"merge", 0)
	_editor.evalGraph()
	FlowNodeIO.saveToResource(_editor)
	assert_dict(_editor_snapshot()).is_equal(_runtime_snapshot(graph, owner))
	assert_int(_editor.gedit_nodes_by_name[&"merge"].generated_bulks[0][0].size()).is_greater(6)
	_editor.clear_graph()
	remove_child(owner)
	owner.free()


# --- scene fingerprints (dirty tracking after scene edits) ----------------------------

# create_points in Local space reads the owner transform (its own
# computeSceneFingerprint says so). Inside a subgraph, the subgraph node must
# then re-run after a scene edit too.
func test_subgraph_with_owner_relative_create_points_is_scene_dependent() -> void:
	var inner : FlowGraphResource = TestGraph.new() \
		.node("pts", "create_points", {"coordinate_space": CreatePointsNodeSettings.eCoordinateSpace.Local}) \
		.node("out", "output", {"name": "result"}) \
		.link("pts", 0, "out", 0) \
		.build()
	var sub : FlowNodeBase = load("res://addons/flow_nodes_editor/nodes/subgraph.gd").new()
	sub.node_template = "subgraph"
	sub.settings = sub.getMeta().settings.new()
	sub.settings.graph = inner
	assert_bool(typeof(sub.computeSceneFingerprint(FlowData.EvaluationContext.new())) == TYPE_STRING_NAME) \
		.override_failure_message("subgraph around an owner-relative create_points reports SCENE_INDEPENDENT").is_false()


# clip_points_by_polygon reads a Path3D from the scene through its
# polygon_node_path setting. Moving that Path3D in the edited scene must
# mark the node dirty, like any other scene-reading node.
func test_clip_points_by_polygon_node_path_is_scene_dependent() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 4, "y": 1, "z": 4}) \
		.node("clip", "clip_points_by_polygon", {"polygon_node_path": NodePath("Poly")}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "clip", 0) \
		.link("clip", 0, "out", 0) \
		.build()
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	var path := Path3D.new()
	path.name = "Poly"
	path.curve = Curve3D.new()
	for p in [Vector3(-1, 0, -1), Vector3(150, 0, -1), Vector3(150, 0, 150), Vector3(-1, 0, 150)]:
		path.curve.add_point(p)
	owner.add_child(path)
	add_child(owner)
	_open_in_editor(graph, owner)
	_editor.evalGraph()
	var clip = _editor.gedit_nodes_by_name[&"clip"]
	assert_bool(clip.dirty).is_false()
	path.position = Vector3(1000, 0, 0)
	_editor.onEditorSceneChanged()
	assert_bool(clip.dirty).override_failure_message("moving the clip polygon left the node clean").is_true()
	_editor.clear_graph()
	remove_child(owner)
	owner.free()


# Without a polygon node path the node reads no scene and stays clean.
func test_clip_points_by_polygon_without_node_path_stays_scene_independent() -> void:
	var clip : FlowNodeBase = load("res://addons/flow_nodes_editor/nodes/clip_points_by_polygon.gd").new()
	clip.node_template = "clip_points_by_polygon"
	clip.settings = clip.getMeta().settings.new()
	assert_bool(typeof(clip.computeSceneFingerprint(FlowData.EvaluationContext.new())) == TYPE_STRING_NAME).is_true()


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
	return JSON.parse_string(JSON.stringify(snapshot, "", true))

func _runtime_snapshot(graph: FlowGraphResource, owner: Node3D) -> Dictionary:
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = owner
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	return JSON.parse_string(JSON.stringify(FlowNodeIO.evaluate_graph_snapshot(graph, {}, ctx, {}, 0), "", true))


# Partial re-evaluation: a setting edit on a middle node reaches a consumer
# that reads it through a variable (set_variable -> get_variable) and a
# reroute, and a disabled toggle on a middle node does too; after each edit
# the dock equals the runtime for the saved graph.
func test_partial_reevaluation_through_variables_reroutes_and_disable() -> void:
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2, "random_seed": 5}) \
		.node("attr", "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": 0.25}) \
		.node("set", "set_variable", {"variable_name": "pts"}) \
		.node("get", "get_variable", {"variable_name": "pts"}) \
		.node("rr", "reroute") \
		.node("filter", "density_filter", {"lower_bound": 0.0, "upper_bound": 0.5}) \
		.node("out_a", "output", {"name": "a"}) \
		.node("out_b", "output", {"name": "b"}) \
		.link("grid", 0, "attr", 0) \
		.link("attr", 0, "set", 0) \
		.link("get", 0, "rr", 0) \
		.link("rr", 0, "filter", 0) \
		.link("filter", 0, "out_a", 0) \
		.link("attr", 0, "out_b", 0) \
		.build()
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	_open_in_editor(graph, owner)
	_editor.evalGraph()
	assert_dict(_editor_snapshot()).is_equal(_runtime_snapshot(graph, owner))
	# Middle-node setting edit.
	var attr = _editor.gedit_nodes_by_name[&"attr"]
	attr.settings.cte_float = 0.75
	attr.settings.emit_changed()
	_editor.evalGraph()
	FlowNodeIO.saveToResource(_editor)
	assert_dict(_editor_snapshot()).is_equal(_runtime_snapshot(graph, owner))
	# Disable the middle filter (pass-through).
	var filter = _editor.gedit_nodes_by_name[&"filter"]
	filter.settings.disabled = true
	filter.settings.emit_changed()
	_editor.evalGraph()
	FlowNodeIO.saveToResource(_editor)
	assert_dict(_editor_snapshot()).is_equal(_runtime_snapshot(graph, owner))
	assert_int(_editor.gedit_nodes_by_name[&"out_a"].generated_bulks[0][0].size()).is_equal(6)
	_editor.clear_graph()
	remove_child(owner)
	owner.free()
