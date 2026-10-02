# data_filter_fast_path_test.gd
# Pins FlowData.Data.filter after the WP13-P1 performance change (common
# streams inserted directly instead of through registerStream) to its
# definition: filteredStream + registerStream for every stream, then
# copy_meta_from. Ordinary and malformed inputs (broadcast streams, selector-like
# names, StringName names, canonical type errors, length mismatches, a failed
# gather) must give byte-identical Data and the same logged messages.
class_name DataFilterFastPathTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const T := FlowDataScript.DataType

class CaptureLogger extends Logger:
	var messages : Array = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		messages.append("%d:%s:%s" % [error_type, code, rationale])
	func _log_message(_message: String, _error: bool) -> void:
		pass

## The definition of Data.filter (the implementation before the change).
static func _reference_filter(data : FlowData.Data, indices : PackedInt32Array) -> FlowData.Data:
	var new_data := FlowDataScript.Data.new()
	for old_stream in data.streams.values():
		var new_container = data.filteredStream(old_stream, indices)
		new_data.registerStream(old_stream.name, new_container, old_stream.data_type)
	new_data.copy_meta_from(data)
	return new_data

static func _bytes(data : FlowData.Data) -> PackedByteArray:
	var out := PackedByteArray()
	for key in data.streams:
		var stream : Dictionary = data.streams[key]
		out.append_array(var_to_bytes([type_string(typeof(key)), str(key), var_to_str(stream.keys()), type_string(typeof(stream.get("name"))), str(stream.get("name")), int(stream.get("data_type", -1))]))
		out.append_array(var_to_bytes(stream.get("container")))
	out.append_array(var_to_bytes([data.last_added_stream_name, data.tags, int(data.kind), var_to_str(data.data_attrs)]))
	return out

func _clear_gdunit_script_errors() -> void:
	var ctx = GdUnitThreadManager.get_current_context()
	if ctx == null:
		return
	var exec_ctx = ctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()

func _assert_same(data : FlowData.Data, indices : PackedInt32Array, label : String) -> void:
	var logger := CaptureLogger.new()
	OS.add_logger(logger)
	var expected := _reference_filter(data, indices)
	var expected_log : Array = logger.messages.duplicate()
	logger.messages.clear()
	var actual := data.filter(indices)
	var actual_log : Array = logger.messages.duplicate()
	OS.remove_logger(logger)
	_clear_gdunit_script_errors()
	assert_array(actual_log).override_failure_message("%s: log differs" % label).is_equal(expected_log)
	assert_bool(_bytes(actual) == _bytes(expected)).override_failure_message("%s: data differs" % label).is_true()

