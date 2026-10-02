# world_scheduler_test.gd
# WP5: the FlowWorld3D runtime scheduler, driven by an injected clock and
# injected source positions (no real frames): generation radius per level,
# coarse-first and nearest-first ordering, frame budget, max concurrent cells,
# cleanup radius hysteresis, parents kept alive by their children, pooling,
# cancellation, OnLoad, and the real source collection and _process driver.
class_name WorldSchedulerTest extends GdUnitTestSuite

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

# Unbounded grid -> 64 level (add_tags) -> 16 level (add_tags); every level
# has an output, and the 16 level consumes the 64 level.
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

func _world(mode : int = FlowWorld3D.GenerationMode.Runtime) -> FlowWorld3D:
	var world := FlowWorld3D.new()
	world.graph = _graph()
	world.world_bounds = WB
	world.generation_mode = mode
	world.generation_radius = {0: 1000.0, 64: 40.0, 16: 12.0}
	world.clock = _clock
	world.source_provider = func(): return _sources
	world.frame_budget_ms = 4.0
	add_child(world)
	return auto_free(world)

func _run_until_idle(world : FlowWorld3D, max_ticks : int = 5000) -> int:
	var ticks := 0
	world.tick()
	ticks += 1
	while world.is_busy() and ticks < max_ticks:
		world.tick()
		ticks += 1
	assert_bool(world.is_busy()).override_failure_message("scheduler did not settle").is_false()
	return ticks

# Brute force over every cell of the world: the cells a source should pull in.
func _expected_cells(world : FlowWorld3D, sources : Array, scale : float = 1.0) -> Array:
	var result := []
	if sources.is_empty():
		return result
	result.append(Vector3i(0, 0, 0))
	for level in [64, 16]:
		var r : float = world.get_generation_radius(level) * scale
		for cz in range(-128 / level, 128 / level):
			for cx in range(-128 / level, 128 / level):
				for src in sources:
					if FlowWorldGrid.distance_to_footprint(src, world.get_cell_bounds(level, Vector2i(cx, cz))) <= r:
						result.append(Vector3i(level, cx, cz))
						break
	return result

func _generated(world : FlowWorld3D) -> Array:
	return Array(world.get_cells(FlowWorld3D.CellState.Generated))

func test_generates_cells_within_radius_coarse_first_then_nearest() -> void:
	var world := _world()
	world.max_concurrent_cells = 1
	var order := []
	var done := [0]
	world.cell_generated.connect(func(level, coord): order.append(FlowWorldCell.key_of(level, coord)))
	world.all_generated.connect(func(): done[0] += 1)
	# Frozen clock: the budget is never exhausted, one tick does everything.
	var ticks := _run_until_idle(world)
	assert_int(ticks).is_equal(1)
	var expected := _expected_cells(world, _sources)
	assert_int(expected.size()).is_equal(1 + 4 + 9)
	assert_array(_generated(world)).contains_exactly_in_any_order(expected)
	assert_array(order).contains_exactly_in_any_order(expected)
	assert_int(done[0]).is_equal(1)
	# Coarse levels first ...
	assert_that(order[0]).is_equal(Vector3i(0, 0, 0))
	for i in range(1, 5):
		assert_int(order[i].x).is_equal(64)
	for i in range(5, order.size()):
		assert_int(order[i].x).is_equal(16)
	# ... then nearest first within a level.
	var first_fine : Vector3i = order[5]
	assert_that(first_fine).is_equal(Vector3i(16, 0, 0))
	var last_dist := -1.0
	for i in range(5, order.size()):
		var c := world.get_cell_bounds(16, Vector2i(order[i].y, order[i].z)).get_center()
		var d := Vector2(c.x - 8.0, c.z - 8.0).length()
		assert_float(d).is_greater_equal(last_dist)
		last_dist = d
	# Each generated cell has its outputs and its component.
	assert_int(world.get_cell_outputs(16, Vector2i(1, 1))["fine"].size()).is_equal(1)
	assert_object(world.get_cell_component(64, Vector2i(-1, -1))).is_not_null()

func test_frame_budget_and_max_concurrent_cells_are_respected() -> void:
	var world := _world()
	world.max_concurrent_cells = 2
	world.frame_budget_ms = 3.0
	_tick_us = 1000	# every clock read advances 1 ms
	var ticks := 0
	var max_elements := 0
	var max_generating := 0
	world.tick()
	ticks += 1
	while world.is_busy() and ticks < 5000:
		max_elements = maxi(max_elements, world.last_tick_elements)
		max_generating = maxi(max_generating, world.get_cells(FlowWorld3D.CellState.Generating).size())
		assert_int(world.last_tick_elements).is_between(1, 3)
		world.tick()
		ticks += 1
	assert_bool(world.is_busy()).is_false()
	assert_int(max_elements).is_equal(3)
	assert_int(max_generating).is_equal(2)
	assert_array(_generated(world)).contains_exactly_in_any_order(_expected_cells(world, _sources))
	# Many frames were needed: the work was spread out.
	assert_int(ticks).is_greater(10)

