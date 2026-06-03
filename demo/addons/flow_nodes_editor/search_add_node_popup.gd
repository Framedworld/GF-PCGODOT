@tool
extends PopupPanel
class_name SearchAddNodePopup

signal node_selected(template_name: String)
signal action_selected(action_id: int)
signal input_selected(input_idx: int)
signal output_selected(output_idx: int)

const IDM_COLLAPSE_TO_SUBGRAPH = 200

# Theme colors
const BG_COLOR = Color("1b1e28")
const BORDER_COLOR = Color("252836")
const ACCENT_COLOR = Color("22d3ee") # Cyan accent
const MENU_WIDTH = 230
const MENU_MAX_HEIGHT = 320
const ROW_HEIGHT = 24
const SCROLL_ARROW_HEIGHT = 18
const SUBMENU_HIDE_DELAY = 0.45
const SUBMENU_KEEPALIVE_PADDING = 36
const POPUP_KEEPALIVE_DISTANCE = 160.0

var node_types = {}
var inputs_list = []
var outputs_list = []
var has_selected_nodes = false
var search_query = ""
var current_category: String = ""

var line_edit: LineEdit
var scroll: ScrollContainer
var list_vbox: VBoxContainer

var all_items: Array[Dictionary] = [] # Array of { "type": "node"|"action"|"input", "key": Variant, "label": String, "category": String, "button_node": Button }
var visible_items: Array[Dictionary] = []
var highlighted_index: int = -1
var recently_used: Array[String] = [] # Ordered list of recently used template names (most recent first)
const MAX_RECENT = 8

# Sub-panel popup
var submenu_popup: PopupPanel
var sub_list_vbox: VBoxContainer
var sub_scroll: Control
var sub_list_margin: MarginContainer
var sub_scrollbar: VScrollBar
var sub_scroll_up_btn: Button
var sub_scroll_down_btn: Button
var sub_has_scroll_overflow := false
var sub_scroll_value := 0.0
var sub_scroll_max := 0.0

var active_hovered_category = ""
var sub_panel_hide_timer: SceneTreeTimer = null
var main_sb: StyleBoxFlat
var sub_sb: StyleBoxFlat

