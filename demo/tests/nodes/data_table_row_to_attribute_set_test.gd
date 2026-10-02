# data_table_row_to_attribute_set_test.gd
class_name DataTableRowToAttributeSetTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DataTableRowToAttributeSetNode = preload("res://addons/flow_nodes_editor/nodes/data_table_row_to_attribute_set.gd")
const DataTableRowToAttributeSetSettings = preload("res://addons/flow_nodes_editor/nodes/data_table_row_to_attribute_set_settings.gd")

func _make_table(names: Array, values: Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	for i in range(names.size()):
		d.registerStream(names[i], values[i][0], values[i][1])
	return d

func _run(inputs: Array, settings) -> DataTableRowToAttributeSetNode:
	var node = DataTableRowToAttributeSetNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
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

func _default_row_index_settings() -> DataTableRowToAttributeSetSettings:
	var s = DataTableRowToAttributeSetSettings.new()
	s.selection_mode = DataTableRowToAttributeSetSettings.eSelectionMode.RowIndex
	s.row_index = 0
	return s

func _default_match_settings() -> DataTableRowToAttributeSetSettings:
	var s = DataTableRowToAttributeSetSettings.new()
	s.selection_mode = DataTableRowToAttributeSetSettings.eSelectionMode.MatchAttribute
	s.key_attribute = "name"
	s.key_value = ""
	s.include_all_matches = false
	s.case_sensitive = false
	return s

func test_missing_input_error() -> void:
	var s = _default_row_index_settings()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_row_index_selects_correct_row() -> void:
	var s = _default_row_index_settings()
	s.row_index = 1

	var d := FlowDataScript.Data.new()
	d.registerStream("value", PackedFloat32Array([10.0, 20.0, 30.0]), FlowDataScript.DataType.Float)
	d.registerStream("label", PackedInt32Array([1, 2, 3]), FlowDataScript.DataType.Int)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var val_stream = out.findStream("value")
	assert_object(val_stream).is_not_null()
	assert_array(val_stream.container).is_equal(PackedFloat32Array([20.0]))

	var label_stream = out.findStream("label")
	assert_object(label_stream).is_not_null()
	assert_array(label_stream.container).is_equal(PackedInt32Array([2]))

func test_row_index_out_of_range_returns_empty() -> void:
	var s = _default_row_index_settings()
	s.row_index = 99

	var d := FlowDataScript.Data.new()
	d.registerStream("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var val_stream = out.findStream("value")
	assert_object(val_stream).is_not_null()
	assert_int(val_stream.container.size()).is_equal(0)

func test_empty_input_passthrough() -> void:
	var s = _default_row_index_settings()

	var d := FlowDataScript.Data.new()
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

func test_match_attribute_first_match_only() -> void:
	var s = _default_match_settings()
	s.key_attribute = "name"
	s.key_value = "apple"
	s.include_all_matches = false
	s.case_sensitive = false

	var d := FlowDataScript.Data.new()
	var names: Array[String] = ["banana", "apple", "cherry", "apple"]
	var packed_names := PackedStringArray(names)
	d.registerStream("name", packed_names, FlowDataScript.DataType.String)
	d.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0, 4.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var score_stream = out.findStream("score")
	assert_object(score_stream).is_not_null()
	assert_array(score_stream.container).is_equal(PackedFloat32Array([2.0]))

func test_match_attribute_include_all_matches() -> void:
	var s = _default_match_settings()
	s.key_attribute = "name"
	s.key_value = "apple"
	s.include_all_matches = true
	s.case_sensitive = false

	var d := FlowDataScript.Data.new()
	var names: Array[String] = ["banana", "apple", "cherry", "apple"]
	d.registerStream("name", PackedStringArray(names), FlowDataScript.DataType.String)
	d.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0, 4.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var score_stream = out.findStream("score")
	assert_object(score_stream).is_not_null()
	assert_array(score_stream.container).is_equal(PackedFloat32Array([2.0, 4.0]))

func test_match_attribute_case_insensitive() -> void:
	var s = _default_match_settings()
	s.key_attribute = "name"
	s.key_value = "APPLE"
	s.include_all_matches = false
	s.case_sensitive = false

	var d := FlowDataScript.Data.new()
	var names: Array[String] = ["banana", "apple", "cherry"]
	d.registerStream("name", PackedStringArray(names), FlowDataScript.DataType.String)
	d.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var score_stream = out.findStream("score")
	assert_object(score_stream).is_not_null()
	assert_array(score_stream.container).is_equal(PackedFloat32Array([2.0]))

func test_match_attribute_case_sensitive_no_match() -> void:
	var s = _default_match_settings()
	s.key_attribute = "name"
	s.key_value = "APPLE"
	s.include_all_matches = false
	s.case_sensitive = true

	var d := FlowDataScript.Data.new()
	var names: Array[String] = ["banana", "apple", "cherry"]
	d.registerStream("name", PackedStringArray(names), FlowDataScript.DataType.String)
	d.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var score_stream = out.findStream("score")
	assert_object(score_stream).is_not_null()
	assert_int(score_stream.container.size()).is_equal(0)

func test_match_attribute_key_attribute_not_found_error() -> void:
	var s = _default_match_settings()
	s.key_attribute = "nonexistent"
	s.key_value = "apple"

	var d := FlowDataScript.Data.new()
	d.registerStream("name", PackedStringArray(["apple", "banana"]), FlowDataScript.DataType.String)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_row_index_first_row() -> void:
	var s = _default_row_index_settings()
	s.row_index = 0

	var d := FlowDataScript.Data.new()
	d.registerStream("value", PackedFloat32Array([100.0, 200.0, 300.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var val_stream = out.findStream("value")
	assert_object(val_stream).is_not_null()
	assert_array(val_stream.container).is_equal(PackedFloat32Array([100.0]))

func test_match_attribute_no_matches_returns_empty() -> void:
	var s = _default_match_settings()
	s.key_attribute = "name"
	s.key_value = "mango"
	s.include_all_matches = true
	s.case_sensitive = false

	var d := FlowDataScript.Data.new()
	d.registerStream("name", PackedStringArray(["apple", "banana", "cherry"]), FlowDataScript.DataType.String)
	d.registerStream("score", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var score_stream = out.findStream("score")
	assert_object(score_stream).is_not_null()
	assert_int(score_stream.container.size()).is_equal(0)
