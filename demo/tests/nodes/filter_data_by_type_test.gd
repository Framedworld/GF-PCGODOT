# filter_data_by_type_test.gd
class_name FilterDataByTypeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FilterDataByTypeNode = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_type.gd")
const FilterDataByTypeSettings = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_type_settings.gd")

func _make_point_data() -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream("rotation", PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), FlowDataScript.DataType.Vector)
	d.registerStream("size", PackedVector3Array([Vector3.ONE, Vector3.ONE]), FlowDataScript.DataType.Vector)
	return d

func _make_spline_data() -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("node", Array([NodePath("SomePath"), NodePath("OtherPath")]), FlowDataScript.DataType.NodePath)
	return d

func _make_attr_set_data() -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("my_attr", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	return d

func _make_empty_data() -> FlowData.Data:
	return FlowDataScript.Data.new()

func _make_kind_data(kind: FlowData.Kind) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.kind = kind
	d.registerStream("some_stream", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	return d

func _run(inputs: Array, settings) -> FilterDataByTypeNode:
	var node = FilterDataByTypeNode.new()
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

func _inside(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func _outside(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.size() < 2: return null
	return bulk[1]

func test_point_data_matches_point_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.PointData
	var node = _run([_make_point_data()], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	assert_bool(inside.hasStream("position")).is_true()
	assert_bool(outside.streams.size() == 0).is_true()
	node.free()

func test_point_data_does_not_match_spline_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.SplineData
	var node = _run([_make_point_data()], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.streams.size() == 0).is_true()
	assert_bool(outside.hasStream("position")).is_true()
	node.free()

func test_spline_data_matches_spline_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.SplineData
	var node = _run([_make_spline_data()], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.hasStream("node")).is_true()
	assert_bool(outside.streams.size() == 0).is_true()
	node.free()

func test_attr_set_matches_attr_set_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.AttributeSet
	var node = _run([_make_attr_set_data()], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.hasStream("my_attr")).is_true()
	assert_bool(outside.streams.size() == 0).is_true()
	node.free()

func test_attr_set_does_not_match_point_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.PointData
	var node = _run([_make_attr_set_data()], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.streams.size() == 0).is_true()
	assert_bool(outside.hasStream("my_attr")).is_true()
	node.free()

func test_missing_input_returns_error() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.PointData
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_data_does_not_match_attr_set() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.AttributeSet
	var node = _run([_make_empty_data()], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.streams.size() == 0).is_true()
	node.free()

func test_explicit_kind_spline_matches_spline_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.SplineData
	var d = _make_kind_data(FlowData.Kind.Spline)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.streams.size() > 0).is_true()
	assert_bool(outside.streams.size() == 0).is_true()
	node.free()

func test_explicit_kind_attr_set_matches_attr_set_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.AttributeSet
	var d = _make_kind_data(FlowData.Kind.AttrSet)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.streams.size() > 0).is_true()
	assert_bool(outside.streams.size() == 0).is_true()
	node.free()

func test_explicit_kind_spline_does_not_match_point_target() -> void:
	var s = FilterDataByTypeSettings.new()
	s.target_type = FilterDataByTypeSettings.eTargetType.PointData
	var d = _make_kind_data(FlowData.Kind.Spline)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _inside(node)
	var outside = _outside(node)
	assert_bool(inside.streams.size() == 0).is_true()
	assert_bool(outside.streams.size() > 0).is_true()
	node.free()
