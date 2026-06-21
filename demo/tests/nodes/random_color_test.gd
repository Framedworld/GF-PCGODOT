# random_color_test.gd
class_name RandomColorTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const RandomColorNode = preload("res://addons/flow_nodes_editor/nodes/random_color.gd")
const RandomColorSettings = preload("res://addons/flow_nodes_editor/nodes/random_color_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(input: FlowData.Data, settings: RandomColorSettings) -> RandomColorNode:
	var node = RandomColorNode.new()
	node.name = "random_color_test_node"
	node.settings = settings
	node.inputs = [input]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: RandomColorNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func _make_settings_palette(out_name: String = "color", seed: int = 42) -> RandomColorSettings:
	var s = RandomColorSettings.new()
	s.out_name = out_name
	s.use_palette = true
	var p: Array[Color] = [Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1)]
	s.palette = p
	s.random_seed = seed
	return s

func _make_settings_hsv(out_name: String = "color", seed: int = 42, h_min: float = 0.0, h_max: float = 1.0, s_min: float = 0.6, s_max: float = 1.0, v_min: float = 0.6, v_max: float = 1.0) -> RandomColorSettings:
	var s = RandomColorSettings.new()
	s.out_name = out_name
	s.use_palette = false
	s.hue_min = h_min
	s.hue_max = h_max
	s.sat_min = s_min
	s.sat_max = s_max
	s.val_min = v_min
	s.val_max = v_max
	s.random_seed = seed
	return s

func test_palette_mode_basic() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings_palette("color", 1234)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	node.free()

func test_palette_mode_colors_from_palette() -> void:
	var pos = PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), Vector3(3,0,0), Vector3(4,0,0)])
	var in_data = _make_data("pos", pos, FlowDataScript.DataType.Vector)
	var palette: Array[Color] = [Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1)]
	var s = _make_settings_palette("color", 999)
	s.palette = palette
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(5)
	for i in range(stream.container.size()):
		var c: Color = stream.container[i]
		var found = false
		for p in palette:
			if c.is_equal_approx(p):
				found = true
				break
		assert_bool(found).is_true()
	node.free()

func test_hsv_mode_values_in_range() -> void:
	var pos = PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0), Vector3(3,0,0)])
	var in_data = _make_data("pos", pos, FlowDataScript.DataType.Vector)
	var s = _make_settings_hsv("color", 7777, 0.2, 0.8, 0.3, 0.9, 0.4, 0.95)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(4)
	for i in range(stream.container.size()):
		var c: Color = stream.container[i]
		assert_float(c.a).is_equal_approx(1.0, 0.001)
	node.free()

func test_hsv_mode_alpha_always_one() -> void:
	var pos = PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)])
	var in_data = _make_data("pos", pos, FlowDataScript.DataType.Vector)
	var s = _make_settings_hsv("color", 1111)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	for i in range(stream.container.size()):
		var c: Color = stream.container[i]
		assert_float(c.a).is_equal_approx(1.0, 0.001)
	node.free()

func test_deterministic_with_seed() -> void:
	var pos = PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)])
	var in_data1 = _make_data("pos", pos, FlowDataScript.DataType.Vector)
	var s1 = _make_settings_hsv("color", 55555)
	var node1 = _run(in_data1, s1)
	assert_str(node1.err).is_empty()
	var out1 = _output(node1)
	var stream1 = out1.findStream("color")
	var result1 = PackedColorArray(stream1.container)
	node1.free()

	var in_data2 = _make_data("pos", pos, FlowDataScript.DataType.Vector)
	var s2 = _make_settings_hsv("color", 55555)
	var node2 = _run(in_data2, s2)
	assert_str(node2.err).is_empty()
	var out2 = _output(node2)
	var stream2 = out2.findStream("color")
	assert_array(stream2.container).is_equal(result1)
	node2.free()

func test_per_point_seed_stream_deterministic() -> void:
	var pos = PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)])
	var seeds = PackedInt32Array([111, 222, 333])

	var in_data1 = FlowDataScript.Data.new()
	in_data1.registerStream("pos", pos, FlowDataScript.DataType.Vector)
	in_data1.registerStream(FlowData.AttrSeed, seeds, FlowDataScript.DataType.Int)
	var s1 = _make_settings_hsv("color", 9999)
	var node1 = _run(in_data1, s1)
	assert_str(node1.err).is_empty()
	var out1 = _output(node1)
	var stream1 = out1.findStream("color")
	var result1 = PackedColorArray(stream1.container)
	node1.free()

	var in_data2 = FlowDataScript.Data.new()
	in_data2.registerStream("pos", pos, FlowDataScript.DataType.Vector)
	in_data2.registerStream(FlowData.AttrSeed, seeds, FlowDataScript.DataType.Int)
	var s2 = _make_settings_hsv("color", 9999)
	var node2 = _run(in_data2, s2)
	assert_str(node2.err).is_empty()
	var out2 = _output(node2)
	var stream2 = out2.findStream("color")
	assert_array(stream2.container).is_equal(result1)
	node2.free()

func test_single_point() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0, 0, 0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings_palette("color", 1)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("color")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	node.free()

func test_preserves_existing_streams() -> void:
	var in_data = FlowDataScript.Data.new()
	in_data.registerStream("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0)]), FlowDataScript.DataType.Vector)
	in_data.registerStream("weight", PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)
	var s = _make_settings_palette("color", 42)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("pos")).is_not_null()
	assert_object(out.findStream("weight")).is_not_null()
	assert_object(out.findStream("color")).is_not_null()
	node.free()

func test_custom_out_name() -> void:
	var in_data = _make_data("pos", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0)]), FlowDataScript.DataType.Vector)
	var s = _make_settings_palette("my_custom_color", 42)
	var node = _run(in_data, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("my_custom_color")).is_not_null()
	assert_object(out.findStream("color")).is_null()
	node.free()

func test_missing_input_error() -> void:
	var s = _make_settings_palette()
	var node = _run(null, s)
	assert_str(node.err).is_not_empty()
	node.free()