func _ready():
	# Configure popup window/panel
	title = ""
	borderless = true
	unresizable = true
	transient = true
	exclusive = false
	min_size = Vector2i(MENU_WIDTH, 0)

	# Apply PanelContainer style to self
	main_sb = StyleBoxFlat.new()
	main_sb.bg_color = BG_COLOR
	main_sb.set_border_width_all(1)
	main_sb.border_color = Color(1.0, 1.0, 1.0, 0.1)
	main_sb.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", main_sb)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size.x = MENU_WIDTH
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)
	
	# Header with LineEdit
	var header_margin = MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 12)
	header_margin.add_theme_constant_override("margin_right", 12)
	header_margin.add_theme_constant_override("margin_top", 8)
	header_margin.add_theme_constant_override("margin_bottom", 8)
	main_vbox.add_child(header_margin)
	
	line_edit = LineEdit.new()
	line_edit.placeholder_text = "Search nodes..."
	line_edit.flat = true
	line_edit.add_theme_font_size_override("font_size", 13)
	line_edit.add_theme_color_override("font_color", Color("c8c8d4"))
	line_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	line_edit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	line_edit.text_changed.connect(_on_search_text_changed)
	line_edit.gui_input.connect(_on_line_edit_gui_input)
	line_edit.mouse_entered.connect(func():
		_hide_sub_panel_immediately()
	)
	header_margin.add_child(line_edit)
	
	# Separator
	var sep = HSeparator.new()
	var sep_style = StyleBoxLine.new()
	sep_style.color = Color(1.0, 1.0, 1.0, 0.07)
	sep_style.thickness = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	main_vbox.add_child(sep)
	
	# Scroll area for items
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(MENU_WIDTH, MENU_MAX_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	var list_margin = MarginContainer.new()
	list_margin.custom_minimum_size.x = MENU_WIDTH
	list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_margin.add_theme_constant_override("margin_left", 0)
	list_margin.add_theme_constant_override("margin_right", 0)
	list_margin.add_theme_constant_override("margin_top", 6)
	list_margin.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(list_margin)
	
	list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 2)
	list_margin.add_child(list_vbox)
	
	# Create separate Submenu Popup
	submenu_popup = PopupPanel.new()
	submenu_popup.title = ""
	submenu_popup.borderless = true
	submenu_popup.unresizable = true
	submenu_popup.transient = true
	submenu_popup.exclusive = false
	
	sub_sb = StyleBoxFlat.new()
	sub_sb.bg_color = BG_COLOR
	sub_sb.set_border_width_all(1)
	sub_sb.border_color = Color(1.0, 1.0, 1.0, 0.1)
	sub_sb.set_corner_radius_all(6)
	submenu_popup.add_theme_stylebox_override("panel", sub_sb)
	
	submenu_popup.mouse_entered.connect(func():
		_cancel_sub_panel_hide_timer()
	)
	submenu_popup.mouse_exited.connect(func():
		_start_sub_panel_hide_timer()
	)
	add_child(submenu_popup) # submenu is owned by self
	
	# Sub-panel content
	var sub_vbox = Control.new()
	sub_vbox.custom_minimum_size.x = MENU_WIDTH
	submenu_popup.add_child(sub_vbox)
	
	sub_scroll_up_btn = _create_scroll_arrow_button("▲")
	sub_vbox.add_child(sub_scroll_up_btn)

	# Sub-panel scroll area
	sub_scroll = Control.new()
	sub_scroll.clip_contents = true
	sub_scroll.custom_minimum_size = Vector2(MENU_WIDTH, MENU_MAX_HEIGHT)
	sub_scroll.gui_input.connect(_on_sub_scroll_gui_input)
	sub_vbox.add_child(sub_scroll)
	
	sub_list_margin = MarginContainer.new()
	sub_list_margin.custom_minimum_size.x = MENU_WIDTH
	sub_list_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_list_margin.add_theme_constant_override("margin_left", 0)
	sub_list_margin.add_theme_constant_override("margin_right", 0)
	sub_list_margin.add_theme_constant_override("margin_top", 6)
	sub_list_margin.add_theme_constant_override("margin_bottom", 6)
	sub_scroll.add_child(sub_list_margin)
	
	sub_list_vbox = VBoxContainer.new()
	sub_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_list_vbox.add_theme_constant_override("separation", 2)
	sub_list_margin.add_child(sub_list_vbox)

	sub_scrollbar = VScrollBar.new()
	sub_scrollbar.focus_mode = Control.FOCUS_NONE
	sub_scrollbar.value_changed.connect(func(value):
		_set_sub_scroll_value(value)
	)
	sub_vbox.add_child(sub_scrollbar)
	
	sub_scroll_down_btn = _create_scroll_arrow_button("▼")
	sub_vbox.add_child(sub_scroll_down_btn)
	sub_vbox.move_child(sub_scroll_up_btn, sub_vbox.get_child_count() - 1)
	_update_sub_scroll_arrows()

	# Hide submenu when main hides, and clear any pending hide timer
	popup_hide.connect(func():
		sub_panel_hide_timer = null
		submenu_popup.hide()
	)
	
	# Grab focus on open
	about_to_popup.connect(func():
		line_edit.text = ""
		search_query = ""
		current_category = ""
		_hide_sub_panel_immediately()
		line_edit.grab_focus()
		rebuild_list()
	)

