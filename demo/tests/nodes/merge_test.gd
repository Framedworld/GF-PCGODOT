# merge_test.gd
class_name MergeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MergeNode = preload("res://addons/flow_nodes_editor/nodes/merge.gd")
const MergeSettings = preload("res://addons/flow_nodes_editor/nodes/merge_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

# Creates a fake source node with pre-populated generated_bulks and adds it to ctx.
# Returns the fake source node (caller must free it).
func _make_source_node(data_bulks: Array, ctx: FlowData.EvaluationContext) -> MergeNode:
	var src = MergeNode.new()
	src.name = "fake_source"
	src.num_generated_bulks = 0
	src.generated_bulks = []
	for bulk_data in data_bulks:
		src.set_output(0, bulk_data)
	ctx.gedit_nodes_by_name["fake_source"] = src
	return src

# Runs the merge node with the given source bulks wired into port 0.
# Returns the merge node; caller must free it and the dummy.
func _run_with_bulks(data_bulks: Array) -> Dictionary:
	var node = MergeNode.new()
	node.name = "test_merge"
	node.settings = MergeSettings.new()
	var empty_deps: Array[Dictionary] = []
	node.deps = empty_deps
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	ctx.gedit_nodes_by_name = {}
	ctx.eval_id = 0
	ctx.runtime_params = {}
	var src = _make_source_node(data_bulks, ctx)
	var wired_deps: Array[Dictionary] = [{"from_node": "fake_source", "from_port": 0, "to_port": 0, "virtual_variable": false}]
	node.deps = wired_deps
	node.preExecute(ctx)
	node.run(ctx)
	dummy.free()
	return {"node": node, "src": src}

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_single_bulk_single_float_stream_passes_through() -> void:
	var d = _make_data("density", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var result = _run_with_bulks([d])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("density")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))
	node.free()
	src.free()

func test_two_bulks_concatenates_float_streams() -> void:
	var d1 = _make_data("value", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)
	var d2 = _make_data("value", PackedFloat32Array([30.0, 40.0]), FlowDataScript.DataType.Float)
	var result = _run_with_bulks([d1, d2])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	assert_float(stream.container[0]).is_equal(10.0)
	assert_float(stream.container[1]).is_equal(20.0)
	assert_float(stream.container[2]).is_equal(30.0)
	assert_float(stream.container[3]).is_equal(40.0)
	node.free()
	src.free()

func test_two_bulks_concatenates_vector_streams() -> void:
	var d1 = _make_data("position", PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)]), FlowDataScript.DataType.Vector)
	var d2 = _make_data("position", PackedVector3Array([Vector3(3, 0, 0), Vector3(4, 0, 0)]), FlowDataScript.DataType.Vector)
	var result = _run_with_bulks([d1, d2])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("position")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(4, 0, 0)]))
	node.free()
	src.free()

func test_two_bulks_with_disjoint_streams_pads_missing_with_default() -> void:
	var d1 := FlowDataScript.Data.new()
	d1.registerStream("s1", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	d1.registerStream("s2", PackedFloat32Array([10.0, 20.0]), FlowDataScript.DataType.Float)
	var d2 := FlowDataScript.Data.new()
	d2.registerStream("s1", PackedFloat32Array([3.0, 4.0]), FlowDataScript.DataType.Float)
	d2.registerStream("s3", PackedFloat32Array([100.0, 200.0]), FlowDataScript.DataType.Float)
	var result = _run_with_bulks([d1, d2])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)
	var s1 = out.findStream("s1")
	assert_object(s1).is_not_null()
	assert_int(s1.container.size()).is_equal(4)
	assert_float(s1.container[0]).is_equal(1.0)
	assert_float(s1.container[1]).is_equal(2.0)
	assert_float(s1.container[2]).is_equal(3.0)
	assert_float(s1.container[3]).is_equal(4.0)
	var s2 = out.findStream("s2")
	assert_object(s2).is_not_null()
	assert_int(s2.container.size()).is_equal(4)
	assert_float(s2.container[0]).is_equal(10.0)
	assert_float(s2.container[1]).is_equal(20.0)
	assert_float(s2.container[2]).is_equal(0.0)
	assert_float(s2.container[3]).is_equal(0.0)
	var s3 = out.findStream("s3")
	assert_object(s3).is_not_null()
	assert_int(s3.container.size()).is_equal(4)
	assert_float(s3.container[0]).is_equal(0.0)
	assert_float(s3.container[1]).is_equal(0.0)
	assert_float(s3.container[2]).is_equal(100.0)
	assert_float(s3.container[3]).is_equal(200.0)
	node.free()
	src.free()

func test_single_bulk_multiple_stream_types() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("pos", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	d.registerStream("density", PackedFloat32Array([0.5]), FlowDataScript.DataType.Float)
	d.registerStream("color", PackedColorArray([Color(1, 0, 0)]), FlowDataScript.DataType.Color)
	d.registerStream("id", PackedInt32Array([42]), FlowDataScript.DataType.Int)
	var result = _run_with_bulks([d])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	var pos = out.findStream("pos")
	assert_object(pos).is_not_null()
	assert_array(pos.container).is_equal(PackedVector3Array([Vector3(1, 2, 3)]))
	var dens = out.findStream("density")
	assert_object(dens).is_not_null()
	assert_float(dens.container[0]).is_equal(0.5)
	var col = out.findStream("color")
	assert_object(col).is_not_null()
	assert_array(col.container).is_equal(PackedColorArray([Color(1, 0, 0)]))
	var id_s = out.findStream("id")
	assert_object(id_s).is_not_null()
	assert_int(id_s.container[0]).is_equal(42)
	node.free()
	src.free()

func test_null_input_bulk_is_skipped_gracefully() -> void:
	var d = _make_data("value", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	var node = MergeNode.new()
	node.name = "test_merge_null"
	node.settings = MergeSettings.new()
	var empty_deps2: Array[Dictionary] = []
	node.deps = empty_deps2
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

func test_three_bulks_concatenated_correctly() -> void:
	var d1 = _make_data("x", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var d2 = _make_data("x", PackedFloat32Array([2.0]), FlowDataScript.DataType.Float)
	var d3 = _make_data("x", PackedFloat32Array([3.0]), FlowDataScript.DataType.Float)
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

func test_type_mismatch_between_bulks_skips_mismatched_values_with_zero_pad() -> void:
	var d1 = _make_data("score", PackedFloat32Array([9.0, 8.0]), FlowDataScript.DataType.Float)
	var d2 := FlowDataScript.Data.new()
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

func test_empty_data_bulk_produces_empty_streams_with_offsets() -> void:
	var d1 = _make_data("val", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var d2 := FlowDataScript.Data.new()
	d2.registerStream("val", PackedFloat32Array(), FlowDataScript.DataType.Float)
	var d3 = _make_data("val", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	var result = _run_with_bulks([d1, d2, d3])
	var node = result.node
	var src = result.src
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("val")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0]).is_equal(1.0)
	assert_float(stream.container[1]).is_equal(2.0)
	assert_float(stream.container[2]).is_equal(5.0)
	node.free()
	src.free()
