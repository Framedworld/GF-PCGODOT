# reduce_test.gd
class_name ReduceTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ReduceNode = preload("res://addons/flow_nodes_editor/nodes/reduce.gd")
const ReduceSettings = preload("res://addons/flow_nodes_editor/nodes/reduce_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> ReduceNode:
	var node = ReduceNode.new()
	node.name = "test_reduce"
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

func test_reduce_floats() -> void:
	var s = ReduceSettings.new()
	s.in_name = "values"
	s.out_prefix = "values"
	var node = _run([
		_make_data("values", PackedFloat32Array([1.0, 3.0, 2.0, 5.0, 4.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var smin = out.findStream("values_min")
	var smax = out.findStream("values_max")
	var savg = out.findStream("values_avg")
	assert_object(smin).is_not_null()
	assert_object(smax).is_not_null()
	assert_object(savg).is_not_null()
	assert_float(smin.container[0]).is_equal(1.0)
	assert_float(smax.container[0]).is_equal(5.0)
	assert_float(savg.container[0]).is_equal_approx(3.0, 0.001)
	node.free()

func test_reduce_ints() -> void:
	var s = ReduceSettings.new()
	s.in_name = "counts"
	s.out_prefix = "counts"
	var node = _run([
		_make_data("counts", PackedInt32Array([10, 20, 30, 40]), FlowDataScript.DataType.Int)
	], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var smin = out.findStream("counts_min")
	var smax = out.findStream("counts_max")
	var savg = out.findStream("counts_avg")
	assert_object(smin).is_not_null()
	assert_object(smax).is_not_null()
	assert_object(savg).is_not_null()
	assert_int(smin.container[0]).is_equal(10)
	assert_int(smax.container[0]).is_equal(40)
	assert_float(savg.container[0]).is_equal_approx(25.0, 0.001)
	node.free()

func test_reduce_vectors() -> void:
	var s = ReduceSettings.new()
	s.in_name = "pos"
	s.out_prefix = "pos"
	var node = _run([
		_make_data("pos", PackedVector3Array([
			Vector3(1.0, 2.0, 3.0),
			Vector3(3.0, 0.0, 1.0),
			Vector3(2.0, 4.0, 2.0)
		]), FlowDataScript.DataType.Vector)
	], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var smin = out.findStream("pos_min")
	var smax = out.findStream("pos_max")
	var savg = out.findStream("pos_avg")
	assert_object(smin).is_not_null()
	assert_object(smax).is_not_null()
	assert_object(savg).is_not_null()
	var vmin: Vector3 = smin.container[0]
	var vmax: Vector3 = smax.container[0]
	var vavg: Vector3 = savg.container[0]
	assert_float(vmin.x).is_equal_approx(1.0, 0.001)
	assert_float(vmin.y).is_equal_approx(0.0, 0.001)
	assert_float(vmin.z).is_equal_approx(1.0, 0.001)
	assert_float(vmax.x).is_equal_approx(3.0, 0.001)
	assert_float(vmax.y).is_equal_approx(4.0, 0.001)
	assert_float(vmax.z).is_equal_approx(3.0, 0.001)
	assert_float(vavg.x).is_equal_approx(2.0, 0.001)
	assert_float(vavg.y).is_equal_approx(2.0, 0.001)
	assert_float(vavg.z).is_equal_approx(2.0, 0.001)
	node.free()

func test_single_element_float() -> void:
	var s = ReduceSettings.new()
	s.in_name = "v"
	s.out_prefix = "v"
	var node = _run([
		_make_data("v", PackedFloat32Array([7.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_float(out.findStream("v_min").container[0]).is_equal_approx(7.0, 0.001)
	assert_float(out.findStream("v_max").container[0]).is_equal_approx(7.0, 0.001)
	assert_float(out.findStream("v_avg").container[0]).is_equal_approx(7.0, 0.001)
	node.free()

func test_empty_input_produces_empty_data() -> void:
	var s = ReduceSettings.new()
	s.in_name = "vals"
	s.out_prefix = "vals"
	var empty_data = FlowDataScript.Data.new()
	empty_data.registerStream("vals", PackedFloat32Array([]), FlowDataScript.DataType.Float)
	var node = _run([empty_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.findStream("vals_min") == null).is_true()
	node.free()

func test_out_prefix_default_from_in_name() -> void:
	var s = ReduceSettings.new()
	s.in_name = "my_attr"
	var node = _run([
		_make_data("my_attr", PackedFloat32Array([2.0, 4.0, 6.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("my_attr_min")).is_not_null()
	assert_object(out.findStream("my_attr_max")).is_not_null()
	assert_object(out.findStream("my_attr_avg")).is_not_null()
	node.free()

func test_error_missing_in_name() -> void:
	var s = ReduceSettings.new()
	var node = _run([
		_make_data("vals", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_error_missing_input() -> void:
	var s = ReduceSettings.new()
	s.in_name = "vals"
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_error_stream_not_found() -> void:
	var s = ReduceSettings.new()
	s.in_name = "nonexistent"
	var node = _run([
		_make_data("other", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_error_unsupported_type_color() -> void:
	var s = ReduceSettings.new()
	s.in_name = "colors"
	var node = _run([
		_make_data("colors", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)
	], s)
	assert_str(node.err).is_not_empty()
	node.free()
