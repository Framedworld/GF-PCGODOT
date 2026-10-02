# world_manual_api_test.gd
# WP5: FlowWorld3D manual control (generate_all / generate_bounds /
# generate_cell / cleanup_cell / cleanup_all / is_busy and signals), cell
# components, spawned-content ownership and cleanup per cell, pooling,
# owner-less evaluation of the same graph.
class_name WorldManualApiTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const Util = preload("res://tests/world/support/world_test_util.gd")
const OWNER_ERROR := "needs an owner node"

const WB := AABB(Vector3(-16.0, -4.0, -16.0), Vector3(32.0, 8.0, 32.0))

# Unbounded grid of 8x8 points (step 4), culled per 16 cell, spawned as meshes.
func _spawn_graph() -> FlowGraphResource:
	var b = TestGraph.new()
	b.node("grid", "grid", {"x": 8, "y": 1, "z": 8, "step": Vector3(4, 1, 4), "origin": Vector3(-14, 0, -14)})
	b.node("marker", "grid_size", {"cell_size": 16.0}).node("cull", "cull_points_outside_bounds")
	b.node("spawn", "spawn_meshes", {"use_vertex_colors": false}).node("out", "output", {"name": "result"})
	b.link("grid", 0, "marker", 0).link("marker", 0, "cull", 0).link("cull", 0, "spawn", 0).link("spawn", 0, "out", 0)
	return b.build()

func _world() -> FlowWorld3D:
	return auto_free(Util.make_world(self, _spawn_graph(), WB))

func _spawned(comp : Node) -> Array:
	return comp.get_children().filter(func(c): return c.has_meta("flow_owner"))

func test_generate_all_creates_one_component_per_cell() -> void:
	var world := _world()
	var generated := []
	var done := [0]
	world.cell_generated.connect(func(level, coord): generated.append(FlowWorldCell.key_of(level, coord)))
	world.all_generated.connect(func(): done[0] += 1)
	world.generate_all()
	assert_int(done[0]).is_equal(1)
	assert_array(generated).contains_exactly_in_any_order([Vector3i(0, 0, 0), Vector3i(16, -1, -1), Vector3i(16, 0, -1), Vector3i(16, -1, 0), Vector3i(16, 0, 0)])
	# Unbounded first.
	assert_that(generated[0]).is_equal(Vector3i(0, 0, 0))
	var names := []
	for child in world.get_children():
		names.append(child.name)
	assert_array(names).contains_exactly_in_any_order(["FlowCell_L0_0_0", "FlowCell_L16_-1_-1", "FlowCell_L16_0_-1", "FlowCell_L16_-1_0", "FlowCell_L16_0_0"])
	assert_bool(world.is_busy()).is_false()
	# 16 points per cell, each spawned under its own component.
	for key in generated:
		if key.x == 0:
			continue
		var coord := Vector2i(key.y, key.z)
		var comp := world.get_cell_component(16, coord)
		assert_object(comp).is_not_null()
		assert_int(world.get_cell_outputs(16, coord)["result"].size()).is_equal(16)
		var spawned := _spawned(comp)
		assert_int(spawned.size()).is_greater(0)
		for node in spawned:
			assert_int(int(node.get_meta("flow_owner")["component"])).is_equal(comp.get_instance_id())
			# Cell components are transient: spawned content is never saved.
			assert_object(node.owner).is_null()
		assert_bool(comp.transient_output).is_true()
		assert_that(comp.last_cell.bounds).is_equal(world.get_cell_bounds(16, coord))
		assert_array(comp.last_errors).is_empty()

func test_generate_cell_generates_its_parents_and_reports_outputs() -> void:
	var world := _world()
	var outputs := world.generate_cell(16, Vector2i(0, -1))
	assert_int(outputs["result"].size()).is_equal(16)
	assert_int(world.get_cell_state(0, Vector2i.ZERO)).is_equal(FlowWorld3D.CellState.Generated)
	assert_int(world.get_cell_state(16, Vector2i(0, -1))).is_equal(FlowWorld3D.CellState.Generated)
	assert_int(world.get_cell_state(16, Vector2i(0, 0))).is_equal(FlowWorld3D.CellState.NONE)
	# A generated cell is returned as is unless forced.
	var comp := world.get_cell_component(16, Vector2i(0, -1))
	var count := [0]
	comp.generated.connect(func(_o): count[0] += 1)
	world.generate_cell(16, Vector2i(0, -1))
	assert_int(count[0]).is_equal(0)
	world.generate_cell(16, Vector2i(0, -1), true)
	assert_int(count[0]).is_equal(1)
	# Regeneration replaces the cell's content instead of adding to it.
	assert_int(_spawned(comp).size()).is_equal(1)

