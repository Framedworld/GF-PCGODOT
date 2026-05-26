@tool
extends Control

# This is the main container of the DataFlow Graph Editor

var current_resource: FlowGraphResource
var resource_owner : FlowGraphNode3D
var ctx := FlowData.EvaluationContext.new()
var regen_pending := false
var save_pending := false
var auto_regen := true
var dump_performance := false

@onready var gedit : GraphEdit = %GraphEdit
@onready var data_inspector : Control
@onready var info : Label = %LabelInfo

# The inspector shows the settings property of the current node
var inspector: FlowInspector
var inspected_node : Node
var make_inspector_visible : Callable
var search_add_node_popup: SearchAddNodePopup

# This is the default graph-node instantiated, the script contains the logic
var packed_node = preload("res://addons/flow_nodes_editor/node.tscn")
const directory_path := "res://addons/flow_nodes_editor/nodes"

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
var color_nodes : bool = true

var ui_scale = 1.0
var node_types = { }

var popup_menu_inputs : PopupMenu
var popup_menu_outputs : PopupMenu
var popup_on_over_input = null
const IDM_PROMOTE_TO_PARAMETER : int = 100
const IDM_COLLAPSE_TO_SUBGRAPH : int = 200

var tab_bar: TabBar
var open_tabs: Array[Dictionary] = []
var active_tab_index: int = -1
var open_file_dialog: FileDialog
var analyze_panel: PanelContainer
var current_analyzed_node: FlowNodeBase

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
			"owner": new_resource_owner
		})
		tab_bar.add_tab(tab_title)
		_switch_to_tab(open_tabs.size() - 1, new_resource_owner)

func _switch_to_tab(index: int, new_owner = null):
	if index < 0 or index >= open_tabs.size():
		return
		
	# Disconnect from old resource in_params_changed
	if current_resource and current_resource.in_params_changed.is_connected(_on_in_params_changed):
		current_resource.in_params_changed.disconnect(_on_in_params_changed)
		
	active_tab_index = index
	current_resource = open_tabs[index].resource
	
	# Connect to new resource in_params_changed
	if current_resource and not current_resource.in_params_changed.is_connected(_on_in_params_changed):
		current_resource.in_params_changed.connect(_on_in_params_changed)
	
	if new_owner != null:
		open_tabs[index].owner = new_owner
	resource_owner = open_tabs[index].owner
	
	_clear_ui_nodes()
	
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
		var closed_active = (index == active_tab_index)
		if closed_active and current_resource:
			saveResource()
			
		var tab_res = open_tabs[index].resource
		if tab_res and tab_res.in_params_changed.is_connected(_on_in_params_changed):
			tab_res.in_params_changed.disconnect(_on_in_params_changed)
			
		open_tabs.remove_at(index)
		tab_bar.remove_tab(index)
		
		if open_tabs.is_empty():
			current_resource = null
			resource_owner = null
			active_tab_index = -1
			_clear_ui_nodes()
		else:
			if closed_active:
				var new_idx = clamp(index - 1, 0, open_tabs.size() - 1)
				_switch_to_tab(new_idx)
			else:
				if active_tab_index > index:
					active_tab_index -= 1

func _clear_ui_nodes():
	var children = []
	for child in gedit.get_children():
		if child is GraphNode or child is GraphFrame:
			child.queue_free()
			children.append( child )
	
	input_sources.clear()
	gedit.clear_connections()
	for child in children:
		gedit.remove_child( child )
	
	gedit_nodes_by_name.clear()
	inspector.edit( null )
	inspected_node = null
	if data_inspector:
		data_inspector.setNode(null)
	_set_analyze_panel_visible(false)

func _update_tab_titles():
	for i in range(open_tabs.size()):
		var tab_res = open_tabs[i].resource
		var tab_title = "New Graph"
		if is_instance_valid(tab_res) and tab_res.resource_path != "":
			tab_title = tab_res.resource_path.get_file()
		elif open_tabs[i].owner:
			tab_title = open_tabs[i].owner.name
		tab_bar.set_tab_title(i, tab_title)

func _on_button_open_pressed():
	if not open_file_dialog:
		open_file_dialog = FileDialog.new()
		open_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		open_file_dialog.access = FileDialog.ACCESS_RESOURCES
		open_file_dialog.add_filter("*.tres", "Flow Graph Resource")
		open_file_dialog.add_filter("*.res", "Flow Graph Resource")
		open_file_dialog.file_selected.connect(_on_graph_file_selected)
		add_child(open_file_dialog)
	open_file_dialog.popup_centered_ratio(0.4)

