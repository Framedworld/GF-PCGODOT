# world_review_scheduler_test.gd
# Adversarial review (WP13-R3) of the FlowWorld3D scheduler and manual API:
# cancelled runs wanted again, radius extremes, budget and concurrency limits,
# re-entry from signal handlers, freeing the world mid-generation, signal
# pairing under churn, settings changes before a forced regeneration.
# Injected clock and source provider throughout; no real frames except where
# _process itself is under test.
class_name WorldReviewSchedulerTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const Util = preload("res://tests/world/support/world_test_util.gd")

const WB := AABB(Vector3(-128.0, -8.0, -128.0), Vector3(256.0, 16.0, 256.0))

var _sources : Array = []
var _now : int = 0
var _tick_us : int = 0

func before_test() -> void:
	_sources = [Vector3(8, 0, 8)]
	_now = 0
	_tick_us = 0

# Unbounded grid -> 64 level (add_tags) -> 16 level (add_tags), an output on
# every level; the 16 level consumes the 64 level, which consumes the grid.
func _graph() -> FlowGraphResource:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 1, "y": 1, "z": 1})
	b.node("m64", "grid_size", {"cell_size": 64.0}).node("c64", "add_tags").node("o64", "output", {"name": "coarse"})
	b.node("m16", "grid_size", {"cell_size": 16.0}).node("f16", "add_tags").node("o16", "output", {"name": "fine"})
	b.node("o0", "output", {"name": "unbounded"})
	b.link("grid", 0, "o0", 0).link("grid", 0, "m64", 0).link("m64", 0, "c64", 0).link("c64", 0, "o64", 0)
	b.link("c64", 0, "m16", 0).link("m16", 0, "f16", 0).link("f16", 0, "o16", 0)
	return b.build()

func _clock() -> int:
	_now += _tick_us
	return _now

func _world(mode : int = FlowWorld3D.GenerationMode.Runtime, graph : FlowGraphResource = null, bounds : AABB = WB) -> FlowWorld3D:
	var world := FlowWorld3D.new()
	world.graph = graph if graph != null else _graph()
	world.world_bounds = bounds
	world.generation_mode = mode
	world.generation_radius = {0: 1000.0, 64: 40.0, 16: 12.0}
	world.clock = _clock
	world.source_provider = func(): return _sources
	world.frame_budget_ms = 4.0
	add_child(world)
	return auto_free(world)

func _settle(world : FlowWorld3D, max_ticks : int = 20000) -> int:
	var ticks := 0
	world.tick()
	ticks += 1
	while world.is_busy() and ticks < max_ticks:
		world.tick()
		ticks += 1
	assert_bool(world.is_busy()).override_failure_message("scheduler did not settle").is_false()
	return ticks

# Every Generated cell really ran: its level's output is there.
func _assert_generated_cells_have_outputs(world : FlowWorld3D) -> void:
	var names := {0: "unbounded", 64: "coarse", 16: "fine"}
	for key in world.get_cells(FlowWorld3D.CellState.Generated):
		var outputs := world.get_cell_outputs(key.x, Vector2i(key.y, key.z))
		var data = outputs.get(names[key.x])
		assert_bool(data is FlowData.Data and data.size() == 1).override_failure_message("cell %s is Generated but has no '%s' output (%s)" % [key, names[key.x], outputs]).is_true()

func _in_flight(world : FlowWorld3D, level : int) -> Array:
	return Array(world.get_cells(FlowWorld3D.CellState.Generating)).filter(func(k): return k.x == level)

