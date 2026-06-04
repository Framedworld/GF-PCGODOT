@tool
extends PanelContainer
class_name FlowInspector

signal property_edited(prop_name: String)

const BASE_SETTINGS_PROPS = [
	"random_seed", "inspect_enabled", "debug_enabled", "debug_mode", "debug_scale",
	"debug_bulk", "debug_output", "debug_color", "debug_modulate_by", "title",
	"disabled", "trace", "resource_local_to_scene", "resource_path", "resource_name", "script"
]
const GRAPH_PARAMETER_VALUE_EDITED := "_graph_parameter_value_edited"

var current_node: Node = null
var current_settings: Object = null
var current_target: Object = null
var editor: Control = null
var ui_scale: float = 1.0

var scroll_container: ScrollContainer
var content_vbox: VBoxContainer

func _scaled_font_size(base_size: int) -> int:
	return maxi(1, int(round(base_size * ui_scale)))

func _ready():
	custom_minimum_size.x = 268
	if Engine.is_editor_hint():
		ui_scale = EditorInterface.get_editor_scale()

	# Apply original dark theme panel colors
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("1b1e28") # #1b1e28 node cards background
	sb.set_border_width_all(0)
	sb.border_width_left = 1
	sb.border_color = Color("252836") # #252836 border/separator
	add_theme_stylebox_override("panel", sb)

	# Create ScrollContainer
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll_container)

	# MarginContainer for spacing inside ScrollContainer
	var margin_container = MarginContainer.new()
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_theme_constant_override("margin_left", 12)
	margin_container.add_theme_constant_override("margin_right", 12)
	margin_container.add_theme_constant_override("margin_top", 12)
	margin_container.add_theme_constant_override("margin_bottom", 12)
	scroll_container.add_child(margin_container)

	# Create ContentVBox
	content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 12)
	margin_container.add_child(content_vbox)

	edit(null)


func _sync_panel_visibility() -> void:
	var has_content := current_target != null and content_vbox.get_child_count() > 0
	visible = has_content
	scroll_container.visible = has_content


func edit(target_node: Object):
	current_target = target_node
	current_node = null if not target_node is Node else target_node
	current_settings = null

	# Clear existing children in ContentVBox
	for child in content_vbox.get_children():
		child.queue_free()
		content_vbox.remove_child(child)

	if target_node == null:
		_sync_panel_visibility()
		return

	if target_node is GraphFrame:
		_populate_frame_properties(target_node)
	elif target_node is GraphNode:
		if target_node.node_template == "input":
			var editor_instance = target_node.getEditor()
			if editor_instance and editor_instance.current_resource:
				current_settings = editor_instance.current_resource
				_populate_graph_resource_properties(editor_instance.current_resource)
				_populate_graph_resource_outputs(editor_instance.current_resource)
				_sync_panel_visibility()
				return
		elif target_node.node_template == "output":
			var editor_instance = target_node.getEditor()
			if editor_instance and editor_instance.current_resource:
				current_settings = editor_instance.current_resource
				_populate_graph_resource_outputs(editor_instance.current_resource)
				_sync_panel_visibility()
				return
		if "settings" in target_node and target_node.settings != null:
			current_settings = target_node.settings
			_populate_node_properties(target_node, target_node.settings)
		else:
			_populate_generic_node_properties(target_node)
	elif target_node is FlowGraphResource:
		current_settings = target_node
		_populate_graph_resource_properties(target_node)
		_populate_graph_resource_outputs(target_node)
	elif target_node is Resource:
		current_settings = target_node
		_populate_generic_resource_properties(target_node)
	_sync_panel_visibility()

func edit_editor_settings(flow_editor):
	current_target = flow_editor
	current_node = null
	current_settings = flow_editor

	for child in content_vbox.get_children():
		child.queue_free()
		content_vbox.remove_child(child)

	_populate_flow_editor_settings(flow_editor)
	_sync_panel_visibility()

func refresh_localized_text() -> void:
	if current_target != null and is_instance_valid(current_target):
		if current_target.has_method("_on_auto_regen_toggled"):
			edit_editor_settings(current_target)
		else:
			edit(current_target)
		return
	edit(null)

func _node_title(node: GraphNode) -> String:
	if node != null and node.has_method("getLocalizedTitle"):
		return str(node.call("getLocalizedTitle"))
	return FlowI18n.tn(node.title)

func _hide_inspector_title_enabled() -> bool:
	if current_target != null and "hide_inspector_title" in current_target:
		return bool(current_target.hide_inspector_title)
	if current_node != null and current_node.has_method("getEditor"):
		var flow_editor = current_node.getEditor()
		if flow_editor and "hide_inspector_title" in flow_editor:
			return bool(flow_editor.hide_inspector_title)
	return false

func _localized_property_label(property_name: String) -> String:
	return FlowI18n.tn(_format_label(property_name))

func _section_label(expanded: bool, label: String) -> String:
	var prefix := "▼ " if expanded else "▶ "
	return prefix + FlowI18n.t(label)

func _populate_flow_editor_settings(flow_editor):
	_add_header(FlowI18n.t("Settings"), FlowI18n.t("Flow Editor"))

	var settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 10)
	content_vbox.add_child(settings_box)

	settings_box.add_child(_create_row(FlowI18n.t("Auto Generate"), _create_editor_setting_checkbox(flow_editor.auto_regen, func(pressed):
		flow_editor._on_auto_regen_toggled(pressed)
	)))
	settings_box.add_child(_create_row(FlowI18n.t("Color Nodes"), _create_editor_setting_checkbox(flow_editor.color_nodes, func(pressed):
		flow_editor._on_color_nodes_toggled(pressed)
	)))
	settings_box.add_child(_create_row(FlowI18n.t("Native GraphEdit Grid"), _create_editor_setting_checkbox(flow_editor.use_native_graph_grid, func(pressed):
		flow_editor._on_native_graph_grid_toggled(pressed)
	)))
	settings_box.add_child(_create_row(FlowI18n.t("Node Language"), _create_editor_setting_checkbox(FlowI18n.is_node_translation_enabled(), func(pressed):
		flow_editor._on_node_translation_toggled(pressed)
	)))
	settings_box.add_child(_create_row(FlowI18n.t("Hide Title"), _create_editor_setting_checkbox(flow_editor.hide_inspector_title, func(pressed):
		flow_editor._on_hide_inspector_title_toggled(pressed)
	)))
	settings_box.add_child(_create_row(FlowI18n.t("Hide Resource Built-in Rows"), _create_editor_setting_checkbox(flow_editor.hide_resource_builtin_rows, func(pressed):
		flow_editor._on_hide_resource_builtin_rows_toggled(pressed)
	)))
	settings_box.add_child(_create_row(FlowI18n.t("Track External Edits"), _create_editor_setting_checkbox(flow_editor.track_external_edits, func(pressed):
		flow_editor._on_track_external_edits_toggled(pressed)
	)))

