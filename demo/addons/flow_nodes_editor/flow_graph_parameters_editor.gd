@tool
extends VBoxContainer
class_name FlowGraphParametersEditor

signal property_edited(prop_name: String)

const GRAPH_PARAMETER_VALUE_EDITED := "_graph_parameter_value_edited"
const TYPE_BUTTON_MIN_WIDTH := 36.0
const NAME_MIN_WIDTH := 90.0
const REMOVE_BUTTON_MIN_WIDTH := 28.0

const PARAMETER_TYPES := [
	FlowData.DataType.Bool,
	FlowData.DataType.Int,
	FlowData.DataType.Float,
	FlowData.DataType.Vector,
	FlowData.DataType.String,
	FlowData.DataType.Resource,
	FlowData.DataType.Int64,
	FlowData.DataType.Double,
	FlowData.DataType.Vector2,
	FlowData.DataType.Vector4,
	FlowData.DataType.Quaternion,
	FlowData.DataType.Color,
	FlowData.DataType.Transform,
]

## Types whose value editor is too wide for the name row; it goes on its own
## row under the name, as Vector always did.
const WIDE_VALUE_TYPES := [
	FlowData.DataType.Vector,
	FlowData.DataType.Vector4,
	FlowData.DataType.Quaternion,
	FlowData.DataType.Transform,
]

var graph_resource: FlowGraphResource
var parameter_property := ""
var section_title := ""
var include_value := false
var list_box: VBoxContainer
var _list_refresh_queued := false
var _structural_property_edited_queued := false
var _pending_structural_property := ""


func setup(res: FlowGraphResource, prop_name: String, title: String, show_value: bool) -> void:
	graph_resource = res
	parameter_property = prop_name
	section_title = title
	include_value = show_value
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	if graph_resource == null:
		return

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(header)

	var title_label := Label.new()
	title_label.text = section_title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	var add_button := Button.new()
	add_button.text = FlowI18n.t("Add Parameter")
	add_button.tooltip_text = FlowI18n.t("Add Parameter")
	_apply_editor_icon(add_button, "Add")
	add_button.pressed.connect(_on_add_parameter_pressed)
	header.add_child(add_button)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 2)
	add_child(list_box)
	_populate_parameter_list()


func _populate_parameter_list() -> void:
	if list_box == null or not is_instance_valid(list_box):
		return
	for child in list_box.get_children():
		list_box.remove_child(child)
		child.queue_free()

	var params := _graph_parameter_array()
	for index in range(params.size()):
		var param := params[index] as GraphInputParameter
		if param == null:
			continue
		list_box.add_child(_make_parameter_row(param, index))


func _make_parameter_row(param: GraphInputParameter, index: int) -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 4)
	wrapper.add_child(row)

	var name_edit := LineEdit.new()
	name_edit.text = param.name
	name_edit.custom_minimum_size.x = NAME_MIN_WIDTH
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(new_text: String):
		_set_parameter_name(param, name_edit, new_text)
	)
	name_edit.focus_exited.connect(func():
		_set_parameter_name(param, name_edit, name_edit.text)
	)
	row.add_child(name_edit)

	row.add_child(_make_type_button(param))

	if include_value and not is_wide_value_type(param.data_type):
		var value_control := _make_value_control(param)
		if value_control != null:
			value_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(value_control)

	var remove_button := Button.new()
	remove_button.text = "-"
	remove_button.tooltip_text = FlowI18n.t("Remove item")
	remove_button.custom_minimum_size.x = REMOVE_BUTTON_MIN_WIDTH
	_apply_editor_icon(remove_button, "Remove", true)
	remove_button.pressed.connect(func():
		var params := _graph_parameter_array()
		if index >= 0 and index < params.size():
			params.remove_at(index)
			_assign_graph_parameter_array(params)
			_emit_parameter_changed(null, true)
			_queue_parameter_list_refresh()
	)
	row.add_child(remove_button)

	if include_value and is_wide_value_type(param.data_type):
		var vector_control := _make_value_control(param)
		if vector_control != null:
			vector_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			wrapper.add_child(vector_control)

	return wrapper


