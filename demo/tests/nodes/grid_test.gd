# grid_test.gd
class_name GridTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GridNode = preload("res://addons/flow_nodes_editor/nodes/grid.gd")
const GridSettings = preload("res://addons/flow_nodes_editor/nodes/grid_settings.gd")

func _run(settings) -> GridNode:
	var node = GridNode.new()
	node.name = "test_grid"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: GridNode) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_default_settings_produces_correct_count() -> void:
	var s = GridSettings.new()
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(9)

func test_single_point_grid() -> void:
	var s = GridSettings.new()
	s.x = 1
	s.y = 1
	s.z = 1
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(1)
	assert_float(positions[0].x).is_equal_approx(0.0, 0.001)
	assert_float(positions[0].y).is_equal_approx(0.0, 0.001)
	assert_float(positions[0].z).is_equal_approx(0.0, 0.001)

func test_zero_axis_produces_empty_output() -> void:
	var s = GridSettings.new()
	s.x = 0
	s.y = 1
	s.z = 3
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(0)

func test_point_positions_match_step() -> void:
	var s = GridSettings.new()
	s.x = 2
	s.y = 1
	s.z = 2
	s.step = Vector3(2.0, 1.0, 3.0)
	s.origin = Vector3.ZERO
	s.rotation = Vector3.ZERO
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(4)
	assert_float(positions[0].x).is_equal_approx(0.0, 0.001)
	assert_float(positions[0].z).is_equal_approx(0.0, 0.001)
	assert_float(positions[1].x).is_equal_approx(2.0, 0.001)
	assert_float(positions[1].z).is_equal_approx(0.0, 0.001)
	assert_float(positions[2].x).is_equal_approx(0.0, 0.001)
	assert_float(positions[2].z).is_equal_approx(3.0, 0.001)
	assert_float(positions[3].x).is_equal_approx(2.0, 0.001)
	assert_float(positions[3].z).is_equal_approx(3.0, 0.001)

func test_origin_offset_applied() -> void:
	var s = GridSettings.new()
	s.x = 1
	s.y = 1
	s.z = 1
	s.origin = Vector3(5.0, 10.0, -3.0)
	s.rotation = Vector3.ZERO
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_float(positions[0].x).is_equal_approx(5.0, 0.001)
	assert_float(positions[0].y).is_equal_approx(10.0, 0.001)
	assert_float(positions[0].z).is_equal_approx(-3.0, 0.001)

func test_common_streams_all_present() -> void:
	var s = GridSettings.new()
	s.x = 2
	s.y = 2
	s.z = 2
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowDataScript.AttrPosition)).is_true()
	assert_bool(out.hasStream(FlowDataScript.AttrRotation)).is_true()
	assert_bool(out.hasStream(FlowDataScript.AttrSize)).is_true()
	assert_bool(out.hasStream(FlowDataScript.AttrDensity)).is_true()
	assert_bool(out.hasStream(FlowDataScript.AttrSeed)).is_true()

func test_density_stream_all_ones() -> void:
	var s = GridSettings.new()
	s.x = 3
	s.y = 1
	s.z = 2
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density = out.findStream(FlowDataScript.AttrDensity)
	assert_object(density).is_not_null()
	assert_int(density.container.size()).is_equal(6)
	for i in range(density.container.size()):
		assert_float(density.container[i]).is_equal_approx(1.0, 0.001)

func test_size_setting_applied_to_all_points() -> void:
	var s = GridSettings.new()
	s.x = 2
	s.y = 1
	s.z = 2
	s.size = 3.5
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_int(sizes.size()).is_equal(4)
	for i in range(sizes.size()):
		assert_float(sizes[i].x).is_equal_approx(3.5, 0.001)
		assert_float(sizes[i].y).is_equal_approx(3.5, 0.001)
		assert_float(sizes[i].z).is_equal_approx(3.5, 0.001)

func test_large_grid_point_count() -> void:
	var s = GridSettings.new()
	s.x = 10
	s.y = 5
	s.z = 10
	var node = _run(s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(500)
	var density = out.findStream(FlowDataScript.AttrDensity)
	assert_int(density.container.size()).is_equal(500)
