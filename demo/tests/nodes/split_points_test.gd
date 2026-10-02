# split_points_test.gd
class_name SplitPointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/split_points.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/split_points_settings.gd")

const VEC := FlowDataScript.DataType.Vector

func _settings(axis : int = 1, ratio : float = 0.5, mode : int = 0):
	var s = SettingsScript.new()
	s.split_axis = axis
	s.split_position = ratio
	s.mode = mode
	return s

func _exec(data, settings) -> Dictionary:
	return H.exec(NodeScript, settings, [data])

func _halves(data, settings) -> Array:
	var r := _exec(data, settings)
	assert_str(r.err).is_empty()
	return [H.port(r, 0), H.port(r, 1)]

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Split Points"])
	assert_int(node.meta_node.outs.size()).is_equal(2)
	H.dispose(node)

func test_keep_transform_splits_implicit_bounds() -> void:
	var d = H.points([Vector3(10, 0, 0)])
	d.getVector3Container("size")[0] = Vector3(2, 4, 2)
	var h = _halves(d, _settings(1, 0.25))
	var before = h[0]
	var after = h[1]
	assert_vector(before.getVector3Container("bounds_min")[0]).is_equal(Vector3(-1, -2, -1))
	assert_vector(before.getVector3Container("bounds_max")[0]).is_equal(Vector3(1, -1, 1))
	assert_vector(after.getVector3Container("bounds_min")[0]).is_equal(Vector3(-1, -1, -1))
	assert_vector(after.getVector3Container("bounds_max")[0]).is_equal(Vector3(1, 2, 1))
	# Transforms untouched (Unreal behaviour).
	assert_vector(before.getVector3Container("position")[0]).is_equal(Vector3(10, 0, 0))
	assert_vector(after.getVector3Container("size")[0]).is_equal(Vector3(2, 4, 2))

func test_keep_transform_respects_asymmetric_bounds() -> void:
	var d = H.points([Vector3.ZERO])
	d.registerStream("bounds_min", PackedVector3Array([Vector3(0, 0, 0)]), VEC)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(10, 1, 1)]), VEC)
	var h = _halves(d, _settings(0, 0.3))
	assert_float(h[0].getVector3Container("bounds_max")[0].x).is_equal_approx(3.0, 1e-5)
	assert_float(h[1].getVector3Container("bounds_min")[0].x).is_equal_approx(3.0, 1e-5)
	assert_float(h[1].getVector3Container("bounds_max")[0].x).is_equal_approx(10.0, 1e-5)

func test_recenter_without_bounds_scales_size_and_moves_points() -> void:
	var d = H.points([Vector3(0, 5, 0)])
	d.getVector3Container("size")[0] = Vector3(2, 4, 2)
	var h = _halves(d, _settings(1, 0.25, 1))
	var before = h[0]
	var after = h[1]
	assert_bool(before.hasStream("bounds_min")).is_false()
	assert_vector(before.getVector3Container("size")[0]).is_equal(Vector3(2, 1, 2))
	assert_vector(after.getVector3Container("size")[0]).is_equal(Vector3(2, 3, 2))
	assert_vector(before.getVector3Container("position")[0]).is_equal(Vector3(0, 3.5, 0))
	assert_vector(after.getVector3Container("position")[0]).is_equal(Vector3(0, 5.5, 0))
	# The two world boxes tile the original one.
	var bb = BoundsOverlapUtil.world_aabbs(before, before.getVector3Container("position"))
	var ab = BoundsOverlapUtil.world_aabbs(after, after.getVector3Container("position"))
	assert_float(bb.min[0].y).is_equal_approx(3.0, 1e-5)
	assert_float(bb.max[0].y).is_equal_approx(ab.min[0].y, 1e-5)
	assert_float(ab.max[0].y).is_equal_approx(7.0, 1e-5)

func test_recenter_with_bounds_writes_symmetric_bounds() -> void:
	var d = H.points([Vector3.ZERO])
	d.registerStream("bounds_min", PackedVector3Array([Vector3(0, 0, 0)]), VEC)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(4, 2, 2)]), VEC)
	var h = _halves(d, _settings(0, 0.5, 1))
	assert_vector(h[0].getVector3Container("position")[0]).is_equal(Vector3(1, 1, 1))
	assert_vector(h[1].getVector3Container("position")[0]).is_equal(Vector3(3, 1, 1))
	assert_vector(h[0].getVector3Container("bounds_min")[0]).is_equal(Vector3(-1, -1, -1))
	assert_vector(h[0].getVector3Container("size")[0]).is_equal(Vector3.ONE)

