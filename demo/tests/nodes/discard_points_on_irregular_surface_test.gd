# discard_points_on_irregular_surface_test.gd
class_name DiscardPointsOnIrregularSurfaceTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/discard_points_on_irregular_surface.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/discard_points_on_irregular_surface_settings.gd")

const VEC := FlowDataScript.DataType.Vector

## size x size grid with spacing 1 and a 3x3 footprint (size stream = 3),
## heights from `height_fn(x, z)`.
func _grid(count : int, height_fn : Callable) -> FlowData.Data:
	var pts := []
	for x in range(count):
		for z in range(count):
			pts.append(Vector3(x, height_fn.call(x, z), z))
	var d = H.points(pts)
	d.registerStream("size", PackedVector3Array([Vector3(3, 1, 3)]), VEC)
	return d

func _settings():
	var s = SettingsScript.new()
	s.neighbor_search = SettingsScript.eNeighborSearch.GDScript
	return s

func _exec(data, settings) -> Dictionary:
	return H.exec(NodeScript, settings, [data])

func _split(data, settings) -> Array:
	var r := _exec(data, settings)
	assert_str(r.err).is_empty()
	return [H.port(r, 0), H.port(r, 1)]

func _has_point(data, p : Vector3) -> bool:
	for q in data.getVector3Container("position"):
		if q.is_equal_approx(p):
			return true
	return false

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Discard Points On Irregular Surface"])
	assert_int(node.meta_node.outs.size()).is_equal(2)
	H.dispose(node)

func test_flat_grid_keeps_everything() -> void:
	var h = _split(_grid(5, func(_x, _z): return 0.0), _settings())
	assert_int(h[0].size()).is_equal(25)
	assert_int(h[1].size()).is_equal(0)

func test_bump_discards_its_neighbourhood_only() -> void:
	var d = _grid(7, func(x, z): return 2.0 if x == 3 and z == 3 else 0.0)
	var h = _split(d, _settings())
	assert_bool(_has_point(h[1], Vector3(3, 2, 3))).is_true()
	assert_bool(_has_point(h[1], Vector3(2, 0, 3))).is_true()
	assert_bool(_has_point(h[0], Vector3(0, 0, 0))).is_true()
	assert_bool(_has_point(h[0], Vector3(5, 0, 3))).is_true()
	assert_int(h[0].size() + h[1].size()).is_equal(49)

func test_smooth_slope_std_dev_vs_plane_residual() -> void:
	var d = _grid(5, func(x, _z): return 0.5 * x)
	var s = _settings()
	assert_int(_split(d, s)[1].size()).is_greater(0)
	s.height_metric = SettingsScript.eHeightMetric.PlaneResidual
	var h = _split(d, s)
	assert_int(h[1].size()).is_equal(0)
	assert_int(h[0].size()).is_equal(25)

func test_max_deviation_metric() -> void:
	var d = _grid(5, func(x, z): return 0.2 if x == 2 and z == 2 else 0.0)
	var s = _settings()
	s.height_metric = SettingsScript.eHeightMetric.MaxDeviation
	s.max_height_deviation = 0.15
	assert_bool(_has_point(_split(d, s)[1], Vector3(2, 0.2, 2))).is_true()
	s.max_height_deviation = 0.25
	assert_int(_split(d, s)[1].size()).is_equal(0)

func test_normal_deviation_from_attribute() -> void:
	var d = _grid(7, func(_x, _z): return 0.0)
	var normals := PackedVector3Array()
	for p in d.getVector3Container("position"):
		normals.append(Vector3(1, 1, 0).normalized() if p == Vector3(3, 0, 3) else Vector3.UP)
	d.registerStream("normal", normals, VEC)
	var s = _settings()
	s.normal_metric_attribute = "nangle"
	var h = _split(d, s)
	assert_bool(_has_point(h[1], Vector3(3, 0, 3))).is_true()
	assert_bool(_has_point(h[0], Vector3(0, 0, 0))).is_true()
	assert_float(h[1].value_at("nangle", 0)).is_equal_approx(45.0, 0.01)
	s.max_normal_angle = -1.0
	assert_int(_split(d, s)[1].size()).is_equal(0)

