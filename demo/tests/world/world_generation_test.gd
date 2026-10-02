# world_generation_test.gd
# WP5: per-cell execution (FlowGraphNode3D.generate_cell), partition
# invariance of world-aligned scatter graphs, parent-to-child data flow, cell
# order independence, threaded / cached / time-sliced equivalence.
class_name WorldGenerationTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const Util = preload("res://tests/world/support/world_test_util.gd")

const WB := AABB(Vector3(-40.0, -10.0, -40.0), Vector3(80.0, 30.0, 80.0))

## Stock samplers whose output does not depend on where the sampled region
## starts (world-anchored candidates with position- or cell-derived seeds).
const ALIGNED := ["grid", "surface_ppsm", "volume_shape", "to_point"]
## Stock samplers that place points relative to the region they are given (or
## draw a count of random points in it), so a cell does not reproduce its part
## of the monolithic result. See docs/_round2/WP5.md. Update this list if one
## becomes world-aligned.
const NOT_ALIGNED := ["surface_count", "surface_points", "grid_fill", "sample_points", "sample_points_random"]

func _world(graph : FlowGraphResource, seed : int = 0, bounds : AABB = WB) -> FlowWorld3D:
	return auto_free(Util.make_world(self, graph, bounds, seed))

func _all_cell_rows(world : FlowWorld3D, output_name : String) -> Dictionary:
	var result := {}
	for key in world.get_cells(FlowWorld3D.CellState.Generated):
		var data = world.get_cell_outputs(key.x, Vector2i(key.y, key.z)).get(output_name)
		result[key] = Util.rows([data]) if data is FlowData.Data else []
	return result

# --- FlowGraphNode3D.generate_cell ---------------------------------------------------------

func _two_level_flow_graph() -> FlowGraphResource:
	# Unbounded grid, passed whole to the 16 level; a 64-level bounds point per
	# coarse cell; the 16 level merges both with its own bounds point.
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 3, "y": 1, "z": 3, "step": Vector3(1, 1, 1), "origin": Vector3(100, 0, 100)})
	b.node("m16", "grid_size", {"cell_size": 16.0})
	b.node("m64", "grid_size", {"cell_size": 64.0})
	b.node("coarse_bounds", "get_execution_bounds", {"output_mode": 1})
	b.node("m16b", "grid_size", {"cell_size": 16.0})
	b.node("fine_bounds", "get_execution_bounds", {"output_mode": 1})
	b.node("merge", "merge")
	b.node("out_fine", "output", {"name": "fine"})
	b.node("out_coarse", "output", {"name": "coarse"})
	b.link("grid", 0, "m16", 0).link("m16", 0, "merge", 0)
	b.link("m64", 0, "coarse_bounds", 0).link("coarse_bounds", 0, "merge", 0).link("coarse_bounds", 0, "out_coarse", 0)
	b.link("m16b", 0, "fine_bounds", 0).link("fine_bounds", 0, "merge", 0)
	b.link("merge", 0, "out_fine", 0)
	return b.build()

func test_generate_cell_runs_only_its_level_with_preseeded_inputs() -> void:
	var graph := _two_level_flow_graph()
	var comp : FlowGraphNode3D = auto_free(FlowGraphNode3D.new())
	comp.generate_on_ready = false
	comp.graph = graph
	add_child(comp)
	var received := []
	comp.generated.connect(func(outputs): received.append(outputs))
	var cell := FlowWorldCell.for_graph(graph, 16, Vector2i(1, -1), WB)
	# Hand-made coarse results: the grid and one coarse bounds point.
	var grid_data := TestGraph.points([Vector3(7, 0, 7)])
	var coarse_point := TestGraph.points([Vector3(-99, 0, -99)])
	var outputs := comp.generate_cell(cell, {&"grid": [[grid_data]], &"coarse_bounds": [[coarse_point]]})
	assert_bool(outputs.has("fine")).is_true()
	# Coarser outputs are not produced by a fine cell.
	assert_bool(outputs.has("coarse")).is_false()
	var positions := Array(outputs["fine"].getVector3Container(FlowData.AttrPosition))
	assert_array(positions).contains_exactly_in_any_order([Vector3(7, 0, 7), Vector3(-99, 0, -99), cell.bounds.get_center()])
	assert_int(received.size()).is_equal(1)
	assert_object(comp.last_cell).is_same(cell)
	assert_bool(comp.is_generating()).is_false()
	# A coarse cell of the same component runs the coarse nodes only.
	var coarse := FlowWorldCell.for_graph(graph, 64, Vector2i(0, 0), WB)
	var coarse_out := comp.generate_cell(coarse)
	assert_bool(coarse_out.has("fine")).is_false()
	assert_that(coarse_out["coarse"].getVector3Container(FlowData.AttrPosition)[0]).is_equal(coarse.bounds.get_center())