func _make_type_button(param: GraphInputParameter) -> OptionButton:
	var type_button := OptionButton.new()
	type_button.custom_minimum_size.x = TYPE_BUTTON_MIN_WIDTH
	type_button.flat = false
	type_button.fit_to_longest_item = false
	type_button.clip_text = true
	type_button.theme_type_variation = &"EditorInspectorButton"
	type_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	type_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	for item_index in range(PARAMETER_TYPES.size()):
		var type_value = PARAMETER_TYPES[item_index]
		var type_label := _type_label(type_value)
		type_button.add_icon_item(_make_type_swatch_icon(type_value), type_label, type_value)
		type_button.set_item_tooltip(item_index, type_label)
		if param.data_type == type_value:
			type_button.selected = item_index
	type_button.tooltip_text = _type_label(param.data_type)
	_style_type_button(type_button, param.data_type)

	type_button.item_selected.connect(func(selected_index: int):
		var selected_type := type_button.get_item_id(selected_index)
		type_button.tooltip_text = _type_label(selected_type)
		_style_type_button(type_button, selected_type)
		_queue_parameter_type_change(param, selected_type)
	)
	return type_button


func _make_value_control(param: GraphInputParameter) -> Control:
	var property_name := _value_property_name(param.data_type)
	if property_name.is_empty():
		return null
	var prop := _property_info(param, property_name)
	if prop.is_empty():
		return null

	var editor := FlowInspectorPropertyPolicy.create_native_property_editor(
		param,
		prop.type,
		property_name,
		prop.hint,
		prop.hint_string,
		prop.usage,
		is_wide_value_type(param.data_type),
		""
	)
	if editor == null:
		return null
	editor.draw_label = false
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if param.data_type == FlowData.DataType.Bool:
		_clear_check_box_text(editor)
	editor.property_changed.connect(func(
		edited_property: StringName,
		value,
		_field: StringName,
		_changing: bool,
	):
		param.set(String(edited_property), value)
		_emit_parameter_changed(param)
	)
	editor.multiple_properties_changed.connect(func(properties: PackedStringArray, values: Array):
		var count := mini(properties.size(), values.size())
		for index in range(count):
			param.set(String(properties[index]), values[index])
		_emit_parameter_changed(param)
	)
	return editor



func _on_add_parameter_pressed() -> void:
	var params := _graph_parameter_array()
	var param := GraphInputParameter.new()
	var base_name := "new_param" if parameter_property == "in_params" else "new_out"
	param.name = _unique_parameter_name(params, base_name)
	param.data_type = FlowData.DataType.Float
	params.append(param)
	_assign_graph_parameter_array(params)
	_emit_parameter_changed(param, true)
	_queue_parameter_list_refresh()


func _set_parameter_name(param: GraphInputParameter, name_edit: LineEdit, new_text: String) -> void:
	var next_name := new_text.strip_edges()
	if next_name.is_empty():
		next_name = param.name
	if param.name == next_name:
		name_edit.text = next_name
		return
	param.name = next_name
	name_edit.text = next_name
	_emit_parameter_changed(param, true)


func _graph_parameter_array() -> Array:
	if parameter_property == "out_params":
		return graph_resource.out_params.duplicate()
	return graph_resource.in_params.duplicate()


func _assign_graph_parameter_array(params: Array) -> void:
	if parameter_property == "out_params":
		var output_params: Array[GraphInputParameter] = []
		for param in params:
			if param is GraphInputParameter:
				output_params.append(param)
		graph_resource.out_params = output_params
		return

	var input_params: Array[GraphInputParameter] = []
	for param in params:
		if param is GraphInputParameter:
			input_params.append(param)
	graph_resource.in_params = input_params


func _emit_parameter_changed(param: GraphInputParameter = null, structural: bool = false) -> void:
	if param != null:
		param.emit_changed()
	graph_resource.emit_changed()
	if structural:
		_queue_structural_property_edited(parameter_property)
		graph_resource._queue_in_params_changed()
		return
	property_edited.emit(GRAPH_PARAMETER_VALUE_EDITED)


func _queue_parameter_list_refresh() -> void:
	if _list_refresh_queued:
		return
	_list_refresh_queued = true
	call_deferred("_refresh_parameter_list_deferred")


func _refresh_parameter_list_deferred() -> void:
	_list_refresh_queued = false
	if is_queued_for_deletion():
		return
	_populate_parameter_list()


func _queue_parameter_type_change(param: GraphInputParameter, data_type: int) -> void:
	call_deferred("_apply_parameter_type_change_deferred", param, data_type)


func _apply_parameter_type_change_deferred(param: GraphInputParameter, data_type: int) -> void:
	if is_queued_for_deletion() or param == null or not is_instance_valid(param):
		return
	if param.data_type == data_type:
		return
	param.data_type = data_type
	_emit_parameter_changed(param, true)
	_queue_parameter_list_refresh()


func _queue_structural_property_edited(prop_name: String) -> void:
	_pending_structural_property = prop_name
	if _structural_property_edited_queued:
		return
	_structural_property_edited_queued = true
	call_deferred("_emit_structural_property_edited_deferred")


