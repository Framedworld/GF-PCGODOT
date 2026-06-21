# volume_sampler_test.gd
class_name VolumeSamplerTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const VolumeSamplerNode = preload("res://addons/flow_nodes_editor/nodes/volume_sampler.gd")
const VolumeSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/volume_sampler_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _run(inputs: Array, settings) -> VolumeSamplerNode:
	var node = VolumeSamplerNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# Build a minimal FlowData.Data with position/rotation/size for one point at
# origin with the given size. This satisfies getTransformsStream().
func _make_volume_input(positions: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	var rotations = PackedVector3Array()
	rotations.resize(positions.size())
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _uniform_settings(dist: float = 0.5) -> VolumeSamplerSettings:
	var s = VolumeSamplerSettings.new()
	s.distribution = SamplePointsNodeSettings.eDistribution.UniformGrid
	s.sampling_distance = dist
	s.max_x = 4
	s.max_y = 4
	s.max_z = 4
	s.new_size_factor = 1.0
	return s

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_null_input_sets_error() -> void:
	var s = VolumeSamplerSettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_input_without_position_stream_sets_error() -> void:
	var s = _uniform_settings()
	var d = FlowDataScript.Data.new()
	d.registerStream("density", PackedFloat32Array([1.0, 1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_zero_sampling_distance_sets_error() -> void:
	# UniformGrid with sampling_distance == 0 must set an error (parent enforces this).
	var s = _uniform_settings(0.0)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_negative_sampling_distance_sets_error() -> void:
	var s = _uniform_settings(-0.1)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# Happy-path: output shape and required streams present
# ---------------------------------------------------------------------------

func test_uniform_grid_produces_output_no_error() -> void:
	# One input point at origin with size (1,1,1), distance 0.5 -> 2x2x2 = 8 points.
	var s = _uniform_settings(0.5)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_output_has_density_stream() -> void:
	var s = _uniform_settings(0.5)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrDensity)).is_true()
	node.free()

func test_output_has_seed_stream() -> void:
	var s = _uniform_settings(0.5)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrSeed)).is_true()
	node.free()

func test_density_stream_all_ones() -> void:
	# Every density value must be exactly 1.0.
	var s = _uniform_settings(0.5)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream(FlowData.AttrDensity)
	assert_object(density_stream).is_not_null()
	var density_container : PackedFloat32Array = density_stream.container
	assert_int(density_container.size()).is_greater(0)
	for i in range(density_container.size()):
		assert_float(density_container[i]).is_equal(1.0)
	node.free()

func test_seed_stream_size_matches_density_stream() -> void:
	# The seed stream must have the same length as the density stream (= num output points).
	var s = _uniform_settings(0.5)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream(FlowData.AttrDensity)
	var seed_stream = out.findStream(FlowData.AttrSeed)
	assert_object(density_stream).is_not_null()
	assert_object(seed_stream).is_not_null()
	assert_int(seed_stream.container.size()).is_equal(density_stream.container.size())
	node.free()

func test_seed_stream_matches_point_seed_formula() -> void:
	# Verify seed values computed against FlowData.point_seed(pos, node_seed).
	var s = _uniform_settings(0.5)
	s.random_seed = 42
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	var seed_stream = out.findStream(FlowData.AttrSeed)
	assert_object(pos_stream).is_not_null()
	assert_object(seed_stream).is_not_null()
	var pos_container : PackedVector3Array = pos_stream.container
	var seed_container : PackedInt32Array = seed_stream.container
	assert_int(pos_container.size()).is_equal(seed_container.size())
	for i in range(pos_container.size()):
		var expected_seed = FlowData.point_seed(pos_container[i], 42)
		assert_int(seed_container[i]).is_equal(expected_seed)
	node.free()

func test_seed_changes_with_different_random_seed_setting() -> void:
	# Two runs with different random_seed in settings must produce different seed streams.
	var positions = PackedVector3Array([Vector3(1, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])

	var s1 = _uniform_settings(0.5)
	s1.random_seed = 1
	var d1 = _make_volume_input(positions, sizes)
	var node1 = _run([d1], s1)

	var s2 = _uniform_settings(0.5)
	s2.random_seed = 99999
	var d2 = _make_volume_input(positions, sizes)
	var node2 = _run([d2], s2)

	assert_str(node1.err).is_empty()
	assert_str(node2.err).is_empty()
	var out1 = _output(node1)
	var out2 = _output(node2)
	assert_object(out1).is_not_null()
	assert_object(out2).is_not_null()
	var seeds1 : PackedInt32Array = out1.findStream(FlowData.AttrSeed).container
	var seeds2 : PackedInt32Array = out2.findStream(FlowData.AttrSeed).container
	# With different seeds and same position the values should differ for at least one point.
	var any_differ = false
	for i in range(mini(seeds1.size(), seeds2.size())):
		if seeds1[i] != seeds2[i]:
			any_differ = true
			break
	assert_bool(any_differ).is_true()
	node1.free()
	node2.free()

func test_uniform_grid_output_point_count() -> void:
	# One input point, size (1,1,1), distance 0.5 -> floor(1/0.5)=2 per axis -> 2*2*2=8 points.
	var s = _uniform_settings(0.5)
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# 2 steps per axis = 8 points total
	assert_int(out.size()).is_equal(8)
	node.free()

func test_empty_input_data_produces_density_and_seed_streams() -> void:
	# Input data with 0 points: parent adds density/seed and returns cleanly (no error).
	var s = _uniform_settings(0.5)
	var d = FlowDataScript.Data.new()
	d.addCommonStreams(0)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrDensity)).is_true()
	assert_bool(out.hasStream(FlowData.AttrSeed)).is_true()
	node.free()

func test_quasi_random_2d_produces_output_no_error() -> void:
	var s = VolumeSamplerSettings.new()
	s.distribution = SamplePointsNodeSettings.eDistribution.QuasiRandom2D
	var g1: Array[int] = [8]
	s.groups = g1
	s.phase = 0.0
	s.size = 1.0
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(2, 2, 2)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrDensity)).is_true()
	assert_bool(out.hasStream(FlowData.AttrSeed)).is_true()
	node.free()

func test_quasi_random_2d_point_count_matches_groups_sum() -> void:
	# groups = [5, 3] -> 8 points per input point; 2 input points -> 16 total.
	var s = VolumeSamplerSettings.new()
	s.distribution = SamplePointsNodeSettings.eDistribution.QuasiRandom2D
	var g2: Array[int] = [5, 3]
	s.groups = g2
	s.phase = 0.0
	s.size = 1.0
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0)])
	var sizes = PackedVector3Array([Vector3(2, 2, 2), Vector3(2, 2, 2)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# 8 samples per input point, 2 input points = 16
	assert_int(out.size()).is_equal(16)
	node.free()

func test_quasi_random_3d_produces_output_no_error() -> void:
	var s = VolumeSamplerSettings.new()
	s.distribution = SamplePointsNodeSettings.eDistribution.QuasiRandom3D
	var g3: Array[int] = [4]
	s.groups = g3
	s.phase = 0.0
	s.size = 1.0
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrDensity)).is_true()
	assert_bool(out.hasStream(FlowData.AttrSeed)).is_true()
	node.free()

func test_multiple_input_points_uniform_grid_accumulates_output() -> void:
	# Two input points each size (1,1,1), distance 0.5 -> 2*8 = 16 output points.
	var s = _uniform_settings(0.5)
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var d = _make_volume_input(positions, sizes)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(16)
	node.free()
