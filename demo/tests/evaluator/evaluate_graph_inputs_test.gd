# evaluate_graph_inputs_test.gd
# Graph-input feeding in FlowNodeIO._build_evaluation_state: primitive
# coercion (_coerce_input_data), what the input feed carries across the graph
# boundary (streams, data_attrs, kind, tags) and graph-default fallback.
class_name EvaluateGraphInputsTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

var Probe

func before_test() -> void:
	TestGraph.register_probes()
	Probe = TestGraph.probe()

func after_test() -> void:
	TestGraph.unregister_probes()

func _log_entry(node_name: String) -> Dictionary:
	for entry in Probe.exec_log:
		if entry.name == node_name:
			return entry
	return {}

## graph: input_<name> -> probe (final). Returns the Data the probe received.
func _feed_specific(param_name: String, data_type: int, value, default_value = null) -> FlowData.Data:
	var graph = TestGraph.new() \
		.in_param(param_name, data_type, default_value) \
		.node("in", "input_" + param_name, {"name": param_name, "data_type": data_type}) \
		.node("sink", "test_probe_final") \
		.link("in", 0, "sink", 0) \
		.build()
	var inputs := {}
	if value != null:
		inputs[param_name] = value
	FlowNodeIO.evaluate_graph(graph, inputs, TestGraph.make_ctx(), {}, 0)
	return _log_entry("sink").get("a_data")

## graph: generic multi-port "input" node with params a, b -> probe (a on A, b on B).
func _feed_multiport(inputs: Dictionary) -> Dictionary:
	var graph = TestGraph.new() \
		.in_param("a", FlowData.DataType.Float, 1.5) \
		.in_param("b", FlowData.DataType.Int, 7) \
		.node("ins", "input", {"name": "in_val"}) \
		.node("sink", "test_probe_final") \
		.link("ins", 0, "sink", 0) \
		.link("ins", 1, "sink", 1) \
		.build()
	FlowNodeIO.evaluate_graph(graph, inputs, TestGraph.make_ctx(), {}, 0)
	return _log_entry("sink")

func _first(data: FlowData.Data, stream_name: String):
	var s = data.findStream(stream_name)
	if s == null or s.container.size() == 0:
		return null
	return s.container[0]


# --- _coerce_input_data (direct) -----------------------------------------------

func test_coerce_wraps_float() -> void:
	var d = FlowNodeIO._coerce_input_data(2.5, "x")
	assert_object(d).is_not_null()
	assert_int(d.findStream("x").data_type).is_equal(FlowData.DataType.Float)
	assert_float(d.findStream("x").container[0]).is_equal(2.5)
	assert_int(d.size()).is_equal(1)

func test_coerce_wraps_int() -> void:
	var d = FlowNodeIO._coerce_input_data(42, "x")
	assert_int(d.findStream("x").data_type).is_equal(FlowData.DataType.Int)
	assert_bool(d.findStream("x").container is PackedInt32Array).is_true()
	assert_int(d.findStream("x").container[0]).is_equal(42)

func test_coerce_wraps_bool_as_byte() -> void:
	var d = FlowNodeIO._coerce_input_data(true, "flag")
	assert_int(d.findStream("flag").data_type).is_equal(FlowData.DataType.Bool)
	assert_bool(d.findStream("flag").container is PackedByteArray).is_true()
	assert_int(d.findStream("flag").container[0]).is_equal(1)

func test_coerce_wraps_string() -> void:
	var d = FlowNodeIO._coerce_input_data("hello", "label")
	assert_int(d.findStream("label").data_type).is_equal(FlowData.DataType.String)
	assert_str(d.findStream("label").container[0]).is_equal("hello")

func test_coerce_wraps_vector3() -> void:
	var d = FlowNodeIO._coerce_input_data(Vector3(1, 2, 3), "offset")
	assert_int(d.findStream("offset").data_type).is_equal(FlowData.DataType.Vector)
	assert_vector(d.findStream("offset").container[0]).is_equal(Vector3(1, 2, 3))

func test_coerce_wraps_color() -> void:
	var d = FlowNodeIO._coerce_input_data(Color(0.25, 0.5, 0.75, 1.0), "tint")
	assert_int(d.findStream("tint").data_type).is_equal(FlowData.DataType.Color)
	assert_bool(d.findStream("tint").container is PackedColorArray).is_true()
	assert_that(d.findStream("tint").container[0]).is_equal(Color(0.25, 0.5, 0.75, 1.0))

func test_coerce_keeps_falsy_primitives() -> void:
	assert_float(FlowNodeIO._coerce_input_data(0.0, "f").findStream("f").container[0]).is_equal(0.0)
	assert_int(FlowNodeIO._coerce_input_data(0, "i").findStream("i").container[0]).is_equal(0)
	assert_int(FlowNodeIO._coerce_input_data(false, "b").findStream("b").container[0]).is_equal(0)
	assert_str(FlowNodeIO._coerce_input_data("", "s").findStream("s").container[0]).is_equal("")

func test_coerce_passes_data_through_unchanged() -> void:
	var d = TestGraph.float_data("v", [1.0, 2.0])
	assert_object(FlowNodeIO._coerce_input_data(d, "v")).is_same(d)

func test_coerce_null_is_null() -> void:
	assert_object(FlowNodeIO._coerce_input_data(null, "x")).is_null()

