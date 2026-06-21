# filter_data_by_attribute_test.gd
class_name FilterDataByAttributeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FilterDataByAttributeNode = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_attribute.gd")
const FilterDataByAttributeSettings = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_attribute_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, attribute_name: String) -> FilterDataByAttributeNode:
	var node = FilterDataByAttributeNode.new()
	node.name = "test_node"
	var s = FilterDataByAttributeSettings.new()
	s.attribute_name = attribute_name
	node.settings = s
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: FilterDataByAttributeNode, port: int) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if port >= bulk.size():
		return null
	return bulk[port]

func test_attribute_found_routes_to_inside() -> void:
	var data = _make_data("color", PackedColorArray([Color.RED, Color.BLUE]), FlowDataScript.DataType.Color)
	var node = _run(data, "color")
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	assert_object(inside.findStream("color")).is_not_null()
	assert_int(inside.size()).is_equal(2)
	assert_int(outside.size()).is_equal(0)
	node.free()

func test_attribute_not_found_routes_to_outside() -> void:
	var data = _make_data("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), FlowDataScript.DataType.Vector)
	var node = _run(data, "color")
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	assert_int(inside.size()).is_equal(0)
	assert_object(outside.findStream("position")).is_not_null()
	assert_int(outside.size()).is_equal(2)
	node.free()

func test_empty_attribute_name_causes_error() -> void:
	var data = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run(data, "")
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_input_causes_error() -> void:
	var node = _run(null, "some_attr")
	assert_str(node.err).is_not_empty()
	node.free()

func test_filter_float_stream_by_attribute() -> void:
	var data = _make_data("density", PackedFloat32Array([0.1, 0.5, 0.9]), FlowDataScript.DataType.Float)
	var node = _run(data, "density")
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_array(inside.findStream("density").container).is_equal(PackedFloat32Array([0.1, 0.5, 0.9]))
	assert_int(outside.size()).is_equal(0)
	node.free()

func test_filter_int_stream_by_attribute() -> void:
	var data = _make_data("point_id", PackedInt32Array([10, 20, 30]), FlowDataScript.DataType.Int)
	var node = _run(data, "point_id")
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	assert_array(inside.findStream("point_id").container).is_equal(PackedInt32Array([10, 20, 30]))
	assert_int(_output(node, 1).size()).is_equal(0)
	node.free()

func test_filter_vector_stream_by_attribute() -> void:
	var data = _make_data("normal", PackedVector3Array([Vector3.UP, Vector3.DOWN]), FlowDataScript.DataType.Vector)
	var node = _run(data, "wrong_name")
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	var outside = _output(node, 1)
	assert_int(inside.size()).is_equal(0)
	assert_array(outside.findStream("normal").container).is_equal(PackedVector3Array([Vector3.UP, Vector3.DOWN]))
	node.free()

func test_single_element_data_routes_correctly() -> void:
	var data = _make_data("tag", PackedFloat32Array([42.0]), FlowDataScript.DataType.Float)
	var node = _run(data, "tag")
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	assert_int(inside.size()).is_equal(1)
	assert_array(inside.findStream("tag").container).is_equal(PackedFloat32Array([42.0]))
	assert_int(_output(node, 1).size()).is_equal(0)
	node.free()

func test_data_with_multiple_streams_preserves_all_when_matched() -> void:
	var data = FlowDataScript.Data.new()
	data.registerStream("pos", PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3.UP]), FlowDataScript.DataType.Vector)
	data.registerStream("weight", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var node = _run(data, "pos")
	assert_str(node.err).is_empty()
	var inside = _output(node, 0)
	assert_object(inside.findStream("pos")).is_not_null()
	assert_object(inside.findStream("weight")).is_not_null()
	assert_int(inside.size()).is_equal(3)
	assert_int(_output(node, 1).size()).is_equal(0)
	node.free()
