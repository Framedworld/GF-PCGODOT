@tool
class_name FlowRerouteWidget
extends FlowNodeWidget

## Widget of the reroute node: draws its output port as a plain dot.
## GraphNode._draw_port replaces the default port drawing for every port of a
## widget that implements it, so only reroute uses this subclass (selected by
## nodes/reroute.gd widget_script()).

const PIN_RADIUS := 5.0
const GRAPH_BG_COLOR := Color("0b0d12")

func _draw_port(_slot_index: int, port_position: Vector2i, left: bool, _color: Color) -> void:
	if left:
		return
	var center := Vector2(size.x * 0.5, port_position.y)
	draw_circle(center, PIN_RADIUS + 1.5, GRAPH_BG_COLOR)
	draw_circle(center, PIN_RADIUS, Color.WHITE)
