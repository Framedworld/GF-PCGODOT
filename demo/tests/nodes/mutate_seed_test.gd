# mutate_seed_test.gd
class_name MutateSeedTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MutateSeedNode = preload("res://addons/flow_nodes_editor/nodes/mutate_seed.gd")
const MutateSeedSettings = preload("res://addons/flow_nodes_editor/nodes/mutate_seed_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _make_data_with_position(seed_values, seed_dtype: int, positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("seed", seed_values, seed_dtype)
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(inputs: Array, settings) -> MutateSeedNode:
	var node = MutateSeedNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
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

func _expected_hash(base_seed: int, idx: int, random_seed: int, seed_offset: int) -> int:
	var h = hash([base_seed, idx, random_seed, seed_offset])
	return h & 0x7fffffff

func test_replace_mode_no_position() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Replace
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "out_seed"
	s.include_position = false
	s.random_seed = 12345
	s.seed_offset = 1

	var in_data = _make_data("seed", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out_seed")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Int)

	var expected0 = _expected_hash(10, 0, 12345, 1)
	var expected1 = _expected_hash(20, 1, 12345, 1)
	var expected2 = _expected_hash(30, 2, 12345, 1)
	assert_int(stream.container[0]).is_equal(expected0)
	assert_int(stream.container[1]).is_equal(expected1)
	assert_int(stream.container[2]).is_equal(expected2)
	node.free()

func test_add_mode_no_position() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Add
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "seed"
	s.include_position = false
	s.random_seed = 99
	s.seed_offset = 7

	var in_data = _make_data("seed", PackedInt32Array([5, 100]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("seed")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)

	var mutated0 = _expected_hash(5, 0, 99, 7)
	var mutated1 = _expected_hash(100, 1, 99, 7)
	assert_int(stream.container[0]).is_equal(int(5 + mutated0))
	assert_int(stream.container[1]).is_equal(int(100 + mutated1))
	node.free()

func test_xor_mode_no_position() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Xor
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "seed"
	s.include_position = false
	s.random_seed = 42
	s.seed_offset = 3

	var in_data = _make_data("seed", PackedInt32Array([255, 1000]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("seed")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)

	var mutated0 = _expected_hash(255, 0, 42, 3)
	var mutated1 = _expected_hash(1000, 1, 42, 3)
	assert_int(stream.container[0]).is_equal(int(255 ^ mutated0))
	assert_int(stream.container[1]).is_equal(int(1000 ^ mutated1))
	node.free()

func test_index_fallback_when_no_seed_attribute() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Replace
	s.in_seed_attribute = ""
	s.out_seed_attribute = "out_seed"
	s.include_position = false
	s.random_seed = 12345
	s.seed_offset = 1

	var in_data = _make_data("density", PackedFloat32Array([0.5, 0.5, 0.5]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out_seed")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)

	var expected0 = _expected_hash(0, 0, 12345, 1)
	var expected1 = _expected_hash(1, 1, 12345, 1)
	var expected2 = _expected_hash(2, 2, 12345, 1)
	assert_int(stream.container[0]).is_equal(expected0)
	assert_int(stream.container[1]).is_equal(expected1)
	assert_int(stream.container[2]).is_equal(expected2)
	node.free()

func test_float_seed_attribute() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Replace
	s.in_seed_attribute = "fseed"
	s.out_seed_attribute = "out_seed"
	s.include_position = false
	s.random_seed = 12345
	s.seed_offset = 1

	var in_data = _make_data("fseed", PackedFloat32Array([3.7, 9.2]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out_seed")
	assert_object(stream).is_not_null()

	var expected0 = _expected_hash(int(round(3.7)), 0, 12345, 1)
	var expected1 = _expected_hash(int(round(9.2)), 1, 12345, 1)
	assert_int(stream.container[0]).is_equal(expected0)
	assert_int(stream.container[1]).is_equal(expected1)
	node.free()

func test_include_position_changes_output() -> void:
	var s_no_pos = MutateSeedSettings.new()
	s_no_pos.mode = MutateSeedSettings.eMode.Replace
	s_no_pos.in_seed_attribute = "seed"
	s_no_pos.out_seed_attribute = "out_seed"
	s_no_pos.include_position = false
	s_no_pos.random_seed = 77
	s_no_pos.seed_offset = 2

	var s_with_pos = MutateSeedSettings.new()
	s_with_pos.mode = MutateSeedSettings.eMode.Replace
	s_with_pos.in_seed_attribute = "seed"
	s_with_pos.out_seed_attribute = "out_seed"
	s_with_pos.include_position = true
	s_with_pos.random_seed = 77
	s_with_pos.seed_offset = 2

	var positions = PackedVector3Array([Vector3(1.0, 2.0, 3.0), Vector3(4.0, 5.0, 6.0)])
	var in_data_with_pos = _make_data_with_position(PackedInt32Array([10, 20]), FlowDataScript.DataType.Int, positions)

	var in_data_no_pos = _make_data("seed", PackedInt32Array([10, 20]), FlowDataScript.DataType.Int)

	var node_no_pos = _run([in_data_no_pos], s_no_pos)
	assert_str(node_no_pos.err).is_empty()
	var out_no_pos = _output(node_no_pos)
	var stream_no_pos = out_no_pos.findStream("out_seed")

	var node_with_pos = _run([in_data_with_pos], s_with_pos)
	assert_str(node_with_pos.err).is_empty()
	var out_with_pos = _output(node_with_pos)
	var stream_with_pos = out_with_pos.findStream("out_seed")

	assert_bool(stream_no_pos.container[0] != stream_with_pos.container[0]).is_true()
	node_no_pos.free()
	node_with_pos.free()

func test_single_point() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Replace
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "out_seed"
	s.include_position = false
	s.random_seed = 12345
	s.seed_offset = 1

	var in_data = _make_data("seed", PackedInt32Array([42]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out_seed")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	var expected = _expected_hash(42, 0, 12345, 1)
	assert_int(stream.container[0]).is_equal(expected)
	node.free()

func test_empty_input_passthrough() -> void:
	var s = MutateSeedSettings.new()
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "out_seed"
	s.include_position = false

	var in_data = FlowDataScript.Data.new()
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_missing_input_error() -> void:
	var s = MutateSeedSettings.new()
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "out_seed"
	s.include_position = false

	var node = _run([], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_output_name_error() -> void:
	var s = MutateSeedSettings.new()
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = ""
	s.include_position = false

	var in_data = _make_data("seed", PackedInt32Array([1, 2]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_wrong_seed_type_error() -> void:
	var s = MutateSeedSettings.new()
	s.in_seed_attribute = "vseed"
	s.out_seed_attribute = "out_seed"
	s.include_position = false

	var in_data = _make_data("vseed", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_include_position_missing_position_stream_error() -> void:
	var s = MutateSeedSettings.new()
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "out_seed"
	s.include_position = true

	var in_data = _make_data("seed", PackedInt32Array([1, 2]), FlowDataScript.DataType.Int)
	var node = _run([in_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_broadcast_single_seed_value() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Replace
	s.in_seed_attribute = "seed"
	s.out_seed_attribute = "out_seed"
	s.include_position = false
	s.random_seed = 12345
	s.seed_offset = 1

	var in_data = _make_data("seed", PackedInt32Array([999]), FlowDataScript.DataType.Int)
	in_data.registerStream("extra", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("out_seed")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	var expected0 = _expected_hash(999, 0, 12345, 1)
	assert_int(stream.container[0]).is_equal(expected0)
	node.free()

func test_output_stream_is_int_type() -> void:
	var s = MutateSeedSettings.new()
	s.mode = MutateSeedSettings.eMode.Replace
	s.in_seed_attribute = ""
	s.out_seed_attribute = "out_seed"
	s.include_position = false
	s.random_seed = 12345
	s.seed_offset = 1

	var in_data = _make_data("density", PackedFloat32Array([0.1, 0.2, 0.3, 0.4, 0.5]), FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("out_seed")
	assert_object(stream).is_not_null()
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Int)
	assert_int(stream.container.size()).is_equal(5)
	node.free()
