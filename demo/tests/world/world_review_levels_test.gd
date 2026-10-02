# world_review_levels_test.gd
# Adversarial review (WP13-R3) of the hierarchy: cell math far from the
# origin, extreme grid sizes, level analysis edge cases checked end to end
# through FlowWorld3D (diamonds, variables across levels, equal markers,
# disabled markers, graph edits between runs), shared coarse data that must
# not be corrupted by finer cells, generation order shuffles, and partition
# invariance re-derived on offset worlds with random seeds.
class_name WorldReviewLevelsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const Util = preload("res://tests/world/support/world_test_util.gd")

const WB := AABB(Vector3(-64.0, -8.0, -64.0), Vector3(128.0, 16.0, 128.0))

func _world(graph : FlowGraphResource, bounds : AABB = WB, seed : int = 0) -> FlowWorld3D:
	return auto_free(Util.make_world(self, graph, bounds, seed))

func _positions(data) -> Array:
	if not (data is FlowData.Data):
		return []
	return Array(data.getVector3Container(FlowData.AttrPosition))

# --- cell math ---------------------------------------------------------------------------

# For float32 positions near large offsets, on exact multiples of the size and
# just beside them, coord_of(p) is the one cell whose box owns p.
func test_ownership_is_a_partition_far_from_the_origin() -> void:
	var tall := AABB(Vector3(-1.0e9, -10.0, -1.0e9), Vector3(2.0e9, 20.0, 2.0e9))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var failures := []
	for size in [1, 2, 16, 64, 1024, 65536]:
		for offset in [0.0, -1.0e6, 1.0e6, 1.0e7, -1.0e7, 123456.789, -987654.321]:
			var samples : Array = []
			var k0 := int(floor(offset / size))
			for dk in range(-2, 3):
				var edge := float((k0 + dk) * size)
				samples.append(edge)
				var ulp := maxf(absf(edge) * 1.2e-7, 1.0e-6)
				samples.append(edge - ulp)
				samples.append(edge + ulp)
			for i in range(20):
				samples.append(offset + rng.randf_range(-3.0 * size, 3.0 * size))
			for x in samples:
				for z in [x, -x, offset]:
					# Round through Vector3 (float32), as real positions are.
					var p := Vector3(x, 0.0, z)
					var c := FlowWorldGrid.coord_of(p, size)
					if not FlowWorldGrid.owns(FlowWorldGrid.cell_aabb(c, size, tall), p):
						failures.append("size %d: %s not owned by its cell %s" % [size, p, c])
						continue
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if FlowWorldGrid.owns(FlowWorldGrid.cell_aabb(c + d, size, tall), p):
							failures.append("size %d: %s also owned by %s" % [size, p, c + d])
	assert_array(failures.slice(0, 10)).is_empty()

