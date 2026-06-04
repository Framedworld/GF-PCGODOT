@tool
extends EditorInspectorPlugin
class_name FlowNodesInspectorPlugin

const DEFAULT_EDITOR_META := &"_flow_creating_default_editor"
const EDITOR_SETTING_HIDE_RESOURCE_BUILTIN_ROWS := "addons/flow_nodes_editor/hide_resource_builtin_rows"
const HIDDEN_RESOURCE_PROPERTIES := {
	"resource_local_to_scene": true,
	"resource_path": true,
	"resource_scene_unique_id": true,
	"resource_name": true,
	"script": true,
}

func _can_handle(object):
	if _is_creating_default_editor(object):
		return false
	return object is NodeSettings or object is FlowGraphResource or _is_flow_editor_settings_proxy(object)

func _parse_property(object, type, name, hint_type, hint_string, usage_flags, wide):
	if _is_flow_editor_settings_proxy(object):
		return _parse_flow_editor_setting_property(object, type, name, hint_type, hint_string, usage_flags, wide)

	var graph_resource := object as FlowGraphResource
	if graph_resource != null:
		return _parse_flow_graph_resource_property(object, type, name, hint_type, hint_string, usage_flags, wide)

	var settings : NodeSettings = object as NodeSettings
	if settings != null:
		if _should_hide_resource_builtin_rows() and _is_hidden_resource_property(name):
			return true
		if not settings.exposeParam(name):
			return true
		return _add_localized_property_editor(
			object,
			type,
			name,
			hint_type,
			hint_string,
			usage_flags,
			wide,
			FlowI18n.tn(_format_label(name))
		)
	return false

func _parse_flow_editor_setting_property(
	object: Object,
	type,
	name: String,
	hint_type,
	hint_string: String,
	usage_flags,
	wide: bool,
) -> bool:
	if not object.has_method("get_flow_editor_setting_label"):
		return false
	if object.has_method("has_flow_editor_setting_property") and not bool(object.call("has_flow_editor_setting_property", name)):
		return true
	var label := String(object.call("get_flow_editor_setting_label", name))
	return _add_localized_property_editor(object, type, name, hint_type, hint_string, usage_flags, wide, label)

func _parse_flow_graph_resource_property(
	object: Object,
	type,
	name: String,
	hint_type,
	hint_string: String,
	usage_flags,
	wide: bool,
) -> bool:
	var graph_resource := object as FlowGraphResource
	if graph_resource == null:
		return false
	var label := ""
	if _should_hide_resource_builtin_rows() and _is_hidden_resource_property(name):
		return true
	match name:
		"in_params":
			add_custom_control(_make_graph_parameters_control(
				graph_resource,
				"in_params",
				FlowI18n.t("Graph Inputs"),
				true
			))
			return true
		"out_params":
			add_custom_control(_make_graph_parameters_control(
				graph_resource,
				"out_params",
				FlowI18n.t("Graph Outputs"),
				false
			))
			return true
		_:
			label = FlowI18n.t(_format_label(name))
	return _add_localized_property_editor(object, type, name, hint_type, hint_string, usage_flags, wide, label)

func _make_graph_parameters_control(
	res: FlowGraphResource,
	prop_name: String,
	title: String,
	include_value: bool,
) -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", 12)
	root.add_child(header)

	var list_box := VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	root.add_child(list_box)
	_populate_graph_parameter_list(list_box, res, prop_name, include_value)

	var add_button := Button.new()
	add_button.text = "+ " + FlowI18n.t("Add Parameter")
	add_button.add_theme_color_override("font_color", Color("22d3ee"))
	add_button.pressed.connect(func():
		var params := _graph_parameter_array(res, prop_name)
		var param := GraphInputParameter.new()
		param.name = _unique_graph_parameter_name(params, "new_param" if prop_name == "in_params" else "new_out")
		param.data_type = FlowData.DataType.Float
		params.append(param)
		_assign_graph_parameter_array(res, prop_name, params)
		_emit_graph_parameter_changed(res, prop_name)
		_populate_graph_parameter_list(list_box, res, prop_name, include_value)
	)
	root.add_child(add_button)

	return root