func test_moving_source_cleans_up_far_cells_and_reuses_components() -> void:
	var world := _world()
	world.cell_pool_size = 3
	_run_until_idle(world)
	var first := _generated(world)
	var created := world.components_created
	var cleaned := []
	world.cell_cleaned_up.connect(func(level, coord): cleaned.append(FlowWorldCell.key_of(level, coord)))
	_sources = [Vector3(90, 0, 90)]
	_run_until_idle(world)
	var expected := _expected_cells(world, _sources)
	assert_array(_generated(world)).contains_exactly_in_any_order(expected)
	# Everything near the old position that the new one does not want is gone.
	for key in first:
		if not expected.has(key):
			assert_bool(cleaned.has(key)).override_failure_message("%s not cleaned" % key).is_true()
			assert_int(world.get_cell_state(key.x, Vector2i(key.y, key.z))).is_equal(FlowWorld3D.CellState.NONE)
	assert_bool(cleaned.has(Vector3i(0, 0, 0))).is_false()
	# Cleaned components were reused, the pool stays bounded, and only live
	# cells have components in the tree.
	assert_int(world.components_reused).is_greater(0)
	assert_int(world.get_pool_size()).is_less_equal(3)
	assert_int(world.get_child_count()).is_equal(expected.size())
	assert_int(world.components_created).is_less(created + expected.size())

func test_cleanup_radius_hysteresis() -> void:
	var world := _world()
	_run_until_idle(world)
	var edge := Vector3i(16, 1, 0)	# footprint [16, 32) x [0, 16)
	assert_int(world.get_cell_state(16, Vector2i(1, 0))).is_equal(FlowWorld3D.CellState.Generated)
	# 12.6 m away: outside the generation radius (12), inside cleanup (13.2).
	_sources = [Vector3(3.4, 0, 8)]
	_run_until_idle(world)
	assert_int(world.get_cell_state(edge.x, Vector2i(edge.y, edge.z))).is_equal(FlowWorld3D.CellState.Generated)
	# 14 m away: cleaned.
	_sources = [Vector3(2, 0, 8)]
	_run_until_idle(world)
	assert_int(world.get_cell_state(edge.x, Vector2i(edge.y, edge.z))).is_equal(FlowWorld3D.CellState.NONE)

func test_cleanup_goes_through_the_cleaning_up_state_within_the_budget() -> void:
	var world := _world()
	_run_until_idle(world)
	_sources = [Vector3(100, 0, -100)]
	_tick_us = 1000
	world.frame_budget_ms = 1.0
	world.max_concurrent_cells = 1
	world.tick()
	# One unit of work per tick with this budget: one cleanup, the rest wait.
	assert_int(world.last_tick_cleaned).is_equal(1)
	assert_int(world.get_cells(FlowWorld3D.CellState.CleaningUp).size()).is_greater(0)
	_run_until_idle(world)
	assert_array(_generated(world)).contains_exactly_in_any_order(_expected_cells(world, _sources))

func test_sources_gone_cleans_runtime_cells_but_not_manual_ones() -> void:
	var world := _world()
	world.generate_cell(16, Vector2i(-6, -6))
	_run_until_idle(world)
	_sources = []
	_run_until_idle(world)
	# The manual cell and the parents it needs stay.
	assert_array(_generated(world)).contains_exactly_in_any_order([Vector3i(0, 0, 0), Vector3i(64, -2, -2), Vector3i(16, -6, -6)])

func test_finer_cells_keep_their_parents_alive() -> void:
	var world := _world()
	world.generation_radius = {0: 1000.0, 64: 1.0, 16: 12.0}
	_run_until_idle(world)
	# The 64 cell (-1, -1) is 11.3 m away (beyond 1.1) but its child 16 cell
	# (-1, -1) is wanted, so it was generated and is kept.
	assert_int(world.get_cell_state(64, Vector2i(-1, -1))).is_equal(FlowWorld3D.CellState.Generated)
	assert_int(world.get_cell_state(16, Vector2i(-1, -1))).is_equal(FlowWorld3D.CellState.Generated)
	world.tick()
	assert_int(world.get_cell_state(64, Vector2i(-1, -1))).is_equal(FlowWorld3D.CellState.Generated)
	# Once the children go, so does the parent.
	_sources = [Vector3(100, 0, 100)]
	_run_until_idle(world)
	assert_int(world.get_cell_state(64, Vector2i(-1, -1))).is_equal(FlowWorld3D.CellState.NONE)
	assert_int(world.get_cell_state(16, Vector2i(-1, -1))).is_equal(FlowWorld3D.CellState.NONE)