func setup(p_node_types: Dictionary, p_inputs: Array, p_outputs: Array, p_has_selected_nodes: bool, p_req_in: int = FlowData.DataType.Invalid, p_req_out: int = FlowData.DataType.Invalid):
	node_types = p_node_types
	inputs_list = p_inputs
	outputs_list = p_outputs
	has_selected_nodes = p_has_selected_nodes
	
	# Cache all items
	all_items.clear()
	
	# 1. Action items (only when no drag connecting is happening)
	if has_selected_nodes and p_req_in == FlowData.DataType.Invalid and p_req_out == FlowData.DataType.Invalid:
		all_items.append({
			"type": "action",
			"key": IDM_COLLAPSE_TO_SUBGRAPH,
			"label": "Collapse Selected to Subgraph",
			"category": "Actions"
		})
		
	# 2. Input/Output items (only when no drag connecting is happening)
	if p_req_in == FlowData.DataType.Invalid and p_req_out == FlowData.DataType.Invalid:
		for idx in range(inputs_list.size()):
			var input_name = inputs_list[idx].name
			all_items.append({
				"type": "input",
				"key": idx,
				"label": "Input: " + input_name,
				"category": "Inputs"
			})
		for idx in range(outputs_list.size()):
			var output_name = outputs_list[idx].name
			all_items.append({
				"type": "output",
				"key": idx,
				"label": "Output: " + output_name,
				"category": "Outputs"
			})
		
	# 3. Node items
	var cat_map = {
		"Black Lantern": ["bl_style_lab_source", "bl_building_mass", "bl_zone_carver", "bl_room_splitter", "bl_decorator_master", "bl_tactical_decorator", "bl_floor_data_to_points", "bl_floor_data_contract_points", "bl_validate_floor_data", "bl_room_style_template", "bl_style_context_source", "bl_style_context_points", "bl_style_anchor_points", "bl_sync_grid_cell", "bl_points_to_style_spec", "bl_style_spec_to_points", "bl_style_spec_merge", "bl_style_metadata_spec", "bl_smart_prop_scatter", "bl_points_to_floor_data_props"],
		"Control Flow": ["input", "output", "subgraph", "loop", "branch", "select", "select_multi", "switch", "get_loop_index"],
		"Debug": ["debug", "print_string", "sanity_check"],
		"Density": ["curve_remap_density", "density_remap", "distance_to_density"],
		"Filter": ["filter", "filter_data_by_tag", "filter_data_by_attribute", "filter_data_by_type", "attribute_filter_range", "point_filter_range", "self_pruning", "substract", "difference", "intersection", "union"],
		"Math": ["math_op", "expression", "reduce", "boolean"],
		"Metadata": ["add_attribute", "attribute_rename", "remove_attribute", "add_tags", "delete_tags", "replace_tags", "make_vector", "compose_vector", "decompose_vector", "attribute_random", "match_and_set", "mutate_seed", "random_color", "point_to_attribute_set", "attribute_set_to_point", "load_data_table", "data_table_row_to_attribute_set", "load_pcg_data_asset"],
		"Point Ops": ["bounds_modifier", "transform", "build_rotation_from_up", "combine_points", "duplicate_point", "point_offsets", "snap_to_grid", "point_neighborhood"],
		"Sampler": ["copy", "copy_points", "sample_mesh", "point_from_mesh", "point_from_player_pawn", "points_from_scene", "points_from_tilemap", "points_from_gridmap", "select_points", "sample_spline", "surface_sampler", "volume_sampler", "texture_sampler", "points_from_imported_scene", "load_alembic_file", "navigation_region_sampler"],
		"Spatial": ["create_spline", "distance", "ray_cast", "physics_overlap_query", "physics_shape_sweep", "clip_points_by_polygon", "clip_paths", "polygon_operation", "split_splines", "create_surface_from_spline", "create_surface_from_polygon"],
		"Assets": ["assets", "spawn_meshes", "spawn_scenes", "spawn_nodes", "apply_on_actor", "points_from_imported_scene", "load_alembic_file", "load_pcg_data_asset"],
		"Generators": ["grid", "noise", "relax", "dungeon_generator", "make_bounds", "grid_fill_bounds", "grid_connect_points", "grid_boundary"],
		"Utility": ["sort", "merge", "merge_points", "partition", "scan_meshes", "scan_splines", "scan_nodes", "sequence_sample", "size", "get_points_count", "get_data_count", "get_entries_count", "transform_points"]
	}

	
	var get_category = func(template_name: String) -> String:
		for cat in cat_map:
			if template_name in cat_map[cat]:
				return cat
		return "Utility"
		
	# Gather templates
	var templates = []
	for key in node_types.keys():
		var meta = node_types[key]
		if not meta.get("auto_register", true):
			continue
			
		# Check port compatibility if drag connecting
		if p_req_in != FlowData.DataType.Invalid or p_req_out != FlowData.DataType.Invalid:
			var has_compatible_port = false
			var ports = meta.ins if p_req_in != FlowData.DataType.Invalid else meta.outs
			var required_type = p_req_in if p_req_in != FlowData.DataType.Invalid else p_req_out
			for port in ports:
				var port_type = port.get("data_type", 0)
				if port_type == required_type:
					has_compatible_port = true
					break
			if not has_compatible_port:
				continue
				
		templates.append(key)
	templates.sort()
	
	for key in templates:
		var meta = node_types[key]
		all_items.append({
			"type": "node",
			"key": key,
			"label": meta.title,
			"category": get_category.call(key),
			"aliases": meta.get("aliases", []),
			"tooltip": meta.get("tooltip", "")
		})

func _item_matches_query(item: Dictionary, query: String) -> bool:
	return _item_match_score(item, query) > 0

