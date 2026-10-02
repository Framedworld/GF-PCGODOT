# copy_attribute_test.gd
class_name CopyAttributeNodeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const CopyNode = preload("res://addons/flow_nodes_editor/nodes/copy_attribute.gd")
const CopySettings = preload("res://addons/flow_nodes_editor/nodes/copy_attribute_settings.gd")

var D = FlowDataScript.DataType

func _target() -> FlowData.Data:
	return H.data({
		"position": [PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(100, 0, 0)]), D.Vector],
		"key": [PackedInt32Array([2, 7, 1]), D.Int],
	})

func _source() -> FlowData.Data:
	return H.data({
		"position": [PackedVector3Array([Vector3(9, 0, 0), Vector3(1, 0, 0), Vector3(50, 0, 0)]), D.Vector],
		"id": [PackedInt64Array([1, 2, 3]), D.Int64],
		"label": [PackedStringArray(["one", "two", "three"]), D.String],
		"big": [PackedInt64Array([1 << 40, 2, 3]), D.Int64],
	})

func _settings(mode: int, attr: String) -> Object:
	var s = CopySettings.new()
	s.mode = mode
	s.source_attribute = attr
	return s

func test_by_index_keeps_type() -> void:
	var r = H.exec(CopyNode, _settings(CopySettings.eMode.ByIndex, "big"), [_target(), _source()])
	assert_str(r.err).is_empty()
	assert_int(H.dtype(r.out, "big")).is_equal(D.Int64)
	assert_array(H.values(r.out, "big")).is_equal([1 << 40, 2, 3])

func test_by_index_broadcasts_a_single_source_entry_and_renames() -> void:
	var src = H.data({"tint": [PackedColorArray([Color.RED]), D.Color]})
	var s = _settings(CopySettings.eMode.ByIndex, "tint")
	s.target_attribute = "color"
	var r = H.exec(CopyNode, s, [_target(), src])
	assert_array(H.values(r.out, "color")).is_equal([Color.RED, Color.RED, Color.RED])

func test_by_index_count_mismatch_fails() -> void:
	var src = H.data({"x": [PackedFloat32Array([1, 2]), D.Float]})
	assert_str(H.exec(CopyNode, _settings(CopySettings.eMode.ByIndex, "x"), [_target(), src]).err).contains("ByIndex needs")

func test_by_match_attribute_with_unmatched_default() -> void:
	var s = _settings(CopySettings.eMode.ByMatchAttribute, "label")
	s.match_attribute = "id"
	s.target_match_attribute = "key"
	s.out_matched_attribute = "matched"
	var r = H.exec(CopyNode, s, [_target(), _source()])
	assert_str(r.err).is_empty()
	# Int target keys match Int64 source keys.
	assert_array(H.values(r.out, "label")).is_equal(["two", "", "one"])
	assert_array(H.values(r.out, "matched")).is_equal([1, 0, 1])

func test_unmatched_points_keep_existing_target_values() -> void:
	var t = _target()
	t.registerStream("label", PackedStringArray(["a", "b", "c"]), D.String)
	var s = _settings(CopySettings.eMode.ByMatchAttribute, "label")
	s.match_attribute = "id"
	s.target_match_attribute = "key"
	var r = H.exec(CopyNode, s, [t, _source()])
	assert_array(H.values(r.out, "label")).is_equal(["two", "b", "one"])
	# input untouched
	assert_array(H.values(t, "label")).is_equal(["a", "b", "c"])

func test_nearest_point_with_max_distance() -> void:
	var s = _settings(CopySettings.eMode.NearestPoint, "label")
	var r = H.exec(CopyNode, s, [_target(), _source()])
	assert_array(H.values(r.out, "label")).is_equal(["two", "one", "three"])
	s.max_distance = 5.0
	var r2 = H.exec(CopyNode, s, [_target(), _source()])
	assert_array(H.values(r2.out, "label")).is_equal(["two", "one", ""])

func test_copy_all_attributes_skips_point_properties() -> void:
	var s = _settings(CopySettings.eMode.ByIndex, "")
	s.copy_all_attributes = true
	var r = H.exec(CopyNode, s, [_target(), _source()])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "position")).is_equal(H.values(_target(), "position"))
	assert_array(H.values(r.out, "label")).is_equal(["one", "two", "three"])
	assert_int(H.dtype(r.out, "id")).is_equal(D.Int64)
	s.include_point_properties = true
	var r2 = H.exec(CopyNode, s, [_target(), _source()])
	assert_array(H.values(r2.out, "position")).is_equal(H.values(_source(), "position"))

func test_new_types_copy_by_match() -> void:
	var xf = FlowDataScript.Data.newContainerOfType(D.Transform)
	xf.append(Transform3D(Basis.IDENTITY, Vector3(1, 1, 1)))
	xf.append(Transform3D(Basis.IDENTITY, Vector3(2, 2, 2)))
	var src = H.data({
		"name": [PackedStringArray(["a", "b"]), D.String],
		"xf": [xf, D.Transform],
		"uv": [PackedVector2Array([Vector2(1, 0), Vector2(0, 1)]), D.Vector2],
		"w": [PackedFloat64Array([0.1, 0.2]), D.Double],
	})
	var dst = H.data({"name": [PackedStringArray(["b", "a", "z"]), D.String]})
	for attr in ["xf", "uv", "w"]:
		var s = _settings(CopySettings.eMode.ByMatchAttribute, attr)
		s.match_attribute = "name"
		var r = H.exec(CopyNode, s, [dst, src])
		assert_str(r.err).is_empty()
		assert_int(H.dtype(r.out, attr)).is_equal(H.dtype(src, attr))
		assert_bool(H.values(r.out, attr)[0] == H.values(src, attr)[1]).override_failure_message(attr).is_true()
		assert_bool(H.values(r.out, attr)[1] == H.values(src, attr)[0]).override_failure_message(attr).is_true()

func test_missing_source_fails() -> void:
	assert_str(H.exec(CopyNode, _settings(CopySettings.eMode.ByIndex, "label"), [_target()]).err).contains("Source")
	assert_str(H.exec(CopyNode, _settings(CopySettings.eMode.ByIndex, "nope"), [_target(), _source()]).err).contains("not found")
