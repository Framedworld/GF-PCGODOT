@tool
extends FlowNodeBase

const HIT_SIZE := Vector2(42, 24)
const PIN_RADIUS := 5.0
const GRAPH_BG_COLOR := Color("0b0d12")
const SELECTED_OUTLINE_COLOR := Color("fbbf24")
const SELECTED_OUTLINE_WIDTH := 1.5

func _init():
	meta_node = {
		"title" : "",
		"settings" : NodeSettings,
		"ins" : [{ "label" : "", "data_type" : FlowData.DataType.Invalid }],
		"outs" : [{ "label" : "", "data_type" : FlowData.DataType.Invalid }],
		"aliases" : ["Reroute"],
		"category" : "Utility",
		"tooltip" : "Reroute point - passes data through unchanged",
		"hide_inputs" : false,
		"auto_register" : false,
	}

func getTitle() -> String:
	# Stay compact: the node renders as a 30x30 dot without a visible title.
	return ""

func getExposedParams():
	return []

# --- Widget hooks (see node.gd) -----------------------------------------------

func widget_script() -> Script:
	return load("res://addons/flow_nodes_editor/executor/flow_reroute_widget.gd")

func widget_init(widget):
	for child in widget.get_children():
		var row := child as FlowConnectorRow
		if row == null:
			continue
		row.custom_minimum_size = HIT_SIZE
		row.getInLabel().text = ""
		row.getOutLabel().text = ""
		row.getInLabel().visible = false
		row.getOutLabel().visible = false
	widget.custom_minimum_size = HIT_SIZE
	widget.size = HIT_SIZE

func widget_refresh(widget):
	widget.title = ""
	widget.custom_minimum_size = HIT_SIZE
	widget.size = HIT_SIZE
	if widget.is_slot_enabled_left(0):
		widget.set_slot_color_left(0, Color.WHITE)
	if widget.is_slot_enabled_right(0):
		widget.set_slot_color_right(0, Color.WHITE)

func execute( ctx : FlowData.EvaluationContext ):
	var in_data = get_optional_input(0)
	if in_data:
		set_output(0, in_data)
	else:
		set_output(0, FlowData.Data.new())

func widget_ready(widget):
	widget.custom_minimum_size = HIT_SIZE
	widget.size = HIT_SIZE
	widget.mouse_filter = Control.MOUSE_FILTER_STOP
	widget.selectable = true
	widget.draggable = true

func widget_draw(widget) -> bool:
	var port_y : float = widget.size.y * 0.5
	if widget.get_input_port_count() > 0:
		port_y = widget.get_input_port_position(0).y
	var center := Vector2(widget.size.x * 0.5, port_y)
	if widget.selected:
		widget.draw_rect(Rect2(Vector2(0.5, 0.5), widget.size - Vector2.ONE), SELECTED_OUTLINE_COLOR, false, SELECTED_OUTLINE_WIDTH)
	widget.draw_circle(center, PIN_RADIUS + 1.5, GRAPH_BG_COLOR)
	widget.draw_circle(center, PIN_RADIUS, Color.WHITE)
	return true