func _on_graph_file_selected(path: String):
	var res = load(path)
	if res is FlowGraphResource:
		setResourceToEdit(res, null)
	else:
		push_error("Selected resource is not a FlowGraphResource!")

func saveResource():
	FlowNodeIO.saveToResource( self )
	save_pending = false
	
func _process(delta: float) -> void:
	if not current_resource:
		return
		
	if save_pending:
		saveResource()
		
	# This is also trigered to true by plugin.gd:_on_history_changed
	if regen_pending:
		#print( "_process.regen_pending: %s" % [ regen_pending ])
		evalGraph()

	# Update active connections
	elif active_intensity > 0.0:
		active_intensity -= 0.016 * 4
		if active_intensity < 0:
			active_intensity = 0.0
		for node in active_nodes:
			node.setActivity( active_intensity )
			
		if active_intensity == 0:
			active_nodes.clear()
		gedit.queue_redraw()
		
func getNewName( suffix : String ):
	new_name_counter += 1
	return "id_%04d_%s" % [ new_name_counter, suffix ]

func _is_node_script_file_name(file_name: String) -> bool:
	var normalized := file_name.strip_edges()
	if normalized.is_empty():
		return false
	if normalized.begins_with("."):
		return false
	if normalized.ends_with(".gd.uid"):
		return false
	return normalized.ends_with(".gd")

func _normalize_node_script_path(file_name: String) -> String:
	var normalized := file_name.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.ends_with(".uid"):
		normalized = normalized.trim_suffix(".uid")
	if normalized.begins_with("uid://"):
		return ""
	if not normalized.begins_with("res://"):
		normalized = "%s/%s" % [directory_path, normalized]
	return normalized

func registerNodeType(node_type_name: String, file_name: String):
	var full_res_path := _normalize_node_script_path(file_name)
	if full_res_path.is_empty():
		if file_name.begins_with("uid://"):
			push_warning("Skipping uid-based node script reference: %s" % file_name)
		return
	if not ResourceLoader.exists(full_res_path, "Script"):
		push_warning("Skipping missing node script %s" % full_res_path)
		return
	var loaded_class : Script = ResourceLoader.load(full_res_path, "Script", ResourceLoader.CACHE_MODE_REPLACE) as Script
	if not loaded_class:
		push_error("Failed to load class %s" % full_res_path )
		return
	if not loaded_class.can_instantiate():
		var reload_err := loaded_class.reload(false)
		if reload_err != OK or not loaded_class.can_instantiate():
			push_error("Script %s failed to compile or cannot be instantiated" % full_res_path)
			return
	print( "Loading class %s" % full_res_path )
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
	#print( "Registering node type %s" % node_type_name )
	node_types[ node_type_name ] = meta

func registerInputNodeType( input ):
	var node_type_name := "input_%s" % input.name
	registerNodeType( node_type_name, "input.gd")

func registerOutputNodeType( output ):
	var node_type_name := "output_%s" % output.name
	registerNodeType( node_type_name, "output.gd")

