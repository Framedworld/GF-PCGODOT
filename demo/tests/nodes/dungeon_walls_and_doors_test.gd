# dungeon_walls_and_doors_test.gd
class_name DungeonWallsAndDoorsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DungeonWallsAndDoorsNode = preload("res://addons/flow_nodes_editor/nodes/dungeon_walls_and_doors.gd")
const DungeonWallsAndDoorsSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_walls_and_doors_settings.gd")

func _make_floor_data(positions: PackedVector3Array, cell_types: PackedStringArray) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(positions.size())
	var spos = d.getVector3Container(FlowData.AttrPosition)
	for i in range(positions.size()):
		spos[i] = positions[i]
	d.registerStream("CellType", cell_types, FlowDataScript.DataType.String)
	return d

func _run(input: FlowData.Data, settings: DungeonWallsAndDoorsSettings) -> DungeonWallsAndDoorsNode:
	var node = DungeonWallsAndDoorsNode.new()
	node.name = "test_dungeon_node"
	node.settings = settings
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _get_output(node: DungeonWallsAndDoorsNode, port: int) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty() or port >= bulk.size():
		return null
	return bulk[port]

func test_missing_input_sets_error() -> void:
	var s = DungeonWallsAndDoorsSettings.new()
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_cell_type_stream_sets_error() -> void:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(1)
	var spos = d.getVector3Container(FlowData.AttrPosition)
	spos[0] = Vector3(0, 0, 0)
	var s = DungeonWallsAndDoorsSettings.new()
	var node = _run(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_input_produces_empty_outputs() -> void:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(0)
	d.registerStream("CellType", PackedStringArray(), FlowDataScript.DataType.String)
	var s = DungeonWallsAndDoorsSettings.new()
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var walls = _get_output(node, 0)
	var doors = _get_output(node, 1)
	var torches = _get_output(node, 2)
	var pillars = _get_output(node, 3)
	assert_int(walls.size() if walls != null else 0).is_equal(0)
	assert_int(doors.size() if doors != null else 0).is_equal(0)
	assert_int(torches.size() if torches != null else 0).is_equal(0)
	assert_int(pillars.size() if pillars != null else 0).is_equal(0)
	node.free()

func test_single_room_cell_generates_walls_and_pillars() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var cell_types = PackedStringArray(["Room"])
	var d = _make_floor_data(positions, cell_types)
	var s = DungeonWallsAndDoorsSettings.new()
	s.cell_size = 2.0
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var walls = _get_output(node, 0)
	assert_object(walls).is_not_null()
	assert_int(walls.size()).is_equal(4)
	var pillars = _get_output(node, 3)
	assert_object(pillars).is_not_null()
	assert_int(pillars.size()).is_greater(0)
	node.free()

func test_room_adjacent_to_corridor_generates_door() -> void:
	# Room at (0,0,0) and Corridor at (2,0,0) with cell_size=2 — East neighbor is Corridor
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var cell_types = PackedStringArray(["Room", "Corridor"])
	var d = _make_floor_data(positions, cell_types)
	var s = DungeonWallsAndDoorsSettings.new()
	s.cell_size = 2.0
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var doors = _get_output(node, 1)
	assert_object(doors).is_not_null()
	assert_int(doors.size()).is_greater(0)
	node.free()

func test_corridor_to_corridor_no_doors() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0)])
	var cell_types = PackedStringArray(["Corridor", "Corridor"])
	var d = _make_floor_data(positions, cell_types)
	var s = DungeonWallsAndDoorsSettings.new()
	s.cell_size = 2.0
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var doors = _get_output(node, 1)
	assert_object(doors).is_not_null()
	assert_int(doors.size()).is_equal(0)
	node.free()

func test_output_scale_is_applied() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var cell_types = PackedStringArray(["Room"])
	var d = _make_floor_data(positions, cell_types)
	var s = DungeonWallsAndDoorsSettings.new()
	s.cell_size = 2.0
	s.output_scale = Vector3(2.0, 3.0, 4.0)
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var walls = _get_output(node, 0)
	assert_object(walls).is_not_null()
	assert_int(walls.size()).is_greater(0)
	var ssize = walls.getVector3Container(FlowData.AttrSize)
	assert_object(ssize).is_not_null()
	assert_bool(ssize[0].is_equal_approx(Vector3(2.0, 3.0, 4.0))).is_true()
	node.free()

func test_include_concave_pillars_toggle() -> void:
	# L-shaped layout creates a concave corner
	var positions = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(2, 0, 0),
		Vector3(0, 0, 2)
	])
	var cell_types = PackedStringArray(["Room", "Room", "Room"])
	var d = _make_floor_data(positions, cell_types)

	var s_with = DungeonWallsAndDoorsSettings.new()
	s_with.cell_size = 2.0
	s_with.include_concave_pillars = true
	var node_with = _run(d, s_with)
	assert_str(node_with.err).is_empty()
	var pillars_with = _get_output(node_with, 3)
	var count_with = pillars_with.size() if pillars_with != null else 0

	var s_without = DungeonWallsAndDoorsSettings.new()
	s_without.cell_size = 2.0
	s_without.include_concave_pillars = false
	var node_without = _run(d, s_without)
	assert_str(node_without.err).is_empty()
	var pillars_without = _get_output(node_without, 3)
	var count_without = pillars_without.size() if pillars_without != null else 0

	assert_int(count_with).is_greater_equal(count_without)
	node_with.free()
	node_without.free()

func test_wall_output_has_type_stream() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var cell_types = PackedStringArray(["Room"])
	var d = _make_floor_data(positions, cell_types)
	var s = DungeonWallsAndDoorsSettings.new()
	s.cell_size = 2.0
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var walls = _get_output(node, 0)
	assert_object(walls).is_not_null()
	var type_stream = walls.findStream("type")
	assert_object(type_stream).is_not_null()
	assert_int(type_stream.container.size()).is_equal(walls.size())
	node.free()

func test_torch_probability_zero_no_torches() -> void:
	var positions = PackedVector3Array([Vector3(0, 0, 0)])
	var cell_types = PackedStringArray(["Room"])
	var d = _make_floor_data(positions, cell_types)
	var s = DungeonWallsAndDoorsSettings.new()
	s.cell_size = 2.0
	s.torch_probability = 0.0
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var torches = _get_output(node, 2)
	assert_object(torches).is_not_null()
	assert_int(torches.size()).is_equal(0)
	node.free()

func test_large_room_layout_no_errors() -> void:
	var positions = PackedVector3Array()
	var cell_types = PackedStringArray()
	for y in range(5):
		for x in range(5):
			positions.append(Vector3(x * 2.0, 0, y * 2.0))
			cell_types.append("Room")
	var d = _make_floor_data(positions, cell_types)
	var s = DungeonWallsAndDoorsSettings.new()
	s.cell_size = 2.0
	s.torch_probability = 0.5
	s.include_concave_pillars = true
	var node = _run(d, s)
	assert_str(node.err).is_empty()
	var walls = _get_output(node, 0)
	assert_object(walls).is_not_null()
	assert_int(walls.size()).is_greater(0)
	var pillars = _get_output(node, 3)
	assert_object(pillars).is_not_null()
	assert_int(pillars.size()).is_greater(0)
	node.free()
