@tool
extends EditorPlugin

# This is the entry point for the plugin
# Where we register all editors, inspectors and hocks

const FlowEditorDockScript := preload("res://addons/flow_nodes_editor/flow_editor_dock.gd")

var graph_dock: Control
var graph_dock_wrapper: EditorDock
var data_inspector_dock: Control
const _SHADER_DOCK_ICON := &"ShaderDock"
const _BOTTOM_DOCK_PLACE_RETRY_INTERVAL_SEC := 0.5
const _BOTTOM_DOCK_PLACE_MAX_RETRIES := 120
const _FLOW_DOCK_LAYOUT_KEY := "FlowNodesEditor_GraphDock_Bottom"
const _DOCK_LAYOUT_WATCH_MS := 120000
var _bottom_dock_place_retries := 0
var _dock_layout_watch_started_ms := 0
var inspector_plugin
var watched_nodes : Array[Node] = []
var undo_redo: EditorUndoRedoManager
var graph_input_inspector_plugin : EditorInspectorPlugin
var node_settings_inspector_plugin : EditorInspectorPlugin

# To detect scene changes
var current_scene_root = null
var current_watched_node = null

# Resolved in _enter_tree; null in headless/--import runs where there is no
# editor selection — every use must null-guard.
var selection : EditorSelection = null

func _has_valid_graph_dock() -> bool:
	return (
		graph_dock != null
		and is_instance_valid(graph_dock)
		and graph_dock_wrapper != null
		and is_instance_valid(graph_dock_wrapper)
	)

func _graph_dock_uses_bottom_slot() -> bool:
	if not _has_valid_graph_dock():
		return false
	return graph_dock_wrapper.default_slot == EditorDock.DOCK_SLOT_BOTTOM

func _graph_dock_is_on_bottom_panel() -> bool:
	var bottom_tabs := _find_editor_bottom_tab_container()
	return (
		bottom_tabs != null
		and graph_dock_wrapper.get_parent() == bottom_tabs
		and bottom_tabs.get_tab_idx_from_control(graph_dock_wrapper) >= 0
	)

func _remove_graph_dock() -> void:
	if graph_dock_wrapper != null and is_instance_valid(graph_dock_wrapper):
		remove_dock(graph_dock_wrapper)
		graph_dock_wrapper.queue_free()
	elif graph_dock != null and is_instance_valid(graph_dock):
		remove_control_from_bottom_panel(graph_dock)
		remove_control_from_docks(graph_dock)
		graph_dock.queue_free()
	graph_dock = null
	graph_dock_wrapper = null

func _create_graph_dock() -> void:
	var packed: PackedScene = load("res://addons/flow_nodes_editor/flow_editor.tscn")
	graph_dock = packed.instantiate() as Control
	var title := FlowI18n.t("Data Flow")
	graph_dock.name = title
	graph_dock_wrapper = FlowEditorDockScript.new()
	graph_dock_wrapper.title = title
	graph_dock_wrapper.layout_key = _FLOW_DOCK_LAYOUT_KEY
	graph_dock_wrapper.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	graph_dock_wrapper.available_layouts = (
		EditorDock.DOCK_LAYOUT_HORIZONTAL | EditorDock.DOCK_LAYOUT_FLOATING
	)
	graph_dock_wrapper.transient = false
	graph_dock_wrapper.global = false
	var editor_scale := EditorInterface.get_editor_scale()
	graph_dock_wrapper.custom_minimum_size = Vector2(460, 300) * editor_scale
	graph_dock_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_dock_wrapper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_dock_wrapper.add_child(graph_dock)
	add_dock(graph_dock_wrapper)
	call_deferred("_fit_graph_dock_in_wrapper")


func _fit_graph_dock_in_wrapper() -> void:
	if not _has_valid_graph_dock():
		return
	if graph_dock_wrapper.has_method("_apply_panel_fill_layout"):
		graph_dock_wrapper.call(
			"_apply_panel_fill_layout",
			EditorDock.DOCK_LAYOUT_HORIZONTAL
		)
	_schedule_place_graph_dock_after_shader()