func test_time_sliced_cell_run_and_cancel() -> void:
	var graph := _two_level_flow_graph()
	var comp : FlowGraphNode3D = auto_free(FlowGraphNode3D.new())
	comp.generate_on_ready = false
	comp.graph = graph
	add_child(comp)
	var cell := FlowWorldCell.for_graph(graph, 64, Vector2i(0, 0), WB)
	var run := comp.begin_cell(cell, {}, true)
	assert_int(run.progress()).is_equal(0)
	assert_bool(comp.is_generating()).is_true()
	assert_bool(run.step(0.0)).is_false()
	assert_int(run.progress()).is_equal(1)
	var steps := 1
	while not run.step(0.0):
		steps += 1
	assert_int(steps + 1).is_equal(run.node_count())
	assert_bool(run.outputs.has("coarse")).is_true()
	# Cancelling finalizes without publishing.
	var received := []
	comp.generated.connect(func(outputs): received.append(outputs))
	var second := comp.begin_cell(cell, {}, true)
	second.step(0.0)
	comp.cleanup()
	assert_bool(second.is_done()).is_true()
	assert_bool(second.was_cancelled()).is_true()
	assert_int(received.size()).is_equal(0)
	assert_bool(comp.is_generating()).is_false()

# --- partition invariance ------------------------------------------------------------------

func test_partition_invariance_of_world_aligned_samplers() -> void:
	for seed in [0, 4711]:
		for kind in ALIGNED:
			var graph := Util.scatter_graph(kind, 32)
			var mono := Util.monolithic(graph, WB, ["bounds"], "result", seed)
			var world := _world(graph, seed)
			world.generate_all()
			var parts := Util.cell_outputs(world, 32)
			assert_int(parts.size()).is_equal(16)
			var expected := Util.rows([mono])
			assert_int(expected.size()).override_failure_message("%s produced no points" % kind).is_greater(50)
			assert_bool(Util.rows(parts) == expected).override_failure_message("%s (seed %d): cells differ from the monolithic result" % [kind, seed]).is_true()
			world.cleanup_all()

func test_samplers_that_are_not_world_aligned() -> void:
	for kind in NOT_ALIGNED:
		var graph := Util.scatter_graph(kind, 32)
		var mono := Util.monolithic(graph, WB, ["bounds"])
		var world := _world(graph)
		world.generate_all()
		var same := Util.rows(Util.cell_outputs(world, 32)) == Util.rows([mono])
		assert_bool(same).override_failure_message("%s is now world-aligned: move it to ALIGNED and update WP5.md" % kind).is_false()
		world.cleanup_all()

# Two grid levels in one graph: each level's cells reproduce that level's part
# of the monolithic run.
func test_partition_invariance_on_two_levels() -> void:
	var b = TestGraph.new()
	b.node("m64", "grid_size", {"cell_size": 64.0}).node("bounds64", "get_execution_bounds")
	b.node("box", "make_bounds", {"output_mode": 1, "size": Vector3(90.0, 4.0, 90.0)})
	b.node("isect", "intersection").node("voxels", "volume_sampler", {"voxel_size": Vector3(5.0, 4.0, 5.0)})
	b.node("cull64", "cull_points_outside_bounds").node("out64", "output", {"name": "coarse"})
	b.link("m64", 0, "bounds64", 0).link("box", 0, "isect", 0).link("bounds64", 0, "isect", 1)
	b.link("isect", 0, "voxels", 0).link("voxels", 0, "cull64", 0).link("cull64", 0, "out64", 0)
	b.node("surface", "get_surface_data", {"source": 1, "heightmap_image": Util.heightmap(), "image_cell_size": 1.5, "image_height_scale": 4.0})
	b.node("m16", "grid_size", {"cell_size": 16.0}).node("bounds16", "get_execution_bounds")
	b.node("sampler", "surface_sampler", {"points_per_square_meter": 0.2, "use_bounding_shape": true, "random_seed": 3})
	b.node("cull16", "cull_points_outside_bounds").node("out16", "output", {"name": "fine"})
	b.link("m16", 0, "bounds16", 0).link("surface", 0, "sampler", 0).link("bounds16", 0, "sampler", 1)
	b.link("sampler", 0, "cull16", 0).link("cull16", 0, "out16", 0)
	var graph : FlowGraphResource = b.build()
	var overrides := {"bounds64/fallback_bounds": WB, "bounds16/fallback_bounds": WB}
	var mono := FlowNodeIO.evaluate(graph, {}, 99, {}, null, overrides)
	var world := _world(graph, 99)
	world.generate_all()
	assert_array(Array(world.get_levels())).is_equal([0, 64, 16])
	assert_int(Util.cell_outputs(world, 64, "coarse").size()).is_equal(4)
	assert_int(Util.cell_outputs(world, 16, "fine").size()).is_equal(36)
	var expected_coarse := Util.rows([Util.cull(mono["coarse"], WB)])
	var expected_fine := Util.rows([Util.cull(mono["fine"], WB)])
	assert_int(expected_coarse.size()).is_greater(50)
	assert_int(expected_fine.size()).is_greater(50)
	assert_bool(Util.rows(Util.cell_outputs(world, 64, "coarse")) == expected_coarse).is_true()
	assert_bool(Util.rows(Util.cell_outputs(world, 16, "fine")) == expected_fine).is_true()