func _populate_graph_parameter_list(
	list_box: VBoxContainer,
	res: FlowGraphResource,
	prop_name: String,
	include_value: bool,
) -> void:
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()

	var params := _graph_parameter_array(res, prop_name)
	for index in range(params.size()):
		var param := params[index] as GraphInputParameter
		if param == null:
			continue
		list_box.add_child(_make_graph_parameter_row(
			list_box,
			res,
			prop_name,
			param,
			index,
			include_value
		))

func _make_graph_parameter_row(
	list_box: VBoxContainer,
	res: FlowGraphResource,
	prop_name: String,
	param: GraphInputParameter,
	index: int,
	include_value: bool,
) -> Control:
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("252836")
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", panel_style)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var name_edit := LineEdit.new()
	name_edit.text = param.name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", 11)
	_style_parameter_line_edit(name_edit)
	name_edit.text_submitted.connect(func(new_text: String):
		_set_graph_parameter_name(res, prop_name, param, name_edit, new_text)
	)
	name_edit.focus_exited.connect(func():
		_set_graph_parameter_name(res, prop_name, param, name_edit, name_edit.text)
	)
	row.add_child(name_edit)

	row.add_child(_make_graph_parameter_type_button(list_box, res, prop_name, param, include_value))

	if include_value:
		var value_control := _make_graph_parameter_value_control(res, prop_name, param)
		if value_control != null:
			value_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(value_control)

	var delete_button := Button.new()
	delete_button.text = "X"
	delete_button.flat = true
	delete_button.custom_minimum_size.x = 24
	delete_button.add_theme_color_override("font_color", Color("ef4444"))
	delete_button.pressed.connect(func():
		var params := _graph_parameter_array(res, prop_name)
		if index >= 0 and index < params.size():
			params.remove_at(index)
			_assign_graph_parameter_array(res, prop_name, params)
			_emit_graph_parameter_changed(res, prop_name)
			_populate_graph_parameter_list(list_box, res, prop_name, include_value)
	)
	row.add_child(delete_button)

	return panel

func _make_graph_parameter_type_button(
	list_box: VBoxContainer,
	res: FlowGraphResource,
	prop_name: String,
	param: GraphInputParameter,
	include_value: bool,
) -> OptionButton:
	var type_button := OptionButton.new()
	type_button.custom_minimum_size.x = 82
	type_button.add_theme_font_size_override("font_size", 10)

	var types_to_show := [
		FlowData.DataType.Bool,
		FlowData.DataType.Int,
		FlowData.DataType.Float,
		FlowData.DataType.Vector,
		FlowData.DataType.String,
		FlowData.DataType.Resource,
	]
	for item_index in range(types_to_show.size()):
		var type_value = types_to_show[item_index]
		type_button.add_item(FlowI18n.t(FlowData.DataType.keys()[type_value]), type_value)
		if param.data_type == type_value:
			type_button.selected = item_index

	_style_parameter_type_button(type_button, param.data_type)
	type_button.item_selected.connect(func(selected_index: int):
		param.data_type = type_button.get_item_id(selected_index)
		_emit_graph_parameter_changed(res, prop_name, param, true)
		_populate_graph_parameter_list(list_box, res, prop_name, include_value)
	)
	return type_button

