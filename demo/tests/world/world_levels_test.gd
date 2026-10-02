# world_levels_test.gd
# WP5: compile-time level assignment on FlowCompiledGraph (node_levels,
# grid_sizes, hierarchy_index, level_plan).
class_name WorldLevelsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

func _levels(graph : FlowGraphResource) -> Dictionary:
	var compiled := FlowCompiledGraph.for_graph(graph)
	var result := {}
	for node_name in compiled.node_levels:
		result[str(node_name)] = compiled.node_levels[node_name]
	return result

func test_graph_without_markers_is_all_unbounded() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid").node("filter", "density_filter").node("out", "output", {"name": "r"})
	b.link("grid", 0, "filter", 0).link("filter", 0, "out", 0)
	var graph : FlowGraphResource = b.build()
	var compiled := FlowCompiledGraph.for_graph(graph)
	assert_dict(_levels(graph)).is_equal({"grid": 0, "filter": 0, "out": 0})
	assert_bool(compiled.has_hierarchy()).is_false()
	assert_array(Array(compiled.levels())).is_equal([0])

# grid -> marker(64) -> a, b -> merge (diamond) -> out; plus an Unbounded
# side branch grid -> side.
func test_diamond_below_one_marker() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid").node("marker", "grid_size", {"cell_size": 64.0})
	b.node("a", "density_filter").node("b", "add_tags").node("merge", "merge").node("out", "output", {"name": "r"})
	b.node("side", "add_tags")
	b.link("grid", 0, "marker", 0).link("marker", 0, "a", 0).link("marker", 0, "b", 0)
	b.link("a", 0, "merge", 0).link("b", 0, "merge", 0).link("merge", 0, "out", 0)
	b.link("grid", 0, "side", 0)
	var graph : FlowGraphResource = b.build()
	assert_dict(_levels(graph)).is_equal({"grid": 0, "marker": 64, "a": 64, "b": 64, "merge": 64, "out": 64, "side": 0})
	var compiled := FlowCompiledGraph.for_graph(graph)
	assert_array(Array(compiled.grid_sizes)).is_equal([64])
	assert_array(Array(compiled.levels())).is_equal([0, 64])
	var plan := compiled.level_plan(64)
	assert_array(plan["preseed"]).is_equal([&"grid"])
	assert_array(plan["capture"]).is_empty()
	assert_array(compiled.level_plan(0)["capture"]).is_equal([&"grid"])
	assert_bool(plan["run"].has(&"merge")).is_true()
	assert_bool(plan["run"].has(&"grid")).is_false()

# Diamond whose two arms carry different markers: the join takes the smallest.
func test_join_of_two_markers_takes_the_smallest() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid")
	b.node("m128", "grid_size", {"cell_size": 128.0}).node("m16", "grid_size", {"cell_size": 16.0})
	b.node("a", "add_tags").node("c", "add_tags").node("join", "merge").node("after", "density_filter")
	b.link("grid", 0, "m128", 0).link("grid", 0, "m16", 0)
	b.link("m128", 0, "a", 0).link("m16", 0, "c", 0)
	b.link("a", 0, "join", 0).link("c", 0, "join", 0).link("join", 0, "after", 0)
	var graph : FlowGraphResource = b.build()
	assert_dict(_levels(graph)).is_equal({"grid": 0, "m128": 128, "m16": 16, "a": 128, "c": 16, "join": 16, "after": 16})
	var compiled := FlowCompiledGraph.for_graph(graph)
	assert_array(Array(compiled.grid_sizes)).is_equal([128, 16])
	assert_int(compiled.hierarchy_index(0)).is_equal(0)
	assert_int(compiled.hierarchy_index(128)).is_equal(1)
	assert_int(compiled.hierarchy_index(16)).is_equal(2)
	# 16 consumes 128's "a" and nothing of Unbounded except through the m16 marker.
	var plan16 := compiled.level_plan(16)
	assert_array(plan16["preseed"]).contains_exactly_in_any_order([&"grid", &"a"])
	assert_array(compiled.level_plan(128)["capture"]).is_equal([&"a"])

