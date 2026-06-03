@tool
extends Control
class_name FlowEditor

# This is the main container of the DataFlow Graph Editor

var current_resource: FlowGraphResource
var resource_owner : FlowGraphNode3D
var ctx := FlowData.EvaluationContext.new()
var regen_pending := false
var regen_running := false
var regen_requested_while_running := false
var regen_run_id := 0
var save_pending := false
var save_pending_delay := 0.0
var auto_regen := true
var dump_performance := false
var use_native_graph_grid := false

@onready var gedit : GraphEdit = %GraphEdit
@onready var data_inspector : Control
@onready var info : Label = %FlowStatusLabel
@onready var open_graph_button: Button = $VBoxContainer/TabBarPanel/TabBarRow/ButtonOpenGraph
@onready var tab_bar: TabBar = $VBoxContainer/TabBarPanel/TabBarRow/TabBar
@onready var expand_graph_button: Button = $VBoxContainer/TabBarPanel/TabBarRow/ButtonExpandGraph
@onready var toolbar_hbox: HBoxContainer = $VBoxContainer/ScrollContainer/HBoxContainer

var _chrome_refs: FlowEditorChrome.Refs

# The inspector shows the settings property of the current node
var inspector: FlowInspector
var inspected_node : Node
var make_inspector_visible : Callable
var search_add_node_popup: SearchAddNodePopup
var custom_graph_grid

# This is the default graph-node instantiated, the script contains the logic
var packed_node = preload("res://addons/flow_nodes_editor/node.tscn")
const directory_path := FlowNodeRegistry.DEFAULT_NODE_DIRECTORY
const FAST_GRAPH_LOAD_NODE_THRESHOLD := 24
const EDITOR_SETTING_AUTO_REGEN := "addons/flow_nodes_editor/auto_generate"
const EDITOR_SETTING_NATIVE_GRAPH_GRID := "addons/flow_nodes_editor/use_native_graph_grid"
const EDITOR_SETTING_HIDE_INSPECTOR_TITLE := "addons/flow_nodes_editor/hide_inspector_title"
const EDITOR_SETTING_TRACK_EXTERNAL_EDITS := "addons/flow_nodes_editor/track_external_edits"

# New nodes generation using the editor
var local_drop_position : Vector2 = Vector2(0,0)
var auto_connect_from_node : String
var auto_connect_from_port : int
var auto_connect_to_node : String
var auto_connect_to_port : int
var new_name_counter : int = 0

# Ranges for the menu
var min_id = 1000
var max_id = min_id
var menu_ids : Dictionary = {}

var comment_padding = Vector2( 40, 40 )

# Required during evaluation
var gedit_nodes_by_name = {}
var input_sources := {} # key: Pair(to_node, to_port) -> value: Array[(from_node, from_port)]

# Activate connections and nodes
var active_intensity = 0.0
var active_nodes = []

var undo_redo: EditorUndoRedoManager
var drag_start_snapshot : Dictionary = {}
var suppress_next_editor_scene_changed := false
var color_nodes : bool = true
var hide_inspector_title : bool = false
var track_external_edits : bool = true

var ui_scale = 1.0
var node_types = { }
var node_registry_version := -1

var popup_menu_inputs : PopupMenu
var popup_menu_outputs : PopupMenu
var popup_on_over_input = null
const IDM_PROMOTE_TO_PARAMETER : int = 100
const IDM_COLLAPSE_TO_SUBGRAPH : int = 200
const IDM_FRAME_ADD_SELECTED_NODES : int = 300
const IDM_FRAME_REMOVE_SELECTED_NODES : int = 301
const RIGHT_DRAG_PAN_THRESHOLD := 4.0
const SAVE_DEBOUNCE_SECONDS := 0.35
const AUTO_REGEN_FRAME_BUDGET_USEC := 5000
const EDITOR_DYNAMIC_UI_META := &"flow_editor_dynamic_ui"
var right_drag_pan_active := false
var right_drag_pan_moved := false
var right_drag_pan_start_position := Vector2.ZERO
var right_drag_pan_start_scroll := Vector2.ZERO
var suppress_next_popup_request := false
var status_counts_dirty := true
var status_nodes_count := 0
var status_wires_count := 0
var data_inspector_refresh_pending := false

var open_tabs: Array[Dictionary] = []
var active_tab_index: int = -1
var open_file_dialog: EditorFileDialog
var save_file_dialog: EditorFileDialog
var unsaved_close_dialog: AcceptDialog
var analyze_panel: Control
var current_analyzed_node: FlowNodeBase
var last_graph_open_dir := "res://graphs"
var graph_loading_overlay: PanelContainer
var graph_loading_label: Label
var graph_loading_bar: ProgressBar
var graph_loading_sweep_container: Control
var graph_loading_sweep: ColorRect
var graph_loading_message := ""
var graph_loading_target_value := 0.0
var graph_loading_display_value := 0.0
var graph_loading_sweep_offset := 0.0
var graph_reload_in_progress := false
var _variable_link_flash_tweens: Dictionary = {}
const VARIABLE_LINK_FLASH_UP_SEC := 0.1
const VARIABLE_LINK_FLASH_DOWN_SEC := 0.1
const VARIABLE_LINK_FLASH_COUNT := 2

func _active_tab_is_valid() -> bool:
	return active_tab_index >= 0 and active_tab_index < open_tabs.size()

func _is_tab_dirty(index: int) -> bool:
	if index < 0 or index >= open_tabs.size():
		return false
	return bool(open_tabs[index].get("dirty", false))

func _set_tab_dirty(index: int, dirty: bool) -> void:
	if index < 0 or index >= open_tabs.size():
		return
	open_tabs[index]["dirty"] = dirty
	_update_tab_titles()

func _set_current_graph_dirty(dirty: bool) -> void:
	if _active_tab_is_valid():
		_set_tab_dirty(active_tab_index, dirty)

func ensureCurrentResource() -> FlowGraphResource:
	if current_resource:
		return current_resource

	var new_resource := FlowGraphResource.new()
	new_resource.resource_name = "Untitled"
	setResourceToEdit(new_resource, null)
	return current_resource

## Node3DEditorViewport::VIEW_CENTER_TO_SELECTION (node_3d_editor_plugin.h)
const SPATIAL_VIEW_CENTER_TO_SELECTION := 7
const VIEWPORT_FOCUS_MARKER_NAME := &"__FlowEditorViewportFocus"

var _viewport_focus_marker: Marker3D
var _pending_focus_world_position := Vector3.ZERO
var _focus_restore_selection: Array[Node] = []

## Moves the 3D editor orbit pivot to [param world_position] while keeping view direction and distance.
## Engine path: focus_selection() sets cursor.pos only (distance unchanged). See node_3d_editor_plugin.cpp.
func focus_viewport_on_point(world_position: Vector3) -> bool:
	if not Engine.is_editor_hint():
		return false
	if not world_position.is_finite():
		return false
	EditorInterface.set_main_screen_editor("3D")
	_pending_focus_world_position = world_position
	call_deferred("_deferred_begin_viewport_focus")
	return true

func _deferred_begin_viewport_focus() -> void:
	var marker := _ensure_viewport_focus_marker(_pending_focus_world_position)
	if marker == null:
		call_deferred("_deferred_apply_viewport_focus_without_selection")
		return
	var selection := EditorInterface.get_selection()
	if selection == null:
		call_deferred("_deferred_apply_viewport_focus_without_selection")
		return
	_focus_restore_selection = selection.get_selected_nodes()
	selection.clear()
	selection.add_node(marker)
	call_deferred("_deferred_apply_viewport_focus")

func _deferred_apply_viewport_focus_without_selection() -> void:
	_focus_viewport_via_camera_basis(_pending_focus_world_position)


func _deferred_apply_viewport_focus() -> void:
	if not _invoke_spatial_editor_focus_selection():
		_focus_viewport_via_camera_basis(_pending_focus_world_position)
		call_deferred("_deferred_finish_viewport_focus")
	else:
		call_deferred("_deferred_verify_viewport_focus_alignment")


func _deferred_verify_viewport_focus_alignment() -> void:
	var measure := mcp_measure_focus_alignment(_pending_focus_world_position)
	if float(measure.get("alignment_error", 0.0)) > 2.0:
		_focus_viewport_via_camera_basis(_pending_focus_world_position)
	call_deferred("_deferred_finish_viewport_focus")

func _deferred_finish_viewport_focus() -> void:
	var selection := EditorInterface.get_selection()
	if selection == null:
		_focus_restore_selection.clear()
		return
	selection.clear()
	for node in _focus_restore_selection:
		if is_instance_valid(node):
			selection.add_node(node)
	_focus_restore_selection.clear()

func _ensure_viewport_focus_marker(world_position: Vector3) -> Marker3D:
	var parent: Node = find_debug_world_node()
	if parent == null:
		parent = EditorInterface.get_edited_scene_root()
	if parent == null:
		return null
	if _viewport_focus_marker == null or not is_instance_valid(_viewport_focus_marker):
		var existing := parent.get_node_or_null(NodePath(str(VIEWPORT_FOCUS_MARKER_NAME)))
		if existing is Marker3D:
			_viewport_focus_marker = existing
		else:
			_viewport_focus_marker = Marker3D.new()
			_viewport_focus_marker.name = String(VIEWPORT_FOCUS_MARKER_NAME)
			parent.add_child(_viewport_focus_marker)
			if Engine.is_editor_hint() and parent == EditorInterface.get_edited_scene_root():
				_viewport_focus_marker.owner = parent
	_viewport_focus_marker.visible = false
	_viewport_focus_marker.global_position = world_position
	return _viewport_focus_marker

func _invoke_spatial_editor_focus_selection() -> bool:
	var spatial_viewport := _find_visible_spatial_editor_viewport()
	if spatial_viewport == null:
		return false
	# focus_selection is not exposed to ClassDB; _menu_option(VIEW_CENTER_TO_SELECTION) is the F-key path.
	if spatial_viewport.has_method("_menu_option"):
		spatial_viewport.call("_menu_option", SPATIAL_VIEW_CENTER_TO_SELECTION)
		return true
	var surface := _find_spatial_viewport_surface(spatial_viewport)
	if surface == null:
		return false
	surface.grab_focus()
	var shortcut: Shortcut = EditorInterface.get_editor_settings().get_shortcut("spatial_editor/focus_selection")
	if shortcut == null:
		return false
	for event in shortcut.events:
		if event is InputEventKey:
			var pressed_event := event.duplicate() as InputEventKey
			pressed_event.pressed = true
			surface.gui_input.emit(pressed_event)
			var released_event := event.duplicate() as InputEventKey
			released_event.pressed = false
			surface.gui_input.emit(released_event)
			return true
	return false

## Fallback when selection focus is unavailable: preserve camera basis, estimate orbit depth to target.
func _focus_viewport_via_camera_basis(world_position: Vector3) -> void:
	var camera := _get_active_spatial_editor_camera()
	if camera == null:
		return
	var xf := camera.global_transform
	var z_axis := xf.basis.z
	var distance := (xf.origin - world_position).dot(z_axis)
	if distance < 0.5:
		distance = maxf(8.0, xf.origin.distance_to(world_position))
	camera.global_transform = Transform3D(xf.basis, world_position + z_axis * distance)

## MCP / tests: read spatial editor camera and estimated orbit pivot.
func mcp_get_spatial_editor_camera_state() -> Dictionary:
	if not Engine.is_editor_hint():
		return {"ok": false, "error": "editor only"}
	var camera := _get_active_spatial_editor_camera()
	if camera == null:
		return {"ok": false, "error": "no editor camera"}
	var xf := camera.global_transform
	return {
		"ok": true,
		"camera_origin": xf.origin,
		"camera_basis_z": xf.basis.z,
		"camera_basis_y": xf.basis.y,
	}

## MCP: queue focus; call [method mcp_measure_focus_alignment] after ~2 editor frames.
func mcp_focus_point_and_measure(world_position: Vector3) -> Dictionary:
	if not world_position.is_finite():
		return {"ok": false, "error": "invalid position"}
	var before := mcp_get_spatial_editor_camera_state()
	var invoked := focus_viewport_on_point(world_position)
	return {
		"ok": invoked,
		"target": world_position,
		"before": before,
		"note": "Call mcp_measure_focus_alignment with the same target after two process frames.",
	}

func mcp_measure_focus_alignment(target: Vector3) -> Dictionary:
	var camera := _get_active_spatial_editor_camera()
	if camera == null:
		return {"ok": false, "error": "no editor camera"}
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if viewport == null:
		return {"ok": false, "error": "no editor viewport"}
	var center := viewport.size * 0.5
	var ray_origin := camera.project_ray_origin(center)
	var ray_dir := camera.project_ray_normal(center)
	var closest := ray_origin + ray_dir * ray_dir.dot(target - ray_origin)
	var alignment_error := closest.distance_to(target)
	var depth := (camera.global_position - target).dot(camera.global_transform.basis.z)
	return {
		"ok": true,
		"target": target,
		"alignment_error": alignment_error,
		"orbit_depth": depth,
		"camera_origin": camera.global_position,
	}


## MCP: populate Analyze panel from existing eval results without running evalGraph() again.
func mcp_show_analyze_for_node(node: FlowNodeBase) -> Dictionary:
	if node == null:
		return {"ok": false, "error": "missing node"}
	if not data_inspector:
		return {"ok": false, "error": "data_inspector missing"}
	var prev_auto_regen := auto_regen
	auto_regen = false
	data_inspector.setNode(null)
	data_inspector.setNode(node)
	node.refreshFromSettings()
	_set_analyze_panel_visible(true)
	current_analyzed_node = node
	auto_regen = prev_auto_regen
	regen_pending = false
	data_inspector.refresh()
	return {
		"ok": true,
		"node_name": node.name,
		"visible_rows": data_inspector.visible_rows.size(),
	}

func _get_active_spatial_editor_camera() -> Camera3D:
	var spatial_viewport := _find_visible_spatial_editor_viewport()
	if spatial_viewport != null and spatial_viewport.has_method("get_camera_3d"):
		var viewport_camera: Camera3D = spatial_viewport.get_camera_3d()
		if viewport_camera != null:
			return viewport_camera
	for idx in range(4):
		var subviewport := EditorInterface.get_editor_viewport_3d(idx)
		if subviewport == null:
			continue
		var camera := subviewport.get_camera_3d()
		if camera != null:
			return camera
	return null

func _find_visible_spatial_editor_viewport() -> Node:
	var root := EditorInterface.get_editor_main_screen()
	return _find_visible_spatial_editor_viewport_descendant(root)

func _find_visible_spatial_editor_viewport_descendant(root: Node) -> Node:
	if root.get_class() == "Node3DEditorViewport" and (root as Control).is_visible_in_tree():
		return root
	for child in root.get_children():
		var match := _find_visible_spatial_editor_viewport_descendant(child)
		if match != null:
			return match
	return null

func _find_spatial_viewport_surface(spatial_viewport: Node) -> Control:
	var children := spatial_viewport.get_children()
	if children.size() >= 2 and children[1] is Control:
		return children[1] as Control
	return null

func _find_editor_node_by_class(node_class: String) -> Node:
	var main_screen := EditorInterface.get_editor_main_screen()
	var found := _find_descendant_by_class(main_screen, node_class)
	if found:
		return found
	var root := EditorInterface.get_base_control()
	while root.get_parent():
		root = root.get_parent()
	return _find_descendant_by_class(root, node_class)

func _find_descendant_by_class(root: Node, node_class: String) -> Node:
	if root.get_class() == node_class:
		return root
	for child in root.get_children():
		var match := _find_descendant_by_class(child, node_class)
		if match:
			return match
	return null

func find_debug_world_node() -> Node3D:
	if resource_owner != null and resource_owner is Node3D:
		return resource_owner
	if not Engine.is_editor_hint():
		return null
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root is Node3D:
		return scene_root
	if scene_root == null:
		return null
	for candidate in scene_root.find_children("*", "Node3D", true, false):
		var node3d := candidate as Node3D
		if node3d != null:
			return node3d
	return null


func setResourceToEdit( new_resource : FlowGraphResource, new_resource_owner : FlowGraphNode3D ):
	if new_resource == null:
		# Selection cleared or scene changed. We save the current active resource,
		# but keep the open tabs intact for editing convenience.
		if current_resource:
			saveResource()
		return
		
	# Check if this resource is already open in a tab
	var found_idx = -1
	for i in range(open_tabs.size()):
		if open_tabs[i].resource == new_resource:
			found_idx = i
			break
			
	if found_idx != -1:
		if active_tab_index == found_idx:
			# If it's already active, update owner if a new one is selected
			if new_resource_owner != null:
				resource_owner = new_resource_owner
				open_tabs[found_idx].owner = new_resource_owner
				ctx.owner = new_resource_owner
			return
		_switch_to_tab(found_idx, new_resource_owner)
	else:
		# Save current tab before opening a new one
		if current_resource:
			saveResource()
			
		var tab_title = "New Graph"
		if new_resource.resource_path != "":
			tab_title = new_resource.resource_path.get_file()
		elif new_resource_owner:
			tab_title = new_resource_owner.name
			
		open_tabs.append({
			"resource": new_resource,
			"owner": new_resource_owner,
			"dirty": false
		})
		_sync_tab_bar_from_open_tabs()
		_switch_to_tab(open_tabs.size() - 1, new_resource_owner)

func _switch_to_tab(index: int, new_owner = null):
	if index < 0 or index >= open_tabs.size():
		return
		
	# Disconnect from old resource in_params_changed
	if current_resource and current_resource.in_params_changed.is_connected(_on_in_params_changed):
		current_resource.in_params_changed.disconnect(_on_in_params_changed)
		
	active_tab_index = index
	
	# Reload the resource from disk to pick up any external changes (agents, git, etc.)
	var tab_resource = open_tabs[index].resource
	var refreshed = _reload_resource_from_disk(tab_resource)
	if refreshed != tab_resource:
		open_tabs[index].resource = refreshed
	current_resource = open_tabs[index].resource
	
	# Connect to new resource in_params_changed
	if current_resource and not current_resource.in_params_changed.is_connected(_on_in_params_changed):
		current_resource.in_params_changed.connect(_on_in_params_changed)
	
	if new_owner != null:
		open_tabs[index].owner = new_owner
	resource_owner = open_tabs[index].owner
	
	_clear_ui_nodes()
	
	scanAvailableNodesIfNeeded()
	FlowNodeIO.loadFromResource( self )
	
	ctx.graph = current_resource
	ctx.owner = resource_owner
	ctx.gedit_nodes_by_name = gedit_nodes_by_name
	markAllNodesAsDirty()
	queueRegen()
	populatePopupInputsMenu()
	
	tab_bar.current_tab = index
	_update_tab_titles()
	
	if inspector:
		inspector.edit(null)
		
	update_status_bar()

func _on_tab_changed(index: int):
	if index >= 0 and index < open_tabs.size() and index != active_tab_index:
		if current_resource:
			saveResource()
		_switch_to_tab(index)

func _on_tab_close_pressed(index: int):
	if index >= 0 and index < open_tabs.size():
		if _is_tab_dirty(index):
			_show_unsaved_close_warning(index)
			return

		var closed_active = (index == active_tab_index)
		if closed_active and current_resource:
			saveResource()
			
		var tab_res = open_tabs[index].resource
		if tab_res and tab_res.in_params_changed.is_connected(_on_in_params_changed):
			tab_res.in_params_changed.disconnect(_on_in_params_changed)
			
		open_tabs.remove_at(index)
		_sync_tab_bar_from_open_tabs()
		
		if open_tabs.is_empty():
			current_resource = null
			resource_owner = null
			active_tab_index = -1
			_clear_ui_nodes()
			ensureCurrentResource()
		else:
			if closed_active:
				var new_idx = clamp(index - 1, 0, open_tabs.size() - 1)
				_switch_to_tab(new_idx)
			else:
				if active_tab_index > index:
					active_tab_index -= 1

func _clear_ui_nodes() -> void:
	clear_graph()
	_ensure_inspector()
	if inspector:
		inspector.edit(null)