func _create_editor_setting_checkbox(is_pressed: bool, changed: Callable) -> CheckBox:
	var checkbox = CheckBox.new()
	checkbox.button_pressed = is_pressed
	checkbox.toggled.connect(changed)
	return checkbox

func _populate_frame_properties(frame: GraphFrame):
	_add_header(FlowI18n.tn(frame.title), frame.name)

	# Frame Properties Container
	var prop_box = VBoxContainer.new()
	prop_box.add_theme_constant_override("separation", 8)
	content_vbox.add_child(prop_box)

	# Title
	prop_box.add_child(_create_row(FlowI18n.t("Title"), _create_string_input(frame, "title")))
	# Tint Color
	prop_box.add_child(_create_row(FlowI18n.t("Tint Color"), _create_color_input(frame, "tint_color")))
	# Tint Enabled
	prop_box.add_child(_create_row(FlowI18n.t("Tint Enabled"), _create_bool_input(frame, "tint_color_enabled")))

	var flow_editor: FlowEditor = _find_flow_editor(frame)
	if flow_editor:
		var actions_box := VBoxContainer.new()
		actions_box.add_theme_constant_override("separation", 6)
		content_vbox.add_child(actions_box)
		var add_btn := Button.new()
		add_btn.text = FlowI18n.t("Add Selected Nodes")
		add_btn.pressed.connect(func():
			var added: int = flow_editor.add_selected_nodes_to_comment_frame(frame)
			if flow_editor.has_method("update_status_bar"):
				if added > 0:
					flow_editor.update_status_bar(FlowI18n.t("Added %d nodes to comment") % added)
				else:
					flow_editor.update_status_bar(FlowI18n.t("No nodes added to comment"))
		)
		actions_box.add_child(add_btn)
		var remove_btn := Button.new()
		remove_btn.text = FlowI18n.t("Remove Selected Nodes")
		remove_btn.pressed.connect(func():
			var removed: int = flow_editor.remove_selected_nodes_from_comment_frame(frame)
			if flow_editor.has_method("update_status_bar"):
				if removed > 0:
					flow_editor.update_status_bar(FlowI18n.t("Removed %d nodes from comment") % removed)
				else:
					flow_editor.update_status_bar(FlowI18n.t("No nodes removed from comment"))
		)
		actions_box.add_child(remove_btn)

func _find_flow_editor(from_node: Node) -> FlowEditor:
	var current := from_node
	while current:
		if current is FlowEditor:
			return current as FlowEditor
		current = current.get_parent()
	return null

func _populate_generic_node_properties(node: GraphNode):
	var hide_title := _hide_inspector_title_enabled()
	_add_header(_node_title(node), node.name, not hide_title)

func _populate_node_properties(node: GraphNode, settings: Object):
	var hide_title := _hide_inspector_title_enabled()
	_add_header(_node_title(node), node.name, not hide_title)

	# Build attribute selector lookup: prop_name -> port
	var attr_selector_map := {}
	if settings.has_method("_get_attribute_selector_props"):
		for entry in settings._get_attribute_selector_props():
			attr_selector_map[entry["prop"]] = entry.get("port", 0)

	var variable_selector_props := {}
	if settings.has_method("_get_variable_selector_props"):
		for entry in settings._get_variable_selector_props():
			variable_selector_props[entry["prop"]] = true

	# Type-specific properties container
	var type_box = VBoxContainer.new()
	type_box.add_theme_constant_override("separation", 10)
	content_vbox.add_child(type_box)

	if not hide_title:
		type_box.add_child(_create_row(FlowI18n.t("Title"), _create_string_input(settings, "title")))

	# Gather subclass-specific properties
	var props = settings.get_property_list()
	var has_custom_props = false

	for prop in props:
		if prop.name in BASE_SETTINGS_PROPS:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if settings.has_method("exposeParam") and not settings.exposeParam(prop.name):
			continue

		var ctrl: Control
		if attr_selector_map.has(prop.name):
			ctrl = _create_attribute_selector(node, settings, prop.name, attr_selector_map[prop.name])
		elif variable_selector_props.has(prop.name):
			ctrl = _create_variable_selector(node, settings, prop.name)
		else:
			ctrl = _create_control_for_property(settings, prop)
		if ctrl:
			type_box.add_child(_create_row(_localized_property_label(prop.name), ctrl))
			has_custom_props = true

	if node is FlowNodeBase and node.node_template == "get_variable":
		type_box.add_child(_create_row(FlowI18n.t("Source"), _create_get_variable_source_button(node, settings)))
		has_custom_props = true
	if node is FlowNodeBase and node.node_template == "set_variable":
		_populate_set_variable_get_references(node as FlowNodeBase, settings, type_box)
		has_custom_props = true

	if not has_custom_props:
		var lbl_empty = Label.new()
		lbl_empty.text = FlowI18n.t("No custom settings")
		lbl_empty.add_theme_color_override("font_color", Color("a1a1aa"))
		lbl_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_box.add_child(lbl_empty)

	# Separator before Common Settings
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", _create_separator_stylebox())
	content_vbox.add_child(sep)

	# Collapsible Common Settings
	var common_header = Button.new()
	common_header.text = _section_label(true, "Common Settings")
	common_header.flat = true
	common_header.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
	common_header.add_theme_color_override("font_color", Color("22d3ee")) # Cyan #22d3ee accent
	common_header.add_theme_color_override("font_hover_color", Color.WHITE)
	content_vbox.add_child(common_header)

	var common_container = VBoxContainer.new()
	common_container.add_theme_constant_override("separation", 8)
	content_vbox.add_child(common_container)

	common_header.pressed.connect(func():
		common_container.visible = not common_container.visible
		if common_container.visible:
			common_header.text = _section_label(true, "Common Settings")
		else:
			common_header.text = _section_label(false, "Common Settings")
	)

	# Populate Common Settings
	for prop in props:
		if not prop.name in BASE_SETTINGS_PROPS:
			continue
		if prop.name in ["resource_local_to_scene", "resource_path", "resource_name", "script", "title", "disabled", "trace"]:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		if settings.has_method("exposeParam") and not settings.exposeParam(prop.name):
			continue

		var ctrl = _create_control_for_property(settings, prop)
		if ctrl:
			common_container.add_child(_create_row(_localized_property_label(prop.name), ctrl))

	# Override Pins for subgraph nodes
	if node.node_template == "subgraph" and settings is SubgraphNodeSettings and settings.graph:
		_populate_subgraph_overrides(node, settings)