# Two 16 cells in flight, then the source leaves: both runs are cancelled and
# at most one of them is cleaned up this tick (one unit of work per tick).
func _cancel_two_in_flight(world : FlowWorld3D) -> Array:
	world.max_concurrent_cells = 2
	world.frame_budget_ms = 0.0
	_tick_us = 1000
	var in_flight : Array = []
	for i in range(400):
		world.tick()
		in_flight = _in_flight(world, 16)
		if in_flight.size() == 2:
			break
	assert_int(in_flight.size()).is_equal(2)
	_sources = [Vector3(-110, 0, 110)]
	world.tick()
	var waiting : Array = []
	for key in in_flight:
		if world.get_cell_state(key.x, Vector2i(key.y, key.z)) == FlowWorld3D.CellState.CleaningUp:
			waiting.append(key)
	assert_array(waiting).is_not_empty()
	return waiting

# A run cancelled by the scheduler leaves the cell in CleaningUp. If the cell
# is wanted again before that cleanup ran, it must be generated again, not
# revived as Generated without outputs (and without its coarse data).
func test_cancelled_cell_wanted_again_is_generated_again() -> void:
	var world := _world()
	var generated := {}
	world.cell_generated.connect(func(level, coord): generated[FlowWorldCell.key_of(level, coord)] = true)
	var waiting := _cancel_two_in_flight(world)
	_sources = [Vector3(8, 0, 8)]
	world.frame_budget_ms = 4.0
	_tick_us = 0
	_settle(world)
	for key in waiting:
		assert_int(world.get_cell_state(key.x, Vector2i(key.y, key.z))).is_equal(FlowWorld3D.CellState.Generated)
		assert_bool(generated.has(key)).override_failure_message("%s never emitted cell_generated" % key).is_true()
	_assert_generated_cells_have_outputs(world)

# The same through the manual API: generate_cell() on a cell whose run was
# cancelled must run it, not return its empty outputs.
func test_generate_cell_on_a_cancelled_cell_generates_it() -> void:
	var world := _world()
	var waiting := _cancel_two_in_flight(world)
	var key : Vector3i = waiting[0]
	var outputs := world.generate_cell(key.x, Vector2i(key.y, key.z))
	assert_bool(outputs.get("fine") is FlowData.Data).override_failure_message("generate_cell returned %s" % outputs).is_true()
	assert_int(world.get_cell_state(key.x, Vector2i(key.y, key.z))).is_equal(FlowWorld3D.CellState.Generated)
	assert_object(world.get_cell_component(key.x, Vector2i(key.y, key.z))).is_not_null()

# A very large finite radius means "everything in the world", like INF.
func test_huge_generation_radius_covers_the_world() -> void:
	for radius in [1.0e30, INF, 1.0e12]:
		_sources = [Vector3(8, 0, 8)]
		var world := _world()
		world.generation_radius = {0: 1000.0, 64: radius, 16: 12.0}
		_settle(world)
		var coarse := Array(world.get_cells(FlowWorld3D.CellState.Generated)).filter(func(k): return k.x == 64)
		assert_int(coarse.size()).override_failure_message("radius %s generated %d of 16 coarse cells" % [radius, coarse.size()]).is_equal(16)
		world.cleanup_all()

