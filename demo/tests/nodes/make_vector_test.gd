# make_vector_test.gd
class_name MakeVectorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const MakeVectorNode = preload("res://addons/flow_nodes_editor/nodes/make_vector.gd")
const MakeVectorSettings = preload("res://addons/flow_nodes_editor/nodes/make_vector_settings.gd")

func _run(settings) -> MakeVectorNode:
	var node = MakeVectorNode.new()
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

func test_default_settings_produce_zero_vector() -> void:
	var s = MakeVectorSettings.new()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("Vector")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0].x).is_equal_approx(0.0, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(0.0, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(0.0, 0.001)
	node.free()

func test_positive_xyz_components() -> void:
	var s = MakeVectorSettings.new()
	s.x = 1.0
	s.y = 2.0
	s.z = 3.0
	s.out_name = "Vector"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("Vector")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0].x).is_equal_approx(1.0, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(2.0, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(3.0, 0.001)
	node.free()

func test_negative_xyz_components() -> void:
	var s = MakeVectorSettings.new()
	s.x = -5.5
	s.y = -10.0
	s.z = -0.25
	s.out_name = "Vector"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("Vector")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0].x).is_equal_approx(-5.5, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(-10.0, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(-0.25, 0.001)
	node.free()

func test_custom_out_name() -> void:
	var s = MakeVectorSettings.new()
	s.x = 7.0
	s.y = 8.0
	s.z = 9.0
	s.out_name = "my_vector"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("my_vector")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0].x).is_equal_approx(7.0, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(8.0, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(9.0, 0.001)
	node.free()

func test_large_float_values() -> void:
	var s = MakeVectorSettings.new()
	s.x = 1000000.0
	s.y = -999999.9
	s.z = 123456.789
	s.out_name = "big"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("big")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0].x).is_equal_approx(1000000.0, 1.0)
	assert_float(stream.container[0].y).is_equal_approx(-999999.9, 1.0)
	assert_float(stream.container[0].z).is_equal_approx(123456.789, 0.1)
	node.free()

func test_fractional_components() -> void:
	var s = MakeVectorSettings.new()
	s.x = 0.1
	s.y = 0.2
	s.z = 0.3
	s.out_name = "frac"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("frac")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0].x).is_equal_approx(0.1, 0.001)
	assert_float(stream.container[0].y).is_equal_approx(0.2, 0.001)
	assert_float(stream.container[0].z).is_equal_approx(0.3, 0.001)
	node.free()

func test_output_is_vector_type() -> void:
	var s = MakeVectorSettings.new()
	s.x = 1.0
	s.y = 0.0
	s.z = 0.0
	s.out_name = "direction"
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("direction")
	assert_object(stream).is_not_null()
	assert_int(stream.data_type).is_equal(FlowDataScript.DataType.Vector)
	assert_int(stream.container.size()).is_equal(1)
	node.free()

func test_default_out_name_is_vector() -> void:
	var s = MakeVectorSettings.new()
	s.x = 3.0
	s.y = 6.0
	s.z = 9.0
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("Vector")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	node.free()