## Scores how well an item matches the query. Higher = better. 0 = no match.
## Supports fuzzy token-based matching: "pt neigh" matches "Point Neighborhood".
func _item_match_score(item: Dictionary, query: String) -> int:
	var label_lower = item.label.to_lower()
	var cat_lower = item.category.to_lower()
	var full_path = cat_lower + " " + label_lower
	
	# Exact match in label = highest score
	if label_lower == query:
		return 100
	# Starts with = high score
	if label_lower.begins_with(query):
		return 80
	# Contains full query = good score
	if label_lower.contains(query):
		return 60
	if full_path.contains(query):
		return 50
	# Check tooltip
	if item.get("tooltip", "").to_lower().contains(query):
		return 40
	# Check aliases
	for alias in item.get("aliases", []):
		if str(alias).to_lower().contains(query):
			return 40
	# Fuzzy token matching: split query into tokens, ALL must match somewhere
	var tokens = query.split(" ", false)
	if tokens.size() > 1:
		var searchable = full_path + " " + item.get("tooltip", "").to_lower()
		for alias in item.get("aliases", []):
			searchable += " " + str(alias).to_lower()
		var all_match = true
		for token in tokens:
			if not searchable.contains(token):
				all_match = false
				break
		if all_match:
			return 30
	return 0

func _create_scroll_arrow_button(label: String) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.custom_minimum_size = Vector2(MENU_WIDTH, SCROLL_ARROW_HEIGHT)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", ACCENT_COLOR)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.80, 0.88, 0.62))
	var sb_normal = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", sb_normal)
	var sb_hover = StyleBoxFlat.new()
	sb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn

func _on_sub_scroll_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_sub_scroll_value(sub_scroll_value - ROW_HEIGHT * 3)
			sub_scroll.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_sub_scroll_value(sub_scroll_value + ROW_HEIGHT * 3)
			sub_scroll.accept_event()

func _set_sub_scroll_value(value: float):
	sub_scroll_value = clampf(value, 0.0, sub_scroll_max)
	if sub_list_margin:
		sub_list_margin.position.y = -sub_scroll_value
	if sub_scrollbar and absf(sub_scrollbar.value - sub_scroll_value) > 0.01:
		sub_scrollbar.value = sub_scroll_value
	_update_sub_scroll_arrows()

func _update_sub_scroll_arrows():
	if not sub_scroll_up_btn or not sub_scroll_down_btn:
		return
	if not sub_has_scroll_overflow:
		sub_scroll_up_btn.visible = false
		sub_scroll_down_btn.visible = false
		return

	sub_scroll_up_btn.visible = sub_scroll_value > 1.0
	sub_scroll_down_btn.visible = sub_scroll_value < sub_scroll_max - 1.0
	sub_scroll_up_btn.disabled = false
	sub_scroll_down_btn.disabled = false

