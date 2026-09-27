# attribute_set_to_point_test.gd
class_name AttributeSetToPointTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const AttributeSetToPointNode = preload("res://addons/flow_nodes_editor/nodes/attribute_set_to_point.gd")
const AttributeSetToPointSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_set_to_point_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _make_empty_data() -> FlowData.Data:
	return FlowDataScript.Data.new()

func _run(inputs: Array, settings) -> AttributeSetToPointNode:
	var node = AttributeSetToPointNode.new()
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

func _default_settings() -> AttributeSetToPointSettings:
	var s = AttributeSetToPointSettings.new()
	s.position_attribute_name = "position"
	s.rotation_attribute_name = "rotation"
	s.size_attribute_name = "size"
	s.use_defaults_when_missing = false
	s.default_position = Vector3.ZERO
	s.default_rotation = Vector3.ZERO
	s.default_size = Vector3.ONE
	return s

func test_all_attributes_present() -> void:
	var s = _default_settings()

	var d = FlowDataScript.Data.new()
	var pos = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)])
	var rot = PackedVector3Array([Vector3(0.1, 0.2, 0.3), Vector3(0.4, 0.5, 0.6)])
	var sz  = PackedVector3Array([Vector3(1, 1, 1), Vector3(2, 2, 2)])
	d.registerStream("position", pos, FlowDataScript.DataType.Vector)
	d.registerStream("rotation", rot, FlowDataScript.DataType.Vector)
	d.registerStream("size", sz, FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(pos)

	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_array(rot_stream.container).is_equal(rot)

	var sz_stream = out.findStream(FlowDataScript.AttrSize)
	assert_object(sz_stream).is_not_null()
	assert_array(sz_stream.container).is_equal(sz)
	node.free()

func test_use_defaults_when_missing_all() -> void:
	var s = _default_settings()
	s.use_defaults_when_missing = true
	s.default_position = Vector3(10, 20, 30)
	s.default_rotation = Vector3(1, 2, 3)
	s.default_size = Vector3(5, 5, 5)

	var d = FlowDataScript.Data.new()
	var dummy_stream = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	d.registerStream("some_other_attr", dummy_stream, FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_stream = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([
		Vector3(10, 20, 30), Vector3(10, 20, 30), Vector3(10, 20, 30)
	]))

	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_array(rot_stream.container).is_equal(PackedVector3Array([
		Vector3(1, 2, 3), Vector3(1, 2, 3), Vector3(1, 2, 3)
	]))

	var sz_stream = out.findStream(FlowDataScript.AttrSize)
	assert_object(sz_stream).is_not_null()
	assert_array(sz_stream.container).is_equal(PackedVector3Array([
		Vector3(5, 5, 5), Vector3(5, 5, 5), Vector3(5, 5, 5)
	]))
	node.free()

func test_missing_input_error() -> void:
	var s = _default_settings()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_position_attribute_no_default_error() -> void:
	var s = _default_settings()
	s.use_defaults_when_missing = false

	var d = FlowDataScript.Data.new()
	var rot = PackedVector3Array([Vector3.ZERO])
	var sz  = PackedVector3Array([Vector3.ONE])
	d.registerStream("rotation", rot, FlowDataScript.DataType.Vector)
	d.registerStream("size", sz, FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_missing_size_attribute_no_default_error() -> void:
	var s = _default_settings()
	s.use_defaults_when_missing = false

	var d = FlowDataScript.Data.new()
	var pos = PackedVector3Array([Vector3(1, 2, 3)])
	var rot = PackedVector3Array([Vector3.ZERO])
	d.registerStream("position", pos, FlowDataScript.DataType.Vector)
	d.registerStream("rotation", rot, FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_wrong_stream_type_error() -> void:
	var s = _default_settings()
	s.use_defaults_when_missing = false

	var d = FlowDataScript.Data.new()
	# The canonical schema refuses a Float "position" through registerStream; build
	# the mistyped stream by hand to keep exercising the node's own type check.
	d.streams["position"] = { "container": PackedFloat32Array([1.0, 2.0, 3.0]), "name": "position", "data_type": FlowDataScript.DataType.Float }
	d.registerStream("rotation", PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]), FlowDataScript.DataType.Vector)
	d.registerStream("size", PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE]), FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_empty_input_passes_through() -> void:
	var s = _default_settings()
	s.use_defaults_when_missing = false

	var d = FlowDataScript.Data.new()
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_single_element_broadcast() -> void:
	var s = _default_settings()
	s.use_defaults_when_missing = false

	var d = FlowDataScript.Data.new()
	var pos = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)])
	var rot_single = PackedVector3Array([Vector3(0.5, 0.5, 0.5)])
	var sz_single  = PackedVector3Array([Vector3(2, 2, 2)])
	d.registerStream("position", pos, FlowDataScript.DataType.Vector)
	d.registerStream("rotation", rot_single, FlowDataScript.DataType.Vector)
	d.registerStream("size", sz_single, FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var rot_stream = out.findStream(FlowDataScript.AttrRotation)
	assert_object(rot_stream).is_not_null()
	assert_array(rot_stream.container).is_equal(PackedVector3Array([
		Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5), Vector3(0.5, 0.5, 0.5)
	]))

	var sz_stream = out.findStream(FlowDataScript.AttrSize)
	assert_object(sz_stream).is_not_null()
	assert_array(sz_stream.container).is_equal(PackedVector3Array([
		Vector3(2, 2, 2), Vector3(2, 2, 2), Vector3(2, 2, 2)
	]))
	node.free()

func test_custom_attribute_names() -> void:
	var s = AttributeSetToPointSettings.new()
	s.position_attribute_name = "pos_custom"
	s.rotation_attribute_name = "rot_custom"
	s.size_attribute_name = "scale_custom"
	s.use_defaults_when_missing = false
	s.default_position = Vector3.ZERO
	s.default_rotation = Vector3.ZERO
	s.default_size = Vector3.ONE

	var d = FlowDataScript.Data.new()
	var pos = PackedVector3Array([Vector3(3, 3, 3)])
	var rot = PackedVector3Array([Vector3(1, 0, 0)])
	var sz  = PackedVector3Array([Vector3(0.5, 0.5, 0.5)])
	d.registerStream("pos_custom", pos, FlowDataScript.DataType.Vector)
	d.registerStream("rot_custom", rot, FlowDataScript.DataType.Vector)
	d.registerStream("scale_custom", sz, FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

	var pos_out = out.findStream(FlowDataScript.AttrPosition)
	assert_object(pos_out).is_not_null()
	assert_array(pos_out.container).is_equal(pos)

	var sz_out = out.findStream(FlowDataScript.AttrSize)
	assert_object(sz_out).is_not_null()
	assert_array(sz_out.container).is_equal(sz)
	node.free()

func test_size_mismatch_error() -> void:
	var s = _default_settings()
	s.use_defaults_when_missing = false

	var d = FlowDataScript.Data.new()
	var pos = PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9)])
	var rot = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var sz  = PackedVector3Array([Vector3.ONE, Vector3.ONE, Vector3.ONE])
	d.registerStream("position", pos, FlowDataScript.DataType.Vector)
	d.registerStream("rotation", rot, FlowDataScript.DataType.Vector)
	d.registerStream("size", sz, FlowDataScript.DataType.Vector)

	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
	node.free()
