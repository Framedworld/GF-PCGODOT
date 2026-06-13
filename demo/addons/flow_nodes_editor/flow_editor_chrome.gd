@tool
class_name FlowEditorChrome
extends RefCounted

## Toolbar + tab row (styles, signals, i18n). Does not touch graph / comment code.

const INITIALIZED_META := &"flow_editor_chrome_initialized"
const TOOLBAR_ICON_BY_NAME := {
	"ButtonSave": "Save",
	"ButtonBrowse": "ShowInFileSystem",
	"ButtonReload": "Reload",
	"ButtonAnalyze": "PackedDataContainer",
	"ButtonRegenerate": "RandomNumberGenerator",
	"ButtonArrange": "Sort",
	"ButtonMinimap": "GridMinimap",
	"ButtonInputs": "GraphEdit",
	"ButtonSettings": "Tools",
}

const TOOLBAR_TOOLTIP_BY_NAME := {
	"ButtonSave": "Save the current FlowGraph resource",
	"ButtonBrowse": "Reveal the saved graph resource in the FileSystem dock",
	"ButtonReload": "Reload the current FlowGraph resource",
	"ButtonAnalyze": "Inspect selected node raw data (A)",
	"ButtonRegenerate": "Regenerate the graph output",
	"ButtonArrange": "Automatically arrange selected nodes.",
	"ButtonMinimap": "Toggle the graph minimap.",
	"ButtonInputs": "Edit graph inputs",
	"ButtonSettings": "Open Flow editor settings",
}


class Refs:
	var host: Control
	var tab_bar: TabBar
	var toolbar_hbox: HBoxContainer
	var graph_edit: GraphEdit
	var open_graph_button: Button
	var expand_graph_button: Button

	func is_valid() -> bool:
		return host != null and tab_bar != null and toolbar_hbox != null


static func is_valid_layout(host: Control) -> bool:
	return host.has_node("VBoxContainer/TabBarPanel/TabBarRow/TabBar")


static func clear_initialized(host: Control) -> void:
	if host.has_meta(INITIALIZED_META):
		host.remove_meta(INITIALIZED_META)


static func _is_editing_host_scene(refs: Refs) -> bool:
	if not Engine.is_editor_hint() or refs.host == null:
		return false
	var tree := refs.host.get_tree()
	if tree == null:
		return false
	return tree.edited_scene_root == refs.host


static func setup(refs: Refs) -> void:
	if not refs.is_valid():
		return
	if refs.host.has_meta(INITIALIZED_META):
		_attach_toolbar_to_graph_menu(refs)
		connect_signals(refs)
		apply_styles(refs)
		apply_translations(refs)
		return
	_attach_toolbar_to_graph_menu(refs)
	connect_signals(refs)
	apply_styles(refs)
	apply_translations(refs)
	refs.host.set_meta(INITIALIZED_META, true)

static func _attach_toolbar_to_graph_menu(refs: Refs) -> void:
	if _is_editing_host_scene(refs):
		return
	if refs.graph_edit == null:
		return
	var graph_menu_hbox := refs.graph_edit.get_menu_hbox()
	if graph_menu_hbox == null:
		return
	var graph_menu_panel := graph_menu_hbox.get_parent() as PanelContainer
	if graph_menu_panel == null:
		return
	var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	refs.graph_edit.show_menu = true
	graph_menu_hbox.visible = false
	graph_menu_panel.visible = true
	graph_menu_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE, Control.PRESET_MODE_MINSIZE, int(10 * editor_scale))
	if refs.toolbar_hbox.get_parent() != graph_menu_panel:
		if refs.toolbar_hbox.get_parent() != null:
			refs.toolbar_hbox.get_parent().remove_child(refs.toolbar_hbox)
		graph_menu_panel.add_child(refs.toolbar_hbox)
	refs.toolbar_hbox.visible = true
	refs.toolbar_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refs.toolbar_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var old_toolbar_container := refs.host.get_node_or_null("VBoxContainer/ScrollContainer") as ScrollContainer
	if old_toolbar_container:
		old_toolbar_container.visible = false
		old_toolbar_container.custom_minimum_size = Vector2.ZERO
		old_toolbar_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