func _populate_subgraph_overrides(node: GraphNode, settings: SubgraphNodeSettings):
	var sep = HSeparator.new()
	sep.add_theme_stylebox_override("separator", _create_separator_stylebox())
	content_vbox.add_child(sep)

	var header = Button.new()
	header.text = _section_label(true, "Override Pins")
	header.flat = true
	header.alignment = HorizontalAlignment.HORIZONTAL_ALIGNMENT_LEFT
	header.add_theme_color_override("font_color", Color("fbbf24"))  # Yellow for overrides
	header.add_theme_color_override("font_hover_color", Color.WHITE)
	content_vbox.add_child(header)

	var override_container = VBoxContainer.new()
	override_container.add_theme_constant_override("separation", 8)
	content_vbox.add_child(override_container)

	header.pressed.connect(func():
		override_container.visible = not override_container.visible
		header.text = _section_label(override_container.visible, "Override Pins")
	)

	for param in settings.graph.in_params:
		if not param:
			continue
		# Create a row with: [Override checkbox] [Param name] [Value control]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Override toggle checkbox
		var checkbox = CheckBox.new()
		checkbox.button_pressed = settings.has_param_override(param.name)
		checkbox.add_theme_font_size_override("font_size", _scaled_font_size(11))

		# Value control based on param type
		var value_ctrl = _create_override_value_control(settings, param)
		if value_ctrl:
			value_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Dim the control when override is not active
			if not settings.has_param_override(param.name):
				value_ctrl.modulate = Color(1, 1, 1, 0.4)

			var captured_param = param
			var captured_ctrl = value_ctrl
			checkbox.toggled.connect(func(pressed: bool):
				if pressed:
					settings.set_param_override(captured_param.name, captured_param.get_default_value())
					captured_ctrl.modulate = Color.WHITE
				else:
					settings.clear_param_override(captured_param.name)
					captured_ctrl.modulate = Color(1, 1, 1, 0.4)
				property_edited.emit("param_overrides")
			)

		row.add_child(checkbox)

		var label = Label.new()
		label.text = param.name
		label.add_theme_font_size_override("font_size", _scaled_font_size(11))
		label.custom_minimum_size.x = 80
		row.add_child(label)

		if value_ctrl:
			row.add_child(value_ctrl)

		override_container.add_child(row)

func _create_override_value_control(settings: SubgraphNodeSettings, param: GraphInputParameter) -> Control:
	var current_val = settings.get_param_value(param)

	match param.data_type:
		FlowData.DataType.Bool:
			var cb = CheckBox.new()
			cb.button_pressed = current_val if current_val is bool else false
			var captured_param = param
			cb.toggled.connect(func(pressed):
				settings.set_param_override(captured_param.name, pressed)
				property_edited.emit("param_overrides")
			)
			return cb
		FlowData.DataType.Int:
			var sb = SpinBox.new()
			sb.min_value = -999999
			sb.max_value = 999999
			sb.step = 1
			sb.value = int(current_val) if current_val != null else 0
			var captured_param = param
			sb.value_changed.connect(func(new_val):
				settings.set_param_override(captured_param.name, int(new_val))
				property_edited.emit("param_overrides")
			)
			return sb
		FlowData.DataType.Float:
			var sb = SpinBox.new()
			sb.min_value = -999999.0
			sb.max_value = 999999.0
			sb.step = 0.01
			sb.value = float(current_val) if current_val != null else 0.0
			var captured_param = param
			sb.value_changed.connect(func(new_val):
				settings.set_param_override(captured_param.name, new_val)
				property_edited.emit("param_overrides")
			)
			return sb
		FlowData.DataType.String:
			var le = LineEdit.new()
			le.text = str(current_val) if current_val != null else ""
			le.add_theme_font_size_override("font_size", _scaled_font_size(11))
			var sb_style := StyleBoxFlat.new()
			sb_style.bg_color = Color("111318")
			sb_style.set_corner_radius_all(3)
			sb_style.content_margin_left = 6
			sb_style.content_margin_right = 6
			le.add_theme_stylebox_override("normal", sb_style)
			var captured_param = param
			le.text_submitted.connect(func(new_text):
				settings.set_param_override(captured_param.name, new_text)
				property_edited.emit("param_overrides")
			)
			le.focus_exited.connect(func():
				var cur = settings.get_param_value(captured_param)
				if str(cur) != le.text:
					settings.set_param_override(captured_param.name, le.text)
					property_edited.emit("param_overrides")
			)
			return le
		FlowData.DataType.Vector:
			var vec_val: Vector3 = current_val if current_val is Vector3 else Vector3.ZERO
			var hbc = HBoxContainer.new()
			hbc.add_theme_constant_override("separation", 4)
			var captured_param = param
			for axis in ["x", "y", "z"]:
				var this_axis = axis
				var sb_axis = SpinBox.new()
				sb_axis.min_value = -999999.0
				sb_axis.max_value = 999999.0
				sb_axis.step = 0.01
				sb_axis.custom_minimum_size.x = 48
				sb_axis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if axis == "x":
					sb_axis.value = vec_val.x
				elif axis == "y":
					sb_axis.value = vec_val.y
				else:
					sb_axis.value = vec_val.z
				sb_axis.value_changed.connect(func(new_val):
					var cur_val = settings.get_param_value(captured_param)
					var next_vec: Vector3 = cur_val if cur_val is Vector3 else Vector3.ZERO
					if this_axis == "x":
						next_vec.x = new_val
					elif this_axis == "y":
						next_vec.y = new_val
					else:
						next_vec.z = new_val
					settings.set_param_override(captured_param.name, next_vec)
					property_edited.emit("param_overrides")
				)
				hbc.add_child(sb_axis)
			return hbc
		FlowData.DataType.Resource:
			var res_hbox = HBoxContainer.new()
			var res_lbl = Label.new()
			res_lbl.text = FlowI18n.t("None") if current_val == null else current_val.resource_path.get_file()
			res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			res_lbl.clip_text = true
			res_lbl.add_theme_font_size_override("font_size", _scaled_font_size(11))
			res_hbox.add_child(res_lbl)
			var res_btn = Button.new()
			res_btn.text = "..."
			var captured_param = param
			res_btn.pressed.connect(func():
				var fd = FileDialog.new()
				fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
				fd.access = FileDialog.ACCESS_RESOURCES
				fd.add_filter("*.tres,*.res", "Resource Files")
				fd.file_selected.connect(func(path):
					var res = load(path)
					if res:
						settings.set_param_override(captured_param.name, res)
						res_lbl.text = path.get_file()
						property_edited.emit("param_overrides")
					fd.queue_free()
				)
				fd.canceled.connect(func():
					fd.queue_free()
				)
				add_child(fd)
				fd.popup_centered_ratio(0.4)
			)
			res_hbox.add_child(res_btn)
			return res_hbox
	return null

