# remap_test.gd
class_name RemapTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const RemapNode = preload("res://addons/flow_nodes_editor/nodes/remap.gd")
const RemapSettings = preload("res://addons/flow_nodes_editor/nodes/remap_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
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

func _run(inputs: Array, settings) -> RemapNode:
	var node = RemapNode.new()
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
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_identity_curve_passthrough() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "out"
	s.remap_curve = _make_linear_curve()
	var values := PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	var node = _run([_make_data("density", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(5)
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.5, 0.01)
	assert_float(stream.container[4]).is_equal_approx(1.0, 0.01)
	node.free()

func test_invert_curve_flips_values() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "remapped"
	s.remap_curve = _make_invert_curve()
	var values := PackedFloat32Array([0.0, 0.5, 1.0])
	var node = _run([_make_data("density", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("remapped")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.0, 0.01)
	node.free()

func test_at_in_name_overwrites_source_attribute() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "@in_name"
	s.remap_curve = _make_constant_curve(0.5)
	var values := PackedFloat32Array([0.0, 0.2, 0.8])
	var node = _run([_make_data("density", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.5, 0.01)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.5, 0.01)
	node.free()

func test_custom_stream_name() -> void:
	var s := RemapSettings.new()
	s.in_name = "steepness"
	s.out_name = "steepness_remapped"
	s.remap_curve = _make_invert_curve()
	var values := PackedFloat32Array([0.0, 0.5, 1.0])
	var node = _run([_make_data("steepness", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("steepness_remapped")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(0.0, 0.01)
	node.free()

func test_broadcast_stream_expands_to_data_size() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "out"
	s.remap_curve = _make_invert_curve()
	var d := FlowDataScript.Data.new()
	var positions := PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)])
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	# Use density=0.0 so the invert curve maps to exactly 1.0 at the endpoint (no
	# cubic-interpolation ambiguity between control points).
	d.registerStream("density", PackedFloat32Array([0.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.01)
	assert_float(stream.container[1]).is_equal_approx(1.0, 0.01)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.01)
	node.free()

func test_other_streams_preserved_in_output() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "remapped"
	s.remap_curve = _make_linear_curve()
	var d := FlowDataScript.Data.new()
	d.registerStream("density", PackedFloat32Array([0.3, 0.7]), FlowDataScript.DataType.Float)
	d.registerStream("position", PackedVector3Array([Vector3(1,2,3), Vector3(4,5,6)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
	node.free()

func test_single_element_data() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "out"
	s.remap_curve = _make_invert_curve()
	var values := PackedFloat32Array([0.3])
	var node = _run([_make_data("density", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(0.784, 0.05)
	node.free()

func test_missing_input_sets_error() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "out"
	s.remap_curve = _make_linear_curve()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_stream_sets_error() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "out"
	s.remap_curve = _make_linear_curve()
	var d = _make_data("position", PackedVector3Array([Vector3(0,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_non_float_stream_sets_error() -> void:
	var s := RemapSettings.new()
	s.in_name = "density"
	s.out_name = "out"
	s.remap_curve = _make_linear_curve()
	var d = _make_data("density", PackedInt32Array([0, 1, 2]), FlowDataScript.DataType.Int)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()
