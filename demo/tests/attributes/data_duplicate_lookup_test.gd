# data_duplicate_lookup_test.gd
# Pins FlowData.Data.duplicate after the WP13-P1 change (one lookup per
# stream) to its definition: every stream dictionary duplicated with the same
# keys in the same order, its container duplicated (independent of the
# source), then last_added_stream_name and copy_meta_from.
class_name DataDuplicateLookupTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const T := FlowDataScript.DataType

static func _reference_duplicate(src : FlowData.Data) -> FlowData.Data:
	var s := FlowDataScript.Data.new()
	for name in src.streams:
		s.streams[name] = src.streams[name].duplicate()
		s.streams[name]["container"] = src.streams[name]["container"].duplicate()
	s.last_added_stream_name = src.last_added_stream_name
	s.copy_meta_from(src)
	return s

static func _bytes(data : FlowData.Data) -> PackedByteArray:
	var out := PackedByteArray()
	for key in data.streams:
		var stream : Dictionary = data.streams[key]
		out.append_array(var_to_bytes([type_string(typeof(key)), str(key), var_to_str(stream.keys())]))
		for k in stream:
			out.append_array(var_to_bytes(var_to_str(stream[k])))
	out.append_array(var_to_bytes([data.last_added_stream_name, data.tags, int(data.kind), var_to_str(data.data_attrs), data.shape]))
	return out

static func _sample() -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(4)
	d.registerStream("density", PackedFloat32Array([0.1, 0.2, 0.3, 0.4]), T.Float)
	d.registerStream("names", PackedStringArray(["a", "b", "c", "d"]), T.String)
	var xf = FlowDataScript.Data.newContainerOfType(T.Transform)
	for i in range(4):
		xf.append(Transform3D(Basis(), Vector3(i, 0, 0)))
	d.registerStream("xf", xf, T.Transform)
	d.registerStream("one", PackedInt32Array([7]), T.Int)
	d.streams[&"sn"] = { "data_type": T.Float, "container": PackedFloat32Array([1, 2, 3, 4]), "name": &"sn", "extra": [1, 2] }
	d.tags = PackedStringArray(["t"])
	d.set_data_attr("level", 4)
	d.kind = FlowDataScript.Kind.AttrSet
	return d

func test_duplicate_matches_the_definition() -> void:
	for d in [_sample(), FlowDataScript.Data.new()]:
		var expected := _reference_duplicate(d)
		var actual : FlowData.Data = d.duplicate()
		assert_bool(_bytes(actual) == _bytes(expected)).is_true()

func test_duplicate_is_independent_of_the_source() -> void:
	var d := _sample()
	var copy : FlowData.Data = d.duplicate()
	var dens : PackedFloat32Array = copy.streams["density"].container
	dens[0] = 9.0
	copy.streams["xf"].container[1] = Transform3D()
	copy.streams["density"]["name"] = "renamed"
	assert_float(d.streams["density"].container[0]).is_equal_approx(0.1, 1e-6)
	assert_vector(d.streams["xf"].container[1].origin).is_equal(Vector3(1, 0, 0))
	assert_str(str(d.streams["density"].name)).is_equal("density")
	assert_bool(copy.streams["sn"]["extra"] == d.streams["sn"]["extra"]).is_true()
