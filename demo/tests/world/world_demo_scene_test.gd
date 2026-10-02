# world_demo_scene_test.gd
# WP5: the hierarchical demo scene (demos/demo_hierarchical.tscn) loads,
# streams cells around its generation source, spawns trees on the 64 level and
# rocks on the 16 level, and the rocks avoid the trees handed down from the
# coarser level.
class_name WorldDemoSceneTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DEMO := "res://demos/demo_hierarchical.tscn"

func test_demo_scene_generates_two_levels_around_its_source() -> void:
	var scene : Node = auto_free(load(DEMO).instantiate())
	add_child(scene)
	var world : FlowWorld3D = scene.get_node("FlowWorld3D")
	assert_int(world.generation_mode).is_equal(FlowWorld3D.GenerationMode.Runtime)
	assert_array(Array(world.get_levels())).is_equal([0, 64, 16])
	# Drive the scheduler directly instead of waiting for frames.
	world.set_process(false)
	scene.get_node("Orbit").set_process(false)
	# The demo switches its source on after a few frames; do it now.
	var source : FlowGenerationSource = scene.get_node("Orbit/Source")
	assert_bool(source.enabled).is_false()
	source.enabled = true
	world.frame_budget_ms = 1000.0
	var ticks := 0
	world.tick()
	while world.is_busy() and ticks < 1000:
		world.tick()
		ticks += 1
	assert_bool(world.is_busy()).is_false()
	var trees := 0
	var rocks := 0
	var tree_positions : Array = []
	var rock_positions : Array = []
	for key in world.get_cells(FlowWorld3D.CellState.Generated):
		var coord := Vector2i(key.y, key.z)
		assert_array(world.get_cell_errors(key.x, coord)).is_empty()
		var outputs := world.get_cell_outputs(key.x, coord)
		if key.x == 64:
			trees += outputs["trees"].size()
			tree_positions.append_array(Array(outputs["trees"].getVector3Container(FlowData.AttrPosition)))
		elif key.x == 16:
			rocks += outputs["rocks"].size()
			rock_positions.append_array(Array(outputs["rocks"].getVector3Container(FlowData.AttrPosition)))
			assert_int(world.get_cell_component(16, coord).get_children().size()).is_greater(0)
	assert_int(trees).is_greater(10)
	assert_int(rocks).is_greater(50)
	# The 16 level removed the rocks that overlap a tree of the 64 cell around
	# them (Difference A - B on the coarse level's points): no rock center is
	# within 1 m of a tree center there. (Difference currently halves boxes
	# that come from bounds streams, so the cleared area is smaller than the
	# trees' +/-2 m point extents suggest; see docs/_round2/WP5.md.)
	for rock in rock_positions:
		for tree in tree_positions:
			if FlowWorldGrid.coord_of(rock, 64) != FlowWorldGrid.coord_of(tree, 64):
				continue
			var inside : bool = absf(rock.x - tree.x) < 1.0 and absf(rock.z - tree.z) < 1.0
			assert_bool(inside).override_failure_message("rock %s inside tree %s" % [rock, tree]).is_false()
