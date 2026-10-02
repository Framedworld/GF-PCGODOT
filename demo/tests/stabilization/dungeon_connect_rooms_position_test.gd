# WP11 item 1: dungeon_connect_rooms on input without a position stream.
class_name DungeonConnectRoomsPositionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/dungeon_connect_rooms.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/dungeon_connect_rooms_settings.gd")

func test_rows_without_position_report_an_error() -> void:
	var d = FlowDataScript.Data.new()
	d.registerStream("weight", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var r := H.exec(NodeScript, SettingsScript.new(), [d])
	assert_str(r.err).is_equal("Input must provide a position stream")

func test_single_row_without_position_is_still_empty_output() -> void:
	var d = FlowDataScript.Data.new()
	d.registerStream("weight", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var r := H.exec(NodeScript, SettingsScript.new(), [d])
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 0).size()).is_equal(0)

func test_points_still_connect() -> void:
	var r := H.exec(NodeScript, SettingsScript.new(), [H.points([Vector3.ZERO, Vector3(8, 0, 0)])])
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 0).size()).is_greater(1)
