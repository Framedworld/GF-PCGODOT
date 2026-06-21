# merge_points_test.gd
class_name MergePointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MergePointsNode = preload("res://addons/flow_nodes_editor/nodes/merge_points.gd")
const MergeNodeSettings = preload("res://addons/flow_nodes_editor/nodes/merge_settings.gd")

# Build a FlowData.Data with one or more streams.
# streams: { stream_name: [container, data_type], ... }
func _make_data(streams: Dictionary) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	for stream_name in streams:
		var info = streams[stream_name]
		d.registerStream(stream_name, info[0], info[1])
	return d

# Creates a fake source node (using MergePointsNode so set_output() is available)
# with one generated bulk per data entry, registers it in ctx, and returns it.
# Caller must free the returned node.
func _make_source_node(data_bulks: Array, ctx: FlowData.EvaluationContext) -> MergePointsNode:
	var src = MergePointsNode.new()
	src.name = "fake_source"
	src.num_generated_bulks = 0
	src.generated_bulks = []
	for bulk_data in data_bulks:
		src.set_output(0, bulk_data)
	ctx.gedit_nodes_by_name["fake_source"] = src
	return src

# Runs MergePointsNode with data_bulks fed into port 0 as a single multi-bulk source.
# Returns a Dictionary {"node": ..., "src": ...}; caller must free both.
func _run_with_bulks(data_bulks: Array) -> Dictionary:
	var node = MergePointsNode.new()
	node.name = "test_merge_points"
	node.settings = MergeNodeSettings.new()
	var _empty_deps: Array[Dictionary] = []
	node.deps = _empty_deps
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	ctx.gedit_nodes_by_name = {}
	ctx.eval_id = 0
	ctx.runtime_params = {}
	var src = _make_source_node(data_bulks, ctx)
	var _src_deps: Array[Dictionary] = [{
		"from_node": "fake_source",
		"from_port": 0,
		"to_port": 0,
		"virtual_variable": false
	}]
	node.deps = _src_deps
	node.preExecute(ctx)
	node.run(ctx)
	dummy.free()
	return {"node": node, "src": src}

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

# --- Tests ---

func test_no_inputs_produces_empty_output() -> void:
	var node = MergePointsNode.new()
	node.name = "test_merge_points_empty"
	node.settings = MergeNodeSettings.new()
	var _no_deps: Array[Dictionary] = []
	node.deps = _no_deps
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	ctx.gedit_nodes_by_name = {}
	ctx.eval_id = 0
	ctx.runtime_params = {}
	node.preExecute(ctx)
	node.run(ctx)
	dummy.free()
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_single_float_stream_passthrough() -> void:
	var data = _make_data({
		"value": [PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float]
	})
	var result = _run_with_bulks([data])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))
	node.free()
	src.free()

func test_two_bulks_float_streams_concatenated() -> void:
	var data_a = _make_data({
		"value": [PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float]
	})
	var data_b = _make_data({
		"value": [PackedFloat32Array([3.0, 4.0]), FlowDataScript.DataType.Float]
	})
	var result = _run_with_bulks([data_a, data_b])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0, 4.0]))
	node.free()
	src.free()

func test_two_bulks_vector_streams_concatenated() -> void:
	var data_a = _make_data({
		"position": [PackedVector3Array([Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0)]), FlowDataScript.DataType.Vector]
	})
	var data_b = _make_data({
		"position": [PackedVector3Array([Vector3(3.0, 0.0, 0.0)]), FlowDataScript.DataType.Vector]
	})
	var result = _run_with_bulks([data_a, data_b])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var stream = out.findStream("position")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedVector3Array([
		Vector3(1.0, 0.0, 0.0), Vector3(2.0, 0.0, 0.0), Vector3(3.0, 0.0, 0.0)
	]))
	node.free()
	src.free()

func test_disjoint_streams_zero_padded() -> void:
	var data_a = FlowDataScript.Data.new()
	data_a.registerStream("x", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	data_a.registerStream("y", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)
	var data_b = FlowDataScript.Data.new()
	data_b.registerStream("x", PackedFloat32Array([3.0]), FlowDataScript.DataType.Float)
	var result = _run_with_bulks([data_a, data_b])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var x_stream = out.findStream("x")
	assert_object(x_stream).is_not_null()
	assert_array(x_stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))
	var y_stream = out.findStream("y")
	assert_object(y_stream).is_not_null()
	assert_int(y_stream.container.size()).is_equal(3)
	assert_float(y_stream.container[0]).is_equal(10.0)
	assert_float(y_stream.container[1]).is_equal(20.0)
	assert_float(y_stream.container[2]).is_equal(0.0)
	node.free()
	src.free()

