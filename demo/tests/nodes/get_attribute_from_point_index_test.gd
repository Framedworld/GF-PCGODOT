# get_attribute_from_point_index_test.gd
class_name GetAttributeFromPointIndexTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/get_attribute_from_point_index.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/get_attribute_from_point_index_settings.gd")

func _settings(attr : String, index : int = 0, out_name : String = ""):
	var s = SettingsScript.new()
	s.input_attribute = attr
	s.index = index
	s.output_attribute = out_name
	return s

func _data() -> FlowData.Data:
	return H.points([Vector3(0, 1, 0), Vector3(5, 2, 0), Vector3(9, 3, 0)], {
		"height": PackedFloat32Array([10.0, 20.0, 30.0]),
		"label": PackedStringArray(["a", "b", "c"]),
		"flag": PackedByteArray([0, 1, 0]),
	})

func _exec(data, settings) -> Dictionary:
	return H.exec(NodeScript, settings, [data])

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Get Attribute From Point Index"])
	assert_int(node.meta_node.outs.size()).is_equal(3)
	H.dispose(node)

func test_reads_value_into_attribute_set_point_and_data_attr() -> void:
	var r := _exec(_data(), _settings("height", 1, "picked"))
	assert_str(r.err).is_empty()
	var aset = H.port(r, 0)
	assert_int(aset.size()).is_equal(1)
	assert_float(aset.first("picked")).is_equal(20.0)
	assert_int(aset.kind).is_equal(FlowDataScript.Kind.AttrSet)
	var point = H.port(r, 1)
	assert_int(point.size()).is_equal(1)
	assert_str(point.first("label")).is_equal("b")
	var out = H.port(r, 2)
	assert_int(out.size()).is_equal(3)
	assert_float(out.get_data_attr("picked")).is_equal(20.0)
	assert_float(out.value_at("@data.picked", 2)).is_equal(20.0)

func test_negative_index_and_derived_names() -> void:
	var r := _exec(_data(), _settings("position.y", -1))
	assert_str(r.err).is_empty()
	assert_float(H.port(r, 0).first("position_y")).is_equal(3.0)
	var last := _exec(_data(), _settings("@last", 0))
	assert_bool(H.port(last, 0).first("flag")).is_false()
	var flag := _exec(_data(), _settings("flag", 1))
	assert_bool(H.port(flag, 0).first("flag")).is_true()
	assert_bool(H.port(flag, 2).get_data_attr("flag")).is_true()

func test_types_are_kept() -> void:
	var r := _exec(_data(), _settings("label", 2))
	var aset = H.port(r, 0)
	assert_int(aset.streams["label"].data_type).is_equal(FlowDataScript.DataType.String)
	assert_str(aset.first("label")).is_equal("c")
	var v := _exec(_data(), _settings("position", 1, "where"))
	assert_vector(H.port(v, 0).first("where")).is_equal(Vector3(5, 2, 0))

func test_broadcast_stream_and_data_attribute_source() -> void:
	var d = _data()
	d.registerStream("bc", PackedFloat32Array([7.5]))
	assert_float(H.port(_exec(d, _settings("bc", 2)), 0).first("bc")).is_equal(7.5)
	var a = FlowDataScript.Data.new()
	a.set_data_attr("level", 4)
	var r := _exec(a, _settings("@data.level", 0))
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 0).first("level")).is_equal(4)

func test_index_out_of_range_is_an_error() -> void:
	var r := _exec(_data(), _settings("height", 3))
	assert_str(r.err).contains("out of range")
	assert_int(H.port(r, 0).size()).is_equal(0)
	assert_int(H.port(r, 2).size()).is_equal(3)
	assert_str(_exec(_data(), _settings("height", -4)).err).contains("out of range")

func test_empty_input_is_out_of_range() -> void:
	var r := _exec(H.points([], {"height": PackedFloat32Array()}), _settings("height", 0))
	assert_str(r.err).contains("out of range")
	assert_int(H.port(r, 1).size()).is_equal(0)

func test_missing_attribute_and_input() -> void:
	assert_str(_exec(_data(), _settings("nope")).err).contains("not found")
	assert_str(_exec(_data(), _settings("")).err).contains("empty")
	assert_str(_exec(null, _settings("height")).err).contains("not connected")

func test_canonical_output_type_is_refused() -> void:
	var r := _exec(_data(), _settings("label", 0, "density"))
	assert_str(r.err).contains("canonical")
