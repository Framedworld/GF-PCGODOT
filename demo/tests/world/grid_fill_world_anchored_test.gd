# WP11 item 9: grid_fill_bounds' opt-in world_anchored setting places cells on
# world multiples of cell_size, so the sampler is partition-invariant under
# FlowWorld3D (same harness as world_generation_test's invariance test).
class_name GridFillWorldAnchoredTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const Util = preload("res://tests/world/support/world_test_util.gd")
const GridFill = preload("res://addons/flow_nodes_editor/nodes/grid_fill_bounds.gd")
const GridFillSettings = preload("res://addons/flow_nodes_editor/nodes/grid_fill_bounds_settings.gd")

const WB := AABB(Vector3(-40.0, -10.0, -40.0), Vector3(80.0, 30.0, 80.0))

func test_world_anchored_grid_fill_is_partition_invariant() -> void:
	for seed in [0, 4711]:
		var graph := Util.scatter_graph("grid_fill_anchored", 32)
		var mono := Util.monolithic(graph, WB, ["bounds"], "result", seed)
		var world : FlowWorld3D = auto_free(Util.make_world(self, graph, WB, seed))
		world.generate_all()
		var parts := Util.cell_outputs(world, 32)
		assert_int(parts.size()).is_equal(16)
		var expected := Util.rows([mono])
		assert_int(expected.size()).is_greater(50)
		assert_bool(Util.rows(parts) == expected).override_failure_message("grid_fill_anchored (seed %d): cells differ from the monolithic result" % seed).is_true()
		world.cleanup_all()

func test_default_stays_centred_on_the_input_box() -> void:
	# The default (world_anchored off) keeps today's centred placement.
	assert_bool(GridFillSettings.new().world_anchored).is_false()
	var s = GridFillSettings.new()
	s.cell_size = Vector3(2, 1, 2)
	s.copy_input_attributes = false
	var box = H.points([Vector3(0.5, 0, 0.5)])
	box.getVector3Container("size")[0] = Vector3(4, 1, 4)
	var out = H.port(H.exec(GridFill, s, [box]), 0)
	var xs := []
	for i in range(out.size()):
		xs.append(out.value_at("position", i).x)
	xs.sort()
	assert_array(xs).is_equal([-0.5, -0.5, 1.5, 1.5])

func test_world_anchored_cells_sit_on_multiples_of_the_cell_size() -> void:
	var s = GridFillSettings.new()
	s.cell_size = Vector3(2, 1, 2)
	s.copy_input_attributes = false
	s.world_anchored = true
	var box = H.points([Vector3(0.5, 0, 0.5)])
	box.getVector3Container("size")[0] = Vector3(4, 1, 4)    # x and z in [-1.5, 2.5]
	var out = H.port(H.exec(GridFill, s, [box]), 0)
	var positions := []
	for i in range(out.size()):
		var p : Vector3 = out.value_at("position", i)
		positions.append(Vector2(p.x, p.z))
		assert_float(p.y).is_equal(0.0)
		assert_vector(out.value_at("size", i)).is_equal(Vector3(2, 1, 2))
	positions.sort()
	# Multiples of 2 inside [-1.5, 2.5]: 0 and 2 on each axis.
	assert_array(positions).is_equal([Vector2(0, 0), Vector2(0, 2), Vector2(2, 0), Vector2(2, 2)])
	# A box that straddles no multiple of the cell size gets no cell.
	var thin = H.points([Vector3(0.9, 0, 0.9)])
	thin.getVector3Container("size")[0] = Vector3(0.5, 1, 0.5)
	assert_int(H.port(H.exec(GridFill, s, [thin]), 0).size()).is_equal(0)

func test_world_anchored_fills_y_on_multiples_too() -> void:
	var s = GridFillSettings.new()
	s.cell_size = Vector3(2, 2, 2)
	s.copy_input_attributes = false
	s.world_anchored = true
	s.fill_y_axis = true
	s.use_input_bounds = false
	s.bounds_center = Vector3(0, 1, 0)
	s.bounds_size = Vector3(2, 2, 2)     # [-1, 1] x [0, 2] x [-1, 1]
	var out = H.port(H.exec(GridFill, s, []), 0)
	var ys := {}
	for i in range(out.size()):
		ys[out.value_at("position", i).y] = true
	assert_array(ys.keys()).contains_exactly_in_any_order([0.0, 2.0])
	assert_int(out.size()).is_equal(2)