func _refresh_active_tab_resource_from_disk() -> void:
	if not _active_tab_is_valid() or current_resource == null:
		return
	var refreshed := _reload_resource_from_disk(current_resource)
	if refreshed == current_resource:
		return
	open_tabs[active_tab_index].resource = refreshed
	current_resource = refreshed
	if not current_resource.in_params_changed.is_connected(_on_in_params_changed):
		current_resource.in_params_changed.connect(_on_in_params_changed)

func _update_tab_titles():
	if tab_bar == null:
		return
	for i in range(open_tabs.size()):
		var tab_res = open_tabs[i].resource
		var tab_title = FlowI18n.t("Untitled")
		if is_instance_valid(tab_res) and tab_res.resource_path != "":
			tab_title = tab_res.resource_path.get_file()
		elif open_tabs[i].owner:
			tab_title = open_tabs[i].owner.name
		elif is_instance_valid(tab_res) and tab_res.resource_path == "":
			tab_title = FlowI18n.t("Untitled / Unsaved")
		if _is_tab_dirty(i):
			tab_title = "* " + tab_title
		tab_bar.set_tab_title(i, tab_title)

func _on_button_open_pressed():
	if not open_file_dialog:
		open_file_dialog = EditorFileDialog.new()
		open_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		open_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		open_file_dialog.add_filter("*.tres", "Flow Graph Resource")
		open_file_dialog.add_filter("*.res", "Flow Graph Resource")
		open_file_dialog.file_selected.connect(_on_graph_file_selected)
		add_child(open_file_dialog)
	open_file_dialog.current_dir = last_graph_open_dir
	open_file_dialog.popup_centered_ratio(0.4)

func _show_save_graph_dialog():
	if not save_file_dialog:
		save_file_dialog = EditorFileDialog.new()
		save_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		save_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		save_file_dialog.add_filter("*.tres", "Flow Graph Resource")
		save_file_dialog.add_filter("*.res", "Flow Graph Resource")
		save_file_dialog.file_selected.connect(_on_graph_save_file_selected)
		add_child(save_file_dialog)
	save_file_dialog.current_dir = last_graph_open_dir
	save_file_dialog.current_file = "untitled_flow_graph.tres"
	save_file_dialog.popup_centered_ratio(0.4)

func _show_unsaved_close_warning(index: int):
	if not unsaved_close_dialog:
		unsaved_close_dialog = AcceptDialog.new()
		unsaved_close_dialog.title = FlowI18n.t("Unsaved Resource")
		add_child(unsaved_close_dialog)
	var title := FlowI18n.t("Untitled / Unsaved")
	if index >= 0 and index < open_tabs.size():
		var tab_res = open_tabs[index].resource
		if is_instance_valid(tab_res) and tab_res.resource_path != "":
			title = tab_res.resource_path.get_file()
	unsaved_close_dialog.dialog_text = FlowI18n.t("Save the graph before closing it:") + "\n" + title
	unsaved_close_dialog.popup_centered()

func _on_graph_file_selected(path: String):
	await _open_graph_file_with_loading(path)

func _on_graph_save_file_selected(path: String):
	_save_current_resource_to_path(path)

func _open_graph_file_with_loading(path: String) -> void:
	_set_graph_loading_progress("Opening Graph...", 5.0)
	await get_tree().process_frame
	_set_graph_loading_progress("Loading Resource...", 18.0)
	var res = ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_REPLACE)
	if res is FlowGraphResource:
		last_graph_open_dir = path.get_base_dir()
		await _set_resource_to_edit_with_loading(res, null)
		_set_graph_loading_progress("Graph Loaded", 100.0)
		await get_tree().process_frame
		_hide_graph_loading()
	else:
		_hide_graph_loading()
		update_status_bar(FlowI18n.t("Selected resource is not a FlowGraphResource"))
		push_error("Selected resource is not a FlowGraphResource!")

func _set_resource_to_edit_with_loading(new_resource: FlowGraphResource, new_resource_owner: FlowGraphNode3D) -> void:
	if new_resource == null:
		if current_resource:
			_set_graph_loading_progress("Saving Current Graph...", 24.0)
			saveResource()
		return

	var found_idx := -1
	for i in range(open_tabs.size()):
		if open_tabs[i].resource == new_resource:
			found_idx = i
			break

	if found_idx != -1:
		if active_tab_index == found_idx:
			if new_resource_owner != null:
				resource_owner = new_resource_owner
				open_tabs[found_idx].owner = new_resource_owner
				ctx.owner = new_resource_owner
			return
		await _switch_to_tab_with_loading(found_idx, new_resource_owner)
		return

	if current_resource:
		_set_graph_loading_progress("Saving Current Graph...", 24.0)
		saveResource()

	var tab_title := "New Graph"
	if new_resource.resource_path != "":
		tab_title = new_resource.resource_path.get_file()
	elif new_resource_owner:
		tab_title = new_resource_owner.name

	open_tabs.append({
		"resource": new_resource,
		"owner": new_resource_owner,
		"dirty": false
	})
	_sync_tab_bar_from_open_tabs()
	await _switch_to_tab_with_loading(open_tabs.size() - 1, new_resource_owner)

func _switch_to_tab_with_loading(index: int, new_owner = null) -> void:
	if index < 0 or index >= open_tabs.size():
		return

	if current_resource and current_resource.in_params_changed.is_connected(_on_in_params_changed):
		current_resource.in_params_changed.disconnect(_on_in_params_changed)

	active_tab_index = index

	_set_graph_loading_progress("Refreshing Resource...", 28.0)
	var tab_resource = open_tabs[index].resource
	var refreshed = _reload_resource_from_disk(tab_resource)
	if refreshed != tab_resource:
		open_tabs[index].resource = refreshed
	current_resource = open_tabs[index].resource

	if current_resource and not current_resource.in_params_changed.is_connected(_on_in_params_changed):
		current_resource.in_params_changed.connect(_on_in_params_changed)

	if new_owner != null:
		open_tabs[index].owner = new_owner
	resource_owner = open_tabs[index].owner

	_set_graph_loading_progress("Clearing Graph...", 34.0)
	_clear_ui_nodes()

	_set_graph_loading_progress("Scanning Nodes...", 42.0)
	scanAvailableNodesIfNeeded()

	var use_fast_graph_load := _should_use_fast_graph_load(current_resource)
	if use_fast_graph_load:
		FlowNodeIO.loadFromResource(self)
	else:
		await FlowNodeIO.loadFromResourceWithProgress(self, Callable(self, "_set_graph_loading_progress"))

	_set_graph_loading_progress("Finalizing Graph...", 96.0)
	ctx.graph = current_resource
	ctx.owner = resource_owner
	ctx.gedit_nodes_by_name = gedit_nodes_by_name
	markAllNodesAsDirty()
	queueRegen()
	populatePopupInputsMenu()
	populatePopupOutputsMenu()

	tab_bar.current_tab = index
	_update_tab_titles()

	if inspector:
		inspector.edit(null)

	update_status_bar()

func _setup_graph_loading_overlay() -> void:
	if graph_loading_overlay != null and is_instance_valid(graph_loading_overlay):
		return
	var existing := get_node_or_null("GraphLoadingOverlay") as PanelContainer
	if existing:
		graph_loading_overlay = existing
		return
	graph_loading_overlay = PanelContainer.new()
	graph_loading_overlay.name = "GraphLoadingOverlay"
	graph_loading_overlay.visible = false
	graph_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	graph_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph_loading_overlay.z_index = 100

	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.04, 0.05, 0.08, 0.72)
	graph_loading_overlay.add_theme_stylebox_override("panel", overlay_style)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph_loading_overlay.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 88)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("171a24")
	card_style.border_color = Color("22d3ee")
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.set_corner_radius_all(4)
	card_style.content_margin_left = 18
	card_style.content_margin_right = 18
	card_style.content_margin_top = 14
	card_style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	graph_loading_label = Label.new()
	graph_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	graph_loading_label.add_theme_font_size_override("font_size", 12)
	graph_loading_label.add_theme_color_override("font_color", Color("e5e7eb"))
	box.add_child(graph_loading_label)

	graph_loading_bar = ProgressBar.new()
	graph_loading_bar.min_value = 0.0
	graph_loading_bar.max_value = 100.0
	graph_loading_bar.value = 0.0
	graph_loading_bar.show_percentage = false
	graph_loading_bar.custom_minimum_size = Vector2(320, 12)
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color("0b1020")
	bar_background.set_corner_radius_all(3)
	graph_loading_bar.add_theme_stylebox_override("background", bar_background)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("22d3ee")
	bar_fill.set_corner_radius_all(3)
	graph_loading_bar.add_theme_stylebox_override("fill", bar_fill)

	graph_loading_sweep_container = Control.new()
	graph_loading_sweep_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_loading_sweep_container.clip_contents = true
	graph_loading_sweep_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph_loading_bar.add_child(graph_loading_sweep_container)

	graph_loading_sweep = ColorRect.new()
	graph_loading_sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_loading_sweep.color = Color(1.0, 1.0, 1.0, 0.34)
	graph_loading_sweep_container.add_child(graph_loading_sweep)
	box.add_child(graph_loading_bar)

	add_child(graph_loading_overlay)

func _set_graph_loading_progress(message: String, value: float) -> void:
	if graph_loading_overlay == null:
		return
	graph_loading_message = message
	graph_loading_target_value = clampf(value, 0.0, 100.0)
	if not graph_loading_overlay.visible:
		graph_loading_display_value = 0.0
		graph_loading_sweep_offset = 0.0
		graph_loading_bar.value = 0.0
	graph_loading_overlay.visible = true
	graph_loading_overlay.move_to_front()
	_update_graph_loading_animation(0.0)

func _should_use_fast_graph_load(resource: FlowGraphResource) -> bool:
	return _count_graph_nodes(resource) <= FAST_GRAPH_LOAD_NODE_THRESHOLD

func _count_graph_nodes(resource: FlowGraphResource) -> int:
	if resource == null or resource.data == null or resource.data.is_empty():
		return 0
	var nodes = resource.data.get("nodes", null)
	if nodes == null:
		return 0
	return nodes.size()

func _hide_graph_loading() -> void:
	if graph_loading_overlay:
		graph_loading_overlay.visible = false
	graph_loading_message = ""
	graph_loading_target_value = 0.0
	graph_loading_display_value = 0.0
	graph_loading_sweep_offset = 0.0

func _update_graph_loading_animation(delta: float) -> void:
	if graph_loading_overlay == null or not graph_loading_overlay.visible:
		return

	var target := graph_loading_target_value
	if target < 100.0 and graph_loading_display_value >= target - 0.1:
		target = minf(target + 12.0, 96.0)

	var speed := 18.0
	if graph_loading_display_value < graph_loading_target_value:
		speed = maxf(18.0, absf(graph_loading_target_value - graph_loading_display_value) * 6.0)
	graph_loading_display_value = move_toward(graph_loading_display_value, target, speed * delta)
	graph_loading_bar.value = graph_loading_display_value
	graph_loading_label.text = "%s  %d%%" % [FlowI18n.t(graph_loading_message), int(round(graph_loading_display_value))]
	_update_graph_loading_sweep(delta)

func _update_graph_loading_sweep(delta: float) -> void:
	if graph_loading_sweep_container == null or graph_loading_sweep == null:
		return

	var bar_size := graph_loading_bar.size
	var fill_width := bar_size.x * graph_loading_display_value / 100.0
	graph_loading_sweep_container.position = Vector2.ZERO
	graph_loading_sweep_container.size = Vector2(fill_width, bar_size.y)
	if fill_width <= 2.0:
		graph_loading_sweep.visible = false
		return

	graph_loading_sweep.visible = true
	var sweep_width := clampf(bar_size.x * 0.22, 42.0, 92.0)
	graph_loading_sweep.size = Vector2(sweep_width, bar_size.y)
	graph_loading_sweep_offset = fposmod(graph_loading_sweep_offset + maxf(bar_size.x * 0.85, 180.0) * delta, fill_width + sweep_width)
	graph_loading_sweep.position = Vector2(graph_loading_sweep_offset - sweep_width, 0.0)

## Reloads a FlowGraphResource from disk if it has a valid path, bypassing cache.
## Returns the refreshed resource, or the original if it has no path (unsaved).
func _reload_resource_from_disk(res: FlowGraphResource) -> FlowGraphResource:
	if res == null or res.resource_path == "":
		return res
	if not ResourceLoader.exists(res.resource_path):
		return res
	var fresh = ResourceLoader.load(res.resource_path, "Resource", ResourceLoader.CACHE_MODE_REPLACE)
	if fresh is FlowGraphResource:
		return fresh
	return res

func _sync_open_tabs_from_disk() -> bool:
	var active_tab_changed := false
	for i in range(open_tabs.size()):
		var tab_res: FlowGraphResource = open_tabs[i].resource
		if tab_res == null or tab_res.resource_path == "":
			continue
		var refreshed := _reload_resource_from_disk(tab_res)
		if refreshed == tab_res:
			continue
		open_tabs[i].resource = refreshed
		if i == active_tab_index:
			current_resource = refreshed
			active_tab_changed = true
	return active_tab_changed

## Called by plugin.gd when EditorFileSystem detects files changed on disk.
## Reloads open graph tabs when [member track_external_edits] is enabled.
func _on_filesystem_changed():
	if not track_external_edits:
		return

	var resource_stale := _sync_open_tabs_from_disk()
	if resource_stale and current_resource:
		if not current_resource.in_params_changed.is_connected(_on_in_params_changed):
			current_resource.in_params_changed.connect(_on_in_params_changed)

	# Check for modified scripts
	var scripts_changed := false
	for type_name in node_types:
		var meta = node_types[type_name]
		if meta.has("full_res_path"):
			var current_mtime = FileAccess.get_modified_time(meta.full_res_path)
			var last_mtime = meta.get("last_modified_time", 0)
			if current_mtime != last_mtime:
				print("[DataFlow] Node script changed on disk: %s. Reloading..." % meta.full_res_path)
				var loaded_class : Script = ResourceLoader.load(meta.full_res_path, "Script", ResourceLoader.CACHE_MODE_REPLACE) as Script
				if loaded_class:
					loaded_class.reload(true)
					var instance = loaded_class.new()
					var flow_node = instance as FlowNodeBase
					if flow_node:
						var new_meta = flow_node.getMeta()
						new_meta.factory = loaded_class
						new_meta.full_res_path = meta.full_res_path
						new_meta.last_modified_time = current_mtime
						node_types[type_name] = new_meta
						flow_node.free()
						scripts_changed = true
					else:
						instance.free()

	if resource_stale:
		# Rebuild the UI from the fresh resource
		_clear_ui_nodes()
		scanAvailableNodes(true)
		FlowNodeIO.loadFromResource(self)
		ctx.graph = current_resource
		ctx.owner = resource_owner
		ctx.gedit_nodes_by_name = gedit_nodes_by_name
		markAllNodesAsDirty()
		queueRegen()
		populatePopupInputsMenu()
		update_status_bar()
		print("[DataFlow] Auto-reloaded graph from disk: %s" % current_resource.resource_path)
	elif scripts_changed:
		# Surgical hot-swap: update metadata on existing nodes and trigger regen
		for child in gedit.get_children():
			var node = child as FlowNodeBase
			if node and node_types.has(node.node_template):
				# Re-bind the factory script and copy new metadata
				node.set_script(node_types[node.node_template].factory)
				node.meta_node = node_types[node.node_template].duplicate()
				node.meta_node.erase("factory")
				node.initFromScript()
				node.refreshFromSettings()
		markAllNodesAsDirty()
		queueRegen()
		update_status_bar()
		print("[DataFlow] Successfully hot-swapped updated scripts.")


func saveResource():
	FlowNodeIO.saveToResource( self )
	save_pending = false
	save_pending_delay = 0.0

func _save_current_resource_to_path(path: String) -> bool:
	if not current_resource:
		return false
	saveResource()
	var save_path := path
	if save_path.get_extension().is_empty():
		save_path += ".tres"
	var err := ResourceSaver.save(current_resource, save_path)
	if err == OK:
		current_resource.take_over_path(save_path)
		last_graph_open_dir = save_path.get_base_dir()
		_set_current_graph_dirty(false)
		update_status_bar(FlowI18n.t("Saved Resource"))
		return true
	update_status_bar("Save failed: %s" % error_string(err))
	return false
	
func _process(delta: float) -> void:
	if node_registry_version != FlowNodeRegistry.get_version():
		_on_node_registry_changed()
	_update_graph_loading_animation(delta)
	if not current_resource:
		return
		
	if save_pending:
		save_pending_delay -= delta
		if save_pending_delay <= 0.0:
			saveResource()
		
	# This is also trigered to true by plugin.gd:_on_history_changed
	if regen_pending and not regen_running:
		#print( "_process.regen_pending: %s" % [ regen_pending ])
		regen_pending = false
		evalGraphAsync()

	# Update active connections
	if active_intensity > 0.0:
		active_intensity -= 0.016 * 4
		if active_intensity < 0:
			active_intensity = 0.0
		var live_active_nodes := []
		for node in active_nodes:
			if not is_instance_valid(node):
				continue
			node.setActivity( active_intensity )
			live_active_nodes.append(node)
		active_nodes = live_active_nodes
			
		if active_intensity == 0:
			active_nodes.clear()
		gedit.queue_redraw()
		
func getNewName( suffix : String ):
	new_name_counter += 1
	return "id_%04d_%s" % [ new_name_counter, suffix ]

func _set_new_name_counter(value: int):
	new_name_counter = value
	if current_resource:
		current_resource.new_name_counter = value

func _is_node_script_file_name(file_name: String) -> bool:
	var normalized := file_name.strip_edges()
	if normalized.is_empty():
		return false
	if normalized.begins_with("."):
		return false
	if normalized.ends_with(".gd.uid"):
		return false
	return normalized.ends_with(".gd")

func _normalize_node_script_path(file_name: String, base_directory: String = directory_path) -> String:
	var normalized := file_name.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.ends_with(".uid"):
		normalized = normalized.trim_suffix(".uid")
	if normalized.begins_with("uid://"):
		return ""
	if not normalized.begins_with("res://"):
		normalized = "%s/%s" % [base_directory, normalized]
	return normalized

func registerNodeType(node_type_name: String, file_name: String, base_directory: String = directory_path, force_reload: bool = false):
	var full_res_path := _normalize_node_script_path(file_name, base_directory)
	if full_res_path.is_empty():
		if file_name.begins_with("uid://"):
			push_warning("Skipping uid-based node script reference: %s" % file_name)
		return
	if not ResourceLoader.exists(full_res_path, "Script"):
		push_warning("Skipping missing node script %s" % full_res_path)
		return
	var current_mtime := FileAccess.get_modified_time(full_res_path)
	if not force_reload and node_types.has(node_type_name):
		var existing_meta = node_types[node_type_name]
		if existing_meta.get("full_res_path", "") == full_res_path and existing_meta.get("last_modified_time", -1) == current_mtime:
			return
	var cache_mode := ResourceLoader.CACHE_MODE_REPLACE if force_reload else ResourceLoader.CACHE_MODE_REUSE
	var loaded_class : Script = ResourceLoader.load(full_res_path, "Script", cache_mode) as Script
	if not loaded_class:
		push_error("Failed to load class %s" % full_res_path )
		return
	var needs_reload := force_reload
	if not needs_reload:
		if node_types.has(node_type_name):
			needs_reload = current_mtime != node_types[node_type_name].get("last_modified_time", -1)
		elif not loaded_class.can_instantiate():
			needs_reload = true
	if needs_reload:
		loaded_class.reload(true)
	if not loaded_class.can_instantiate():
		var reload_err := loaded_class.reload(false)
		if reload_err != OK or not loaded_class.can_instantiate():
			push_error("Script %s failed to compile or cannot be instantiated" % full_res_path)
			return
	var instance = loaded_class.new()
	var flow_node := instance as FlowNodeBase
	if not flow_node:
		push_warning("Skipping non-FlowNode script %s" % full_res_path)
		if instance is Object:
			instance.free()
		return
	var meta = flow_node.getMeta()
	flow_node.free()
	if meta.is_empty():
		push_warning("Skipping node with empty metadata %s" % full_res_path)
		return
	meta.factory = loaded_class
	meta.full_res_path = full_res_path
	meta.last_modified_time = current_mtime
	#print( "Registering node type %s" % node_type_name )
	if node_types.has(node_type_name):
		var existing_path := String(node_types[node_type_name].get("full_res_path", ""))
		if existing_path != full_res_path:
			push_warning("Node template '%s' from %s overrides %s" % [node_type_name, full_res_path, existing_path])
	node_types[ node_type_name ] = meta

