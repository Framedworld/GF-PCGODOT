# get_loop_index_test.gd
class_name GetLoopIndexTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GetLoopIndexNode = preload("res://addons/flow_nodes_editor/nodes/get_loop_index.gd")
const GetLoopIndexSettings = preload("res://addons/flow_nodes_editor/nodes/get_loop_index_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> GetLoopIndexNode:
	var node = GetLoopIndexNode.new()
	node.name = "test_get_loop_index"
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

func test_default_start_index_zero() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "loop_index"
	s.start_index = 0
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("loop_index")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_int(stream.container[0]).is_equal(0)
	assert_int(stream.container[1]).is_equal(1)
	assert_int(stream.container[2]).is_equal(2)

func test_custom_start_index() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "idx"
	s.start_index = 5
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2,0,0), Vector3(3,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("idx")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	assert_int(stream.container[0]).is_equal(5)
	assert_int(stream.container[1]).is_equal(6)
	assert_int(stream.container[2]).is_equal(7)
	assert_int(stream.container[3]).is_equal(8)

func test_negative_start_index() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "loop_index"
	s.start_index = -3
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("loop_index")
	assert_object(stream).is_not_null()
	assert_int(stream.container[0]).is_equal(-3)
	assert_int(stream.container[1]).is_equal(-2)
	assert_int(stream.container[2]).is_equal(-1)

func test_single_point_input() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "loop_index"
	s.start_index = 0
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("loop_index")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_int(stream.container[0]).is_equal(0)

func test_input_streams_are_preserved() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "loop_index"
	s.start_index = 0
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	in_data.registerStream("density", PackedFloat32Array([0.1, 0.9]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("position")).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("loop_index")).is_not_null()

func test_missing_input_produces_error() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "loop_index"
	s.start_index = 0
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_empty_output_name_produces_error() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = ""
	s.start_index = 0
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()

func test_custom_output_name() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "my_custom_index"
	s.start_index = 10
	var in_data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("my_custom_index")).is_not_null()
	assert_object(out.findStream("loop_index")).is_null()
	var stream = out.findStream("my_custom_index")
	assert_int(stream.container[0]).is_equal(10)
	assert_int(stream.container[2]).is_equal(12)

func test_large_input_sequential_values() -> void:
	var s = GetLoopIndexSettings.new()
	s.out_name = "loop_index"
	s.start_index = 0
	var positions := PackedVector3Array()
	positions.resize(100)
	for i in range(100):
		positions[i] = Vector3(i, 0, 0)
	var in_data = _make_data("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("loop_index")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(100)
	assert_int(stream.container[0]).is_equal(0)
	assert_int(stream.container[99]).is_equal(99)