func _style_menu_button(btn: Button):
	btn.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color("c8c8d4"))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	
	var font_to_use = null
	if has_theme_font("main", "EditorFonts"):
		font_to_use = get_theme_font("main", "EditorFonts")
	if font_to_use:
		btn.add_theme_font_override("font", font_to_use)
		
	var sb_normal = StyleBoxEmpty.new()
	sb_normal.content_margin_left = 12
	sb_normal.content_margin_right = 12
	sb_normal.content_margin_top = 4
	sb_normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sb_normal)
	
	var sb_hover = StyleBoxFlat.new()
	sb_hover.bg_color = Color(1.0, 1.0, 1.0, 0.05)
	sb_hover.set_corner_radius_all(4)
	sb_hover.content_margin_left = 12
	sb_hover.content_margin_right = 12
	sb_hover.content_margin_top = 4
	sb_hover.content_margin_bottom = 4
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func rebuild_list():
	# Clear list vbox
	for child in list_vbox.get_children():
		child.queue_free()
		list_vbox.remove_child(child)
		
	visible_items.clear()
	highlighted_index = -1
	
	var current_item_index: int
	
	var query = search_query.strip_edges().to_lower()
	if query != "":
		# Filter and score items, then sort by score descending
		var scored = []
		for item in all_items:
			var score = _item_match_score(item, query)
			if score > 0:
				scored.append({"item": item, "score": score})
		scored.sort_custom(func(a, b): return a.score > b.score)
		
		var item_index = 0
		for entry in scored:
			var item = entry.item
			var btn = Button.new()
			# Show path: e.g. "ASSETS > SPAWN MESHES"
			if item.type == "node":
				btn.text = item.category.to_upper() + " > " + item.label.to_upper()
				btn.tooltip_text = item.get("tooltip", "")
			else:
				btn.text = item.label.to_upper()
				
			_style_menu_button(btn)
			
			current_item_index = item_index
			btn.mouse_entered.connect(func():
				_set_highlight(current_item_index)
			)
			btn.pressed.connect(func():
				_select_item(item)
			)
			
			list_vbox.add_child(btn)
			item.button_node = btn
			visible_items.append(item)
			item_index += 1
	else:
		# Empty search query -> show collapsed browsing
		var item_index = 0
		
		if current_category != "":
			# We are inside a category!
			# Render Back button
			var back_btn = Button.new()
			back_btn.text = "< " + current_category.to_upper()
			_style_menu_button(back_btn)
			back_btn.add_theme_color_override("font_color", Color("22d3ee")) # Cyan back color
			back_btn.add_theme_color_override("font_hover_color", Color("22d3ee"))
			
			current_item_index = item_index
			back_btn.mouse_entered.connect(func():
				_set_highlight(current_item_index)
			)
			back_btn.pressed.connect(func():
				current_category = ""
				rebuild_list()
			)
			
			list_vbox.add_child(back_btn)
			
			var back_item = {
				"type": "back",
				"key": null,
				"label": "Back",
				"category": "",
				"button_node": back_btn
			}
			visible_items.append(back_item)
			item_index += 1
			
			# Render node items of this category
			for item in all_items:
				if item.type == "node" and item.category == current_category:
					var btn = Button.new()
					btn.text = item.label.to_upper()
					btn.tooltip_text = item.get("tooltip", "")
					_style_menu_button(btn)
					
					current_item_index = item_index
					btn.mouse_entered.connect(func():
						_set_highlight(current_item_index)
					)
					btn.pressed.connect(func():
						_select_item(item)
					)
					
					list_vbox.add_child(btn)
					item.button_node = btn
					visible_items.append(item)
					item_index += 1
		else:
			# We are at the root list: show Actions, Inputs, and Categories
			
			# Render Actions, Inputs & Outputs first (flat)
			for item in all_items:
				if item.type in ["action", "input", "output"]:
					var btn = Button.new()
					btn.text = item.label.to_upper()
					_style_menu_button(btn)
					
					current_item_index = item_index
					btn.mouse_entered.connect(func():
						_set_highlight(current_item_index)
					)
					btn.pressed.connect(func():
						_select_item(item)
					)
					
					list_vbox.add_child(btn)
					item.button_node = btn
					visible_items.append(item)
					item_index += 1
			
			# Render "Recently Used" section
			if recently_used.size() > 0:
				var recent_header = Label.new()
				recent_header.text = "RECENTLY USED"
				recent_header.add_theme_font_size_override("font_size", 9)
				recent_header.add_theme_color_override("font_color", Color("6b7280"))
				var header_margin = MarginContainer.new()
				header_margin.add_theme_constant_override("margin_left", 12)
				header_margin.add_theme_constant_override("margin_top", 6)
				header_margin.add_theme_constant_override("margin_bottom", 2)
				header_margin.add_child(recent_header)
				list_vbox.add_child(header_margin)
				
				for template_name in recently_used:
					var recent_item = null
					for item in all_items:
						if item.type == "node" and item.key == template_name:
							recent_item = item
							break
					if recent_item == null:
						continue
					var btn = Button.new()
					btn.text = recent_item.label.to_upper()
					btn.tooltip_text = recent_item.get("tooltip", "")
					_style_menu_button(btn)
					btn.add_theme_color_override("font_color", ACCENT_COLOR)
					
					current_item_index = item_index
					btn.mouse_entered.connect(func():
						_set_highlight(current_item_index)
					)
					var captured_item = recent_item
					btn.pressed.connect(func():
						_select_item(captured_item)
					)
					
					list_vbox.add_child(btn)
					recent_item.button_node = btn
					visible_items.append(recent_item)
					item_index += 1
				
				# Small separator after recent
				var sep = HSeparator.new()
				var sep_style = StyleBoxLine.new()
				sep_style.color = Color(1.0, 1.0, 1.0, 0.05)
				sep_style.thickness = 1
				sep.add_theme_stylebox_override("separator", sep_style)
				list_vbox.add_child(sep)
			
			# Render categories collapsed
			var categories = []
			for item in all_items:
				if item.type == "node":
					var cat = item.category
					if not cat in categories:
						categories.append(cat)
			categories.sort()
			
			for cat in categories:
				var btn = Button.new()
				btn.text = cat.to_upper() + "  >"
				_style_menu_button(btn)
				btn.add_theme_color_override("font_color", Color("cbd5e1")) # slightly brighter for categories
				
				current_item_index = item_index
				var target_cat = cat
				btn.mouse_entered.connect(func():
					_set_highlight(current_item_index)
					_show_sub_panel(target_cat, btn)
				)
				btn.mouse_exited.connect(func():
					_start_sub_panel_hide_timer()
				)
				btn.pressed.connect(func():
					current_category = target_cat
					_hide_sub_panel_immediately()
					rebuild_list()
				)
				
				list_vbox.add_child(btn)
				
				var cat_item = {
					"type": "category",
					"key": cat,
					"label": cat,
					"category": "",
					"button_node": btn
				}
				visible_items.append(cat_item)
				item_index += 1
				
	if visible_items.size() > 0:
		_set_highlight(0)
		
	# Disable vertical scrollbar if content fits
	var main_content_height = list_vbox.get_child_count() * ROW_HEIGHT + 12
	var main_scroll_height = min(main_content_height, MENU_MAX_HEIGHT)
	scroll.custom_minimum_size = Vector2(MENU_WIDTH, main_scroll_height)
	if main_content_height > MENU_MAX_HEIGHT:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	else:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		
	update_layout()

