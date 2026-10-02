@tool
extends GraphEdit

const REROUTE_TEMPLATE := "reroute"
const REROUTE_PORT_MATCH_DISTANCE := 2.5
const CONNECTION_SAMPLE_COUNT := 32
const FORWARD_HORIZONTAL_RANGE := 1000.0
const FORWARD_VERTICAL_RANGE := 1000.0
const BACKWARD_HORIZONTAL_RANGE := 200.0
const BACKWARD_VERTICAL_RANGE := 200.0
const FORWARD_HORIZONTAL_TANGENT := Vector2(1.0, 0.0)
const FORWARD_VERTICAL_TANGENT := Vector2(1.0, 0.0)
const BACKWARD_HORIZONTAL_TANGENT := Vector2(2.0, 0.0)
const BACKWARD_VERTICAL_TANGENT := Vector2(1.5, 0.0)

enum PinDirection {
	INPUT,
	OUTPUT,
}

var _last_connection_zoom := -1.0

func _ready() -> void:
	minimap_enabled = false
	_last_connection_zoom = zoom
	set_process(true)

func _process(_delta: float) -> void:
	if is_equal_approx(_last_connection_zoom, zoom):
		return
	_last_connection_zoom = zoom
	# GraphEdit caches line points, but some zoom paths do not invalidate them.
	set_connection_lines_curvature(get_connection_lines_curvature())

func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var from_endpoint := _resolve_reroute_endpoint(from_position)
	var to_endpoint := _resolve_reroute_endpoint(to_position)
	var start_position : Vector2 = from_endpoint.position
	var end_position : Vector2 = to_endpoint.position

	var start_direction := PinDirection.OUTPUT
	if from_endpoint.node != null and _should_reverse_reroute_tangent(from_endpoint.node):
		start_direction = PinDirection.INPUT

	var end_direction := PinDirection.INPUT
	if to_endpoint.node != null and _should_reverse_reroute_tangent(to_endpoint.node):
		end_direction = PinDirection.OUTPUT

	return _make_connection_line(start_position, end_position, start_direction, end_direction)

func _resolve_reroute_endpoint(position: Vector2) -> Dictionary:
	for child in get_children():
		var node := child as FlowNodeWidget
		if node == null or node.node_template != REROUTE_TEMPLATE:
			continue

		var left_port := _reroute_left_port_graph_position(node)
		var right_port := _reroute_right_port_graph_position(node)
		var center := _reroute_center_graph_position(node)
		if _is_near_scaled_reroute_port(position, left_port) or _is_near_scaled_reroute_port(position, right_port):
			return {
				"position": center * zoom,
				"node": node,
			}
		if _is_near_graph_reroute_port(position, left_port) or _is_near_graph_reroute_port(position, right_port):
			return {
				"position": center,
				"node": node,
			}

	return {
		"position": position,
		"node": null,
	}

func _is_near_scaled_reroute_port(position: Vector2, graph_port_position: Vector2) -> bool:
	return position.distance_to(graph_port_position * zoom) <= REROUTE_PORT_MATCH_DISTANCE

func _is_near_graph_reroute_port(position: Vector2, graph_port_position: Vector2) -> bool:
	return position.distance_to(graph_port_position) <= REROUTE_PORT_MATCH_DISTANCE

func _reroute_center_graph_position(node: FlowNodeWidget) -> Vector2:
	var port_y := node.size.y * 0.5
	if node.get_input_port_count() > 0:
		port_y = node.get_input_port_position(0).y
	return node.position_offset + Vector2(node.size.x * 0.5, port_y)

func _reroute_left_port_graph_position(node: FlowNodeWidget) -> Vector2:
	if node.get_input_port_count() > 0:
		return node.position_offset + node.get_input_port_position(0)
	var center := _reroute_center_graph_position(node)
	return Vector2(node.position_offset.x, center.y)

func _reroute_right_port_graph_position(node: FlowNodeWidget) -> Vector2:
	if node.get_output_port_count() > 0:
		return node.position_offset + node.get_output_port_position(0)
	var center := _reroute_center_graph_position(node)
	return Vector2(node.position_offset.x + node.size.x, center.y)

