# match_and_set_test.gd
class_name MatchAndSetTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MatchAndSetNode = preload("res://addons/flow_nodes_editor/nodes/match_and_set.gd")
const MatchAndSetSettings = preload("res://addons/flow_nodes_editor/nodes/match_and_set_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> MatchAndSetNode:
	var node = MatchAndSetNode.new()
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
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_missing_in_input_errors() -> void:
	var s = MatchAndSetSettings.new()
	var node = _run([null, null], s)
	assert_str(node.err).is_not_empty()

func test_missing_attrs_input_errors() -> void:
	var s = MatchAndSetSettings.new()
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run([in_data, null], s)
	assert_str(node.err).is_not_empty()

func test_random_pick_no_match_attr_copies_float_stream() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = ""
	s.weight_attr = ""

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2, 0, 0)]), FlowDataScript.DataType.Vector)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("color_id", PackedFloat32Array([10.0, 20.0, 30.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var color_stream = out.findStream("color_id")
	assert_object(color_stream).is_not_null()
	assert_int(color_stream.container.size()).is_equal(3)

func test_match_attr_assigns_correct_float_values() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "type_id"
	s.weight_attr = ""

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("type_id", PackedInt32Array([1, 2, 1]), FlowDataScript.DataType.Int)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("type_id", PackedInt32Array([1, 2]), FlowDataScript.DataType.Int)
	attrs_data.registerStream("scale", PackedFloat32Array([0.5, 1.5]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var scale_stream = out.findStream("scale")
	assert_object(scale_stream).is_not_null()
	assert_float(scale_stream.container[0]).is_equal_approx(0.5, 0.001)
	assert_float(scale_stream.container[1]).is_equal_approx(1.5, 0.001)
	assert_float(scale_stream.container[2]).is_equal_approx(0.5, 0.001)

func test_match_attr_missing_in_attrs_errors() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "nonexistent"
	s.weight_attr = ""

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("nonexistent", PackedInt32Array([1, 2]), FlowDataScript.DataType.Int)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("some_other", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_not_empty()

func test_match_attr_missing_in_in_data_errors() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "type_id"
	s.weight_attr = ""

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("other_stream", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("type_id", PackedInt32Array([1, 2]), FlowDataScript.DataType.Int)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_not_empty()

func test_weight_attr_missing_in_attrs_errors() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = ""
	s.weight_attr = "bad_weight"

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("scale", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_not_empty()

func test_weighted_random_no_match_attr_no_crash() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = ""
	s.weight_attr = "weight"

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2, 0, 0), Vector3(3, 0, 0)]), FlowDataScript.DataType.Vector)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("weight", PackedFloat32Array([1.0, 3.0, 0.0]), FlowDataScript.DataType.Float)
	attrs_data.registerStream("tag", PackedFloat32Array([10.0, 20.0, 30.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)
	var tag_stream = out.findStream("tag")
	assert_object(tag_stream).is_not_null()
	assert_int(tag_stream.container.size()).is_equal(4)

func test_match_attr_with_weight_picks_from_candidates() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "type_id"
	s.weight_attr = "weight"

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("type_id", PackedInt32Array([1, 1, 1, 1, 1]), FlowDataScript.DataType.Int)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("type_id", PackedInt32Array([1, 1]), FlowDataScript.DataType.Int)
	attrs_data.registerStream("weight", PackedFloat32Array([1.0, 0.0]), FlowDataScript.DataType.Float)
	attrs_data.registerStream("value", PackedFloat32Array([100.0, 200.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(5)
	var value_stream = out.findStream("value")
	assert_object(value_stream).is_not_null()
	assert_int(value_stream.container.size()).is_equal(5)
	for i in range(5):
		assert_float(value_stream.container[i]).is_equal_approx(100.0, 0.001)

func test_no_match_attr_single_attrs_entry_assigns_to_all() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = ""
	s.weight_attr = ""

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3(2, 0, 0)]), FlowDataScript.DataType.Vector)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("label", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var label_stream = out.findStream("label")
	assert_object(label_stream).is_not_null()
	assert_int(label_stream.container.size()).is_equal(3)
	for i in range(3):
		assert_float(label_stream.container[i]).is_equal_approx(42.0, 0.001)

func test_match_attr_unmatched_values_get_zero_filled() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "type_id"
	s.weight_attr = ""

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("type_id", PackedInt32Array([1, 99, 1]), FlowDataScript.DataType.Int)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("type_id", PackedInt32Array([1]), FlowDataScript.DataType.Int)
	attrs_data.registerStream("value", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(3)
	var value_stream = out.findStream("value")
	assert_object(value_stream).is_not_null()
	assert_float(value_stream.container[0]).is_equal_approx(5.0, 0.001)
	assert_float(value_stream.container[2]).is_equal_approx(5.0, 0.001)

func test_random_pick_empty_in_data_no_crash() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = ""
	s.weight_attr = ""

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array(), FlowDataScript.DataType.Vector)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("label", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_match_attr_multiple_candidates_selected_randomly() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "cat"
	s.weight_attr = ""
	s.random_seed = 7

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("cat", PackedInt32Array([2, 2, 2, 2, 2, 2, 2, 2, 2, 2]), FlowDataScript.DataType.Int)

	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("cat", PackedInt32Array([2, 2, 2]), FlowDataScript.DataType.Int)
	attrs_data.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)

	var node = _run([in_data, attrs_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(10)
	var score_stream = out.findStream("score")
	assert_object(score_stream).is_not_null()
	assert_int(score_stream.container.size()).is_equal(10)

# ---------------------------------------------------------------------------
# Numeric keys: JSON numbers load as floats, keys are often "3"/3. Values that
# have no exact string match fall back to a float comparison when both sides
# are numeric.
# ---------------------------------------------------------------------------

func _run_match(in_stream: Dictionary, key_stream: Dictionary) -> MatchAndSetNode:
	var s = MatchAndSetSettings.new()
	s.match_attr = "id"
	s.weight_attr = ""
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("id", in_stream.values, in_stream.type)
	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("id", key_stream.values, key_stream.type)
	attrs_data.registerStream("color", PackedStringArray(["red", "blue"]), FlowDataScript.DataType.String)
	return _run([in_data, attrs_data], s)

func test_numeric_key_int_attribute_matches_float_string_key() -> void:
	var node = _run_match(
		{"values": PackedInt32Array([3, 5, 4]), "type": FlowDataScript.DataType.Int},
		{"values": PackedStringArray(["3.0", "5.00"]), "type": FlowDataScript.DataType.String})
	assert_str(node.err).is_empty()
	# 4 matches nothing and keeps the zero-filled default.
	assert_array(Array(_output(node).findStream("color").container)).is_equal(["red", "blue", ""])

func test_numeric_key_float_attribute_matches_int_string_key() -> void:
	var node = _run_match(
		{"values": PackedFloat32Array([3.0, 7.0, 5.0]), "type": FlowDataScript.DataType.Float},
		{"values": PackedStringArray(["3", "5"]), "type": FlowDataScript.DataType.String})
	assert_array(Array(_output(node).findStream("color").container)).is_equal(["red", "", "blue"])

func test_numeric_key_float_attribute_matches_int_key() -> void:
	# Float32 storage of 0.1 is not exactly 0.1: matched with is_equal_approx.
	var node = _run_match(
		{"values": PackedFloat32Array([3.0, 0.1]), "type": FlowDataScript.DataType.Float},
		{"values": PackedStringArray(["3", "0.1"]), "type": FlowDataScript.DataType.String})
	assert_array(Array(_output(node).findStream("color").container)).is_equal(["red", "blue"])

func test_numeric_key_non_numeric_values_keep_string_matching() -> void:
	var node = _run_match(
		{"values": PackedStringArray(["a", "3", "b"]), "type": FlowDataScript.DataType.String},
		{"values": PackedStringArray(["b", "a"]), "type": FlowDataScript.DataType.String})
	assert_array(Array(_output(node).findStream("color").container)).is_equal(["blue", "", "red"])

func test_numeric_key_empty_string_key_is_not_a_fallback() -> void:
	# An empty key must not swallow numeric values that match no numeric key.
	var node = _run_match(
		{"values": PackedFloat32Array([9.0, 3.0]), "type": FlowDataScript.DataType.Float},
		{"values": PackedStringArray(["", "3"]), "type": FlowDataScript.DataType.String})
	assert_array(Array(_output(node).findStream("color").container)).is_equal(["", "blue"])

# ---------------------------------------------------------------------------
# RNG source without a `seed` stream. Default: per-point seed from
# FlowData.resolve_seed (position hash), stable under reordering.
# legacy_global_rng = true: the node-global RNG in point order (old output).
# ---------------------------------------------------------------------------

const _RNG_POSITIONS := [Vector3(0, 0, 0), Vector3(1.5, 0, 2), Vector3(-3, 1, 4), Vector3(7, 0, -2), Vector3(2, 2, 2), Vector3(9, 0, 1), Vector3(-5, 0, -5), Vector3(4, 3, 0)]
const _SCORES := [10.0, 20.0, 30.0, 40.0, 50.0]

func _run_random_pick(positions: Array, legacy: bool, seed_value := 99) -> MatchAndSetNode:
	var s = MatchAndSetSettings.new()
	s.match_attr = ""
	s.weight_attr = ""
	s.random_seed = seed_value
	s.legacy_global_rng = legacy
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array(positions), FlowDataScript.DataType.Vector)
	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("score", PackedFloat32Array(_SCORES), FlowDataScript.DataType.Float)
	return _run([in_data, attrs_data], s)

func test_legacy_global_rng_defaults_off() -> void:
	assert_bool(MatchAndSetSettings.new().legacy_global_rng).is_false()

func test_no_seed_stream_uses_position_hashed_seed() -> void:
	var node = _run_random_pick(_RNG_POSITIONS, false)
	assert_str(node.err).is_empty()
	var scores = _output(node).findStream("score").container
	var expected := []
	var prng := RandomNumberGenerator.new()
	var positions := PackedVector3Array(_RNG_POSITIONS)
	for i in positions.size():
		prng.seed = FlowData.resolve_seed(null, positions, i, 99)
		expected.append(_SCORES[prng.randi_range(0, 4)])
	assert_array(Array(scores)).is_equal(expected)

func test_no_seed_stream_pick_is_stable_under_reordering() -> void:
	var node_a = _run_random_pick(_RNG_POSITIONS, false)
	var reversed := _RNG_POSITIONS.duplicate()
	reversed.reverse()
	var node_b = _run_random_pick(reversed, false)
	var a = _output(node_a).findStream("score").container
	var b = _output(node_b).findStream("score").container
	for i in _RNG_POSITIONS.size():
		assert_float(b[_RNG_POSITIONS.size() - 1 - i]).is_equal(a[i])

func test_legacy_global_rng_draws_node_rng_in_point_order() -> void:
	var node = _run_random_pick(_RNG_POSITIONS, true)
	assert_str(node.err).is_empty()
	var scores = _output(node).findStream("score").container
	var expected := []
	var global_rng := RandomNumberGenerator.new()
	global_rng.seed = 99
	for i in _RNG_POSITIONS.size():
		expected.append(_SCORES[global_rng.randi_range(0, 4)])
	assert_array(Array(scores)).is_equal(expected)

func test_legacy_global_rng_lut_path_draws_node_rng_in_point_order() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "cat"
	s.random_seed = 7
	s.legacy_global_rng = true
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("cat", PackedInt32Array([2, 2, 2, 2, 2, 2]), FlowDataScript.DataType.Int)
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array(_RNG_POSITIONS.slice(0, 6)), FlowDataScript.DataType.Vector)
	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("cat", PackedInt32Array([2, 2, 2]), FlowDataScript.DataType.Int)
	attrs_data.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data, attrs_data], s)
	var expected := []
	var global_rng := RandomNumberGenerator.new()
	global_rng.seed = 7
	for i in 6:
		expected.append([1.0, 2.0, 3.0][global_rng.randi_range(0, 2)])
	assert_array(Array(_output(node).findStream("score").container)).is_equal(expected)

func test_lut_path_without_seed_stream_uses_position_hashed_seed() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "cat"
	s.random_seed = 7
	var positions := PackedVector3Array(_RNG_POSITIONS.slice(0, 6))
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("cat", PackedInt32Array([2, 2, 2, 2, 2, 2]), FlowDataScript.DataType.Int)
	in_data.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	var attrs_data := FlowDataScript.Data.new()
	attrs_data.registerStream("cat", PackedInt32Array([2, 2, 2]), FlowDataScript.DataType.Int)
	attrs_data.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run([in_data, attrs_data], s)
	var expected := []
	var prng := RandomNumberGenerator.new()
	for i in 6:
		prng.seed = FlowData.resolve_seed(null, positions, i, 7)
		expected.append([1.0, 2.0, 3.0][prng.randi_range(0, 2)])
	assert_array(Array(_output(node).findStream("score").container)).is_equal(expected)

func test_seed_stream_path_unchanged_by_legacy_flag() -> void:
	var outputs := []
	for legacy in [false, true]:
		var s = MatchAndSetSettings.new()
		s.random_seed = 5
		s.legacy_global_rng = legacy
		var in_data := FlowDataScript.Data.new()
		in_data.registerStream(FlowData.AttrPosition, PackedVector3Array(_RNG_POSITIONS), FlowDataScript.DataType.Vector)
		in_data.registerStream(FlowData.AttrSeed, PackedInt32Array([11, 22, 33, 44, 55, 66, 77, 88]), FlowDataScript.DataType.Int)
		var attrs_data := FlowDataScript.Data.new()
		attrs_data.registerStream("score", PackedFloat32Array(_SCORES), FlowDataScript.DataType.Float)
		var node = _run([in_data, attrs_data], s)
		outputs.append(Array(_output(node).findStream("score").container))
	var expected := []
	var prng := RandomNumberGenerator.new()
	for sd in [11, 22, 33, 44, 55, 66, 77, 88]:
		prng.seed = (sd ^ 5) & 0x7fffffff
		expected.append(_SCORES[prng.randi_range(0, 4)])
	assert_array(outputs[0]).is_equal(expected)
	assert_array(outputs[1]).is_equal(expected)

# ---------------------------------------------------------------------------
# Empty In keeps the Attributes table's schema: downstream expressions name the
# table columns, so an empty result must still carry them (typed, zero-length).
# ---------------------------------------------------------------------------

func _attribute_table() -> FlowData.Data:
	var attrs := FlowDataScript.Data.new()
	attrs.registerStream("cat", PackedInt32Array([1, 2]), FlowDataScript.DataType.Int)
	attrs.registerStream("mesh_name", PackedStringArray(["a", "b"]), FlowDataScript.DataType.String)
	attrs.registerStream("scale", PackedFloat32Array([0.5, 2.0]), FlowDataScript.DataType.Float)
	attrs.registerStream("tint", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)
	attrs.registerStream("weight", PackedFloat32Array([1.0, 3.0]), FlowDataScript.DataType.Float)
	return attrs

func _assert_empty_with_table_schema(node, in_data: FlowData.Data) -> void:
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	if out == null:
		return
	assert_int(out.size()).is_equal(0)
	var table := _attribute_table()
	for stream in table.streams.values():
		var got = out.findStream(stream.name)
		assert_object(got).override_failure_message("missing column '%s'" % stream.name).is_not_null()
		if got != null:
			assert_int(got.data_type).override_failure_message("column '%s' type" % stream.name).is_equal(stream.data_type)
			assert_int(got.container.size()).is_equal(0)
	# In's own streams are kept, and nothing else is added.
	var expected := {}
	for n in in_data.streams.keys():
		expected[n] = true
	for n in table.streams.keys():
		expected[n] = true
	assert_int(out.streams.size()).is_equal(expected.size())

func test_empty_in_keeps_attribute_table_schema_random_pick() -> void:
	var s = MatchAndSetSettings.new()
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array(), FlowDataScript.DataType.Vector)
	var node = _run([in_data, _attribute_table()], s)
	_assert_empty_with_table_schema(node, in_data)

func test_empty_in_without_streams_keeps_schema_with_match_and_weight_attrs() -> void:
	# A stream-less empty In has no match column; that used to be an error.
	var s = MatchAndSetSettings.new()
	s.match_attr = "cat"
	s.weight_attr = "weight"
	var in_data := FlowDataScript.Data.new()
	var node = _run([in_data, _attribute_table()], s)
	_assert_empty_with_table_schema(node, in_data)

func test_empty_in_with_match_column_keeps_schema() -> void:
	var s = MatchAndSetSettings.new()
	s.match_attr = "cat"
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array(), FlowDataScript.DataType.Vector)
	in_data.registerStream("cat", PackedInt32Array(), FlowDataScript.DataType.Int)
	var node = _run([in_data, _attribute_table()], s)
	_assert_empty_with_table_schema(node, in_data)

func test_empty_in_and_empty_table_passes_in_through() -> void:
	var s = MatchAndSetSettings.new()
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array(), FlowDataScript.DataType.Vector)
	var node = _run([in_data, FlowDataScript.Data.new()], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	assert_array(out.streams.keys()).contains_exactly([FlowData.AttrPosition])
	assert_object(out).is_not_same(in_data)