func scanAvailableNodes():
	node_types.clear()
	var files : PackedStringArray
	var dir := DirAccess.open(directory_path)
	if dir:
		files = dir.get_files()
	else:
		files = ResourceLoader.list_directory(directory_path)
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
		registerNodeType( stem, file )

	# Dynamic input_* and output_* templates depend on the graph being edited.
	if current_resource:
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
		popup_menu_inputs.add_item( "No inputs defined", -1 )
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
		popup_menu_outputs.add_item( "No outputs defined", -1 )
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
			var oport = meta.outs[ auto_connect_from_port ]
			required_input_type = oport.get( "data_type", FlowData.DataType.Invalid )
		print( "auto_connect_from_node: %s:%d -> %d" % [ auto_connect_from_node, auto_connect_from_port, required_input_type])
		
	if auto_connect_to_node:
		var to_node = gedit_nodes_by_name.get( auto_connect_to_node )
		if to_node:
			var meta = to_node.getMeta()
			var iport = meta.ins[ auto_connect_to_port ]
			required_output_type = iport.get( "data_type", FlowData.DataType.Invalid )
		print( "auto_connect_to_node: %s:%d -> %d" % [auto_connect_to_node, auto_connect_to_port, required_output_type ])

	# A submenu to invoke the inputs declared in the pcg
	if required_input_type == FlowData.DataType.Invalid:
		if getSelectedNodes().size() > 0:
			pm.add_item("Collapse Selected to Subgraph", IDM_COLLAPSE_TO_SUBGRAPH)
			pm.add_separator("", -1)
			
		if popup_menu_inputs:
			popup_menu_inputs.queue_free()
		popup_menu_inputs = PopupMenu.new()
		popup_menu_inputs.name = "inputs_menu"
		popup_menu_inputs.id_pressed.connect( _on_inputs_menu_id_pressed )
		pm.add_child(popup_menu_inputs)
		pm.add_submenu_item("Inputs...", popup_menu_inputs.name)
		pm.add_separator( "", -1 )
		populatePopupInputsMenu()

		if popup_menu_outputs:
			popup_menu_outputs.queue_free()
		popup_menu_outputs = PopupMenu.new()
		popup_menu_outputs.name = "outputs_menu"
		popup_menu_outputs.id_pressed.connect( _on_outputs_menu_id_pressed )
		pm.add_child(popup_menu_outputs)
		pm.add_submenu_item("Outputs...", popup_menu_outputs.name)
		pm.add_separator( "", -1 )
		populatePopupOutputsMenu()

	# Categorized node submenus
	var cat_map = {
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
	var get_category = func(template_name: String) -> String:
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
				
		var cat = get_category.call(key)
		if not categorized_keys.has(cat):
			categorized_keys[cat] = []
		categorized_keys[cat].append(key)
		
	# Sort categories alphabetically
	var sorted_categories = categorized_keys.keys()
	sorted_categories.sort()
	
	for cat in sorted_categories:
		var sub_pm = PopupMenu.new()
		sub_pm.name = cat + "_menu"
		sub_pm.id_pressed.connect(_on_popup_menu_id_pressed)
		pm.add_child(sub_pm)
		pm.add_submenu_item(cat, sub_pm.name)
		
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
			sub_pm.add_item(node_meta.title, max_id, KEY_NONE)
			if node_meta.has("tooltip"):
				sub_pm.set_item_tooltip(idx, node_meta.get("tooltip"))
			idx += 1
			
	return pm

func _ready():
	
	if not Engine.is_editor_hint():
		return
		
	ui_scale = 1.0
	var dpi = DisplayServer.screen_get_dpi()
	if dpi > 150:
		ui_scale *= 2.0
				
	scanAvailableNodes()
	
	# Wrap TabBar in a PanelContainer with background #0e1016
	var tab_panel = PanelContainer.new()
	var tab_sb = StyleBoxFlat.new()
	tab_sb.bg_color = Color("0e1016")
	tab_sb.content_margin_left = 4
	tab_sb.content_margin_right = 4
	tab_sb.content_margin_top = 2
	tab_sb.content_margin_bottom = 0
	tab_panel.add_theme_stylebox_override("panel", tab_sb)
	
	tab_bar = TabBar.new()
	tab_bar.tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ALWAYS
	tab_bar.tab_changed.connect(_on_tab_changed)
	tab_bar.tab_close_pressed.connect(_on_tab_close_pressed)
	
	tab_panel.add_child(tab_bar)
	$VBoxContainer.add_child(tab_panel)
	$VBoxContainer.move_child(tab_panel, 1)
	
	# Initialize Open Graph Button
	var btn_open := Button.new()
	btn_open.text = "Open Graph"
	btn_open.tooltip_text = "Open a FlowGraph resource"
	btn_open.pressed.connect(_on_button_open_pressed)
	var toolbar = $VBoxContainer/ScrollContainer/HBoxContainer
	toolbar.add_child(btn_open)
	toolbar.move_child(btn_open, 0)

	# Unreal-style analyze: inspect selected node raw output
	var btn_analyze := Button.new()
	btn_analyze.text = "Analyze"
	btn_analyze.tooltip_text = "Inspect selected node raw data (A)"
	btn_analyze.pressed.connect(_on_button_analyze_pressed)
	toolbar.add_child(btn_analyze)
	toolbar.move_child(btn_analyze, 1)
	
	# Style the toolbar background #171a24
	var toolbar_container = $VBoxContainer/ScrollContainer
	if toolbar_container:
		var sb_tb = StyleBoxFlat.new()
		sb_tb.bg_color = Color("171a24")
		sb_tb.content_margin_left = 8
		sb_tb.content_margin_right = 8
		sb_tb.content_margin_top = 6
		sb_tb.content_margin_bottom = 6
		toolbar_container.add_theme_stylebox_override("panel", sb_tb)
		
	# Style all buttons in the toolbar to match Figma Style
	for child in toolbar.get_children():
		if child is Button:
			if child.name == "ButtonRegenerate":
				# Style Regenerate button as a flat button with cyan border and text
				var sb_normal := StyleBoxFlat.new()
				sb_normal.bg_color = Color("1b1e28")
				sb_normal.set_border_width_all(1)
				sb_normal.border_color = Color("22d3ee") # Cyan
				sb_normal.set_corner_radius_all(3)
				sb_normal.content_margin_left = 10
				sb_normal.content_margin_right = 10
				sb_normal.content_margin_top = 4
				sb_normal.content_margin_bottom = 4
				child.add_theme_stylebox_override("normal", sb_normal)
				
				var sb_hover := sb_normal.duplicate()
				sb_hover.bg_color = Color("252836")
				child.add_theme_stylebox_override("hover", sb_hover)
				
				var sb_pressed := sb_normal.duplicate()
				sb_pressed.bg_color = Color("111318")
				child.add_theme_stylebox_override("pressed", sb_pressed)
				
				child.add_theme_color_override("font_color", Color("22d3ee"))
				child.add_theme_color_override("font_hover_color", Color("22d3ee"))
				child.add_theme_color_override("font_pressed_color", Color("22d3ee"))
			else:
				_style_toolbar_button(child)
				
	# Custom Dot Grid Background on GraphEdit
	gedit.show_grid = false
	var bg_grid = preload("res://addons/flow_nodes_editor/custom_grid.gd").new()
	bg_grid.gedit = gedit
	gedit.add_child(bg_grid)
	gedit.move_child(bg_grid, 0)
	_setup_inline_analyze_panel()
	
	# Custom Sidebar Inspector
	inspector = FlowInspector.new()
	inspector.custom_minimum_size = Vector2(268, 200) # persistent 268px width
	var splitter = $VBoxContainer/VSplitContainer
	splitter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	splitter.size_flags_vertical = Control.SIZE_EXPAND_FILL
	splitter.add_child(inspector)
	splitter.split_offset = 600
	
	gedit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gedit.size_flags_vertical = Control.SIZE_EXPAND_FILL	
	gedit.add_theme_color_override("activity", Color(1, 0.2, 0.2, 1))
	inspector.size_flags_horizontal = Control.SIZE_FILL # Keep size based on min width
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector.property_edited.connect(onNodePropertyChanged)
	
	# Connect node deselection to clear inspector
	gedit.node_deselected.connect(func(node):
		if inspected_node == node:
			inspected_node = null
			inspector.edit(null)
	)
	
	# Instantiate custom SearchAddNodePopup
	search_add_node_popup = SearchAddNodePopup.new()
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
	
	# Setup premium status bar at bottom of the editor
	if info:
		info.visible = false # hide old toolbar info label
		
	var status_panel = PanelContainer.new()
	var status_sb = StyleBoxFlat.new()
	status_sb.bg_color = Color("0a0c12")
	status_sb.border_width_top = 1
	status_sb.border_color = Color(1.0, 1.0, 1.0, 0.04)
	status_sb.content_margin_left = 12
	status_sb.content_margin_right = 12
	status_sb.content_margin_top = 4
	status_sb.content_margin_bottom = 4
	status_panel.add_theme_stylebox_override("panel", status_sb)
	
	var status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color("2e2c48"))
	status_panel.add_child(status_label)
	
	$VBoxContainer.add_child(status_panel)
	info = status_label
	
	%AutoRegen.button_pressed = auto_regen
	if has_node("%CheckColorNodes"):
		%CheckColorNodes.button_pressed = color_nodes
		
	if not gedit.begin_node_move.is_connected(_on_graph_edit_begin_node_move):
		gedit.begin_node_move.connect(_on_graph_edit_begin_node_move)
	if not gedit.end_node_move.is_connected(_on_graph_edit_end_node_move):
		gedit.end_node_move.connect(_on_graph_edit_end_node_move)
		
	update_status_bar()

