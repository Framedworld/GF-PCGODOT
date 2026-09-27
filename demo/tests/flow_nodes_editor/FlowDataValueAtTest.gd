# FlowDataValueAtTest.gd
# Data.value_at(name, i, default): per-point read that honours broadcast
# (one-element streams, per-data attributes) and every findStream selector.
class_name FlowDataValueAtTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const T := FlowData.DataType


func _data() -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)]), T.Vector)
	d.registerStream("weight", PackedFloat32Array([0.25, 0.5, 0.75]), T.Float)
	d.registerStream("tint", PackedColorArray([Color.RED]), T.Color)			# broadcast
	d.registerStream("flag", PackedByteArray([1, 0, 1]), T.Bool)
	d.registerStream("label", PackedStringArray(["a", "b", "c"]), T.String)
	d.set_data_attr("tier", 3)
	return d


func test_reads_the_point_value() -> void:
	var d := _data()
	assert_float(d.value_at("weight", 0)).is_equal(0.25)
	assert_float(d.value_at("weight", 2)).is_equal(0.75)
	assert_str(d.value_at("label", 1)).is_equal("b")
	assert_vector(d.value_at("position", 1)).is_equal(Vector3(4, 5, 6))


func test_broadcast_stream_applies_to_every_point() -> void:
	var d := _data()
	for i in 3:
		assert_object(d.value_at("tint", i)).is_equal(Color.RED)
	# A broadcast value answers any index, as bcast_idx does.
	assert_object(d.value_at("tint", 42)).is_equal(Color.RED)


func test_bool_streams_read_as_bool() -> void:
	var d := _data()
	assert_bool(d.value_at("flag", 0)).is_true()
	assert_bool(d.value_at("flag", 1)).is_false()
	assert_int(typeof(d.value_at("flag", 2))).is_equal(TYPE_BOOL)


func test_data_attributes_broadcast() -> void:
	var d := _data()
	assert_int(d.value_at("@data.tier", 0)).is_equal(3)
	assert_int(d.value_at("@data.tier", 2)).is_equal(3)
	# Plain name with no stream falls back to the data attribute, like first().
	assert_int(d.value_at("tier", 1)).is_equal(3)


func test_stream_wins_over_data_attribute_of_the_same_name() -> void:
	var d := _data()
	d.set_data_attr("weight", 9.0)
	assert_float(d.value_at("weight", 1)).is_equal(0.5)
	assert_float(d.value_at("@data.weight", 1)).is_equal(9.0)


func test_selectors() -> void:
	var d := _data()
	assert_float(d.value_at("position.y", 2)).is_equal(8.0)
	d.registerStream("rotation", PackedVector3Array([Vector3(10, 20, 30), Vector3(40, 50, 60), Vector3(70, 80, 90)]), T.Vector)
	assert_float(d.value_at("Yaw", 1)).is_equal(50.0)
	assert_vector(d.value_at("@last", 2)).is_equal(Vector3(70, 80, 90))


func test_missing_and_out_of_range_return_default() -> void:
	var d := _data()
	assert_object(d.value_at("nope", 0)).is_null()
	assert_int(d.value_at("nope", 0, -1)).is_equal(-1)
	assert_float(d.value_at("weight", 3, -1.0)).is_equal(-1.0)
	assert_float(d.value_at("weight", -1, -2.0)).is_equal(-2.0)
	assert_str(d.value_at("", 0, "x")).is_equal("x")


func test_empty_stream_returns_default() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream("weight", PackedFloat32Array(), T.Float)
	assert_float(d.value_at("weight", 0, 7.0)).is_equal(7.0)


func test_matches_first_for_index_zero() -> void:
	var d := _data()
	for stream_name in ["position", "weight", "tint", "flag", "label", "@data.tier", "tier", "position.x"]:
		assert_that(d.value_at(stream_name, 0)).is_equal(d.first(stream_name))