func test_generate_bounds_only_touches_overlapping_cells() -> void:
	var world := _world()
	var done := [0]
	world.all_generated.connect(func(): done[0] += 1)
	world.generate_bounds(AABB(Vector3(1, 0, 1), Vector3(3, 1, 3)))
	assert_array(world.get_cells()).contains_exactly_in_any_order([Vector3i(0, 0, 0), Vector3i(16, 0, 0)])
	assert_int(done[0]).is_equal(1)

func test_invalid_requests_are_reported() -> void:
	var world := _world()
	assert_dict(world.generate_cell(32, Vector2i.ZERO)).is_empty()
	assert_dict(world.generate_cell(16, Vector2i(5, 5))).is_empty()
	assert_array(world.get_cells()).is_empty()
	var empty := FlowWorld3D.new()
	add_child(empty)
	empty.generate_all()
	assert_array(empty.get_cells()).is_empty()
	empty.free()

func test_cleanup_cell_frees_only_its_content_and_pools_the_component() -> void:
	var world := _world()
	world.generate_all()
	var cleaned := []
	world.cell_cleaned_up.connect(func(level, coord): cleaned.append(FlowWorldCell.key_of(level, coord)))
	var doomed := world.get_cell_component(16, Vector2i(0, 0))
	var doomed_content := _spawned(doomed)
	var survivor := world.get_cell_component(16, Vector2i(-1, 0))
	var survivor_content := _spawned(survivor)
	world.cleanup_cell(16, Vector2i(0, 0))
	assert_array(cleaned).is_equal([Vector3i(16, 0, 0)])
	assert_int(world.get_cell_state(16, Vector2i(0, 0))).is_equal(FlowWorld3D.CellState.NONE)
	assert_object(doomed.get_parent()).is_null()
	assert_int(world.get_pool_size()).is_equal(1)
	assert_int(_spawned(doomed).size()).is_equal(0)
	for node in doomed_content:
		assert_bool(node.is_queued_for_deletion()).is_true()
	for node in survivor_content:
		assert_bool(is_instance_valid(node) and not node.is_queued_for_deletion()).is_true()
	assert_int(_spawned(survivor).size()).is_equal(survivor_content.size())
	# Regenerating the cell reuses the pooled component.
	var created := world.components_created
	world.generate_cell(16, Vector2i(0, 0))
	assert_int(world.components_created).is_equal(created)
	assert_int(world.components_reused).is_equal(1)
	assert_object(world.get_cell_component(16, Vector2i(0, 0))).is_same(doomed)
	assert_str(String(doomed.name)).is_equal("FlowCell_L16_0_0")
	assert_int(_spawned(doomed).size()).is_greater(0)

func test_cleanup_all_and_pool_bound() -> void:
	var world := _world()
	world.cell_pool_size = 2
	world.generate_all()
	var cleaned := [0]
	world.cell_cleaned_up.connect(func(_l, _c): cleaned[0] += 1)
	world.cleanup_all()
	assert_int(cleaned[0]).is_equal(5)
	assert_array(world.get_cells()).is_empty()
	assert_int(world.get_pool_size()).is_equal(2)
	assert_int(world.get_child_count()).is_equal(0)
	assert_bool(world.is_busy()).is_false()

func test_owner_less_evaluation_of_the_same_graph() -> void:
	# Outside world generation the cull is a pass-through and the spawner
	# reports the documented owner error and forwards its input.
	var outputs := FlowNodeIO.evaluate(_spawn_graph())
	assert_int(outputs["result"].size()).is_equal(64)
	var messages := FlowNodeIO.last_errors.map(func(e): return e.message)
	assert_int(messages.size()).is_equal(1)
	assert_str(messages[0]).contains(OWNER_ERROR)

func test_world_settings_reach_cell_components() -> void:
	var world := _world()
	world.seed = 77
	world.params = {"k": 1}
	world.overrides = {"grid/x": 2}
	world.generate_cell(16, Vector2i(-1, -1))
	var comp := world.get_cell_component(16, Vector2i(-1, -1))
	assert_int(comp.seed).is_equal(77)
	assert_dict(comp.params).is_equal({"k": 1})
	assert_dict(comp.overrides).is_equal({"grid/x": 2})
	assert_bool(comp.generate_on_ready).is_false()
	# The override shrank the Unbounded grid to 2 columns (x = -14 and -10,
	# both in cell x = -1) of 8 rows, 4 of them in cell z = -1.
	assert_int(world.get_cell_outputs(16, Vector2i(-1, -1))["result"].size()).is_equal(8)
