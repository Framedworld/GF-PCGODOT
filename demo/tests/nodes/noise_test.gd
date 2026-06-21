# noise_test.gd
class_name NoiseTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const NoiseNode = preload("res://addons/flow_nodes_editor/nodes/noise.gd")
const NoiseSettings = preload("res://addons/flow_nodes_editor/nodes/noise_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _make_pos_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> NoiseNode:
	var node = NoiseNode.new()
	node.name = "test_noise"
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

func test_float_output_basic() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	s.output_type = NoiseSettings.eOutputType.Float
	s.mode = NoiseSettings.eMode.Override
	s.sample_space = NoiseSettings.eSampleSpace.World3D
	s.noise_type = NoiseSettings.eNoiseType.Value
	s.fractal_type = NoiseSettings.eFractalType.None
	s.in_scale = 1.0
	s.noise_bias = 0.0
	s.noise_amplitude = 1.0
	s.random_seed = 42

	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(1.0, 1.0, 1.0),
	])
	var in_data = _make_pos_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	for i in range(stream.container.size()):
		var v: float = stream.container[i]
		assert_bool(v >= 0.0 and v <= 1.0).is_true()
	node.free()

func test_float_output_xz2d() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	s.output_type = NoiseSettings.eOutputType.Float
	s.mode = NoiseSettings.eMode.Override
	s.sample_space = NoiseSettings.eSampleSpace.XZ2D
	s.noise_type = NoiseSettings.eNoiseType.Perlin
	s.fractal_type = NoiseSettings.eFractalType.None
	s.in_scale = 0.5
	s.noise_bias = 0.0
	s.noise_amplitude = 1.0
	s.random_seed = 7

	var positions = PackedVector3Array([
		Vector3(0.0, 5.0, 0.0),
		Vector3(1.0, 10.0, 1.0),
		Vector3(-1.0, 0.0, 2.0),
	])
	var in_data = _make_pos_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	node.free()

func test_vector3_output() -> void:
	var s = NoiseSettings.new()
	s.out_name = "offset"
	s.output_type = NoiseSettings.eOutputType.Vector3
	s.mode = NoiseSettings.eMode.Override
	s.sample_space = NoiseSettings.eSampleSpace.World3D
	s.noise_type = NoiseSettings.eNoiseType.Simplex
	s.fractal_type = NoiseSettings.eFractalType.None
	s.in_scale = 1.0
	s.noise_bias = 0.0
	s.noise_amplitude = 1.0
	s.random_seed = 99

	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(2.0, 3.0, 4.0),
	])
	var in_data = _make_pos_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("offset")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	var v0: Vector3 = stream.container[0]
	assert_bool(v0.x >= 0.0 and v0.x <= 1.0).is_true()
	assert_bool(v0.y >= 0.0 and v0.y <= 1.0).is_true()
	assert_bool(v0.z >= 0.0 and v0.z <= 1.0).is_true()
	node.free()

func test_add_mode_float() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	s.output_type = NoiseSettings.eOutputType.Float
	s.mode = NoiseSettings.eMode.Add
	s.sample_space = NoiseSettings.eSampleSpace.World3D
	s.noise_type = NoiseSettings.eNoiseType.Value
	s.fractal_type = NoiseSettings.eFractalType.None
	s.in_scale = 1.0
	s.noise_bias = 0.0
	s.noise_amplitude = 1.0
	s.random_seed = 1

	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 1.0, 1.0),
	])
	var in_data = _make_pos_data(positions)
	in_data.registerStream("density", PackedFloat32Array([0.5, 0.5]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	for i in range(stream.container.size()):
		var v: float = stream.container[i]
		assert_bool(v >= 0.5).is_true()
	node.free()

func test_fractal_fbm() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	s.output_type = NoiseSettings.eOutputType.Float
	s.mode = NoiseSettings.eMode.Override
	s.sample_space = NoiseSettings.eSampleSpace.World3D
	s.noise_type = NoiseSettings.eNoiseType.Perlin
	s.fractal_type = NoiseSettings.eFractalType.FBM
	s.fractal_octaves = 4
	s.fractal_lacunarity = 2.0
	s.fractal_gain = 0.5
	s.in_scale = 1.0
	s.noise_bias = 0.0
	s.noise_amplitude = 1.0
	s.random_seed = 10

	var positions = PackedVector3Array([
		Vector3(0.5, 0.5, 0.5),
		Vector3(1.5, 2.5, 0.1),
		Vector3(-1.0, 0.0, 3.0),
	])
	var in_data = _make_pos_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	node.free()

func test_bias_and_amplitude() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	s.output_type = NoiseSettings.eOutputType.Float
	s.mode = NoiseSettings.eMode.Override
	s.sample_space = NoiseSettings.eSampleSpace.World3D
	s.noise_type = NoiseSettings.eNoiseType.Value
	s.fractal_type = NoiseSettings.eFractalType.None
	s.in_scale = 1.0
	s.noise_bias = 2.0
	s.noise_amplitude = 0.0
	s.random_seed = 5

	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 2.0, 3.0),
		Vector3(-5.0, 0.0, 2.0),
	])
	var in_data = _make_pos_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	for i in range(stream.container.size()):
		var v: float = stream.container[i]
		assert_float(v).is_equal_approx(2.0, 0.0001)
	node.free()

func test_custom_sample_attribute() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	s.output_type = NoiseSettings.eOutputType.Float
	s.mode = NoiseSettings.eMode.Override
	s.sample_space = NoiseSettings.eSampleSpace.World3D
	s.noise_type = NoiseSettings.eNoiseType.Value
	s.fractal_type = NoiseSettings.eFractalType.None
	s.sample_attribute = "uv"
	s.in_scale = 1.0
	s.noise_bias = 0.0
	s.noise_amplitude = 1.0
	s.random_seed = 3

	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
	])
	var uv_coords = PackedVector3Array([
		Vector3(0.1, 0.2, 0.0),
		Vector3(0.9, 0.8, 0.0),
	])
	var in_data = _make_pos_data(positions)
	in_data.registerStream("uv", uv_coords, FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	node.free()

func test_missing_input_error() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	var out = _output(node)
	assert_object(out).is_null()
	node.free()

func test_single_element_array() -> void:
	var s = NoiseSettings.new()
	s.out_name = "density"
	s.output_type = NoiseSettings.eOutputType.Float
	s.mode = NoiseSettings.eMode.Override
	s.sample_space = NoiseSettings.eSampleSpace.World3D
	s.noise_type = NoiseSettings.eNoiseType.Value
	s.fractal_type = NoiseSettings.eFractalType.None
	s.in_scale = 1.0
	s.noise_bias = 0.0
	s.noise_amplitude = 1.0
	s.random_seed = 0

	var positions = PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var in_data = _make_pos_data(positions)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	node.free()
