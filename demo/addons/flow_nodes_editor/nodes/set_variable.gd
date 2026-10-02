@tool
extends FlowNodeBase

const SetVariableNodeSettings = preload("res://addons/flow_nodes_editor/nodes/set_variable_settings.gd")

func _init():
	meta_node = {
		"title" : "Set Variable",
		"settings" : SetVariableNodeSettings,
		"ins" : [{ "label" : "In", "data_type" : FlowData.DataType.Invalid }],
		"outs" : [{ "label" : "Out", "data_type" : FlowData.DataType.Invalid }],
		"tooltip" : "Stores the input data in a named graph variable and passes it through unchanged.",
		"category" : "Metadata",
		"aliases" : ["variable", "set"],
	}

func _variable_name() -> String:
	if not settings or not ("variable_name" in settings):
		return ""
	return String(settings.variable_name).strip_edges()

func _get_custom_node_color() -> Color:
	if settings and "node_color" in settings:
		return settings.node_color
	return Color("22d3ee")

func getTitle() -> String:
	var variable_name := _variable_name()
	if variable_name.is_empty():
		return "Set Variable"
	return "Set: %s" % variable_name

func getExposedParams():
	return []

# --- Widget hooks (see node.gd) -----------------------------------------------

func widget_refresh(widget):
	var color := _get_custom_node_color()
	if widget.is_slot_enabled_left(0):
		widget.set_slot_color_left(0, color)
	if widget.is_slot_enabled_right(0):
		widget.set_slot_color_right(0, color)
	widget.title = getTitle()

func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = get_optional_input(0)
	if in_data == null:
		in_data = FlowData.Data.new()
	var variable_name := _variable_name()
	if variable_name.is_empty():
		setError("Variable name can't be empty")
		set_output(0, in_data)
		return
	ctx.variables[variable_name] = in_data
	set_output(0, in_data)