func _add_header(title_text: String, id_text: String, show_title: bool = true):
	# Title bar panel matching #252836
	var header_panel = PanelContainer.new()
	var hb_style = StyleBoxFlat.new()
	hb_style.bg_color = Color("252836") # #252836 node headers background
	hb_style.set_corner_radius_all(4)
	hb_style.content_margin_left = 10
	hb_style.content_margin_right = 10
	hb_style.content_margin_top = 8
	hb_style.content_margin_bottom = 8
	header_panel.add_theme_stylebox_override("panel", hb_style)

	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 2)
	header_panel.add_child(header_vbox)

	if show_title and not title_text.is_empty():
		var lbl_title = Label.new()
		lbl_title.text = title_text
		lbl_title.add_theme_font_size_override("font_size", _scaled_font_size(14))
		lbl_title.add_theme_color_override("font_color", Color.WHITE)
		header_vbox.add_child(lbl_title)

	var lbl_id = Label.new()
	lbl_id.text = id_text
	lbl_id.add_theme_font_size_override("font_size", _scaled_font_size(10 if show_title and not title_text.is_empty() else 14))
	lbl_id.add_theme_color_override("font_color", Color("a1a1aa") if show_title and not title_text.is_empty() else Color.WHITE)
	header_vbox.add_child(lbl_id)

	content_vbox.add_child(header_panel)

	# Small space
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 4
	content_vbox.add_child(spacer)

func _create_row(label_text: String, control: Control) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", _scaled_font_size(11))
	lbl.add_theme_color_override("font_color", Color("cbd5e1")) # light gray
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.clip_text = true
	row.add_child(lbl)

	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _create_control_for_property(obj: Object, prop: Dictionary) -> Control:
	var prop_name = prop.name
	var prop_type = prop.type
	var val = obj.get(prop_name)

	if prop_type == TYPE_INT and prop.hint == PROPERTY_HINT_ENUM:
		var opt = OptionButton.new()
		var options = prop.hint_string.split(",")
		for idx in range(options.size()):
			opt.add_item(FlowI18n.tn(options[idx]), idx)
		opt.selected = val
		opt.item_selected.connect(func(index):
			_on_value_changed(obj, prop_name, index)
		)
		opt.add_theme_font_size_override("font_size", _scaled_font_size(11))
		return opt

	match prop_type:
		TYPE_BOOL:
			var cb = CheckBox.new()
			cb.button_pressed = val
			cb.toggled.connect(func(pressed):
				_on_value_changed(obj, prop_name, pressed)
			)
			return cb
		TYPE_INT:
			var sb = SpinBox.new()
			sb.min_value = -999999
			sb.max_value = 999999
			sb.step = 1
			sb.value = val
			sb.value_changed.connect(func(new_val):
				_on_value_changed(obj, prop_name, int(new_val))
			)
			return sb
		TYPE_FLOAT:
			var sb = SpinBox.new()
			sb.min_value = -999999.0
			sb.max_value = 999999.0
			sb.step = 0.01
			sb.value = val
			sb.value_changed.connect(func(new_val):
				_on_value_changed(obj, prop_name, new_val)
			)
			return sb
		TYPE_STRING:
			return _create_string_input(obj, prop_name)
		TYPE_COLOR:
			return _create_color_input(obj, prop_name)
		TYPE_VECTOR3:
			return _create_vector3_input(obj, prop_name)
		TYPE_ARRAY:
			return _create_array_input(obj, prop_name, val if val is Array else [], prop)
		TYPE_DICTIONARY:
			return _create_dictionary_input(obj, prop_name, val if val is Dictionary else {})
		TYPE_OBJECT:
			var hbc = HBoxContainer.new()
			var lbl = Label.new()
			lbl.text = FlowI18n.t("None") if val == null else val.resource_path.get_file()
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.clip_text = true
			lbl.add_theme_font_size_override("font_size", _scaled_font_size(11))
			hbc.add_child(lbl)

			var btn = Button.new()
			btn.text = "..."
			btn.pressed.connect(func():
				_show_file_dialog_for_property(obj, prop_name, lbl, prop)
			)
			hbc.add_child(btn)
			return hbc

	return null

func _create_string_input(obj: Object, prop_name: String) -> LineEdit:
	var le = LineEdit.new()
	le.text = str(obj.get(prop_name))
	le.add_theme_font_size_override("font_size", _scaled_font_size(11))

	# Apply dark background stylebox #111318
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("111318")
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	le.add_theme_stylebox_override("normal", sb)

	le.text_submitted.connect(func(new_text):
		_on_value_changed(obj, prop_name, new_text)
	)
	le.focus_exited.connect(func():
		if str(obj.get(prop_name)) != le.text:
			_on_value_changed(obj, prop_name, le.text)
	)
	return le

## Creates an attribute selector: OptionButton dropdown populated from upstream
## stream names, with a "(custom...)" option that reveals a text field.
func _create_attribute_selector(node: GraphNode, settings: Object, prop_name: String, port: int) -> Control:
	var current_val := str(settings.get(prop_name))
	var stream_names := _get_input_stream_names(node, port)

	var wrapper = VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 4)

	var opt = OptionButton.new()
	opt.add_theme_font_size_override("font_size", _scaled_font_size(11))
	opt.custom_minimum_size.x = 100

	# Fallback text input for custom attribute names
	var le = LineEdit.new()
	le.text = current_val
	le.placeholder_text = FlowI18n.t("attribute name...")
	le.add_theme_font_size_override("font_size", _scaled_font_size(11))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("111318")
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	le.add_theme_stylebox_override("normal", sb)
	le.visible = false

	# Populate dropdown
	var selected_idx := -1
	var idx := 0
	for sname in stream_names:
		opt.add_item(sname, idx)
		if sname == current_val:
			selected_idx = idx
		idx += 1

	# Add separator and custom option
	var custom_idx := idx
	opt.add_separator()
	opt.add_item(FlowI18n.t("(custom...)"), custom_idx + 1)

	if stream_names.is_empty():
		opt.selected = opt.item_count - 1
		opt.set_item_text(opt.item_count - 1, FlowI18n.t("(no attributes found)"))
		opt.disabled = true
		opt.visible = true
		le.visible = true
	elif selected_idx >= 0:
		opt.selected = selected_idx
		opt.disabled = false
		opt.set_item_text(opt.item_count - 1, FlowI18n.t("(custom...)"))
		opt.visible = true
		le.visible = false
	else:
		opt.selected = opt.item_count - 1
		opt.disabled = false
		opt.set_item_text(opt.item_count - 1, FlowI18n.t("(custom...)"))
		opt.visible = true
		le.visible = true

	opt.item_selected.connect(func(index):
		var item_id = opt.get_item_id(index)
		if item_id == custom_idx + 1:
			# Switch to custom text input
			le.visible = true
			le.grab_focus()
		else:
			var chosen = opt.get_item_text(index)
			le.visible = false
			le.text = chosen
			_on_value_changed(settings, prop_name, chosen)
	)

	le.text_submitted.connect(func(new_text):
		_on_value_changed(settings, prop_name, new_text)
	)
	le.focus_exited.connect(func():
		if str(settings.get(prop_name)) != le.text:
			_on_value_changed(settings, prop_name, le.text)
	)

	wrapper.add_child(opt)
	wrapper.add_child(le)
	return wrapper

