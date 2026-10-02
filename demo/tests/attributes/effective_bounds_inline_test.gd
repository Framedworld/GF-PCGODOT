# effective_bounds_inline_test.gd
# Pins FlowData.Data.getEffectiveBounds after the WP13-P1 change that inlined
# FlowData.bcast_idx in its loops: per-point, broadcast and mixed bounds
# streams, the size fallback (per point, broadcast, missing) and malformed
# lengths must give the same result and the same logged messages as the
# previous body, kept below.
class_name EffectiveBoundsInlineTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")

const T := FlowDataScript.DataType

static func _reference(d : FlowData.Data) -> Dictionary:
	var n := d.size()
	var out_min := PackedVector3Array()
	var out_max := PackedVector3Array()
	out_min.resize( n )
	out_max.resize( n )
	var has_bounds : bool = d.streams.has( FlowDataScript.AttrBoundsMin ) and d.streams.has( FlowDataScript.AttrBoundsMax )
	if has_bounds:
		var bmin : PackedVector3Array = d.getVector3Container( FlowDataScript.AttrBoundsMin )
		var bmax : PackedVector3Array = d.getVector3Container( FlowDataScript.AttrBoundsMax )
		if bmin.size() >= 1 and bmax.size() >= 1:
			for i in range( n ):
				out_min[i] = bmin[ FlowDataScript.bcast_idx( bmin.size(), i ) ]
				out_max[i] = bmax[ FlowDataScript.bcast_idx( bmax.size(), i ) ]
			return { "min": out_min, "max": out_max }
	var sizes : PackedVector3Array = d.getVector3Container( FlowDataScript.AttrSize )
	var half := Vector3( 0.5, 0.5, 0.5 )
	for i in range( n ):
		var s : Vector3 = Vector3.ONE
		if sizes.size() >= 1:
			s = sizes[ FlowDataScript.bcast_idx( sizes.size(), i ) ]
		var h : Vector3 = s * half
		out_min[i] = -h
		out_max[i] = h
	return { "min": out_min, "max": out_max }

static func _data(n : int, bmin_count : int, bmax_count : int, size_count : int) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 100 + bmin_count * 10 + bmax_count + size_count
	var d := FlowDataScript.Data.new()
	var pos := PackedVector3Array()
	for i in range(n):
		pos.append(Vector3(i, 0, 0))
	d.streams["position"] = { "container": pos, "name": "position", "data_type": T.Vector }
	for spec in [["size", size_count], ["bounds_min", bmin_count], ["bounds_max", bmax_count]]:
		if spec[1] < 0:
			continue
		var c := PackedVector3Array()
		for i in range(spec[1]):
			c.append(Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
		d.streams[spec[0]] = { "container": c, "name": spec[0], "data_type": T.Vector }
	return d

func _logged(fn : Callable) -> Array:
	var logger := R.CaptureLogger.new()
	OS.add_logger(logger)
	var result = fn.call()
	OS.remove_logger(logger)
	R.clear_gdunit_script_errors()
	return [var_to_bytes(result), logger.messages]

func test_every_stream_layout_matches_the_previous_body() -> void:
	var checked := 0
	for n in [0, 1, 5]:
		for bmin_count in [-1, 0, 1, n, 3]:
			for bmax_count in [-1, 0, 1, n, 3]:
				for size_count in [-1, 0, 1, n, 2]:
					var d := _data(n, bmin_count, bmax_count, size_count)
					var expected := _logged(func(): return _reference(d))
					var actual := _logged(func(): return d.getEffectiveBounds())
					assert_array(actual).override_failure_message("n=%d bmin=%d bmax=%d size=%d differs" % [n, bmin_count, bmax_count, size_count]).is_equal(expected)
					checked += 1
	assert_int(checked).is_equal(3 * 5 * 5 * 5)
