# loop_modes_executor_test.gd
# WP8 (docs/_round2/WP8.md): loop graphs in the executor's threaded mode and
# with FlowOutputCache give the same results as the sequential uncached run,
# and the loop / subgraph / get_loop_* editor hooks (getMeta, title, port
# rebuild) follow their new settings through the FlowNodeWidget.
class_name LoopModesExecutorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const LoopSettings = preload("res://addons/flow_nodes_editor/nodes/loop_settings.gd")


func after_test() -> void:
	FlowOutputCache.clear()


## grid (4 x 4, "group" = index % 3 via math_op) -> three loops over the same
## seed-dependent body (Partitions + Collection, Chunks + Merge, Entries over
## the partitions) -> outputs.
func _graph() -> FlowGraphResource:
	var body : FlowGraphResource = TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("rand", "attribute_random", {"attribute_name": "r", "min_value": 0.0, "max_value": 100.0, "random_seed": 3}) \
		.node("idx", "get_loop_index", {"out_name": "it", "source": 1}) \
		.node("key", "get_loop_key", {"out_name": "key"}) \
		.node("w", "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": 0.0, "bindings": {"cte_float": "iteration_index"}}) \
		.node("out", "output", {"name": "result"}) \
		.link("in_item", 0, "rand", 0) \
		.link("rand", 0, "idx", 0) \
		.link("idx", 0, "key", 0) \
		.link("key", 0, "w", 0) \
		.link("w", 0, "out", 0) \
		.build()
	var loop_common := {"graph": body, "item_input_name": "item", "output_attribute_name": "result"}
	return TestGraph.new() \
		.node("grid", "grid", {"x": 4, "y": 1, "z": 4, "random_seed": 11}) \
		.node("enum", "get_loop_index", {"out_name": "group"}) \
		.node("mod", "math_op", {"operation": 10, "in_nameA": "group", "in_nameB": "3", "out_name": "group"}) \
		.node("parts", "loop", loop_common.merged({"iteration_mode": LoopSettings.IterationMode.Partitions, "partition_attribute": "group", "output_mode": LoopSettings.OutputMode.Collection})) \
		.node("chunks", "loop", loop_common.merged({"iteration_mode": LoopSettings.IterationMode.Chunks, "chunk_size": 5})) \
		.node("split", "partition", {"attribute_name": "group"}) \
		.node("entries", "loop", loop_common.merged({"iteration_mode": LoopSettings.IterationMode.Entries})) \
		.node("after", "add_attribute", {"name": "after", "data_type": FlowData.DataType.Int, "cte_int": 1}) \
		.node("merge", "merge") \
		.node("out_parts", "output", {"name": "parts"}) \
		.node("out_chunks", "output", {"name": "chunks"}) \
		.node("out_entries", "output", {"name": "entries"}) \
		.link("grid", 0, "enum", 0) \
		.link("enum", 0, "mod", 0) \
		.link("mod", 0, "parts", 0) \
		.link("parts", 0, "after", 0) \
		.link("after", 0, "merge", 0) \
		.link("merge", 0, "out_parts", 0) \
		.link("mod", 0, "chunks", 0) \
		.link("chunks", 0, "out_chunks", 0) \
		.link("mod", 0, "split", 0) \
		.link("split", 0, "entries", 0) \
		.link("entries", 0, "out_entries", 0) \
		.build()

func _eval(graph: FlowGraphResource, seed: int, threaded: bool, cached: bool) -> Dictionary:
	var ctx := FlowNodeIO.make_context(null, seed, {})
	if threaded:
		ctx.set_meta(FlowExecutor.THREADED_META, true)
	if cached:
		ctx.set_meta(FlowExecutor.OUTPUT_CACHE_META, true)
	var result := FlowNodeIO.evaluate_collecting_errors(graph, {}, ctx)
	var summary := {}
	for key in result.outputs:
		summary[str(key)] = FlowNodeIO.snapshot_summarize_data(result.outputs[key])
	summary["__errors"] = result.errors.map(func(e): return e.message)
	return summary


func test_threaded_and_cached_runs_equal_the_sequential_run() -> void:
	var graph := _graph()
	for seed in [0, 1234]:
		var reference := _eval(graph, seed, false, false)
		assert_array(reference["__errors"]).is_empty()
		assert_int(reference.size()).is_equal(4)
		assert_dict(_eval(graph, seed, true, false)).is_equal(reference)
		FlowOutputCache.clear()
		assert_dict(_eval(graph, seed, false, true)).is_equal(reference)
		# Warm cache: body nodes hit across iterations and evaluations.
		assert_dict(_eval(graph, seed, false, true)).is_equal(reference)
		assert_int(FlowOutputCache.hits).is_greater(0)
		assert_dict(_eval(graph, seed, true, true)).is_equal(reference)

