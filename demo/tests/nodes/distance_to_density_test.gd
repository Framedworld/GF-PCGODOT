# distance_to_density_test.gd
class_name DistanceToDensityTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DistanceToDensityNode = preload("res://addons/flow_nodes_editor/nodes/distance_to_density.gd")
const DistanceToDensitySettings = preload("res://addons/flow_nodes_editor/nodes/distance_to_density_settings.gd")

func _make_point_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> DistanceToDensityNode:
	var node = DistanceToDensityNode.new()
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

func test_basic_density_mapping() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 0.0
	s.max_distance = 10.0
	s.min_density = 0.0
	s.max_density = 1.0
	s.invert = false
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(5.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.001)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.001)

func test_invert_flag_reverses_density() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 0.0
	s.max_distance = 10.0
	s.min_density = 0.0
	s.max_density = 1.0
	s.invert = true
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(5.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.001)
	assert_float(stream.container[2]).is_equal_approx(0.0, 0.001)

func test_points_closer_than_min_distance_get_min_density() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 5.0
	s.max_distance = 10.0
	s.min_density = 0.2
	s.max_density = 0.8
	s.invert = false
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
		Vector3(4.9, 0.0, 0.0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.2, 0.001)
	assert_float(stream.container[1]).is_equal_approx(0.2, 0.001)
	assert_float(stream.container[2]).is_equal_approx(0.2, 0.001)

func test_points_farther_than_max_distance_get_max_density() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 0.0
	s.max_distance = 5.0
	s.min_density = 0.0
	s.max_density = 1.0
	s.invert = false
	var positions = PackedVector3Array([
		Vector3(6.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		Vector3(100.0, 0.0, 0.0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.001)

func test_non_zero_reference_position() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3(5.0, 0.0, 0.0)
	s.min_distance = 0.0
	s.max_distance = 10.0
	s.min_density = 0.0
	s.max_density = 1.0
	s.invert = false
	var positions = PackedVector3Array([
		Vector3(5.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		Vector3(15.0, 0.0, 0.0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.001)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.001)

func test_zero_distance_range_does_not_crash() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 5.0
	s.max_distance = 5.0
	s.min_density = 0.0
	s.max_density = 1.0
	s.invert = false
	var positions = PackedVector3Array([
		Vector3(3.0, 0.0, 0.0),
		Vector3(5.0, 0.0, 0.0),
		Vector3(8.0, 0.0, 0.0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)

func test_single_point() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 0.0
	s.max_distance = 10.0
	s.min_density = 0.0
	s.max_density = 1.0
	s.invert = false
	var positions = PackedVector3Array([Vector3(5.0, 0.0, 0.0)])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(0.5, 0.001)

func test_custom_density_range() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 0.0
	s.max_distance = 10.0
	s.min_density = 2.0
	s.max_density = 5.0
	s.invert = false
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(2.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(5.0, 0.001)

func test_missing_input_sets_error() -> void:
	var s = DistanceToDensitySettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_missing_position_stream_sets_error() -> void:
	var s = DistanceToDensitySettings.new()
	var d := FlowDataScript.Data.new()
	d.registerStream("some_other_attr", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_output_preserves_input_streams() -> void:
	var s = DistanceToDensitySettings.new()
	s.reference_position = Vector3.ZERO
	s.min_distance = 0.0
	s.max_distance = 10.0
	s.min_density = 0.0
	s.max_density = 1.0
	s.invert = false
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)]), FlowDataScript.DataType.Vector)
	d.registerStream("color", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var color_stream = out.findStream("color")
	assert_object(color_stream).is_not_null()
	assert_int(color_stream.container.size()).is_equal(2)
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_int(density_stream.container.size()).is_equal(2)
