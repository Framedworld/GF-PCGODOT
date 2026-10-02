# WP11 item 5: in threaded mode, elements known to print errors outside
# setError (FlowData helper push_error, engine errors) run one at a time on the
# calling thread instead of in a concurrent pool batch, because script Loggers
# are called on the raising thread and are often not thread-safe.
class_name ThreadedLoggingBatchTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

func _element(template : String) -> FlowNodeBase:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path(template)).new()
	element.node_template = template
	return element

func test_conformance_logging_templates_are_flagged() -> void:
	# The templates the conformance harness recorded printing outside setError
	# on its fixtures (docs/_round2/WP9.md), all threadable.
	for template in ["relax", "snap_to_grid", "point_filter_range", "mutate_seed", "boolean", "filter", "partition"]:
		var element := _element(template)
		assert_bool(FlowNodeTraits.logs_outside_set_error(element)).override_failure_message(template).is_true()
		assert_bool(FlowNodeTraits.main_thread(element)).override_failure_message(template).is_false()
	for template in ["grid", "transform_points", "math_op", "spawn_meshes"]:
		assert_bool(FlowNodeTraits.logs_outside_set_error(_element(template))).override_failure_message(template).is_false()

func test_meta_logs_flag_marks_third_party_nodes() -> void:
	var element := _element("grid")
	element.meta_node = element.meta_node.duplicate()
	element.meta_node["logs"] = true
	assert_bool(FlowNodeTraits.logs_outside_set_error(element)).is_true()

func test_split_batch_moves_logging_elements_out_of_the_pool() -> void:
	var ordered := [_element("grid"), _element("relax"), _element("transform_points"), _element("snap_to_grid"), _element("math_op")]
	var split := FlowExecutor.split_batch(ordered, PackedInt32Array([0, 1, 2, 3, 4]))
	assert_array(Array(split.serial)).is_equal([1, 3])
	assert_array(Array(split.pooled)).is_equal([0, 2, 4])

## grid -> 4 relax branches and 4 transform_points branches -> merge -> output.
func _graph() -> FlowGraphResource:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 6, "y": 1, "z": 6})
	b.node("merge", "merge")
	b.node("out", "output", {"name": "result"})
	for i in range(4):
		var r := "relax_%d" % i
		b.node(r, "relax", {"num_iterations": 1 + i})
		b.link("grid", 0, r, 0)
		b.link(r, 0, "merge", 0)
		var t := "xform_%d" % i
		b.node(t, "transform_points", {"random_seed": i, "offset_max": Vector3(1, 0, 1)})
		b.link("grid", 0, t, 0)
		b.link(t, 0, "merge", 0)
	b.link("merge", 0, "out", 0)
	return b.build()

func _summary(outputs : Dictionary) -> Dictionary:
	var out := {}
	for key in outputs:
		var value = outputs[key]
		if value is FlowDataScript.Data:
			out[key] = value.content_hash()
		else:
			out[key] = str(value)
	return out

func test_threaded_run_serializes_logging_elements_only() -> void:
	var graph := _graph()
	var sequential := _summary(FlowNodeIO.evaluate_graph(graph, {}, FlowNodeIO.make_context(null), {}, 0))
	var pooled_before := FlowExecutor.pooled_element_count
	var serial_before := FlowExecutor.serialized_element_count
	var ctx := FlowNodeIO.make_context(null)
	ctx.set_meta(FlowExecutor.THREADED_META, true)
	var threaded := _summary(FlowNodeIO.evaluate_graph(graph, {}, ctx, {}, 0))
	assert_dict(threaded).is_equal(sequential)
	# The four relax elements ran one at a time on the calling thread; the four
	# transform_points elements still ran concurrently on the pool.
	assert_int(FlowExecutor.serialized_element_count - serial_before).is_equal(4)
	assert_int(FlowExecutor.pooled_element_count - pooled_before).is_equal(4)