static func connect_signals(refs: Refs) -> void:
	var host := refs.host
	if refs.tab_bar:
		if not refs.tab_bar.tab_changed.is_connected(host._on_tab_changed):
			refs.tab_bar.tab_changed.connect(host._on_tab_changed)
		if not refs.tab_bar.tab_close_pressed.is_connected(host._on_tab_close_pressed):
			refs.tab_bar.tab_close_pressed.connect(host._on_tab_close_pressed)
	if refs.open_graph_button and not refs.open_graph_button.pressed.is_connected(host._on_button_open_pressed):
		refs.open_graph_button.pressed.connect(host._on_button_open_pressed)
	_connect_pressed(refs, "ButtonSave", host._on_button_save_pressed)
	_connect_pressed(refs, "ButtonBrowse", host._on_button_browse_pressed)
	_connect_pressed(refs, "ButtonReload", host._on_button_reload_pressed)
	_connect_pressed(refs, "ButtonAnalyze", host._on_button_analyze_pressed)
	_connect_pressed(refs, "ButtonRegenerate", host._on_button_regenerate_pressed)
	_connect_pressed(refs, "ButtonArrange", host._on_button_arrange_pressed)
	_connect_button_toggled(refs, "ButtonMinimap", host._on_button_minimap_toggled)
	_connect_pressed(refs, "ButtonInputs", host._on_button_inputs_pressed)
	_connect_pressed(refs, "ButtonSettings", host._on_button_settings_pressed)
	_connect_toggled(refs, "AutoRegen", host._on_auto_regen_toggled)
	_connect_toggled(refs, "CheckColorNodes", host._on_color_nodes_toggled)
	var inputs_button := refs.toolbar_hbox.get_node_or_null("ButtonInputs") as Button
	if inputs_button:
		inputs_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if refs.expand_graph_button and not refs.expand_graph_button.pressed.is_connected(host._on_button_expand_graph_pressed):
		refs.expand_graph_button.pressed.connect(host._on_button_expand_graph_pressed)


static func _connect_pressed(refs: Refs, node_name: String, callback: Callable) -> void:
	var button := refs.toolbar_hbox.get_node_or_null(node_name) as Button
	if button and not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


static func _connect_button_toggled(refs: Refs, node_name: String, callback: Callable) -> void:
	var button := refs.toolbar_hbox.get_node_or_null(node_name) as Button
	if button:
		button.toggle_mode = true
		if not button.toggled.is_connected(callback):
			button.toggled.connect(callback)


static func _connect_toggled(refs: Refs, node_name: String, callback: Callable) -> void:
	var checkbox := refs.toolbar_hbox.get_node_or_null(node_name) as CheckBox
	if checkbox and not checkbox.toggled.is_connected(callback):
		checkbox.toggled.connect(callback)


static func apply_styles(refs: Refs) -> void:
	if not refs.is_valid():
		return
	var editing_host_scene := _is_editing_host_scene(refs)
	if not editing_host_scene:
		_attach_toolbar_to_graph_menu(refs)
	var vbox := refs.host.get_node_or_null("VBoxContainer")
	if vbox == null:
		return
	var toolbar_container := vbox.get_node_or_null("ScrollContainer") as ScrollContainer
	if toolbar_container:
		toolbar_container.visible = editing_host_scene

static func apply_translations(refs: Refs) -> void:
	if not refs.is_valid():
		return
	FlowI18n.reload_locale_files()
	var text_by_name := {
		"AutoRegen": "Auto Generate",
		"CheckColorNodes": "Color Nodes",
	}
	for node_name in text_by_name:
		var control := _get_control(refs, node_name)
		if control is Button:
			(control as Button).text = FlowI18n.t(String(text_by_name[node_name]))
		elif control is Label:
			(control as Label).text = FlowI18n.t(String(text_by_name[node_name]))
	var tooltip_by_name := {
		"ButtonExpandGraph": "Float Graph Panel",
	}
	if refs.open_graph_button:
		refs.open_graph_button.text = ""
		refs.open_graph_button.tooltip_text = FlowI18n.t("Open a FlowGraph resource")
	if refs.expand_graph_button:
		refs.expand_graph_button.text = ""
		refs.expand_graph_button.tooltip_text = FlowI18n.t("Float Graph Panel")


static func _get_control(refs: Refs, node_name: String) -> Control:
	var control := refs.toolbar_hbox.get_node_or_null(node_name) as Control
	if control:
		return control
	if node_name == "ButtonOpenGraph" and refs.open_graph_button:
		return refs.open_graph_button
	if node_name == "ButtonExpandGraph" and refs.expand_graph_button:
		return refs.expand_graph_button
	return null


