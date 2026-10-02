# sequence_sample_test.gd
class_name SequenceSampleTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SequenceSampleNode = preload("res://addons/flow_nodes_editor/nodes/sequence_sample.gd")
const SequenceSampleSettings = preload("res://addons/flow_nodes_editor/nodes/sequence_sample_settings.gd")


func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d


func _run(inputs: Array, settings) -> SequenceSampleNode:
	var node = SequenceSampleNode.new()
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


func test_default_settings_returns_all_floats() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 0
	s.count = 0
	s.step = 1
	var values = PackedFloat32Array([10.0, 20.0, 30.0, 40.0, 50.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([10.0, 20.0, 30.0, 40.0, 50.0]))


func test_count_limits_output() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 0
	s.count = 3
	s.step = 1
	var values = PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))


func test_step_skips_elements() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 0
	s.count = 0
	s.step = 2
	var values = PackedFloat32Array([10.0, 20.0, 30.0, 40.0, 50.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([10.0, 30.0, 50.0]))


func test_start_offset() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 2
	s.count = 0
	s.step = 1
	var values = PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([3.0, 4.0, 5.0]))


func test_negative_start_counts_from_end() -> void:
	var s = SequenceSampleSettings.new()
	s.start = -2
	s.count = 0
	s.step = 1
	var values = PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([4.0, 5.0]))


func test_negative_step_walks_backwards() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 4
	s.count = 0
	s.step = -1
	var values = PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([5.0, 4.0, 3.0, 2.0, 1.0]))


func test_vector_stream_sampled_correctly() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 1
	s.count = 2
	s.step = 1
	var values = PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(2.0, 0.0, 0.0),
		Vector3(3.0, 0.0, 0.0),
	])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Vector)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)]))


func test_single_element_input() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 0
	s.count = 0
	s.step = 1
	var values = PackedFloat32Array([42.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([42.0]))


func test_start_beyond_bounds_returns_empty() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 10
	s.count = 0
	s.step = 1
	var values = PackedFloat32Array([1.0, 2.0, 3.0])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Float)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(0)


func test_missing_input_sets_error() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 0
	s.count = 0
	s.step = 1
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()


func test_int_stream_with_step_and_count() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 0
	s.count = 3
	s.step = 2
	var values = PackedInt32Array([100, 200, 300, 400, 500, 600, 700])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Int)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedInt32Array([100, 300, 500]))


func test_color_stream_sampled() -> void:
	var s = SequenceSampleSettings.new()
	s.start = 0
	s.count = 2
	s.step = 1
	var values = PackedColorArray([
		Color(1.0, 0.0, 0.0, 1.0),
		Color(0.0, 1.0, 0.0, 1.0),
		Color(0.0, 0.0, 1.0, 1.0),
	])
	var node = _run([_make_data("In", values, FlowDataScript.DataType.Color)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("In")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedColorArray([Color(1.0, 0.0, 0.0, 1.0), Color(0.0, 1.0, 0.0, 1.0)]))