func update_layout(hovered_button: Button = null):
	min_size = Vector2i(MENU_WIDTH, 0)
	reset_size()
	size.x = MENU_WIDTH

	if submenu_popup.visible:
		var item_count = sub_list_vbox.get_child_count()
		var content_height = item_count * ROW_HEIGHT + 12
		var has_arrow_buttons = sub_scroll_up_btn != null and sub_scroll_down_btn != null
		var scrollbar_width = 14
		var scroll_max_height = MENU_MAX_HEIGHT
		var chosen_scroll_height = min(content_height, scroll_max_height)
		
		# Disable vertical scrollbar if content fits
		var has_overflow = content_height > scroll_max_height
		sub_has_scroll_overflow = has_overflow
		sub_scroll_max = maxf(0.0, content_height - chosen_scroll_height)
		sub_scroll_value = clampf(sub_scroll_value, 0.0, sub_scroll_max)
		var submenu_height = maxi(ROW_HEIGHT, int(chosen_scroll_height))
		var view_width = MENU_WIDTH - (scrollbar_width if has_overflow else 0)
		var sub_container = sub_scroll.get_parent() as Control
		if sub_container:
			sub_container.custom_minimum_size = Vector2(MENU_WIDTH, submenu_height)
			sub_container.size = Vector2(MENU_WIDTH, submenu_height)
		sub_scroll.custom_minimum_size = Vector2(view_width, chosen_scroll_height)
		sub_scroll.position = Vector2.ZERO
		sub_scroll.size = Vector2(view_width, chosen_scroll_height)
		if sub_list_margin:
			sub_list_margin.custom_minimum_size = Vector2(view_width, content_height)
			sub_list_margin.size = Vector2(view_width, content_height)
			sub_list_margin.position = Vector2(0, -sub_scroll_value)
		if sub_scrollbar:
			sub_scrollbar.visible = has_overflow
			sub_scrollbar.position = Vector2(view_width, 0)
			sub_scrollbar.size = Vector2(scrollbar_width, chosen_scroll_height)
			sub_scrollbar.min_value = 0.0
			sub_scrollbar.max_value = content_height
			sub_scrollbar.page = chosen_scroll_height
			sub_scrollbar.step = 1.0
			sub_scrollbar.value = sub_scroll_value
		if has_arrow_buttons:
			sub_scroll_up_btn.visible = has_overflow
			sub_scroll_down_btn.visible = has_overflow
			sub_scroll_up_btn.position = Vector2.ZERO
			sub_scroll_up_btn.size = Vector2(view_width, SCROLL_ARROW_HEIGHT)
			sub_scroll_down_btn.position = Vector2(0, chosen_scroll_height - SCROLL_ARROW_HEIGHT)
			sub_scroll_down_btn.size = Vector2(view_width, SCROLL_ARROW_HEIGHT)
		if not has_overflow:
			_set_sub_scroll_value(0.0)

		submenu_popup.min_size = Vector2i(MENU_WIDTH, submenu_height)
		submenu_popup.size = Vector2i(MENU_WIDTH, submenu_height)
		
		# Position submenu popup to the right of the main popup
		var x = position.x + size.x + 8
		var y = position.y
		
		if hovered_button and is_instance_valid(hovered_button):
			# Calculate screen y of hovered button: window pos + button local y
			y = position.y + int(hovered_button.global_position.y)
			# Clamp y so the submenu doesn't go below the main popup's bottom
			var max_y = position.y + size.y - submenu_popup.size.y
			y = clamp(y, position.y, max(position.y, max_y))
			
		submenu_popup.position = Vector2i(x, y)
		call_deferred("_update_sub_scroll_arrows")

