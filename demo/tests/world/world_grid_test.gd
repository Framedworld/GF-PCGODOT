# world_grid_test.gd
# WP5: cell math (FlowWorldGrid) and the FlowWorldCell descriptor.
class_name WorldGridTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

const WB := AABB(Vector3(-100.0, -10.0, -70.0), Vector3(200.0, 30.0, 150.0))

func test_snap_matches_grid_size_settings() -> void:
	for v in [0.25, 1.0, 1.4, 1.5, 3.0, 33.0, 48.0, 50.0, 64.0, 100.0, 200.0, 1000.0]:
		var s := GridSizeNodeSettings.new()
		s.cell_size = v
		assert_int(FlowWorldGrid.snap_grid_size(v)).is_equal(int(s.cell_size))

func test_floor_div() -> void:
	assert_int(FlowWorldGrid.floor_div(7, 2)).is_equal(3)
	assert_int(FlowWorldGrid.floor_div(-7, 2)).is_equal(-4)
	assert_int(FlowWorldGrid.floor_div(-8, 2)).is_equal(-4)
	assert_int(FlowWorldGrid.floor_div(0, 4)).is_equal(0)
	assert_int(FlowWorldGrid.floor_div(-1, 4)).is_equal(-1)

func test_coord_of_world_positions() -> void:
	assert_that(FlowWorldGrid.coord_of(Vector3(0, 5, 0), 32)).is_equal(Vector2i(0, 0))
	assert_that(FlowWorldGrid.coord_of(Vector3(31.999, 0, 63.0), 32)).is_equal(Vector2i(0, 1))
	assert_that(FlowWorldGrid.coord_of(Vector3(32.0, 0, 64.0), 32)).is_equal(Vector2i(1, 2))
	assert_that(FlowWorldGrid.coord_of(Vector3(-0.001, 0, -32.0), 32)).is_equal(Vector2i(-1, -1))
	assert_that(FlowWorldGrid.coord_of(Vector3(-32.001, 0, 0), 32)).is_equal(Vector2i(-2, 0))
	assert_that(FlowWorldGrid.coord_of(Vector3(123, 0, 456), 0)).is_equal(Vector2i.ZERO)

func test_cell_bounds_follow_the_contract_formula() -> void:
	var box := FlowWorldGrid.cell_aabb(Vector2i(-2, 3), 16, WB)
	assert_that(box).is_equal(AABB(Vector3(-32.0, -10.0, 48.0), Vector3(16.0, 30.0, 16.0)))
	# Execution bounds are clipped to the world on XZ.
	var edge := FlowWorldGrid.execution_bounds(Vector2i(-4, 0), 32, WB)
	assert_that(edge).is_equal(AABB(Vector3(-100.0, -10.0, 0.0), Vector3(4.0, 30.0, 32.0)))
	assert_that(FlowWorldGrid.execution_bounds(Vector2i(1, 1), 0, WB)).is_equal(WB)
	var outside := FlowWorldGrid.execution_bounds(Vector2i(50, 0), 32, WB)
	assert_float(outside.size.x).is_equal(0.0)

func test_parent_coord() -> void:
	assert_that(FlowWorldGrid.parent_coord(Vector2i(3, -1), 32, 128)).is_equal(Vector2i(0, -1))
	assert_that(FlowWorldGrid.parent_coord(Vector2i(4, -4), 32, 128)).is_equal(Vector2i(1, -1))
	assert_that(FlowWorldGrid.parent_coord(Vector2i(-5, -4), 32, 128)).is_equal(Vector2i(-2, -1))
	assert_that(FlowWorldGrid.parent_coord(Vector2i(7, 9), 32, 0)).is_equal(Vector2i.ZERO)
	# The parent box contains the child box.
	for coord in [Vector2i(-5, 7), Vector2i(0, 0), Vector2i(3, -9)]:
		var parent := FlowWorldGrid.parent_coord(coord, 16, 64)
		var child_box := FlowWorldGrid.cell_aabb(coord, 16, WB)
		var parent_box := FlowWorldGrid.cell_aabb(parent, 64, WB)
		assert_bool(parent_box.encloses(child_box)).is_true()

# Every point is owned by exactly one cell, including points on shared edges
# and corners, and the owner is coord_of(point).
func test_half_open_ownership_is_a_partition() -> void:
	var size := 8
	var points : Array[Vector3] = [
		Vector3(0, 0, 0), Vector3(8, 0, 0), Vector3(0, 0, 8), Vector3(8, 0, 8), Vector3(-8, 0, -8),
		Vector3(7.9999, 0, 4), Vector3(8.0001, 0, 4), Vector3(-0.0001, 0, -0.0001), Vector3(16, 0, -16),
		Vector3(3.5, 0, -12.25),
	]
	var big := AABB(Vector3(-1000, -10, -1000), Vector3(2000, 30, 2000))
	for p in points:
		var owners := 0
		for cz in range(-4, 4):
			for cx in range(-4, 4):
				if FlowWorldGrid.owns(FlowWorldGrid.execution_bounds(Vector2i(cx, cz), size, big), p):
					owners += 1
					assert_that(Vector2i(cx, cz)).is_equal(FlowWorldGrid.coord_of(p, size))
		assert_int(owners).override_failure_message("point %s owned by %d cells" % [p, owners]).is_equal(1)