func registerInputNodeType( input ):
	var node_type_name := "input_%s" % input.name
	registerNodeType( node_type_name, "input.gd")

func registerOutputNodeType( output ):
	var node_type_name := "output_%s" % output.name
	registerNodeType( node_type_name, "output.gd")

func ensureNodeTypeRegistered(node_template: String) -> bool:
	if node_types.has(node_template):
		return true
	if node_template.begins_with("input_"):
		registerNodeType(node_template, "input.gd")
	elif node_template.begins_with("output_"):
		registerNodeType(node_template, "output.gd")
	else:
		var script_path := FlowNodeRegistry.get_node_script_path(node_template)
		if not script_path.is_empty():
			registerNodeType(node_template, script_path.get_file(), script_path.get_base_dir())
	return node_types.has(node_template)

func normalizeDynamicNodeTemplate(node: FlowNodeBase) -> void:
	if node == null or node.settings == null or not ("name" in node.settings):
		return
	var param_name := str(node.settings.name)
	if param_name.is_empty():
		return
	var canonical_template := ""
	if node.node_template.begins_with("input_"):
		canonical_template = "input_%s" % param_name
	elif node.node_template.begins_with("output_"):
		canonical_template = "output_%s" % param_name
	if canonical_template.is_empty() or canonical_template == node.node_template:
		return
	ensureNodeTypeRegistered(canonical_template)
	node.node_template = canonical_template

func scanAvailableNodesIfNeeded(force: bool = false) -> void:
	var registry_version := FlowNodeRegistry.get_version()
	if not force and node_registry_version == registry_version and not node_types.is_empty():
		_register_graph_dynamic_node_types()
		return
	scanAvailableNodes()

func scanAvailableNodes(force: bool = false):
	if not force and not node_types.is_empty() and node_registry_version == FlowNodeRegistry.get_version():
		_register_graph_dynamic_node_types()
		return
	node_types.clear()
	node_registry_version = FlowNodeRegistry.get_version()
	for node_directory in FlowNodeRegistry.get_node_directories():
		var files : PackedStringArray
		var dir := DirAccess.open(node_directory)
		if dir:
			files = dir.get_files()
		else:
			files = ResourceLoader.list_directory(node_directory)
		var node_files : PackedStringArray = []
		for file in files:
			var file_name := String(file)
			if not _is_node_script_file_name(file_name):
				continue
			var stem := file_name.get_basename()
			if stem.ends_with("_settings"):
				continue
			node_files.append(file_name)
		node_files.sort()
		for file in node_files:
			var stem := file.get_basename()
			registerNodeType( stem, file, node_directory, force )

	_register_graph_dynamic_node_types()

func _register_graph_dynamic_node_types() -> void:
	if not current_resource:
		return
	for input in current_resource.in_params:
		registerInputNodeType(input)
	if "out_params" in current_resource:
		for output in current_resource.out_params:
			registerOutputNodeType(output)

func populatePopupInputsMenu():
	if not popup_menu_inputs:
		return
	popup_menu_inputs.clear()

	if current_resource:
		for idx in range(current_resource.in_params.size()):
			var label : String = current_resource.in_params[idx].name
			popup_menu_inputs.add_item( FlowNodeBase.editorDisplayName( label ), idx)

	if popup_menu_inputs.get_item_count() == 0:
		popup_menu_inputs.add_item( FlowI18n.t("No inputs defined"), -1 )
		popup_menu_inputs.set_item_disabled(0, true)

func populatePopupOutputsMenu():
	if not popup_menu_outputs:
		return
	popup_menu_outputs.clear()

	if current_resource and "out_params" in current_resource:
		for idx in range(current_resource.out_params.size()):
			var label : String = current_resource.out_params[idx].name
			popup_menu_outputs.add_item( FlowNodeBase.editorDisplayName( label ), idx)

	if popup_menu_outputs.get_item_count() == 0:
		popup_menu_outputs.add_item( FlowI18n.t("No outputs defined"), -1 )
		popup_menu_outputs.set_item_disabled(0, true)

func populatePopupMenu() -> PopupMenu:
	min_id = 1000
	max_id = min_id
	menu_ids = {}
	
	var pm := PopupMenu.new()
	add_child( pm )
	pm.name = "MainMenu"
	pm.clear()
	pm.id_pressed.connect( _on_popup_menu_id_pressed )
	
	var required_input_type := FlowData.DataType.Invalid
	var required_output_type := FlowData.DataType.Invalid
	if auto_connect_from_node:
		var from_node = gedit_nodes_by_name.get( auto_connect_from_node )
		if from_node:
			var meta = from_node.getMeta()
			if auto_connect_from_port < meta.outs.size():
				var oport = meta.outs[ auto_connect_from_port ]
				required_input_type = oport.get( "data_type", FlowData.DataType.Invalid )
		print( "auto_connect_from_node: %s:%d -> %d" % [ auto_connect_from_node, auto_connect_from_port, required_input_type])

	if auto_connect_to_node:
		var to_node = gedit_nodes_by_name.get( auto_connect_to_node )
		if to_node:
			var meta = to_node.getMeta()
			if auto_connect_to_port < meta.ins.size():
				var iport = meta.ins[ auto_connect_to_port ]
				required_output_type = iport.get( "data_type", FlowData.DataType.Invalid )
		print( "auto_connect_to_node: %s:%d -> %d" % [auto_connect_to_node, auto_connect_to_port, required_output_type ])

	# A submenu to invoke the inputs declared in the pcg
	if required_input_type == FlowData.DataType.Invalid:
		if getSelectedNodes().size() > 0:
			pm.add_item( FlowI18n.t("Collapse Selected to Subgraph"), IDM_COLLAPSE_TO_SUBGRAPH )
			pm.add_separator("", -1)
			
		if popup_menu_inputs:
			popup_menu_inputs.queue_free()
		popup_menu_inputs = PopupMenu.new()
		popup_menu_inputs.name = "inputs_menu"
		popup_menu_inputs.id_pressed.connect( _on_inputs_menu_id_pressed )
		pm.add_child(popup_menu_inputs)
		pm.add_submenu_item( FlowI18n.t("Inputs..."), popup_menu_inputs.name )
		pm.add_separator( "", -1 )
		populatePopupInputsMenu()

		if popup_menu_outputs:
			popup_menu_outputs.queue_free()
		popup_menu_outputs = PopupMenu.new()
		popup_menu_outputs.name = "outputs_menu"
		popup_menu_outputs.id_pressed.connect( _on_outputs_menu_id_pressed )
		pm.add_child(popup_menu_outputs)
		pm.add_submenu_item( FlowI18n.t("Outputs..."), popup_menu_outputs.name )
		pm.add_separator( "", -1 )
		populatePopupOutputsMenu()

	# Categorized node submenus
	var cat_map = {
		"Black Lantern": ["bl_style_lab_source", "bl_building_mass", "bl_zone_carver", "bl_room_splitter", "bl_decorator_master", "bl_tactical_decorator", "bl_floor_data_to_points", "bl_floor_data_contract_points", "bl_validate_floor_data", "bl_room_style_template", "bl_style_context_source", "bl_style_context_points", "bl_style_anchor_points", "bl_sync_grid_cell", "bl_points_to_style_spec", "bl_style_spec_to_points", "bl_style_spec_merge", "bl_style_metadata_spec", "bl_smart_prop_scatter", "bl_points_to_floor_data_props"],
		"Attributes": ["add_attribute", "attribute_rename", "remove_attribute", "attribute_filter_range", "point_filter_range", "mutate_seed", "add_tags", "delete_tags", "replace_tags", "point_to_attribute_set", "attribute_set_to_point", "load_data_table", "data_table_row_to_attribute_set", "load_pcg_data_asset"],
		"Math": ["math_op", "remap", "expression", "reduce", "boolean"],
		"Splines": ["create_spline", "sample_spline", "distance", "scan_splines", "clip_points_by_polygon", "clip_paths", "polygon_operation", "split_splines", "create_surface_from_spline", "create_surface_from_polygon"],
		"Meshes": ["sample_mesh", "scan_meshes", "point_from_mesh", "texture_sampler", "points_from_imported_scene", "load_alembic_file"],
		"Spatial": ["substract", "difference", "intersection", "union", "point_neighborhood", "ray_cast", "physics_overlap_query", "physics_shape_sweep", "navigation_region_sampler"],
		"Assets": ["assets", "spawn_meshes", "spawn_scenes", "apply_on_actor", "points_from_imported_scene", "load_alembic_file", "load_pcg_data_asset"],
		"Generators": ["grid", "grid_fill_bounds", "grid_connect_points", "grid_boundary", "noise", "relax", "self_pruning", "dungeon_generator", "volume_sampler"],
		"Utility": ["input", "output", "subgraph", "loop", "debug", "sort", "merge", "merge_points", "partition", "filter", "copy", "copy_points", "point_offsets", "transform_points", "points_from_scene", "point_from_player_pawn", "points_from_tilemap", "points_from_gridmap", "size", "get_points_count", "get_data_count", "get_entries_count", "get_loop_index"]
	}
	
	# Helper to find category of a node template
	var get_category = func(template_name: String, node_meta: Dictionary) -> String:
		var meta_category := String(node_meta.get("category", "")).strip_edges()
		if not meta_category.is_empty():
			return meta_category
		for cat in cat_map:
			if template_name in cat_map[cat]:
				return cat
		return "Utility"
		
	# Group node types by category
	var categorized_keys = {}
	for key in node_types.keys():
		var node_meta = node_types[key]
		if not node_meta.get("auto_register", true):
			continue
			
		# Check port compatibility if drag connecting
		if required_input_type != FlowData.DataType.Invalid or required_output_type != FlowData.DataType.Invalid:
			var has_compatible_port = false
			var ports = node_meta.ins if required_input_type != FlowData.DataType.Invalid else node_meta.outs
			var required_type = required_input_type if required_input_type != FlowData.DataType.Invalid else required_output_type
			for port in ports:
				var port_type = port.get("data_type", 0)
				if port_type == required_type:
					has_compatible_port = true
					break
			if not has_compatible_port:
				continue
				
		var cat = get_category.call(key, node_meta)
		if not categorized_keys.has(cat):
			categorized_keys[cat] = []
		categorized_keys[cat].append(key)
		
	# Sort categories alphabetically
	var sorted_categories = categorized_keys.keys()
	sorted_categories.sort()
	
	var category_idx := 0
	for cat in sorted_categories:
		var sub_pm = PopupMenu.new()
		sub_pm.name = "category_%d_menu" % category_idx
		category_idx += 1
		sub_pm.id_pressed.connect(_on_popup_menu_id_pressed)
		pm.add_child(sub_pm)
		pm.add_submenu_item( FlowI18n.tn(cat), sub_pm.name )
		
		# Sort node templates in this category alphabetically by title
		var templates = categorized_keys[cat]
		templates.sort_custom(func(a, b):
			return node_types[a].title.nocasecmp_to(node_types[b].title) < 0
		)
		
		var idx = 0
		for key in templates:
			var node_meta = node_types[key]
			max_id += 1
			menu_ids[max_id] = key
			sub_pm.add_item( FlowI18n.tn(String(node_meta.title)), max_id, KEY_NONE )
			if node_meta.has("tooltip"):
				sub_pm.set_item_tooltip(idx, FlowI18n.tn(String(node_meta.get("tooltip"))))
			idx += 1
			
	return pm

func _ready():
	
	if not Engine.is_editor_hint():
		return

	_load_editor_settings()
		
	ui_scale = 1.0
	var dpi = DisplayServer.screen_get_dpi()
	if dpi > 150:
		ui_scale *= 2.0
				
	scanAvailableNodes()
	_chrome_refs = FlowEditorChrome.Refs.new()
	_chrome_refs.host = self
	_chrome_refs.tab_bar = tab_bar
	_chrome_refs.toolbar_hbox = toolbar_hbox
	_chrome_refs.open_graph_button = open_graph_button
	_chrome_refs.expand_graph_button = expand_graph_button
	FlowEditorChrome.setup(_chrome_refs)
	if not has_meta(EDITOR_DYNAMIC_UI_META):
		_create_dynamic_editor_ui()
		set_meta(EDITOR_DYNAMIC_UI_META, true)
	else:
		_refresh_dynamic_editor_ui()
	%AutoRegen.button_pressed = auto_regen
	if has_node("%CheckColorNodes"):
		%CheckColorNodes.button_pressed = color_nodes
	if not gedit.begin_node_move.is_connected(_on_graph_edit_begin_node_move):
		gedit.begin_node_move.connect(_on_graph_edit_begin_node_move)
	if not gedit.end_node_move.is_connected(_on_graph_edit_end_node_move):
		gedit.end_node_move.connect(_on_graph_edit_end_node_move)
	call_deferred("_finish_editor_ready")

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		FlowEditorChrome.clear_initialized(self)
		if has_meta(EDITOR_DYNAMIC_UI_META):
			remove_meta(EDITOR_DYNAMIC_UI_META)

func _finish_editor_ready() -> void:
	if not is_inside_tree():
		return
	_ensure_inspector()
	FlowEditorChrome.apply_translations(_chrome_refs)
	_sync_tab_bar_from_open_tabs()
	ensureCurrentResource()
	_sync_tab_bar_from_open_tabs()
	FlowEditorChrome.apply_translations(_chrome_refs)
	update_status_bar()

func _on_button_expand_graph_pressed() -> void:
	_float_graph_panel()

func _on_button_settings_pressed() -> void:
	_show_editor_settings_panel()

func _create_dynamic_editor_ui() -> void:
	_ensure_custom_graph_grid()
	_apply_graph_grid_mode()
	_setup_inline_analyze_panel()
	_ensure_inspector()
	_ensure_search_add_node_popup()
	_setup_graph_loading_overlay()

func _refresh_dynamic_editor_ui() -> void:
	inspector = null
	_ensure_custom_graph_grid()
	_apply_graph_grid_mode()
	_ensure_inspector()
	if search_add_node_popup == null or not is_instance_valid(search_add_node_popup):
		_ensure_search_add_node_popup()

func _sync_tab_bar_from_open_tabs() -> void:
	if tab_bar == null:
		return
	if tab_bar.get_tab_count() == open_tabs.size():
		_update_tab_titles()
		return
	while tab_bar.get_tab_count() > 0:
		tab_bar.remove_tab(tab_bar.get_tab_count() - 1)
	for tab in open_tabs:
		var tab_title := FlowI18n.t("Untitled")
		var tab_res: FlowGraphResource = tab.get("resource")
		if is_instance_valid(tab_res) and tab_res.resource_path != "":
			tab_title = tab_res.resource_path.get_file()
		elif tab.get("owner"):
			tab_title = String(tab.owner.name)
		tab_bar.add_tab(tab_title)
	if active_tab_index >= 0 and active_tab_index < tab_bar.get_tab_count():
		tab_bar.current_tab = active_tab_index
	_update_tab_titles()

func _ensure_custom_graph_grid() -> void:
	if custom_graph_grid != null and is_instance_valid(custom_graph_grid):
		custom_graph_grid.gedit = gedit
		return
	custom_graph_grid = gedit.get_node_or_null("CustomGraphGrid")
	if custom_graph_grid == null:
		custom_graph_grid = preload("res://addons/flow_nodes_editor/custom_grid.gd").new()
		custom_graph_grid.name = "CustomGraphGrid"
		custom_graph_grid.gedit = gedit
		gedit.add_child(custom_graph_grid)
		gedit.move_child(custom_graph_grid, 0)
	else:
		custom_graph_grid.gedit = gedit

func _ensure_inspector() -> void:
	if inspector != null and not is_instance_valid(inspector):
		inspector = null
	var splitter := $VBoxContainer/VSplitContainer
	if splitter == null:
		return
	for child in splitter.get_children():
		if child is FlowInspector:
			inspector = child as FlowInspector
			break
	if inspector == null:
		inspector = FlowInspector.new()
		inspector.custom_minimum_size = Vector2(268, 200)
		splitter.add_child(inspector)
		splitter.split_offset = 600
	if inspector == null:
		return
	inspector.ui_scale = ui_scale
	gedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gedit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gedit.add_theme_color_override("activity", Color(1, 0.2, 0.2, 1))
	inspector.size_flags_horizontal = Control.SIZE_FILL
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not inspector.property_edited.is_connected(onNodePropertyChanged):
		inspector.property_edited.connect(onNodePropertyChanged)
	if not gedit.node_deselected.is_connected(_on_graph_edit_node_deselected):
		gedit.node_deselected.connect(_on_graph_edit_node_deselected)

func _on_graph_edit_node_deselected(node: Node) -> void:
	if inspected_node == node:
		inspected_node = null
		if inspector:
			inspector.edit(null)

func _ensure_search_add_node_popup() -> void:
	search_add_node_popup = get_node_or_null("SearchAddNodePopup") as SearchAddNodePopup
	if search_add_node_popup:
		return
	search_add_node_popup = SearchAddNodePopup.new()
	search_add_node_popup.name = "SearchAddNodePopup"
	add_child(search_add_node_popup)
	search_add_node_popup.node_selected.connect(func(template_name):
		addNode(template_name)
	)
	search_add_node_popup.action_selected.connect(func(action_id):
		if action_id == IDM_COLLAPSE_TO_SUBGRAPH:
			collapse_selected_to_subgraph()
	)
	search_add_node_popup.input_selected.connect(func(input_idx):
		_on_inputs_menu_id_pressed(input_idx)
	)
	search_add_node_popup.output_selected.connect(func(output_idx):
		_on_outputs_menu_id_pressed(output_idx)
	)
	search_add_node_popup.popup_hide.connect(func():
		auto_connect_from_node = ""
		auto_connect_to_node = ""
	)

func _show_editor_settings_panel():
	_ensure_inspector()
	if inspector:
		inspector.edit_editor_settings(self)
	inspected_node = null

func _load_editor_settings():
	var editor_settings := EditorInterface.get_editor_settings()
	if not editor_settings:
		return
	if not editor_settings.has_setting(EDITOR_SETTING_AUTO_REGEN):
		editor_settings.set_setting(EDITOR_SETTING_AUTO_REGEN, auto_regen)
	editor_settings.add_property_info({
		"name": EDITOR_SETTING_AUTO_REGEN,
		"type": TYPE_BOOL,
	})
	if not editor_settings.has_setting(EDITOR_SETTING_NATIVE_GRAPH_GRID):
		editor_settings.set_setting(EDITOR_SETTING_NATIVE_GRAPH_GRID, use_native_graph_grid)
	editor_settings.add_property_info({
		"name": EDITOR_SETTING_NATIVE_GRAPH_GRID,
		"type": TYPE_BOOL,
	})
	if not editor_settings.has_setting(EDITOR_SETTING_HIDE_INSPECTOR_TITLE):
		editor_settings.set_setting(EDITOR_SETTING_HIDE_INSPECTOR_TITLE, hide_inspector_title)
	editor_settings.add_property_info({
		"name": EDITOR_SETTING_HIDE_INSPECTOR_TITLE,
		"type": TYPE_BOOL,
	})
	if not editor_settings.has_setting(EDITOR_SETTING_TRACK_EXTERNAL_EDITS):
		editor_settings.set_setting(EDITOR_SETTING_TRACK_EXTERNAL_EDITS, track_external_edits)
	editor_settings.add_property_info({
		"name": EDITOR_SETTING_TRACK_EXTERNAL_EDITS,
		"type": TYPE_BOOL,
	})
	auto_regen = bool(editor_settings.get_setting(EDITOR_SETTING_AUTO_REGEN))
	use_native_graph_grid = bool(editor_settings.get_setting(EDITOR_SETTING_NATIVE_GRAPH_GRID))
	hide_inspector_title = bool(editor_settings.get_setting(EDITOR_SETTING_HIDE_INSPECTOR_TITLE))
	track_external_edits = bool(editor_settings.get_setting(EDITOR_SETTING_TRACK_EXTERNAL_EDITS))