# A radius that would pull in millions of cells is capped: each tick stays
# bounded (MAX_RUNTIME_CELLS_PER_LEVEL around each source), the cells kept are
# the ones nearest the source, and the scheduler still makes progress.
func test_runtime_radius_is_capped() -> void:
	var b = TestGraph.new()
	b.node("m1", "grid_size", {"cell_size": 1.0}).node("bounds", "get_execution_bounds").node("o", "output", {"name": "fine"})
	b.link("m1", 0, "bounds", 0).link("bounds", 0, "o", 0)
	var cap : int = FlowWorld3D.MAX_RUNTIME_CELLS_PER_LEVEL
	# 40 000 cells in range, then 4e12 (a 2e6 x 2e6 world at grid size 1).
	for half_extent in [100.0, 1.0e6]:
		var bounds := AABB(Vector3(-half_extent, -1.0, -half_extent), Vector3(2.0 * half_extent, 2.0, 2.0 * half_extent))
		var world := _world(FlowWorld3D.GenerationMode.Runtime, b.build(), bounds)
		world.generation_radius = {1: 5.0e5}
		_sources = [Vector3(10.5, 0, -20.5)]
		_tick_us = 1000
		var started := Time.get_ticks_msec()
		world.tick()
		var known := world.get_cells().size()
		assert_int(known).is_greater(0)
		assert_int(known).is_less_equal(cap)
		# The source's own cell and its neighbours are among them, and they
		# are generated first.
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				assert_int(world.get_cell_state(1, Vector2i(10 + dx, -21 + dz))).is_not_equal(FlowWorld3D.CellState.NONE)
		world.tick()
		assert_int(world.get_cell_state(1, Vector2i(10, -21))).is_equal(FlowWorld3D.CellState.Generated)
		assert_int(Time.get_ticks_msec() - started).is_less(20000)
		# A source outside the world still gets the world cells nearest to it.
		_sources = [Vector3(-half_extent - 1000.0, 0, 0)]
		world.tick()
		assert_int(world.get_cell_state(1, Vector2i(int(-half_extent), 0))).is_not_equal(FlowWorld3D.CellState.NONE)
		world.cleanup_all()
		world.free()

# Zero or negative budgets and concurrency still make progress (one unit of
# work per tick, at least one cell at a time).
func test_degenerate_budget_and_concurrency_settle() -> void:
	for budget in [0.0, -5.0]:
		for concurrent in [0, -3]:
			_sources = [Vector3(8, 0, 8)]
			var world := _world()
			world.frame_budget_ms = budget
			world.max_concurrent_cells = concurrent
			_tick_us = 1000
			_settle(world)
			assert_int(world.get_cells(FlowWorld3D.CellState.Generated).size()).is_equal(1 + 4 + 9)
			_assert_generated_cells_have_outputs(world)
			world.cleanup_all()

# Under churn (a source jumping around with tiny budgets) a cell never emits
# cell_generated twice without a cell_cleaned_up in between, and every
# Generated cell really ran. (A cancelled run emits cell_cleaned_up without a
# cell_generated before it: documented, "a generated (or generating) cell".)
func test_signals_under_churn() -> void:
	var world := _world()
	world.max_concurrent_cells = 3
	world.frame_budget_ms = 0.002
	_tick_us = 1
	var last := {}
	var violations := []
	world.cell_generated.connect(func(level, coord):
		var k := FlowWorldCell.key_of(level, coord)
		if last.get(k, "") == "g":
			violations.append("%s generated twice" % k)
		last[k] = "g")
	world.cell_cleaned_up.connect(func(level, coord):
		last[FlowWorldCell.key_of(level, coord)] = "c")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in range(600):
		if i % 7 == 0:
			_sources = [Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-120, 120))]
		world.tick()
		if i % 50 == 0:
			_assert_generated_cells_have_outputs(world)
	_settle(world)
	assert_array(violations).is_empty()
	_assert_generated_cells_have_outputs(world)
	# Exactly the cells the final source wants (plus nothing stale).
	for key in world.get_cells():
		assert_int(world.get_cell_state(key.x, Vector2i(key.y, key.z))).is_equal(FlowWorld3D.CellState.Generated)

# A cell_generated handler may call back into the world.
func test_reentry_from_cell_generated_handlers() -> void:
	var world := _world()
	world.max_concurrent_cells = 2
	var calls := [0]
	world.cell_generated.connect(func(level, coord):
		calls[0] += 1
		if calls[0] == 3:
			# Synchronously generate a far cell from inside the tick.
			world.generate_cell(16, Vector2i(-8, -8))
		elif calls[0] == 6:
			world.cleanup_cell(64, Vector2i(0, 0)))
	_settle(world)
	assert_int(world.get_cell_state(16, Vector2i(-8, -8))).is_equal(FlowWorld3D.CellState.Generated)
	_assert_generated_cells_have_outputs(world)
	# Nothing is left generating without a run.
	for key in world.get_cells():
		var comp := world.get_cell_component(key.x, Vector2i(key.y, key.z))
		assert_bool(comp == null or not comp.is_generating()).is_true()
	# cleanup_all from a handler stops everything.
	var world2 := _world()
	world2.max_concurrent_cells = 2
	world2.cell_generated.connect(func(_l, _c): world2.cleanup_all(), CONNECT_ONE_SHOT)
	world2.generation_mode = FlowWorld3D.GenerationMode.OnLoad
	world2.queue_all()
	world2.tick()
	assert_array(world2.get_cells()).is_empty()
	assert_bool(world2.is_busy()).is_false()

