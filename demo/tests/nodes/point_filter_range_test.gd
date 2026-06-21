# point_filter_range_test.gd
class_name PointFilterRangeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointFilterRangeNode = preload("res://addons/flow_nodes_editor/nodes/point_filter_range.gd")
const PointFilterRangeSettings = preload("res://addons/flow_nodes_editor/nodes/point_filter_range_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> PointFilterRangeNode:
	var node = PointFilterRangeNode.new()
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

func _output(node, port: int = 0) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	if port >= bulk.size(): return null
	return bulk[port]

func test_default_attribute_name_is_position_x() -> void:
	var s = PointFilterRangeSettings.new()
	assert_str(s.attribute_name).is_equal("position.X")
	# PointFilterRangeSettings is RefCounted — do NOT call .free()

func test_position_x_range_splits_inside_outside() -> void:
	var s = PointFilterRangeSettings.new()
	s.min_value = 0.0
	s.max_value = 5.0
	s.inclusive_min = true
	s.inclusive_max = true
	# Register a "position" Vector3 stream — the default attribute "position.X"
	# is split by findStream() into stream="position", component=X.
	var positions = PackedVector3Array([
		Vector3(1, 0, 0), Vector3(3, 0, 0), Vector3(5, 0, 0),
		Vector3(7, 0, 0), Vector3(10, 0, 0)
	])
	var d = _make_data("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	var inside_pos = inside.findStream("position")
	var outside_pos = outside.findStream("position")
	assert_object(inside_pos).is_not_null()
	assert_object(outside_pos).is_not_null()
	assert_int(inside_pos.container.size()).is_equal(3)
	assert_int(outside_pos.container.size()).is_equal(2)
	node.free()

func test_exclusive_boundaries_on_position_x() -> void:
	var s = PointFilterRangeSettings.new()
	s.min_value = 0.0
	s.max_value = 5.0
	s.inclusive_min = false
	s.inclusive_max = false
	# Register "position" Vector3 — default attribute "position.X" splits on "." → reads X component
	var positions = PackedVector3Array([Vector3(0.0, 0, 0), Vector3(2.5, 0, 0), Vector3(5.0, 0, 0)])
	var d = _make_data("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_pos = inside.findStream("position")
	var outside_pos = outside.findStream("position")
	assert_object(inside_pos).is_not_null()
	assert_object(outside_pos).is_not_null()
	assert_int(inside_pos.container.size()).is_equal(1)
	assert_int(outside_pos.container.size()).is_equal(2)
	node.free()

func test_vector_stream_filters_by_length() -> void:
	var s = PointFilterRangeSettings.new()
	s.attribute_name = "position"
	s.min_value = 0.0
	s.max_value = 2.0
	s.inclusive_min = true
	s.inclusive_max = true
	var arr = PackedVector3Array([Vector3(1.0, 0.0, 0.0), Vector3(10.0, 10.0, 10.0)])
	var d = _make_data("position", arr, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("position")
	var outside_stream = outside.findStream("position")
	assert_int(inside_stream.container.size()).is_equal(1)
	assert_int(outside_stream.container.size()).is_equal(1)
	node.free()

func test_absolute_value_mode() -> void:
	var s = PointFilterRangeSettings.new()
	s.attribute_name = "position.X"
	s.min_value = 1.0
	s.max_value = 5.0
	s.inclusive_min = true
	s.inclusive_max = true
	s.use_absolute_value = true
	# Register "position" Vector3 — attribute "position.X" splits on "." → reads X component (then abs)
	# abs(-3)=3→inside, abs(2)=2→inside, abs(-6)=6→outside, abs(4)=4→inside
	var positions = PackedVector3Array([Vector3(-3.0,0,0), Vector3(2.0,0,0), Vector3(-6.0,0,0), Vector3(4.0,0,0)])
	var d = _make_data("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_pos = inside.findStream("position")
	var outside_pos = outside.findStream("position")
	assert_object(inside_pos).is_not_null()
	assert_object(outside_pos).is_not_null()
	assert_int(inside_pos.container.size()).is_equal(3)
	assert_int(outside_pos.container.size()).is_equal(1)
	node.free()

func test_string_match_mode_case_insensitive() -> void:
	var s = PointFilterRangeSettings.new()
	s.attribute_name = "tag"
	s.string_match_mode = true
	s.string_match_values = "red, blue"
	s.case_sensitive = false
	var packed = PackedStringArray(["red", "green", "Blue", "yellow", "RED"])
	var d = _make_data("tag", packed, FlowDataScript.DataType.String)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("tag")
	var outside_stream = outside.findStream("tag")
	assert_int(inside_stream.container.size()).is_equal(3)
	assert_int(outside_stream.container.size()).is_equal(2)
	node.free()

func test_empty_input_data_produces_empty_outputs() -> void:
	var s = PointFilterRangeSettings.new()
	s.min_value = 0.0
	s.max_value = 1.0
	var d = FlowDataScript.Data.new()
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	assert_int(inside.size()).is_equal(0)
	assert_int(outside.size()).is_equal(0)
	node.free()

func test_missing_input_sets_error() -> void:
	var s = PointFilterRangeSettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_attribute_not_found_sets_error() -> void:
	var s = PointFilterRangeSettings.new()
	s.attribute_name = "position.X"
	var d = _make_data("other", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_string_match_no_values_sets_error() -> void:
	var s = PointFilterRangeSettings.new()
	s.attribute_name = "tag"
	s.string_match_mode = true
	s.string_match_values = ""
	var packed = PackedStringArray(["red", "blue"])
	var d = _make_data("tag", packed, FlowDataScript.DataType.String)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_color_stream_filters_by_rgb_average() -> void:
	var s = PointFilterRangeSettings.new()
	s.attribute_name = "col"
	s.min_value = 0.5
	s.max_value = 1.0
	s.inclusive_min = true
	s.inclusive_max = true
	var bright = Color(1.0, 1.0, 1.0)
	var dark = Color(0.0, 0.0, 0.0)
	var mid = Color(0.6, 0.6, 0.6)
	var arr = PackedColorArray([bright, dark, mid])
	var d = _make_data("col", arr, FlowDataScript.DataType.Color)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	var inside_stream = inside.findStream("col")
	var outside_stream = outside.findStream("col")
	assert_int(inside_stream.container.size()).is_equal(2)
	assert_int(outside_stream.container.size()).is_equal(1)
	node.free()