func _make_graph_parameter_value_control(
	res: FlowGraphResource,
	prop_name: String,
	param: GraphInputParameter,
) -> Control:
	match param.data_type:
		FlowData.DataType.Bool:
			var checkbox := CheckBox.new()
			checkbox.button_pressed = param.cte_bool
			checkbox.toggled.connect(func(pressed: bool):
				param.cte_bool = pressed
				_emit_graph_parameter_changed(res, prop_name, param)
			)
			return checkbox
		FlowData.DataType.Int:
			var spin_int := SpinBox.new()
			spin_int.min_value = -999999
			spin_int.max_value = 999999
			spin_int.step = 1
			spin_int.value = param.cte_int
			spin_int.value_changed.connect(func(new_value: float):
				param.cte_int = int(new_value)
				_emit_graph_parameter_changed(res, prop_name, param)
			)
			return spin_int
		FlowData.DataType.Float:
			var spin_float := SpinBox.new()
			spin_float.min_value = -999999.0
			spin_float.max_value = 999999.0
			spin_float.step = 0.01
			spin_float.value = param.cte_float
			spin_float.value_changed.connect(func(new_value: float):
				param.cte_float = new_value
				_emit_graph_parameter_changed(res, prop_name, param)
			)
			return spin_float
		FlowData.DataType.Vector:
			return _make_graph_parameter_vector_control(res, prop_name, param)
		FlowData.DataType.String:
			var text_edit := LineEdit.new()
			text_edit.text = param.cte_string
			_style_parameter_line_edit(text_edit)
			text_edit.text_submitted.connect(func(new_text: String):
				param.cte_string = new_text
				_emit_graph_parameter_changed(res, prop_name, param)
			)
			text_edit.focus_exited.connect(func():
				if param.cte_string != text_edit.text:
					param.cte_string = text_edit.text
					_emit_graph_parameter_changed(res, prop_name, param)
			)
			return text_edit
		FlowData.DataType.Resource:
			return _make_graph_parameter_resource_control(res, prop_name, param)
	return null

func _make_graph_parameter_vector_control(
	res: FlowGraphResource,
	prop_name: String,
	param: GraphInputParameter,
) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for axis in ["x", "y", "z"]:
		var spin := SpinBox.new()
		spin.min_value = -999999.0
		spin.max_value = 999999.0
		spin.step = 0.01
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		match axis:
			"x":
				spin.value = param.cte_vector.x
			"y":
				spin.value = param.cte_vector.y
			"z":
				spin.value = param.cte_vector.z
		spin.value_changed.connect(func(new_value: float):
			match axis:
				"x":
					param.cte_vector.x = new_value
				"y":
					param.cte_vector.y = new_value
				"z":
					param.cte_vector.z = new_value
			_emit_graph_parameter_changed(res, prop_name, param)
		)
		row.add_child(spin)
	return row

func _make_graph_parameter_resource_control(
	res: FlowGraphResource,
	prop_name: String,
	param: GraphInputParameter,
) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = FlowI18n.t("None") if param.cte_resource == null else param.cte_resource.resource_path.get_file()
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var button := Button.new()
	button.text = "..."
	button.pressed.connect(func():
		_show_graph_parameter_resource_dialog(res, prop_name, param, label)
	)
	row.add_child(button)
	return row

