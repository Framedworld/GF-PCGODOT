extends SceneTree

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")


func _init() -> void:
	var passed := true
	passed = _test_filter_preserves_broadcast_streams() and passed
	passed = _test_filter_drops_single_row_streams_when_not_selected() and passed
	if not passed:
		push_error("FlowDataFilterBroadcastTest failed.")
		quit(1)
		return
	quit(0)


func _test_filter_preserves_broadcast_streams() -> bool:
	var data := FlowDataScript.Data.new()
	data.registerStream(
		"position",
		PackedVector3Array([
			Vector3.ZERO,
			Vector3(1.0, 0.0, 0.0),
			Vector3(2.0, 0.0, 0.0),
			Vector3(3.0, 0.0, 0.0),
		]),
		FlowDataScript.DataType.Vector
	)
	data.registerStream(
		"shared_radius",
		PackedFloat32Array([42.0]),
		FlowDataScript.DataType.Float
	)
	var payload := Resource.new()
	var shared_payload: Array[Resource] = [payload]
	data.registerStream("shared_payload", shared_payload, FlowDataScript.DataType.Resource)

	var filtered: FlowData.Data = data.filter(PackedInt32Array([3, 1]))
	var position_stream = filtered.findStream("position")
	var radius_stream = filtered.findStream("shared_radius")
	var payload_stream = filtered.findStream("shared_payload")

	return (
		_expect(position_stream != null, "filtered data should keep position")
		and _expect(position_stream.container.size() == 2, "position should have selected rows")
		and _expect(position_stream.container[0] == Vector3(3.0, 0.0, 0.0), "position[0] should come from index 3")
		and _expect(position_stream.container[1] == Vector3(1.0, 0.0, 0.0), "position[1] should come from index 1")
		and _expect(radius_stream != null, "filtered data should keep broadcast float")
		and _expect(radius_stream.container.size() == 1, "broadcast float should stay single-value")
		and _expect(is_equal_approx(radius_stream.container[0], 42.0), "broadcast float value should be preserved")
		and _expect(payload_stream != null, "filtered data should keep broadcast resource")
		and _expect(payload_stream.container.size() == 1, "broadcast resource should stay single-value")
		and _expect(payload_stream.container[0] == payload, "broadcast resource value should be preserved")
	)


func _test_filter_drops_single_row_streams_when_not_selected() -> bool:
	var data := FlowDataScript.Data.new()
	data.registerStream(
		"position",
		PackedVector3Array([Vector3(1.0, 0.0, 0.0)]),
		FlowDataScript.DataType.Vector
	)

	var filtered: FlowData.Data = data.filter(PackedInt32Array())
	var position_stream = filtered.findStream("position")

	return (
		_expect(position_stream != null, "filtered single-row data should keep stream")
		and _expect(position_stream.container.is_empty(), "unselected single-row stream should be empty")
	)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	return false
