# reset_point_center_test.gd
class_name ResetPointCenterTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/reset_point_center.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/reset_point_center_settings.gd")

const VEC := FlowDataScript.DataType.Vector

func _out(data, loc : Vector3 = Vector3(0.5, 0.5, 0.5)):
	var s = SettingsScript.new()
	s.point_center_location = loc
	var r := H.exec(NodeScript, s, [data])
	assert_str(r.err).is_empty()
	return H.port(r)

func test_center_of_asymmetric_bounds() -> void:
	var d = H.points([Vector3(1, 0, 0)])
	d.registerStream("bounds_min", PackedVector3Array([Vector3(0, 0, 0)]), VEC)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(4, 2, 2)]), VEC)
	var out = _out(d)
	assert_vector(out.getVector3Container("position")[0]).is_equal(Vector3(3, 1, 1))
	assert_vector(out.getVector3Container("bounds_min")[0]).is_equal(Vector3(-2, -1, -1))
	assert_vector(out.getVector3Container("bounds_max")[0]).is_equal(Vector3(2, 1, 1))

func test_world_box_is_preserved() -> void:
	var d = H.points([Vector3(2, 3, 4)])
	d.getVector3Container("size")[0] = Vector3(2, 2, 2)
	var before = BoundsOverlapUtil.world_aabbs(d, d.getVector3Container("position"))
	var out = _out(d, Vector3(0, 0, 1))
	assert_vector(out.getVector3Container("position")[0]).is_equal(Vector3(1, 2, 5))
	var after = BoundsOverlapUtil.world_aabbs(out, out.getVector3Container("position"))
	assert_vector(after.min[0]).is_equal(before.min[0])
	assert_vector(after.max[0]).is_equal(before.max[0])
	assert_vector(out.getVector3Container("size")[0]).is_equal(Vector3(2, 2, 2))

func test_empty_and_missing_streams() -> void:
	assert_int(_out(H.points([])).size()).is_equal(0)
	var d = FlowDataScript.Data.new()
	d.registerStream("size", PackedVector3Array([Vector3.ONE]), VEC)
	var r := H.exec(NodeScript, SettingsScript.new(), [d])
	assert_str(r.err).contains("position")
	var missing := H.exec(NodeScript, SettingsScript.new(), [null])
	assert_str(missing.err).contains("not connected")

func test_broadcast_bounds() -> void:
	var d = H.points([Vector3.ZERO, Vector3(10, 0, 0)])
	d.registerStream("bounds_min", PackedVector3Array([Vector3.ZERO]), VEC)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(2, 2, 2)]), VEC)
	var out = _out(d)
	assert_vector(out.getVector3Container("position")[1]).is_equal(Vector3(11, 1, 1))
