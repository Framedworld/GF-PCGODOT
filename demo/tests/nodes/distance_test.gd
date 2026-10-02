# distance_test.gd
class_name DistanceTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DistanceNode = preload("res://addons/flow_nodes_editor/nodes/distance.gd")
const DistanceSettings = preload("res://addons/flow_nodes_editor/nodes/distance_settings.gd")

func _make_vector_data(stream_name: String, vectors: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, vectors, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> DistanceNode:
	var node = DistanceNode.new()
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

func test_basic_distance() -> void:
	var s = DistanceSettings.new()
	s.in_nameA = "position"
	s.in_nameB = "position"
	s.out_name = "distance"
	s.max_distance = 0.0

	var pts_a := PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0)])
	var pts_b := PackedVector3Array([Vector3(1, 0, 0)])

	var node = _run([
		_make_vector_data("position", pts_a),
		_make_vector_data("position", pts_b)
	], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("distance")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(2.0, 0.001)

func test_distance_normalized_by_max_distance() -> void:
	var s = DistanceSettings.new()
	s.in_nameA = "position"
	s.in_nameB = "position"
	s.out_name = "dist_norm"
	s.max_distance = 10.0

	var pts_a := PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0)])
	var pts_b := PackedVector3Array([Vector3(0, 0, 0)])

	var node = _run([
		_make_vector_data("position", pts_a),
		_make_vector_data("position", pts_b)
	], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("dist_norm")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(0.5, 0.001)

func test_empty_input_a_passes_through() -> void:
	var s = DistanceSettings.new()
	s.in_nameA = "position"
	s.in_nameB = "position"
	s.out_name = "distance"

	var node = _run([null, _make_vector_data("position", PackedVector3Array([Vector3(0, 0, 0)]))], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("distance")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(0)

func test_empty_b_set_fills_with_ones() -> void:
	var s = DistanceSettings.new()
	s.in_nameA = "position"
	s.in_nameB = "position"
	s.out_name = "distance"

	var pts_a := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var empty_b := FlowDataScript.Data.new()

	var node = _run([
		_make_vector_data("position", pts_a),
		empty_b
	], s)

	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("distance")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_float(stream.container[0]).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(1.0, 0.001)

func test_missing_target_port_errors() -> void:
	var s = DistanceSettings.new()
	s.in_nameA = "position"
	s.in_nameB = "position"
	s.out_name = "distance"

	var pts_a := PackedVector3Array([Vector3(0, 0, 0)])

	var node = _run([_make_vector_data("position", pts_a), null], s)

	assert_str(node.err).is_not_empty()

func test_empty_out_name_errors() -> void:
	var s = DistanceSettings.new()
	s.in_nameA = "position"
	s.in_nameB = "position"
	s.out_name = ""

	var pts_a := PackedVector3Array([Vector3(0, 0, 0)])
	var pts_b := PackedVector3Array([Vector3(1, 0, 0)])

	var node = _run([
		_make_vector_data("position", pts_a),
		_make_vector_data("position", pts_b)
	], s)

	assert_str(node.err).is_not_empty()