func _create_variable_selector(node: GraphNode, settings: Object, prop_name: String) -> Control:
	var current_val := str(settings.get(prop_name))
	var opt = OptionButton.new()
	opt.add_theme_font_size_override("font_size", 11)
	opt.custom_minimum_size.x = 100

	var selected_idx := -1
	var item_idx := 0
	var editor_instance = node.getEditor() if node and node.has_method("getEditor") else null
	var definitions := []
	if editor_instance and editor_instance.has_method("getSetVariableDefinitions"):
		definitions = editor_instance.getSetVariableDefinitions()

	for definition in definitions:
		var variable_name := String(definition.get("name", ""))
		if variable_name.is_empty():
			continue
		opt.add_item(variable_name, item_idx)
		if variable_name == current_val:
			selected_idx = item_idx
		item_idx += 1

	if item_idx == 0:
		opt.add_item(FlowI18n.t("No variables set"), 0)
		opt.selected = 0
		opt.disabled = true
	else:
		opt.disabled = false
		opt.select(selected_idx)

	opt.item_selected.connect(func(index):
		if opt.disabled:
			return
		_on_value_changed(settings, prop_name, opt.get_item_text(index))
		if node and node.has_method("refreshVariableChoices"):
			node.refreshVariableChoices()
	)
	return opt

func _populate_set_variable_get_references(node: FlowNodeBase, settings: Object, parent: VBoxContainer) -> void:
	var variable_name := str(settings.get("variable_name")).strip_edges()
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 4)
	parent.add_child(section)
	var header := Label.new()
	header.text = FlowI18n.t("Get nodes using this variable")
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color("a1a1aa"))
	section.add_child(header)
	if variable_name.is_empty():
		var hint := Label.new()
		hint.text = FlowI18n.t("Set a variable name first")
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color("71717a"))
		section.add_child(hint)
		return
	var editor_instance: FlowEditor = null
	if node.has_method("getEditor"):
		editor_instance = node.getEditor() as FlowEditor
	if editor_instance == null or not editor_instance.has_method("getGetVariableNodes"):
		return
	var get_nodes := editor_instance.getGetVariableNodes(variable_name)
	if get_nodes.is_empty():
		var empty := Label.new()
		empty.text = FlowI18n.t("No get nodes use this variable")
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color("71717a"))
		section.add_child(empty)
		return
	for get_node in get_nodes:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_child(row)
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 11)
		if get_node.has_method("getTitle"):
			btn.text = String(get_node.call("getTitle"))
		else:
			btn.text = String(get_node.name)
		btn.tooltip_text = FlowI18n.t("Pan to this get node without changing selection")
		btn.disabled = not editor_instance.has_method("focusGetVariableNode")
		var target := get_node
		btn.pressed.connect(func():
			if editor_instance and editor_instance.has_method("focusGetVariableNode"):
				editor_instance.focusGetVariableNode(target)
		)
		row.add_child(btn)

func _create_get_variable_source_button(node: GraphNode, settings: Object) -> Button:
	var btn = Button.new()
	btn.text = FlowI18n.t("Locate Set Variable")
	btn.add_theme_font_size_override("font_size", 11)

	var editor_instance = node.getEditor() if node and node.has_method("getEditor") else null
	btn.disabled = editor_instance == null or not editor_instance.has_method("focusSetVariableNode")
	btn.pressed.connect(func():
		var variable_name := str(settings.get("variable_name")).strip_edges()
		if variable_name.is_empty():
			return
		editor_instance.focusSetVariableNode(variable_name)
	)
	return btn

## Gets the stream names available on a node's input at the given port.
## Returns the names from the last-evaluated data (requires Regenerate first).
func _get_input_stream_names(node: GraphNode, port: int) -> PackedStringArray:
	var names := PackedStringArray()
	if not node or not "inputs" in node:
		return names
	if port < 0 or port >= node.inputs.size():
		return names
	var input_data = node.inputs[port]
	if input_data == null or not input_data is FlowData.Data:
		return names
	for sname in input_data.streams.keys():
		names.append(str(sname))
	names.sort()
	return names


func _create_bool_input(obj: Object, prop_name: String) -> CheckBox:
	var cb = CheckBox.new()
	cb.button_pressed = obj.get(prop_name)
	cb.toggled.connect(func(pressed):
		_on_value_changed(obj, prop_name, pressed)
	)
	return cb

func _create_color_input(obj: Object, prop_name: String) -> ColorPickerButton:
	var cpb = ColorPickerButton.new()
	cpb.color = obj.get(prop_name)
	cpb.color_changed.connect(func(new_color):
		_on_value_changed(obj, prop_name, new_color)
	)
	return cpb

func _create_vector3_input(obj: Object, prop_name: String) -> Control:
	var current_val = obj.get(prop_name)
	var value: Vector3 = current_val if current_val is Vector3 else Vector3.ZERO
	var hbc = HBoxContainer.new()
	hbc.add_theme_constant_override("separation", 4)
	for axis in ["x", "y", "z"]:
		var this_axis = axis
		var sb = SpinBox.new()
		sb.min_value = -999999.0
		sb.max_value = 999999.0
		sb.step = 0.01
		sb.custom_minimum_size.x = 52
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if axis == "x":
			sb.value = value.x
		elif axis == "y":
			sb.value = value.y
		else:
			sb.value = value.z
		sb.value_changed.connect(func(new_val):
			var current = obj.get(prop_name)
			var next: Vector3 = current if current is Vector3 else Vector3.ZERO
			if this_axis == "x":
				next.x = new_val
			elif this_axis == "y":
				next.y = new_val
			else:
				next.z = new_val
			_on_value_changed(obj, prop_name, next)
		)
		hbc.add_child(sb)
	return hbc

func _infer_array_mode(prop_name: String, prop: Dictionary, arr_val: Array) -> String:
	var hint = str(prop.get("hint_string", "")).to_lower()
	var hint_prefix = hint
	if hint.find(":") != -1:
		hint_prefix = hint.split(":")[0]
	if hint.find("packedscene") != -1 or prop_name == "scene_variants":
		return "packedscene"
	if hint.find("vector3") != -1 or prop_name in ["offsets", "rotations", "sizes"]:
		return "vector3"
	if hint.find("float") != -1 or prop_name == "scene_variant_weights":
		return "float"
	if hint.find("string") != -1 or prop_name == "labels":
		return "string"
	if hint_prefix == "9":
		return "vector3"
	if hint_prefix == "4":
		return "string"
	if hint_prefix == "3":
		return "float"
	if arr_val.size() > 0:
		var first = arr_val[0]
		if first is PackedScene:
			return "packedscene"
		match typeof(first):
			TYPE_VECTOR3:
				return "vector3"
			TYPE_FLOAT:
				return "float"
			TYPE_STRING:
				return "string"
	return "string"

