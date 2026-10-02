# point_to_attribute_set_test.gd
class_name PointToAttributeSetTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointToAttributeSetNode = preload("res://addons/flow_nodes_editor/nodes/point_to_attribute_set.gd")
const PointToAttributeSetSettings = preload("res://addons/flow_nodes_editor/nodes/point_to_attribute_set_settings.gd")

func _make_point_data(positions: PackedVector3Array, rotations: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrRotation, rotations, FlowDataScript.DataType.Vector)
	d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _make_data_with_extra(positions: PackedVector3Array, rotations: PackedVector3Array, sizes: PackedVector3Array, extra_name: String, extra_values: PackedFloat32Array) -> FlowData.Data:
	var d := _make_point_data(positions, rotations, sizes)
	d.registerStream(extra_name, extra_values, FlowDataScript.DataType.Float)
	return d

func _run(inputs: Array, settings) -> PointToAttributeSetNode:
	var node = PointToAttributeSetNode.new()
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

func _make_default_settings() -> PointToAttributeSetSettings:
	var s = PointToAttributeSetSettings.new()
	s.drop_point_transform_streams = true
	s.preserve_transforms_as_attributes = true
	s.out_position_attribute_name = "point_position"
	s.out_rotation_attribute_name = "point_rotation"
	s.out_size_attribute_name = "point_size"
	return s

func test_missing_input_sets_error() -> void:
	var s = _make_default_settings()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_plain_copy_when_drop_disabled() -> void:
	var s = _make_default_settings()
	s.drop_point_transform_streams = false
	var positions = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	var rotations = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 2, 2)])
	var in_data = _make_point_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrPosition)).is_true()
	assert_bool(out.hasStream(FlowData.AttrRotation)).is_true()
	assert_bool(out.hasStream(FlowData.AttrSize)).is_true()
	assert_array(out.findStream(FlowData.AttrPosition).container).is_equal(positions)
	assert_array(out.findStream(FlowData.AttrRotation).container).is_equal(rotations)
	assert_array(out.findStream(FlowData.AttrSize).container).is_equal(sizes)

func test_drop_transforms_no_preserve() -> void:
	var s = _make_default_settings()
	s.drop_point_transform_streams = true
	s.preserve_transforms_as_attributes = false
	var positions = PackedVector3Array([Vector3(1, 0, 0), Vector3(0, 1, 0)])
	var rotations = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 45, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 2, 1)])
	var in_data = _make_point_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrPosition)).is_false()
	assert_bool(out.hasStream(FlowData.AttrRotation)).is_false()
	assert_bool(out.hasStream(FlowData.AttrSize)).is_false()

func test_drop_transforms_with_preserve() -> void:
	var s = _make_default_settings()
	var positions = PackedVector3Array([Vector3(1, 2, 3), Vector3(7, 8, 9)])
	var rotations = PackedVector3Array([Vector3(0, 90, 0), Vector3(0, 0, 45)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 3, 4)])
	var in_data = _make_point_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrPosition)).is_false()
	assert_bool(out.hasStream(FlowData.AttrRotation)).is_false()
	assert_bool(out.hasStream(FlowData.AttrSize)).is_false()
	assert_bool(out.hasStream(&"point_position")).is_true()
	assert_bool(out.hasStream(&"point_rotation")).is_true()
	assert_bool(out.hasStream(&"point_size")).is_true()
	assert_array(out.findStream(&"point_position").container).is_equal(positions)
	assert_array(out.findStream(&"point_rotation").container).is_equal(rotations)
	assert_array(out.findStream(&"point_size").container).is_equal(sizes)

func test_custom_attribute_names() -> void:
	var s = _make_default_settings()
	s.out_position_attribute_name = "my_pos"
	s.out_rotation_attribute_name = "my_rot"
	s.out_size_attribute_name = "my_scale"
	var positions = PackedVector3Array([Vector3(5, 0, 5)])
	var rotations = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var in_data = _make_point_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(&"my_pos")).is_true()
	assert_bool(out.hasStream(&"my_rot")).is_true()
	assert_bool(out.hasStream(&"my_scale")).is_true()
	assert_bool(out.hasStream(&"point_position")).is_false()
	assert_bool(out.hasStream(&"point_rotation")).is_false()
	assert_bool(out.hasStream(&"point_size")).is_false()

func test_extra_streams_are_preserved() -> void:
	var s = _make_default_settings()
	var positions = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)])
	var rotations = PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 1)])
	var extra = PackedFloat32Array([10.0, 20.0, 30.0])
	var in_data = _make_data_with_extra(positions, rotations, sizes, "density", extra)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(&"density")).is_true()
	assert_array(out.findStream(&"density").container).is_equal(extra)

func test_single_point() -> void:
	var s = _make_default_settings()
	var positions = PackedVector3Array([Vector3(1, 2, 3)])
	var rotations = PackedVector3Array([Vector3(0, 45, 0)])
	var sizes = PackedVector3Array([Vector3(2, 2, 2)])
	var in_data = _make_point_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrPosition)).is_false()
	assert_bool(out.hasStream(&"point_position")).is_true()
	assert_array(out.findStream(&"point_position").container).is_equal(positions)

func test_empty_point_array() -> void:
	var s = _make_default_settings()
	var in_data = _make_point_data(PackedVector3Array(), PackedVector3Array(), PackedVector3Array())
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrPosition)).is_false()
	assert_bool(out.hasStream(&"point_position")).is_true()
	assert_int(out.findStream(&"point_position").container.size()).is_equal(0)

func test_blank_attribute_name_skips_copy() -> void:
	var s = _make_default_settings()
	s.out_position_attribute_name = ""
	var positions = PackedVector3Array([Vector3(1, 0, 0)])
	var rotations = PackedVector3Array([Vector3(0, 0, 0)])
	var sizes = PackedVector3Array([Vector3(1, 1, 1)])
	var in_data = _make_point_data(positions, rotations, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowData.AttrPosition)).is_false()
	assert_bool(out.hasStream(&"")).is_false()
	assert_bool(out.hasStream(&"point_rotation")).is_true()
	assert_bool(out.hasStream(&"point_size")).is_true()
