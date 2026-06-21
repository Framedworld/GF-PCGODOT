# load_pcg_data_asset_test.gd
class_name LoadPcgDataAssetTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const LoadPcgDataAssetNode = preload("res://addons/flow_nodes_editor/nodes/load_pcg_data_asset.gd")
const LoadPcgDataAssetSettings = preload("res://addons/flow_nodes_editor/nodes/load_pcg_data_asset_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_settings() -> LoadPcgDataAssetSettings:
	var s = LoadPcgDataAssetSettings.new()
	s.asset_path = ""
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Auto
	s.rows_property_name = "rows"
	s.streams_property_name = "streams"
	s.add_source_path = false
	s.source_path_attribute = "source_path"
	return s

func _run(settings) -> LoadPcgDataAssetNode:
	var node = LoadPcgDataAssetNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

## Write text to a temp user:// file and return the absolute filesystem path.
func _write_temp_json(filename: String, content: String) -> String:
	var user_path = "user://" + filename
	var f = FileAccess.open(user_path, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	return ProjectSettings.globalize_path(user_path)

# ---------------------------------------------------------------------------
# Error-path tests (no fixture file needed)
# ---------------------------------------------------------------------------

func test_empty_path_produces_no_error_and_empty_output() -> void:
	var s = _make_settings()
	s.asset_path = ""
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_missing_file_sets_error() -> void:
	var s = _make_settings()
	s.asset_path = "res://nonexistent_file_that_does_not_exist.json"
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_file_with_explicit_json_format_sets_error() -> void:
	var s = _make_settings()
	s.asset_path = "res://nonexistent_file.json"
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_file_with_explicit_resource_format_sets_error() -> void:
	var s = _make_settings()
	s.asset_path = "res://nonexistent_file.tres"
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Resource
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

# ---------------------------------------------------------------------------
# JSON parsing tests (write temp file to user://)
# ---------------------------------------------------------------------------

func test_json_array_of_rows_float_column() -> void:
	# JSON numbers always parse as float in Godot's JSON class
	var json := '[{"x": 1.0, "y": 2.0}, {"x": 3.0, "y": 4.0}]'
	var path = _write_temp_json("test_rows.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sx = out.findStream("x")
	var sy = out.findStream("y")
	assert_object(sx).is_not_null()
	assert_object(sy).is_not_null()
	# Two rows, two columns
	assert_int(sx.container.size()).is_equal(2)
	assert_int(sy.container.size()).is_equal(2)
	# Float containers (JSON numbers are floats)
	assert_int(sx.data_type).is_equal(FlowData.DataType.Float)
	assert_float(float(sx.container[0])).is_equal_approx(1.0, 0.001)
	assert_float(float(sx.container[1])).is_equal_approx(3.0, 0.001)
	node.free()

func test_json_array_of_rows_string_column() -> void:
	var json := '[{"name": "alpha"}, {"name": "beta"}]'
	var path = _write_temp_json("test_string_rows.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("name")
	assert_object(stream).is_not_null()
	assert_int(stream.data_type).is_equal(FlowData.DataType.String)
	assert_int(stream.container.size()).is_equal(2)
	assert_str(stream.container[0]).is_equal("alpha")
	assert_str(stream.container[1]).is_equal("beta")
	node.free()

func test_json_object_with_rows_property() -> void:
	var json := '{"rows": [{"val": 10.0}, {"val": 20.0}]}'
	var path = _write_temp_json("test_rows_prop.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	s.rows_property_name = "rows"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("val")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	node.free()

func test_json_object_with_streams_property() -> void:
	# streams format: {"streams": {"x": [1.0, 2.0, 3.0], "y": [4.0, 5.0, 6.0]}}
	var json := '{"streams": {"px": [10.0, 20.0], "py": [30.0, 40.0]}}'
	var path = _write_temp_json("test_streams_prop.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	s.streams_property_name = "streams"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sx = out.findStream("px")
	var sy = out.findStream("py")
	assert_object(sx).is_not_null()
	assert_object(sy).is_not_null()
	assert_int(sx.container.size()).is_equal(2)
	assert_int(sy.container.size()).is_equal(2)
	node.free()

func test_json_object_with_points_property() -> void:
	var json := '{"points": [{"z": 5.0}, {"z": 7.0}]}'
	var path = _write_temp_json("test_points_prop.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("z")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	node.free()

func test_json_single_object_becomes_one_row() -> void:
	# A plain dict with no known "rows"/"streams"/"points" key -> treated as one row
	var json := '{"color": "red", "weight": 1.5}'
	var path = _write_temp_json("test_single_obj.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# Should have exactly 1 row
	var color_stream = out.findStream("color")
	assert_object(color_stream).is_not_null()
	assert_int(color_stream.container.size()).is_equal(1)
	assert_str(color_stream.container[0]).is_equal("red")
	node.free()

func test_invalid_json_sets_error() -> void:
	var path = _write_temp_json("test_bad.json", "{ not valid json !!!")
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	var node = _run(s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_json_number_always_float_not_int() -> void:
	# GDScript JSON always gives floats for numbers, never int
	var json := '[{"count": 42}]'
	var path = _write_temp_json("test_numtype.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("count")
	assert_object(stream).is_not_null()
	# JSON numbers parse as float in Godot JSON (per node tooltip)
	assert_int(stream.data_type).is_equal(FlowData.DataType.Float)
	node.free()

func test_source_path_attribute_added_when_enabled() -> void:
	var json := '[{"v": 1.0}]'
	var path = _write_temp_json("test_src_path.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	s.add_source_path = true
	s.source_path_attribute = "source_path"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sp_stream = out.findStream("source_path")
	assert_object(sp_stream).is_not_null()
	assert_int(sp_stream.data_type).is_equal(FlowData.DataType.String)
	assert_int(sp_stream.container.size()).is_equal(1)
	# The recorded path is the filesystem path we passed in
	assert_str(sp_stream.container[0]).is_equal(path)
	node.free()

func test_source_path_attribute_absent_when_disabled() -> void:
	var json := '[{"v": 1.0}]'
	var path = _write_temp_json("test_no_src_path.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Json
	s.add_source_path = false
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("source_path")).is_false()
	node.free()

func test_auto_format_detects_json_by_extension() -> void:
	var json := '[{"n": 1.0}]'
	var path = _write_temp_json("test_auto_detect.json", json)
	var s = _make_settings()
	s.asset_path = path
	s.asset_format = LoadPcgDataAssetSettings.eAssetFormat.Auto
	var node = _run(s)
	# Auto should detect .json and parse successfully
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream("n")).is_true()
	node.free()

# ---------------------------------------------------------------------------
# Pure helper method tests (no file I/O, direct calls on node instance)
# ---------------------------------------------------------------------------

func test_as_vector3_from_vector3() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._as_vector3(Vector3(1.0, 2.0, 3.0))
	assert_bool(result.ok).is_true()
	assert_bool(result.value.is_equal_approx(Vector3(1.0, 2.0, 3.0))).is_true()
	node.free()

func test_as_vector3_from_array() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._as_vector3([1.0, 2.0, 3.0])
	assert_bool(result.ok).is_true()
	assert_bool(result.value.is_equal_approx(Vector3(1.0, 2.0, 3.0))).is_true()
	node.free()

func test_as_vector3_from_dict() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._as_vector3({"x": 4.0, "y": 5.0, "z": 6.0})
	assert_bool(result.ok).is_true()
	assert_bool(result.value.is_equal_approx(Vector3(4.0, 5.0, 6.0))).is_true()
	node.free()

func test_as_vector3_from_string_space_separated() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._as_vector3("1.0 2.0 3.0")
	assert_bool(result.ok).is_true()
	assert_bool(result.value.is_equal_approx(Vector3(1.0, 2.0, 3.0))).is_true()
	node.free()

func test_as_vector3_from_string_parentheses() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._as_vector3("(1.0, 2.0, 3.0)")
	assert_bool(result.ok).is_true()
	assert_bool(result.value.is_equal_approx(Vector3(1.0, 2.0, 3.0))).is_true()
	node.free()

func test_as_vector3_from_invalid_returns_not_ok() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._as_vector3("not_a_vector")
	assert_bool(result.ok).is_false()
	node.free()

func test_as_vector3_from_short_array_returns_not_ok() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._as_vector3([1.0, 2.0])
	assert_bool(result.ok).is_false()
	node.free()

func test_infer_variant_type_bools() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._infer_variant_type([true, false, true])
	assert_int(result).is_equal(FlowData.DataType.Bool)
	node.free()

func test_infer_variant_type_ints() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._infer_variant_type([1, 2, 3])
	assert_int(result).is_equal(FlowData.DataType.Int)
	node.free()

func test_infer_variant_type_floats() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._infer_variant_type([1.0, 2.5, 3.7])
	assert_int(result).is_equal(FlowData.DataType.Float)
	node.free()

func test_infer_variant_type_vectors() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._infer_variant_type([Vector3(1, 0, 0), Vector3(0, 1, 0)])
	assert_int(result).is_equal(FlowData.DataType.Vector)
	node.free()

func test_infer_variant_type_strings() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var result = node._infer_variant_type(["hello", "world"])
	assert_int(result).is_equal(FlowData.DataType.String)
	node.free()

func test_infer_variant_type_mixed_becomes_string() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	# Int and string mixed -> not bool, int, float, or vector -> String
	var result = node._infer_variant_type([1, "hello"])
	assert_int(result).is_equal(FlowData.DataType.String)
	node.free()

func test_rows_to_data_column_count() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	# Inject settings so _rows_to_data can read add_source_path
	var s = _make_settings()
	s.add_source_path = false
	node.settings = s
	var rows = [
		{"a": 1.0, "b": 2.0},
		{"a": 3.0, "b": 4.0},
		{"a": 5.0, "b": 6.0},
	]
	var out = node._rows_to_data(rows, "test_source")
	assert_object(out).is_not_null()
	assert_int(out.numFields()).is_equal(2)
	var sa = out.findStream("a")
	var sb = out.findStream("b")
	assert_object(sa).is_not_null()
	assert_object(sb).is_not_null()
	assert_int(sa.container.size()).is_equal(3)
	assert_int(sb.container.size()).is_equal(3)
	node.free()

func test_rows_to_data_missing_key_fills_null() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var s = _make_settings()
	s.add_source_path = false
	node.settings = s
	# Row 0 has "a", row 1 does not -> row 1 gets default 0.0 for float
	var rows = [
		{"a": 5.0},
		{},
	]
	var out = node._rows_to_data(rows, "test_source")
	var sa = out.findStream("a")
	assert_object(sa).is_not_null()
	assert_int(sa.container.size()).is_equal(2)
	assert_float(float(sa.container[1])).is_equal_approx(0.0, 0.001)
	node.free()

func test_streams_to_data_aligns_columns() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var s = _make_settings()
	s.add_source_path = false
	node.settings = s
	var streams = {
		"x": [1.0, 2.0, 3.0],
		"y": [4.0, 5.0, 6.0],
	}
	var out = node._streams_to_data(streams, "test_source")
	assert_object(out).is_not_null()
	var sx = out.findStream("x")
	var sy = out.findStream("y")
	assert_object(sx).is_not_null()
	assert_object(sy).is_not_null()
	assert_int(sx.container.size()).is_equal(3)
	assert_int(sy.container.size()).is_equal(3)
	node.free()

func test_streams_to_data_source_path_when_enabled() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var s = _make_settings()
	s.add_source_path = true
	s.source_path_attribute = "src"
	node.settings = s
	var streams = {"v": [9.0, 8.0]}
	var out = node._streams_to_data(streams, "my_source.json")
	var sp = out.findStream("src")
	assert_object(sp).is_not_null()
	assert_int(sp.container.size()).is_equal(2)
	assert_str(sp.container[0]).is_equal("my_source.json")
	node.free()

func test_streams_to_data_skips_non_array_entries() -> void:
	var node = LoadPcgDataAssetNode.new()
	node.name = "helper_test"
	var s = _make_settings()
	s.add_source_path = false
	node.settings = s
	# "meta" is not an Array — should be ignored
	var streams = {"v": [1.0, 2.0], "meta": "not_an_array"}
	var out = node._streams_to_data(streams, "")
	assert_bool(out.hasStream("v")).is_true()
	assert_bool(out.hasStream("meta")).is_false()
	node.free()