func _style_toolbar_button(btn: Button):
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	sb_normal.set_border_width_all(1)
	sb_normal.border_color = Color(1.0, 1.0, 1.0, 0.1)
	sb_normal.set_corner_radius_all(3)
	sb_normal.content_margin_left = 10
	sb_normal.content_margin_right = 10
	sb_normal.content_margin_top = 4
	sb_normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sb_normal)
	
	var sb_hover := sb_normal.duplicate()
	sb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.09)
	btn.add_theme_stylebox_override("hover", sb_hover)
	
	var sb_pressed := sb_normal.duplicate()
	sb_pressed.bg_color = Color(1.0, 1.0, 1.0, 0.02)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	
	btn.add_theme_color_override("font_color", Color("cdd0dc"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color("a1a1aa"))

func _setup_inline_analyze_panel():
	var panel := PanelContainer.new()
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

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color("10141f")
	panel_sb.set_border_width_all(1)
	panel_sb.border_color = Color(1.0, 1.0, 1.0, 0.08)
	panel_sb.set_corner_radius_all(4)
	panel_sb.content_margin_left = 8
	panel_sb.content_margin_right = 8
	panel_sb.content_margin_top = 8
	panel_sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_sb)

	var packed := load("res://addons/flow_nodes_editor/data_inspector.tscn") as PackedScene
	if not packed:
		push_error("Failed to load inline data inspector scene")
		return
	var inline_inspector = packed.instantiate() as Control
	if not inline_inspector:
		push_error("Failed to instantiate inline data inspector")
		return
	inline_inspector.name = "InlineDataInspector"
	inline_inspector.anchor_left = 0.0
	inline_inspector.anchor_top = 0.0
	inline_inspector.anchor_right = 1.0
	inline_inspector.anchor_bottom = 1.0
	inline_inspector.offset_left = 0.0
	inline_inspector.offset_top = 0.0
	inline_inspector.offset_right = 0.0
	inline_inspector.offset_bottom = 0.0

	panel.add_child(inline_inspector)
	gedit.add_child(panel)
	analyze_panel = panel
	data_inspector = inline_inspector

