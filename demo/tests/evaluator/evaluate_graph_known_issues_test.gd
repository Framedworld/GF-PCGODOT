# evaluate_graph_known_issues_test.gd
# Current, buggy evaluator behaviour pinned down so a fix is noticed.
# Tests named *_BUG assert today's behaviour; when the bug is fixed they fail
# and should be replaced by the skipped *_EXPECTED test next to them (remove
# its do_skip). Each is listed in the agent-C report with file:line.
class_name EvaluateGraphKnownIssuesTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var Probe

func before_test() -> void:
	TestGraph.register_probes()
	Probe = TestGraph.probe()

func after_test() -> void:
	TestGraph.unregister_probes()


## grid (no flow inputs) whose exposed "x" parameter port 0 is wired to an
## Int stream, as the editor saves it when a parameter pin is connected.
func _wired_param_graph() -> FlowGraphResource:
	var g = TestGraph.new() \
		.node("count", "add_attribute", {"name": "x", "data_type": FlowData.DataType.Int, "cte_int": 5}) \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("sink", "test_probe_final") \
		.link("count", 0, "grid", 0) \
		.link("grid", 0, "sink", 0) \
		.build()
	# What the editor stores for a connected parameter pin.
	g.data["nodes"][1]["args_port"] = {"x": {"port": 0, "connected": true}}
	return g


# flow_nodes_io.gd:951 — _execute_single_node sizes node.inputs to the node's
# flow "ins" only, then writes every wired dep into inputs[to_port]. A wired
# parameter port (index >= ins.size()) raises a script error, which aborts
# _execute_single_node for that node: it never runs and emits nothing. (Even
# without the error, args_ports_by_name is never restored from the saved
# "args_port" at runtime, so getSettingValue would ignore the wire.) Several
# demo graphs hit this (see tests/golden/baseline.json script_errors).
func test_wired_parameter_port_overrides_setting() -> void:
	FlowNodeIO.evaluate_graph(_wired_param_graph(), {}, TestGraph.make_ctx(), {}, 0)
	var sink = Probe.exec_log.filter(func(e): return e.name == "sink")
	# x = 5 from the wire, y = z = 1
	assert_int(sink[0].a_size).is_equal(5)


# node.gd:345 — refreshFromSettings() calls draw_debug.cleanup_multimesh_direct()
# when settings.disabled is true, but evaluator-built nodes have no draw_debug.
# The script error aborts refreshFromSettings; evaluation itself continues and
# the disabled node still passes its input through.
func test_disabled_node_saved_in_graph_passes_through_without_error() -> void:
	var graph = TestGraph.new() \
		.node("a", "test_probe") \
		.node("skipped", "test_probe", {"disabled": true}) \
		.node("out", "output", {"name": "result"}) \
		.link("a", 0, "skipped", 0) \
		.link("skipped", 0, "out", 0) \
		.build()
	var outputs := {}
	await assert_error(func(): outputs.merge(FlowNodeIO.evaluate_graph(graph, {}, TestGraph.make_ctx(), {}, 0))) \
		.is_success()
	assert_array(Array(TestGraph.trail(outputs.get("result")))).is_equal(["a"])