func _save_editor_settings():
	var editor_settings := EditorInterface.get_editor_settings()
	if not editor_settings:
		return
	editor_settings.set_setting(EDITOR_SETTING_AUTO_REGEN, auto_regen)
	editor_settings.set_setting(EDITOR_SETTING_NATIVE_GRAPH_GRID, use_native_graph_grid)
	editor_settings.set_setting(EDITOR_SETTING_HIDE_INSPECTOR_TITLE, hide_inspector_title)
	editor_settings.set_setting(EDITOR_SETTING_TRACK_EXTERNAL_EDITS, track_external_edits)

func _apply_graph_grid_mode():
	if not gedit:
		return
	gedit.show_grid = use_native_graph_grid
	if custom_graph_grid and is_instance_valid(custom_graph_grid):
		custom_graph_grid.visible = not use_native_graph_grid

func _on_native_graph_grid_toggled(toggled_on: bool):
	use_native_graph_grid = toggled_on
	_save_editor_settings()
	_apply_graph_grid_mode()

func _float_graph_panel():
	var current_window := get_window()
	var main_window := EditorInterface.get_base_control().get_window()
	if current_window and current_window != main_window:
		_maximize_graph_panel_window()
		return

	var float_button := _get_dock_float_button()
	if not float_button:
		update_status_bar(FlowI18n.t("Could not float graph panel"))
		return
	if float_button.disabled:
		update_status_bar(FlowI18n.t("Graph panel floating is disabled"))
		return

	float_button.pressed.emit()
	await get_tree().process_frame
	_maximize_graph_panel_window()

func _get_dock_float_button() -> Button:
	var editor_dock := _get_editor_dock()
	if not editor_dock:
		return null

	var tab_container := editor_dock.get_parent() as TabContainer
	if not tab_container:
		return null

	var tab_index := tab_container.get_tab_idx_from_control(editor_dock)
	if tab_index < 0:
		return null
	tab_container.set_current_tab(tab_index)
	tab_container.emit_signal("pre_popup_pressed")

	var popup := tab_container.get_popup()
	if not popup:
		return null
	return _find_dock_float_button(popup)

func _get_editor_dock() -> Control:
	var node: Node = self
	while node:
		var parent := node.get_parent()
		if parent is TabContainer and node is Control:
			return node as Control
		node = parent
	return null

func _find_dock_float_button(node: Node) -> Button:
	for child in node.get_children():
		var button := child as Button
		if button and not button.text.strip_edges().is_empty():
			return button
		var nested_button := _find_dock_float_button(child)
		if nested_button:
			return nested_button
	return null

func _maximize_graph_panel_window():
	var current_window := get_window()
	var main_window := EditorInterface.get_base_control().get_window()
	if not current_window or current_window == main_window:
		update_status_bar(FlowI18n.t("Could not float graph panel"))
		return
	current_window.mode = Window.MODE_MAXIMIZED
	current_window.grab_focus()
	update_status_bar(FlowI18n.t("Graph panel floated"))

func _notification(what: int):
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree() and _chrome_refs != null:
		FlowEditorChrome.apply_translations(_chrome_refs)
		if search_add_node_popup:
			search_add_node_popup.update_localized_text()
		_refresh_node_translations()
		if data_inspector and data_inspector.has_method("refresh_localized_text"):
			data_inspector.refresh_localized_text()
		if gedit and info:
			update_status_bar()

func _on_node_translation_toggled(toggled_on: bool):
	FlowI18n.set_node_translation_enabled(toggled_on)
	if _chrome_refs != null:
		FlowEditorChrome.apply_translations(_chrome_refs)
	if search_add_node_popup:
		search_add_node_popup.update_localized_text()
	_refresh_node_translations()

func _refresh_node_translations() -> void:
	if gedit:
		for child in gedit.get_children():
			var node := child as FlowNodeBase
			if node:
				node.refreshLocalizedText()
	if inspector:
		inspector.refresh_localized_text()

## Handles debug hotkeys: D (toggle debug), A (toggle inspect), Alt+D (clear all), T (toggle trace).
## Uses _input so it fires before GraphEdit consumes the key events.
## Only active when this editor is visible and no text field is focused.
func _input(event: InputEvent):
	if not visible or not is_visible_in_tree():
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	
	# Don't intercept when a text field has focus (LineEdit, TextEdit, SpinBox)
	var focused = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	if focused and focused.get_parent() is SpinBox:
		return
	# Only intercept when focus is within this editor's subtree
	if focused and not is_ancestor_of(focused):
		return
	
	match key_event.keycode:
		KEY_D:
			if key_event.alt_pressed:
				_hotkey_clear_all_debug()
			else:
				_hotkey_toggle_debug()
			get_viewport().set_input_as_handled()
		KEY_A:
			if not key_event.ctrl_pressed:
				_hotkey_toggle_inspect()
				get_viewport().set_input_as_handled()
		KEY_T:
			_hotkey_toggle_trace()
			get_viewport().set_input_as_handled()
		KEY_E:
			_hotkey_toggle_disabled()
			get_viewport().set_input_as_handled()

## Returns the FlowNodeBase under the mouse cursor, or null if none.
func _get_node_under_cursor() -> FlowNodeBase:
	var mouse_pos = gedit.get_local_mouse_position()
	# Hit test all graph nodes (reverse order = front-to-back)
	var children = gedit.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child = children[i]
		if child is FlowNodeBase:
			var node_rect = Rect2(child.position_offset, child.size)
			# Account for graph zoom and scroll
			var graph_pos = (mouse_pos + gedit.scroll_offset) / gedit.zoom
			if node_rect.has_point(graph_pos):
				return child
	return null

## Returns target nodes for hotkey: hovered node first, then selected nodes.
func _get_hotkey_target_nodes() -> Array:
	var hovered = _get_node_under_cursor()
	if hovered:
		return [hovered]
	return getSelectedNodes()

func _refresh_inspector_if_showing_nodes(nodes: Array):
	if not inspector:
		return
	for node in nodes:
		if not is_instance_valid(node) or not (node is FlowNodeBase):
			continue
		if inspector.current_target == node:
			inspector.edit(node)
			return
		if node.settings and inspector.current_target == node.settings:
			inspector.edit(node.settings)
			return
		if inspected_node == node or (node.settings and inspector.current_settings == node.settings):
			inspector.edit(node)
			return

func _hotkey_toggle_debug():
	var nodes = _get_hotkey_target_nodes()
	if nodes.is_empty():
		return
	# Toggle based on first node's current state
	var new_state = not nodes[0].settings.debug_enabled if nodes[0].settings else true
	var names := PackedStringArray()
	for node in nodes:
		if node is FlowNodeBase and node.settings:
			node.settings.debug_enabled = new_state
			node.dirty = true
			node.refreshFromSettings()
			names.append(node.settings.title)
	var state_str = "ON" if new_state else "OFF"
	update_status_bar("Debug %s: %s" % [state_str, ", ".join(names)])
	_refresh_inspector_if_showing_nodes(nodes)
	queueRegen()

func _hotkey_clear_all_debug():
	var count := 0
	var changed_nodes := []
	for child in gedit.get_children():
		var node = child as FlowNodeBase
		if node and node.settings and node.settings.debug_enabled:
			node.settings.debug_enabled = false
			node.dirty = true
			node.refreshFromSettings()
			changed_nodes.append(node)
			count += 1
	update_status_bar("Debug cleared on %d nodes" % count)
	_refresh_inspector_if_showing_nodes(changed_nodes)
	queueRegen()

func _hotkey_toggle_inspect():
	# Try hovered node first, then fall back to selection
	var hovered = _get_node_under_cursor()
	if hovered:
		analyzeNode(hovered)
	else:
		analyzeSelection()

func _hotkey_toggle_trace():
	var nodes = _get_hotkey_target_nodes()
	if nodes.is_empty():
		return
	var new_state = not nodes[0].settings.trace if nodes[0].settings else true
	var names := PackedStringArray()
	for node in nodes:
		if node is FlowNodeBase and node.settings:
			node.settings.trace = new_state
			node.dirty = true
			node.refreshFromSettings()
			names.append(node.settings.title)
	var state_str = "ON" if new_state else "OFF"
	update_status_bar("Trace %s: %s" % [state_str, ", ".join(names)])
	queueRegen()

func _hotkey_toggle_disabled():
	var nodes = _get_hotkey_target_nodes()
	if nodes.is_empty():
		return
	var new_state = not nodes[0].settings.disabled if nodes[0].settings else true
	var names := PackedStringArray()
	for node in nodes:
		if node is FlowNodeBase and node.settings:
			node.settings.disabled = new_state
			node.dirty = true
			node.refreshFromSettings()
			names.append(node.settings.title)
	var state_str = "DISABLED" if new_state else "ENABLED"
	update_status_bar("%s: %s" % [state_str, ", ".join(names)])
	queueRegen()

## Zooms and scrolls the GraphEdit so all nodes are visible (hotkey: F).
func _zoom_to_fit():
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for child in gedit.get_children():
		if child is GraphNode:
			min_pos = min_pos.min(child.position_offset)
			max_pos = max_pos.max(child.position_offset + child.size)
	if max_pos.x <= min_pos.x:
		return
	var center := (min_pos + max_pos) * 0.5
	var zoom_x := gedit.size.x / (max_pos.x - min_pos.x + 200.0)
	var zoom_y := gedit.size.y / (max_pos.y - min_pos.y + 200.0)
	gedit.zoom = clampf(minf(zoom_x, zoom_y), 0.1, 2.0)
	gedit.scroll_offset = center * gedit.zoom - gedit.size * 0.5

## Finds the nearest connection to a screen position in the GraphEdit.
## Returns the connection dict or null if nothing is within threshold.
func _find_nearest_connection(screen_pos: Vector2):
	var zoom := maxf(gedit.zoom, 0.001)
	var threshold := 20.0
	var connection_pos := screen_pos + gedit.scroll_offset
	var best_conn = null
	var best_dist := threshold
	
	for conn in gedit.connections:
		var from_node = gedit_nodes_by_name.get(conn.from_node)
		var to_node = gedit_nodes_by_name.get(conn.to_node)
		if not from_node or not to_node:
			continue
		
		# Match GraphEdit's connection layer coordinates.
		var from_pos = (from_node.position_offset + from_node.get_output_port_position(conn.from_port)) * zoom
		var to_pos = (to_node.position_offset + to_node.get_input_port_position(conn.to_port)) * zoom
		
		var line_points := gedit.get_connection_line(from_pos, to_pos)
		if line_points.size() < 2:
			continue
		for idx in range(line_points.size() - 1):
			var point := Geometry2D.get_closest_point_to_segment(connection_pos, line_points[idx], line_points[idx + 1])
			var dist = connection_pos.distance_to(point)
			if dist < best_dist:
				best_dist = dist
				best_conn = conn
	
	return best_conn

## Analyze a specific node (used by hover-based hotkeys).
func analyzeNode(node: FlowNodeBase):
	if not data_inspector:
		return
	var prev_auto_regen := auto_regen
	var previous_node = data_inspector.node
	auto_regen = false
	# Toggle off: if analyzer is open on the same node
	if analyze_panel and analyze_panel.visible:
		if current_analyzed_node and node == current_analyzed_node:
			data_inspector.setNode(null)
			_set_analyze_panel_visible(false)
			auto_regen = prev_auto_regen
			regen_pending = false
			_refresh_inspector_if_showing_nodes([node])
			return
	data_inspector.setNode(null)
	data_inspector.setNode(node)
	markAllNodesAsDirty()
	node.refreshFromSettings()
	_set_analyze_panel_visible(true)
	current_analyzed_node = node
	auto_regen = prev_auto_regen
	regen_pending = false
	evalGraph()
	data_inspector.refresh()
	_refresh_inspector_if_showing_nodes([previous_node, node])
	if make_inspector_visible and make_inspector_visible.is_valid():
		make_inspector_visible.call()

func _setup_inline_analyze_panel():
	var panel := Control.new()
	panel.name = "InlineAnalyzePanel"
	panel.visible = false
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 8.0
	panel.offset_top = -280.0
	panel.offset_right = -8.0
	panel.offset_bottom = -8.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.z_index = 100
	# Minimum size so it doesn't collapse to nothing
	panel.custom_minimum_size = Vector2(200, 120)

	var panel_background := PanelContainer.new()
	panel_background.name = "AnalyzePanelBackground"
	panel_background.mouse_filter = Control.MOUSE_FILTER_STOP
	panel_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color("10141f")
	panel_sb.set_border_width_all(1)
	panel_sb.border_color = Color(1.0, 1.0, 1.0, 0.08)
	panel_sb.set_corner_radius_all(4)
	panel_sb.content_margin_left = 8
	panel_sb.content_margin_right = 8
	panel_sb.content_margin_top = 12 # Extra room for resize handle
	panel_sb.content_margin_bottom = 8
	panel_background.add_theme_stylebox_override("panel", panel_sb)
	panel.add_child(panel_background)

	var packed := load("res://addons/flow_nodes_editor/data_inspector.tscn") as PackedScene
	if not packed:
		push_error("Failed to load inline data inspector scene")
		return
	var inline_inspector = packed.instantiate() as Control
	if not inline_inspector:
		push_error("Failed to instantiate inline data inspector")
		return
	inline_inspector.name = "InlineDataInspector"
	inline_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inline_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inline_inspector.anchor_left = 0.0
	inline_inspector.anchor_top = 0.0
	inline_inspector.anchor_right = 1.0
	inline_inspector.anchor_bottom = 1.0
	inline_inspector.offset_left = 0.0
	inline_inspector.offset_top = 0.0
	inline_inspector.offset_right = 0.0
	inline_inspector.offset_bottom = 0.0

	panel_background.add_child(inline_inspector)
	gedit.add_child(panel)
	analyze_panel = panel
	data_inspector = inline_inspector
	if inline_inspector.has_method("set_flow_editor"):
		inline_inspector.set_flow_editor(self)
	
	# Add resize handle to the top edge
	_setup_analyze_resize_handle(panel)

var _analyze_drag_active := false
var _analyze_drag_start_y := 0.0
var _analyze_drag_start_offset := 0.0
const ANALYZE_MIN_HEIGHT := 120.0
const ANALYZE_MAX_HEIGHT_RATIO := 0.85

func _setup_analyze_resize_handle(panel: Control):
	var handle := Control.new()
	handle.name = "ResizeHandle"
	handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	handle.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	handle.anchor_left = 0.0
	handle.anchor_right = 1.0
	handle.anchor_top = 0.0
	handle.anchor_bottom = 0.0
	handle.offset_top = -2.0
	handle.offset_bottom = 8.0 # 10px grab zone at top
	handle.offset_left = 0.0
	handle.offset_right = 0.0
	# Draw a visible drag handle indicator
	handle.draw.connect(func():
		var w = handle.size.x
		var cy = handle.size.y * 0.5
		var bar_w = 32.0
		var bar_x = (w - bar_w) * 0.5
		handle.draw_line(Vector2(bar_x, cy - 1), Vector2(bar_x + bar_w, cy - 1), Color(1, 1, 1, 0.15), 1.0)
		handle.draw_line(Vector2(bar_x, cy + 1), Vector2(bar_x + bar_w, cy + 1), Color(1, 1, 1, 0.15), 1.0)
	)
	panel.add_child(handle)
	
	panel.gui_input.connect(func(event: InputEvent):
		if not (event is InputEventMouseButton or event is InputEventMouseMotion):
			return
		var local_y := panel.get_local_mouse_position().y
		if local_y > 12.0:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_analyze_drag_active = true
				_analyze_drag_start_y = event.global_position.y
				_analyze_drag_start_offset = analyze_panel.offset_top
				panel.accept_event()
			else:
				_analyze_drag_active = false
		elif event is InputEventMouseMotion and _analyze_drag_active:
			var delta = event.global_position.y - _analyze_drag_start_y
			var new_offset = _analyze_drag_start_offset + delta
			var parent_h = gedit.size.y
			var max_offset = -ANALYZE_MIN_HEIGHT
			var min_offset = -(parent_h * ANALYZE_MAX_HEIGHT_RATIO)
			analyze_panel.offset_top = clampf(new_offset, min_offset, max_offset)
			panel.accept_event()
	)

func _set_analyze_panel_visible(visible: bool):
	if not analyze_panel:
		return
	analyze_panel.visible = visible
	if visible:
		analyze_panel.move_to_front()
	else:
		current_analyzed_node = null

func _mark_status_counts_dirty() -> void:
	status_counts_dirty = true

func _refresh_status_counts() -> void:
	if not status_counts_dirty:
		return
	status_nodes_count = 0
	for child in gedit.get_children():
		if child is GraphNode:
			status_nodes_count += 1
	status_wires_count = gedit.get_connection_list().size()
	status_counts_dirty = false

func update_status_bar(eval_msg: String = ""):
	_refresh_status_counts()
	
	var text_parts = []
	text_parts.append(FlowI18n.count(status_nodes_count, "nodes"))
	text_parts.append(FlowI18n.count(status_wires_count, "connections"))
	if eval_msg != "":
		text_parts.append(eval_msg)
	elif inspected_node and inspected_node is FlowNodeBase and inspected_node.has_method("get_data_summary"):
		var summary = inspected_node.get_data_summary()
		if summary != "":
			text_parts.append(summary)
	elif current_resource:
		text_parts.append(FlowI18n.t("Ready"))
		
	var status_text := " · ".join(text_parts)
	if info.text != status_text:
		info.text = status_text

func _on_in_params_changed():
	if current_resource:
		for input in current_resource.in_params:
			registerInputNodeType(input)
		if "out_params" in current_resource:
			for output in current_resource.out_params:
				registerOutputNodeType(output)
		populatePopupInputsMenu()
		populatePopupOutputsMenu()
		if inspector and inspector.current_settings == current_resource:
			inspector.edit(current_resource)

func _refresh_graph_resource_parameter_edit(prop_name: String) -> bool:
	if prop_name != "in_params" and prop_name != "out_params":
		return false
	if not current_resource:
		return false

	current_resource.emit_changed()
	current_resource.in_params_changed.emit()
	for node in getAllNodes():
		var is_graph_parameter_node = (
			node.node_template == "input"
			or node.node_template == "output"
			or node.node_template.begins_with("input_")
			or node.node_template.begins_with("output_")
		)
		if is_graph_parameter_node:
			node.initFromScript()
			node.refreshFromSettings()
			refreshSignalsInputArgs(node)
	queueSave()
	queueRegen()
	return true

func notifyGraphParametersEdited(prop_name: String):
	_refresh_graph_resource_parameter_edit(prop_name)
	
func onNodePropertyChanged( prop_name : String):
	if _refresh_graph_resource_parameter_edit(prop_name):
		return
	if inspected_node and inspected_node is GraphNode:
		#print( "Node %s.%s has changed" % [ inspected_node.name, prop_name ])
		inspected_node.onPropChanged( prop_name )
		inspected_node.refreshFromSettings()
		if inspected_node is FlowNodeBase and (inspected_node.node_template == "input" or inspected_node.node_template.begins_with("input_")):
			if prop_name == "name" or prop_name == "data_type":
				normalizeDynamicNodeTemplate(inspected_node)
				syncGraphParameters()
		elif inspected_node is FlowNodeBase and (inspected_node.node_template == "output" or inspected_node.node_template.begins_with("output_")):
			if prop_name == "name" or prop_name == "data_type":
				normalizeDynamicNodeTemplate(inspected_node)
				syncGraphOutputs()
		elif inspected_node is FlowNodeBase and (inspected_node.node_template == "set_variable" or inspected_node.node_template == "get_variable"):
			if inspected_node.node_template == "set_variable" and prop_name == "variable_name":
				var variable_name := String(inspected_node.settings.variable_name).strip_edges()
				ensureSetVariableNameUnique(inspected_node)
				_ensure_inspector()
				if inspector:
					inspector.edit(inspected_node)
			if prop_name == "variable_name" or prop_name == "node_color":
				refreshVariableNodes()
		queueSave()
		queueRegen()
		
