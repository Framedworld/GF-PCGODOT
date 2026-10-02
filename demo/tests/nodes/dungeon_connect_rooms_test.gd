# dungeon_connect_rooms_test.gd
class_name DungeonConnectRoomsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DungeonConnectRoomsNode = preload("res://addons/flow_nodes_editor/nodes/dungeon_connect_rooms.gd")
const DungeonConnectRoomsSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_connect_rooms_settings.gd")

func _make_input(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var n := positions.size()
	d.addCommonStreams(n)
	var spos = d.getVector3Container(FlowData.AttrPosition)
	for i in range(n):
		spos[i] = positions[i]
	return d

func _run(input: FlowData.Data, cell_size: float = 2.0, seed_val: int = 12345) -> DungeonConnectRoomsNode:
	var node = DungeonConnectRoomsNode.new()
	node.name = "test_node"
	var s = DungeonConnectRoomsSettings.new()
	s.cell_size = cell_size
	node.settings = s
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: DungeonConnectRoomsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_missing_input_error() -> void:
	var node = DungeonConnectRoomsNode.new()
	node.name = "test_node"
	node.settings = DungeonConnectRoomsSettings.new()
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_not_empty()
	dummy.free()

func test_single_point_returns_empty_output() -> void:
	var input = _make_input(PackedVector3Array([Vector3(0, 0, 0)]))
	var node = _run(input)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_equal(0)

func test_two_rooms_generates_corridor() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(10, 0, 0)
	]))
	var node = _run(input, 2.0, 12345)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var spos = out.getVector3Container(FlowData.AttrPosition)
	assert_int(spos.size()).is_greater(0)
	var cell_type_stream = out.findStream("CellType")
	assert_object(cell_type_stream).is_not_null()
	var conn_id_stream = out.findStream("ConnectionID")
	assert_object(conn_id_stream).is_not_null()
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	assert_int(cell_type_stream.container.size()).is_equal(spos.size())
	assert_int(conn_id_stream.container.size()).is_equal(spos.size())

func test_corridor_cells_are_all_corridor_type() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(6, 0, 4)
	]))
	var node = _run(input, 2.0, 12345)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var cell_type_stream = out.findStream("CellType")
	assert_object(cell_type_stream).is_not_null()
	for ct in cell_type_stream.container:
		assert_str(ct).is_equal("Corridor")

func test_connection_ids_assigned_per_pair() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(10, 0, 0),
		Vector3(10, 0, 10)
	]))
	var node = _run(input, 2.0, 12345)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var conn_id_stream = out.findStream("ConnectionID")
	assert_object(conn_id_stream).is_not_null()
	var ids_seen := {}
	for id in conn_id_stream.container:
		ids_seen[id] = true
	assert_bool(ids_seen.has(0)).is_true()
	assert_bool(ids_seen.has(1)).is_true()

func test_no_duplicate_corridor_cells() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(8, 0, 8),
		Vector3(0, 0, 8)
	]))
	var node = _run(input, 2.0, 12345)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	var seen := {}
	for p in spos:
		var key := Vector3i(int(p.x), int(p.y), int(p.z))
		assert_bool(seen.has(key)).is_false()
		seen[key] = true

func test_cell_size_affects_output_positions() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(4, 0, 0)
	]))
	var node_small = _run(input, 1.0, 12345)
	var node_large = _run(input, 2.0, 12345)
	assert_str(node_small.err).is_empty()
	assert_str(node_large.err).is_empty()
	var out_small = _output(node_small)
	var out_large = _output(node_large)
	var spos_small = out_small.getVector3Container(FlowData.AttrPosition)
	var spos_large = out_large.getVector3Container(FlowData.AttrPosition)
	assert_bool(spos_small.size() != spos_large.size() or spos_small != spos_large).is_true()

func test_output_size_stream_matches_cell_size() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(6, 0, 0)
	]))
	var cell_size := 2.0
	var node = _run(input, cell_size, 12345)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var ssize = out.getVector3Container(FlowData.AttrSize)
	assert_int(ssize.size()).is_greater(0)
	for sz in ssize:
		assert_float(sz.x).is_equal_approx(cell_size, 0.001)
		assert_float(sz.z).is_equal_approx(cell_size, 0.001)
		assert_float(sz.y).is_equal_approx(1.0, 0.001)

func test_corridor_y_positions_are_zero() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(8, 0, 6)
	]))
	var node = _run(input, 2.0, 12345)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var spos = out.getVector3Container(FlowData.AttrPosition)
	for p in spos:
		assert_float(p.y).is_equal_approx(0.0, 0.001)

func test_type_stream_all_zeros() -> void:
	var input = _make_input(PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(4, 0, 4)
	]))
	var node = _run(input, 2.0, 12345)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var type_stream = out.findStream("type")
	assert_object(type_stream).is_not_null()
	for v in type_stream.container:
		assert_float(v).is_equal_approx(0.0, 0.001)