func test_new_stream_in_second_bulk_zero_padded_at_start() -> void:
	var data_a = FlowDataScript.Data.new()
	data_a.registerStream("x", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var data_b = FlowDataScript.Data.new()
	data_b.registerStream("x", PackedFloat32Array([2.0]), FlowDataScript.DataType.Float)
	data_b.registerStream("extra", PackedFloat32Array([99.0]), FlowDataScript.DataType.Float)
	var result = _run_with_bulks([data_a, data_b])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var x_stream = out.findStream("x")
	assert_object(x_stream).is_not_null()
	assert_array(x_stream.container).is_equal(PackedFloat32Array([1.0, 2.0]))
	var extra_stream = out.findStream("extra")
	assert_object(extra_stream).is_not_null()
	assert_int(extra_stream.container.size()).is_equal(2)
	assert_float(extra_stream.container[0]).is_equal(0.0)
	assert_float(extra_stream.container[1]).is_equal(99.0)
	node.free()
	src.free()

func test_color_streams_concatenated() -> void:
	var data_a = _make_data({
		"color": [PackedColorArray([Color(1.0, 0.0, 0.0), Color(0.0, 1.0, 0.0)]), FlowDataScript.DataType.Color]
	})
	var data_b = _make_data({
		"color": [PackedColorArray([Color(0.0, 0.0, 1.0)]), FlowDataScript.DataType.Color]
	})
	var result = _run_with_bulks([data_a, data_b])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedColorArray([
		Color(1.0, 0.0, 0.0), Color(0.0, 1.0, 0.0), Color(0.0, 0.0, 1.0)
	]))
	node.free()
	src.free()

func test_multiple_streams_multiple_bulks_merged() -> void:
	var data_a = FlowDataScript.Data.new()
	data_a.registerStream("position", PackedVector3Array([Vector3(0.0, 0.0, 0.0)]), FlowDataScript.DataType.Vector)
	data_a.registerStream("density", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var data_b = FlowDataScript.Data.new()
	data_b.registerStream("position", PackedVector3Array([Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0)]), FlowDataScript.DataType.Vector)
	data_b.registerStream("density", PackedFloat32Array([0.5, 0.25]), FlowDataScript.DataType.Float)
	var result = _run_with_bulks([data_a, data_b])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(1.0, 1.0, 1.0), Vector3(2.0, 2.0, 2.0)
	]))
	var density_stream = out.findStream("density")
	assert_object(density_stream).is_not_null()
	assert_array(density_stream.container).is_equal(PackedFloat32Array([1.0, 0.5, 0.25]))
	node.free()
	src.free()

func test_single_element_bulk() -> void:
	var data = _make_data({
		"value": [PackedFloat32Array([42.0]), FlowDataScript.DataType.Float]
	})
	var result = _run_with_bulks([data])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([42.0]))
	node.free()
	src.free()

func test_three_bulks_concatenated_correctly() -> void:
	var d1 = _make_data({"x": [PackedFloat32Array([1.0]), FlowDataScript.DataType.Float]})
	var d2 = _make_data({"x": [PackedFloat32Array([2.0]), FlowDataScript.DataType.Float]})
	var d3 = _make_data({"x": [PackedFloat32Array([3.0]), FlowDataScript.DataType.Float]})
	var result = _run_with_bulks([d1, d2, d3])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var stream = out.findStream("x")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))
	node.free()
	src.free()

func test_type_mismatch_skips_mismatched_values_with_zero_pad() -> void:
	var d1 = _make_data({"score": [PackedFloat32Array([9.0, 8.0]), FlowDataScript.DataType.Float]})
	var d2 = FlowDataScript.Data.new()
	d2.registerStream("score", PackedInt32Array([7, 6]), FlowDataScript.DataType.Int)
	var result = _run_with_bulks([d1, d2])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("score")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	assert_float(stream.container[0]).is_equal(9.0)
	assert_float(stream.container[1]).is_equal(8.0)
	assert_float(stream.container[2]).is_equal(0.0)
	assert_float(stream.container[3]).is_equal(0.0)
	node.free()
	src.free()