# ------------------------------------------------
func getSelectedFrames() -> Array[GraphFrame]:
	var nodes : Array[GraphFrame] = []
	for child in gedit.get_children():
		var node = child as GraphFrame
		if node and node.selected:
			nodes.push_back(node)
	return nodes

func deleteFrames( frames : Array[GraphFrame] ):
	for node in frames:
		gedit.remove_child( node )
		node.queue_free()
	if not frames.is_empty():
		_mark_status_counts_dirty()
	
# ------------------------------------------------
func getSelectedNodes() -> Array[GraphNode]:
	var nodes : Array[GraphNode] = []
	for child in gedit.get_children():
		var node = child as GraphNode
		if node and node.selected:
			nodes.push_back(node)
	return nodes

func _get_selected_graph_element_names() -> Array:
	var selected_names := []
	for child in gedit.get_children():
		if child is GraphNode or child is GraphFrame:
			if child.selected:
				selected_names.append(child.name)
	return selected_names

func _clear_graph_selection():
	for child in gedit.get_children():
		if child is GraphNode or child is GraphFrame:
			child.selected = false

func _restore_graph_selection(selected_names: Array):
	var selected_lookup := {}
	for node_name in selected_names:
		selected_lookup[node_name] = true
	for child in gedit.get_children():
		if child is GraphNode or child is GraphFrame:
			child.selected = selected_lookup.has(child.name)

func deleteNodes( nodes : Array[GraphNode] ):
	var has_input_nodes := false
	var has_output_nodes := false
	var has_variable_nodes := false
	for node in nodes:
		active_nodes.erase(node)
		if node is FlowNodeBase and (node.node_template == "input" or node.node_template.begins_with("input_")):
			has_input_nodes = true
		elif node is FlowNodeBase and (node.node_template == "output" or node.node_template.begins_with("output_")):
			has_output_nodes = true
		elif node is FlowNodeBase and (node.node_template == "set_variable" or node.node_template == "get_variable"):
			has_variable_nodes = true
		for n in range( node.num_ports ):
			remove_all_inputs_to_target_connection( node.name, n )
		for n in range( node.getMeta().outs.size() ):
			remove_all_inputs_to_source_connection( node.name, n )
		gedit_nodes_by_name.erase( node.name )
		gedit.remove_child( node )
		node.queue_free()
	if not nodes.is_empty():
		_mark_status_counts_dirty()
	if has_input_nodes:
		syncGraphParameters()
	if has_output_nodes:
		syncGraphOutputs()
	if has_variable_nodes:
		refreshVariableNodes()

func deleteGraphElementsAndRefresh( nodes : Array[GraphNode], frames : Array[GraphFrame] ):
	deleteFrames( frames )
	deleteNodes( nodes )
	queueSave()
	inspected_node = null
	_ensure_inspector()
	if inspector:
		inspector.edit(null)
	queueRegen()
	
func deleteSelectedNodes():
	var before_state = get_graph_snapshot()
	var frames := getSelectedFrames()
	var nodes := getSelectedNodes()
	if frames.is_empty() and nodes.is_empty():
		return
	deleteGraphElementsAndRefresh( nodes, frames )
	record_undo_action("Delete Nodes", before_state)
	
func queueSave():
	_set_current_graph_dirty(true)
	save_pending = true
	save_pending_delay = SAVE_DEBOUNCE_SECONDS
	
func queueRegen():
	#print( "queueRegen -> %s" % [ auto_regen ])
	regen_pending = auto_regen
	if regen_running and auto_regen:
		regen_requested_while_running = true

func queueForcedRegen():
	regen_pending = true
	if regen_running:
		regen_requested_while_running = true

func _cancel_regen_run() -> void:
	regen_run_id += 1
	regen_pending = false
	regen_running = false
	regen_requested_while_running = false

func _start_regen_run() -> int:
	regen_run_id += 1
	regen_running = true
	return regen_run_id

func _is_current_regen_run(run_id: int) -> bool:
	return regen_running and run_id == regen_run_id

func _complete_regen_run(run_id: int) -> void:
	if not _is_current_regen_run(run_id):
		return
	regen_running = false
	if regen_requested_while_running:
		regen_requested_while_running = false
		regen_pending = auto_regen
	
func getRectOfNodes( nodes : Array[GraphNode] ):
	var r : Rect2
	var first : bool = true
	for node in nodes:
		var p0 = node.position_offset
		var p1 = p0 + node.size
		if first:
			r.position = p0
			r.size = Vector2(0,0)
			first = false
		else:
			r = r.expand( p0 )
		r = r.expand( p1 )
	return r

func localToGraphCoords( local_coords : Vector2 ):
	#var view_zero_in_scroll_offset = gedit.scroll_offset / gedit.zoom
	return ( gedit.scroll_offset + local_coords ) / gedit.zoom

func setOnOverInParam( row ):
	popup_on_over_input = row
	
func refreshSignalsInputArgs( node ):
	for child in node.get_children():
		var row = child as FlowConnectorRow
		if not row or not row.isParameter():
			continue
		if row.in_popup.get_connections().is_empty():
			row.in_popup.connect( setOnOverInParam.bind( row ) )
		if row.out_popup.get_connections().is_empty():
			row.out_popup.connect( setOnOverInParam.bind( null ) )	

func addNodeFromTemplate( node_template, node_name : String, settings = null, initialize := true ):
	print( "addNode %s (%s : %s)" % [ node_template, node_name, str(settings) ])
	var node = packed_node.instantiate() as GraphNode
	ensureNodeTypeRegistered(node_template)
	var meta = node_types.get( node_template, null )
	if not meta:
		push_error("node_type %s is not registered" % node_template)
		print( node_types.keys() )
		return null	
	#print( "Meta:", str(meta) )
		
	node.set_script(meta.factory)

	node.node_template = node_template
	node.name = node_name
	node.ui_scale = ui_scale
	node.position_offset = localToGraphCoords(local_drop_position)
	if settings:
		node.settings = settings
	else:
		if meta.has( "settings" ):
			var s = meta.settings.new()
			if node_template == "input" and s.name == "in_val":
				var index = 1
				var uname = "in_val"
				while _has_input_node_named(uname):
					uname = "in_val_%d" % index
					index += 1
				s.name = uname
			elif node_template == "output" and s.name == "out_val":
				var index = 1
				var uname = "out_val"
				while _has_output_node_named(uname):
					uname = "out_val_%d" % index
					index += 1
				s.name = uname
			node.settings = s
		else:
			#print( "Assigning default settings" )
			node.settings = NodeSettings.new()
	if node_template == "set_variable":
		ensureSetVariableNameUnique(node, false)
	node.settings.title = meta.title
	node.title = node.getTitle()
	node.size = Vector2(32,32)
	node.tooltip_text = meta.get( "tooltip", "" )
	if initialize:
		node.initFromScript()
		node.refreshFromSettings()
		refreshSignalsInputArgs( node )
	
	gedit.add_child(node)
	gedit_nodes_by_name[ node.name ] = node
	_mark_status_counts_dirty()
	return node

func _has_input_node_named(uname: String) -> bool:
	for child in gedit.get_children():
		var node = child as FlowNodeBase
		if node and (node.node_template == "input" or node.node_template.begins_with("input_")):
			if node.settings and node.settings.name == uname:
				return true
	return false

func _has_output_node_named(uname: String) -> bool:
	for child in gedit.get_children():
		var node = child as FlowNodeBase
		if node and (node.node_template == "output" or node.node_template.begins_with("output_")):
			if node.settings and node.settings.name == uname:
				return true
	return false

func _is_multi_port_flow_node(node: FlowNodeBase) -> bool:
	return node != null and node.has_method("is_multi_port") and node.is_multi_port()

func _is_specific_input_node(node: FlowNodeBase) -> bool:
	if not node or not node.settings:
		return false
	if node.node_template.begins_with("input_"):
		return true
	if node.node_template == "input":
		return not _is_multi_port_flow_node(node)
	return false

func _is_specific_output_node(node: FlowNodeBase) -> bool:
	if not node or not node.settings:
		return false
	if node.node_template.begins_with("output_"):
		return true
	if node.node_template == "output":
		return not _is_multi_port_flow_node(node)
	return false
	
func canConnect( src : FlowNodeBase, src_port : int, dst : FlowNodeBase, dst_port : int ):
	# Discard self connections and null values
	if dst == src or src == null or dst == null:
		push_warning( "canConnect. Invalid inputs: ", src, " <-> ", dst )
		return false
		
	# Check Slot numbers
	if dst_port >= dst.num_in_ports:
		push_warning( "canConnect. dst_port(%d) >= num_in_ports(%d) dst:%s" % [ dst_port, dst.num_in_ports, dst.name ])
		return false
	if src_port >= src.num_out_ports:
		push_warning( "canConnect. src_port(%d) >= num_out_ports(%d) src:%s" % [ src_port, src.num_out_ports, src.name ])
		return false
		
	var src_type = src.get_output_port_type( src_port )
	var dst_type = dst.get_input_port_type( dst_port )
	# When both ports have an explicit non-zero type they must match exactly.
	# A zero (default/untyped) port is treated as a wildcard and connects to anything.
	if src_type != 0 and dst_type != 0:
		if src_type != dst_type:
			push_warning( "Node types do not match %d vs %d" % [ src_type, dst_type ])
			return false
		
	#print( "canConnect OK %s:%d (%d)-> %s:%d (%d)" % [ src.name, src_port, src_type, dst.name, dst_port, dst_type ] )
	return true

func _node_needs_parameter_sync(node_template: String) -> bool:
	return node_template == "input" or node_template.begins_with("input_")

func _node_needs_output_sync(node_template: String) -> bool:
	return node_template == "output" or node_template.begins_with("output_")

func _sync_graph_parameters_for_node_template(node_template: String):
	if _node_needs_parameter_sync(node_template):
		syncGraphParameters()
	elif _node_needs_output_sync(node_template):
		syncGraphOutputs()

func _get_added_node_undo_data(node: FlowNodeBase) -> Dictionary:
	node.refreshConnectionFlags()
	return {
		"name": node.name,
		"template": node.node_template,
		"position_offset": node.position_offset,
		"show_disconnected_inputs": node.show_disconnected_inputs,
		"args_port": node.args_ports_by_name.duplicate(true),
		"settings": FlowNodeIO.resource_to_dict(node.settings).duplicate(true),
	}

func _has_graph_connection(connection: Dictionary) -> bool:
	for existing in gedit.connections:
		var same_source = existing.from_node == connection.from_node and existing.from_port == connection.from_port
		var same_target = existing.to_node == connection.to_node and existing.to_port == connection.to_port
		if same_source and same_target:
			return true
	return false

func _restore_added_node(node_data: Dictionary, connections: Array, selected_names: Array, restored_name_counter: int):
	_suppress_next_editor_scene_changed()
	var node_name = node_data.name
	var node = gedit.get_node_or_null(NodePath(node_name)) as FlowNodeBase
	if node == null:
		node = addNodeFromTemplate(node_data.template, node_name, null, false) as FlowNodeBase
		if node == null:
			return
		node.position_offset = node_data.position_offset
		node.show_disconnected_inputs = node_data.get("show_disconnected_inputs", false)
		node.args_ports_by_name = node_data.get("args_port", {}).duplicate(true)
		FlowNodeIO.dict_to_resource(node_data.get("settings", {}), node.settings)
		node.initFromScript()
		node.refreshFromSettings()
	for connection in connections:
		if not _has_graph_connection(connection):
			connect_nodes(connection.from_node, connection.from_port, connection.to_node, connection.to_port)
	node.visible = true
	_restore_graph_selection(selected_names)
	_set_new_name_counter(restored_name_counter)
	_sync_graph_parameters_for_node_template(node.node_template)
	queueSave()
	if not connections.is_empty():
		markAllNodesAsDirty()
		queueRegen()

func _remove_added_node(node_name: StringName, selected_names: Array, restored_name_counter: int, had_connections := false):
	_suppress_next_editor_scene_changed()
	var node = gedit.get_node_or_null(NodePath(node_name)) as GraphNode
	if node:
		if inspected_node == node:
			inspected_node = null
			if inspector:
				inspector.edit(null)
		if data_inspector and data_inspector.node == node:
			data_inspector.setNode(null)
			_set_analyze_panel_visible(false)
			current_analyzed_node = null
		var nodes: Array[GraphNode] = [node]
		deleteNodes(nodes)
	_restore_graph_selection(selected_names)
	_set_new_name_counter(restored_name_counter)
	queueSave()
	if had_connections:
		markAllNodesAsDirty()
		queueRegen()

func _record_add_node_undo(
	node: FlowNodeBase,
	node_data: Dictionary,
	connections: Array,
	selected_before: Array,
	selected_after: Array,
	name_counter_before: int,
	name_counter_after: int
):
	_set_new_name_counter(name_counter_after)
	_suppress_next_editor_scene_changed()
	var ur = undo_redo
	if ur and current_resource:
		var context = EditorInterface.get_edited_scene_root()
		if not context:
			context = current_resource
		ur.create_action("Add Node", 0, context)
		ur.add_do_method(self, "_restore_added_node", node_data, connections, selected_after, name_counter_after)
		ur.add_undo_method(self, "_remove_added_node", node.name, selected_before, name_counter_before, not connections.is_empty())
		ur.commit_action(false) # already executed
	queueSave()
	if not connections.is_empty():
		markAllNodesAsDirty()
		queueRegen()
	
func addNode( node_template, settings = null ):
	ensureCurrentResource()
	var selected_before := _get_selected_graph_element_names()
	var name_counter_before := new_name_counter
	var node_name = getNewName(node_template)
	var node = addNodeFromTemplate( node_template, node_name, settings )
	if not node:
		return null
	var added_connections := []

	if auto_connect_from_node:
		var source_node = gedit_nodes_by_name.get( auto_connect_from_node )
		if canConnect( source_node, auto_connect_from_port, node, 0 ):
			connect_nodes(auto_connect_from_node, auto_connect_from_port, node.name, 0)
			added_connections.append({
				"from_node": auto_connect_from_node,
				"from_port": auto_connect_from_port,
				"to_node": node.name,
				"to_port": 0
			})
		auto_connect_from_node = ""
		
	if auto_connect_to_node:
		var target_node = gedit_nodes_by_name.get( auto_connect_to_node )
		if canConnect( node, 0, target_node, auto_connect_to_port ):
			connect_nodes(node.name, 0, auto_connect_to_node, auto_connect_to_port )
			added_connections.append({
				"from_node": node.name,
				"from_port": 0,
				"to_node": auto_connect_to_node,
				"to_port": auto_connect_to_port
			})
		auto_connect_to_node = ""
	
	for prev_node in getSelectedNodes():
		prev_node.selected = false
	node.selected = true
	node.visible = true
	
	var selected_after := _get_selected_graph_element_names()
	var name_counter_after := new_name_counter
	var node_data := _get_added_node_undo_data(node)
	_record_add_node_undo(
		node,
		node_data,
		added_connections,
		selected_before,
		selected_after,
		name_counter_before,
		name_counter_after
	)
	_sync_graph_parameters_for_node_template(node_template)
	if node_template == "set_variable" or node_template == "get_variable":
		refreshVariableNodes()
	return node

func insertRerouteOnConnection(conn: Dictionary, local_position: Vector2) -> FlowNodeBase:
	if conn.is_empty():
		return null
	ensureCurrentResource()
	var before_state = get_graph_snapshot()
	local_drop_position = local_position
	var reroute_name = getNewName("reroute")
	var reroute = addNodeFromTemplate("reroute", reroute_name) as FlowNodeBase
	if not reroute:
		return null
	var reroute_size : Vector2 = reroute.custom_minimum_size
	if reroute_size == Vector2.ZERO:
		reroute_size = reroute.size
	reroute.position_offset = localToGraphCoords(local_position) - reroute_size * 0.5
	disconnect_nodes(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
	connect_nodes(conn.from_node, conn.from_port, reroute.name, 0)
	connect_nodes(reroute.name, 0, conn.to_node, conn.to_port)
	for prev_node in getSelectedNodes():
		prev_node.selected = false
	reroute.selected = true
	reroute.visible = true
	queueSave()
	markAllNodesAsDirty()
	queueRegen()
	record_undo_action("Insert Reroute", before_state)
	return reroute

func _handle_right_mouse_pan(event: InputEvent) -> bool:
	var evt_mouse := event as InputEventMouseButton
	if evt_mouse and evt_mouse.button_index == MOUSE_BUTTON_RIGHT:
		if evt_mouse.pressed:
			right_drag_pan_active = true
			right_drag_pan_moved = false
			right_drag_pan_start_position = evt_mouse.position
			right_drag_pan_start_scroll = gedit.scroll_offset
			gedit.accept_event()
			return true

		if right_drag_pan_active:
			var was_drag := right_drag_pan_moved or evt_mouse.position.distance_to(right_drag_pan_start_position) >= RIGHT_DRAG_PAN_THRESHOLD
			right_drag_pan_active = false
			right_drag_pan_moved = false
			gedit.accept_event()
			if not was_drag:
				suppress_next_popup_request = true
				call_deferred("_clear_suppressed_popup_request")
				_open_graph_context_menu(evt_mouse.position)
			return true
		return false

	var evt_motion := event as InputEventMouseMotion
	if evt_motion and right_drag_pan_active:
		var delta := evt_motion.position - right_drag_pan_start_position
		if right_drag_pan_moved or delta.length() >= RIGHT_DRAG_PAN_THRESHOLD:
			right_drag_pan_moved = true
			gedit.scroll_offset = right_drag_pan_start_scroll - delta
		gedit.accept_event()
		return true

	return false

func _clear_suppressed_popup_request():
	suppress_next_popup_request = false

# ------------------------------------------------
func _on_graph_edit_gui_input(event):
	if _handle_right_mouse_pan(event):
		return

	var evt_mouse = event as InputEventMouseButton
	if evt_mouse and evt_mouse.pressed and evt_mouse.button_index == MOUSE_BUTTON_LEFT and evt_mouse.double_click:
		var conn_to_reroute = _find_nearest_connection(evt_mouse.position)
		if conn_to_reroute:
			insertRerouteOnConnection(conn_to_reroute.duplicate(), evt_mouse.position)
			update_status_bar("Inserted reroute")
			gedit.accept_event()
			return

	# Ctrl+Click on wire to disconnect
	if evt_mouse and evt_mouse.pressed and evt_mouse.button_index == MOUSE_BUTTON_LEFT and evt_mouse.ctrl_pressed:
		var conn = _find_nearest_connection(evt_mouse.position)
		if conn:
			_on_graph_edit_disconnection_request(conn.from_node, conn.from_port, conn.to_node, conn.to_port)
			update_status_bar("Disconnected %s → %s" % [conn.from_node, conn.to_node])
			gedit.accept_event()
			return
	
	var evt_key = event as InputEventKey
	if evt_key and evt_key.pressed:
		var no_modifiers = not evt_key.ctrl_pressed and not evt_key.alt_pressed and not evt_key.shift_pressed
		var key = evt_key.keycode
		if key == KEY_X or key == KEY_DELETE:
			if no_modifiers:
				deleteSelectedNodes()
				gedit.accept_event()
		elif key == KEY_A:
			if evt_key.shift_pressed:
				openAddMenu()
				gedit.accept_event()
			elif no_modifiers:
				_hotkey_toggle_inspect()
				gedit.accept_event()
		elif key == KEY_C:
			if no_modifiers:
				addComment()
				gedit.accept_event()
		elif key == KEY_E:
			if no_modifiers:
				_hotkey_toggle_disabled()
				gedit.accept_event()
		elif key == KEY_D:
			if no_modifiers:
				_hotkey_toggle_debug()
				gedit.accept_event()
		elif key == KEY_T:
			if no_modifiers:
				_hotkey_toggle_trace()
				gedit.accept_event()
		elif key == KEY_R:
			if no_modifiers:
				for node in getSelectedNodes():
					node.dirty = true
				evalGraph()
				gedit.accept_event()
		elif key == KEY_F:
			if no_modifiers:
				_zoom_to_fit()
				gedit.accept_event()
		elif evt_key.ctrl_pressed and not evt_key.alt_pressed:
			if key == KEY_Z:
				if evt_key.shift_pressed:
					if undo_redo:
						var context = EditorInterface.get_edited_scene_root()
						if not context:
							context = current_resource
						if context:
							var history_obj = undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(context))
							if history_obj:
								history_obj.redo()
						accept_event()
				else:
					if undo_redo:
						var context = EditorInterface.get_edited_scene_root()
						if not context:
							context = current_resource
						if context:
							var history_obj = undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(context))
							if history_obj:
								history_obj.undo()
						accept_event()
			elif key == KEY_Y:
				if undo_redo:
					var context = EditorInterface.get_edited_scene_root()
					if not context:
						context = current_resource
					if context:
						var history_obj = undo_redo.get_history_undo_redo(undo_redo.get_object_history_id(context))
						if history_obj:
							history_obj.redo()
					accept_event()