static func _style_toolbar_button(btn: Button) -> void:
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


static func _style_toolbar_icon_button(btn: Button, icon_name: String, graph_edit: GraphEdit = null) -> void:
	var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	btn.text = ""
	btn.theme_type_variation = "FlatButton"
	btn.focus_mode = Control.FOCUS_ACCESSIBILITY
	btn.custom_minimum_size = Vector2(34, 32) * editor_scale
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon = false
	if Engine.is_editor_hint():
		var editor_theme := EditorInterface.get_editor_theme()
		if icon_name.begins_with("GraphEdit:") and graph_edit != null:
			var graph_icon_name := icon_name.trim_prefix("GraphEdit:")
			btn.icon = graph_edit.get_theme_icon(graph_icon_name, "GraphEdit")
		elif editor_theme != null and editor_theme.has_icon(icon_name, "EditorIcons"):
			btn.icon = editor_theme.get_icon(icon_name, "EditorIcons")
	if btn.name == "ButtonRegenerate":
		_style_regenerate_button(btn)


static func _style_open_graph_button(btn: Button) -> void:
	var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	btn.text = ""
	btn.theme_type_variation = "FlatMenuButton"
	btn.focus_mode = Control.FOCUS_ACCESSIBILITY
	btn.custom_minimum_size = Vector2(28, 28) * editor_scale
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon = false
	if Engine.is_editor_hint():
		var editor_theme := EditorInterface.get_editor_theme()
		if editor_theme != null and editor_theme.has_icon("Load", "EditorIcons"):
			btn.icon = editor_theme.get_icon("Load", "EditorIcons")


static func _style_expand_graph_button(btn: Button) -> void:
	var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	btn.text = ""
	btn.theme_type_variation = "BottomPanelButton"
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(28, 28) * editor_scale
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.expand_icon = false
	if Engine.is_editor_hint():
		var editor_theme := EditorInterface.get_editor_theme()
		if editor_theme != null and editor_theme.has_icon("MakeFloating", "EditorIcons"):
			btn.icon = editor_theme.get_icon("MakeFloating", "EditorIcons")
		elif editor_theme != null and editor_theme.has_icon("ExpandBottomDock", "EditorIcons"):
			btn.icon = editor_theme.get_icon("ExpandBottomDock", "EditorIcons")


static func _style_regenerate_button(btn: Button) -> void:
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color("1b1e28")
	sb_normal.set_border_width_all(1)
	sb_normal.border_color = Color("22d3ee")
	sb_normal.set_corner_radius_all(3)
	sb_normal.content_margin_left = 10
	sb_normal.content_margin_right = 10
	sb_normal.content_margin_top = 4
	sb_normal.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sb_normal)
	var sb_hover := sb_normal.duplicate()
	sb_hover.bg_color = Color("252836")
	btn.add_theme_stylebox_override("hover", sb_hover)
	var sb_pressed := sb_normal.duplicate()
	sb_pressed.bg_color = Color("111318")
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_color_override("font_color", Color("22d3ee"))
	btn.add_theme_color_override("font_hover_color", Color("22d3ee"))
	btn.add_theme_color_override("font_pressed_color", Color("22d3ee"))


static func _style_graph_menu_toolbar(refs: Refs) -> void:
	if refs.graph_edit == null:
		return
	var graph_menu_hbox := refs.graph_edit.get_menu_hbox()
	if graph_menu_hbox == null:
		return
	var graph_menu_panel := graph_menu_hbox.get_parent() as PanelContainer
	if graph_menu_panel == null:
		return
	var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	var toolbar_panel_style := StyleBoxFlat.new()
	toolbar_panel_style.bg_color = Color(0.055, 0.06, 0.075, 0.82)
	toolbar_panel_style.set_border_width_all(1)
	toolbar_panel_style.border_color = Color(1.0, 1.0, 1.0, 0.08)
	toolbar_panel_style.set_corner_radius_all(int(4 * editor_scale))
	toolbar_panel_style.content_margin_left = 8 * editor_scale
	toolbar_panel_style.content_margin_right = 8 * editor_scale
	toolbar_panel_style.content_margin_top = 6 * editor_scale
	toolbar_panel_style.content_margin_bottom = 6 * editor_scale
	graph_menu_panel.add_theme_stylebox_override("panel", toolbar_panel_style)
	refs.toolbar_hbox.add_theme_constant_override("separation", int(4 * editor_scale))