func test_owns_and_overlaps_conventions() -> void:
	var b := AABB(Vector3(0, 0, 0), Vector3(10, 5, 10))
	assert_bool(FlowWorldGrid.owns(b, Vector3(0, 0, 0))).is_true()
	assert_bool(FlowWorldGrid.owns(b, Vector3(10, 0, 5))).is_false()
	assert_bool(FlowWorldGrid.owns(b, Vector3(5, 0, 10))).is_false()
	assert_bool(FlowWorldGrid.owns(b, Vector3(5, 5, 5))).is_true()	# Y closed
	assert_bool(FlowWorldGrid.owns(b, Vector3(5, 5.01, 5))).is_false()
	# A box touching only the max side does not overlap; touching the min side does.
	assert_bool(FlowWorldGrid.overlaps(b, Vector3(10, 0, 0), Vector3(12, 1, 1))).is_false()
	assert_bool(FlowWorldGrid.overlaps(b, Vector3(-2, 0, 0), Vector3(0, 1, 1))).is_true()
	assert_bool(FlowWorldGrid.overlaps(b, Vector3(9, 0, 9), Vector3(12, 1, 12))).is_true()
	var grown := FlowWorldGrid.grow(b, 1.0)
	assert_that(grown).is_equal(AABB(Vector3(-1, -1, -1), Vector3(12, 7, 12)))
	assert_that(FlowWorldGrid.grow(b, -20.0).size).is_equal(Vector3.ZERO)

func test_cells_in_area() -> void:
	var cells := FlowWorldGrid.cells_in(WB, 64, WB)
	# x: -100..100 -> -2..1, z: -70..80 -> -2..1
	assert_int(cells.size()).is_equal(16)
	assert_that(cells[0]).is_equal(Vector2i(-2, -2))
	assert_that(cells[cells.size() - 1]).is_equal(Vector2i(1, 1))
	# An area ending exactly on a boundary does not reach the next cell.
	var exact := FlowWorldGrid.cells_in(AABB(Vector3(0, 0, 0), Vector3(64, 1, 64)), 64, WB)
	assert_array(exact).is_equal([Vector2i(0, 0)])
	assert_array(FlowWorldGrid.cells_in(AABB(Vector3(500, 0, 500), Vector3(1, 1, 1)), 64, WB)).is_empty()
	assert_array(FlowWorldGrid.cells_in(WB, 0, WB)).is_equal([Vector2i.ZERO])

func test_distances_and_names() -> void:
	var box := AABB(Vector3(0, 0, 0), Vector3(10, 10, 10))
	assert_float(FlowWorldGrid.distance_to_footprint(Vector3(5, 100, 5), box)).is_equal(0.0)
	assert_float(FlowWorldGrid.distance_to_footprint(Vector3(13, 0, 14), box)).is_equal(5.0)
	assert_float(FlowWorldGrid.distance_to_aabb(Vector3(5, 13, 5), box)).is_equal(3.0)
	assert_str(FlowWorldGrid.cell_name(32, Vector2i(-1, 4))).is_equal("FlowCell_L32_-1_4")
	assert_str(FlowWorldGrid.cell_name(0, Vector2i.ZERO)).is_equal("FlowCell_L0_0_0")

func test_world_cell_descriptor() -> void:
	var b = TestGraph.new()
	b.node("grid", "grid").node("m64", "grid_size", {"cell_size": 64.0}).node("a", "add_tags")
	b.node("m16", "grid_size", {"cell_size": 16.0}).node("c", "add_tags")
	b.link("grid", 0, "m64", 0).link("m64", 0, "a", 0).link("a", 0, "m16", 0).link("m16", 0, "c", 0)
	var graph : FlowGraphResource = b.build()
	var cell := FlowWorldCell.for_graph(graph, 16, Vector2i(-7, 2), WB)
	assert_that(cell.bounds).is_equal(AABB(Vector3(-100, -10, 32), Vector3(4, 30, 16)))
	assert_int(cell.hierarchy_level).is_equal(2)
	assert_array(cell.run_nodes.keys()).contains_exactly_in_any_order([&"m16", &"c"])
	assert_float(cell.grid_size()).is_equal(16.0)
	assert_that(cell.key()).is_equal(Vector3i(16, -7, 2))
	var coarse := FlowWorldCell.for_graph(graph, 64, Vector2i(0, 0), WB)
	assert_array(coarse.capture_nodes).is_equal([&"a"])
	var unbounded := FlowWorldCell.for_graph(graph, 0, Vector2i(3, 3), WB)
	assert_that(unbounded.coord).is_equal(Vector2i.ZERO)
	assert_that(unbounded.bounds).is_equal(WB)
	var ctx := FlowData.EvaluationContext.new()
	cell.variables = {"v": 1}
	cell.apply_to_context(ctx)
	assert_bool(ctx.has_bounds).is_true()
	assert_float(ctx.grid_size).is_equal(16.0)
	assert_that(ctx.cell_coord).is_equal(Vector2i(-7, 2))
	assert_int(ctx.hierarchy_level).is_equal(2)
	assert_int(ctx.variables["v"]).is_equal(1)

func test_context_defaults_outside_world_generation() -> void:
	var ctx := FlowNodeIO.make_context()
	assert_bool(ctx.has_bounds).is_false()
	assert_that(ctx.bounds).is_equal(AABB())
	assert_float(ctx.grid_size).is_equal(0.0)
	assert_that(ctx.cell_coord).is_equal(Vector2i.ZERO)
	assert_int(ctx.hierarchy_level).is_equal(0)