func _show_graph_parameter_resource_dialog(
	res: FlowGraphResource,
	prop_name: String,
	param: GraphInputParameter,
	label: Label,
) -> void:
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.file_selected.connect(func(path: String):
		var loaded = load(path)
		if loaded is Resource:
			param.cte_resource = loaded
			label.text = path.get_file()
			_emit_graph_parameter_changed(res, prop_name, param)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	base_control.add_child(dialog)
	dialog.popup_centered_ratio(0.4)

func _set_graph_parameter_name(
	res: FlowGraphResource,
	prop_name: String,
	param: GraphInputParameter,
	name_edit: LineEdit,
	new_text: String,
) -> void:
	var next_name := new_text.strip_edges()
	if next_name.is_empty():
		next_name = param.name
	if param.name == next_name:
		name_edit.text = next_name
		return
	param.name = next_name
	name_edit.text = next_name
	_emit_graph_parameter_changed(res, prop_name, param, true)

func _graph_parameter_array(res: FlowGraphResource, prop_name: String) -> Array:
	if prop_name == "out_params":
		return res.out_params.duplicate()
	return res.in_params.duplicate()

func _assign_graph_parameter_array(res: FlowGraphResource, prop_name: String, params: Array) -> void:
	if prop_name == "out_params":
		var output_params: Array[GraphInputParameter] = []
		for param in params:
			if param is GraphInputParameter:
				output_params.append(param)
		res.out_params = output_params
		return
	var input_params: Array[GraphInputParameter] = []
	for param in params:
		if param is GraphInputParameter:
			input_params.append(param)
	res.in_params = input_params

func _emit_graph_parameter_changed(
	res: FlowGraphResource,
	_prop_name: String,
	param: GraphInputParameter = null,
	structural: bool = false,
) -> void:
	if param != null:
		param.emit_changed()
	res.emit_changed()
	if structural:
		res._queue_in_params_changed()

func _unique_graph_parameter_name(params: Array, base_name: String) -> String:
	var used := {}
	for param in params:
		if param is GraphInputParameter:
			used[param.name] = true
	var index := params.size() + 1
	var candidate := "%s_%d" % [base_name, index]
	while used.has(candidate):
		index += 1
		candidate = "%s_%d" % [base_name, index]
	return candidate

func _style_parameter_line_edit(line_edit: LineEdit) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111318")
	style.set_corner_radius_all(3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	line_edit.add_theme_stylebox_override("normal", style)

func _style_parameter_type_button(type_button: OptionButton, data_type: FlowData.DataType) -> void:
	var type_color := FlowNodeBase.getColorForFlowDataType(data_type)
	var normal := StyleBoxFlat.new()
	normal.bg_color = type_color.darkened(0.45)
	normal.set_border_width_all(1)
	normal.border_color = type_color.darkened(0.05)
	normal.set_corner_radius_all(3)
	normal.content_margin_left = 6
	normal.content_margin_right = 6
	type_button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = type_color.darkened(0.32)
	type_button.add_theme_stylebox_override("hover", hover)
	type_button.add_theme_stylebox_override("pressed", hover)
	type_button.add_theme_color_override("font_color", Color.WHITE)
	type_button.add_theme_color_override("font_hover_color", Color.WHITE)
	type_button.add_theme_color_override("font_pressed_color", Color.WHITE)

func _add_localized_property_editor(
	object: Object,
	type,
	name: String,
	hint_type,
	hint_string: String,
	usage_flags,
	wide: bool,
	label: String,
) -> bool:
	if object != null:
		object.set_meta(DEFAULT_EDITOR_META, true)
	var editor := EditorInspector.instantiate_property_editor(
		object,
		type,
		name,
		hint_type,
		hint_string,
		usage_flags,
		wide
	)
	if object != null and object.has_meta(DEFAULT_EDITOR_META):
		object.remove_meta(DEFAULT_EDITOR_META)
	if editor == null:
		return false
	add_property_editor(name, editor, false, label)
	return true

func _is_flow_editor_settings_proxy(object: Object) -> bool:
	return object != null and object.has_method("is_flow_editor_settings_proxy") and bool(object.call("is_flow_editor_settings_proxy"))

func _is_creating_default_editor(object: Object) -> bool:
	return object != null and object.has_meta(DEFAULT_EDITOR_META)

func _is_hidden_resource_property(property_name: String) -> bool:
	return HIDDEN_RESOURCE_PROPERTIES.has(property_name)

func _should_hide_resource_builtin_rows() -> bool:
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings == null:
		return true
	if not editor_settings.has_setting(EDITOR_SETTING_HIDE_RESOURCE_BUILTIN_ROWS):
		return true
	return bool(editor_settings.get_setting(EDITOR_SETTING_HIDE_RESOURCE_BUILTIN_ROWS))

func _format_label(property_name: String) -> String:
	return property_name.capitalize()