func toggleDebug():
	var nodes = getSelectedNodes()
	var prev_auto_regen := auto_regen
	auto_regen = false
	for node in nodes:
		node.settings.debug_enabled = !node.settings.debug_enabled
		node.dirty = true
		node.refreshFromSettings()
	auto_regen = prev_auto_regen
	regen_pending = false
	markAllNodesAsDirty()
	evalGraph()

func toggleDisabled():
	var nodes = getSelectedNodes()
	for node in nodes:
		node.dirty = true
		node.settings.disabled = !node.settings.disabled
		node.refreshFromSettings()

func toggleInspection():
	if not data_inspector:
		return
	var nodes = getSelectedNodes()
	var prev_auto_regen := auto_regen
	auto_regen = false
	if nodes.size() != 1:
		data_inspector.setNode( null )
		_set_analyze_panel_visible(false)
		auto_regen = prev_auto_regen
		regen_pending = false
		return
	var node = nodes[0]
	data_inspector.setNode( node )
	markAllNodesAsDirty()
	node.refreshFromSettings()
	_set_analyze_panel_visible(true)
	current_analyzed_node = node
	auto_regen = prev_auto_regen
	regen_pending = false
	evalGraph()
	data_inspector.refresh()

func analyzeSelection():
	if not data_inspector:
		return
	var nodes = getSelectedNodes()
	var prev_auto_regen := auto_regen
	var previous_node = data_inspector.node
	auto_regen = false
	# Toggle off: if analyzer is open and user re-runs Analyze on the same node (or with no node selected).
	if analyze_panel and analyze_panel.visible:
		if nodes.size() != 1 or (current_analyzed_node and nodes[0] == current_analyzed_node):
			data_inspector.setNode(null)
			_set_analyze_panel_visible(false)
			auto_regen = prev_auto_regen
			regen_pending = false
			_refresh_inspector_if_showing_nodes([previous_node])
			return
	if nodes.size() != 1:
		data_inspector.setNode(null)
		_set_analyze_panel_visible(false)
		auto_regen = prev_auto_regen
		regen_pending = false
		_refresh_inspector_if_showing_nodes([previous_node])
		return
	var node = nodes[0]
	# Force rebind so repeated Analyze on the same node stays active.
	data_inspector.setNode(null)
	data_inspector.setNode(node)
	markAllNodesAsDirty()
	node.refreshFromSettings()
	_set_analyze_panel_visible(true)
	current_analyzed_node = node
	auto_regen = prev_auto_regen
	regen_pending = false
	evalGraph()
	data_inspector.refresh()
	_refresh_inspector_if_showing_nodes([previous_node, node])
	if make_inspector_visible and make_inspector_visible.is_valid():
		make_inspector_visible.call()

func addComment():
	var nodes = getSelectedNodes()
	var rect = getRectOfNodes( nodes )
	rect.position -= comment_padding
	rect.size += comment_padding * 2
	
	var frame := GraphFrame.new()
	frame.name = getNewName("comment")
	frame.title = "My Comments..."
	frame.position_offset = rect.position
	frame.size = rect.size
	frame.tint_color = Color.DARK_SLATE_BLUE
	frame.tint_color_enabled = true
	gedit.add_child(frame)
	_mark_status_counts_dirty()
	
	for node in nodes:
		gedit.attach_graph_element_to_frame( node.name, frame.name )
	_fit_comment_frame_to_attached_nodes(frame)

func get_comment_frame_at_graph_position(graph_position: Vector2) -> GraphFrame:
	for child in gedit.get_children():
		var frame := child as GraphFrame
		if frame == null:
			continue
		var frame_rect := Rect2(frame.position_offset, frame.size)
		if frame_rect.has_point(graph_position):
			return frame
	return null

func _get_target_comment_frame(at_local_position: Vector2) -> GraphFrame:
	var selected_frames := getSelectedFrames()
	if selected_frames.size() == 1:
		return selected_frames[0]
	if selected_frames.is_empty():
		return get_comment_frame_at_graph_position(localToGraphCoords(at_local_position))
	return get_comment_frame_at_graph_position(localToGraphCoords(at_local_position))

func add_selected_nodes_to_comment_frame(frame: GraphFrame) -> int:
	if frame == null:
		return 0
	var added := 0
	for node in getSelectedNodes():
		if node == null or not is_instance_valid(node):
			continue
		var current_frame := gedit.get_element_frame(node.name)
		if current_frame == frame:
			continue
		gedit.attach_graph_element_to_frame(node.name, frame.name)
		added += 1
	if added > 0:
		_fit_comment_frame_to_attached_nodes(frame)
		queueSave()
		_mark_status_counts_dirty()
	return added

func remove_selected_nodes_from_comment_frame(frame: GraphFrame) -> int:
	if frame == null:
		return 0
	var removed := 0
	for node in getSelectedNodes():
		if node == null or not is_instance_valid(node):
			continue
		if gedit.get_element_frame(node.name) != frame:
			continue
		gedit.detach_graph_element_from_frame(node.name)
		removed += 1
	if removed > 0:
		_fit_comment_frame_to_attached_nodes(frame)
		queueSave()
		_mark_status_counts_dirty()
	return removed

func _fit_comment_frame_to_attached_nodes(frame: GraphFrame) -> void:
	if frame == null:
		return
	var attached_nodes: Array[GraphNode] = []
	for node_name in gedit.get_attached_nodes_of_frame(frame.name):
		var child := gedit.get_node_or_null(NodePath(node_name))
		if child is GraphNode:
			attached_nodes.append(child as GraphNode)
	if attached_nodes.is_empty():
		return
	var rect: Rect2 = getRectOfNodes(attached_nodes)
	rect.position -= comment_padding
	rect.size += comment_padding * 2
	frame.position_offset = rect.position
	frame.size = rect.size

func _on_frame_context_menu_pressed(menu_id: int, frame: GraphFrame) -> void:
	if frame == null:
		return
	match menu_id:
		IDM_FRAME_ADD_SELECTED_NODES:
			var added := add_selected_nodes_to_comment_frame(frame)
			if added > 0:
				update_status_bar(FlowI18n.t("Added %d nodes to comment") % added)
			else:
				update_status_bar(FlowI18n.t("No nodes added to comment"))
		IDM_FRAME_REMOVE_SELECTED_NODES:
			var removed := remove_selected_nodes_from_comment_frame(frame)
			if removed > 0:
				update_status_bar(FlowI18n.t("Removed %d nodes from comment") % removed)
			else:
				update_status_bar(FlowI18n.t("No nodes removed from comment"))

func _on_graph_edit_node_selected(node):
	if not inspector:
		push_error("inspector is null")
		return
	
	inspected_node = node
	if inspected_node:
		inspector.edit(inspected_node)
		
	update_status_bar()

func registerAsParameter( name : String, data_type : FlowData.DataType ):
	var new_input = GraphInputParameter.new()
	new_input.name = name
	new_input.data_type = data_type
	current_resource.in_params.append( new_input )
	current_resource.in_params_changed.emit()
	registerInputNodeType( current_resource.in_params.back() )

func syncGraphParameters():
	if not current_resource:
		return
	var has_multi_port_input = false
	var input_nodes = []
	for child in gedit.get_children():
		var node = child as FlowNodeBase
		if not node:
			continue
		if node.node_template == "input" and _is_multi_port_flow_node(node):
			has_multi_port_input = true
		elif _is_specific_input_node(node):
			input_nodes.append(node)
	var new_in_params : Array[GraphInputParameter] = []
	var seen_names = {}
	if has_multi_port_input:
		for p in current_resource.in_params:
			if p and not seen_names.has(p.name):
				seen_names[p.name] = true
				new_in_params.append(p)
	for input_node in input_nodes:
		var param_name = input_node.settings.name
		if param_name == "":
			continue
		if seen_names.has(param_name):
			continue
		seen_names[param_name] = true
		var existing = null
		for p in current_resource.in_params:
			if p and p.name == param_name:
				existing = p
				break
		if existing:
			if existing.data_type != input_node.settings.data_type:
				existing.data_type = input_node.settings.data_type
			new_in_params.append(existing)
		else:
			var new_param = GraphInputParameter.new()
			new_param.name = param_name
			new_param.data_type = input_node.settings.data_type
			new_in_params.append(new_param)
	current_resource.in_params = new_in_params
	current_resource.in_params_changed.emit()

func syncGraphOutputs():
	if not current_resource:
		return
	var has_multi_port_output = false
	var output_nodes = []
	for child in gedit.get_children():
		var node = child as FlowNodeBase
		if not node:
			continue
		if node.node_template == "output" and _is_multi_port_flow_node(node):
			has_multi_port_output = true
		elif _is_specific_output_node(node):
			output_nodes.append(node)
	var new_out_params : Array[GraphInputParameter] = []
	var seen_names = {}
	
	if has_multi_port_output:
		for p in current_resource.out_params:
			if p and not seen_names.has(p.name):
				seen_names[p.name] = true
				new_out_params.append(p)
				
	for output_node in output_nodes:
		var param_name = output_node.settings.name
		if param_name == "" or seen_names.has(param_name):
			continue
		seen_names[param_name] = true
		var existing = null
		if "out_params" in current_resource:
			for p in current_resource.out_params:
				if p and p.name == param_name:
					existing = p
					break
		if existing:
			if existing.data_type != output_node.settings.data_type:
				existing.data_type = output_node.settings.data_type
			new_out_params.append(existing)
		else:
			var new_param = GraphInputParameter.new()
			new_param.name = param_name
			new_param.data_type = output_node.settings.data_type
			new_out_params.append(new_param)
	current_resource.out_params = new_out_params
	current_resource.in_params_changed.emit()

func _on_in_popup_menu_pressed( id: int, row : FlowConnectorRow ) -> void:
	if id == IDM_PROMOTE_TO_PARAMETER and row:
		var node = row.getNode()
		print( "Promoting to parameter %s.%s (%s)" % [ node.name, row.getInLabel().text, row.data ] )
		var in_name = node.getMeta().title + " - " + row.data.label
		registerAsParameter( in_name, row.data.data_type )
		# Instantiate the input
		var new_input_node = _on_inputs_menu_id_pressed( current_resource.in_params.size() - 1 )
		if new_input_node:
			# Adjust the positions, the size is correct, our left is the parent left - size
			new_input_node.position_offset.x = node.position_offset.x - new_input_node.size.x - 40
			new_input_node.position_offset.y -= new_input_node.size.y - 15
			# Connect the input to the node
			_on_graph_edit_connection_request( new_input_node.name, 0, node.name, row.data.port )
		populatePopupInputsMenu()
		
func _on_graph_edit_delete_nodes_request(node_names : Array):
	print( "_on_graph_edit_delete_nodes_request", node_names )
	var before_state = get_graph_snapshot()
	var frames : Array[ GraphFrame ]
	var nodes : Array[ GraphNode ]
	for node_name in node_names:
		var node = gedit.get_node( node_name )
		if not node:
			push_error( "Failed to find node %s to be deleted" % node_name)
			continue
		if node is GraphNode:
			nodes.append(node)
		elif node is GraphFrame:
			frames.append(node)
	deleteGraphElementsAndRefresh( nodes, frames )
	record_undo_action("Delete Nodes", before_state)

func _on_graph_edit_popup_request(at_position):
	if suppress_next_popup_request:
		suppress_next_popup_request = false
		return
	_open_graph_context_menu(at_position)

func _open_graph_context_menu(at_position: Vector2):
	local_drop_position = at_position
	
	if popup_on_over_input:
		var node = popup_on_over_input.getNode()
		var pm := PopupMenu.new()
		add_child( pm )
		pm.name = "InPopupMenu"
		pm.add_item( FlowI18n.t("Promote To Parameter"), IDM_PROMOTE_TO_PARAMETER, KEY_NONE )
		pm.id_pressed.connect( _on_in_popup_menu_pressed.bind( popup_on_over_input ) )
		pm.position = get_screen_position() + at_position + Vector2( 20, 20 )
		pm.popup()
		#print( "Show popup associated to %s.%s" % [ node.name, popup_on_over_input.getInLabel().text ] )
		return

	var target_frame := _get_target_comment_frame(at_position)
	if target_frame:
		var frame_menu := PopupMenu.new()
		add_child(frame_menu)
		frame_menu.name = "FramePopupMenu"
		frame_menu.add_item(FlowI18n.t("Add Selected Nodes"), IDM_FRAME_ADD_SELECTED_NODES)
		frame_menu.add_item(FlowI18n.t("Remove Selected Nodes"), IDM_FRAME_REMOVE_SELECTED_NODES)
		frame_menu.id_pressed.connect(_on_frame_context_menu_pressed.bind(target_frame))
		frame_menu.position = get_screen_position() + at_position + Vector2(20, 20)
		frame_menu.popup()
		return
	
	var required_input_type := FlowData.DataType.Invalid
	var required_output_type := FlowData.DataType.Invalid
	if auto_connect_from_node:
		var from_node = gedit_nodes_by_name.get( auto_connect_from_node )
		if from_node:
			var meta = from_node.getMeta()
			if auto_connect_from_port < meta.outs.size():
				var oport = meta.outs[ auto_connect_from_port ]
				required_input_type = oport.get( "data_type", FlowData.DataType.Invalid )

	if auto_connect_to_node:
		var to_node = gedit_nodes_by_name.get( auto_connect_to_node )
		if to_node:
			var meta = to_node.getMeta()
			if auto_connect_to_port < meta.ins.size():
				var iport = meta.ins[ auto_connect_to_port ]
				required_output_type = iport.get( "data_type", FlowData.DataType.Invalid )

	var in_params = []
	var out_params = []
	if current_resource:
		in_params = current_resource.in_params
		if "out_params" in current_resource:
			out_params = current_resource.out_params
		
	search_add_node_popup.setup(node_types, in_params, out_params, getSelectedNodes().size() > 0, required_input_type, required_output_type)
	search_add_node_popup.position = get_screen_position() + at_position
	search_add_node_popup.popup()
	
	
func openAddMenu():
	var pos = get_local_mouse_position()
	_open_graph_context_menu( pos )

func _on_inputs_menu_id_pressed(id: int):
	var input = current_resource.in_params[id]
	var node_type = "input_%s" % input.name
	print( "Creating a input node: %s (%d) -> %s" % [ input.name, input.data_type, node_type] )
	var settings := InputNodeSettings.new()
	settings.name = input.name
	settings.data_type = input.data_type
	return addNode( node_type, settings )

func _on_outputs_menu_id_pressed(id: int):
	var output = current_resource.out_params[id]
	var node_type = "output_%s" % output.name
	print( "Creating an output node: %s (%d) -> %s" % [ output.name, output.data_type, node_type] )
	var settings := OutputNodeSettings.new()
	settings.name = output.name
	settings.data_type = output.data_type
	return addNode( node_type, settings )

func _on_popup_menu_id_pressed(id: int) -> void:
	if id == IDM_COLLAPSE_TO_SUBGRAPH:
		collapse_selected_to_subgraph()
	elif menu_ids.has( id ):
		var key = menu_ids[ id ]
		addNode( key )
	else:
		# Highlight the connection...
		var nodes = getSelectedNodes()
		if nodes.size() > 1:
			var node = nodes[0]
			var target = nodes[1]
			gedit.set_connection_activity( node.name, 0, target.name, 0, 1.0)

