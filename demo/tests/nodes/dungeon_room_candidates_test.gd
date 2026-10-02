# dungeon_room_candidates_test.gd
class_name DungeonRoomCandidatesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DungeonRoomCandidatesNode = preload("res://addons/flow_nodes_editor/nodes/dungeon_room_candidates.gd")
const DungeonRoomCandidatesSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_room_candidates_settings.gd")

func _run(settings: DungeonRoomCandidatesSettings) -> DungeonRoomCandidatesNode:
	var node = DungeonRoomCandidatesNode.new()
	node.name = "dungeon_room_candidates_test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: DungeonRoomCandidatesNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func _default_settings() -> DungeonRoomCandidatesSettings:
	var s = DungeonRoomCandidatesSettings.new()
	s.grid_width = 24
	s.grid_height = 24
	s.cell_size = 2.0
	s.candidate_count = 40
	s.min_room_size = 3
	s.max_room_size = 6
	s.random_seed = 12345
	return s

func test_default_settings_produces_correct_count() -> void:
	var s = _default_settings()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(40)

func test_output_streams_exist() -> void:
	var s = _default_settings()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrPosition)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrRotation)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSize)).is_not_null()
	assert_object(out.findStream("RoomID")).is_not_null()
	assert_object(out.findStream("RoomWidth")).is_not_null()
	assert_object(out.findStream("RoomHeight")).is_not_null()
	assert_object(out.findStream("RoomPriority")).is_not_null()
	assert_object(out.findStream("type")).is_not_null()
	assert_object(out.findStream("bSelectedRoom")).is_not_null()

func test_room_ids_are_sequential() -> void:
	var s = _default_settings()
	s.candidate_count = 10
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var id_stream = out.findStream("RoomID")
	assert_object(id_stream).is_not_null()
	var ids: PackedInt32Array = id_stream.container
	assert_int(ids.size()).is_equal(10)
	for i in range(10):
		assert_int(ids[i]).is_equal(i)

func test_room_sizes_within_bounds() -> void:
	var s = _default_settings()
	s.min_room_size = 3
	s.max_room_size = 6
	s.candidate_count = 20
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var width_stream = out.findStream("RoomWidth")
	var height_stream = out.findStream("RoomHeight")
	assert_object(width_stream).is_not_null()
	assert_object(height_stream).is_not_null()
	var widths: PackedFloat32Array = width_stream.container
	var heights: PackedFloat32Array = height_stream.container
	for i in range(widths.size()):
		assert_bool(widths[i] >= 3.0).is_true()
		assert_bool(widths[i] <= 6.0).is_true()
		assert_bool(heights[i] >= 3.0).is_true()
		assert_bool(heights[i] <= 6.0).is_true()

func test_type_stream_filled_with_four() -> void:
	var s = _default_settings()
	s.candidate_count = 5
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	var types: PackedFloat32Array = type_stream.container
	assert_int(types.size()).is_equal(5)
	for i in range(5):
		assert_float(types[i]).is_equal(4.0)

func test_selected_room_stream_all_false() -> void:
	var s = _default_settings()
	s.candidate_count = 5
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var sel_stream = out.findStream("bSelectedRoom")
	assert_object(sel_stream).is_not_null()
	var selected: PackedByteArray = sel_stream.container
	assert_int(selected.size()).is_equal(5)
	for i in range(5):
		assert_int(selected[i]).is_equal(0)

func test_deterministic_with_same_seed() -> void:
	var s1 = _default_settings()
	s1.random_seed = 99999
	var node1 = _run(s1)
	var out1 = _output(node1)
	var pos1 = out1.getVector3Container(FlowDataScript.AttrPosition).duplicate()

	var s2 = _default_settings()
	s2.random_seed = 99999
	var node2 = _run(s2)
	var out2 = _output(node2)
	var pos2 = out2.getVector3Container(FlowDataScript.AttrPosition)

	assert_int(pos1.size()).is_equal(pos2.size())
	for i in range(pos1.size()):
		assert_bool(pos1[i] == pos2[i]).is_true()

func test_different_seeds_produce_different_output() -> void:
	var s1 = _default_settings()
	s1.random_seed = 1
	var node1 = _run(s1)
	var out1 = _output(node1)
	var pos1 = out1.getVector3Container(FlowDataScript.AttrPosition).duplicate()

	var s2 = _default_settings()
	s2.random_seed = 999999
	var node2 = _run(s2)
	var out2 = _output(node2)
	var pos2 = out2.getVector3Container(FlowDataScript.AttrPosition)

	var any_different := false
	for i in range(mini(pos1.size(), pos2.size())):
		if pos1[i] != pos2[i]:
			any_different = true
			break
	assert_bool(any_different).is_true()

func test_min_room_size_greater_than_max_produces_error() -> void:
	var s = _default_settings()
	s.min_room_size = 8
	s.max_room_size = 3
	var node = _run(s)
	assert_str(node.err).is_not_empty()

func test_single_candidate() -> void:
	var s = _default_settings()
	s.candidate_count = 1
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(1)
	var id_stream = out.findStream("RoomID")
	var ids: PackedInt32Array = id_stream.container
	assert_int(ids[0]).is_equal(0)

func test_cell_size_scales_positions() -> void:
	var s1 = _default_settings()
	s1.cell_size = 1.0
	s1.random_seed = 42
	s1.candidate_count = 5
	var node1 = _run(s1)
	var out1 = _output(node1)
	var pos1 = out1.getVector3Container(FlowDataScript.AttrPosition).duplicate()

	var s2 = _default_settings()
	s2.cell_size = 2.0
	s2.random_seed = 42
	s2.candidate_count = 5
	var node2 = _run(s2)
	var out2 = _output(node2)
	var pos2 = out2.getVector3Container(FlowDataScript.AttrPosition)

	for i in range(pos1.size()):
		assert_float(pos2[i].x).is_equal_approx(pos1[i].x * 2.0, 0.001)
		assert_float(pos2[i].z).is_equal_approx(pos1[i].z * 2.0, 0.001)

func test_large_candidate_count() -> void:
	var s = _default_settings()
	s.candidate_count = 200
	s.grid_width = 64
	s.grid_height = 64
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(200)
