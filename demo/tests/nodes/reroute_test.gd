# reroute_test.gd
class_name RerouteTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const RerouteNode = preload("res://addons/flow_nodes_editor/nodes/reroute.gd")
# No separate settings file

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array) -> RerouteNode:
	var node = RerouteNode.new()
	node.name = "test_reroute"
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

func test_passthrough_float_stream() -> void:
	var values := PackedFloat32Array([1.0, 2.0, 3.0])
	var in_data = _make_data("density", values, FlowDataScript.DataType.Float)
	var node = _run([in_data])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.0001)
	assert_float(stream.container[1]).is_equal_approx(2.0, 0.0001)
	assert_float(stream.container[2]).is_equal_approx(3.0, 0.0001)
	node.free()

func test_passthrough_vector_stream() -> void:
	var values := PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	var in_data = _make_data("position", values, FlowDataScript.DataType.Vector)
	var node = _run([in_data])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("position")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_bool(stream.container[0].is_equal_approx(Vector3(1, 2, 3))).is_true()
	assert_bool(stream.container[1].is_equal_approx(Vector3(4, 5, 6))).is_true()
	node.free()

func test_passthrough_int_stream() -> void:
	var values := PackedInt32Array([10, 20, 30, 40])
	var in_data = _make_data("point_id", values, FlowDataScript.DataType.Int)
	var node = _run([in_data])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("point_id")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	assert_int(stream.container[0]).is_equal(10)
	assert_int(stream.container[3]).is_equal(40)
	node.free()

func test_passthrough_color_stream() -> void:
	var values := PackedColorArray([Color(1, 0, 0, 1), Color(0, 1, 0, 1)])
	var in_data = _make_data("tint", values, FlowDataScript.DataType.Color)
	var node = _run([in_data])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("tint")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_bool(stream.container[0].is_equal_approx(Color(1, 0, 0, 1))).is_true()
	assert_bool(stream.container[1].is_equal_approx(Color(0, 1, 0, 1))).is_true()
	node.free()

func test_passthrough_multiple_streams() -> void:
	var in_data = FlowDataScript.Data.new()
	in_data.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	in_data.registerStream("density", PackedFloat32Array([0.5, 0.9]), FlowDataScript.DataType.Float)
	in_data.registerStream("id", PackedInt32Array([0, 1]), FlowDataScript.DataType.Int)
	var node = _run([in_data])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("position")).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("id")).is_not_null()
	node.free()

func test_no_input_produces_empty_data() -> void:
	var node = _run([null])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_passthrough_single_element() -> void:
	var values := PackedFloat32Array([42.0])
	var in_data = _make_data("val", values, FlowDataScript.DataType.Float)
	var node = _run([in_data])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("val")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(42.0, 0.0001)
	node.free()

func test_passthrough_large_float_array() -> void:
	var values := PackedFloat32Array()
	values.resize(1000)
	for i in range(1000):
		values[i] = float(i) * 0.1
	var in_data = _make_data("big", values, FlowDataScript.DataType.Float)
	var node = _run([in_data])
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("big")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1000)
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.0001)
	assert_float(stream.container[999]).is_equal_approx(99.9, 0.01)
	node.free()