func collapse_selected_to_subgraph():
	var selected_nodes = getSelectedNodes()
	if selected_nodes.is_empty():
		return
		
	# Determine unique path in same folder as current resource
	var base_dir = "res://"
	if current_resource and current_resource.resource_path != "":
		base_dir = current_resource.resource_path.get_base_dir()
		
	var path = base_dir.path_join("subgraph_collapsed.tres")
	var counter = 1
	while ResourceLoader.exists(path):
		path = base_dir.path_join("subgraph_collapsed_%d.tres" % counter)
		counter += 1
		
	var before_state = get_graph_snapshot()
	
	var selected_node_names = {}
	for node in selected_nodes:
		selected_node_names[node.name] = true
		
	var internal_links = []
	var input_boundary_list = []
	var output_boundary_list = []
	
	for conn in gedit.connections:
		var from_sel = selected_node_names.has(conn.from_node)
		var to_sel = selected_node_names.has(conn.to_node)
		
		if from_sel and to_sel:
			internal_links.append(conn)
		elif not from_sel and to_sel:
			var found = false
			for item in input_boundary_list:
				if item.from_node == conn.from_node and item.from_port == conn.from_port:
					item.targets.append({"to_node": conn.to_node, "to_port": conn.to_port})
					found = true
					break
			if not found:
				input_boundary_list.append({
					"from_node": conn.from_node,
					"from_port": conn.from_port,
					"targets": [{"to_node": conn.to_node, "to_port": conn.to_port}]
				})
		elif from_sel and not to_sel:
			var found = false
			for item in output_boundary_list:
				if item.from_node == conn.from_node and item.from_port == conn.from_port:
					item.targets.append({"to_node": conn.to_node, "to_port": conn.to_port})
					found = true
					break
			if not found:
				output_boundary_list.append({
					"from_node": conn.from_node,
					"from_port": conn.from_port,
					"targets": [{"to_node": conn.to_node, "to_port": conn.to_port}]
				})
				
	# Calculate positions
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	var avg_pos = Vector2.ZERO
	for node in selected_nodes:
		var pos = node.position_offset / ui_scale
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.y = minf(min_pos.y, pos.y)
		max_pos.x = maxf(max_pos.x, pos.x + node.size.x / ui_scale)
		max_pos.y = maxf(max_pos.y, pos.y + node.size.y / ui_scale)
		avg_pos += node.position_offset
	avg_pos /= selected_nodes.size()
	
	# Serialize selected nodes relative to min_pos
	var subgraph_data = FlowNodeIO.nodes_as_dict(selected_nodes, [], self)
	var parsed_min_pos = FlowNodeIO._parse_vector2(subgraph_data.get("min_pos", Vector2.ZERO))
	
	var links_clean = []
	for link in internal_links:
		links_clean.append({
			"from_node": link.from_node,
			"from_port": link.from_port,
			"to_node": link.to_node,
			"to_port": link.to_port
		})
	subgraph_data["links"] = links_clean
	
	var nodes_clean = subgraph_data.get("nodes", [])
	
	# Create input parameters and input nodes in the subgraph
	var subgraph_in_params : Array[GraphInputParameter] = []
	var input_idx = 0
	for item in input_boundary_list:
		var first_target = item.targets[0]
		var target_node = gedit_nodes_by_name.get(first_target.to_node)
		var port_label = "in"
		var data_type = FlowData.DataType.Float
		if target_node:
			var target_meta = target_node.getMeta()
			if first_target.to_port < target_meta.ins.size():
				port_label = target_meta.ins[first_target.to_port].get("label", "in")
				data_type = target_meta.ins[first_target.to_port].get("data_type", FlowData.DataType.Float)
				
		var param_name = "in_" + target_node.name + "_" + port_label
		
		var param = GraphInputParameter.new()
		param.name = param_name
		param.data_type = data_type
		subgraph_in_params.append(param)
		
		var input_node_name = "input_" + param_name
		nodes_clean.append({
			"position": Vector2(-250.0, input_idx * 150.0),
			"name": input_node_name,
			"template": "input_" + param_name,
			"show_disconnected_inputs": false,
			"args_port": {},
			"settings": {
				"name": param_name,
				"data_type": data_type
			}
		})
		
		for target in item.targets:
			subgraph_data["links"].append({
				"from_node": input_node_name,
				"from_port": 0,
				"to_node": target.to_node,
				"to_port": target.to_port
			})
			
		item["param_name"] = param_name
		item["param_idx"] = input_idx
		input_idx += 1
		
	# Create output nodes in the subgraph
	var output_idx = 0
	for item in output_boundary_list:
		var source_node = gedit_nodes_by_name.get(item.from_node)
		var port_label = "out"
		var data_type = FlowData.DataType.Float
		if source_node:
			var source_meta = source_node.getMeta()
			if item.from_port < source_meta.outs.size():
				port_label = source_meta.outs[item.from_port].get("label", "out")
				data_type = source_meta.outs[item.from_port].get("data_type", FlowData.DataType.Float)
				
		var out_name = "out_" + source_node.name + "_" + port_label
		var output_node_name = "output_" + out_name
		nodes_clean.append({
			"position": Vector2((max_pos.x - parsed_min_pos.x) + 100.0, output_idx * 150.0),
			"name": output_node_name,
			"template": "output",
			"show_disconnected_inputs": false,
			"args_port": {},
			"settings": {
				"name": out_name,
				"data_type": data_type
			}
		})
		
		subgraph_data["links"].append({
			"from_node": item.from_node,
			"from_port": item.from_port,
			"to_node": output_node_name,
			"to_port": 0
		})
		
		item["out_name"] = out_name
		item["out_idx"] = output_idx
		output_idx += 1
		
	subgraph_data["nodes"] = nodes_clean
	
	# Build output params from the output boundary (mirrors how in_params are built)
	var subgraph_out_params : Array[GraphInputParameter] = []
	for item in output_boundary_list:
		var param = GraphInputParameter.new()
		param.name = item["out_name"]
		var source_node = gedit_nodes_by_name.get(item.from_node)
		if source_node:
			var source_meta = source_node.getMeta()
			if item.from_port < source_meta.outs.size():
				param.data_type = source_meta.outs[item.from_port].get("data_type", FlowData.DataType.Float)
		subgraph_out_params.append(param)
	
	# Save subgraph resource
	var subgraph_res = FlowGraphResource.new()
	subgraph_res.data = subgraph_data
	subgraph_res.in_params = subgraph_in_params
	subgraph_res.out_params = subgraph_out_params
	var save_err = ResourceSaver.save(subgraph_res, path)
	if save_err != OK:
		push_error("Failed to save collapsed subgraph to %s" % path)
		return
		
	# Load the resource fresh from disk (bypass cache) to ensure we get the just-saved version
	var loaded_subgraph = ResourceLoader.load(path, "Resource", ResourceLoader.CACHE_MODE_REPLACE)
	
	# Prepare parent graph state change
	var after_nodes = []
	for node in before_state.nodes:
		if not selected_node_names.has(node.name):
			after_nodes.append(node)
			
	var subgraph_node_name = getNewName("subgraph")
	var before_min_pos = FlowNodeIO._parse_vector2(before_state.min_pos)
	var subgraph_node_dict = {
		"position": Vector2((avg_pos.x / ui_scale) - before_min_pos.x, (avg_pos.y / ui_scale) - before_min_pos.y),
		"name": subgraph_node_name,
		"template": "subgraph",
		"show_disconnected_inputs": false,
		"args_port": {},
		"settings": {
			"graph": loaded_subgraph
		}
	}
	after_nodes.append(subgraph_node_dict)
	
	var after_links = []
	for link in before_state.links:
		if not selected_node_names.has(link.from_node) and not selected_node_names.has(link.to_node):
			after_links.append(link)
			
	# Connect external inputs to the subgraph node
	for item in input_boundary_list:
		after_links.append({
			"from_node": item.from_node,
			"from_port": item.from_port,
			"to_node": subgraph_node_name,
			"to_port": item.param_idx
		})
		
	# Connect subgraph node to external outputs
	for item in output_boundary_list:
		for target in item.targets:
			after_links.append({
				"from_node": subgraph_node_name,
				"from_port": item.out_idx,
				"to_node": target.to_node,
				"to_port": target.to_port
			})
			
	var after_frames = []
	for frame in before_state.frames:
		if not frame.name in before_state.selected_names:
			var attached : Array[StringName] = []
			for node_name in frame.attached:
				if not selected_node_names.has(node_name):
					attached.append(node_name)
			frame.attached = attached
			after_frames.append(frame)
			
	var after_absolute_positions = {}
	for node in after_nodes:
		if node.name == subgraph_node_name:
			after_absolute_positions[node.name] = [avg_pos.x, avg_pos.y]
		else:
			if before_state.absolute_positions.has(node.name):
				after_absolute_positions[node.name] = before_state.absolute_positions[node.name]
				
	for frame in after_frames:
		if before_state.absolute_positions.has(frame.name):
			after_absolute_positions[frame.name] = before_state.absolute_positions[frame.name]
			
	var after_state = {
		"type": "flow_graph_nodes",
		"version": 1,
		"min_pos": before_state.min_pos,
		"zoom": before_state.zoom,
		"scroll_offset": before_state.scroll_offset,
		"new_name_counter": new_name_counter,
		"absolute_positions": after_absolute_positions,
		"selected_names": [subgraph_node_name],
		"inspected_node_name": subgraph_node_name,
		"nodes": after_nodes,
		"links": after_links,
		"frames": after_frames
	}
	
	load_graph_state(after_state)
	record_undo_action("Collapse to Subgraph", before_state)