static func _points(n : int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(n)
	var pos := d.getVector3Container("position")
	var dens := PackedFloat32Array()
	var ids := PackedInt32Array()
	for i in range(n):
		pos[i] = Vector3(i, i * 0.5, -i)
		dens.append(float(i) / maxf(1.0, float(n)))
		ids.append(i)
	d.registerStream("density", dens, T.Float)
	d.registerStream("id", ids, T.Int)
	return d

static func _every_type(n : int) -> FlowData.Data:
	var d := _points(n)
	var b := PackedByteArray(); var s := PackedStringArray(); var c := PackedColorArray()
	var q := PackedVector4Array(); var v2 := PackedVector2Array(); var i64 := PackedInt64Array()
	var f64 := PackedFloat64Array(); var res : Array[Resource] = []; var tr = FlowDataScript.Data.newContainerOfType(T.Transform)
	for i in range(n):
		b.append(i % 2); s.append("s%d" % i); c.append(Color(i, 0, 1)); q.append(Vector4(0, 0, 0, 1))
		v2.append(Vector2(i, -i)); i64.append(i * 5000000000); f64.append(i * 0.1)
		res.append(null); tr.append(Transform3D(Basis(), Vector3(i, 0, 0)))
	d.registerStream("b", b, T.Bool); d.registerStream("s", s, T.String); d.registerStream("c", c, T.Color)
	d.registerStream("rotation_quat", q, T.Quaternion); d.registerStream("v2", v2, T.Vector2)
	d.registerStream("v4", q.duplicate(), T.Vector4); d.registerStream("i64", i64, T.Int64)
	d.registerStream("f64", f64, T.Double); d.registerStream("res", res, T.Resource)
	d.registerStream("xf", tr, T.Transform)
	d.tags = PackedStringArray(["t1"])
	d.set_data_attr("level", 2)
	return d

static func _idx(values : Array) -> PackedInt32Array:
	return PackedInt32Array(values)

func test_ordinary_data_matches_the_definition() -> void:
	var d := _every_type(10)
	_assert_same(d, _idx([0, 2, 4, 6, 8]), "every 2nd")
	_assert_same(d, _idx([9, 3, 3, 0]), "reorder and repeat")
	_assert_same(d, _idx([]), "empty selection")
	_assert_same(d, _idx(range(10)), "identity")
	_assert_same(_every_type(1), _idx([0]), "one point")
	_assert_same(_every_type(0), _idx([]), "no points")
	_assert_same(FlowDataScript.Data.new(), _idx([]), "no streams")

func test_broadcast_streams_match_the_definition() -> void:
	var d := _points(6)
	d.registerStream("one", PackedFloat32Array([3.0]), T.Float)
	_assert_same(d, _idx([1, 2, 5]), "broadcast kept")
	var first_broadcast := FlowDataScript.Data.new()
	first_broadcast.registerStream("k", PackedFloat32Array([1.0]), T.Float)
	first_broadcast.registerStream("v", PackedFloat32Array([1.0, 2.0, 3.0]), T.Float)
	_assert_same(first_broadcast, _idx([0]), "first stream of length 1")

func test_malformed_streams_match_the_definition() -> void:
	# Streams inserted directly, bypassing registerStream's checks.
	var d := _points(5)
	d.streams[&"sn"] = { "container": PackedFloat32Array([1, 2, 3, 4, 5]), "name": &"sn", "data_type": T.Float }
	d.streams["Yaw"] = { "container": PackedFloat32Array([1, 2, 3, 4, 5]), "name": "Yaw", "data_type": T.Float }
	d.streams["$Density"] = { "container": PackedFloat32Array([9, 9, 9, 9, 9]), "name": "$Density", "data_type": T.Float }
	d.streams["a.b"] = { "container": PackedFloat32Array([1, 2, 3, 4, 5]), "name": "a.b", "data_type": T.Float }
	d.streams["@data.x"] = { "container": PackedFloat32Array([1, 2, 3, 4, 5]), "name": "@data.x", "data_type": T.Float }
	d.streams["seedf"] = { "name": "seed", "data_type": T.Float, "container": PackedFloat32Array([1, 2, 3, 4, 5]) }
	d.streams["bad_type"] = { "container": PackedFloat32Array([1, 2, 3, 4, 5]), "name": "bad_type", "data_type": 77 }
	d.streams["short"] = { "container": PackedFloat32Array([1, 2]), "name": "short", "data_type": T.Float }
	d.streams["long"] = { "container": PackedFloat32Array([1, 2, 3, 4, 5, 6, 7]), "name": "long", "data_type": T.Float }
	d.streams[""] = { "container": PackedFloat32Array([1, 2, 3, 4, 5]), "name": "", "data_type": T.Float }
	_assert_same(d, _idx([0, 1]), "malformed, short selection")
	_assert_same(d, _idx([4, 3]), "malformed, out of range for short")

func test_length_mismatch_against_the_first_stream_matches_the_definition() -> void:
	var d := FlowDataScript.Data.new()
	d.streams["first"] = { "container": PackedFloat32Array([1, 2]), "name": "first", "data_type": T.Float }
	d.streams["second"] = { "container": PackedFloat32Array([1, 2, 3, 4]), "name": "second", "data_type": T.Float }
	_assert_same(d, _idx([0, 1]), "first shorter")
	var failing := FlowDataScript.Data.new()
	failing.streams["gone"] = { "container": PackedFloat32Array([1, 2, 3]), "name": "gone", "data_type": 55 }
	failing.streams["one"] = { "container": PackedFloat32Array([7]), "name": "one", "data_type": T.Float }
	failing.streams["three"] = { "container": PackedFloat32Array([1, 2, 3]), "name": "three", "data_type": T.Float }
	_assert_same(failing, _idx([0, 2]), "first gather fails")
