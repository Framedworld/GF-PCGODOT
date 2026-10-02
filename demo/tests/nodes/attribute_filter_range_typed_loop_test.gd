# attribute_filter_range_typed_loop_test.gd
# Pins the numeric range mode of attribute_filter_range (and density_filter,
# which composes it) to the original per-point implementation after the
# typed-loop rewrite (docs/_round2/WP13-P1.md): every stream type, broadcast
# streams, both inclusive flags, absolute value, boundary values, NaN and
# non-parseable strings must split exactly as the reference below does.
class_name AttributeFilterRangeTypedLoopTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/attribute_filter_range.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/attribute_filter_range_settings.gd")
const DensityNodeScript = preload("res://addons/flow_nodes_editor/nodes/density_filter.gd")
const DensitySettingsScript = preload("res://addons/flow_nodes_editor/nodes/density_filter_settings.gd")

const T := FlowDataScript.DataType

# --- reference: the per-point implementation before the rewrite ------------------------

static func _ref_value(stream : Dictionary, index : int) -> Array:
	var size = stream.container.size()
	if size <= 0:
		return [false, 0.0]
	var read_idx = FlowDataScript.bcast_idx(size, index)
	match stream.data_type:
		T.Float, T.Int:
			return [true, float(stream.container[read_idx])]
		T.Bool:
			return [true, 1.0 if stream.container[read_idx] != 0 else 0.0]
		T.Vector:
			var v : Vector3 = stream.container[read_idx]
			return [true, v.length()]
		T.Color:
			var c : Color = stream.container[read_idx]
			return [true, (c.r + c.g + c.b) / 3.0]
		T.String:
			var s = String(stream.container[read_idx]).strip_edges()
			if s.is_valid_float():
				return [true, s.to_float()]
	return [false, 0.0]

static func _ref_split(stream : Dictionary, n : int, s) -> Array:
	var range_min = minf(s.min_value, s.max_value)
	var range_max = maxf(s.min_value, s.max_value)
	var inside := PackedInt32Array()
	var outside := PackedInt32Array()
	for i in range(n):
		var converted = _ref_value(stream, i)
		if not converted[0]:
			outside.append(i)
			continue
		var value = float(converted[1])
		if s.use_absolute_value:
			value = absf(value)
		var min_ok = value >= range_min if s.inclusive_min else value > range_min
		var ok = min_ok and (value <= range_max if s.inclusive_max else value < range_max)
		if ok:
			inside.append(i)
		else:
			outside.append(i)
	return [inside, outside]

# --- inputs ---------------------------------------------------------------------------

## Point data with an "id" stream (the original index) and stream "v".
static func _data(container, data_type : int, n : int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	var ids := PackedInt32Array()
	ids.resize(n)
	for i in range(n):
		ids[i] = i
	d.registerStream("id", ids, T.Int)
	d.registerStream("v", container, data_type)
	return d

static func _containers(n : int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var f := PackedFloat32Array()
	var i32 := PackedInt32Array()
	var b := PackedByteArray()
	var v3 := PackedVector3Array()
	var col := PackedColorArray()
	var str := PackedStringArray()
	# Boundary and special values first, then random ones.
	var specials := [0.0, 5.0, -5.0, 2.0, -2.0, 4.999999, 5.000001, NAN, INF, -INF]
	for k in range(n):
		var x : float = specials[k] if k < specials.size() else rng.randf_range(-8.0, 8.0)
		f.append(x)
		i32.append(int(round(x)) if is_finite(x) else 0)
		b.append(1 if x > 0.0 else 0)
		v3.append(Vector3(x, rng.randf_range(-3.0, 3.0), x * 0.5) if k >= 3 else Vector3(x, 0, 0))
		col.append(Color(x, absf(x) * 0.3, 1.0 - x, 0.5))
		str.append(" %f " % x if k % 7 != 3 else "not a number")
	return [[f, T.Float], [i32, T.Int], [b, T.Bool], [v3, T.Vector], [col, T.Color], [str, T.String]]

static func _ids(data) -> PackedInt32Array:
	if data == null or not data.hasStream("id"):
		return PackedInt32Array()
	return data.streams["id"].container

static func _settings(inc_min : bool, inc_max : bool, use_abs : bool, lo : float, hi : float):
	var s = SettingsScript.new()
	s.attribute_name = "v"
	s.min_value = lo
	s.max_value = hi
	s.inclusive_min = inc_min
	s.inclusive_max = inc_max
	s.use_absolute_value = use_abs
	return s

# --- tests ----------------------------------------------------------------------------

func test_every_type_and_flag_combination_matches_the_reference() -> void:
	var n := 64
	var checked := 0
	for pair in _containers(n):
		for flags in range(8):
			for bounds in [[-2.0, 5.0], [5.0, -2.0], [0.0, 0.0]]:
				var s = _settings(flags & 1 != 0, flags & 2 != 0, flags & 4 != 0, bounds[0], bounds[1])
				var data := _data(pair[0], pair[1], n)
				var expected := _ref_split(data.streams["v"], n, s)
				var r := H.exec(NodeScript, s, [data])
				assert_str(r.err).is_empty()
				assert_array(Array(_ids(H.port(r, 0)))).is_equal(Array(expected[0]))
				assert_array(Array(_ids(H.port(r, 1)))).is_equal(Array(expected[1]))
				checked += 1
	assert_int(checked).is_equal(6 * 8 * 3)

func test_broadcast_stream_matches_the_reference() -> void:
	var n := 5
	for pair in _containers(12):
		var one = pair[0].slice(1, 2)  # a single element: 5.0 or its coercion
		for flags in range(4):
			var s = _settings(flags & 1 != 0, flags & 2 != 0, false, 0.0, 5.0)
			var data := _data(one, pair[1], n)
			# The id stream sets the point count; "v" is a length-1 broadcast.
			var expected := _ref_split(data.streams["v"], n, s)
			var r := H.exec(NodeScript, s, [data])
			assert_str(r.err).is_empty()
			assert_array(Array(_ids(H.port(r, 0)))).is_equal(Array(expected[0]))
			assert_array(Array(_ids(H.port(r, 1)))).is_equal(Array(expected[1]))

func test_density_filter_matches_the_reference_and_invert() -> void:
	var n := 40
	var f : PackedFloat32Array = _containers(n)[0][0]
	for invert in [false, true]:
		var s = DensitySettingsScript.new()
		s.lower_bound = 0.0
		s.upper_bound = 5.0
		s.invert_filter = invert
		var data := FlowDataScript.Data.new()
		var ids := PackedInt32Array()
		for i in range(n):
			ids.append(i)
		data.registerStream("id", ids, T.Int)
		data.registerStream(FlowDataScript.AttrDensity, f, T.Float)
		var ref_settings = _settings(true, true, false, 0.0, 5.0)
		var expected := _ref_split(data.streams[FlowDataScript.AttrDensity], n, ref_settings)
		var r := H.exec(DensityNodeScript, s, [data])
		assert_str(r.err).is_empty()
		var first : Array = Array(expected[1]) if invert else Array(expected[0])
		var second : Array = Array(expected[0]) if invert else Array(expected[1])
		assert_array(Array(_ids(H.port(r, 0)))).is_equal(first)
		assert_array(Array(_ids(H.port(r, 1)))).is_equal(second)