# A world smaller than one cell, or with zero height, still has exactly the
# cells its footprint touches, and each cell's execution bounds stay inside it.
func test_tiny_and_flat_worlds() -> void:
	var b = TestGraph.new()
	b.node("m", "grid_size", {"cell_size": 64.0}).node("bounds", "get_execution_bounds").node("o", "output", {"name": "b"})
	b.link("m", 0, "bounds", 0).link("bounds", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	for bounds in [AABB(Vector3(3, 0, 5), Vector3(2, 1, 2)), AABB(Vector3(60, 0, -2), Vector3(8, 0, 4)), AABB(Vector3(-1, 2, -1), Vector3(2, 0, 2))]:
		var world := _world(graph, bounds)
		world.generate_all()
		var cells := world.get_cells(FlowWorld3D.CellState.Generated)
		var expected := FlowWorldGrid.cells_in(bounds, 64, bounds)
		assert_int(cells.size()).is_equal(expected.size())
		for coord in expected:
			var shape_bounds : AABB = world.get_cell_outputs(64, coord)["b"].shape.get_bounds()
			assert_bool(bounds.encloses(shape_bounds)).override_failure_message("%s not inside %s" % [shape_bounds, bounds]).is_true()
			assert_float(shape_bounds.size.y).is_equal(bounds.size.y)
		world.cleanup_all()

# Grid sizes too large for the int32 level ids are clamped instead of
# wrapping to 0 or negative levels.
func test_extreme_grid_sizes_stay_valid_levels() -> void:
	for cell_size in [3.0e9, 1.0e12, INF]:
		var b = TestGraph.new()
		b.node("grid", "grid").node("m", "grid_size", {"cell_size": cell_size}).node("o", "output", {"name": "r"})
		b.link("grid", 0, "m", 0).link("m", 0, "o", 0)
		var compiled := FlowCompiledGraph.for_graph(b.build())
		var levels := Array(compiled.levels())
		assert_int(levels.size()).override_failure_message("cell_size %s: levels %s" % [cell_size, levels]).is_equal(2)
		assert_int(levels[0]).is_equal(0)
		assert_int(levels[1]).override_failure_message("cell_size %s: levels %s" % [cell_size, levels]).is_greater(0)
		assert_int(compiled.level_of("o")).is_equal(levels[1])
		assert_int(levels[1] & (levels[1] - 1)).is_equal(0)

# --- level analysis, end to end ----------------------------------------------------------

# Diamond with a marker on one branch only: grid -> m64 -> a; grid -> b; a, b
# -> merge. merge runs per 64 cell with b's whole Unbounded output.
func test_diamond_with_a_marker_on_one_branch() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 2, "y": 1, "z": 1, "step": Vector3(1, 1, 1), "origin": Vector3(500, 0, 500)})
	b.node("m64", "grid_size", {"cell_size": 64.0}).node("a", "add_tags", {"tags": "a"})
	b.node("bb", "add_tags", {"tags": "b"}).node("bounds", "get_execution_bounds", {"output_mode": 1})
	b.node("merge", "merge").node("o", "output", {"name": "r"})
	b.link("grid", 0, "m64", 0).link("m64", 0, "a", 0).link("grid", 0, "bb", 0)
	b.link("m64", 0, "bounds", 0)
	b.link("a", 0, "merge", 0).link("bb", 0, "merge", 0).link("bounds", 0, "merge", 0).link("merge", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	var compiled := FlowCompiledGraph.for_graph(graph)
	assert_int(compiled.level_of("bb")).is_equal(0)
	assert_int(compiled.level_of("merge")).is_equal(64)
	var world := _world(graph)
	world.generate_all()
	for coord in FlowWorldGrid.cells_in(WB, 64, WB):
		var positions := _positions(world.get_cell_outputs(64, coord).get("r"))
		var expected := [Vector3(500, 0, 500), Vector3(501, 0, 500), Vector3(500, 0, 500), Vector3(501, 0, 500), world.get_cell_bounds(64, coord).get_center()]
		assert_array(positions).contains_exactly_in_any_order(expected)
		assert_array(world.get_cell_errors(64, coord)).is_empty()

# set_variable on the 64 level, read by get_variable feeding the 16 level:
# get_variable is on the 64 level (it follows its set_variable), and every 16
# cell receives its containing 64 cell's value.
func test_variable_set_on_a_coarse_level_reaches_finer_cells() -> void:
	var b = TestGraph.new()
	b.node("m64", "grid_size", {"cell_size": 64.0}).node("cb", "get_execution_bounds", {"output_mode": 1})
	b.node("set", "set_variable", {"variable_name": "coarse_box"})
	b.node("get", "get_variable", {"variable_name": "coarse_box"})
	b.node("m16", "grid_size", {"cell_size": 16.0}).node("fb", "get_execution_bounds", {"output_mode": 1})
	b.node("merge", "merge").node("o", "output", {"name": "r"})
	b.link("m64", 0, "cb", 0).link("cb", 0, "set", 0)
	b.link("m16", 0, "fb", 0).link("get", 0, "merge", 0).link("fb", 0, "merge", 0).link("merge", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	var compiled := FlowCompiledGraph.for_graph(graph)
	assert_int(compiled.level_of("get")).is_equal(64)
	assert_int(compiled.level_of("merge")).is_equal(16)
	var world := _world(graph)
	var coords := FlowWorldGrid.cells_in(WB, 16, WB)
	# Fine cells first: their parents are generated on demand.
	for coord in coords:
		world.generate_cell(16, coord)
	for coord in coords:
		var parent := FlowWorldGrid.parent_coord(coord, 16, 64)
		var positions := _positions(world.get_cell_outputs(16, coord).get("r"))
		assert_array(positions).contains_exactly_in_any_order([world.get_cell_bounds(64, parent).get_center(), world.get_cell_bounds(16, coord).get_center()])
		assert_array(world.get_cell_errors(16, coord)).is_empty()

# Two markers with the same size on separate branches are one level; a
# disabled marker is still a marker (documented) and passes its data through.
func test_equal_and_disabled_markers() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 1, "y": 1, "z": 1, "origin": Vector3(1, 0, 1)})
	b.node("m1", "grid_size", {"cell_size": 32.0}).node("b1", "get_execution_bounds", {"output_mode": 1})
	b.node("m2", "grid_size", {"cell_size": 32.0, "disabled": true}).node("cull", "cull_points_outside_bounds")
	b.node("merge", "merge").node("o", "output", {"name": "r"})
	b.link("m1", 0, "b1", 0).link("grid", 0, "m2", 0).link("m2", 0, "cull", 0)
	b.link("b1", 0, "merge", 0).link("cull", 0, "merge", 0).link("merge", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	assert_array(Array(FlowCompiledGraph.for_graph(graph).levels())).is_equal([0, 32])
	var world := _world(graph)
	world.generate_all()
	for coord in FlowWorldGrid.cells_in(WB, 32, WB):
		var expected := [world.get_cell_bounds(32, coord).get_center()]
		if coord == Vector2i(0, 0):
			expected.append(Vector3(1, 0, 1))
		assert_array(_positions(world.get_cell_outputs(32, coord).get("r"))).contains_exactly_in_any_order(expected)

# Editing the graph between runs: the levels follow, and a runtime world drops
# the cells of a level that no longer exists instead of keeping them forever.
func test_graph_edit_between_runs() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 1, "y": 1, "z": 1})
	b.node("m", "grid_size", {"cell_size": 16.0}).node("bounds", "get_execution_bounds").node("o", "output", {"name": "r"})
	b.link("grid", 0, "m", 0).link("m", 0, "bounds", 0).link("bounds", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	var world := _world(graph)
	world.generation_mode = FlowWorld3D.GenerationMode.Runtime
	world.generation_radius = {0: 1000.0, 16: 20.0, 32: 20.0}
	world.source_provider = func(): return [Vector3(4, 0, 4)]
	world.clock = func(): return 0
	world.tick()
	assert_bool(world.is_busy()).is_false()
	assert_int(Array(world.get_cells()).filter(func(k): return k.x == 16).size()).is_greater(0)
	# The marker becomes 32: a new data dictionary, as the editor saves it.
	var data : Dictionary = graph.data.duplicate(true)
	for n in data["nodes"]:
		if n["name"] == &"m":
			n["settings"]["cell_size"] = 32.0
	graph.data = data
	assert_array(Array(world.get_levels())).is_equal([0, 32])
	for i in range(10):
		world.tick()
	assert_bool(world.is_busy()).is_false()
	var stale := Array(world.get_cells()).filter(func(k): return k.x == 16)
	assert_array(stale).override_failure_message("cells of the removed level 16 are kept: %s" % [stale]).is_empty()
	var fine := Array(world.get_cells(FlowWorld3D.CellState.Generated)).filter(func(k): return k.x == 32)
	assert_int(fine.size()).is_greater(0)
	for key in fine:
		var shape_bounds : AABB = world.get_cell_outputs(32, Vector2i(key.y, key.z))["r"].shape.get_bounds()
		assert_that(shape_bounds).is_equal(world.get_cell_bounds(32, Vector2i(key.y, key.z)))
	# Every child of the world is the component of a known cell.
	assert_int(world.get_child_count()).is_equal(world.get_cells().size())

# --- shared coarse data --------------------------------------------------------------------

# The coarse cell's captured Data is handed to every finer cell by reference.
# Finer cells (spawners, variables, pass-through culls, outputs) must leave
# it unchanged, and forwarding it must not let one cell's output alias
# another cell's mutable state.
func test_shared_coarse_data_is_not_mutated_by_finer_cells() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 8, "y": 1, "z": 8, "step": Vector3(16, 1, 16), "origin": Vector3(-56, 0, -56)})
	b.node("attr", "attribute_random", {"attribute_name": "w", "random_seed": 5})
	b.node("m16", "grid_size", {"cell_size": 16.0}).node("cull", "cull_points_outside_bounds", {"margin": 200.0})
	b.node("set", "set_variable", {"variable_name": "v"}).node("get", "get_variable", {"variable_name": "v"})
	b.node("spawn", "spawn_nodes", {}).node("dens", "density_remap", {})
	b.node("merge", "merge").node("o", "output", {"name": "r"})
	b.link("grid", 0, "attr", 0).link("attr", 0, "m16", 0).link("m16", 0, "cull", 0)
	b.link("cull", 0, "set", 0).link("cull", 0, "spawn", 0).link("spawn", 0, "dens", 0)
	b.link("get", 0, "merge", 0).link("dens", 0, "merge", 0).link("merge", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	var world := _world(graph)
	world.generate_cell(0, Vector2i.ZERO)
	var root = world._cells[FlowWorldCell.key_of(0, Vector2i.ZERO)]
	var captured : Array = root.captured.get(&"attr", root.captured.get("attr", []))
	assert_array(captured).is_not_empty()
	var shared : FlowData.Data = captured[0][0]
	var before := shared.content_hash()
	var before_size := shared.size()
	world.generate_all()
	assert_int(shared.content_hash()).is_equal(before)
	assert_int(shared.size()).is_equal(before_size)
	# The cull with a huge margin keeps everything and forwards its input as
	# is; the outputs still describe every point once per cell.
	for coord in FlowWorldGrid.cells_in(WB, 16, WB):
		assert_int(world.get_cell_outputs(16, coord)["r"].size()).is_equal(2 * before_size)

# Any generation order of cells over three levels (fine before coarse,
# shuffled) gives the same per-cell results as generate_all.
func test_shuffled_generation_orders_match() -> void:
	var b = TestGraph.new()
	b.node("surface", "get_surface_data", {"source": 1, "heightmap_image": Util.heightmap(), "image_cell_size": 2.0, "image_height_scale": 4.0})
	b.node("m32", "grid_size", {"cell_size": 32.0}).node("b32", "get_execution_bounds")
	b.node("s32", "surface_sampler", {"points_per_square_meter": 0.05, "use_bounding_shape": true, "random_seed": 4})
	b.node("c32", "cull_points_outside_bounds")
	b.node("m8", "grid_size", {"cell_size": 8.0}).node("b8", "get_execution_bounds")
	b.node("s8", "surface_sampler", {"points_per_square_meter": 0.2, "use_bounding_shape": true, "random_seed": 6})
	b.node("c8", "cull_points_outside_bounds")
	b.node("diff", "difference", {}).node("o", "output", {"name": "r"}).node("o32", "output", {"name": "coarse"})
	b.link("m32", 0, "b32", 0).link("surface", 0, "s32", 0).link("b32", 0, "s32", 1).link("s32", 0, "c32", 0).link("c32", 0, "o32", 0)
	b.link("m8", 0, "b8", 0).link("surface", 0, "s8", 0).link("b8", 0, "s8", 1).link("s8", 0, "c8", 0)
	b.link("c8", 0, "diff", 0).link("c32", 0, "diff", 1).link("diff", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	var bounds := AABB(Vector3(-32, -10, -32), Vector3(64, 30, 64))
	var reference := _world(graph, bounds, 17)
	reference.generate_all()
	var expected := {}
	for key in reference.get_cells(FlowWorld3D.CellState.Generated):
		expected[key] = Util.rows(reference.get_cell_outputs(key.x, Vector2i(key.y, key.z)).values())
	assert_int(expected.size()).is_equal(1 + 4 + 64)
	var keys : Array = expected.keys()
	var rng := RandomNumberGenerator.new()
	for trial in range(3):
		rng.seed = 1000 + trial
		var order := keys.duplicate()
		for i in range(order.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = order[i]
			order[i] = order[j]
			order[j] = t
		var world := _world(graph, bounds, 17)
		for key in order:
			world.generate_cell(key.x, Vector2i(key.y, key.z))
		for key in keys:
			var got := Util.rows(world.get_cell_outputs(key.x, Vector2i(key.y, key.z)).values())
			assert_bool(got == expected[key]).override_failure_message("trial %d: cell %s differs" % [trial, key]).is_true()
		world.cleanup_all()

# --- partition invariance, re-derived --------------------------------------------------------

# The world-aligned samplers on worlds that are offset and not aligned to the
# grid, with random seeds and two grid sizes: the union of the cells equals
# the monolithic run culled to the world.
func test_partition_invariance_on_offset_worlds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2468
	var worlds := [AABB(Vector3(-37.3, -10.0, -21.7), Vector3(71.9, 30.0, 58.1)), AABB(Vector3(-5.5, -10.0, 3.25), Vector3(43.0, 30.0, 35.5))]
	var failures := []
	for kind in ["surface_ppsm", "volume_shape", "to_point", "grid_fill_anchored", "grid"]:
		for wb in worlds:
			for grid in [16, 32]:
				var seed := rng.randi_range(1, 1 << 30)
				var graph := Util.scatter_graph(kind, grid)
				var mono := Util.monolithic(graph, wb, ["bounds"], "result", seed)
				var world := _world(graph, wb, seed)
				world.generate_all()
				var parts := Util.cell_outputs(world, grid)
				assert_int(parts.size()).is_equal(FlowWorldGrid.cells_in(wb, grid, wb).size())
				var expected := Util.rows([mono])
				if expected.size() < 10:
					failures.append("%s %s grid %d: only %d points" % [kind, wb, grid, expected.size()])
				elif Util.rows(parts) != expected:
					failures.append("%s %s grid %d seed %d: cells differ (%d vs %d rows)" % [kind, wb, grid, seed, Util.rows(parts).size(), expected.size()])
				world.cleanup_all()
	assert_array(failures).is_empty()

# A grid_size marker inside a loop body is a pass-through (documented): the
# outer graph's levels ignore it and the body runs whole inside the cell.
func test_marker_inside_a_loop_body_is_a_pass_through() -> void:
	var body = TestGraph.new()
	body.in_param("item", FlowData.DataType.Vector)
	body.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Vector})
	body.node("m8", "grid_size", {"cell_size": 8.0}).node("eb", "get_execution_bounds", {"output_mode": 1})
	body.node("out", "output", {"name": "result"})
	body.link("in_item", 0, "m8", 0).link("m8", 0, "eb", 0).link("eb", 0, "out", 0)
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 2, "y": 1, "z": 1, "step": Vector3(1, 1, 1), "origin": Vector3(1, 0, 1)})
	b.node("m32", "grid_size", {"cell_size": 32.0}).node("cull", "cull_points_outside_bounds")
	b.node("loop", "loop", {"graph": body.build(), "item_input_name": "item", "output_attribute_name": "result"})
	b.node("o", "output", {"name": "r"})
	b.link("grid", 0, "m32", 0).link("m32", 0, "cull", 0).link("cull", 0, "loop", 0).link("loop", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	assert_array(Array(FlowCompiledGraph.for_graph(graph).levels())).is_equal([0, 32])
	var world := _world(graph)
	world.generate_cell(32, Vector2i(0, 0))
	world.generate_cell(32, Vector2i(-1, 0))
	assert_array(world.get_cell_errors(32, Vector2i(0, 0))).is_empty()
	assert_array(world.get_cell_errors(32, Vector2i(-1, 0))).is_empty()
	assert_bool(world.get_cell_outputs(32, Vector2i(0, 0)).get("r") is FlowData.Data).is_true()