func _schedule_place_graph_dock_after_shader() -> void:
	_bottom_dock_place_retries = 0
	call_deferred("_try_place_graph_dock_after_shader")

func _try_place_graph_dock_after_shader() -> void:
	if not is_instance_valid(graph_dock_wrapper):
		return
	if _place_graph_dock_after_shader_editor():
		return
	_bottom_dock_place_retries += 1
	if _bottom_dock_place_retries >= _BOTTOM_DOCK_PLACE_MAX_RETRIES:
		return
	get_tree().create_timer(_BOTTOM_DOCK_PLACE_RETRY_INTERVAL_SEC).timeout.connect(
		_try_place_graph_dock_after_shader,
		CONNECT_ONE_SHOT
	)

func _find_editor_bottom_tab_container() -> TabContainer:
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	return _find_editor_bottom_tab_container_under(base)


func _find_editor_bottom_tab_container_under(node: Node) -> TabContainer:
	if node is EditorDock and (node as EditorDock).icon_name == _SHADER_DOCK_ICON:
		var parent := node.get_parent()
		if parent is TabContainer:
			return parent as TabContainer
	for child in node.get_children():
		var found := _find_editor_bottom_tab_container_under(child)
		if found:
			return found
	return null


func _get_bottom_panel_tab_container() -> TabContainer:
	return _find_editor_bottom_tab_container()

func _find_shader_editor_bottom_tab_index(tab_container: TabContainer) -> int:
	for i in tab_container.get_tab_count():
		var tab_control := tab_container.get_tab_control(i)
		if tab_control is EditorDock and (tab_control as EditorDock).icon_name == _SHADER_DOCK_ICON:
			return i
		var tab_title := tab_container.get_tab_title(i)
		if tab_title == "Shader Editor" or tab_title == "着色器编辑器":
			return i
	return -1

func _move_editor_dock_to_tab_index(
	dock: EditorDock,
	tab_container: TabContainer,
	target_index: int
) -> void:
	target_index = clampi(target_index, 0, tab_container.get_tab_count() - 1)
	var anchor_tab := tab_container.get_tab_control(target_index)
	if anchor_tab == null:
		return
	tab_container.set_block_signals(true)
	tab_container.move_child(dock, anchor_tab.get_index(false))
	tab_container.set_block_signals(false)


func _place_graph_dock_after_shader_editor() -> bool:
	var tab_container := _get_bottom_panel_tab_container()
	if tab_container == null:
		return false
	var shader_idx := _find_shader_editor_bottom_tab_index(tab_container)
	if shader_idx < 0:
		return false
	if graph_dock_wrapper.get_parent() != tab_container:
		return false
	var flow_idx := tab_container.get_tab_idx_from_control(graph_dock_wrapper)
	if flow_idx < 0:
		return false
	var target_idx := shader_idx + 1
	if flow_idx != target_idx:
		_move_editor_dock_to_tab_index(graph_dock_wrapper, tab_container, target_idx)
	flow_idx = tab_container.get_tab_idx_from_control(graph_dock_wrapper)
	return flow_idx == target_idx

func _ensure_graph_dock() -> void:
	if graph_dock != null and is_instance_valid(graph_dock) and graph_dock_wrapper == null:
		_remove_graph_dock()
	if _has_valid_graph_dock() and not FlowEditorChrome.is_valid_layout(graph_dock):
		_remove_graph_dock()
	if _has_valid_graph_dock() and not _graph_dock_uses_bottom_slot():
		_remove_graph_dock()
	if not _has_valid_graph_dock():
		_create_graph_dock()
	elif not _graph_dock_is_on_bottom_panel():
		_schedule_place_graph_dock_after_shader()