func test_normal_falls_back_to_rotation_up() -> void:
	var d = _grid(5, func(_x, _z): return 0.0)
	var rot = d.getVector3Container("rotation")
	rot[12] = Vector3(0, 0, 60)  # (2, 0, 2) tilted 60 degrees
	var h = _split(d, _settings())
	assert_bool(_has_point(h[1], Vector3(2, 0, 2))).is_true()

func test_isolated_points() -> void:
	var d = H.points([Vector3(0, 0, 0), Vector3(100, 5, 0)])
	var h = _split(d, _settings())
	assert_int(h[0].size()).is_equal(2)
	var s = _settings()
	s.keep_isolated = false
	assert_int(_split(d, s)[1].size()).is_equal(2)

func test_footprint_scale_and_asymmetric_bounds() -> void:
	# Bump at x = 2 seen only by points whose footprint reaches it.
	var d = H.points([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 3, 0), Vector3(3, 0, 0), Vector3(4, 0, 0)])
	d.registerStream("bounds_min", PackedVector3Array([Vector3(-1.5, 0, -0.5)]), VEC)
	d.registerStream("bounds_max", PackedVector3Array([Vector3(0, 0, 0.5)]), VEC)
	var s = _settings()
	s.min_neighbors = 1
	s.height_metric_attribute = "hm"
	s.neighbor_count_attribute = "nb"
	var h = _split(d, s)
	# Footprints look only towards -X: x = 3 sees the bump, x = 1 does not.
	assert_bool(_has_point(h[1], Vector3(3, 0, 0))).is_true()
	assert_bool(_has_point(h[0], Vector3(1, 0, 0))).is_true()
	assert_bool(h[0].hasStream("hm")).is_true()
	assert_bool(h[1].hasStream("nb")).is_true()
	s.footprint_scale = 0.0
	s.min_neighbors = 0
	assert_int(_split(d, s)[1].size()).is_equal(0)

func test_min_footprint_extent() -> void:
	var d = H.points([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 3, 0)])
	d.registerStream("size", PackedVector3Array([Vector3(0.1, 0.1, 0.1)]), VEC)
	var s = _settings()
	s.min_neighbors = 1
	assert_int(_split(d, s)[1].size()).is_equal(0)
	s.min_footprint_extent = 2.5
	assert_bool(_has_point(_split(d, s)[1], Vector3(1, 0, 0))).is_true()

func _noisy_cloud(count : int) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var pts := []
	for i in range(count):
		var x := rng.randf_range(0, 20)
		var z := rng.randf_range(0, 20)
		var y := (0.6 if rng.randf() < 0.15 else 0.0) + 0.05 * x
		pts.append(Vector3(x, y, z))
	var d = H.points(pts)
	d.registerStream("size", PackedVector3Array([Vector3(2.5, 1, 2.5)]), VEC)
	return d

func test_native_and_gdscript_backends_agree() -> void:
	if not NodeScript.native_available():
		return
	var d = _noisy_cloud(300)
	var s = _settings()
	s.height_metric = SettingsScript.eHeightMetric.PlaneResidual
	s.max_height_deviation = 0.2
	s.height_metric_attribute = "hm"
	var a = _split(d, s)
	s.neighbor_search = SettingsScript.eNeighborSearch.Native
	var b = _split(d, s)
	assert_int(a[1].size()).is_greater(0)
	assert_int(a[0].size()).is_greater(0)
	assert_array(H.position_set(a[0])).is_equal(H.position_set(b[0]))
	assert_array(Array(a[0].container("hm"))).is_equal(Array(b[0].container("hm")))

func test_reorder_gives_same_split() -> void:
	var d = _noisy_cloud(120)
	var s = _settings()
	s.height_metric_attribute = "hm"
	var a = _split(d, s)
	var b = _split(H.reversed(d), s)
	assert_array(H.position_set(a[0])).is_equal(H.position_set(b[0]))
	assert_array(H.position_set(a[1])).is_equal(H.position_set(b[1]))

func test_empty_missing_position_and_missing_input() -> void:
	var h = _split(H.points([]), _settings())
	assert_int(h[0].size()).is_equal(0)
	assert_int(h[1].size()).is_equal(0)
	var d = FlowDataScript.Data.new()
	d.registerStream("density", PackedFloat32Array([1, 1]))
	assert_str(_exec(d, _settings()).err).contains("position")
	assert_str(_exec(null, _settings()).err).contains("not connected")
