# wp14e_editor_bugs_test.gd
# Editor bugs found in a real Godot editor session (docs/_round2/WP14-E.md):
# pooling in the dock, undo of Insert Reroute, Collapse to Subgraph, and small
# load/inspector issues. The dock is driven headless like the R1 review suite;
# undo and redo replay the graph states the dock recorded for the action.
class_name WP14EEditorBugsTest extends GdUnitTestSuite

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
		_editor.current_resource = null
		_editor.resource_owner = null
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


func _make_owner() -> FlowGraphNode3D:
	var owner := FlowGraphNode3D.new()
	owner.generate_on_ready = false
	add_child(owner)
	return owner


func _free_owner(owner: Node) -> void:
	_editor.clear_graph()
	if is_instance_valid(owner):
		remove_child(owner)
		owner.free()


## Sorted node names (with templates) and sorted connections of the dock.
func _graph_shape() -> Dictionary:
	var nodes := []
	for node in _editor.getAllNodes():
		nodes.append("%s:%s" % [node.name, node.node_template])
	nodes.sort()
	var links := []
	for c in _editor.gedit.connections:
		links.append("%s:%d->%s:%d" % [c.from_node, c.from_port, c.to_node, c.to_port])
	links.sort()
	var frames := []
	for child in _editor.gedit.get_children():
		if child is GraphFrame and not child.has_meta("flow_retired"):
			var attached := []
			for attached_name in _editor.gedit.get_attached_nodes_of_frame(child.name):
				attached.append(String(attached_name))
			attached.sort()
			frames.append("%s:%s" % [child.name, ",".join(attached)])
	frames.sort()
	return {"nodes": nodes, "links": links, "frames": frames}


func _output_summary(node_name: String) -> Dictionary:
	var widget = _editor.gedit_nodes_by_name.get(StringName(node_name))
	if widget == null or widget.generated_bulks.is_empty():
		return {}
	var bulk = widget.generated_bulks[widget.generated_bulks.size() - 1]
	if bulk.is_empty() or not (bulk[0] is FlowData.Data):
		return {}
	return JSON.parse_string(JSON.stringify(FlowNodeIO.snapshot_summarize_data(bulk[0]), "", true))


# --- 2. Insert Reroute undo ------------------------------------------------------

func _chain_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2, "random_seed": 5}) \
		.node("attr", "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": 0.25}) \
		.node("noise", "attribute_noise", {"target_attribute": "density", "random_seed": 9}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "attr", 0) \
		.link("attr", 0, "noise", 0) \
		.link("noise", 0, "out", 0) \
		.build()


## What the editor's debounced save (FlowEditor._process) does 0.35 s after
## an edit: in a real session it has always run before the user presses Ctrl+Z.
func _flush_debounced_save() -> void:
	_editor.saveResource()


## The states of the last recorded undo action. EditorUndoRedoManager is
## editor-only, so the test replays them: the do and undo methods of every
## snapshot action are load_graph_state(after) and load_graph_state(before).
func _recorded(action_name: String) -> Dictionary:
	var record : Dictionary = _editor.last_recorded_undo_action
	assert_str(String(record.get("name", ""))).is_equal(action_name)
	return record


func test_insert_reroute_undo_restores_the_original_wire() -> void:
	var owner := _make_owner()
	_open_in_editor(_chain_graph(), owner)
	_editor.evalGraph()
	_flush_debounced_save()
	var original_shape := _graph_shape()
	var original_out := _output_summary("out")
	var conn := {"from_node": &"attr", "from_port": 0, "to_node": &"noise", "to_port": 0}
	var reroute = _editor.insertRerouteOnConnection(conn, Vector2(100, 100))
	assert_object(reroute).is_not_null()
	var record := _recorded("Insert Reroute")
	_editor.evalGraph()
	_flush_debounced_save()
	var inserted_shape := _graph_shape()
	assert_int(inserted_shape.nodes.size()).is_equal(original_shape.nodes.size() + 1)
	assert_int(inserted_shape.links.size()).is_equal(original_shape.links.size() + 1)
	assert_dict(_output_summary("out")).is_equal(original_out)
	# Undo.
	_editor.load_graph_state(record.before)
	_editor.evalGraph()
	assert_dict(_graph_shape()).is_equal(original_shape)
	assert_dict(_output_summary("out")).is_equal(original_out)
	_flush_debounced_save()
	# Redo.
	_editor.load_graph_state(record.after)
	_editor.evalGraph()
	assert_dict(_graph_shape()).is_equal(inserted_shape)
	assert_dict(_output_summary("out")).is_equal(original_out)
	_flush_debounced_save()
	# Undo again; a click on the graph (which repairs the dock against the
	# resource) keeps the restored graph.
	_editor.load_graph_state(record.before)
	_editor.prepare_graph_for_interaction()
	assert_dict(_graph_shape()).is_equal(original_shape)
	_free_owner(owner)