func disconnect_nodes(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	#print( "disconnect_nodes From:%s:%d To:%s:%d" % [ from_node, from_port, to_node, to_port ])
	var connection = {
		"from_node": from_node,
		"from_port": from_port,
		"to_node": to_node,
		"to_port": to_port
	}
	if _has_graph_connection(connection):
		gedit.disconnect_node(from_node, from_port, to_node, to_port)
	remove_input_source_target_connection( from_node, from_port, to_node, to_port )
	_mark_status_counts_dirty()

	var dst_node : FlowNodeBase = gedit_nodes_by_name.get( to_node )
	if dst_node != null:
		dst_node.dirty = true
	
func connect_nodes(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	#print( "connect_nodes %s:%d -> %s:%d" % [ from_node, from_port, to_node, to_port ] )
	var connection = {
		"from_node": from_node,
		"from_port": from_port,
		"to_node": to_node,
		"to_port": to_port
	}
	if not _has_graph_connection(connection):
		gedit.connect_node(from_node, from_port, to_node, to_port)
	_mark_status_counts_dirty()
	_add_input_source_target_connection(from_node, from_port, to_node, to_port)

	var dst_node : FlowNodeBase = gedit_nodes_by_name.get( to_node )
	if dst_node != null:
		dst_node.dirty = true

func _add_input_source_target_connection(from_node: StringName, from_port: int, to_node: StringName, to_port: int):
	var key = [to_node, to_port]
	if not input_sources.has(key):
		input_sources.set( key, [])
	var source = [from_node, from_port]
	if not input_sources[key].has(source):
		input_sources[key].append(source)


func findConnectionToNodeAndPort( node : FlowNodeBase, in_port : int ):
	for conn in node.deps:
		if conn.to_port == in_port:
			return conn
	return null

func _on_graph_edit_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var src_node = gedit_nodes_by_name.get( from_node )
	var dst_node = gedit_nodes_by_name.get( to_node )
	if not canConnect( src_node, from_port, dst_node, to_port ):
		return
	
	var conns_to_remove = []
	# Check if the input does not allow multiple connections
	var to_port_meta = dst_node.getMeta().ins[ to_port ] if to_port < dst_node.getMeta().ins.size() else {}
	if not to_port_meta.get( "multiple_connections", true ):
		var conn = findConnectionToNodeAndPort( dst_node, to_port )
		if conn != null:
			conns_to_remove.append({
				"from_node": conn.from_node,
				"from_port": conn.from_port,
				"to_node": conn.to_node,
				"to_port": conn.to_port
			})
	
	var conns_to_add = [{
		"from_node": from_node,
		"from_port": from_port,
		"to_node": to_node,
		"to_port": to_port
	}]
	
	var ur = undo_redo
	if ur and current_resource:
		var context = EditorInterface.get_edited_scene_root()
		if not context:
			context = current_resource
		ur.create_action("Connect Nodes", 0, context)
		ur.add_do_method(self, "apply_connections_change", conns_to_remove, conns_to_add)
		ur.add_undo_method(self, "apply_connections_change", conns_to_add, conns_to_remove)
		ur.commit_action(true) # execute immediately
	else:
		apply_connections_change(conns_to_remove, conns_to_add)
	
func get_connected_sources(to_node: StringName, to_port: int) -> Array:
	return input_sources.get([to_node, to_port], [])
	
func is_node_port_connected( to_node: StringName, to_port: int ) -> bool:
	return not input_sources.get([to_node, to_port], []).is_empty()
	
func remove_input_source_target_connection( from_node: StringName, from_port: int, to_node : StringName, to_port : int ):
	var key = [to_node, to_port]
	if key in input_sources:
		var source = [from_node, from_port]
		while input_sources[key].has(source):
			input_sources[key].erase(source)
		if input_sources[key].is_empty():
			input_sources.erase(key)
	
func remove_all_inputs_to_target_connection( to_node : StringName, to_port : int ):
	var key = [to_node, to_port]
	if key in input_sources:
		input_sources.erase(key)
	
func remove_all_inputs_to_source_connection( from_node : StringName, from_port : int ):
	var conns_to_delete = []
	for key in input_sources.keys():
		for src in input_sources[ key ]:
			if src[0] == from_node && src[1] == from_port:
				conns_to_delete.append( [ src[0], src[1], key[0], key[1] ] )
	for conn in conns_to_delete:
		remove_input_source_target_connection( conn[0], conn[1], conn[2], conn[3])
	
func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	var conns_to_remove = [{
		"from_node": from_node,
		"from_port": from_port,
		"to_node": to_node,
		"to_port": to_port
	}]
	var conns_to_add = []
	
	var ur = undo_redo
	if ur and current_resource:
		var context = EditorInterface.get_edited_scene_root()
		if not context:
			context = current_resource
		ur.create_action("Disconnect Nodes", 0, context)
		ur.add_do_method(self, "apply_connections_change", conns_to_remove, conns_to_add)
		ur.add_undo_method(self, "apply_connections_change", conns_to_add, conns_to_remove)
		ur.commit_action(true) # execute immediately
	else:
		apply_connections_change(conns_to_remove, conns_to_add)

func _on_graph_edit_connection_to_empty(from_node: StringName, from_port: int, release_position: Vector2) -> void:
	auto_connect_from_node = from_node
	auto_connect_from_port = from_port
	auto_connect_to_node = ""
	local_drop_position = release_position
	_on_graph_edit_popup_request( local_drop_position )

func _on_graph_edit_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
	auto_connect_to_node = to_node
	auto_connect_to_port = to_port
	auto_connect_from_node = ""
	local_drop_position = release_position
	_on_graph_edit_popup_request( local_drop_position )

func getDeps( node : FlowNodeBase ) -> Array[ FlowNodeBase ]:
	var deps : Array[ FlowNodeBase ] = [ node ]
	for conn in node.deps:
		var dep_node = gedit_nodes_by_name.get( conn.from_node, null )
		if not dep_node:
			continue
		var req_deps = getDeps( dep_node )
		deps.append_array( req_deps )
	return deps
	
func getAllNodes() -> Array[ FlowNodeBase ]:
	var nodes : Array[ FlowNodeBase ] = []
	for child in gedit.get_children():
		var node = child as FlowNodeBase
		if not node:
			continue
		nodes.append( node )
	return nodes

func getSetVariableNodes(variable_name: String = "", exclude_node: FlowNodeBase = null) -> Array[FlowNodeBase]:
	var nodes : Array[FlowNodeBase] = []
	var requested_name := variable_name.strip_edges()
	for node in getAllNodes():
		if node == exclude_node:
			continue
		if node.node_template != "set_variable" or not node.settings or not ("variable_name" in node.settings):
			continue
		var set_name := String(node.settings.variable_name).strip_edges()
		if set_name.is_empty():
			continue
		if not requested_name.is_empty() and set_name != requested_name:
			continue
		nodes.append(node)
	return nodes

func getGetVariableNodes(variable_name: String = "") -> Array[FlowNodeBase]:
	var nodes : Array[FlowNodeBase] = []
	var requested_name := variable_name.strip_edges()
	if requested_name.is_empty():
		return nodes
	for node in getAllNodes():
		if node.node_template != "get_variable" or not node.settings or not ("variable_name" in node.settings):
			continue
		var get_name := String(node.settings.variable_name).strip_edges()
		if get_name == requested_name:
			nodes.append(node)
	nodes.sort_custom(func(a: FlowNodeBase, b: FlowNodeBase) -> bool:
		return String(a.name) < String(b.name)
	)
	return nodes

func flash_linked_get_variable_nodes(set_node: FlowNodeBase) -> void:
	if set_node == null or not is_instance_valid(set_node):
		return
	if set_node.node_template != "set_variable":
		return
	var variable_name := FlowVariableEval.variable_name_from_node(set_node)
	if variable_name.is_empty():
		return
	for get_node in getGetVariableNodes(variable_name):
		_flash_graph_node_white_twice(get_node)

func flash_linked_set_variable_nodes(get_node: FlowNodeBase) -> void:
	if get_node == null or not is_instance_valid(get_node):
		return
	if get_node.node_template != "get_variable":
		return
	var variable_name := FlowVariableEval.variable_name_from_node(get_node)
	if variable_name.is_empty():
		return
	for set_node in getSetVariableNodes(variable_name):
		_flash_graph_node_white_twice(set_node)

func _flash_graph_node_white_twice(node: CanvasItem) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _variable_link_flash_tweens.has(node):
		var old_tween: Tween = _variable_link_flash_tweens[node]
		if old_tween and old_tween.is_valid():
			old_tween.kill()
		_variable_link_flash_tweens.erase(node)
	var base_modulate := node.modulate
	var flash_modulate := Color(
		minf(base_modulate.r + 0.55, 2.0),
		minf(base_modulate.g + 0.55, 2.0),
		minf(base_modulate.b + 0.55, 2.0),
		base_modulate.a,
	)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	_variable_link_flash_tweens[node] = tween
	for _i in VARIABLE_LINK_FLASH_COUNT:
		tween.tween_property(node, "modulate", flash_modulate, VARIABLE_LINK_FLASH_UP_SEC)
		tween.tween_property(node, "modulate", base_modulate, VARIABLE_LINK_FLASH_DOWN_SEC)
	tween.finished.connect(func() -> void:
		if is_instance_valid(node):
			node.modulate = base_modulate
		_variable_link_flash_tweens.erase(node)
	, CONNECT_ONE_SHOT)

func _set_variable_name_exists(variable_name: String, exclude_node: FlowNodeBase = null) -> bool:
	return not getSetVariableNodes(variable_name, exclude_node).is_empty()

func getUniqueSetVariableName(base_name: String, exclude_node: FlowNodeBase = null) -> String:
	var root_name := base_name.strip_edges()
	if root_name.is_empty():
		root_name = "variable"
	if not _set_variable_name_exists(root_name, exclude_node):
		return root_name

	var index := 2
	while true:
		var candidate := "%s_%d" % [root_name, index]
		if not _set_variable_name_exists(candidate, exclude_node):
			return candidate
		index += 1
	return root_name

func ensureSetVariableNameUnique(node: FlowNodeBase, refresh_node := true) -> String:
	if node == null or node.node_template != "set_variable" or not node.settings or not ("variable_name" in node.settings):
		return ""
	var variable_name := String(node.settings.variable_name).strip_edges()
	var unique_variable_name := getUniqueSetVariableName(variable_name, node)
	if unique_variable_name == variable_name:
		return unique_variable_name
	node.settings.variable_name = unique_variable_name
	if refresh_node:
		if node.settings is Resource:
			node.settings.emit_changed()
		elif node.is_inside_tree():
			node.refreshFromSettings()
	return unique_variable_name

func findSetVariableNode(variable_name: String) -> FlowNodeBase:
	for node in getSetVariableNodes(variable_name):
		return node
	return null

func panToGraphNode(node: GraphNode, select_node: bool = false) -> bool:
	if node == null or not is_instance_valid(node) or gedit == null:
		return false
	if select_node:
		for selected_node in getSelectedNodes():
			selected_node.selected = false
		for selected_frame in getSelectedFrames():
			selected_frame.selected = false
		node.selected = true
		inspected_node = node
		_ensure_inspector()
		if inspector:
			inspector.edit(node)
	node.visible = true
	var target_center := node.position_offset + node.size * 0.5
	gedit.scroll_offset = target_center * gedit.zoom - gedit.size * 0.5
	return true

func focusSetVariableNode(variable_name: String) -> bool:
	var node := findSetVariableNode(variable_name)
	if node == null:
		update_status_bar("Set variable not found: %s" % variable_name)
		return false
	panToGraphNode(node, true)
	update_status_bar("Located set variable: %s" % variable_name)
	return true

func focusGetVariableNode(get_node: GraphNode) -> bool:
	if get_node == null or not is_instance_valid(get_node):
		return false
	panToGraphNode(get_node, false)
	var label := get_node.name
	if get_node is FlowNodeBase and get_node.has_method("getTitle"):
		label = String(get_node.call("getTitle"))
	update_status_bar(FlowI18n.t("Located get: %s") % label)
	return true

func getSetVariableDefinitions() -> Array[Dictionary]:
	var definitions_by_name := {}
	for node in getSetVariableNodes():
		var variable_name := String(node.settings.variable_name).strip_edges()
		definitions_by_name[variable_name] = node.settings.node_color
	var names = definitions_by_name.keys()
	names.sort()
	var definitions : Array[Dictionary] = []
	for variable_name in names:
		definitions.append({
			"name": variable_name,
			"color": definitions_by_name[variable_name],
		})
	return definitions

func getSetVariableColor(variable_name: String) -> Color:
	var requested_name := variable_name.strip_edges()
	for node in getSetVariableNodes(requested_name):
		return node.settings.node_color
	return Color("22d3ee")

func refreshVariableNodes() -> void:
	for node in getAllNodes():
		if node.node_template != "set_variable" and node.node_template != "get_variable":
			continue
		if node.has_method("refreshVariableChoices"):
			node.refreshVariableChoices()
		node.dirty = true
		node.refreshFromSettings()
	
func getEvalOrder():
	# Find targets, like spawn meshes
	var finals := getAllNodes().filter(func(node: FlowNodeBase) -> bool:
		if node.settings.disabled:
			return false
		return FlowNodeIO._is_topo_final_root(node)
	)
	
	# for each node, find requirements
	# A -
	#    -- C - D
	# B -
	# D -> C -> A -> B
	var all_deps : Array[ FlowNodeBase ]
	for node in finals:
		var node_deps = getDeps( node )
		all_deps.append_array( node_deps )
	
	# Evaluate in inverse order
	# B, A, C, D
	all_deps.reverse()	
	return all_deps

func removeGeneratedNodes():
	if not resource_owner:
		return
	# Remove instances from prev execution
	var nodes_to_remove = []
	for child in resource_owner.get_children():
		if child.has_meta( "flow_owner" ):
			nodes_to_remove.append(child)
	#print( "Removing %d generated comps" % [nodes_to_remove.size()])
	for child in nodes_to_remove:
		resource_owner.remove_child( child )
		child.queue_free()

func getDirtyNodes() -> Array[ FlowNodeBase ]:
	return getAllNodes().filter( func( node : FlowNodeBase ) -> bool:
		return node.dirty 
	)

func cacheConnections():
	
	# Clear all the arrays
	var nodes := getAllNodes()
	for node in nodes:
		node.deps.clear()
		node.dependants.clear()
			
	# Add each connection to left and right sides
	for conn in gedit.connections:
		var src_node = gedit_nodes_by_name.get( conn.from_node )
		var dst_node = gedit_nodes_by_name.get( conn.to_node )
		if src_node and dst_node:
			src_node.dependants.append( conn )
			dst_node.deps.append( conn )
	_cache_variable_dependencies(nodes)

	#for node in getAllNodes():
		#print( "Node: %s" % [ node.name ])
		#print( "  deps: %s" % [ node.deps ])
		#print( "  dependants: %s" % [ node.dependants ])

func _cache_variable_dependencies(nodes: Array[FlowNodeBase]) -> void:
	var set_nodes_by_name := {}
	for node in nodes:
		if node.node_template != "set_variable" or not node.settings or not ("variable_name" in node.settings):
			continue
		var variable_name := String(node.settings.variable_name).strip_edges()
		if variable_name.is_empty():
			continue
		if not set_nodes_by_name.has(variable_name):
			set_nodes_by_name[variable_name] = []
		set_nodes_by_name[variable_name].append(node)

	for node in nodes:
		if node.node_template != "get_variable" or not node.settings or not ("variable_name" in node.settings):
			continue
		var variable_name := String(node.settings.variable_name).strip_edges()
		if variable_name.is_empty() or not set_nodes_by_name.has(variable_name):
			continue
		var set_nodes : Array = set_nodes_by_name[variable_name].duplicate()
		set_nodes.reverse()
		for set_node in set_nodes:
			var conn = {
				"from_node": set_node.name,
				"from_port": 0,
				"to_node": node.name,
				"to_port": -1,
				"virtual_variable": true,
			}
			set_node.dependants.append(conn)
			node.deps.append(conn)

func expandDirtyFlagToDependants( node : FlowNodeBase ):
	#print( "%s is dirty" % [ node.name ] )
	for out_conn in node.dependants:
		#print( "  -> %s" % [ out_conn ])
		var dst_node = gedit_nodes_by_name.get( out_conn.to_node )
		if dst_node:
			if not dst_node.dirty:
				dst_node.dirty = true
				expandDirtyFlagToDependants( dst_node )

func _begin_eval_graph() -> Dictionary:
	ctx.eval_id += 1
	ctx.variables.clear()
	
	var time_start = Time.get_ticks_usec()
	
	# print( "evalGraph %d starts from %s" % [ ctx.eval_id, resource_owner.name if resource_owner else "null" ] )
	removeGeneratedNodes()
	
	cacheConnections()
	# Generated instances are cleared globally; keep all final producers dirty so
	# unaffected branches respawn instead of disappearing during analyze/debug.
	markFinalNodesAsDirty()
	
	active_intensity = 1.0
	active_nodes.clear()
	
	var dirty_nodes := getDirtyNodes()
	for node in dirty_nodes:
		expandDirtyFlagToDependants( node )
	dirty_nodes = getDirtyNodes()
	#for node in dirty_nodes:
		#print( "Dirty: %s" % node.name )
	
	#print( "getEvalOrder..." )
	return {
		"time_start": time_start,
		"nodes_to_eval": getEvalOrder(),
		"performance": [],
	}

func _evaluate_graph_node(node: FlowNodeBase, performance: Array) -> void:
	#print( "  Eval: %s (%d) Dirty:%s" % [ node.name, node.eval_id, node.dirty ] )

	# The node has already been evaluated or it's not dirty. No need to reevaluate it
	if node.eval_id == ctx.eval_id or not node.dirty:
		return

	var time_node_start = Time.get_ticks_usec()
	active_nodes.append( node )

	node.preExecute( ctx )

	#print( "Evaluating %s" % node.name )
	if node.settings.disabled:
		node.executedDisabled( ctx )
	elif not FlowVariableEval.try_fast_execute( node, ctx, ctx.gedit_nodes_by_name ):
		node.run( ctx )

	if node.settings.inspect_enabled:
		_queue_data_inspector_refresh(node)
	if FlowVariableEval.should_refresh_debug_draw( node ):
		node.setupDrawDebug()
	node.dirty = false
	var time_node_ends = Time.get_ticks_usec()
	var exec_usec = time_node_ends - time_node_start

	# Always show execution time on the node
	node.setExecTime(exec_usec)

	if dump_performance:
		performance.append( { "name": node.name, "time": exec_usec })

func _queue_data_inspector_refresh(node: FlowNodeBase) -> void:
	if data_inspector and analyze_panel and analyze_panel.visible and node == current_analyzed_node:
		data_inspector_refresh_pending = true

func _flush_data_inspector_refresh() -> void:
	if data_inspector_refresh_pending and data_inspector and analyze_panel and analyze_panel.visible:
		data_inspector.refresh()
	data_inspector_refresh_pending = false

func _finish_eval_graph(eval_state: Dictionary) -> void:
	regen_pending = false
	#print( "regen_pending is now false")
	_flush_data_inspector_refresh()
	
	var elapsed_usec = Time.get_ticks_usec() - eval_state.time_start
	update_status_bar("%d evals in %.3f ms" % [ ctx.eval_id, elapsed_usec / 1000.0 ])
	if dump_performance:
		for entry in eval_state.performance:
			var formatted := "%8.1s" % String.num(entry.time, 1)
			print( "%s usecs %s" % [ formatted, entry.name ] )
		dump_performance = false

func evalGraph():
	if regen_running:
		regen_requested_while_running = true
		return
	var run_id := _start_regen_run()
	var eval_state := _begin_eval_graph()
	for node in eval_state.nodes_to_eval:
		if not _is_current_regen_run(run_id):
			return
		if not is_instance_valid(node):
			continue
		_evaluate_graph_node(node, eval_state.performance)
	if not _is_current_regen_run(run_id):
		return
	_finish_eval_graph(eval_state)
	_complete_regen_run(run_id)

func evalGraphAsync() -> void:
	if regen_running:
		regen_requested_while_running = true
		return
	var run_id := _start_regen_run()
	var eval_state := _begin_eval_graph()
	var frame_start := Time.get_ticks_usec()
	for node in eval_state.nodes_to_eval:
		if not _is_current_regen_run(run_id):
			return
		if not is_instance_valid(node):
			continue
		_evaluate_graph_node(node, eval_state.performance)
		if Time.get_ticks_usec() - frame_start >= AUTO_REGEN_FRAME_BUDGET_USEC:
			await get_tree().process_frame
			if not _is_current_regen_run(run_id):
				return
			frame_start = Time.get_ticks_usec()
	if not _is_current_regen_run(run_id):
		return
	_finish_eval_graph(eval_state)
	_complete_regen_run(run_id)

func _on_button_reload_pressed() -> void:
	if graph_reload_in_progress:
		return
	await _reload_current_graph_with_loading()

func _reload_current_graph_with_loading() -> void:
	if graph_reload_in_progress:
		return
	if not current_resource:
		scanAvailableNodesIfNeeded()
		return

	graph_reload_in_progress = true
	_set_graph_loading_progress("Reloading Graph...", 8.0)
	await get_tree().process_frame
	_set_graph_loading_progress("Refreshing Resource...", 18.0)
	_refresh_active_tab_resource_from_disk()
	_set_graph_loading_progress("Scanning Nodes...", 24.0)
	scanAvailableNodesIfNeeded()
	_set_graph_loading_progress("Clearing Graph...", 34.0)
	_clear_ui_nodes()
	if _should_use_fast_graph_load(current_resource):
		FlowNodeIO.loadFromResource(self)
	else:
		await FlowNodeIO.loadFromResourceWithProgress(self, Callable(self, "_set_graph_loading_progress"))
	_set_graph_loading_progress("Finalizing Graph...", 96.0)
	ctx.graph = current_resource
	ctx.owner = resource_owner
	ctx.gedit_nodes_by_name = gedit_nodes_by_name
	markAllNodesAsDirty()
	queueForcedRegen()
	populatePopupInputsMenu()
	populatePopupOutputsMenu()
	update_status_bar()
	_set_graph_loading_progress("Graph Loaded", 100.0)
	await get_tree().process_frame
	_hide_graph_loading()
	graph_reload_in_progress = false

func _on_node_registry_changed() -> void:
	if current_resource and save_pending:
		saveResource()
	scanAvailableNodes(true)
	if not current_resource:
		return
	_clear_ui_nodes()
	FlowNodeIO.loadFromResource(self)
	ctx.graph = current_resource
	ctx.owner = resource_owner
	ctx.gedit_nodes_by_name = gedit_nodes_by_name
	markAllNodesAsDirty()
	queueRegen()
	populatePopupInputsMenu()
	populatePopupOutputsMenu()
	update_status_bar()

func _on_button_analyze_pressed() -> void:
	analyzeSelection()

func _on_button_save_pressed() -> void:
	ensureCurrentResource()
	if not current_resource:
		return
	if current_resource.resource_path == "":
		_show_save_graph_dialog()
		return
	_save_current_resource_to_path(current_resource.resource_path)

func markAllNodesAsDirty():
	for node in getAllNodes():
		node.dirty = true	

func markFinalNodesAsDirty():
	for node in getAllNodes():
		if node.settings.disabled:
			continue
		if node.getMeta().get("is_final", false):
			node.dirty = true

func _on_button_regenerate_pressed() -> void:
	#for key in input_sources.keys():
		#print( key )	
		#for val in input_sources[ key ]:
			#print( "  %s" % [ val ] )	
	#for conn in gedit.connections:
		#print( conn )
	dump_performance = true
	_cancel_regen_run()
	markAllNodesAsDirty()
	evalGraph()
	#for n : FlowNodeBase in getSelectedNodes():
		#print( "Node: %s  Ins:%d  Outs:%d" % [ n.name, n.num_in_ports, n.num_out_ports ])
		#for idx in range( n.num_in_ports ):
			#var type = n.get_slot_type_left( idx )
			#print( "Left.%d = %d" % [ idx, type ] )

func _on_auto_regen_toggled(toggled_on: bool) -> void:
	auto_regen = toggled_on
	if has_node("%AutoRegen") and %AutoRegen.button_pressed != toggled_on:
		%AutoRegen.set_pressed_no_signal(toggled_on)
	if not toggled_on:
		regen_pending = false
		regen_requested_while_running = false
	_save_editor_settings()

func _on_button_inputs_pressed():
	_show_graph_inputs_panel()

func _show_graph_inputs_panel():
	ensureCurrentResource()
	inspected_node = null
	_clear_graph_selection()
	if current_resource:
		_ensure_inspector()
		if inspector:
			inspector.edit(current_resource)

# Cut/Copy/Paste/Dupe
func _on_graph_edit_copy_nodes_request():
	FlowNodeIO.copySelectionToClipboard( self )

func _on_graph_edit_cut_nodes_request():
	_on_graph_edit_copy_nodes_request()
	deleteSelectedNodes()

func _on_graph_edit_paste_nodes_request():
	FlowNodeIO.pasteNodeFromClipboard( self )

func _on_graph_edit_duplicate_nodes_request():
	FlowNodeIO.duplicateSelecteddNodes( self )
	
func onEditorSceneChanged():
	if suppress_next_editor_scene_changed:
		suppress_next_editor_scene_changed = false
		return
	# When a node in the scene changes, just mark dirty all nodes
	# which can potentially become dirty
	# This also triggers as dirty all scan_* nodes when we change
	# anything in another of our nodes. Not very good
	for node in getAllNodes():
		node.dirty = true
	queueRegen()

func _suppress_next_editor_scene_changed() -> void:
	suppress_next_editor_scene_changed = true
	call_deferred("_clear_editor_scene_changed_suppression")

func _clear_editor_scene_changed_suppression() -> void:
	suppress_next_editor_scene_changed = false

func create_node_network(net_description: Dictionary) -> Dictionary:
	var created_nodes := {}
	
	# Create and configure nodes
	if net_description.has("nodes"):
		for n_desc in net_description["nodes"]:
			var template = n_desc.get("template", "")
			var name_key = n_desc.get("name_key", "")
			var settings_dict = n_desc.get("settings", {})
			var pos = n_desc.get("position", Vector2.ZERO)
			
			var node = addNode(template)
			if node:
				if name_key != "":
					created_nodes[name_key] = node
				node.position_offset = pos
				
				# Set settings
				for key in settings_dict:
					node.settings.set(key, settings_dict[key])
				node.settings.notify_property_list_changed()
				node.refreshFromSettings()
				
	# Connect nodes
	if net_description.has("links"):
		for link_desc in net_description["links"]:
			var from_key = link_desc.get("from", "")
			var from_port = link_desc.get("from_port", 0)
			var to_key = link_desc.get("to", "")
			var to_port = link_desc.get("to_port", 0)
			
			var from_node = created_nodes.get(from_key, null)
			var to_node = created_nodes.get(to_key, null)
			if from_node and to_node:
				if canConnect(from_node, from_port, to_node, to_port):
					connect_nodes(from_node.name, from_port, to_node.name, to_port)
					
	queueSave()
	queueRegen()
	return created_nodes

func get_graph_snapshot() -> Dictionary:
	var all_nodes = gedit.get_children().filter(func(n): return n is GraphNode)
	var all_frames = gedit.get_children().filter(func(n): return n is GraphFrame)
	var state = FlowNodeIO.nodes_as_dict(all_nodes, all_frames, self)
	state["zoom"] = gedit.zoom
	state["scroll_offset"] = [gedit.scroll_offset.x, gedit.scroll_offset.y]
	state["new_name_counter"] = new_name_counter
	
	# Save absolute positions of all nodes and frames
	var absolute_positions = {}
	for node in all_nodes:
		absolute_positions[node.name] = [node.position_offset.x, node.position_offset.y]
	for frame in all_frames:
		absolute_positions[frame.name] = [frame.position_offset.x, frame.position_offset.y]
	state["absolute_positions"] = absolute_positions
	
	# Save selection
	var selected_names = []
	for node in getSelectedNodes():
		selected_names.append(node.name)
	for frame in getSelectedFrames():
		selected_names.append(frame.name)
	state["selected_names"] = selected_names
	
	# Save inspected node
	if inspected_node:
		state["inspected_node_name"] = inspected_node.name
		
	return state

func get_graph_element_positions() -> Dictionary:
	var positions := {}
	for child in gedit.get_children():
		if child is GraphNode or child is GraphFrame:
			positions[child.name] = [child.position_offset.x, child.position_offset.y]
	return positions

func clear_graph():
	_cancel_regen_run()
	_clear_active_nodes()
	_mark_status_counts_dirty()
	gedit.clear_connections()
	input_sources.clear()
	for child in gedit.get_children():
		if child is GraphNode or child is GraphFrame:
			gedit.remove_child(child)
			child.queue_free()
	gedit_nodes_by_name.clear()
	inspected_node = null
	if data_inspector:
		data_inspector.setNode(null)
	_set_analyze_panel_visible(false)
	current_analyzed_node = null

func _clear_active_nodes() -> void:
	active_intensity = 0.0
	active_nodes.clear()

func load_graph_state(state: Dictionary):
	clear_graph()
	if state.has("new_name_counter"):
		new_name_counter = state.new_name_counter
	if state.has("min_pos"):
		var paste_offset = FlowNodeIO._parse_vector2(state.min_pos)
		FlowNodeIO.create_nodes_from_dict(state, self, paste_offset)
		
	# Restore absolute positions exactly if present
	if state.has("absolute_positions"):
		var abs_pos = state.absolute_positions
		for name in abs_pos:
			var node = gedit.get_node_or_null(NodePath(name))
			if node:
				var pos_arr = abs_pos[name]
				node.position_offset = Vector2(pos_arr[0], pos_arr[1])
				
	# Restore selection
	if state.has("selected_names"):
		for name in state.selected_names:
			var node = gedit.get_node_or_null(NodePath(name))
			if node:
				if node is GraphNode or node is GraphFrame:
					node.selected = true
					
	# Restore inspected node
	if state.has("inspected_node_name"):
		var node = gedit.get_node_or_null(NodePath(state.inspected_node_name))
		if node:
			inspected_node = node
			if node is GraphNode:
				inspector.edit(node.settings)
				if data_inspector:
					data_inspector.setNode(node)
					_set_analyze_panel_visible(true)
					current_analyzed_node = node
			elif node is GraphFrame:
				inspector.edit(node)
				
	queueSave()
	queueRegen()

func record_undo_action(action_name: String, before_state: Dictionary):
	var ur = undo_redo
	if ur and current_resource:
		var context = EditorInterface.get_edited_scene_root()
		if not context:
			context = current_resource
		var after_state = get_graph_snapshot()
		ur.create_action(action_name, 0, context)
		ur.add_do_method(self, "load_graph_state", after_state)
		ur.add_undo_method(self, "load_graph_state", before_state)
		
		# Also record new_name_counter
		current_resource.new_name_counter += 1
		ur.add_do_property(current_resource, "new_name_counter", current_resource.new_name_counter)
		ur.add_undo_property(current_resource, "new_name_counter", current_resource.new_name_counter - 1)
		
		ur.commit_action(false) # already executed
		queueSave()

func set_nodes_positions(positions: Dictionary):
	_suppress_next_editor_scene_changed()
	for name in positions:
		var node = gedit.get_node_or_null(NodePath(name))
		if node:
			var pos_arr = positions[name]
			node.position_offset = Vector2(pos_arr[0], pos_arr[1])
	queueSave()

func _on_graph_edit_begin_node_move():
	drag_start_snapshot = get_graph_element_positions()

func _on_graph_edit_end_node_move():
	var moved_nodes_before = {}
	var moved_nodes_after = {}
	if not drag_start_snapshot.is_empty():
		var start_positions = drag_start_snapshot
		for child in gedit.get_children():
			if child is GraphNode or child is GraphFrame:
				var start_pos_arr = start_positions.get(child.name, null)
				if start_pos_arr:
					var start_pos = Vector2(start_pos_arr[0], start_pos_arr[1])
					if (child.position_offset - start_pos).length() > 0.01:
						moved_nodes_before[child.name] = [start_pos.x, start_pos.y]
						moved_nodes_after[child.name] = [child.position_offset.x, child.position_offset.y]
						
	if not moved_nodes_before.is_empty():
		var ur = undo_redo
		if ur and current_resource:
			var context = EditorInterface.get_edited_scene_root()
			if not context:
				context = current_resource
			ur.create_action("Move Nodes", 0, context)
			ur.add_do_method(self, "set_nodes_positions", moved_nodes_after)
			ur.add_undo_method(self, "set_nodes_positions", moved_nodes_before)
			_suppress_next_editor_scene_changed()
			ur.commit_action(false) # already executed
			queueSave()
			
	drag_start_snapshot = {}

func _on_color_nodes_toggled(toggled_on: bool) -> void:
	color_nodes = toggled_on
	if has_node("%CheckColorNodes") and %CheckColorNodes.button_pressed != toggled_on:
		%CheckColorNodes.set_pressed_no_signal(toggled_on)
	for node in getAllNodes():
		node.refreshFromSettings()

func _on_hide_inspector_title_toggled(toggled_on: bool) -> void:
	hide_inspector_title = toggled_on
	_save_editor_settings()
	if inspector and inspected_node:
		inspector.edit(inspected_node)

func _on_track_external_edits_toggled(toggled_on: bool) -> void:
	track_external_edits = toggled_on
	_save_editor_settings()

func apply_connections_change(conns_to_remove: Array, conns_to_add: Array):
	for c in conns_to_remove:
		disconnect_nodes(c.from_node, c.from_port, c.to_node, c.to_port)
	for c in conns_to_add:
		connect_nodes(c.from_node, c.from_port, c.to_node, c.to_port)
	queueSave()
	queueRegen()