func _create_array_input(obj: Object, prop_name: String, arr_val: Array, prop: Dictionary) -> Control:
	var wrapper = VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 4)
	var mode = _infer_array_mode(prop_name, prop, arr_val)

	for idx in range(arr_val.size()):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var this_idx = idx

		match mode:
			"vector3":
				var vec_val = arr_val[this_idx]
				var vec: Vector3 = vec_val if vec_val is Vector3 else Vector3.ZERO
				for axis in ["x", "y", "z"]:
					var this_axis = axis
					var sb_axis = SpinBox.new()
					sb_axis.min_value = -999999.0
					sb_axis.max_value = 999999.0
					sb_axis.step = 0.01
					sb_axis.custom_minimum_size.x = 48
					sb_axis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					if axis == "x":
						sb_axis.value = vec.x
					elif axis == "y":
						sb_axis.value = vec.y
					else:
						sb_axis.value = vec.z
					sb_axis.value_changed.connect(func(new_val):
						var current_arr = obj.get(prop_name)
						var next: Array = current_arr.duplicate(true) if current_arr is Array else []
						var cur = next[this_idx]
						var next_vec: Vector3 = cur if cur is Vector3 else Vector3.ZERO
						if this_axis == "x":
							next_vec.x = new_val
						elif this_axis == "y":
							next_vec.y = new_val
						else:
							next_vec.z = new_val
						next[this_idx] = next_vec
						_on_value_changed(obj, prop_name, next)
					)
					row.add_child(sb_axis)
			"float":
				var sb = SpinBox.new()
				sb.min_value = -999999.0
				sb.max_value = 999999.0
				sb.step = 0.01
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sb.value = float(arr_val[this_idx])
				sb.value_changed.connect(func(new_val):
					var current_arr = obj.get(prop_name)
					var next: Array = current_arr.duplicate(true) if current_arr is Array else []
					next[this_idx] = new_val
					_on_value_changed(obj, prop_name, next)
				)
				row.add_child(sb)
			"packedscene":
				var lbl = Label.new()
				var res = arr_val[this_idx]
				lbl.text = FlowI18n.t("None") if res == null else res.resource_path.get_file()
				lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				lbl.clip_text = true
				lbl.add_theme_font_size_override("font_size", _scaled_font_size(11))
				row.add_child(lbl)
				var btn_pick = Button.new()
				btn_pick.text = "..."
				btn_pick.pressed.connect(func():
					_show_file_dialog_for_array_resource(obj, prop_name, this_idx, lbl, "packedscene")
				)
				row.add_child(btn_pick)
			_:
				var le = LineEdit.new()
				le.text = str(arr_val[this_idx])
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var sb_style := StyleBoxFlat.new()
				sb_style.bg_color = Color("111318")
				sb_style.set_corner_radius_all(3)
				sb_style.content_margin_left = 6
				sb_style.content_margin_right = 6
				le.add_theme_stylebox_override("normal", sb_style)
				le.text_submitted.connect(func(new_text):
					var current_arr = obj.get(prop_name)
					var next: Array = current_arr.duplicate(true) if current_arr is Array else []
					next[this_idx] = new_text
					_on_value_changed(obj, prop_name, next)
				)
				le.focus_exited.connect(func():
					var current_arr = obj.get(prop_name)
					var next: Array = current_arr.duplicate(true) if current_arr is Array else []
					if str(next[this_idx]) != le.text:
						next[this_idx] = le.text
						_on_value_changed(obj, prop_name, next)
				)
				row.add_child(le)

		var btn_remove = Button.new()
		btn_remove.text = "-"
		btn_remove.tooltip_text = FlowI18n.t("Remove item")
		btn_remove.pressed.connect(func():
			var current_arr = obj.get(prop_name)
			var next: Array = current_arr.duplicate(true) if current_arr is Array else []
			if this_idx >= 0 and this_idx < next.size():
				next.remove_at(this_idx)
				_on_value_changed(obj, prop_name, next)
			edit(current_node)
		)
		row.add_child(btn_remove)
		wrapper.add_child(row)

	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	var add_btn = Button.new()
	add_btn.text = "+ " + FlowI18n.t("Add")
	add_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_btn.pressed.connect(func():
		var current_arr = obj.get(prop_name)
		var next: Array = current_arr.duplicate(true) if current_arr is Array else []
		match mode:
			"vector3":
				next.append(Vector3.ZERO)
			"float":
				next.append(1.0)
			"packedscene":
				next.append(null)
			_:
				next.append("")
		_on_value_changed(obj, prop_name, next)
		edit(current_node)
	)
	add_row.add_child(add_btn)
	wrapper.add_child(add_row)

	return wrapper

func _create_dictionary_input(obj: Object, prop_name: String, dict_val: Dictionary) -> Control:
	var wrapper = VBoxContainer.new()
	wrapper.add_theme_constant_override("separation", 4)

	for key in dict_val.keys():
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var key_le = LineEdit.new()
		key_le.text = str(key)
		key_le.custom_minimum_size.x = 80
		key_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_le)

		var value_le = LineEdit.new()
		value_le.text = str(dict_val[key])
		value_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value_le)

		var btn_remove = Button.new()
		btn_remove.text = "-"
		btn_remove.tooltip_text = FlowI18n.t("Remove entry")
		var original_key = key
		btn_remove.pressed.connect(func():
			var current_dict = obj.get(prop_name)
			var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
			if next.has(original_key):
				next.erase(original_key)
				_on_value_changed(obj, prop_name, next)
			edit(current_node)
		)
		row.add_child(btn_remove)

		key_le.focus_exited.connect(func():
			var current_dict = obj.get(prop_name)
			var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
			var new_key = key_le.text.strip_edges()
			if new_key == "":
				key_le.text = str(original_key)
				return
			var current_val = next[original_key] if next.has(original_key) else value_le.text
			if new_key != str(original_key):
				next.erase(original_key)
				next[new_key] = current_val
				_on_value_changed(obj, prop_name, next)
				edit(current_node)
		)

		value_le.focus_exited.connect(func():
			var current_dict = obj.get(prop_name)
			var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
			var target_key = key_le.text.strip_edges()
			if target_key == "":
				target_key = str(original_key)
			next[target_key] = value_le.text
			_on_value_changed(obj, prop_name, next)
		)

		wrapper.add_child(row)

	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 4)
	var add_key = LineEdit.new()
	add_key.placeholder_text = FlowI18n.t("key")
	add_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add_key)
	var add_value = LineEdit.new()
	add_value.placeholder_text = FlowI18n.t("value")
	add_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(add_value)
	var add_btn = Button.new()
	add_btn.text = "+"
	add_btn.pressed.connect(func():
		var key = add_key.text.strip_edges()
		if key == "":
			return
		var current_dict = obj.get(prop_name)
		var next: Dictionary = current_dict.duplicate(true) if current_dict is Dictionary else {}
		next[key] = add_value.text
		_on_value_changed(obj, prop_name, next)
		edit(current_node)
	)
	add_row.add_child(add_btn)
	wrapper.add_child(add_row)

	return wrapper