func test_recenter_follows_rotation() -> void:
	var d = H.points([Vector3.ZERO])
	d.getVector3Container("size")[0] = Vector3(4, 1, 1)
	d.getVector3Container("rotation")[0] = Vector3(0, 90, 0)
	var h = _halves(d, _settings(0, 0.5, 1))
	var p0 : Vector3 = h[0].getVector3Container("position")[0]
	# Local -X rotated 90 degrees around Y points to +Z.
	assert_float(p0.x).is_equal_approx(0.0, 1e-4)
	assert_float(p0.z).is_equal_approx(1.0, 1e-4)

func test_ratio_attribute_per_point_and_broadcast() -> void:
	var d = H.points([Vector3.ZERO, Vector3(5, 0, 0)])
	d.registerStream("cut", PackedFloat32Array([0.1, 0.9]))
	var s = _settings(0, 0.5)
	s.split_position_attribute = "cut"
	var h = _halves(d, s)
	assert_float(h[0].getVector3Container("bounds_max")[0].x).is_equal_approx(-0.4, 1e-5)
	assert_float(h[0].getVector3Container("bounds_max")[1].x).is_equal_approx(0.4, 1e-5)
	var b = H.points([Vector3.ZERO, Vector3(5, 0, 0)])
	b.registerStream("cut", PackedFloat32Array([0.0]))
	var hb = _halves(b, s)
	assert_float(hb[0].getVector3Container("bounds_max")[1].x).is_equal_approx(-0.5, 1e-5)

func test_missing_ratio_attribute_is_an_error() -> void:
	var s = _settings()
	s.split_position_attribute = "nope"
	var r := _exec(H.points([Vector3.ZERO]), s)
	assert_str(r.err).contains("not found")

func test_side_and_fraction_attributes_and_inheritance() -> void:
	var d = H.points([Vector3.ZERO])
	d.registerStream("tag_id", PackedInt32Array([7]))
	d.registerStream("density", PackedFloat32Array([0.5]))
	var s = _settings(1, 0.25)
	s.side_attribute = "side"
	s.fraction_attribute = "frac"
	var h = _halves(d, s)
	assert_int(h[0].value_at("side", 0)).is_equal(0)
	assert_int(h[1].value_at("side", 0)).is_equal(1)
	assert_float(h[1].value_at("frac", 0)).is_equal_approx(0.75, 1e-6)
	assert_int(h[1].value_at("tag_id", 0)).is_equal(7)
	s.inherit_attributes = false
	var stripped = _halves(d, s)
	assert_bool(stripped[0].hasStream("tag_id")).is_false()
	assert_bool(stripped[0].hasStream("density")).is_true()
	assert_bool(stripped[0].hasStream("side")).is_true()

func test_tags_and_data_attributes_survive() -> void:
	var d = H.points([Vector3.ZERO])
	d.tags = PackedStringArray(["wall"])
	d.set_data_attr("floor", 3)
	var h = _halves(d, _settings())
	assert_array(Array(h[1].tags)).contains(["wall"])
	assert_int(h[1].get_data_attr("floor")).is_equal(3)

func test_empty_input_gives_two_empty_outputs() -> void:
	var h = _halves(H.points([]), _settings())
	assert_int(h[0].size()).is_equal(0)
	assert_int(h[1].size()).is_equal(0)

func test_missing_input_reports_error() -> void:
	var r := _exec(null, _settings())
	assert_str(r.err).contains("not connected")

func test_recenter_requires_position() -> void:
	var d = FlowDataScript.Data.new()
	d.registerStream("size", PackedVector3Array([Vector3.ONE]), VEC)
	var r := _exec(d, _settings(1, 0.5, 1))
	assert_str(r.err).contains("position")

func test_reorder_is_pointwise() -> void:
	var d = H.points([Vector3.ZERO, Vector3(3, 0, 0), Vector3(7, 1, 0)])
	d.getVector3Container("size")[1] = Vector3(2, 2, 2)
	var a = _halves(d, _settings(1, 0.3, 1))
	var b = _halves(H.reversed(d), _settings(1, 0.3, 1))
	assert_array(H.position_set(a[0])).is_equal(H.position_set(b[0]))
	assert_array(H.position_set(a[1])).is_equal(H.position_set(b[1]))