# The other undo paths (add node, wire removal, node move) do not go through
# load_graph_state; they must keep working, and a click right after them (before
# the debounced save) must not restore what they removed from the resource.
func test_add_node_wire_and_move_undo_survive_a_click_before_the_save() -> void:
	var owner := _make_owner()
	_open_in_editor(_chain_graph(), owner)
	_editor.evalGraph()
	_flush_debounced_save()
	var original_shape := _graph_shape()
	# Add Node: do = _restore_added_node, undo = _remove_added_node.
	var counter_before : int = _editor.new_name_counter
	var added = _editor.addNode("grid")
	assert_object(added).is_not_null()
	var added_name : StringName = added.name
	var counter_after : int = _editor.new_name_counter
	var node_data : Dictionary = _editor._get_added_node_undo_data(added)
	_flush_debounced_save()
	_editor._remove_added_node(added_name, [], counter_before, false)
	_editor.prepare_graph_for_interaction()
	assert_dict(_graph_shape()).is_equal(original_shape)
	_flush_debounced_save()
	_editor._restore_added_node(node_data, [], [], counter_after)
	_editor.prepare_graph_for_interaction()
	assert_bool(_editor.gedit_nodes_by_name.has(added_name)).is_true()
	assert_int(_graph_shape().nodes.size()).is_equal(original_shape.nodes.size() + 1)
	_flush_debounced_save()
	_editor._remove_added_node(added_name, [], counter_before, false)
	_editor.prepare_graph_for_interaction()
	assert_dict(_graph_shape()).is_equal(original_shape)
	_flush_debounced_save()
	# Wire removal: do and undo are apply_connections_change.
	var conn := {"from_node": &"attr", "from_port": 0, "to_node": &"noise", "to_port": 0}
	_editor._on_graph_edit_disconnection_request(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
	assert_int(_graph_shape().links.size()).is_equal(original_shape.links.size() - 1)
	_flush_debounced_save()
	_editor.apply_connections_change([], [conn])
	_editor.prepare_graph_for_interaction()
	assert_dict(_graph_shape()).is_equal(original_shape)
	_flush_debounced_save()
	_editor.apply_connections_change([conn], [])
	_editor.prepare_graph_for_interaction()
	assert_int(_graph_shape().links.size()).is_equal(original_shape.links.size() - 1)
	_editor.apply_connections_change([], [conn])
	assert_dict(_graph_shape()).is_equal(original_shape)
	# Node move: do and undo are set_nodes_positions.
	var grid = _editor.gedit_nodes_by_name[&"grid"]
	var start : Vector2 = grid.position_offset
	_editor.set_nodes_positions({"grid": [start.x + 120.0, start.y + 40.0]})
	assert_vector(grid.position_offset).is_equal(start + Vector2(120, 40))
	_editor.set_nodes_positions({"grid": [start.x, start.y]})
	assert_vector(grid.position_offset).is_equal(start)
	assert_dict(_graph_shape()).is_equal(original_shape)
	_free_owner(owner)


# --- 3. Collapse to Subgraph -------------------------------------------------------

const COLLAPSE_DIR := "user://wp14e_collapse"


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(path)


## Opens the chain graph (embedded in a saved scene, or saved as its own .tres)
## in the dock, collapses `attr` and `noise` into a subgraph, then undoes and
## redoes the collapse.
func _check_collapse(embedded: bool) -> void:
	_remove_dir(COLLAPSE_DIR)
	DirAccess.make_dir_recursive_absolute(COLLAPSE_DIR)
	var graph := _chain_graph()
	var owner : FlowGraphNode3D
	if embedded:
		var scene_root := FlowGraphNode3D.new()
		scene_root.name = "CollapseHost"
		scene_root.generate_on_ready = false
		scene_root.graph = graph
		var packed := PackedScene.new()
		packed.pack(scene_root)
		scene_root.free()
		assert_int(ResourceSaver.save(packed, COLLAPSE_DIR + "/host.tscn")).is_equal(OK)
		var loaded : PackedScene = ResourceLoader.load(COLLAPSE_DIR + "/host.tscn", "", ResourceLoader.CACHE_MODE_IGNORE)
		owner = loaded.instantiate()
		add_child(owner)
		graph = owner.graph
		assert_str(graph.resource_path).contains("::")
	else:
		assert_int(ResourceSaver.save(graph, COLLAPSE_DIR + "/graph.tres")).is_equal(OK)
		graph = ResourceLoader.load(COLLAPSE_DIR + "/graph.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		owner = _make_owner()
		owner.graph = graph
	_open_in_editor(graph, owner)
	# A comment frame around grid and attr: the collapse detaches attr from it,
	# the undo must attach it again.
	for node in _editor.getAllNodes():
		node.selected = node.name == &"grid" or node.name == &"attr"
	_editor.addComment()
	_editor.evalGraph()
	_flush_debounced_save()
	var original_shape := _graph_shape()
	assert_int(original_shape.frames.size()).is_equal(1)
	assert_str(original_shape.frames[0]).ends_with(":attr,grid")
	var original_out := _output_summary("out")
	for node in _editor.getAllNodes():
		node.selected = node.name == &"attr" or node.name == &"noise"
	_editor.collapse_selected_to_subgraph()
	var record := _recorded("Collapse to Subgraph")
	_editor.evalGraph()
	var collapsed_shape := _graph_shape()
	var sub_name := ""
	for node in _editor.getAllNodes():
		if node.node_template == "subgraph":
			sub_name = String(node.name)
	assert_str(sub_name).is_not_empty()
	assert_array(collapsed_shape.nodes).contains_exactly_in_any_order([
		"grid:grid", "out:output", "%s:subgraph" % sub_name])
	assert_array(collapsed_shape.links).contains_exactly_in_any_order([
		"grid:0->%s:0" % sub_name, "%s:0->out:0" % sub_name])
	assert_str(collapsed_shape.frames[0]).ends_with(":grid")
	_assert_keeps_streams(_output_summary("out"), original_out)
	_flush_debounced_save()
	_editor.prepare_graph_for_interaction()
	assert_dict(_graph_shape()).is_equal(collapsed_shape)
	# Undo.
	_editor.load_graph_state(record.before)
	_editor.evalGraph()
	assert_dict(_graph_shape()).is_equal(original_shape)
	assert_dict(_output_summary("out")).is_equal(original_out)
	_flush_debounced_save()
	_editor.prepare_graph_for_interaction()
	assert_dict(_graph_shape()).is_equal(original_shape)
	# Redo.
	_editor.load_graph_state(record.after)
	_editor.evalGraph()
	assert_dict(_graph_shape()).is_equal(collapsed_shape)
	_assert_keeps_streams(_output_summary("out"), original_out)
	_free_owner(owner)
	_remove_dir(COLLAPSE_DIR)


## The collapsed graph yields the same points and every original stream with
## the same values. The subgraph's boundary input and output nodes add their
## parameter streams (in_attr_In, out_noise_Out), as any subgraph does.
func _assert_keeps_streams(actual: Dictionary, expected: Dictionary) -> void:
	assert_float(actual.get("size", -1.0)).is_equal(expected.size)
	var by_name := {}
	for stream in actual.get("streams", []):
		by_name[stream.name] = stream
	for stream in expected.streams:
		assert_dict(by_name.get(stream.name, {})).is_equal(stream)


func test_collapse_to_subgraph_replaces_selection_in_embedded_graph() -> void:
	_check_collapse(true)


func test_collapse_to_subgraph_replaces_selection_in_external_graph() -> void:
	_check_collapse(false)


# --- 4. Opening graphs, inspector formatting ----------------------------------------

class ErrorCapture extends Logger:
	var messages : Array = []

	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append(rationale if not rationale.is_empty() else code)

	func _log_message(_message: String, _error: bool) -> void:
		pass


const OPEN_DIR := "user://wp14e_open"


## A graph embedded in a saved scene (resource path "<scene>::<id>") and its
## loaded scene instance, or a graph saved as its own .tres and a fresh owner.
func _saved_graph_and_owner(embedded: bool) -> Array:
	_remove_dir(OPEN_DIR)
	DirAccess.make_dir_recursive_absolute(OPEN_DIR)
	if embedded:
		var scene_root := FlowGraphNode3D.new()
		scene_root.name = "OpenHost"
		scene_root.generate_on_ready = false
		scene_root.graph = _chain_graph()
		var packed := PackedScene.new()
		packed.pack(scene_root)
		scene_root.free()
		ResourceSaver.save(packed, OPEN_DIR + "/host.tscn")
		# Cached like a scene the editor opened: its sub-resources are then
		# registered under "<scene>::<id>" paths, so ResourceLoader.exists()
		# accepts them.
		var loaded : PackedScene = ResourceLoader.load(OPEN_DIR + "/host.tscn", "", ResourceLoader.CACHE_MODE_REPLACE)
		var owner : FlowGraphNode3D = loaded.instantiate()
		add_child(owner)
		return [owner.graph, owner]
	ResourceSaver.save(_chain_graph(), OPEN_DIR + "/graph.tres")
	var graph : FlowGraphResource = ResourceLoader.load(OPEN_DIR + "/graph.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	var host := _make_owner()
	host.graph = graph
	return [graph, host]


func _close_all_tabs() -> void:
	_editor.clear_graph()
	_editor.open_tabs.clear()
	_editor.active_tab_index = -1
	_editor.current_resource = null
	_editor.resource_owner = null
	_editor.save_pending = false
	_editor._sync_tab_bar_from_open_tabs()


# Opening a scene whose graph is a scene sub-resource must not try to reload
# "<scene>::<id>" from disk (ResourceLoader.exists accepts it, load fails).
func test_opening_an_embedded_graph_does_not_reload_it_from_disk() -> void:
	var pair := _saved_graph_and_owner(true)
	var graph : FlowGraphResource = pair[0]
	assert_str(graph.resource_path).contains("::")
	var capture := ErrorCapture.new()
	OS.add_logger(capture)
	var reloaded = _editor._reload_resource_from_disk(graph)
	_editor.setResourceToEdit(graph, pair[1])
	OS.remove_logger(capture)
	assert_object(reloaded).is_same(graph)
	assert_object(_editor.current_resource).is_same(graph)
	assert_array(capture.messages).is_empty()
	_close_all_tabs()
	_free_owner(pair[1])
	_remove_dir(OPEN_DIR)


func _check_fresh_tab_is_not_modified(embedded: bool) -> void:
	var pair := _saved_graph_and_owner(embedded)
	_editor.setResourceToEdit(pair[0], pair[1])
	assert_int(_editor.open_tabs.size()).is_equal(1)
	assert_bool(_editor._is_tab_dirty(0)).is_false()
	assert_str(_editor.tab_bar.get_tab_title(0)).not_contains("*")
	# The first dock evaluation after opening does not modify it either.
	_editor.evalGraph()
	assert_bool(_editor._is_tab_dirty(0)).is_false()
	assert_int(_editor.getAllNodes().size()).is_equal(4)
	_close_all_tabs()
	_free_owner(pair[1])
	_remove_dir(OPEN_DIR)


# The demo graphs are saved at format version 1; opening one upgraded the
# version stamp in memory and marked the tab modified before any edit.
func test_freshly_opened_embedded_graph_tab_is_not_modified() -> void:
	_check_fresh_tab_is_not_modified(true)


func test_freshly_opened_external_graph_tab_is_not_modified() -> void:
	_check_fresh_tab_is_not_modified(false)


# A rotation of exactly zero is often -0.0 (a negated or decomposed zero); the
# inspector shows it as 0.000. The data keeps its value.
func test_inspector_formats_negative_zero_as_zero() -> void:
	assert_str(FlowDataTableModel.fmt_real(-0.0)).is_equal("0.000")
	assert_str(FlowDataTableModel.fmt_real(-0.0001)).is_equal("0.000")
	assert_str(FlowDataTableModel.fmt_real(0.0)).is_equal("0.000")
	assert_str(FlowDataTableModel.fmt_real(-0.5)).is_equal("-0.500")
	assert_str(FlowDataTableModel.fmt_real(-0.0, 6)).is_equal("0.000000")
	var data := FlowData.Data.new()
	var rotations = data.addStream(FlowData.AttrRotation, FlowData.DataType.Vector)
	rotations.append(Vector3(-0.0, 0.0, -0.0))
	var xforms = data.addStream(&"xform", FlowData.DataType.Transform)
	xforms.append(Transform3D(Basis.from_euler(Vector3(-0.0, -0.0, -0.0)), Vector3(-0.0, 1.0, 0.0)))
	var model := FlowDataTableModel.new()
	model.set_data(data)
	var texts := []
	for col in model.columns.size():
		var column = model.columns[col]
		if column.stream_name == String(FlowData.AttrRotation) or column.title.contains("Rot.") or column.title.ends_with("Pos.X"):
			texts.append(model.cell_text(col, 0))
	assert_array(texts).contains_exactly(["0.000", "0.000", "0.000", "0.000", "0.000", "0.000", "0.000"])
	# Formatting only: the stored value is still negative zero.
	assert_float(1.0 / data.findStream(FlowData.AttrRotation).container[0].x).is_less(0.0)


# --- 1. Spawner pooling in the dock ------------------------------------------------

func _spawn_graph(reuse: bool) -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 3, "y": 1, "z": 2}) \
		.node("spawn", "spawn_meshes", {"mesh": BoxMesh.new(), "reuse_instances": reuse}) \
		.link("grid", 0, "spawn", 0) \
		.build()


## The spawned MultiMeshInstance3Ds directly under `owner`.
func _spawned(owner: Node) -> Array:
	var found := []
	for child in owner.get_children():
		if child is MultiMeshInstance3D and child.has_meta("flow_owner") and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _single_spawned_id(owner: Node) -> int:
	var spawned := _spawned(owner)
	assert_int(spawned.size()).is_equal(1)
	return spawned[0].get_instance_id() if spawned.size() == 1 else 0


func _settings_of(node_name: String) -> Resource:
	return _editor.gedit_nodes_by_name[StringName(node_name)].settings


# The dock removes previous generated content before every evaluation; with
# reuse_instances on, the spawner's pool must still find its previous content,
# as FlowGraphNode3D.generate() does at runtime.
func test_dock_evaluation_reuses_pooled_spawner_content() -> void:
	var owner := _make_owner()
	_open_in_editor(_spawn_graph(true), owner)
	_editor.evalGraph()
	var first := _single_spawned_id(owner)
	var key = instance_from_id(first).get_meta(FlowSpawnPool.KEY_META, "")
	assert_str(String(key)).is_not_empty()
	_editor.evalGraph()
	assert_int(_single_spawned_id(owner)).is_equal(first)
	# An upstream edit with the same mesh keeps the instance and resizes it.
	_settings_of("grid").x = 5
	_editor.gedit_nodes_by_name[&"grid"].dirty = true
	_editor.evalGraph()
	assert_int(_single_spawned_id(owner)).is_equal(first)
	var mmi : MultiMeshInstance3D = instance_from_id(first)
	assert_int(mmi.multimesh.instance_count).is_equal(10)
	assert_str(String(mmi.get_meta(FlowSpawnPool.KEY_META))).is_equal(String(key))
	assert_object(mmi.owner).is_not_null()
	# Transient output: the reused instance is never saved with the scene.
	owner.transient_output = true
	_editor.evalGraph()
	assert_int(_single_spawned_id(owner)).is_equal(first)
	assert_object(mmi.owner).is_null()
	_free_owner(owner)


func test_dock_evaluation_without_reuse_replaces_spawner_content() -> void:
	var owner := _make_owner()
	_open_in_editor(_spawn_graph(false), owner)
	_editor.evalGraph()
	var first := _single_spawned_id(owner)
	_editor.evalGraph()
	var second := _single_spawned_id(owner)
	assert_int(second).is_not_equal(first)
	await get_tree().process_frame
	assert_bool(is_instance_id_valid(first)).is_false()
	# Turning reuse off on a pooled spawner frees its pooled content.
	_settings_of("spawn").reuse_instances = true
	_editor.evalGraph()
	var pooled := _single_spawned_id(owner)
	_settings_of("spawn").reuse_instances = false
	_editor.evalGraph()
	assert_int(_single_spawned_id(owner)).is_not_equal(pooled)
	await get_tree().process_frame
	assert_bool(is_instance_id_valid(pooled)).is_false()
	_free_owner(owner)


# Pooled content whose spawner no longer produces it must not stay behind.
func test_dock_frees_pooled_content_of_removed_disabled_or_starved_spawners() -> void:
	var owner := _make_owner()
	_open_in_editor(_spawn_graph(true), owner)
	# Disabled spawner.
	_editor.evalGraph()
	var first := _single_spawned_id(owner)
	_settings_of("spawn").disabled = true
	_editor.evalGraph()
	assert_array(_spawned(owner)).is_empty()
	await get_tree().process_frame
	assert_bool(is_instance_id_valid(first)).is_false()
	# Spawner without input (it reports an error and spawns nothing).
	_settings_of("spawn").disabled = false
	_editor.evalGraph()
	var second := _single_spawned_id(owner)
	_editor.disconnect_nodes(&"grid", 0, &"spawn", 0)
	_editor.evalGraph()
	assert_array(_spawned(owner)).is_empty()
	await get_tree().process_frame
	assert_bool(is_instance_id_valid(second)).is_false()
	# Deleted spawner.
	_editor.connect_nodes(&"grid", 0, &"spawn", 0)
	_editor.evalGraph()
	var third := _single_spawned_id(owner)
	var spawn_nodes : Array[GraphNode] = [_editor.gedit_nodes_by_name[&"spawn"]]
	_editor.deleteNodes(spawn_nodes)
	_editor.evalGraph()
	assert_array(_spawned(owner)).is_empty()
	await get_tree().process_frame
	assert_bool(is_instance_id_valid(third)).is_false()
	_free_owner(owner)