# Freeing the world while cells are generating cancels the runs, releases
# their elements and frees every component (pooled ones included).
func test_freeing_the_world_mid_generation() -> void:
	var world := FlowWorld3D.new()
	world.graph = _graph()
	world.world_bounds = WB
	world.generation_mode = FlowWorld3D.GenerationMode.Runtime
	world.generation_radius = {0: 1000.0, 64: 40.0, 16: 12.0}
	world.clock = _clock
	world.source_provider = func(): return _sources
	world.max_concurrent_cells = 2
	world.frame_budget_ms = 0.0
	_tick_us = 1000
	add_child(world)
	_settle(world)
	# Pool something, then put two cells in flight.
	_sources = [Vector3(100, 0, 100)]
	for i in range(30):
		world.tick()
	var runs := []
	for key in world.get_cells(FlowWorld3D.CellState.Generating):
		runs.append(world.get_cell_component(key.x, Vector2i(key.y, key.z))._cell_run)
	assert_array(runs).is_not_empty()
	var comps := []
	for child in world.get_children():
		comps.append(weakref(child))
	assert_int(world.get_pool_size()).is_greater(0)
	world.free()
	for run in runs:
		assert_bool(run.is_done()).is_true()
		assert_bool(run.was_cancelled()).is_true()
		assert_bool(run.executor.state.get("instances", {}).is_empty()).is_true()
	for ref in comps:
		assert_object(ref.get_ref()).is_null()

# Changing the world's seed, params or overrides and forcing a regeneration
# regenerates the cell with the new values, as a fresh world would.
func test_forced_regeneration_uses_current_world_settings() -> void:
	var b = TestGraph.new()
	b.node("m16", "grid_size", {"cell_size": 16.0}).node("bounds", "get_execution_bounds", {"output_mode": 1})
	b.node("fill", "grid_fill_bounds", {"cell_size": Vector3(4, 1, 4), "copy_input_attributes": false, "world_anchored": true})
	b.node("noise", "attribute_random", {"attribute_name": "r", "random_seed": 3})
	b.node("o", "output", {"name": "fine"})
	b.link("m16", 0, "bounds", 0).link("bounds", 0, "fill", 0).link("fill", 0, "noise", 0).link("noise", 0, "o", 0)
	var graph : FlowGraphResource = b.build()
	var world := _world(FlowWorld3D.GenerationMode.Manual, graph)
	world.seed = 1
	world.generate_cell(16, Vector2i(0, 0))
	world.seed = 777
	world.generate_cell(16, Vector2i(0, 0), true)
	var fresh := _world(FlowWorld3D.GenerationMode.Manual, graph)
	fresh.seed = 777
	fresh.generate_cell(16, Vector2i(0, 0))
	var got := Util.rows([world.get_cell_outputs(16, Vector2i(0, 0))["fine"]])
	var want := Util.rows([fresh.get_cell_outputs(16, Vector2i(0, 0))["fine"]])
	assert_int(want.size()).is_greater(0)
	assert_bool(got == want).override_failure_message("forced regeneration kept the old seed").is_true()
	assert_int(world.get_cell_component(16, Vector2i(0, 0)).seed).is_equal(777)