func _set_analyze_panel_visible(visible: bool):
	if not analyze_panel:
		return
	analyze_panel.visible = visible
	if visible:
		analyze_panel.move_to_front()
	else:
		current_analyzed_node = null

func update_status_bar(eval_msg: String = ""):
	var nodes_count = 0
	for child in gedit.get_children():
		if child is GraphNode:
			nodes_count += 1
	var connections = gedit.get_connection_list()
	var wires_count = connections.size()
	
	var text_parts = []
	text_parts.append("%d nodes" % nodes_count)
	text_parts.append("%d connections" % wires_count)
	if eval_msg != "":
		text_parts.append(eval_msg)
	elif current_resource:
		text_parts.append("Ready")
		
	info.text = " · ".join(text_parts)

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
	
func onNodePropertyChanged( prop_name : String):
	if inspected_node and inspected_node is GraphNode:
		#print( "Node %s.%s has changed" % [ inspected_node.name, prop_name ])
		inspected_node.onPropChanged( prop_name )
		inspected_node.refreshFromSettings()
		if inspected_node is FlowNodeBase and (inspected_node.node_template == "input" or inspected_node.node_template.begins_with("input_")):
			if prop_name == "name" or prop_name == "data_type":
				syncGraphParameters()
		elif inspected_node is FlowNodeBase and (inspected_node.node_template == "output" or inspected_node.node_template.begins_with("output_")):
			if prop_name == "name" or prop_name == "data_type":
				syncGraphOutputs()
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
	
# ------------------------------------------------
func getSelectedNodes() -> Array[GraphNode]:
	var nodes : Array[GraphNode] = []
	for child in gedit.get_children():
		var node = child as GraphNode
		if node and node.selected:
			nodes.push_back(node)
	return nodes

func deleteNodes( nodes : Array[GraphNode] ):
	var has_input_nodes := false
	var has_output_nodes := false
	for node in nodes:
		if node is FlowNodeBase and (node.node_template == "input" or node.node_template.begins_with("input_")):
			has_input_nodes = true
		elif node is FlowNodeBase and (node.node_template == "output" or node.node_template.begins_with("output_")):
			has_output_nodes = true
		for n in range( node.num_ports ):
			remove_all_inputs_to_target_connection( node.name, n )
		for n in range( node.getMeta().outs.size() ):
			remove_all_inputs_to_source_connection( node.name, n )
		gedit_nodes_by_name.erase( node.name )
		gedit.remove_child( node )
		node.queue_free()
	if has_input_nodes:
		syncGraphParameters()
	if has_output_nodes:
		syncGraphOutputs()

