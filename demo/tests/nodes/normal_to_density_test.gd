# normal_to_density_test.gd
class_name NormalToDensityTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const NormalToDensityNode = preload("res://addons/flow_nodes_editor/nodes/normal_to_density.gd")
const NormalToDensitySettings = preload("res://addons/flow_nodes_editor/nodes/normal_to_density_settings.gd")

func _make_data_with_normal(normals: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrNormal, normals, FlowDataScript.DataType.Vector)
	return d

func _make_data_with_rotation(rotations: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	return d

func _make_data_with_normal_and_density(normals: PackedVector3Array, densities: PackedFloat32Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrNormal, normals, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrDensity, densities, FlowDataScript.DataType.Float)
	return d

func _run(inputs: Array, settings) -> NormalToDensityNode:
	var node = NormalToDensityNode.new()
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

func _make_settings(compare: Vector3 = Vector3.UP, offset: float = 0.0, strength: float = 1.0, mode: int = NormalToDensityNodeSettings.eDensityMode.Set) -> NormalToDensitySettings:
	var s = NormalToDensitySettings.new()
	s.normal_to_compare = compare
	s.offset = offset
	s.strength = strength
	s.density_mode = mode
	return s

func test_normal_pointing_up_against_up_gives_density_one() -> void:
	var normals = PackedVector3Array([Vector3.UP, Vector3.UP])
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Set)
	var node = _run([_make_data_with_normal(normals)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(1.0, 0.001)

func test_normal_pointing_down_against_up_gives_density_zero() -> void:
	var normals = PackedVector3Array([Vector3.DOWN])
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Set)
	var node = _run([_make_data_with_normal(normals)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.001)

func test_rotation_fallback_used_when_no_normal_stream() -> void:
	var rotations = PackedVector3Array([Vector3.ZERO])
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Set)
	var node = _run([_make_data_with_rotation(rotations)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)

func test_missing_input_gives_error() -> void:
	var s = _make_settings()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_no_normal_no_rotation_gives_error() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	var s = _make_settings()
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_empty_input_passes_through_empty_output() -> void:
	var d := FlowDataScript.Data.new()
	var s = _make_settings()
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_density_mode_minimum_takes_lower_value() -> void:
	var normals = PackedVector3Array([Vector3.UP])
	var densities = PackedFloat32Array([0.3])
	var d = _make_data_with_normal_and_density(normals, densities)
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Minimum)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_float(stream.container[0]).is_equal_approx(0.3, 0.001)

func test_density_mode_maximum_takes_higher_value() -> void:
	var normals = PackedVector3Array([Vector3.DOWN])
	var densities = PackedFloat32Array([0.8])
	var d = _make_data_with_normal_and_density(normals, densities)
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Maximum)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_float(stream.container[0]).is_equal_approx(0.8, 0.001)

func test_density_mode_add_clamps_to_one() -> void:
	var normals = PackedVector3Array([Vector3.UP])
	var densities = PackedFloat32Array([0.8])
	var d = _make_data_with_normal_and_density(normals, densities)
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Add)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)

func test_density_mode_multiply_scales_density() -> void:
	var normals = PackedVector3Array([Vector3.UP])
	var densities = PackedFloat32Array([0.5])
	var d = _make_data_with_normal_and_density(normals, densities)
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Multiply)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_float(stream.container[0]).is_equal_approx(0.5, 0.001)

func test_offset_shifts_alignment_result() -> void:
	var normals = PackedVector3Array([Vector3.RIGHT])
	var s = _make_settings(Vector3.UP, 0.5, 1.0, NormalToDensityNodeSettings.eDensityMode.Set)
	var node = _run([_make_data_with_normal(normals)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_float(stream.container[0]).is_equal_approx(0.5, 0.001)

func test_strength_applies_power_to_result() -> void:
	var normals = PackedVector3Array([Vector3(0.0, 0.707107, 0.707107).normalized()])
	var s = _make_settings(Vector3.UP, 0.0, 2.0, NormalToDensityNodeSettings.eDensityMode.Set)
	var node = _run([_make_data_with_normal(normals)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_float(stream.container[0]).is_equal_approx(0.5, 0.01)

func test_no_density_stream_defaults_to_one_for_multiply() -> void:
	var normals = PackedVector3Array([Vector3.UP])
	var d = _make_data_with_normal(normals)
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Multiply)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)

func test_large_array_processes_all_points() -> void:
	var count := 100
	var normals := PackedVector3Array()
	normals.resize(count)
	for i in range(count):
		normals[i] = Vector3.UP
	var s = _make_settings(Vector3.UP, 0.0, 1.0, NormalToDensityNodeSettings.eDensityMode.Set)
	var node = _run([_make_data_with_normal(normals)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream(FlowData.AttrDensity)
	assert_int(stream.container.size()).is_equal(count)
	for i in range(count):
		assert_float(stream.container[i]).is_equal_approx(1.0, 0.001)