func _should_reverse_reroute_tangent(node: FlowNodeWidget) -> bool:
	var input_average := Vector2.ZERO
	var output_average := Vector2.ZERO
	var input_count := 0
	var output_count := 0

	for conn in get_connection_list():
		if conn.to_node == node.name and int(conn.to_port) == 0:
			var source_node := get_node_or_null(NodePath(conn.from_node)) as GraphNode
			if source_node != null and int(conn.from_port) < source_node.get_output_port_count():
				input_average += _node_output_port_graph_position(source_node, conn.from_port)
				input_count += 1
		if conn.from_node == node.name and int(conn.from_port) == 0:
			var target_node := get_node_or_null(NodePath(conn.to_node)) as GraphNode
			if target_node != null and int(conn.to_port) < target_node.get_input_port_count():
				output_average += _node_input_port_graph_position(target_node, conn.to_port)
				output_count += 1

	if input_count > 0:
		input_average /= float(input_count)
	if output_count > 0:
		output_average /= float(output_count)

	if input_count > 0 and output_count > 0:
		return output_average.x < input_average.x

	var center := _reroute_center_graph_position(node)
	if input_count > 0:
		return center.x < input_average.x
	if output_count > 0:
		return output_average.x < center.x
	return false

func _node_input_port_graph_position(node: GraphNode, port: int) -> Vector2:
	var flow_node := node as FlowNodeWidget
	if flow_node != null and flow_node.node_template == REROUTE_TEMPLATE:
		return _reroute_center_graph_position(flow_node)
	return node.position_offset + node.get_input_port_position(port)

func _node_output_port_graph_position(node: GraphNode, port: int) -> Vector2:
	var flow_node := node as FlowNodeWidget
	if flow_node != null and flow_node.node_template == REROUTE_TEMPLATE:
		return _reroute_center_graph_position(flow_node)
	return node.position_offset + node.get_output_port_position(port)

func _make_connection_line(start_position: Vector2, end_position: Vector2, start_direction: int, end_direction: int) -> PackedVector2Array:
	var tangent := _compute_ue_spline_tangent(start_position, end_position)
	var start_tangent := tangent if start_direction == PinDirection.OUTPUT else -tangent
	var end_tangent := tangent if end_direction == PinDirection.INPUT else -tangent
	var points := PackedVector2Array()
	for idx in range(CONNECTION_SAMPLE_COUNT + 1):
		var alpha := float(idx) / float(CONNECTION_SAMPLE_COUNT)
		points.append(_cubic_hermite(start_position, start_tangent, end_position, end_tangent, alpha))
	return points

func _compute_ue_spline_tangent(start_position: Vector2, end_position: Vector2) -> Vector2:
	var delta := end_position - start_position
	var going_forward := delta.x >= 0.0
	var clamped_x := minf(absf(delta.x), FORWARD_HORIZONTAL_RANGE if going_forward else BACKWARD_HORIZONTAL_RANGE)
	var clamped_y := minf(absf(delta.y), FORWARD_VERTICAL_RANGE if going_forward else BACKWARD_VERTICAL_RANGE)
	if going_forward:
		return clamped_x * FORWARD_HORIZONTAL_TANGENT + clamped_y * FORWARD_VERTICAL_TANGENT
	return clamped_x * BACKWARD_HORIZONTAL_TANGENT + clamped_y * BACKWARD_VERTICAL_TANGENT

func _cubic_hermite(start_position: Vector2, start_tangent: Vector2, end_position: Vector2, end_tangent: Vector2, alpha: float) -> Vector2:
	var alpha2 := alpha * alpha
	var alpha3 := alpha2 * alpha
	var h00 := 2.0 * alpha3 - 3.0 * alpha2 + 1.0
	var h10 := alpha3 - 2.0 * alpha2 + alpha
	var h01 := -2.0 * alpha3 + 3.0 * alpha2
	var h11 := alpha3 - alpha2
	return h00 * start_position + h10 * start_tangent + h01 * end_position + h11 * end_tangent