func test_the_loop_outputs_carry_the_iteration_streams() -> void:
	var outputs := FlowNodeIO.evaluate(_graph(), {}, 5)
	assert_array(FlowNodeIO.last_errors).is_empty()
	# Merge of the Chunks loop: 16 points in 4 chunks (5, 5, 5, 1).
	var chunks : FlowData.Data = outputs["chunks"]
	assert_int(chunks.size()).is_equal(16)
	assert_array(Array(chunks.findStream("it").container)).is_equal([0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3])
	assert_array(Array(chunks.findStream("w").container).slice(14)).is_equal([2.0, 3.0])
	# Entries: three partition entries, keys are entry indices.
	var entries : FlowData.Data = outputs["entries"]
	assert_int(entries.size()).is_equal(16)
	assert_array(Array(entries.findStream("key").container).slice(0, 6)).is_equal([0, 0, 0, 0, 0, 0])


# --- editor hooks -----------------------------------------------------------------------

func _element(template: String) -> FlowNodeBase:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path(template)).new()
	element.node_template = template
	element.name = "n_" + template
	var meta := element.getMeta()
	element.settings = meta.settings.new() if meta.has("settings") and meta.settings else NodeSettings.new()
	return element

func _body() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.in_param("acc", FlowData.DataType.Vector) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector}) \
		.node("out", "output", {"name": "result"}) \
		.node("out_acc", "output", {"name": "acc"}) \
		.link("in_item", 0, "out", 0) \
		.build()

func test_loop_widget_follows_mode_settings() -> void:
	var element := _element("loop")
	element.settings.graph = _body()
	var widget := FlowNodeWidget.new()
	widget.element = element
	widget.initFromScript()
	widget.refreshFromSettings()
	assert_str(widget.title).is_equal("Loop (New Graph)")
	assert_int(widget.num_in_ports).is_equal(2)   # Stream, acc
	assert_int(widget.num_out_ports).is_equal(1)
	element.settings.iteration_mode = LoopSettings.IterationMode.Partitions
	widget.onPropChanged("iteration_mode")
	widget.refreshFromSettings()
	assert_str(widget.title).is_equal("Loop (New Graph) [Partitions]")
	element.settings.output_mode = LoopSettings.OutputMode.Collection
	widget.onPropChanged("output_mode")
	widget.refreshFromSettings()
	assert_str(widget.title).is_equal("Loop (New Graph) [Partitions, Collection]")
	# Feedback still adds its output pin in every mode.
	element.settings.feedback_param_name = "acc"
	widget.onPropChanged("feedback_param_name")
	assert_int(widget.num_out_ports).is_equal(2)
	# A dynamic loop without a default graph shows its attribute.
	element.settings.graph = null
	element.settings.graph_attribute = "body"
	widget.onPropChanged("graph_attribute")
	widget.refreshFromSettings()
	assert_str(widget.title).is_equal("Loop (@body) [Partitions, Collection]")
	assert_int(widget.num_in_ports).is_equal(1)
	widget.free()

func test_subgraph_widget_rebuilds_ports_for_graph_attribute() -> void:
	var element := _element("subgraph")
	element.settings.graph = TestGraph.new() \
		.in_param("x", FlowData.DataType.Float) \
		.node("out", "output", {"name": "result"}) \
		.build()
	var widget := FlowNodeWidget.new()
	widget.element = element
	widget.initFromScript()
	assert_int(widget.num_in_ports).is_equal(1)
	element.settings.graph_attribute = "g"
	widget.onPropChanged("graph_attribute")
	assert_int(widget.num_in_ports).is_equal(2)
	widget.refreshFromSettings()
	assert_str(widget.title).is_equal("Subgraph (New Graph) [@g]")
	element.settings.graph_attribute = ""
	widget.onPropChanged("graph_attribute")
	assert_int(widget.num_in_ports).is_equal(1)
	widget.free()

func test_loop_settings_hide_unused_mode_options() -> void:
	var s := LoopSettings.new()
	var visible := func(prop: String) -> bool:
		for p in s.get_property_list():
			if p.name == prop:
				return (p.usage & PROPERTY_USAGE_EDITOR) != 0
		return false
	assert_bool(visible.call("partition_attribute")).is_false()
	assert_bool(visible.call("chunk_size")).is_false()
	s.iteration_mode = LoopSettings.IterationMode.Chunks
	assert_bool(visible.call("chunk_size")).is_true()
	s.iteration_mode = LoopSettings.IterationMode.Partitions
	assert_bool(visible.call("partition_attribute")).is_true()
	s.iteration_mode = LoopSettings.IterationMode.Entries
	assert_bool(visible.call("key_attribute")).is_true()
	# Hidden options are still saved.
	assert_bool(FlowNodeIO.resource_to_dict(s).has("partition_attribute")).is_true()

func test_get_loop_widgets_build() -> void:
	for template in ["get_loop_index", "get_loop_key"]:
		var element := _element(template)
		var widget := FlowNodeWidget.new()
		widget.element = element
		widget.initFromScript()
		widget.refreshFromSettings()
		assert_int(widget.num_in_ports).is_equal(1)
		assert_int(widget.num_out_ports).is_equal(1)
		widget.free()

func test_traits_of_the_loop_nodes() -> void:
	for template in ["loop", "subgraph", "get_loop_index", "get_loop_key"]:
		var traits := FlowNodeTraits.resolve(template)
		assert_bool(traits.main_thread).override_failure_message(template).is_true()
		assert_bool(traits.cacheable).override_failure_message(template).is_false()