# --- parent-to-child data flow ------------------------------------------------------------

func test_coarser_results_flow_whole_into_finer_cells_and_are_computed_once() -> void:
	var world := _world(_two_level_flow_graph(), 0, AABB(Vector3(-64, -8, -64), Vector3(128, 16, 128)))
	var generated := {}
	world.cell_generated.connect(func(level, coord): generated[FlowWorldCell.key_of(level, coord)] = generated.get(FlowWorldCell.key_of(level, coord), 0) + 1)
	world.generate_all()
	assert_int(world.get_cells(FlowWorld3D.CellState.Generated).size()).is_equal(1 + 4 + 64)
	for key in generated:
		assert_int(generated[key]).override_failure_message("%s generated %d times" % [key, generated[key]]).is_equal(1)
	var grid_positions := []
	for x in range(3):
		for z in range(3):
			grid_positions.append(Vector3(100 + x, 0, 100 + z))
	for coord in [Vector2i(-4, -4), Vector2i(-1, 2), Vector2i(3, 3), Vector2i(0, -1)]:
		var fine : FlowData.Data = world.get_cell_outputs(16, coord)["fine"]
		var positions := Array(fine.getVector3Container(FlowData.AttrPosition))
		var parent := FlowWorldGrid.parent_coord(coord, 16, 64)
		var expected := grid_positions.duplicate()
		expected.append(world.get_cell_bounds(64, parent).get_center())
		expected.append(world.get_cell_bounds(16, coord).get_center())
		assert_array(positions).contains_exactly_in_any_order(expected)
	# The parents are what get_parent_cells() reports.
	assert_array(world.get_parent_cells(16, Vector2i(-1, 2))).is_equal([Vector3i(0, 0, 0), Vector3i(64, -1, 0)])

func test_variables_and_cell_fields_reach_nested_subgraphs() -> void:
	var inner = TestGraph.new()
	inner.out_param("b").out_param("v")
	inner.node("inner_bounds", "get_execution_bounds").node("ob", "output", {"name": "b"})
	inner.node("get", "get_variable", {"variable_name": "shared"}).node("ov", "output", {"name": "v"})
	inner.link("inner_bounds", 0, "ob", 0).link("get", 0, "ov", 0)
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 2, "y": 1, "z": 1}).node("set", "set_variable", {"variable_name": "shared"})
	b.link("grid", 0, "set", 0)
	# A set_variable only runs when something reads it (it is not an execution
	# root): an Unbounded reader makes it run in the Unbounded cell.
	b.node("get_top", "get_variable", {"variable_name": "shared"}).node("out_top", "output", {"name": "top_var"})
	b.link("get_top", 0, "out_top", 0)
	b.node("m32", "grid_size", {"cell_size": 32.0}).node("sub", "subgraph", {"graph": inner.build()})
	b.node("out_b", "output", {"name": "nested_bounds"}).node("out_v", "output", {"name": "nested_var"})
	b.link("m32", 0, "sub", 0).link("sub", 0, "out_b", 0).link("sub", 1, "out_v", 0)
	var world := _world(b.build())
	world.generate_cell(32, Vector2i(-1, 0))
	var outputs := world.get_cell_outputs(32, Vector2i(-1, 0))
	assert_array(world.get_cell_errors(32, Vector2i(-1, 0))).is_empty()
	var nested_bounds : FlowData.Data = outputs["nested_bounds"]
	assert_that(nested_bounds.shape.get_bounds()).is_equal(world.get_cell_bounds(32, Vector2i(-1, 0)))
	assert_float(nested_bounds.get_data_attr("grid_size")).is_equal(32.0)
	assert_int(nested_bounds.get_data_attr("cell_x")).is_equal(-1)
	assert_int(nested_bounds.get_data_attr("hierarchy_level")).is_equal(1)
	assert_int(outputs["nested_var"].size()).is_equal(2)
	# The variable was published by the Unbounded cell.
	assert_int(world.get_cell_state(0, Vector2i.ZERO)).is_equal(FlowWorld3D.CellState.Generated)
	assert_int(world.get_cell_outputs(0, Vector2i.ZERO)["top_var"].size()).is_equal(2)