func _set_highlight(index: int):
	# Clear previous highlight
	if highlighted_index >= 0 and highlighted_index < visible_items.size():
		var old_item = visible_items[highlighted_index]
		if is_instance_valid(old_item.button_node):
			old_item.button_node.add_theme_color_override("font_color", Color("c8c8d4"))
			var sb_normal = StyleBoxEmpty.new()
			sb_normal.content_margin_left = 12
			sb_normal.content_margin_right = 12
			sb_normal.content_margin_top = 4
			sb_normal.content_margin_bottom = 4
			old_item.button_node.add_theme_stylebox_override("normal", sb_normal)
			
	highlighted_index = index
	if highlighted_index >= 0 and highlighted_index < visible_items.size():
		var new_item = visible_items[highlighted_index]
		if is_instance_valid(new_item.button_node):
			new_item.button_node.add_theme_color_override("font_color", Color.WHITE)
			var sb_sel = StyleBoxFlat.new()
			sb_sel.bg_color = Color(1.0, 1.0, 1.0, 0.08) # slightly brighter background
			sb_sel.set_corner_radius_all(4)
			sb_sel.content_margin_left = 12
			sb_sel.content_margin_right = 12
			sb_sel.content_margin_top = 4
			sb_sel.content_margin_bottom = 4
			new_item.button_node.add_theme_stylebox_override("normal", sb_sel)
			# Ensure it is visible in scroll container
			_ensure_visible(new_item.button_node)

func _ensure_visible(ctrl: Control):
	var scroll_y = scroll.scroll_vertical
	var scroll_height = scroll.size.y
	var ctrl_y = ctrl.position.y
	var ctrl_height = ctrl.size.y
	
	if ctrl_y < scroll_y:
		scroll.scroll_vertical = int(ctrl_y)
	elif ctrl_y + ctrl_height > scroll_y + scroll_height:
		scroll.scroll_vertical = int(ctrl_y + ctrl_height - scroll_height)

func _select_item(item: Dictionary):
	if item.type == "node":
		_track_recently_used(item.key)
		node_selected.emit(item.key)
		hide()
	elif item.type == "action":
		action_selected.emit(item.key)
		hide()
	elif item.type == "input":
		input_selected.emit(item.key)
		hide()
	elif item.type == "output":
		output_selected.emit(item.key)
		hide()
	elif item.type == "category":
		current_category = item.key
		rebuild_list()
	elif item.type == "back":
		current_category = ""
		rebuild_list()

func _track_recently_used(template_name: String):
	# Remove if already present
	var idx = recently_used.find(template_name)
	if idx >= 0:
		recently_used.remove_at(idx)
	# Insert at front
	recently_used.insert(0, template_name)
	# Trim to max
	if recently_used.size() > MAX_RECENT:
		recently_used.resize(MAX_RECENT)

func _on_search_text_changed(new_text: String):
	search_query = new_text
	rebuild_list()

func _on_line_edit_gui_input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_UP:
				if visible_items.size() > 0:
					var next_idx = highlighted_index - 1
					if next_idx < 0:
						next_idx = visible_items.size() - 1
					_set_highlight(next_idx)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				if visible_items.size() > 0:
					var next_idx = (highlighted_index + 1) % visible_items.size()
					_set_highlight(next_idx)
				get_viewport().set_input_as_handled()
			KEY_LEFT:
				if current_category != "" and search_query == "":
					current_category = ""
					rebuild_list()
					get_viewport().set_input_as_handled()
			KEY_RIGHT:
				if highlighted_index >= 0 and highlighted_index < visible_items.size() and search_query == "":
					var item = visible_items[highlighted_index]
					if item.type == "category":
						current_category = item.key
						rebuild_list()
						get_viewport().set_input_as_handled()
			KEY_ENTER:
				if highlighted_index >= 0 and highlighted_index < visible_items.size():
					_select_item(visible_items[highlighted_index])
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				hide()
				get_viewport().set_input_as_handled()

