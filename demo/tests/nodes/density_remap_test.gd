# density_remap_test.gd
class_name DensityRemapTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DensityRemapNode = preload("res://addons/flow_nodes_editor/nodes/density_remap.gd")
const DensityRemapSettings = preload("res://addons/flow_nodes_editor/nodes/density_remap_settings.gd")

func _make_data_with_density(values: PackedFloat32Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("density", values, FlowDataScript.DataType.Float)
	return d

func _make_data_no_density(count: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var positions := PackedVector3Array()
	positions.resize(count)
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	return d

func _make_settings(in_min: float, in_max: float, out_min: float, out_max: float, clamp_to_output: bool) -> DensityRemapNodeSettings:
	var s := DensityRemapSettings.new()
	s.in_min = in_min
	s.in_max = in_max
	s.out_min = out_min
	s.out_max = out_max
	s.clamp_to_output_range = clamp_to_output
	return s

func _run(inputs: Array, settings) -> DensityRemapNode:
	var node = DensityRemapNode.new()
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

func test_identity_remap() -> void:
	var s := _make_settings(0.0, 1.0, 0.0, 1.0, false)
	var values := PackedFloat32Array([0.0, 0.5, 1.0])
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.0001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.0001)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.0001)

func test_invert_remap() -> void:
	var s := _make_settings(0.0, 1.0, 1.0, 0.0, false)
	var values := PackedFloat32Array([0.0, 0.5, 1.0])
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.0001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.0001)
	assert_float(stream.container[2]).is_equal_approx(0.0, 0.0001)

func test_scale_remap() -> void:
	var s := _make_settings(0.0, 1.0, 0.0, 2.0, false)
	var values := PackedFloat32Array([0.0, 0.25, 0.5, 1.0])
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.0001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.0001)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.0001)
	assert_float(stream.container[3]).is_equal_approx(2.0, 0.0001)

func test_clamp_enabled_clips_out_of_range() -> void:
	var s := _make_settings(0.0, 1.0, 0.0, 1.0, true)
	var values := PackedFloat32Array([-0.5, 0.5, 1.5])
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.0001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.0001)
	assert_float(stream.container[2]).is_equal_approx(1.0, 0.0001)

func test_clamp_disabled_allows_out_of_range() -> void:
	var s := _make_settings(0.0, 1.0, 0.0, 1.0, false)
	var values := PackedFloat32Array([-0.5, 1.5])
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(-0.5, 0.0001)
	assert_float(stream.container[1]).is_equal_approx(1.5, 0.0001)

func test_no_density_stream_defaults_to_one() -> void:
	var s := _make_settings(0.0, 1.0, 0.0, 2.0, false)
	var in_data := _make_data_no_density(3)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	for i in 3:
		assert_float(stream.container[i]).is_equal_approx(2.0, 0.0001)

func test_zero_range_in_does_not_divide_by_zero() -> void:
	var s := _make_settings(0.5, 0.5, 0.0, 1.0, false)
	var values := PackedFloat32Array([0.0, 0.5, 1.0])
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)

func test_missing_input_sets_error() -> void:
	var s := _make_settings(0.0, 1.0, 0.0, 1.0, true)
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_single_element_array() -> void:
	var s := _make_settings(0.0, 1.0, 10.0, 20.0, false)
	var values := PackedFloat32Array([0.5])
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(15.0, 0.0001)

func test_large_array_remap() -> void:
	var s := _make_settings(0.0, 1.0, -1.0, 1.0, true)
	var values := PackedFloat32Array()
	values.resize(1000)
	for i in 1000:
		values[i] = float(i) / 999.0
	var node = _run([_make_data_with_density(values)], s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1000)
	assert_float(stream.container[0]).is_equal_approx(-1.0, 0.0001)
	assert_float(stream.container[999]).is_equal_approx(1.0, 0.0001)
