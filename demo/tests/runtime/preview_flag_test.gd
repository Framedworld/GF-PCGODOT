# preview_flag_test.gd
# EvaluationContext.preview: only the editor dock sets it. Owner-less previews stay
# silent about missing inputs/owner and emit empty Data; every other owner-less
# evaluation (runtime, @tool scripts) reports the documented errors.
class_name PreviewFlagTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")


func _ctx(preview: bool) -> FlowData.EvaluationContext:
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.preview = preview
	return ctx


func _run(template: String, inputs: Array, ctx: FlowData.EvaluationContext) -> FlowNodeBase:
	var node: FlowNodeBase = load(FlowNodeRegistry.get_node_script_path(template)).new()
	node.name = "n"
	node.node_template = template
	node.settings = node.getMeta().settings.new()
	node.inputs = inputs
	node.preExecute(ctx)
	node.execute(ctx)
	return node


func _output(node: FlowNodeBase):
	if node.generated_bulks.is_empty() or node.generated_bulks[0].is_empty():
		return null
	return node.generated_bulks[0][0]


func test_preview_defaults_off() -> void:
	assert_bool(FlowDataScript.EvaluationContext.new().preview).is_false()
	assert_bool(FlowNodeIO.make_context().preview).is_false()


func test_require_input_errors_without_preview() -> void:
	var node := _run("match_and_set", [null, null], _ctx(false))
	assert_str(node.err).is_equal("Input 'In' not connected")
	assert_object(_output(node)).is_null()


func test_require_input_is_silent_in_ownerless_preview() -> void:
	var node := _run("match_and_set", [null, null], _ctx(true))
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	assert_int(out.streams.size()).is_equal(0)


func test_preview_with_owner_still_reports_errors() -> void:
	# A graph opened from a FlowGraphNode3D keeps reporting, as before.
	var ctx := _ctx(true)
	var host := FlowGraphNode3D.new()
	ctx.owner = host
	var node := _run("match_and_set", [null, null], ctx)
	assert_str(node.err).is_equal("Input 'In' not connected")
	host.free()


func test_idiom_node_uses_preview_flag() -> void:
	# distance: unwired Input B.
	var pts := TestGraph.points([Vector3.ZERO, Vector3.ONE])
	var loud := _run("distance", [pts, null], _ctx(false))
	assert_str(loud.err).is_equal("Input B not connected")
	var quiet := _run("distance", [pts, null], _ctx(true))
	assert_str(quiet.err).is_empty()
	assert_int(_output(quiet).size()).is_equal(0)


func test_missing_owner_reported_only_outside_preview() -> void:
	var loud := _run("create_spline", [TestGraph.points([Vector3.ZERO])], _ctx(false))
	assert_str(loud.err).contains("needs an owner node")
	var quiet := _run("create_spline", [TestGraph.points([Vector3.ZERO])], _ctx(true))
	assert_str(quiet.err).not_contains("needs an owner node")


func _failing_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.node("grid", "grid", {"x": 2, "z": 1}) \
		.node("bad", "match_and_set") \
		.node("out", "output", {"name": "result"}) \
		.link("grid", 0, "bad", 1) \
		.link("bad", 0, "out", 0) \
		.build()


func test_nested_evaluations_inherit_preview() -> void:
	var graph: FlowGraphResource = TestGraph.new() \
		.node("sub", "subgraph", {"graph": _failing_graph()}) \
		.node("out", "output", {"name": "final"}) \
		.link("sub", 0, "out", 0) \
		.build()
	var ctx := FlowNodeIO.make_context()
	ctx.preview = true
	FlowNodeIO.start_error_log(ctx)
	var outputs := FlowNodeIO.evaluate_graph(graph, {}, ctx, {}, 0)
	assert_array(FlowNodeIO.last_errors).is_empty()
	assert_int(outputs["final"].size()).is_equal(0)
	# The same graph evaluated at runtime (no preview) reports the inner error.
	FlowNodeIO.evaluate(graph)
	assert_bool(FlowNodeIO.last_errors.any(func(e): return e.node == "bad" and e.message == "Input 'In' not connected")).is_true()


func test_editor_context_is_a_preview() -> void:
	var source := FileAccess.get_file_as_string("res://addons/flow_nodes_editor/flow_editor.gd")
	assert_str(source).contains("var ctx := _new_preview_context()")
	assert_str(source).contains("preview_ctx.preview = true")
	# No other evaluation context is built by the editor.
	assert_int(source.count("EvaluationContext.new()")).is_equal(1)