func _enter_tree():
	print("Data Flow plugin enabled")
	_dock_layout_watch_started_ms = Time.get_ticks_msec()
	_ensure_graph_dock()
	selection = EditorInterface.get_selection()

	graph_input_inspector_plugin = load("res://addons/flow_nodes_editor/graph_input_parameter_inspector.gd").new()
	add_inspector_plugin(graph_input_inspector_plugin)
	node_settings_inspector_plugin = load("res://addons/flow_nodes_editor/node_settings_inspector_plugin.gd").new()
	add_inspector_plugin(node_settings_inspector_plugin)

	# Will refresh everytime the undo/redo subsystem saves a point
	undo_redo = get_undo_redo()
	undo_redo.history_changed.connect(_on_history_changed)
	graph_dock.undo_redo = undo_redo

	# Auto-detect file changes on disk (from git, agents, external editors)
	var efs = EditorInterface.get_resource_filesystem()
	if efs:
		efs.filesystem_changed.connect(_on_filesystem_changed)
		efs.resources_reimported.connect(_on_resources_reimported)

	if selection and not selection.selection_changed.is_connected(_selection_changed):
		selection.selection_changed.connect(_selection_changed)
	elif selection == null:
		push_warning("Data Flow: EditorSelection unavailable in _enter_tree; selection sync disabled until editor is ready.")

	set_process(true)


func _set_window_layout(_configuration: ConfigFile) -> void:
	call_deferred("_reconcile_graph_dock_after_editor_layout")


func _reconcile_graph_dock_after_editor_layout() -> void:
	_ensure_graph_dock()
	if not _has_valid_graph_dock():
		return
	if not _graph_dock_uses_bottom_slot() or not _graph_dock_is_on_bottom_panel():
		if not _graph_dock_uses_bottom_slot():
			_remove_graph_dock()
			_create_graph_dock()
		else:
			_schedule_place_graph_dock_after_shader()
	else:
		_schedule_place_graph_dock_after_shader()
	call_deferred("_fit_graph_dock_in_wrapper")


func _save_external_data():
	if _has_valid_graph_dock() and graph_dock.has_method("saveResource"):
		graph_dock.saveResource()

func _exit_tree():
	setWatchedNode(null)
	if undo_redo and undo_redo.history_changed.is_connected(_on_history_changed):
		undo_redo.history_changed.disconnect(_on_history_changed)
	var efs = EditorInterface.get_resource_filesystem()
	if efs:
		if efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)
		if efs.resources_reimported.is_connected(_on_resources_reimported):
			efs.resources_reimported.disconnect(_on_resources_reimported)
	if node_settings_inspector_plugin:
		remove_inspector_plugin(node_settings_inspector_plugin)
	if graph_input_inspector_plugin:
		remove_inspector_plugin(graph_input_inspector_plugin)
	#remove_inspector_plugin(inspector_plugin)
	if _has_valid_graph_dock():
		_remove_graph_dock()
	if data_inspector_dock and is_instance_valid(data_inspector_dock):
		remove_control_from_bottom_panel(data_inspector_dock)
		data_inspector_dock.queue_free()
		data_inspector_dock = null
	if selection and selection.selection_changed.is_connected(_selection_changed):
		selection.selection_changed.disconnect(_selection_changed)

func _ready():
	if selection == null:
		selection = EditorInterface.get_selection()
		if selection and not selection.selection_changed.is_connected(_selection_changed):
			selection.selection_changed.connect(_selection_changed)
	if selection:
		_selection_changed()

func _handles(object: Object) -> bool:
	return object is FlowGraphResource

func _edit(object: Object) -> void:
	var graph_resource := object as FlowGraphResource
	if graph_resource == null:
		return
	call_deferred("_open_flow_graph_resource_from_filesystem", graph_resource)

func _open_flow_graph_resource_from_filesystem(graph_resource: FlowGraphResource) -> void:
	if graph_resource == null:
		return
	_ensure_graph_dock()
	if not _has_valid_graph_dock():
		return
	_make_graph_dock_visible()
	if graph_resource.resource_path != "":
		await graph_dock._open_graph_file_with_loading(graph_resource.resource_path)
		return
	await graph_dock._set_resource_to_edit_with_loading(graph_resource, null)