func test_coerce_unsupported_type_is_null() -> void:
	# Dictionaries, Vector2 and StringName are not wrappable today.
	assert_object(FlowNodeIO._coerce_input_data({"a": 1}, "x")).is_null()
	assert_object(FlowNodeIO._coerce_input_data(Vector2(1, 2), "x")).is_null()
	assert_object(FlowNodeIO._coerce_input_data(&"name", "x")).is_null()


# --- primitive feeds through evaluate_graph ------------------------------------

func test_float_primitive_feeds_input_node() -> void:
	var d = _feed_specific("speed", FlowData.DataType.Float, 3.25)
	assert_float(_first(d, "speed")).is_equal(3.25)

func test_int_primitive_feeds_input_node() -> void:
	var d = _feed_specific("count", FlowData.DataType.Int, 9)
	assert_int(_first(d, "count")).is_equal(9)
	assert_int(d.findStream("count").data_type).is_equal(FlowData.DataType.Int)

func test_bool_primitive_feeds_input_node() -> void:
	var d = _feed_specific("enabled", FlowData.DataType.Bool, true)
	assert_int(_first(d, "enabled")).is_equal(1)

func test_string_primitive_feeds_input_node() -> void:
	var d = _feed_specific("label", FlowData.DataType.String, "north")
	assert_str(_first(d, "label")).is_equal("north")

func test_vector3_primitive_feeds_input_node() -> void:
	var d = _feed_specific("offset", FlowData.DataType.Vector, Vector3(0, 1, 0))
	assert_vector(_first(d, "offset")).is_equal(Vector3(0, 1, 0))

func test_color_primitive_feeds_input_node() -> void:
	var d = _feed_specific("tint", FlowData.DataType.Color, Color.RED)
	assert_that(_first(d, "tint")).is_equal(Color.RED)

func test_primitive_type_comes_from_the_value_not_the_param() -> void:
	# Current behaviour: an int fed into a Float parameter arrives as an Int stream.
	var d = _feed_specific("speed", FlowData.DataType.Float, 3)
	assert_int(d.findStream("speed").data_type).is_equal(FlowData.DataType.Int)

func test_unfed_specific_input_uses_graph_default() -> void:
	var d = _feed_specific("speed", FlowData.DataType.Float, null, 0.75)
	assert_float(_first(d, "speed")).is_equal(0.75)


# --- Data feeds: what crosses the boundary -------------------------------------

func _rich_data() -> FlowData.Data:
	var d := TestGraph.points([Vector3(1, 0, 0), Vector3(2, 0, 0)])
	d.registerStream("weight", PackedFloat32Array([0.1, 0.9]), FlowData.DataType.Float)
	d.registerStream("@data.room_id", PackedInt32Array([17]), FlowData.DataType.Int)
	d.kind = FlowData.Kind.Spline
	d.tags = PackedStringArray(["hall", "north"])
	return d

func test_input_feed_registers_streams_and_aliases_main_stream_under_input_name() -> void:
	var d = _feed_specific("pts", FlowData.DataType.Vector, _rich_data())
	assert_object(d.findStream("position")).is_not_null()
	assert_object(d.findStream("weight")).is_not_null()
	# The last-added stream ("weight") is also exposed as the input name.
	assert_object(d.findStream("pts")).is_not_null()
	assert_array(Array(d.findStream("pts").container)).is_equal(Array(d.findStream("weight").container))

func test_input_feed_carries_data_attrs_and_kind() -> void:
	var d = _feed_specific("pts", FlowData.DataType.Vector, _rich_data())
	assert_bool(d.data_attrs.has("room_id")).is_true()
	assert_int(d.data_attrs["room_id"].value).is_equal(17)
	assert_int(d.kind).is_equal(FlowData.Kind.Spline)

func test_input_feed_is_a_new_data_sharing_containers() -> void:
	var src = _rich_data()
	var d = _feed_specific("pts", FlowData.DataType.Vector, src)
	assert_object(d).is_not_same(src)
	assert_int(d.size()).is_equal(2)

# LEGACY: the input feed drops tags today. Agent A's P0 round
# (RUNTIME_API_P0.md section 3) makes both feed branches copy tags; when that
# lands, invert these assertions (tags must equal ["hall", "north"]).
func test_input_feed_carries_tags() -> void:
	# Tags cross the graph-input boundary along with data_attrs and kind
	# (RUNTIME_API_P0 §3); both feed branches must carry them.
	var specific = _feed_specific("pts", FlowData.DataType.Vector, _rich_data())
	assert_array(Array(specific.tags)).is_equal(["hall", "north"])
	Probe.reset_probe_state()
	var multi = _feed_multiport({"a": _rich_data()})
	assert_array(Array(multi.a_data.tags)).is_equal(["hall", "north"])


func test_multiport_input_carries_data_attrs_and_kind() -> void:
	var entry = _feed_multiport({"a": _rich_data()})
	var a = entry.a_data
	assert_int(a.kind).is_equal(FlowData.Kind.Spline)
	assert_int(a.data_attrs["room_id"].value).is_equal(17)
	assert_object(a.findStream("a")).is_not_null()

func test_multiport_input_uses_defaults_for_unfed_params() -> void:
	var entry = _feed_multiport({})
	assert_float(_first(entry.a_data, "a")).is_equal(1.5)
	assert_int(_first(entry.b_data, "b")).is_equal(7)

func test_multiport_input_coerces_primitives_per_param() -> void:
	var entry = _feed_multiport({"a": 4.0, "b": 11})
	assert_float(_first(entry.a_data, "a")).is_equal(4.0)
	assert_int(_first(entry.b_data, "b")).is_equal(11)
