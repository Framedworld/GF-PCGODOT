# filter_typed_loop_test.gd
# Pins the filter node after the WP13-P1 performance rewrite (numeric streams
# converted to doubles, one typed loop per condition) to the original
# implementation kept verbatim in support/filter_reference.gd: every condition,
# every numeric type pair, constants, broadcast B, NaN, Int64 and malformed
# streams must give byte-identical outputs and the same logged messages.
class_name FilterTypedLoopTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/filter.gd")
const ReferenceScript = preload("res://tests/nodes/support/filter_reference.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/filter_settings.gd")

const T := FlowDataScript.DataType

static func _streams(n : int) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var d := FlowDataScript.Data.new()
	var f := PackedFloat32Array(); var g := PackedFloat32Array(); var i32 := PackedInt32Array()
	var j32 := PackedInt32Array(); var b := PackedByteArray(); var dbl := PackedFloat64Array()
	var i64 := PackedInt64Array(); var v := PackedVector3Array()
	var specials := [0.0, 1.0, -1.0, 0.5, 0.5, NAN, INF, -INF, 0.05, -0.0]
	for k in range(n):
		var x : float = specials[k] if k < specials.size() else snappedf(rng.randf_range(-3.0, 3.0), 0.25)
		f.append(x)
		g.append(specials[(k + 3) % specials.size()] if k < specials.size() else snappedf(rng.randf_range(-3.0, 3.0), 0.25))
		i32.append(int(x) if is_finite(x) else 7)
		j32.append(rng.randi_range(-2, 2))
		b.append(k % 3 == 0)
		dbl.append(x * 1.0e-9 if is_finite(x) else x)
		i64.append((1 << 53) + k if k % 2 == 0 else (1 << 53) + k + 1)
		v.append(Vector3(x, 0, 0))
	d.registerStream("f", f, T.Float)
	d.registerStream("g", g, T.Float)
	d.registerStream("i", i32, T.Int)
	d.registerStream("j", j32, T.Int)
	d.registerStream("b", b, T.Bool)
	d.registerStream("d", dbl, T.Double)
	d.registerStream("l", i64, T.Int64)
	d.registerStream("m", i64.duplicate(), T.Int64)
	d.registerStream("v", v, T.Vector)
	return d

static func _settings(a : String, condition : int, b : String, threshold := 0.1):
	var s = SettingsScript.new()
	s.in_nameA = a
	s.condition = condition
	s.in_nameB = b
	s.threshold = threshold
	return s

func _clear_gdunit_script_errors() -> void:
	var ctx = GdUnitThreadManager.get_current_context()
	if ctx == null:
		return
	var exec_ctx = ctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()

func _assert_same(a : String, condition : int, b : String, inputs : Array, threshold := 0.1) -> void:
	var expected := R.exec_logged(ReferenceScript, _settings(a, condition, b, threshold), inputs)
	var actual := R.exec_logged(NodeScript, _settings(a, condition, b, threshold), inputs)
	_clear_gdunit_script_errors()
	assert_array(actual).override_failure_message("%s %d %s differs from the reference" % [a, condition, b]).is_equal(expected)

func test_every_condition_and_type_pair_matches_the_reference() -> void:
	var d := _streams(40)
	var names := ["f", "g", "i", "j", "b", "d", "l", "m"]
	var checked := 0
	for condition in range(0, 10):
		for a in names:
			for b in names:
				_assert_same(a, condition, b, [d, d])
				checked += 1
	assert_int(checked).is_equal(10 * 8 * 8)

func test_constants_and_threshold_match_the_reference() -> void:
	var d := _streams(30)
	for condition in range(0, 11):
		for b in ["0.5", "-1", "true", "false", "nope"]:
			_assert_same("f", condition, b, [d])
			_assert_same("i", condition, b, [d])
		_assert_same("f", condition, "0", [d], 0.6)
	_assert_same("f", 99, "g", [d, d])
	_assert_same("f", -1, "g", [d, d])

func test_broadcast_and_mismatched_inputs_match_the_reference() -> void:
	var d := _streams(12)
	var one := FlowDataScript.Data.new()
	one.registerStream("k", PackedFloat32Array([0.5]), T.Float)
	var one_d := FlowDataScript.Data.new()
	one_d.registerStream("k", PackedFloat64Array([0.5]), T.Double)
	var three := _streams(3)
	for condition in [0, 2, 5, 6, 7]:
		_assert_same("f", condition, "k", [d, one])
		_assert_same("i", condition, "k", [d, one_d])
		_assert_same("f", condition, "g", [d, three])
	_assert_same("v", 0, "f", [d, d])
	_assert_same("missing", 0, "f", [d, d])

func test_malformed_streams_match_the_reference() -> void:
	var d := _streams(6)
	d.streams["short"] = { "name": "short", "data_type": T.Float, "container": PackedFloat32Array([1.0, 2.0]) }
	d.streams["wrong"] = { "name": "wrong", "data_type": T.Float, "container": PackedFloat64Array([1, 2, 3, 4, 5, 6]) }
	d.streams["wrong_i"] = { "name": "wrong_i", "data_type": T.Int, "container": PackedFloat32Array([1, 2, 3, 4, 5, 6]) }
	for name in ["short", "wrong", "wrong_i"]:
		_assert_same(name, 2, "f", [d, d])
		_assert_same("f", 2, name, [d, d])
