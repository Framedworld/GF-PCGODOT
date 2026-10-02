# bounds_modifier_test.gd
class_name BoundsModifierTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const BoundsModifierNode = preload("res://addons/flow_nodes_editor/nodes/bounds_modifier.gd")
const BoundsModifierSettings = preload("res://addons/flow_nodes_editor/nodes/bounds_modifier_settings.gd")

func _make_point_data(sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _make_point_data_with_bounds(bmin: PackedVector3Array, bmax: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrBoundsMin, bmin, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrBoundsMax, bmax, FlowDataScript.DataType.Vector)
	return d

func _run(in_data: FlowData.Data, s: BoundsModifierNodeSettings) -> BoundsModifierNode:
	var node = BoundsModifierNode.new()
	node.name = "bounds_modifier_test_node"
	node.settings = s
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: BoundsModifierNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_symmetric_set_mode() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Set
	s.output_mode = BoundsModifierNodeSettings.eOutput.SymmetricSize
	s.bounds_min = Vector3(-1.0, -2.0, -3.0)
	s.bounds_max = Vector3(1.0, 2.0, 3.0)
	var in_data = _make_point_data(PackedVector3Array([Vector3(0.5, 0.5, 0.5), Vector3(1.0, 1.0, 1.0)]))
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrSize)
	assert_object(stream).is_not_null()
	var expected_size = (s.bounds_max - s.bounds_min).abs()
	assert_array(stream.container).is_equal(PackedVector3Array([expected_size, expected_size]))

func test_symmetric_add_mode() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Add
	s.output_mode = BoundsModifierNodeSettings.eOutput.SymmetricSize
	s.bounds_min = Vector3(-0.5, -0.5, -0.5)
	s.bounds_max = Vector3(0.5, 0.5, 0.5)
	var in_data = _make_point_data(PackedVector3Array([Vector3(1.0, 2.0, 3.0)]))
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrSize)
	assert_object(stream).is_not_null()
	var delta = (s.bounds_max - s.bounds_min).abs()
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(1.0, 2.0, 3.0) + delta]))

func test_symmetric_multiply_mode() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Multiply
	s.output_mode = BoundsModifierNodeSettings.eOutput.SymmetricSize
	s.bounds_min = Vector3(-1.0, -2.0, -1.5)
	s.bounds_max = Vector3(1.0, 2.0, 1.5)
	var in_data = _make_point_data(PackedVector3Array([Vector3(2.0, 1.0, 4.0)]))
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrSize)
	assert_object(stream).is_not_null()
	var scale = (s.bounds_max - s.bounds_min).abs()
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(2.0, 1.0, 4.0) * scale]))

func test_per_point_bounds_set_mode() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Set
	s.output_mode = BoundsModifierNodeSettings.eOutput.PerPointBounds
	s.bounds_min = Vector3(-2.0, -2.0, -2.0)
	s.bounds_max = Vector3(2.0, 2.0, 2.0)
	var in_data = _make_point_data(PackedVector3Array([Vector3(1.0, 1.0, 1.0), Vector3(3.0, 3.0, 3.0)]))
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var bmin_stream = out.findStream(FlowData.AttrBoundsMin)
	var bmax_stream = out.findStream(FlowData.AttrBoundsMax)
	assert_object(bmin_stream).is_not_null()
	assert_object(bmax_stream).is_not_null()
	assert_array(bmin_stream.container).is_equal(PackedVector3Array([s.bounds_min, s.bounds_min]))
	assert_array(bmax_stream.container).is_equal(PackedVector3Array([s.bounds_max, s.bounds_max]))

func test_per_point_bounds_add_mode() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Add
	s.output_mode = BoundsModifierNodeSettings.eOutput.PerPointBounds
	s.bounds_min = Vector3(-1.0, -1.0, -1.0)
	s.bounds_max = Vector3(1.0, 1.0, 1.0)
	var base_min = PackedVector3Array([Vector3(-0.5, -0.5, -0.5)])
	var base_max = PackedVector3Array([Vector3(0.5, 0.5, 0.5)])
	var in_data = _make_point_data_with_bounds(base_min, base_max)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var bmin_stream = out.findStream(FlowData.AttrBoundsMin)
	var bmax_stream = out.findStream(FlowData.AttrBoundsMax)
	assert_object(bmin_stream).is_not_null()
	assert_object(bmax_stream).is_not_null()
	assert_array(bmin_stream.container).is_equal(PackedVector3Array([base_min[0] + s.bounds_min]))
	assert_array(bmax_stream.container).is_equal(PackedVector3Array([base_max[0] + s.bounds_max]))

func test_per_point_bounds_multiply_mode() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Multiply
	s.output_mode = BoundsModifierNodeSettings.eOutput.PerPointBounds
	s.bounds_min = Vector3(2.0, 2.0, 2.0)
	s.bounds_max = Vector3(3.0, 3.0, 3.0)
	var base_min = PackedVector3Array([Vector3(-1.0, -1.0, -1.0)])
	var base_max = PackedVector3Array([Vector3(1.0, 1.0, 1.0)])
	var in_data = _make_point_data_with_bounds(base_min, base_max)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var bmin_stream = out.findStream(FlowData.AttrBoundsMin)
	var bmax_stream = out.findStream(FlowData.AttrBoundsMax)
	assert_object(bmin_stream).is_not_null()
	assert_object(bmax_stream).is_not_null()
	assert_array(bmin_stream.container).is_equal(PackedVector3Array([base_min[0] * s.bounds_min]))
	assert_array(bmax_stream.container).is_equal(PackedVector3Array([base_max[0] * s.bounds_max]))

func test_missing_input_error() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Set
	s.output_mode = BoundsModifierNodeSettings.eOutput.SymmetricSize
	var node = BoundsModifierNode.new()
	node.name = "bounds_modifier_test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()

func test_symmetric_missing_size_stream_error() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Set
	s.output_mode = BoundsModifierNodeSettings.eOutput.SymmetricSize
	s.bounds_min = Vector3(-1.0, -1.0, -1.0)
	s.bounds_max = Vector3(1.0, 1.0, 1.0)
	var in_data = FlowDataScript.Data.new()
	var node = _run(in_data, s)
	assert_str(node.err).is_not_empty()

func test_per_point_bounds_empty_data() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Set
	s.output_mode = BoundsModifierNodeSettings.eOutput.PerPointBounds
	s.bounds_min = Vector3(-1.0, -1.0, -1.0)
	s.bounds_max = Vector3(1.0, 1.0, 1.0)
	var in_data = FlowDataScript.Data.new()
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

func test_symmetric_asymmetric_bounds_collapses_to_abs_extent() -> void:
	var s = BoundsModifierSettings.new()
	s.mode = BoundsModifierNodeSettings.eMode.Set
	s.output_mode = BoundsModifierNodeSettings.eOutput.SymmetricSize
	s.bounds_min = Vector3(-3.0, -1.0, -2.0)
	s.bounds_max = Vector3(1.0, 3.0, 2.0)
	var in_data = _make_point_data(PackedVector3Array([Vector3(0.5, 0.5, 0.5)]))
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrSize)
	assert_object(stream).is_not_null()
	var expected = (s.bounds_max - s.bounds_min).abs()
	assert_array(stream.container).is_equal(PackedVector3Array([expected]))