func _on_value_changed(obj: Object, prop_name: String, new_val):
	obj.set(prop_name, new_val)
	if obj is Resource:
		obj.emit_changed()
	property_edited.emit(prop_name)

func _show_file_dialog_for_property(obj: Object, prop_name: String, label: Label, prop: Dictionary = {}):
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	var hint = str(prop.get("hint_string", "")).to_lower()
	if hint.find("packedscene") != -1 or prop_name.find("scene") != -1:
		fd.add_filter("*.tscn,*.scn", "Scene Files")
		fd.add_filter("*.tres,*.res", "Resource Files")
	else:
		fd.add_filter("*.tres,*.res", "Resource Files")
		fd.add_filter("*.tscn,*.scn", "Scene Files")
	fd.file_selected.connect(func(path):
		var res = load(path)
		if res:
			_on_value_changed(obj, prop_name, res)
			label.text = path.get_file()
		fd.queue_free()
	)
	fd.canceled.connect(func():
		fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered_ratio(0.4)

func _show_file_dialog_for_array_resource(obj: Object, prop_name: String, index: int, label: Label, mode: String):
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	if mode == "packedscene":
		fd.add_filter("*.tscn,*.scn", "Scene Files")
	else:
		fd.add_filter("*.tres,*.res", "Resource Files")
	fd.file_selected.connect(func(path):
		var res = load(path)
		if res:
			var current_arr = obj.get(prop_name)
			var next: Array = current_arr.duplicate(true) if current_arr is Array else []
			if index >= 0 and index < next.size():
				next[index] = res
				_on_value_changed(obj, prop_name, next)
				label.text = path.get_file()
		fd.queue_free()
	)
	fd.canceled.connect(func():
		fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered_ratio(0.4)

func _format_label(name: String) -> String:
	var words = name.replace("_", " ").split(" ")
	for i in range(words.size()):
		words[i] = words[i].capitalize()
	return " ".join(words)

func _create_separator_stylebox() -> StyleBoxLine:
	var sbl = StyleBoxLine.new()
	sbl.color = Color("252836")
	sbl.thickness = 1
	return sbl

func _create_graph_parameter_panel(res: FlowGraphResource, params: Array, param: GraphInputParameter, idx: int, prop_name: String, include_value: bool) -> PanelContainer:
	var param_panel = PanelContainer.new()
	var p_style = StyleBoxFlat.new()
	p_style.bg_color = Color("252836")
	p_style.set_corner_radius_all(6)
	p_style.content_margin_left = 8
	p_style.content_margin_right = 8
	p_style.content_margin_top = 6
	p_style.content_margin_bottom = 6
	param_panel.add_theme_stylebox_override("panel", p_style)

	var row = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	param_panel.add_child(row)

	var le_name = LineEdit.new()
	le_name.text = param.name
	le_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le_name.add_theme_font_size_override("font_size", 11)
	_style_parameter_line_edit(le_name)
	le_name.text_submitted.connect(func(new_text):
		_update_graph_parameter_name(res, param, prop_name, le_name, new_text)
	)
	le_name.focus_exited.connect(func():
		_update_graph_parameter_name(res, param, prop_name, le_name, le_name.text)
	)
	row.add_child(le_name)

	row.add_child(_create_graph_parameter_type_button(res, param, prop_name))

	if include_value:
		var val_ctrl = _create_graph_parameter_value_control(res, param, prop_name)
		if val_ctrl:
			val_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(val_ctrl)

	var btn_del = Button.new()
	btn_del.text = "X"
	btn_del.flat = true
	btn_del.custom_minimum_size.x = 24
	btn_del.add_theme_color_override("font_color", Color("ef4444"))
	btn_del.pressed.connect(func():
		params.remove_at(idx)
		res.emit_changed()
		property_edited.emit(prop_name)
		edit(res)
	)
	row.add_child(btn_del)

	return param_panel

func _style_parameter_line_edit(line_edit: LineEdit):
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("111318")
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	line_edit.add_theme_stylebox_override("normal", sb)

func _update_graph_parameter_name(res: FlowGraphResource, param: GraphInputParameter, prop_name: String, line_edit: LineEdit, new_text: String):
	if param.name == new_text:
		return
	param.name = new_text
	param.emit_changed()
	res.emit_changed()
	property_edited.emit(prop_name)
	line_edit.text = new_text

func _create_graph_parameter_type_button(res: FlowGraphResource, param: GraphInputParameter, prop_name: String) -> OptionButton:
	var opt_type = OptionButton.new()
	opt_type.custom_minimum_size.x = 82
	opt_type.size_flags_horizontal = Control.SIZE_FILL
	opt_type.add_theme_font_size_override("font_size", 10)

	var types_to_show = [
		FlowData.DataType.Bool,
		FlowData.DataType.Int,
		FlowData.DataType.Float,
		FlowData.DataType.Vector,
		FlowData.DataType.String,
		FlowData.DataType.Resource
	]
	for t_idx in range(types_to_show.size()):
		var t_val = types_to_show[t_idx]
		var t_name = FlowData.DataType.keys()[t_val]
		opt_type.add_item(FlowI18n.t(t_name), t_val)
		if param.data_type == t_val:
			opt_type.selected = t_idx

	opt_type.get_popup().min_size = Vector2i(180, 0)
	_style_parameter_type_button(opt_type, param.data_type)
	opt_type.item_selected.connect(func(id_index):
		var new_type = opt_type.get_item_id(id_index)
		param.data_type = new_type
		param.emit_changed()
		res.emit_changed()
		property_edited.emit(prop_name)
		edit(res)
	)
	return opt_type

func _style_parameter_type_button(opt_type: OptionButton, data_type: FlowData.DataType):
	var type_color := FlowNodeBase.getColorForFlowDataType(data_type)
	var normal := StyleBoxFlat.new()
	normal.bg_color = type_color.darkened(0.45)
	normal.set_border_width_all(1)
	normal.border_color = type_color.darkened(0.05)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	opt_type.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = type_color.darkened(0.32)
	opt_type.add_theme_stylebox_override("hover", hover)
	opt_type.add_theme_stylebox_override("pressed", hover)
	opt_type.add_theme_color_override("font_color", Color.WHITE)
	opt_type.add_theme_color_override("font_hover_color", Color.WHITE)
	opt_type.add_theme_color_override("font_pressed_color", Color.WHITE)

func _create_graph_parameter_value_control(res: FlowGraphResource, param: GraphInputParameter, prop_name: String) -> Control:
	match param.data_type:
		FlowData.DataType.Bool:
			var checkbox = CheckBox.new()
			checkbox.button_pressed = param.cte_bool
			checkbox.toggled.connect(func(pressed):
				param.cte_bool = pressed
				_emit_graph_parameter_changed(res, param, prop_name)
			)
			return checkbox
		FlowData.DataType.Int:
			var spin_int = SpinBox.new()
			spin_int.min_value = -999999
			spin_int.max_value = 999999
			spin_int.step = 1
			spin_int.value = param.cte_int
			spin_int.value_changed.connect(func(new_val):
				param.cte_int = int(new_val)
				_emit_graph_parameter_changed(res, param, prop_name)
			)
			return spin_int
		FlowData.DataType.Float:
			var spin_float = SpinBox.new()
			spin_float.min_value = -999999.0
			spin_float.max_value = 999999.0
			spin_float.step = 0.01
			spin_float.value = param.cte_float
			spin_float.value_changed.connect(func(new_val):
				param.cte_float = new_val
				_emit_graph_parameter_changed(res, param, prop_name)
			)
			return spin_float
		FlowData.DataType.Vector:
			var vec_hbox = HBoxContainer.new()
			vec_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for axis in ["x", "y", "z"]:
				var sb_axis = SpinBox.new()
				sb_axis.min_value = -999999.0
				sb_axis.max_value = 999999.0
				sb_axis.step = 0.01
				sb_axis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if axis == "x":
					sb_axis.value = param.cte_vector.x
					sb_axis.value_changed.connect(func(nv):
						param.cte_vector.x = nv
						_emit_graph_parameter_changed(res, param, prop_name)
					)
				elif axis == "y":
					sb_axis.value = param.cte_vector.y
					sb_axis.value_changed.connect(func(nv):
						param.cte_vector.y = nv
						_emit_graph_parameter_changed(res, param, prop_name)
					)
				else:
					sb_axis.value = param.cte_vector.z
					sb_axis.value_changed.connect(func(nv):
						param.cte_vector.z = nv
						_emit_graph_parameter_changed(res, param, prop_name)
					)
				vec_hbox.add_child(sb_axis)
			return vec_hbox
		FlowData.DataType.String:
			var line_edit = LineEdit.new()
			line_edit.text = param.cte_string
			_style_parameter_line_edit(line_edit)
			line_edit.text_submitted.connect(func(new_text):
				param.cte_string = new_text
				_emit_graph_parameter_changed(res, param, prop_name)
			)
			line_edit.focus_exited.connect(func():
				if param.cte_string != line_edit.text:
					param.cte_string = line_edit.text
					_emit_graph_parameter_changed(res, param, prop_name)
			)
			return line_edit
		FlowData.DataType.Resource:
			var res_hbox = HBoxContainer.new()
			var res_lbl = Label.new()
			res_lbl.text = FlowI18n.t("None") if param.cte_resource == null else param.cte_resource.resource_path.get_file()
			res_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			res_lbl.clip_text = true
			res_lbl.add_theme_font_size_override("font_size", 11)
			res_hbox.add_child(res_lbl)

			var res_btn = Button.new()
			res_btn.text = "..."
			res_btn.pressed.connect(func():
				_show_file_dialog_for_param_resource(param, res_lbl, res, prop_name)
			)
			res_hbox.add_child(res_btn)
			return res_hbox
	return null

func _emit_graph_parameter_changed(res: FlowGraphResource, param: GraphInputParameter, prop_name: String):
	param.emit_changed()
	res.emit_changed()
	property_edited.emit(GRAPH_PARAMETER_VALUE_EDITED)

func _populate_graph_resource_properties(res: FlowGraphResource):
	_add_header(FlowI18n.t("Graph Inputs"), res.resource_path.get_file() if res.resource_path != "" else FlowI18n.t("Unsaved Resource"))

	# Inputs list
	var list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 12)
	content_vbox.add_child(list_box)

	for idx in range(res.in_params.size()):
		var param = res.in_params[idx]
		if not param:
			continue

		list_box.add_child(_create_graph_parameter_panel(res, res.in_params, param, idx, "in_params", true))

	# Add Parameter Button
	var btn_add = Button.new()
	btn_add.text = "+ " + FlowI18n.t("Add Parameter")
	btn_add.add_theme_color_override("font_color", Color("22d3ee")) # Cyan
	btn_add.pressed.connect(func():
		var new_param = GraphInputParameter.new()
		new_param.name = "new_param_%d" % (res.in_params.size() + 1)
		new_param.data_type = FlowData.DataType.Float
		res.in_params.append(new_param)
		res.emit_changed()
		property_edited.emit("in_params")
		edit(res) # refresh
	)
	content_vbox.add_child(btn_add)

func _show_file_dialog_for_param_resource(param: GraphInputParameter, label: Label, parent_res: FlowGraphResource, prop_name: String):
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	fd.file_selected.connect(func(path):
		var loaded_res = load(path)
		if loaded_res:
			param.cte_resource = loaded_res
			param.emit_changed()
			parent_res.emit_changed()
			property_edited.emit(GRAPH_PARAMETER_VALUE_EDITED)
			label.text = path.get_file()
		fd.queue_free()
	)
	fd.canceled.connect(func():
		fd.queue_free()
	)
	add_child(fd)
	fd.popup_centered_ratio(0.4)

func _populate_graph_resource_outputs(res: FlowGraphResource):
	_add_header(FlowI18n.t("Graph Outputs"), res.resource_path.get_file() if res.resource_path != "" else FlowI18n.t("Unsaved Resource"))

	# Outputs list
	var list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 12)
	content_vbox.add_child(list_box)

	for idx in range(res.out_params.size()):
		var param = res.out_params[idx]
		if not param:
			continue

		list_box.add_child(_create_graph_parameter_panel(res, res.out_params, param, idx, "out_params", false))

	# Add Parameter Button
	var btn_add = Button.new()
	btn_add.text = "+ " + FlowI18n.t("Add Parameter")
	btn_add.add_theme_color_override("font_color", Color("22d3ee")) # Cyan
	btn_add.pressed.connect(func():
		var new_param = GraphInputParameter.new()
		new_param.name = "new_out_%d" % (res.out_params.size() + 1)
		new_param.data_type = FlowData.DataType.Float
		res.out_params.append(new_param)
		res.emit_changed()
		property_edited.emit("out_params")
		edit(res) # refresh
	)
	content_vbox.add_child(btn_add)

func _populate_generic_resource_properties(res: Resource):
	_add_header(res.resource_path.get_file() if res.resource_path != "" else res.get_class(), res.get_class())

	var prop_box = VBoxContainer.new()
	prop_box.add_theme_constant_override("separation", 10)
	content_vbox.add_child(prop_box)

	var props = res.get_property_list()
	for prop in props:
		if prop.name in ["resource_local_to_scene", "resource_path", "resource_name", "script"]:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue

		var ctrl = _create_control_for_property(res, prop)
		if ctrl:
			prop_box.add_child(_create_row(_localized_property_label(prop.name), ctrl))