func test_generating_cell_is_cancelled_when_its_source_leaves() -> void:
	var world := _world()
	world.max_concurrent_cells = 1
	world.frame_budget_ms = 0.0
	_tick_us = 1000
	var finished := []
	world.cell_generated.connect(func(level, coord): finished.append(FlowWorldCell.key_of(level, coord)))
	# Tick until a 16 cell is in flight.
	var in_flight : Array = []
	for i in range(200):
		world.tick()
		in_flight = Array(world.get_cells(FlowWorld3D.CellState.Generating)).filter(func(k): return k.x == 16)
		if not in_flight.is_empty():
			break
	assert_array(in_flight).is_not_empty()
	var key : Vector3i = in_flight[0]
	var comp := world.get_cell_component(16, Vector2i(key.y, key.z))
	_sources = [Vector3(-110, 0, 110)]
	world.tick()
	assert_bool(comp.is_generating()).is_false()
	_run_until_idle(world)
	assert_bool(finished.has(key)).is_false()
	assert_int(world.get_cell_state(16, Vector2i(key.y, key.z))).is_equal(FlowWorld3D.CellState.NONE)

func test_radius_scale_per_source() -> void:
	var world := _world()
	_sources = [{"position": Vector3(8, 0, 8), "radius_scale": 2.0}]
	_run_until_idle(world)
	assert_array(_generated(world)).contains_exactly_in_any_order(_expected_cells(world, [Vector3(8, 0, 8)], 2.0))
	assert_int(world.get_cells(FlowWorld3D.CellState.Generated).size()).is_greater(1 + 4 + 9)

func test_on_load_generates_everything_without_sources() -> void:
	var world := FlowWorld3D.new()
	world.graph = _graph()
	world.world_bounds = AABB(Vector3(-32, -8, -32), Vector3(64, 16, 64))
	world.generation_mode = FlowWorld3D.GenerationMode.OnLoad
	world.source_provider = func(): return []
	world.clock = _clock
	add_child(world)
	auto_free(world)
	assert_bool(world.is_busy()).is_true()
	var done := [0]
	world.all_generated.connect(func(): done[0] += 1)
	_run_until_idle(world)
	assert_int(world.get_cells(FlowWorld3D.CellState.Generated).size()).is_equal(1 + 4 + 16)
	assert_int(done[0]).is_equal(1)

func test_sources_are_collected_from_the_group_and_paths() -> void:
	var world := _world()
	world.source_provider = Callable()
	var src : FlowGenerationSource = auto_free(FlowGenerationSource.new())
	src.radius_scale = 1.5
	add_child(src)
	src.global_position = Vector3(3, 0, 4)
	var off : FlowGenerationSource = auto_free(FlowGenerationSource.new())
	off.enabled = false
	add_child(off)
	var plain : Node3D = auto_free(Node3D.new())
	add_child(plain)
	plain.global_position = Vector3(-50, 0, 20)
	var paths : Array[NodePath] = [world.get_path_to(plain)]
	world.sources = paths
	var sources := world.get_generation_sources()
	assert_int(sources.size()).is_equal(2)
	var by_pos := {}
	for s in sources:
		by_pos[s.position] = s.radius_scale
	assert_float(by_pos[Vector3(3, 0, 4)]).is_equal(1.5)
	assert_float(by_pos[Vector3(-50, 0, 20)]).is_equal(1.0)
	assert_bool(src.is_in_group(FlowWorld3D.SOURCE_GROUP)).is_true()

func test_runtime_mode_runs_from_process() -> void:
	var world := FlowWorld3D.new()
	world.graph = _graph()
	world.world_bounds = WB
	world.generation_mode = FlowWorld3D.GenerationMode.Runtime
	world.generation_radius = {0: 1000.0, 64: 10.0, 16: 6.0}
	var src : FlowGenerationSource = auto_free(FlowGenerationSource.new())
	add_child(src)
	src.global_position = Vector3(40, 0, 40)
	add_child(world)
	auto_free(world)
	assert_bool(world.is_processing()).is_true()
	for i in range(120):
		await get_tree().process_frame
		if not world.is_busy() and world.get_cells().size() > 0:
			break
	assert_array(_generated(world)).contains_exactly_in_any_order(_expected_cells(world, [Vector3(40, 0, 40)]))
