# make_bounds_test.gd
class_name MakeBoundsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MakeBoundsNode = preload("res://addons/flow_nodes_editor/nodes/make_bounds.gd")
const MakeBoundsSettings = preload("res://addons/flow_nodes_editor/nodes/make_bounds_settings.gd")

func _run(settings) -> MakeBoundsNode:
	var node = MakeBoundsNode.new()
	node.name = "make_bounds_test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: MakeBoundsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_default_settings() -> void:
	var s = MakeBoundsSettings.new()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(1)
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3.ZERO]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_int(size_stream.container.size()).is_equal(1)
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(48.0, 1.0, 48.0)]))

func test_custom_center() -> void:
	var s = MakeBoundsSettings.new()
	s.center = Vector3(10.0, 5.0, -3.0)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(10.0, 5.0, -3.0)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(48.0, 1.0, 48.0)]))

func test_custom_size() -> void:
	var s = MakeBoundsSettings.new()
	s.size = Vector3(100.0, 20.0, 50.0)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3.ZERO]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(100.0, 20.0, 50.0)]))

func test_custom_center_and_size() -> void:
	var s = MakeBoundsSettings.new()
	s.center = Vector3(1.0, 2.0, 3.0)
	s.size = Vector3(4.0, 5.0, 6.0)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(1.0, 2.0, 3.0)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(4.0, 5.0, 6.0)]))

func test_zero_size() -> void:
	var s = MakeBoundsSettings.new()
	s.size = Vector3.ZERO
	s.center = Vector3.ZERO
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3.ZERO]))

func test_negative_size() -> void:
	var s = MakeBoundsSettings.new()
	s.size = Vector3(-10.0, -5.0, -20.0)
	s.center = Vector3(0.0, 0.0, 0.0)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(-10.0, -5.0, -20.0)]))

func test_output_is_single_point() -> void:
	var s = MakeBoundsSettings.new()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_int(pos_stream.container.size()).is_equal(1)
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_int(size_stream.container.size()).is_equal(1)

func test_large_values() -> void:
	var s = MakeBoundsSettings.new()
	s.center = Vector3(100000.0, -50000.0, 99999.9)
	s.size = Vector3(999999.0, 0.001, 500000.0)
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(100000.0, -50000.0, 99999.9)]))
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_array(size_stream.container).is_equal(PackedVector3Array([Vector3(999999.0, 0.001, 500000.0)]))
