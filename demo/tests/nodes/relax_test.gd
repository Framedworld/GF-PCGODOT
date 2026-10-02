# relax_test.gd
class_name RelaxTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const RelaxNode = preload("res://addons/flow_nodes_editor/nodes/relax.gd")
const RelaxSettings = preload("res://addons/flow_nodes_editor/nodes/relax_settings.gd")

func _make_point_data(positions: PackedVector3Array, sizes: PackedVector3Array = PackedVector3Array()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	if sizes.size() > 0:
		d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings: RelaxSettings) -> RelaxNode:
	var node = RelaxNode.new()
	node.name = "relax_test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: RelaxNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_null_input_sets_error() -> void:
	var s = RelaxSettings.new()
	s.num_iterations = 1
	s.strength = 0.5
	s.padding = 0.0
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_missing_position_stream_sets_error() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("some_other_stream", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var s = RelaxSettings.new()
	s.num_iterations = 1
	s.strength = 0.5
	s.padding = 0.0
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_well_separated_points_unchanged() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(10.0, 0.0, 0.0),
		Vector3(0.0, 10.0, 0.0),
	])
	var sizes = PackedVector3Array([
		Vector3.ONE,
		Vector3.ONE,
		Vector3.ONE,
	])
	var s = RelaxSettings.new()
	s.num_iterations = 5
	s.strength = 1.0
	s.padding = 0.0
	var node = _run([_make_point_data(positions, sizes)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrPosition)
	assert_object(stream).is_not_null()
	var result : PackedVector3Array = stream.container
	assert_int(result.size()).is_equal(3)
	assert_float(result[0].distance_to(positions[0])).is_less(0.001)
	assert_float(result[1].distance_to(positions[1])).is_less(0.001)
	assert_float(result[2].distance_to(positions[2])).is_less(0.001)

func test_overlapping_points_pushed_apart() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.1, 0.0, 0.0),
	])
	var sizes = PackedVector3Array([
		Vector3.ONE,
		Vector3.ONE,
	])
	var s = RelaxSettings.new()
	s.num_iterations = 20
	s.strength = 1.0
	s.padding = 0.0
	var node = _run([_make_point_data(positions, sizes)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrPosition)
	assert_object(stream).is_not_null()
	var result : PackedVector3Array = stream.container
	assert_int(result.size()).is_equal(2)
	var dist = result[0].distance_to(result[1])
	assert_float(dist).is_greater(0.1)

func test_padding_increases_separation() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.8, 0.0, 0.0),
	])
	var sizes = PackedVector3Array([
		Vector3.ONE,
		Vector3.ONE,
	])
	var s_no_padding = RelaxSettings.new()
	s_no_padding.num_iterations = 20
	s_no_padding.strength = 1.0
	s_no_padding.padding = 0.0
	var node_no_pad = _run([_make_point_data(positions, sizes)], s_no_padding)
	assert_str(node_no_pad.err).is_empty()
	var out_no_pad = _output(node_no_pad)
	var stream_no_pad = out_no_pad.findStream(FlowData.AttrPosition)
	var result_no_pad : PackedVector3Array = stream_no_pad.container
	var dist_no_pad = result_no_pad[0].distance_to(result_no_pad[1])

	var s_padding = RelaxSettings.new()
	s_padding.num_iterations = 20
	s_padding.strength = 1.0
	s_padding.padding = 1.0
	var node_pad = _run([_make_point_data(positions, sizes)], s_padding)
	assert_str(node_pad.err).is_empty()
	var out_pad = _output(node_pad)
	var stream_pad = out_pad.findStream(FlowData.AttrPosition)
	var result_pad : PackedVector3Array = stream_pad.container
	var dist_pad = result_pad[0].distance_to(result_pad[1])

	assert_float(dist_pad).is_greater(dist_no_pad - 0.001)

func test_output_preserves_other_streams() -> void:
	var positions = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.05, 0.0, 0.0),
	])
	var sizes = PackedVector3Array([Vector3.ONE, Vector3.ONE])
	var d = _make_point_data(positions, sizes)
	d.registerStream("density", PackedFloat32Array([0.8, 0.4]), FlowDataScript.DataType.Float)
	var s = RelaxSettings.new()
	s.num_iterations = 5
	s.strength = 0.5
	s.padding = 0.0
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_array(density_stream.container).is_equal(PackedFloat32Array([0.8, 0.4]))