func _show_sub_panel(category_name: String, category_button: Button):
	_cancel_sub_panel_hide_timer()
	
	if active_hovered_category == category_name and submenu_popup.visible:
		return # Already showing this category
		
	active_hovered_category = category_name
	
	# Clear sub list
	for child in sub_list_vbox.get_children():
		child.queue_free()
		sub_list_vbox.remove_child(child)
		
	# Populate sub list buttons
	var sub_items = all_items.filter(func(item):
		return item.type == "node" and item.category == category_name
	)
	
	for item in sub_items:
		var btn = Button.new()
		btn.text = item.label.to_upper()
		btn.tooltip_text = item.get("tooltip", "")
		_style_menu_button(btn)
		
		btn.mouse_entered.connect(func():
			_cancel_sub_panel_hide_timer()
			btn.add_theme_color_override("font_color", Color.WHITE)
			var sb_sel = StyleBoxFlat.new()
			sb_sel.bg_color = Color(1.0, 1.0, 1.0, 0.08)
			sb_sel.set_corner_radius_all(4)
			sb_sel.content_margin_left = 12
			sb_sel.content_margin_right = 12
			sb_sel.content_margin_top = 4
			sb_sel.content_margin_bottom = 4
			btn.add_theme_stylebox_override("normal", sb_sel)
		)
		btn.mouse_exited.connect(func():
			_start_sub_panel_hide_timer()
			btn.add_theme_color_override("font_color", Color("c8c8d4"))
			var sb_normal = StyleBoxEmpty.new()
			sb_normal.content_margin_left = 12
			sb_normal.content_margin_right = 12
			sb_normal.content_margin_top = 4
			sb_normal.content_margin_bottom = 4
			btn.add_theme_stylebox_override("normal", sb_normal)
		)
		
		btn.pressed.connect(func():
			_select_item(item)
		)
		
		sub_list_vbox.add_child(btn)
		
	_set_sub_scroll_value(0.0)
	submenu_popup.visible = true
	update_layout(category_button)

func _hide_sub_panel_immediately():
	_cancel_sub_panel_hide_timer()
	if submenu_popup.visible:
		submenu_popup.visible = false
		active_hovered_category = ""

func _start_sub_panel_hide_timer():
	_cancel_sub_panel_hide_timer()
	sub_panel_hide_timer = get_tree().create_timer(SUBMENU_HIDE_DELAY)
	sub_panel_hide_timer.timeout.connect(func():
		if not is_instance_valid(self):
			return
		if sub_panel_hide_timer and not _is_mouse_near_submenu_stack():
			_hide_sub_panel_immediately()
		elif sub_panel_hide_timer:
			_start_sub_panel_hide_timer()
	)

func _cancel_sub_panel_hide_timer():
	if sub_panel_hide_timer:
		sub_panel_hide_timer = null

func _process(delta):
	if not visible:
		return
		
	# Bounding box calculation for automatic hide when mouse moves too far away
	# We use screen-level coordinates from DisplayServer to avoid clamping issues outside the popup window
	var mouse_screen_pos = DisplayServer.mouse_get_position()
	
	# Main popup screen rect
	var main_rect = Rect2(position, size)
	var dist = _dist_to_rect(mouse_screen_pos, main_rect)
	
	if submenu_popup.visible:
		var sub_rect = Rect2(submenu_popup.position, submenu_popup.size)
		var sub_dist = _dist_to_rect(mouse_screen_pos, sub_rect)
		dist = min(dist, sub_dist)
		
	if dist > POPUP_KEEPALIVE_DISTANCE:
		hide()

func _is_mouse_near_submenu_stack() -> bool:
	var mouse_screen_pos = DisplayServer.mouse_get_position()
	var main_rect = Rect2(position, size).grow(SUBMENU_KEEPALIVE_PADDING)
	if main_rect.has_point(mouse_screen_pos):
		return true
	if submenu_popup.visible:
		var sub_rect = Rect2(submenu_popup.position, submenu_popup.size).grow(SUBMENU_KEEPALIVE_PADDING)
		if sub_rect.has_point(mouse_screen_pos):
			return true
	return false

func _dist_to_rect(p: Vector2, rect: Rect2) -> float:
	var dx = max(rect.position.x - p.x, 0.0, p.x - rect.end.x)
	var dy = max(rect.position.y - p.y, 0.0, p.y - rect.end.y)
	return sqrt(dx*dx + dy*dy)