func _make_graph_dock_visible() -> void:
	if not _has_valid_graph_dock():
		return
	var tab_container := graph_dock_wrapper.get_parent() as TabContainer
	if tab_container != null:
		var tab_index := tab_container.get_tab_idx_from_control(graph_dock_wrapper)
		if tab_index >= 0:
			tab_container.set_current_tab(tab_index)
	var window := graph_dock_wrapper.get_window()
	if window != null:
		window.grab_focus()
	graph_dock.grab_focus()

# This is called after the a new scene is loaded, but the 'selection' event of the new
# scene is called first.
func on_scene_changed(scene_root: Node) -> void:
	if not _has_valid_graph_dock() or scene_root == null:
		return
	if is_instance_valid(graph_dock.resource_owner):
		var node = graph_dock.resource_owner
		if scene_root and (node.get_owner() != scene_root and not scene_root.is_ancestor_of(node)):
			graph_dock.setResourceToEdit( null, null )

	# Auto activate the first flow node graph found in the scene
	for node in scene_root.get_children():
		var flow_node = node as FlowGraphNode3D
		if flow_node:
			graph_dock.setResourceToEdit( flow_node.graph, flow_node )
			break


func _selection_changed():
	if not _has_valid_graph_dock():
		return
	if selection == null:
		selection = EditorInterface.get_selection()
	if selection == null:
		return

	var scene_nodes = selection.get_selected_nodes()
	if not scene_nodes.is_empty():
		var scene_node = scene_nodes[0]
		if scene_node is FlowGraphNode3D:
			setWatchedNode( scene_node )
			graph_dock.setResourceToEdit( scene_node.graph, scene_node )
			return
	setWatchedNode( null )

func setWatchedNode( new_node ):
	#print( "setWatchedNode %s" % new_node )
	if current_watched_node:
		current_watched_node.graph_node_changed.disconnect( onSelectedGraphNodeChanged )
		current_watched_node = null
	if new_node:
		current_watched_node = new_node
		new_node.graph_node_changed.connect( onSelectedGraphNodeChanged )

func onSelectedGraphNodeChanged( node : FlowGraphNode3D, prop_name: String ):
	if not _has_valid_graph_dock():
		return
	print( "onSelectedGraphNodeChanged %s.%s" % [node.name, prop_name] )
	if prop_name == "graph_resource":
		print( "  -> %s" % [node.graph] )
		graph_dock.setResourceToEdit( node.graph, node )


func _on_history_changed( ):
	#print("Something changed in the editor (undo/redo history updated)")
	if _has_valid_graph_dock():
		graph_dock.onEditorSceneChanged()

func _process( elapsed : float ):
	_watch_graph_dock_bottom_placement()
	var scene_root = get_editor_interface().get_edited_scene_root()
	if scene_root != current_scene_root:
		current_scene_root = scene_root
		on_scene_changed(scene_root)

func _on_filesystem_changed():
	# Auto-reload current graph when files change on disk
	if _has_valid_graph_dock() and graph_dock.current_resource:
		graph_dock._on_filesystem_changed()

func _watch_graph_dock_bottom_placement() -> void:
	if Time.get_ticks_msec() - _dock_layout_watch_started_ms > _DOCK_LAYOUT_WATCH_MS:
		return
	if not _has_valid_graph_dock():
		return
	if not _graph_dock_is_on_bottom_panel():
		if _graph_dock_uses_bottom_slot():
			_schedule_place_graph_dock_after_shader()
		else:
			_remove_graph_dock()
			_create_graph_dock()
			_dock_layout_watch_started_ms = Time.get_ticks_msec()
		return
	if _place_graph_dock_after_shader_editor():
		return


func _on_resources_reimported(resources: PackedStringArray):
	# Check if any reimported resource is the current graph or a subgraph
	if _has_valid_graph_dock() and graph_dock.current_resource:
		var current_path = graph_dock.current_resource.resource_path
		for res_path in resources:
			if res_path == current_path or res_path.ends_with(".tres"):
				graph_dock._on_filesystem_changed()
				return