func deleteGraphElementsAndRefresh( nodes : Array[GraphNode], frames : Array[GraphFrame] ):
	deleteFrames( frames )
	deleteNodes( nodes )
	queueSave()
	inspected_node = null
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
	save_pending = true
	
func queueRegen():
	#print( "queueRegen -> %s" % [ auto_regen ])
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

func addNodeFromTemplate( node_template, node_name : String, settings = null ):
	print( "addNode %s (%s : %s)" % [ node_template, node_name, str(settings) ])
	var node = packed_node.instantiate() as GraphNode
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
	node.settings.title = meta.title
	node.initFromScript()
	node.title = node.getTitle()
	node.size = Vector2(32,32)
	node.tooltip_text = meta.get( "tooltip", "" )
	node.refreshFromSettings()
	refreshSignalsInputArgs( node )
	
	gedit.add_child(node)
	gedit_nodes_by_name[ node.name ] = node
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
		if node and node.node_template == "output":
			if node.settings and node.settings.name == uname:
				return true
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
	if (src_type and dst_type) or (src_type == FlowData.DataType.NodePath) or (src_type == FlowData.DataType.NodeMesh):
		if src_type != dst_type:
			push_warning( "Node types do not match %d vs %d" % [ src_type, dst_type ])
			return false
		
	#print( "canConnect OK %s:%d (%d)-> %s:%d (%d)" % [ src.name, src_port, src_type, dst.name, dst_port, dst_type ] )
	return true
	
func addNode( node_template, settings = null ):
	var before_state = get_graph_snapshot()
	var node_name = getNewName(node_template)
	var node = addNodeFromTemplate( node_template, node_name, settings )
	if not node:
		return null
		
	if auto_connect_from_node:
		var source_node = gedit_nodes_by_name.get( auto_connect_from_node )
		if canConnect( source_node, auto_connect_from_port, node, 0 ):
			connect_nodes(auto_connect_from_node, auto_connect_from_port, node.name, 0)
		auto_connect_from_node = ""
		
	if auto_connect_to_node:
		var target_node = gedit_nodes_by_name.get( auto_connect_to_node )
		if canConnect( node, 0, target_node, auto_connect_to_port ):
			connect_nodes(node.name, 0, auto_connect_to_node, auto_connect_to_port )
		auto_connect_to_node = ""
	
	for prev_node in getSelectedNodes():
		prev_node.selected = false
	node.selected = true
	node.visible = true
	
	record_undo_action("Add Node", before_state)
	if node_template == "input" or node_template.begins_with("input_"):
		syncGraphParameters()
	elif node_template == "output" or node_template.begins_with("output_"):
		syncGraphOutputs()
	return node

# ------------------------------------------------
func _on_graph_edit_gui_input(event):
	var evt_key = event as InputEventKey
	if evt_key and evt_key.pressed:
		var no_modifiers = not evt_key.ctrl_pressed and not evt_key.alt_pressed and not evt_key.shift_pressed
		var key = evt_key.keycode
		if key == KEY_X or key == KEY_DELETE:
			if no_modifiers:
				deleteSelectedNodes()
		elif key == KEY_A:
			if evt_key.shift_pressed:
				openAddMenu()
			elif no_modifiers:
				analyzeSelection()
		elif key == KEY_C:
			if no_modifiers:
				addComment()
		elif key == KEY_G:
			if no_modifiers:
				toggleDisabled()
				evalGraph()
		elif key == KEY_D:
			if no_modifiers:
				toggleDebug()
		elif key == KEY_E:
			if no_modifiers:
				analyzeSelection()
		elif key == KEY_R:
			if no_modifiers:
				for node in getSelectedNodes():
					node.dirty = true
				evalGraph()
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
		node.refreshFromSettings()
		node.setupDrawDebug()
	auto_regen = prev_auto_regen
	regen_pending = false

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
	node.dirty = true
	node.refreshFromSettings()
	_set_analyze_panel_visible(true)
	current_analyzed_node = node
	auto_regen = prev_auto_regen
	regen_pending = false
	data_inspector.refresh()

