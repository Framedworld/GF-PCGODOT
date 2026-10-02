# find_convex_hull_2d_test.gd
class_name FindConvexHull2DTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/find_convex_hull_2d.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/find_convex_hull_2d_settings.gd")

func _exec(data, settings = null) -> Dictionary:
	if settings == null:
		settings = SettingsScript.new()
	return H.exec(NodeScript, settings, [data])

func _out(data, settings = null):
	var r := _exec(data, settings)
	assert_str(r.err).is_empty()
	return H.port(r)

func _xz(out) -> Array:
	var res := []
	for p in out.getVector3Container("position"):
		res.append(Vector2(p.x, p.z))
	return res

func _square_with_interior() -> FlowData.Data:
	return H.points([
		Vector3(0.5, 0, 0.5), Vector3(1, 3, 1), Vector3(0, 0, 0), Vector3(0, 1, 1),
		Vector3(1, 0, 0), Vector3(0.2, 9, 0.7), Vector3(0.5, 0, 0),
	])

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Find Convex Hull 2D"])
	H.dispose(node)

func test_square_hull_in_ccw_order_with_index() -> void:
	var out = _out(_square_with_interior())
	assert_array(_xz(out)).is_equal([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	assert_array(Array(out.container("hull_index"))).is_equal([0, 1, 2, 3])
	# Heights are kept from the source points (projection is only for the test).
	assert_float(out.getVector3Container("position")[2].y).is_equal(3.0)

func test_shoelace_area_is_positive() -> void:
	var out = _out(H.points([Vector3(0, 0, 0), Vector3(4, 0, 1), Vector3(2, 0, 5), Vector3(-1, 0, 3), Vector3(1, 0, 2)]))
	var pts := _xz(out)
	var area := 0.0
	for i in range(pts.size()):
		var a : Vector2 = pts[i]
		var b : Vector2 = pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	assert_float(area).is_greater(0.0)
	assert_int(pts.size()).is_equal(4)

func test_reorder_gives_identical_hull() -> void:
	var d = _square_with_interior()
	d.registerStream("id", PackedInt32Array([0, 1, 2, 3, 4, 5, 6]))
	var a = _out(d)
	var b = _out(H.reversed(d))
	assert_array(_xz(a)).is_equal(_xz(b))
	assert_array(Array(a.container("id"))).is_equal(Array(b.container("id")))

func test_collinear_edge_points_optional() -> void:
	var d = _square_with_interior()
	assert_int(_out(d).size()).is_equal(4)
	var s = SettingsScript.new()
	s.include_collinear = true
	var out = _out(d, s)
	assert_array(_xz(out)).is_equal([Vector2(0, 0), Vector2(0.5, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])

func test_all_collinear_gives_segment() -> void:
	var d = H.points([Vector3(2, 0, 2), Vector3(0, 0, 0), Vector3(1, 0, 1)])
	assert_array(_xz(_out(d))).is_equal([Vector2(0, 0), Vector2(2, 2)])
	var s = SettingsScript.new()
	s.include_collinear = true
	assert_int(_out(d, s).size()).is_equal(3)

func test_duplicate_xz_keeps_one_point() -> void:
	var d = H.points([Vector3(0, 5, 0), Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
	var out = _out(d)
	assert_int(out.size()).is_equal(3)
	# The lowest y wins between equal x/z, whatever the input order.
	assert_float(out.getVector3Container("position")[0].y).is_equal(1.0)
	assert_float(_out(H.reversed(d)).getVector3Container("position")[0].y).is_equal(1.0)

func test_repeat_first_point_closes_loop() -> void:
	var s = SettingsScript.new()
	s.repeat_first_point = true
	var out = _out(_square_with_interior(), s)
	assert_int(out.size()).is_equal(5)
	assert_vector(out.getVector3Container("position")[4]).is_equal(out.getVector3Container("position")[0])
	assert_int(out.value_at("hull_index", 4)).is_equal(4)

func test_order_attribute_can_be_disabled() -> void:
	var s = SettingsScript.new()
	s.order_attribute = ""
	assert_bool(_out(_square_with_interior(), s).hasStream("hull_index")).is_false()

func test_broadcast_streams_and_tags_survive() -> void:
	var d = _square_with_interior()
	d.registerStream("density", PackedFloat32Array([0.25]))
	d.tags = PackedStringArray(["rim"])
	var out = _out(d)
	assert_float(out.value_at("density", 3)).is_equal_approx(0.25, 1e-6)
	assert_array(Array(out.tags)).contains(["rim"])

func test_small_inputs() -> void:
	assert_int(_out(H.points([])).size()).is_equal(0)
	assert_int(_out(H.points([Vector3.ONE])).size()).is_equal(1)
	assert_int(_out(H.points([Vector3.ONE, Vector3.ZERO])).size()).is_equal(2)

func test_missing_position_and_input() -> void:
	var d = FlowDataScript.Data.new()
	d.registerStream("density", PackedFloat32Array([1, 1, 1]))
	assert_str(_exec(d).err).contains("position")
	assert_str(_exec(null).err).contains("not connected")
