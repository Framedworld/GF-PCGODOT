# sample_spline_test.gd
class_name SampleSplineTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SampleSplineNode = preload("res://addons/flow_nodes_editor/nodes/sample_spline.gd")
const SampleSplineSettings = preload("res://addons/flow_nodes_editor/nodes/sample_spline_settings.gd")

func _run_sample_spline(path_3d: Path3D, fill_curve: bool, custom_settings_cb: Callable = Callable()) -> SampleSplineNode:
	var node = SampleSplineNode.new()
	node.name = "sample_spline_test_node"
	node.settings = SampleSplineSettings.new()
	node.settings.fill_curve = fill_curve
	
	if custom_settings_cb.is_valid():
		custom_settings_cb.call(node.settings)
	
	var in_data := FlowDataScript.Data.new()
	var nodes: Array[Node] = [path_3d]
	in_data.registerStream("node", nodes, FlowDataScript.DataType.NodePath)
	
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = in_data
	
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	
	node.preExecute(ctx)
	node.execute(ctx)
	
	dummy_owner.free()
	return node

func _get_output_data(node: SampleSplineNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_uniform_path_sampling() -> void:
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(10, 0, 0))
	
	# Uniform sampling at interval 2.0
	var node = _run_sample_spline(path_3d, false, func(s):
		s.sampling_mode = SampleSplineSettings.eSamplingMode.Uniform
		s.uniform_interval = 2.0
		s.adjust_to_borders = true
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# Godot's baked points generation for a line of length 10 at interval 2.0 may yield 7 points
	assert_int(positions.size()).is_equal(7)
	
	assert_bool(positions[0].is_equal_approx(Vector3(0, 0, 0))).is_true()
	assert_bool(positions[positions.size() - 1].is_equal_approx(Vector3(10, 0, 0))).is_true()
	
	# Verify density and seed streams exist
	assert_object(out.findStream(FlowDataScript.AttrDensity)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSeed)).is_not_null()
	
	node.free()
	path_3d.free()

func test_random_path_sampling() -> void:
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(10, 0, 0))
	
	var node = _run_sample_spline(path_3d, false, func(s):
		s.sampling_mode = SampleSplineSettings.eSamplingMode.Random
		s.num_random_samples = 8
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(8)
	
	# All points should be on the X axis between 0 and 10
	for p in positions:
		assert_bool(p.x >= 0.0 and p.x <= 10.0).is_true()
		assert_bool(p.y == 0.0).is_true()
		assert_bool(p.z == 0.0).is_true()
		
	node.free()
	path_3d.free()

func test_grid_fill() -> void:
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	# Square loop in XZ plane: (0,0) to (4,4)
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(4, 0, 0))
	path_3d.curve.add_point(Vector3(4, 0, 4))
	path_3d.curve.add_point(Vector3(0, 0, 4))
	path_3d.curve.add_point(Vector3(0, 0, 0)) # Closed
	
	var node = _run_sample_spline(path_3d, true, func(s):
		s.fill_mode = SampleSplineSettings.eFillMode.Grid
		s.uniform_interval = 1.0
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_bool(positions.size() > 0).is_true()
	
	# All grid points must lie within the bounds [0, 4] on X and Z
	for p in positions:
		assert_bool(p.x >= -0.1 and p.x <= 4.1).is_true()
		assert_bool(p.z >= -0.1 and p.z <= 4.1).is_true()
		
	node.free()
	path_3d.free()

func test_random_fill() -> void:
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(4, 0, 0))
	path_3d.curve.add_point(Vector3(4, 0, 4))
	path_3d.curve.add_point(Vector3(0, 0, 4))
	path_3d.curve.add_point(Vector3(0, 0, 0))
	
	var node = _run_sample_spline(path_3d, true, func(s):
		s.fill_mode = SampleSplineSettings.eFillMode.Random
		s.num_random_samples = 12
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(12)
	
	for p in positions:
		assert_bool(p.x >= 0.0 and p.x <= 4.0).is_true()
		assert_bool(p.z >= 0.0 and p.z <= 4.0).is_true()
		
	node.free()
	path_3d.free()

func test_poisson_fill() -> void:
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(4, 0, 0))
	path_3d.curve.add_point(Vector3(4, 0, 4))
	path_3d.curve.add_point(Vector3(0, 0, 4))
	path_3d.curve.add_point(Vector3(0, 0, 0))
	
	var node = _run_sample_spline(path_3d, true, func(s):
		s.fill_mode = SampleSplineSettings.eFillMode.Poisson
		s.uniform_interval = 1.5
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_bool(positions.size() > 0).is_true()
	
	# Verify that the points are within the bounds
	for p in positions:
		assert_bool(p.x >= 0.0 and p.x <= 4.0).is_true()
		assert_bool(p.z >= 0.0 and p.z <= 4.0).is_true()
		
	node.free()
	path_3d.free()
