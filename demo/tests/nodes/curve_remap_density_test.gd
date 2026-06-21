# curve_remap_density_test.gd
class_name CurveRemapDensityTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const CurveRemapDensityNode = preload("res://addons/flow_nodes_editor/nodes/curve_remap_density.gd")
const CurveRemapDensitySettings = preload("res://addons/flow_nodes_editor/nodes/curve_remap_density_settings.gd")

func _make_data_with_density(densities: PackedFloat32Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrDensity, densities, FlowDataScript.DataType.Float)
	return d

func _make_data_no_density(count: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var positions := PackedVector3Array()
	positions.resize(count)
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _make_linear_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(1.0, 1.0))
	return c

func _make_invert_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c

func _make_constant_curve(value: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, value))
	c.add_point(Vector2(1.0, value))
	return c

func _run(input: FlowData.Data, curve) -> CurveRemapDensityNode:
	var node = CurveRemapDensityNode.new()
	node.name = "test_node"
	var s := CurveRemapDensitySettings.new()
	s.remap_curve = curve
	node.settings = s
	node.inputs = [input]
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: CurveRemapDensityNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_identity_curve_passthrough() -> void:
	var densities := PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	var input = _make_data_with_density(densities)
	var node = _run(input, _make_linear_curve())
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(5)
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.5, 0.01)
	assert_float(stream.container[4]).is_equal_approx(1.0, 0.01)
	node.free()

func test_invert_curve_flips_densities() -> void:
	var densities := PackedFloat32Array([0.0, 0.5, 1.0])
	var input = _make_data_with_density(densities)
	var node = _run(input, _make_invert_curve())
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.0, 0.01)
	node.free()

func test_constant_zero_curve_zeros_all_densities() -> void:
	var densities := PackedFloat32Array([0.2, 0.5, 0.9])
	var input = _make_data_with_density(densities)
	var node = _run(input, _make_constant_curve(0.0))
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.01)
	assert_float(stream.container[1]).is_equal_approx(0.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.0, 0.01)
	node.free()

func test_constant_one_curve_maxes_all_densities() -> void:
	var densities := PackedFloat32Array([0.0, 0.3, 0.7])
	var input = _make_data_with_density(densities)
	var node = _run(input, _make_constant_curve(1.0))
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.01)
	assert_float(stream.container[1]).is_equal_approx(1.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.01)
	node.free()

func test_null_curve_acts_as_identity() -> void:
	var densities := PackedFloat32Array([0.0, 0.5, 1.0])
	var input = _make_data_with_density(densities)
	var node = _run(input, null)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.01)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.01)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.01)
	node.free()

func test_no_density_stream_defaults_to_one() -> void:
	var input = _make_data_no_density(3)
	var node = _run(input, _make_constant_curve(0.5))
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0]).is_equal_approx(0.5, 0.01)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.5, 0.01)
	node.free()

func test_output_clamped_to_zero_one() -> void:
	var densities := PackedFloat32Array([0.0, 0.5, 1.0])
	var input = _make_data_with_density(densities)
	var c := Curve.new()
	c.add_point(Vector2(0.0, -0.5))
	c.add_point(Vector2(1.0, 1.5))
	var node = _run(input, c)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	for i in stream.container.size():
		assert_bool(stream.container[i] >= 0.0).is_true()
		assert_bool(stream.container[i] <= 1.0).is_true()
	node.free()

func test_missing_input_sets_error() -> void:
	var node = CurveRemapDensityNode.new()
	node.name = "test_node"
	var s := CurveRemapDensitySettings.new()
	node.settings = s
	node.inputs = [null]
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()
	node.free()

func test_single_element_data() -> void:
	var densities := PackedFloat32Array([0.3])
	var input = _make_data_with_density(densities)
	var node = _run(input, _make_invert_curve())
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream(FlowData.AttrDensity)
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(0.784, 0.05)
	node.free()

func test_other_streams_preserved_in_output() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrDensity, PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)
	d.registerStream(FlowData.AttrPosition, PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var node = _run(d, _make_linear_curve())
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
	node.free()