func _emit_structural_property_edited_deferred() -> void:
	_structural_property_edited_queued = false
	if is_queued_for_deletion():
		return
	property_edited.emit(_pending_structural_property)


func _unique_parameter_name(params: Array, base_name: String) -> String:
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


func _type_label(data_type: int) -> String:
	var keys := FlowData.DataType.keys()
	if data_type >= 0 and data_type < keys.size():
		return FlowI18n.t(keys[data_type])
	return str(data_type)


static func is_wide_value_type(data_type: int) -> bool:
	return WIDE_VALUE_TYPES.has(data_type)


func _value_property_name(data_type: int) -> String:
	return GraphInputParameter.value_property_name(data_type)


func _property_info(object: Object, property_name: String) -> Dictionary:
	for prop in object.get_property_list():
		if str(prop.name) == property_name:
			return prop
	return {}


func _make_type_swatch_icon(data_type: int) -> Texture2D:
	var image := Image.create(12, 4, false, Image.FORMAT_RGBA8)
	image.fill(_ue_type_color(data_type))
	return ImageTexture.create_from_image(image)


func _style_type_button(type_button: OptionButton, data_type: int) -> void:
	var type_color := _ue_type_color(data_type)
	_apply_type_button_background(type_button, "normal", type_color.darkened(0.42))
	_apply_type_button_background(type_button, "hover", type_color.darkened(0.34))
	_apply_type_button_background(type_button, "pressed", type_color.darkened(0.26))
	_apply_type_button_background(type_button, "hover_pressed", type_color.darkened(0.26))
	_apply_type_button_background(type_button, "disabled", type_color.darkened(0.58))
	_apply_type_button_background(type_button, "normal_mirrored", type_color.darkened(0.42))
	_apply_type_button_background(type_button, "hover_mirrored", type_color.darkened(0.34))
	_apply_type_button_background(type_button, "pressed_mirrored", type_color.darkened(0.26))
	_apply_type_button_background(type_button, "hover_pressed_mirrored", type_color.darkened(0.26))
	_apply_type_button_background(type_button, "disabled_mirrored", type_color.darkened(0.58))
	type_button.add_theme_color_override("font_color", type_color.lightened(0.18))
	type_button.add_theme_color_override("font_hover_color", type_color.lightened(0.28))
	type_button.add_theme_color_override("font_pressed_color", type_color.lightened(0.35))
	type_button.add_theme_color_override("font_focus_color", type_color.lightened(0.28))
	type_button.add_theme_color_override("font_hover_pressed_color", type_color.lightened(0.35))


func _clear_check_box_text(root: Node) -> void:
	if root is CheckBox:
		(root as CheckBox).text = ""
	for child in root.get_children():
		_clear_check_box_text(child)


func _apply_type_button_background(
	type_button: OptionButton,
	style_name: String,
	bg_color: Color,
) -> void:
	var stylebox := type_button.get_theme_stylebox(style_name, &"EditorInspectorButton").duplicate()
	var flat_stylebox := stylebox as StyleBoxFlat
	if flat_stylebox == null:
		flat_stylebox = StyleBoxFlat.new()
	flat_stylebox.bg_color = bg_color
	flat_stylebox.draw_center = true
	type_button.add_theme_stylebox_override(style_name, flat_stylebox)


func _ue_type_color(data_type: int) -> Color:
	match data_type:
		FlowData.DataType.Bool:
			return Color("c21f1f")
		FlowData.DataType.Int:
			return Color("2dd4a3")
		FlowData.DataType.Float:
			return Color("67e34d")
		FlowData.DataType.Vector:
			return Color("ffd23f")
		FlowData.DataType.String:
			return Color("f12cff")
		FlowData.DataType.Resource:
			return Color("1685ff")
		FlowData.DataType.Int64:
			return Color("1f9e8a")
		FlowData.DataType.Double:
			return Color("9be35a")
		FlowData.DataType.Vector2:
			return Color("e8c547")
		FlowData.DataType.Vector4:
			return Color("ff9f3f")
		FlowData.DataType.Quaternion:
			return Color("a29bfe")
		FlowData.DataType.Color:
			return Color("3f6fff")
		FlowData.DataType.Transform:
			return Color("ff6a00")
	return Color("7a8494")


func _apply_editor_icon(button: Button, icon_name: String, icon_only: bool = false) -> void:
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme == null or not editor_theme.has_icon(icon_name, "EditorIcons"):
		return
	button.icon = editor_theme.get_icon(icon_name, "EditorIcons")
	if icon_only:
		button.text = ""