# --- order independence, modes -------------------------------------------------------------

# Surface scatter at 16 plus pure (cacheable) nodes: an attribute on the
# culled points and a transform of Unbounded data handed whole to every cell.
func _mixed_graph() -> FlowGraphResource:
	var b = TestGraph.new()
	b.node("surface", "get_surface_data", {"source": 1, "heightmap_image": Util.heightmap(), "image_cell_size": 1.5, "image_height_scale": 4.0})
	b.node("marker", "grid_size", {"cell_size": 16.0}).node("bounds", "get_execution_bounds")
	b.node("sampler", "surface_sampler", {"points_per_square_meter": 0.3, "use_bounding_shape": true, "random_seed": 8})
	b.node("cull", "cull_points_outside_bounds")
	b.node("attr", "add_attribute", {"name": "w", "data_type": FlowData.DataType.Float, "cte_float": 0.25})
	b.node("grid", "grid", {"x": 4, "y": 1, "z": 4, "step": Vector3(9, 1, 9), "origin": Vector3(-18, 0, -18)})
	b.node("m_grid", "grid_size", {"cell_size": 16.0})
	b.node("move", "transform_points", {"random_seed": 6})
	b.node("merge", "merge").node("out", "output", {"name": "result"})
	b.link("marker", 0, "bounds", 0).link("surface", 0, "sampler", 0).link("bounds", 0, "sampler", 1)
	b.link("sampler", 0, "cull", 0).link("cull", 0, "attr", 0).link("attr", 0, "merge", 0)
	b.link("grid", 0, "m_grid", 0).link("m_grid", 0, "move", 0).link("move", 0, "merge", 0)
	b.link("merge", 0, "out", 0)
	return b.build()

func test_cell_order_does_not_change_results() -> void:
	var graph := _mixed_graph()
	var reference := _world(graph, 21)
	reference.generate_all()
	var expected := _all_cell_rows(reference, "result")
	var shuffled := _world(graph, 21)
	var coords : Array = FlowWorldGrid.cells_in(WB, 16, WB)
	coords.reverse()
	# Interleave: odd positions first, then the rest, fine cells before their
	# parents exist (generate_cell generates parents on demand).
	var order : Array = []
	for i in range(1, coords.size(), 2):
		order.append(coords[i])
	for i in range(0, coords.size(), 2):
		order.append(coords[i])
	for coord in order:
		shuffled.generate_cell(16, coord)
	assert_bool(_all_cell_rows(shuffled, "result") == expected).is_true()

func test_threaded_cached_and_time_sliced_cells_match() -> void:
	var graph := _mixed_graph()
	var reference := _world(graph, 5)
	reference.generate_all()
	var expected := _all_cell_rows(reference, "result")
	assert_int(expected.size()).is_equal(1 + 36)
	FlowOutputCache.clear()
	var hits_before := FlowOutputCache.hits
	var pooled_before := FlowExecutor.pooled_element_count
	for options in [{"threaded": true}, {"output_cache": true}, {"threaded": true, "output_cache": true}]:
		var world := _world(graph, 5)
		world.threaded = options.get("threaded", false)
		world.output_cache = options.get("output_cache", false)
		world.generate_all()
		assert_bool(_all_cell_rows(world, "result") == expected).override_failure_message("mode %s differs" % options).is_true()
		var comp := world.get_cell_component(16, Vector2i(0, 0))
		assert_bool(comp.threaded).is_equal(options.get("threaded", false))
		assert_bool(comp.output_cache).is_equal(options.get("output_cache", false))
	# The second cached run reused the first one's pure node outputs, and the
	# threaded runs used the worker pool.
	assert_int(FlowOutputCache.hits).is_greater(hits_before)
	assert_int(FlowExecutor.pooled_element_count).is_greater(pooled_before)
	# Time-sliced through the scheduler (OnLoad queue).
	var sliced := _world(graph, 5)
	sliced.frame_budget_ms = 0.0
	sliced.max_concurrent_cells = 3
	sliced.queue_all()
	var ticks := 0
	while sliced.is_busy() and ticks < 10000:
		sliced.tick()
		ticks += 1
	assert_bool(sliced.is_busy()).is_false()
	assert_int(ticks).is_greater(26)
	assert_bool(_all_cell_rows(sliced, "result") == expected).is_true()
	FlowOutputCache.clear()