# After OnLoad has gone idle (and stopped processing), queue_bounds still
# gets generated by the per-frame driver.
func test_queue_bounds_after_on_load_went_idle_is_generated() -> void:
	var world := FlowWorld3D.new()
	world.graph = _graph()
	world.world_bounds = AABB(Vector3(-32, -8, -32), Vector3(64, 16, 64))
	world.generation_mode = FlowWorld3D.GenerationMode.OnLoad
	world.source_provider = func(): return []
	add_child(world)
	auto_free(world)
	for i in range(200):
		await get_tree().process_frame
		if not world.is_busy():
			break
	assert_bool(world.is_busy()).is_false()
	world.cleanup_cell(16, Vector2i(0, 0))
	world.queue_bounds(AABB(Vector3(1, 0, 1), Vector3(2, 1, 2)))
	assert_bool(world.is_busy()).is_true()
	for i in range(200):
		await get_tree().process_frame
		if not world.is_busy():
			break
	assert_int(world.get_cell_state(16, Vector2i(0, 0))).is_equal(FlowWorld3D.CellState.Generated)

# Pooled components come back clean: new name and meta, no old content, their
# own cell, and the pool never holds more than cell_pool_size.
func test_pool_reuse_resets_components_and_stays_bounded() -> void:
	var world := _world()
	world.cell_pool_size = 2
	_settle(world)
	var max_pool := 0
	for p in [Vector3(-100, 0, -100), Vector3(100, 0, -100), Vector3(100, 0, 100), Vector3(8, 0, 8)]:
		_sources = [p]
		var ticks := 0
		world.tick()
		while world.is_busy() and ticks < 20000:
			max_pool = maxi(max_pool, world.get_pool_size())
			world.tick()
			ticks += 1
		max_pool = maxi(max_pool, world.get_pool_size())
	assert_int(max_pool).is_less_equal(2)
	assert_int(world.components_reused).is_greater(0)
	for key in world.get_cells(FlowWorld3D.CellState.Generated):
		var coord := Vector2i(key.y, key.z)
		var comp := world.get_cell_component(key.x, coord)
		assert_str(String(comp.name)).is_equal(FlowWorldGrid.cell_name(key.x, coord))
		assert_that(comp.get_meta(&"flow_cell")).is_equal(key)
		assert_that(comp.last_cell.key()).is_equal(key)
		assert_object(comp.get_parent()).is_same(world)
	assert_int(world.get_child_count()).is_equal(world.get_cells().size())
	_assert_generated_cells_have_outputs(world)

# The Unbounded level has one cell, (0, 0). Every API normalises the
# coordinate the same way, so a query with another coordinate finds it.
func test_unbounded_coordinates_are_normalised_everywhere() -> void:
	var world := _world(FlowWorld3D.GenerationMode.Manual)
	var outputs := world.generate_cell(0, Vector2i(5, -3))
	assert_bool(outputs.get("unbounded") is FlowData.Data).is_true()
	assert_int(world.get_cell_state(0, Vector2i(5, -3))).is_equal(FlowWorld3D.CellState.Generated)
	assert_dict(world.get_cell_outputs(0, Vector2i(7, 7))).is_equal(outputs)
	assert_object(world.get_cell_component(0, Vector2i(1, 0))).is_same(world.get_cell_component(0, Vector2i.ZERO))
	assert_array(world.get_cells()).is_equal([Vector3i(0, 0, 0)])
	world.cleanup_cell(0, Vector2i(2, 2))
	assert_array(world.get_cells()).is_empty()

# Sources that are freed, disabled or moved between ticks are handled; a
# custom provider may return a freed node.
func test_sources_freed_or_disabled_mid_run() -> void:
	var world := _world()
	var src : FlowGenerationSource = FlowGenerationSource.new()
	add_child(src)
	src.global_position = Vector3(8, 0, 8)
	world.source_provider = Callable()
	world.max_concurrent_cells = 1
	_tick_us = 1000
	world.frame_budget_ms = 0.0
	for i in range(20):
		world.tick()
	src.enabled = false
	world.tick()
	src.enabled = true
	src.global_position = Vector3(-100, 0, -100)
	world.tick()
	src.free()
	_settle(world)
	assert_array(Array(world.get_cells())).is_empty()
	# A provider that hands out a freed node.
	var provided : Array = [Node3D.new(), Vector3(8, 0, 8)]
	provided[0].free()
	world.source_provider = func(): return provided
	_tick_us = 0
	_settle(world)
	assert_int(world.get_cells(FlowWorld3D.CellState.Generated).size()).is_equal(1 + 4 + 9)