# Chained markers: a finer marker downstream of a coarser one; a coarser
# marker downstream of a finer one keeps the finer size (smallest wins).
func test_chained_markers() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid").node("m256", "grid_size", {"cell_size": 256.0}).node("x", "add_tags")
	b.node("m32", "grid_size", {"cell_size": 32.0}).node("y", "add_tags").node("m512", "grid_size", {"cell_size": 512.0}).node("z", "add_tags")
	b.link("grid", 0, "m256", 0).link("m256", 0, "x", 0).link("x", 0, "m32", 0).link("m32", 0, "y", 0)
	b.link("y", 0, "m512", 0).link("m512", 0, "z", 0)
	var graph : FlowGraphResource = b.build()
	assert_dict(_levels(graph)).is_equal({"grid": 0, "m256": 256, "x": 256, "m32": 32, "y": 32, "m512": 32, "z": 32})
	assert_array(Array(FlowCompiledGraph.for_graph(graph).grid_sizes)).is_equal([256, 32])

func test_marker_without_input_puts_its_dependants_on_its_level() -> void:
	var b = TestGraph.new()
	b.node("marker", "grid_size", {"cell_size": 32.0}).node("bounds", "get_execution_bounds")
	b.link("marker", 0, "bounds", 0)
	var graph : FlowGraphResource = b.build()
	assert_dict(_levels(graph)).is_equal({"marker": 32, "bounds": 32})
	assert_array(Array(FlowCompiledGraph.for_graph(graph).levels())).is_equal([32])

func test_cell_size_is_snapped_and_defaults_to_64() -> void:
	var b = TestGraph.new()
	b.node("m_default", "grid_size").node("m_odd", "grid_size", {"cell_size": 100.0})
	var levels := _levels(b.build())
	assert_int(levels["m_default"]).is_equal(64)
	assert_int(levels["m_odd"]).is_equal(128)

# set_variable -> get_variable is a dependency: the reader follows the writer.
func test_virtual_variable_dependency_carries_the_level() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid").node("marker", "grid_size", {"cell_size": 8.0}).node("set", "set_variable", {"variable_name": "v"})
	b.node("get", "get_variable", {"variable_name": "v"}).node("after", "add_tags")
	b.link("grid", 0, "marker", 0).link("marker", 0, "set", 0).link("get", 0, "after", 0)
	var levels := _levels(b.build())
	assert_int(levels["set"]).is_equal(8)
	assert_int(levels["get"]).is_equal(8)
	assert_int(levels["after"]).is_equal(8)

# A cycle the sequential order tolerates must not hang the level pass.
func test_cycle_terminates() -> void:
	var b = TestGraph.new()
	b.node("marker", "grid_size", {"cell_size": 4.0}).node("a", "add_tags").node("c", "add_tags")
	b.link("marker", 0, "a", 0).link("a", 0, "c", 0).link("c", 0, "a", 0)
	var levels := _levels(b.build())
	assert_int(levels["a"]).is_equal(4)
	assert_int(levels["c"]).is_equal(4)

func test_levels_follow_graph_data_changes() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid").node("marker", "grid_size", {"cell_size": 64.0}).node("a", "add_tags")
	b.link("grid", 0, "marker", 0).link("marker", 0, "a", 0)
	var graph : FlowGraphResource = b.build()
	assert_int(FlowCompiledGraph.for_graph(graph).level_of("a")).is_equal(64)
	for n_data in graph.data.nodes:
		if n_data.name == &"marker":
			n_data.settings["cell_size"] = 16.0
	assert_int(FlowCompiledGraph.for_graph(graph).level_of("a")).is_equal(16)
	assert_int(FlowCompiledGraph.for_graph(graph).level_of("unknown")).is_equal(0)

# grid_size stays a pass-through: a marked graph evaluates exactly like the
# same graph without the marker outside world generation.
func test_marker_is_inert_outside_world_generation() -> void:
	var with_marker = TestGraph.new()
	with_marker.node("grid", "grid", {"x": 5, "z": 4}).node("marker", "grid_size", {"cell_size": 2.0}).node("out", "output", {"name": "r"})
	with_marker.link("grid", 0, "marker", 0).link("marker", 0, "out", 0)
	var plain = TestGraph.new()
	plain.node("grid", "grid", {"x": 5, "z": 4}).node("out", "output", {"name": "r"})
	plain.link("grid", 0, "out", 0)
	var a := FlowNodeIO.evaluate(with_marker.build())
	var c := FlowNodeIO.evaluate(plain.build())
	assert_dict(FlowNodeIO.snapshot_summarize_data(a["r"])).is_equal(FlowNodeIO.snapshot_summarize_data(c["r"]))
