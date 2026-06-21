# select_points_test.gd
class_name SelectPointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SelectPointsNode = preload("res://addons/flow_nodes_editor/nodes/select_points.gd")
const SelectPointsSettings = preload("res://addons/flow_nodes_editor/nodes/select_points_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> SelectPointsNode:
	var node = SelectPointsNode.new()
	node.name = "test_select_points"
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
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_ratio_zero_produces_empty_output() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.0
	s.weight_name = ""
	var positions = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)
	])
	var d = _make_data("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_ratio_one_produces_all_points() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 1.0
	s.weight_name = ""
	var positions = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)
	])
	var d = _make_data("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)
	node.free()

func test_ratio_half_produces_half_points() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.5
	s.random_seed = 42
	s.weight_name = ""
	var positions = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0),
		Vector3(4, 0, 0), Vector3(5, 0, 0), Vector3(6, 0, 0), Vector3(7, 0, 0)
	])
	var d = _make_data("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(4)
	node.free()

func test_missing_input_produces_error() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.5
	s.weight_name = ""
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_input_data() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.5
	s.weight_name = ""
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array(), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_single_point_ratio_one() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 1.0
	s.weight_name = ""
	var d = _make_data("position", PackedVector3Array([Vector3(5, 5, 5)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(1)
	node.free()

func test_single_point_ratio_zero() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.0
	s.weight_name = ""
	var d = _make_data("position", PackedVector3Array([Vector3(5, 5, 5)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

func test_weighted_sampling_biases_selection() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.5
	s.random_seed = 1
	s.weight_name = "weight"
	var positions = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)
	])
	# Give very high weight to first two points and near-zero to last two
	var weights = PackedFloat32Array([1000.0, 1000.0, 0.0001, 0.0001])
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	d.registerStream("weight", weights, FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var out_positions = out.findStream("position")
	assert_object(out_positions).is_not_null()
	node.free()

func test_weight_name_not_found_produces_error() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.5
	s.weight_name = "nonexistent_attr"
	var d = _make_data("position", PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)
	]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_per_point_seed_sampling_is_deterministic() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.5
	s.random_seed = 99
	s.weight_name = ""
	var positions = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)
	])
	var seeds = PackedInt32Array([10, 20, 30, 40])
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSeed, seeds, FlowDataScript.DataType.Int)
	var node1 = _run([d], s)
	assert_str(node1.err).is_empty()
	var out1 = _output(node1)
	assert_object(out1).is_not_null()
	assert_int(out1.size()).is_equal(2)

	var node2 = _run([d], s)
	assert_str(node2.err).is_empty()
	var out2 = _output(node2)
	assert_object(out2).is_not_null()

	var pos1 = out1.findStream("position")
	var pos2 = out2.findStream("position")
	assert_array(pos1.container).is_equal(pos2.container)

	node1.free()
	node2.free()

func test_all_streams_preserved_after_selection() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 1.0
	s.weight_name = ""
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var colors = PackedColorArray([Color(1, 0, 0), Color(0, 1, 0)])
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	d.registerStream("color", colors, FlowDataScript.DataType.Color)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(2)
	var out_colors = out.findStream("color")
	assert_object(out_colors).is_not_null()
	assert_int(out_colors.container.size()).is_equal(colors.size())
	node.free()

func test_wrong_weight_type_produces_error() -> void:
	var s = SelectPointsSettings.new()
	s.ratio = 0.5
	s.weight_name = "label"
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var labels = PackedStringArray(["a", "b"])
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	d.registerStream("label", labels, FlowDataScript.DataType.String)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()
