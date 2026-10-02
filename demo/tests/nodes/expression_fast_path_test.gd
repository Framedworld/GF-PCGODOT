# expression_fast_path_test.gd
# Pins the expression node after the WP13-P1 performance rewrite (only the
# streams named in the expression are bound, unrolled per-point copies, direct
# typed stores) to the original implementation, kept verbatim in
# support/expression_reference.gd. Every case runs both scripts on the same
# input and requires byte-identical output Data (stream order, names, types,
# raw container bytes, tags, data attributes) and the same error text.
class_name ExpressionFastPathTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/expression.gd")
const ReferenceScript = preload("res://tests/nodes/support/expression_reference.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/expression_settings.gd")

const T := FlowDataScript.DataType

static func _make_input(n : int) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var positions := []
	for i in range(n):
		positions.append(Vector3(rng.randf_range(-5, 5), rng.randf_range(0, 2), rng.randf_range(-5, 5)))
	var d = H.points(positions)
	var dens := PackedFloat32Array()
	var ids := PackedInt32Array()
	var flags := PackedByteArray()
	var cols := PackedColorArray()
	var names := PackedStringArray()
	var wide := PackedFloat64Array()
	var big := PackedInt64Array()
	for i in range(n):
		dens.append(rng.randf())
		ids.append(i * 3 - 7)
		flags.append(i % 3 == 0)
		cols.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))
		names.append("n%d" % i)
		wide.append(rng.randf() * 1.0e10)
		big.append(int(i) * 3000000000)
	d.registerStream(FlowDataScript.AttrDensity, dens, T.Float)
	d.registerStream("id", ids, T.Int)
	d.registerStream("flag", flags, T.Bool)
	d.registerStream("tint", cols, T.Color)
	d.registerStream("label", names, T.String)
	d.registerStream("wide", wide, T.Double)
	d.registerStream("big", big, T.Int64)
	d.tags = PackedStringArray(["a", "b"])
	d.set_data_attr("level", 3)
	return d

static func _settings(expression : String, out_name : String, expose_arrays := false, args := {}):
	var s = SettingsScript.new()
	s.expression = expression
	s.out_name = out_name
	s.expose_arrays = expose_arrays
	s.args = args.duplicate()
	return s

static func _bytes(data) -> PackedByteArray:
	if not (data is FlowData.Data):
		return var_to_bytes(str(data))
	var out := PackedByteArray()
	for stream_name in data.streams:
		var stream : Dictionary = data.streams[stream_name]
		out.append_array(var_to_bytes([str(stream_name), str(stream.name), int(stream.data_type)]))
		out.append_array(var_to_bytes(stream.container))
	out.append_array(var_to_bytes([data.last_added_stream_name, data.tags, int(data.kind), var_to_str(data.data_attrs)]))
	return out

static func _result_bytes(r : Dictionary) -> Array:
	var parts := [r.err, r.bulks.size()]
	for bulk in r.bulks:
		for data in bulk:
			parts.append(_bytes(data))
	return parts

## Every error and warning logged while a node runs (script errors included),
## so the two implementations can be compared message for message.
class CaptureLogger extends Logger:
	var messages : Array = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append("%d:%s:%s" % [error_type, code, rationale])
	func _log_message(_message: String, _error: bool) -> void:
		pass

static func _exec_logged(script, settings, input) -> Array:
	var logger := CaptureLogger.new()
	OS.add_logger(logger)
	var r := H.exec(script, settings, [input])
	OS.remove_logger(logger)
	var parts := _result_bytes(r)
	parts.append(logger.messages)
	return parts

## Script errors are expected in some cases (both implementations raise the
## same ones, compared above); drop them from GdUnit's monitor.
func _clear_gdunit_script_errors() -> void:
	var ctx = GdUnitThreadManager.get_current_context()
	if ctx == null:
		return
	var exec_ctx = ctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()