func analyzeSelection():
	if not data_inspector:
		return
	var nodes = getSelectedNodes()
	var prev_auto_regen := auto_regen
	auto_regen = false
	# Toggle off: if analyzer is open and user re-runs Analyze on the same node (or with no node selected).
	if analyze_panel and analyze_panel.visible:
		if nodes.size() != 1 or (current_analyzed_node and nodes[0] == current_analyzed_node):
			data_inspector.setNode(null)
			_set_analyze_panel_visible(false)
			auto_regen = prev_auto_regen
			regen_pending = false
			return
	if nodes.size() != 1:
		data_inspector.setNode(null)
		_set_analyze_panel_visible(false)
		auto_regen = prev_auto_regen
		regen_pending = false
		return
	var node = nodes[0]
	# Force rebind so repeated Analyze on the same node stays active.
	data_inspector.setNode(null)
	data_inspector.setNode(node)
	node.dirty = true
	node.refreshFromSettings()
	_set_analyze_panel_visible(true)
	current_analyzed_node = node
	auto_regen = prev_auto_regen
	regen_pending = false
	data_inspector.refresh()
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
	
	for node in nodes:
		gedit.attach_graph_element_to_frame( node.name, frame.name )
	
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
	var input_nodes = []
	for child in gedit.get_children():
		var node = child as FlowNodeBase
		if node and (node.node_template == "input" or node.node_template.begins_with("input_")):
			input_nodes.append(node)
	var new_in_params : Array[GraphInputParameter] = []
	var seen_names = {}
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
		if node:
			if node.node_template == "output":
				has_multi_port_output = true
			elif node.node_template.begins_with("output_"):
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
	local_drop_position = at_position
	
	if popup_on_over_input:
		var node = popup_on_over_input.getNode()
		var pm := PopupMenu.new()
		add_child( pm )
		pm.name = "InPopupMenu"
		pm.add_item( "Promote To Parameter", IDM_PROMOTE_TO_PARAMETER, KEY_NONE )
		pm.id_pressed.connect( _on_in_popup_menu_pressed.bind( popup_on_over_input ) )
		pm.position = get_screen_position() + at_position + Vector2( 20, 20 )
		pm.popup()
		#print( "Show popup associated to %s.%s" % [ node.name, popup_on_over_input.getInLabel().text ] )
		return
	
	var required_input_type := FlowData.DataType.Invalid
	var required_output_type := FlowData.DataType.Invalid
	if auto_connect_from_node:
		var from_node = gedit_nodes_by_name.get( auto_connect_from_node )
		if from_node:
			var meta = from_node.getMeta()
			var oport = meta.outs[ auto_connect_from_port ]
			required_input_type = oport.get( "data_type", FlowData.DataType.Invalid )
		
	if auto_connect_to_node:
		var to_node = gedit_nodes_by_name.get( auto_connect_to_node )
		if to_node:
			var meta = to_node.getMeta()
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
	_on_graph_edit_popup_request( pos )

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
	
	# Save subgraph resource
	var subgraph_res = FlowGraphResource.new()
	subgraph_res.data = subgraph_data
	subgraph_res.in_params = subgraph_in_params
	var save_err = ResourceSaver.save(subgraph_res, path)
	if save_err != OK:
		push_error("Failed to save collapsed subgraph to %s" % path)
		return
		
	# Load the resource to make sure we have a valid reference
	var loaded_subgraph = load(path)
	
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
	gedit.disconnect_node(from_node, from_port, to_node, to_port)
	remove_input_source_target_connection( from_node, from_port, to_node, to_port )

	var dst_node : FlowNodeBase = gedit_nodes_by_name.get( to_node )
	if dst_node != null:
		dst_node.dirty = true
	
