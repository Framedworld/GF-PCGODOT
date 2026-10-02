# dungeon_generator_test.gd
class_name DungeonGeneratorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DungeonGeneratorNode = preload("res://addons/flow_nodes_editor/nodes/dungeon_generator.gd")
const DungeonGeneratorSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_generator_settings.gd")

func _make_settings(width: int = 20, height: int = 20, cell_size: float = 2.0,
		max_rooms: int = 8, room_min: int = 4, room_max: int = 8,
		torch_prob: float = 0.0, seed_val: int = 12345) -> DungeonGeneratorNodeSettings:
	var s = DungeonGeneratorSettings.new()
	s.width = width
	s.height = height
	s.cell_size = cell_size
	s.max_rooms = max_rooms
	s.room_min_size = room_min
	s.room_max_size = room_max
	s.torch_probability = torch_prob
	s.random_seed = seed_val
	return s

func _run(settings) -> DungeonGeneratorNode:
	var node = DungeonGeneratorNode.new()
	node.name = "test_dungeon_generator"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_default_settings_produces_output() -> void:
	var s = _make_settings()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_bool(positions.size() > 0).is_true()

func test_output_has_required_streams() -> void:
	var s = _make_settings()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.getVector3Container(FlowDataScript.AttrPosition)).is_not_null()
	assert_object(out.getVector3Container(FlowDataScript.AttrRotation)).is_not_null()
	assert_object(out.getVector3Container(FlowDataScript.AttrSize)).is_not_null()
	assert_object(out.findStream("type")).is_not_null()

func test_type_stream_contains_known_values_only() -> void:
	var s = _make_settings(20, 20, 2.0, 6, 4, 8, 0.0, 42)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	var types: PackedFloat32Array = type_stream.container
	for t in types:
		assert_bool(t == 0.0 or t == 1.0 or t == 2.0 or t == 3.0 or t == 4.0).is_true()

func test_output_contains_floor_and_wall_points() -> void:
	var s = _make_settings(20, 20, 2.0, 6, 4, 8, 0.0, 99)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	var types: PackedFloat32Array = type_stream.container
	var has_floor := false
	var has_wall := false
	for t in types:
		if t == 0.0:
			has_floor = true
		elif t == 1.0:
			has_wall = true
	assert_bool(has_floor).is_true()
	assert_bool(has_wall).is_true()

func test_chest_count_matches_room_count() -> void:
	var s = _make_settings(30, 30, 2.0, 5, 4, 6, 0.0, 7777)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	var types: PackedFloat32Array = type_stream.container
	var chest_count := 0
	for t in types:
		if t == 4.0:
			chest_count += 1
	assert_bool(chest_count > 0).is_true()
	assert_bool(chest_count <= 5).is_true()

func test_cell_size_affects_positions() -> void:
	var s1 = _make_settings(20, 20, 1.0, 4, 4, 6, 0.0, 5555)
	var node1 = _run(s1)
	assert_str(node1.err).is_empty()
	var out1 = _output(node1)

	var s2 = _make_settings(20, 20, 4.0, 4, 4, 6, 0.0, 5555)
	var node2 = _run(s2)
	assert_str(node2.err).is_empty()
	var out2 = _output(node2)

	assert_object(out1).is_not_null()
	assert_object(out2).is_not_null()
	var pos1 = out1.getVector3Container(FlowDataScript.AttrPosition)
	var pos2 = out2.getVector3Container(FlowDataScript.AttrPosition)
	assert_bool(pos1.size() == pos2.size()).is_true()
	if pos1.size() > 0 and pos2.size() > 0:
		assert_bool(pos1[0] != pos2[0]).is_true()


func test_deterministic_with_same_seed() -> void:
	var s1 = _make_settings(20, 20, 2.0, 6, 4, 8, 0.1, 12345)
	var node1 = _run(s1)
	assert_str(node1.err).is_empty()
	var out1 = _output(node1)

	var s2 = _make_settings(20, 20, 2.0, 6, 4, 8, 0.1, 12345)
	var node2 = _run(s2)
	assert_str(node2.err).is_empty()
	var out2 = _output(node2)

	assert_object(out1).is_not_null()
	assert_object(out2).is_not_null()
	var pos1 = out1.getVector3Container(FlowDataScript.AttrPosition)
	var pos2 = out2.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(pos1.size()).is_equal(pos2.size())


func test_invalid_room_min_greater_than_max_sets_error() -> void:
	var s = _make_settings(20, 20, 2.0, 6, 8, 4, 0.0, 12345)
	var node = _run(s)
	assert_str(node.err).is_not_empty()

func test_torch_probability_zero_produces_no_torches() -> void:
	var s = _make_settings(20, 20, 2.0, 6, 4, 8, 0.0, 12345)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	var types: PackedFloat32Array = type_stream.container
	var torch_count := 0
	for t in types:
		if t == 3.0:
			torch_count += 1
	assert_int(torch_count).is_equal(0)

func test_torch_probability_one_produces_torches_on_walls() -> void:
	var s = _make_settings(20, 20, 2.0, 6, 4, 8, 1.0, 12345)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	var types: PackedFloat32Array = type_stream.container
	var torch_count := 0
	var wall_count := 0
	for t in types:
		if t == 1.0:
			wall_count += 1
		elif t == 3.0:
			torch_count += 1
	assert_bool(torch_count > 0).is_true()
	assert_bool(torch_count == wall_count).is_true()

func test_all_sizes_are_unit_vectors() -> void:
	var s = _make_settings(20, 20, 2.0, 6, 4, 8, 0.0, 12345)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_bool(sizes.size() > 0).is_true()
	for sz in sizes:
		assert_bool(sz == Vector3.ONE).is_true()

func test_stream_lengths_are_consistent() -> void:
	var s = _make_settings(20, 20, 2.0, 6, 4, 8, 0.2, 12345)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	var rotations = out.getVector3Container(FlowDataScript.AttrRotation)
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	var type_stream = out.findStream("type")
	var types: PackedFloat32Array = type_stream.container
	var n := positions.size()
	assert_int(rotations.size()).is_equal(n)
	assert_int(sizes.size()).is_equal(n)
	assert_int(types.size()).is_equal(n)
