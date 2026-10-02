# point_offsets_hoisted_test.gd
# Pins point_offsets after the WP13-P1 performance change (per-offset values
# and settings resolved once, rotation helpers inlined, stream copy reading
# each anchor value once) to the original implementation kept verbatim in
# support/point_offsets_reference.gd: every flag combination, short
# rotation/size/label lists, quaternion anchors, broadcast and malformed
# streams must give byte-identical outputs and the same logged messages.
class_name PointOffsetsHoistedTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/point_offsets.gd")
const ReferenceScript = preload("res://tests/nodes/support/point_offsets_reference.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/point_offsets_settings.gd")

const T := FlowDataScript.DataType

static func _anchors(n : int, quats : bool) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var positions := []
	for i in range(n):
		positions.append(Vector3(rng.randf_range(-9, 9), rng.randf_range(0, 2), rng.randf_range(-9, 9)))
	var d = H.points(positions)
	var rot : PackedVector3Array = d.getVector3Container("rotation")
	var siz : PackedVector3Array = d.getVector3Container("size")
	var names := PackedStringArray()
	for i in range(n):
		rot[i] = Vector3(rng.randf_range(-30, 30), rng.randf_range(-180, 180), rng.randf_range(-30, 30))
		siz[i] = Vector3(rng.randf_range(0.5, 2), rng.randf_range(0.5, 2), rng.randf_range(0.5, 2))
		names.append("a%d" % i)
	d.registerStream("name", names, T.String)
	d.registerStream("one", PackedFloat32Array([2.5]), T.Float)
	d.tags = PackedStringArray(["anchors"])
	if quats:
		var q := PackedVector4Array()
		for i in range(n):
			var qq := Quaternion(Vector3(0.3, 1, 0.1).normalized(), rng.randf_range(-3, 3))
			q.append(Vector4(qq.x, qq.y, qq.z, qq.w))
		d.registerStream("rotation_quat", q, T.Quaternion)
	return d

static func _vecs(values : Array) -> Array[Vector3]:
	var out : Array[Vector3] = []
	for v in values:
		out.append(v)
	return out

static func _settings(flags : int, short_lists : bool):
	var s = SettingsScript.new()
	s.offsets = _vecs([Vector3(1, 0, 0), Vector3(-1, 0.5, 0), Vector3(0, 0, 2), Vector3(0.25, -1, -1)])
	s.rotations = _vecs([Vector3(0, 45, 0)] if short_lists else [Vector3(0, 45, 0), Vector3(10, 0, 0), Vector3(0, 0, -30), Vector3(5, 90, 5)])
	s.sizes = _vecs([] if short_lists else [Vector3.ONE, Vector3(2, 1, 1), Vector3(0.5, 0.5, 0.5), Vector3(1, 3, 1)])
	s.labels.clear()
	for label in (["a", "b"] if short_lists else ["n", "e", "s", "w"]):
		s.labels.append(label)
	s.local_space = flags & 1 != 0
	s.combine_rotation = flags & 2 != 0
	s.scale_offsets_by_anchor_size = flags & 4 != 0
	s.inherit_anchor_size = flags & 8 != 0
	if flags & 16 != 0:
		s.parent_index_attribute = ""
		s.label_attribute = " "
	return s

func test_every_flag_combination_matches_the_reference() -> void:
	var checked := 0
	for quats in [false, true]:
		var input := _anchors(13, quats)
		for flags in range(32):
			for short_lists in [false, true]:
				var expected := R.exec_logged(ReferenceScript, _settings(flags, short_lists), [input])
				var actual := R.exec_logged(NodeScript, _settings(flags, short_lists), [input])
				assert_array(actual).override_failure_message("quats=%s flags=%d short=%s differs" % [quats, flags, short_lists]).is_equal(expected)
				checked += 1
	assert_int(checked).is_equal(2 * 32 * 2)

func test_degenerate_inputs_match_the_reference() -> void:
	var one := _anchors(1, false)
	var bad := _anchors(4, false)
	bad.streams["short"] = { "container": PackedFloat32Array([1, 2]), "name": "short", "data_type": T.Float }
	var no_rot := FlowDataScript.Data.new()
	no_rot.registerStream("position", PackedVector3Array([Vector3.ONE]), T.Vector)
	var empty_offsets = _settings(3, false)
	empty_offsets.offsets = _vecs([])
	for input in [one, bad, no_rot, FlowDataScript.Data.new()]:
		assert_array(R.exec_logged(NodeScript, _settings(3, false), [input])).is_equal(R.exec_logged(ReferenceScript, _settings(3, false), [input]))
	assert_array(R.exec_logged(NodeScript, empty_offsets, [one])).is_equal(R.exec_logged(ReferenceScript, empty_offsets, [one]))
