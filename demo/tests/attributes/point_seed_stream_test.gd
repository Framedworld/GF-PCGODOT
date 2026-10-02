# point_seed_stream_test.gd
# Pins FlowData.point_seed_stream (WP13-P1) to FlowData.point_seed element by
# element, and the generators that switched to it (grid, surface_sampler) to
# their original implementations kept verbatim under tests/nodes/support,
# including the negative-count paths that log resize errors.
class_name PointSeedStreamTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")
const GridScript = preload("res://addons/flow_nodes_editor/nodes/grid.gd")
const GridReference = preload("res://tests/nodes/support/grid_reference.gd")
const SurfaceScript = preload("res://addons/flow_nodes_editor/nodes/surface_sampler.gd")
const SurfaceReference = preload("res://tests/nodes/support/surface_sampler_reference.gd")

func test_stream_matches_point_seed_for_every_position() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var positions := PackedVector3Array([Vector3.ZERO, Vector3(-0.0005, 0.0005, 0.0015), Vector3(1e9, -1e9, 3.5),
		Vector3(INF, -INF, 0), Vector3(NAN, 1, 2), Vector3(0.4999, -0.5001, 2.5)])
	for i in range(3000):
		positions.append(Vector3(rng.randf_range(-1e4, 1e4), rng.randf_range(-10, 10), rng.randf_range(-1e4, 1e4)))
	for node_seed in [0, 1, -7, 123456789, 0x7fffffff, -0x80000000]:
		var stream := FlowDataScript.point_seed_stream(positions, node_seed)
		assert_int(stream.size()).is_equal(positions.size())
		var mismatches := 0
		for i in range(positions.size()):
			if stream[i] != FlowDataScript.point_seed(positions[i], node_seed):
				mismatches += 1
		assert_int(mismatches).is_equal(0)
	assert_int(FlowDataScript.point_seed_stream(PackedVector3Array(), 5).size()).is_equal(0)

static func _grid_settings(x : int, y : int, z : int):
	var s = GridNodeSettings.new()
	s.x = x
	s.y = y
	s.z = z
	s.step = Vector3(0.5, 2, 1.25)
	s.origin = Vector3(3, -1, 7)
	s.rotation = Vector3(0, 33, 0)
	s.random_seed = 99
	return s

func test_grid_matches_the_reference() -> void:
	for dims in [[4, 1, 5], [1, 1, 1], [0, 3, 3], [3, -2, 2], [-1, -1, 1]]:
		var expected := R.exec_logged(GridReference, _grid_settings(dims[0], dims[1], dims[2]), [])
		var actual := R.exec_logged(GridScript, _grid_settings(dims[0], dims[1], dims[2]), [])
		assert_array(actual).override_failure_message("grid %s differs" % str(dims)).is_equal(expected)

func test_surface_sampler_matches_the_reference() -> void:
	var boxes = H.points([Vector3(0, 0, 0), Vector3(10, 1, -4)])
	boxes.getVector3Container("size")[0] = Vector3(4, 1, 6)
	boxes.getVector3Container("rotation")[1] = Vector3(0, 45, 10)
	for num_points in [17, 1, 0, -3]:
		var s_ref = SurfaceReference.new().meta_node.settings.new()
		var s_new = SurfaceScript.new().meta_node.settings.new()
		for s in [s_ref, s_new]:
			s.num_points = num_points
			s.random_seed = 4321
		var expected := R.exec_logged(SurfaceReference, s_ref, [boxes])
		var actual := R.exec_logged(SurfaceScript, s_new, [boxes])
		assert_array(actual).override_failure_message("surface_sampler %d differs" % num_points).is_equal(expected)