func connect_nodes(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	#print( "connect_nodes %s:%d -> %s:%d" % [ from_node, from_port, to_node, to_port ] )
	gedit.connect_node(from_node, from_port, to_node, to_port)
	var key = [to_node, to_port]
	if not input_sources.has(key):
		input_sources.set( key, [])
	input_sources[key].append([from_node, from_port])

	var dst_node : FlowNodeBase = gedit_nodes_by_name.get( to_node )
	if dst_node != null:
		dst_node.dirty = true


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
		input_sources[key].erase([from_node, from_port])
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
	
func getEvalOrder():
	# Find targets, like spawn meshes
	var finals := getAllNodes().filter( func ( node : FlowNodeBase ) -> bool:
		return ( not node.settings.disabled ) and ( node.settings.inspect_enabled or node.settings.debug_enabled or node.getMeta().get( "is_final", false ) )
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

	#for node in getAllNodes():
		#print( "Node: %s" % [ node.name ])
		#print( "  deps: %s" % [ node.deps ])
		#print( "  dependants: %s" % [ node.dependants ])

func expandDirtyFlagToDependants( node : FlowNodeBase ):
	#print( "%s is dirty" % [ node.name ] )
	for out_conn in node.dependants:
		#print( "  -> %s" % [ out_conn ])
		var dst_node = gedit_nodes_by_name.get( out_conn.to_node )
		if dst_node:
			if not dst_node.dirty:
				dst_node.dirty = true
				expandDirtyFlagToDependants( dst_node )

func evalGraph():
	ctx.eval_id += 1
	
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
	
	var performance = []
	#print( "getEvalOrder..." )
	var nodes_to_eval = getEvalOrder( )
		
	for node in nodes_to_eval:
		#print( "  Eval: %s (%d) Dirty:%s" % [ node.name, node.eval_id, node.dirty ] )
			
		# The node has already been evaluated or it's not dirty. No need to reevaluate it
		if node.eval_id == ctx.eval_id or not node.dirty:
			continue
		
		var time_node_start = Time.get_ticks_usec()
		active_nodes.append( node )
		
		node.preExecute( ctx )
		
		#print( "Evaluating %s" % node.name )
		if node.settings.disabled:
			node.executedDisabled( ctx )
		else:
			node.run( ctx )
		
		if node.settings.inspect_enabled:
			data_inspector.refresh()
		node.setupDrawDebug()
		node.dirty = false
		var time_node_ends = Time.get_ticks_usec()
		
		if dump_performance:
			performance.append( { "name": node.name, "time": time_node_ends - time_node_start })

	regen_pending = false
	#print( "regen_pending is now false")
	
	var elapsed_usec = Time.get_ticks_usec() - time_start
	update_status_bar("%d evals in %.3f ms" % [ ctx.eval_id, elapsed_usec / 1000.0 ])
	if dump_performance:
		for entry in performance:
			var formatted := "%8.1s" % String.num(entry.time, 1)
			print( "%s usecs %s" % [ formatted, entry.name ] )
		dump_performance = false

func _on_button_reload_pressed() -> void:
	scanAvailableNodes()

func _on_button_analyze_pressed() -> void:
	analyzeSelection()

func _on_button_save_pressed() -> void:
	if current_resource:
		saveResource()
		ResourceSaver.save(current_resource)

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
	markAllNodesAsDirty()
	queueRegen()
	#for n : FlowNodeBase in getSelectedNodes():
		#print( "Node: %s  Ins:%d  Outs:%d" % [ n.name, n.num_in_ports, n.num_out_ports ])
		#for idx in range( n.num_in_ports ):
			#var type = n.get_slot_type_left( idx )
			#print( "Left.%d = %d" % [ idx, type ] )

func _on_auto_regen_toggled(toggled_on: bool) -> void:
	auto_regen = toggled_on

func _on_button_inputs_pressed():
	if current_resource:
		inspector.edit( current_resource )
	inspected_node = null

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
	# When a node in the scene changes, just mark dirty all nodes
	# which can potentially become dirty
	# This also triggers as dirty all scan_* nodes when we change
	# anything in another of our nodes. Not very good
	for node in getAllNodes():
		node.dirty = true
	queueRegen()

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

func clear_graph():
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
	print("set_nodes_positions called with: ", positions)
	for name in positions:
		var node = gedit.get_node_or_null(NodePath(name))
		if node:
			var pos_arr = positions[name]
			node.position_offset = Vector2(pos_arr[0], pos_arr[1])
	queueSave()
	queueRegen()

func _on_graph_edit_begin_node_move():
	drag_start_snapshot = get_graph_snapshot()

func _on_graph_edit_end_node_move():
	var moved_nodes_before = {}
	var moved_nodes_after = {}
	if not drag_start_snapshot.is_empty() and drag_start_snapshot.has("absolute_positions"):
		var start_positions = drag_start_snapshot.absolute_positions
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
			ur.commit_action(false) # already executed
			queueSave()
			
	drag_start_snapshot = {}

func _on_color_nodes_toggled(toggled_on: bool) -> void:
	color_nodes = toggled_on
	for node in getAllNodes():
		node.refreshFromSettings()

func apply_connections_change(conns_to_remove: Array, conns_to_add: Array):
	for c in conns_to_remove:
		disconnect_nodes(c.from_node, c.from_port, c.to_node, c.to_port)
	for c in conns_to_add:
		connect_nodes(c.from_node, c.from_port, c.to_node, c.to_port)
	queueSave()
	queueRegen()