func _assert_same(expression : String, out_name : String, data = null, expose_arrays := false, args := {}, trace := false) -> void:
	var input = data if data != null else _make_input(37)
	var s_ref = _settings(expression, out_name, expose_arrays, args)
	var s_new = _settings(expression, out_name, expose_arrays, args)
	s_ref.trace = trace
	s_new.trace = trace
	var expected := _exec_logged(ReferenceScript, s_ref, input)
	var actual := _exec_logged(NodeScript, s_new, input)
	_clear_gdunit_script_errors()
	assert_array(actual).override_failure_message("'%s' -> %s differs from the reference:\n%s\nvs\n%s" % [expression, out_name, str(actual.back()), str(expected.back())]).is_equal(expected)

func test_scalar_results_match_the_reference() -> void:
	_assert_same("density * 0.5 + 0.25", "density")
	_assert_same("density * 0.5 + 0.25", "new_float")
	_assert_same("position.y + density", "py")
	_assert_same("sin(density) * 3.0", "s")
	_assert_same("Index * 2 + Size", "ints")
	_assert_same("id % 5", "id")
	_assert_same("Index % 2 == 0", "even")
	_assert_same("flag", "flag2")
	_assert_same("wide * 2.0", "wide")
	_assert_same("big + 1", "big")
	_assert_same("label + \"_x\"", "label2")

func test_vector_and_color_results_match_the_reference() -> void:
	_assert_same("position * 2.0", "p2")
	_assert_same("position", "position")
	_assert_same("tint * 0.5", "tint2")
	_assert_same("Vector2(density, Index)", "uv")
	_assert_same("Vector4(density, 1, 2, 3)", "v4")
	_assert_same("Quaternion(0, 0, 0, 1)", "q")

func test_mixed_result_types_and_coercion_match_the_reference() -> void:
	# Result type changes between points: later points go through writeValue.
	_assert_same("Index if Index % 2 == 0 else 0.5", "mixed")
	_assert_same("0.5 if Index % 2 == 0 else Index", "mixed2")
	_assert_same("Index % 3 == 0 if Index > 4 else Index", "mixed3")
	# Numeric result into an existing stream of another numeric type.
	_assert_same("density * 10.0", "id")
	_assert_same("Index", "density")
	_assert_same("density > 0.5", "id")
	# A vector result for a later point of a float stream.
	_assert_same("density if Index < 3 else position", "bad")

func test_arguments_selectors_and_unbound_names_match_the_reference() -> void:
	_assert_same("density * k + offset", "d2", null, false, { "k": 2.0, "offset": 1 })
	_assert_same("$Density * 2.0", "d3")
	_assert_same("$Position.x + $Index", "d4")
	# Five and more bound streams take the generic copy loop.
	_assert_same("density + id + position.x + rotation.y + size.z + tint.r", "many")
	# Names that are substrings of other identifiers.
	_assert_same("densityx", "dx")
	_assert_same("missing_name + 1", "m")
	_assert_same("density +", "syntax")

func test_expose_arrays_matches_the_reference() -> void:
	_assert_same("position[Index].x + (position[Index - 1].x if Index > 0 else 0.0)", "prev", null, true)
	_assert_same("density[Index] * Size", "ds", null, true)
	_assert_same("density[Index + 1]", "oob", null, true)

func test_short_and_broadcast_streams_match_the_reference() -> void:
	var d := _make_input(9)
	d.registerStream("one", PackedFloat32Array([4.0]), T.Float)
	_assert_same("density * 2.0", "d", d)
	_assert_same("one * density", "d", d)
	_assert_same("one[0] * density[Index]", "d", d, true)
	var empty_stream := _make_input(5)
	empty_stream.streams["hole"] = { "name": "hole", "data_type": T.Float, "container": PackedFloat32Array() }
	_assert_same("density * 2.0", "d", empty_stream)

func test_single_point_and_trace_match_the_reference() -> void:
	_assert_same("density + 1.0", "d", _make_input(1))
	_assert_same("density * 3.0", "d", _make_input(4), false, {}, true)
	_assert_same("density[Index] * 3.0", "d", _make_input(4), true, {}, true)