# Reparenting the world (or taking it out of the tree for a while) in the
# middle of generation keeps every cell and finishes the work.
func test_reparenting_mid_generation() -> void:
	var world := _world()
	world.max_concurrent_cells = 2
	world.frame_budget_ms = 0.0
	_tick_us = 1000
	for i in range(15):
		world.tick()
	assert_bool(world.is_busy()).is_true()
	var holder : Node3D = auto_free(Node3D.new())
	add_child(holder)
	world.reparent(holder)
	for i in range(5):
		world.tick()
	holder.remove_child(world)
	add_child(world)
	_settle(world)
	assert_int(world.get_cells(FlowWorld3D.CellState.Generated).size()).is_equal(1 + 4 + 9)
	_assert_generated_cells_have_outputs(world)
	assert_int(world.get_child_count()).is_equal(world.get_cells().size())

# An idle runtime tick must not cost one compiled-graph lookup per cell. A
# lookup hashes the whole graph data (FlowCompiledGraph.is_valid_for), so
# with a large graph and a few hundred cells an idle frame cost hundreds of
# lookups. The graph data here is padded so that one lookup is measurable;
# the idle tick must stay within a few lookups' worth of time, measured in
# the same run (self-calibrating, no absolute timing).
func test_idle_tick_does_not_look_up_the_graph_per_cell() -> void:
	var graph := _graph()
	var data : Dictionary = graph.data.duplicate(true)
	var padding := []
	for i in range(2000):
		padding.append({"note": "padding %d" % i, "value": i})
	data["frames"] = padding
	graph.data = data
	var world := _world(FlowWorld3D.GenerationMode.Runtime, graph)
	world.generation_radius = {0: 1000.0, 64: 100.0, 16: 90.0}
	_settle(world)
	var cells := world.get_cells().size()
	assert_int(cells).is_greater(100)
	var lookups := 10
	var t0 := Time.get_ticks_usec()
	for i in range(lookups):
		world.get_levels()
	var per_lookup := float(Time.get_ticks_usec() - t0) / lookups
	var best := INF
	for i in range(3):
		var s := Time.get_ticks_usec()
		world.tick()
		best = minf(best, float(Time.get_ticks_usec() - s))
	assert_bool(world.is_busy()).is_false()
	# Before: about `cells` lookups per idle tick. Allow 20.
	assert_float(best).override_failure_message("idle tick %.0f us, one lookup %.0f us, %d cells" % [best, per_lookup, cells]).is_less(20.0 * per_lookup + 20000.0)

# Switching generation_mode to Runtime after the world is ready (for example
# after a loading screen) starts the per-frame scheduler.
func test_switching_to_runtime_mode_after_ready_starts_the_scheduler() -> void:
	var world := FlowWorld3D.new()
	world.graph = _graph()
	world.world_bounds = WB
	world.generation_radius = {0: 1000.0, 64: 40.0, 16: 12.0}
	world.source_provider = func(): return _sources
	add_child(world)
	auto_free(world)
	await get_tree().process_frame
	assert_array(world.get_cells()).is_empty()
	world.generation_mode = FlowWorld3D.GenerationMode.Runtime
	for i in range(300):
		await get_tree().process_frame
		if not world.is_busy() and not world.get_cells().is_empty():
			break
	assert_int(world.get_cells(FlowWorld3D.CellState.Generated).size()).is_equal(1 + 4 + 9)
