# codex_findings_test.gd
# Regression tests for the four automated-review findings on the pull request:
# loop key type, stale rotation_quat, NaN selection order and a negative cache
# capacity. Each test failed before its fix.
class_name CodexFindingsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const LoopNode = preload("res://addons/flow_nodes_editor/nodes/loop.gd")
const LoopSettings = preload("res://addons/flow_nodes_editor/nodes/loop_settings.gd")
const SelectNode = preload("res://addons/flow_nodes_editor/nodes/attribute_select.gd")
const SelectSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_select_settings.gd")
const SetToPointNode = preload("res://addons/flow_nodes_editor/nodes/attribute_set_to_point.gd")
const SetToPointSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_set_to_point_settings.gd")

var D = FlowDataScript.DataType

# --- Get Loop Key keeps the partition attribute's declared type --------------------

func _key_body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("key", "get_loop_key", {"out_name": "key"}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "key", 0) \
		.link("key", 0, "out", 0) \
		.build()

func _run_partition_loop(d: FlowData.Data, attribute: String) -> FlowData.Data:
	var node := LoopNode.new()
	node.name = "test_loop"
	node.node_template = "loop"
	var s := LoopSettings.new()
	s.graph = _key_body()
	s.item_input_name = "item"
	s.output_attribute_name = "result"
	s.iteration_mode = LoopSettings.IterationMode.Partitions
	s.partition_attribute = attribute
	s.output_mode = LoopSettings.OutputMode.Merge
	node.settings = s
	var ctx := TestGraph.make_ctx()
	var src := FlowNodeBase.new()
	src.name = &"src"
	src.generated_bulks.append([d])
	src.num_generated_bulks = 1
	node.deps.clear()
	node.deps.append({ "from_node": &"src", "from_port": 0, "to_node": node.name, "to_port": 0 })
	ctx.gedit_nodes_by_name = { &"src": src }
	node.preExecute(ctx)
	node.run(ctx)
	var out = null
	if not node.generated_bulks.is_empty():
		out = node.generated_bulks[0][0]
	return out

func test_get_loop_key_keeps_int64_partition_keys() -> void:
	var big : int = 1 << 40
	var d := TestGraph.points([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	d.registerStream("big", PackedInt64Array([big + 1, big, big + 1]), D.Int64)
	var out := _run_partition_loop(d, "big")
	assert_object(out).is_not_null()
	assert_int(H.dtype(out, "key")).is_equal(D.Int64)
	var keys := H.values(out, "key")
	keys.sort()
	assert_array(keys).is_equal([big, big + 1, big + 1])

func test_get_loop_key_keeps_double_partition_keys() -> void:
	var v : float = 0.1234567890123
	var d := TestGraph.points([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	d.registerStream("dbl", PackedFloat64Array([v, v]), D.Double)
	var out := _run_partition_loop(d, "dbl")
	assert_object(out).is_not_null()
	assert_int(H.dtype(out, "key")).is_equal(D.Double)
	assert_array(H.values(out, "key")).is_equal([v, v])

func test_get_loop_key_of_an_int_partition_stays_int() -> void:
	var d := TestGraph.points([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	d.registerStream("g", PackedInt32Array([3, 4]), D.Int)
	var out := _run_partition_loop(d, "g")
	assert_int(H.dtype(out, "key")).is_equal(D.Int)
	var keys := H.values(out, "key")
	keys.sort()
	assert_array(keys).is_equal([3, 4])

# --- Attribute Set To Point: a stale rotation_quat must not win --------------------

func test_set_to_point_from_transform_updates_rotation_quat() -> void:
	var q := Quaternion(Vector3.UP, deg_to_rad(90.0))
	var xf := Transform3D(Basis(Quaternion(Vector3.RIGHT, deg_to_rad(30.0))), Vector3(1, 2, 3))
	var d := H.data({
		"position": [PackedVector3Array([Vector3.ZERO]), D.Vector],
		"rotation_quat": [PackedVector4Array([Vector4(q.x, q.y, q.z, q.w)]), D.Quaternion],
		"tf": [[xf], D.Transform],
	})
	var s := SetToPointSettings.new()
	s.transform_attribute_name = "tf"
	var r := H.exec(SetToPointNode, s, [d])
	assert_str(r.err).is_empty()
	var out_xf : Transform3D = r.out.getTransformsStream().atIndex(0)
	var got := out_xf.basis.get_rotation_quaternion()
	var want := xf.basis.get_rotation_quaternion()
	assert_float(absf(got.dot(want))).is_equal_approx(1.0, 1e-4)

func test_set_to_point_from_attributes_drops_a_stale_rotation_quat() -> void:
	var q := Quaternion(Vector3.UP, deg_to_rad(90.0))
	var d := H.data({
		"position": [PackedVector3Array([Vector3.ZERO]), D.Vector],
		"rotation_quat": [PackedVector4Array([Vector4(q.x, q.y, q.z, q.w)]), D.Quaternion],
		"rot": [PackedVector3Array([Vector3(0, 0, 0)]), D.Vector],
	})
	var s := SetToPointSettings.new()
	s.rotation_attribute_name = "rot"
	var r := H.exec(SetToPointNode, s, [d])
	assert_str(r.err).is_empty()
	var out_xf : Transform3D = r.out.getTransformsStream().atIndex(0)
	var got := out_xf.basis.get_rotation_quaternion()
	assert_float(absf(got.dot(Quaternion.IDENTITY))).is_equal_approx(1.0, 1e-4)

# --- Attribute Select: NaN keys sort last, deterministically -----------------------

func _select(values: Array, operation: int) -> Dictionary:
	var d := H.data({ "v": [PackedFloat32Array(values), D.Float] })
	var s := SelectSettings.new()
	s.operation = operation
	s.input_attribute = "v"
	s.index_attribute = "idx"
	var r := H.exec(SelectNode, s, [d])
	return { "err": r.err, "idx": H.values(r.out, "idx") }

func test_attribute_select_ignores_nan_keys_for_min_max_and_median() -> void:
	var cases := [
		[NAN, 2.0, 1.0, 3.0],
		[2.0, NAN, 3.0, 1.0],
		[3.0, 1.0, 2.0, NAN],
		[NAN, NAN, 2.0, 1.0],
	]
	for values in cases:
		var finite : Array = values.filter(func(x): return not is_nan(x))
		var lo : float = finite.min()
		var hi : float = finite.max()
		assert_array(_select(values, SelectSettings.eOperation.Min).idx).is_equal([values.find(lo)])
		assert_array(_select(values, SelectSettings.eOperation.Max).idx).is_equal([values.find(hi)])

func test_attribute_select_with_only_nan_keys_picks_the_first_entry() -> void:
	for op in [SelectSettings.eOperation.Min, SelectSettings.eOperation.Max]:
		var r := _select([NAN, NAN, NAN], op)
		assert_str(r.err).is_empty()
		assert_array(r.idx).is_equal([0])

# --- FlowOutputCache: a negative capacity must not hang eviction --------------------

func test_output_cache_with_a_negative_capacity_does_not_hang() -> void:
	var saved := FlowOutputCache.max_entries
	FlowOutputCache.clear()
	FlowOutputCache.max_entries = -5
	var graph : FlowGraphResource = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "out", 0) \
		.build()
	var ctx := FlowNodeIO.make_context(null, 0, {})
	ctx.set_meta(FlowExecutor.OUTPUT_CACHE_META, true)
	var result := FlowNodeIO.evaluate_collecting_errors(graph, {}, ctx)
	FlowOutputCache.max_entries = saved
	FlowOutputCache.clear()
	assert_bool(result.outputs.has("result")).is_true()
