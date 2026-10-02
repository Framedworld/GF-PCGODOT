@tool
extends FlowNodeBase

const GetVariableNodeSettings = preload("res://addons/flow_nodes_editor/nodes/get_variable_settings.gd")

# Editor only: the variable picker the widget shows on the output row.
var variable_option: OptionButton

func _init():
	meta_node = {
		"title" : "Get Variable",
		"settings" : GetVariableNodeSettings,
		"ins" : [],
		"outs" : [{ "label" : "", "data_type" : FlowData.DataType.Invalid }],
		"tooltip" : "Reads data from a named graph variable declared by a Set Variable node.",
		"hide_inputs" : true,
		"category" : "Metadata",
		"aliases" : ["variable", "get"],
	}

func _variable_name() -> String:
	if not settings or not ("variable_name" in settings):
		return ""
	return String(settings.variable_name).strip_edges()

func _get_variable_color() -> Color:
	var variable_name := _variable_name()
	var editor = getEditor()
	if editor and editor.has_method("getSetVariableColor"):
		return editor.getSetVariableColor(variable_name)
	return Color("22d3ee")

func _get_custom_node_color() -> Color:
	return _get_variable_color()

func getTitle() -> String:
	var variable_name := _variable_name()
	if variable_name.is_empty():
		return "Get Variable"
	return "Get: %s" % variable_name

func getExposedParams():
	return []

# --- Widget hooks (see node.gd) -----------------------------------------------

func widget_init(widget):
	_place_variable_option_on_connector_row(widget)
	refreshVariableChoices()

func refreshVariableChoices() -> void:
	if not variable_option or not is_instance_valid(variable_option):
		return
	variable_option.clear()
	var current_name := _variable_name()
	var selected_idx := -1
	var item_idx := 0
	var editor = getEditor()
	var definitions := []
	if editor and editor.has_method("getSetVariableDefinitions"):
		definitions = editor.getSetVariableDefinitions()
	for definition in definitions:
		var variable_name := String(definition.get("name", ""))
		if variable_name.is_empty():
			continue
		variable_option.add_item(variable_name, item_idx)
		if variable_name == current_name:
			selected_idx = item_idx
		item_idx += 1
	if item_idx == 0:
		variable_option.add_item(FlowI18n.t("No variables set"), 0)
		variable_option.selected = 0
		variable_option.disabled = true
	else:
		variable_option.disabled = false
		variable_option.select(selected_idx)

func widget_refresh(widget):
	refreshVariableChoices()
	var color := _get_variable_color()
	if widget.is_slot_enabled_right(0):
		widget.set_slot_color_right(0, color)
	widget.title = getTitle()

func _place_variable_option_on_connector_row(widget) -> void:
	var row : FlowConnectorRow
	for child in widget.get_children():
		row = child as FlowConnectorRow
		if row != null:
			break
	if row == null:
		return
	row.getInLabel().text = ""
	row.getOutLabel().text = ""
	row.getInLabel().visible = false
	row.getOutLabel().visible = false
	var spacer = row.get_node_or_null("Spacer") as Control
	if spacer:
		spacer.custom_minimum_size.x = 8
	variable_option = OptionButton.new()
	variable_option.add_theme_font_size_override("font_size", 11)
	variable_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	variable_option.custom_minimum_size.x = 120
	variable_option.item_selected.connect(_on_variable_option_selected)
	row.add_child(variable_option)
	row.move_child(variable_option, 1)

func _on_variable_option_selected(index: int) -> void:
	if not settings or variable_option.disabled:
		return
	var selected_name := variable_option.get_item_text(index)
	if String(settings.variable_name) == selected_name:
		return
	settings.variable_name = selected_name
	settings.emit_changed()
	var editor = getEditor()
	if editor:
		editor.queueSave()
		editor.queueRegen()
		if editor.has_method("refreshVariableNodes"):
			editor.refreshVariableNodes()

func execute(ctx : FlowData.EvaluationContext):
	var variable_name := _variable_name()
	if variable_name.is_empty():
		setError("No variable selected")
		set_output(0, FlowData.Data.new())
		return
	var data = ctx.variables.get(variable_name, null)
	if data == null:
		setError("Variable '%s' is not set" % variable_name)
		set_output(0, FlowData.Data.new())
		return
	set_output(0, data)
