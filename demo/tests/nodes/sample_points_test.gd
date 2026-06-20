# sample_points_test.gd
class_name SamplePointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SamplePointsNode = preload("res://addons/flow_nodes_editor/nodes/sample_points.gd")
const SamplePointsSettings = preload("res://addons/flow_nodes_editor/nodes/sample_points_settings.gd")

func _run_sample_points(in_data: FlowData.Data, distribution: int, custom_settings_cb: Callable = Callable()) -> SamplePointsNode:
	var node = SamplePointsNode.new()
	node.name = "sample_points_test_node"
	node.settings = SamplePointsSettings.new()
	node.settings.distribution = distribution
	
	if custom_settings_cb.is_valid():
		custom_settings_cb.call(node.settings)
	
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

func _get_output_data(node: SamplePointsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_uniform_grid() -> void:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowDataScript.AttrPosition, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrRotation, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrSize, PackedVector3Array([Vector3(2, 2, 2)]), FlowDataScript.DataType.Vector)
	
	var node = _run_sample_points(in_data, SamplePointsSettings.eDistribution.UniformGrid, func(s):
		s.sampling_distance = 1.0
		s.max_x = 32
		s.max_y = 32
		s.max_z = 32
		s.new_size_factor = 1.0
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# Grid count = (2/1.0)^3 = 8 points
	assert_int(positions.size()).is_equal(8)
	
	# Verify output size is sampling_distance * new_size_factor = 1.0
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_bool(sizes[0] == Vector3.ONE).is_true()
	
	# Verify density and seed streams
	assert_object(out.findStream(FlowDataScript.AttrDensity)).is_not_null()
	assert_object(out.findStream(FlowDataScript.AttrSeed)).is_not_null()
	
	node.free()

func test_quasi_random_2d() -> void:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowDataScript.AttrPosition, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrRotation, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrSize, PackedVector3Array([Vector3(5, 1, 5)]), FlowDataScript.DataType.Vector)
	
	# Request groups: 10 of group 0, 20 of group 1
	var node = _run_sample_points(in_data, SamplePointsSettings.eDistribution.QuasiRandom2D, func(s):
		s.groups = Array([10, 20], TYPE_INT, &"", null)
		s.out_group_id = "grp"
		s.size = 1.5
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(30)
	
	var group_stream = out.findStream("grp")
	assert_object(group_stream).is_not_null()
	
	var groups : PackedInt32Array = group_stream.container
	# Verify first 10 points are group 0
	for i in range(10):
		assert_int(groups[i]).is_equal(0)
	# Verify next 20 points are group 1
	for i in range(10, 30):
		assert_int(groups[i]).is_equal(1)
		
	node.free()

func test_quasi_random_3d() -> void:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowDataScript.AttrPosition, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrRotation, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrSize, PackedVector3Array([Vector3(5, 5, 5)]), FlowDataScript.DataType.Vector)
	
	var node = _run_sample_points(in_data, SamplePointsSettings.eDistribution.QuasiRandom3D, func(s):
		s.groups = Array([15], TYPE_INT, &"", null)
		s.size = 1.0
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	assert_int(positions.size()).is_equal(15)
	
	node.free()

func test_blue_noise_2d() -> void:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowDataScript.AttrPosition, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrRotation, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	in_data.registerStream(FlowDataScript.AttrSize, PackedVector3Array([Vector3(10, 1, 10)]), FlowDataScript.DataType.Vector)
	
	var node = _run_sample_points(in_data, SamplePointsSettings.eDistribution.BlueNoise2D, func(s):
		s.num_samples = 40
		s.size = 1.0
	)
	assert_str(node.err).is_empty()
	
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	
	var positions = out.getVector3Container(FlowDataScript.AttrPosition)
	# BlueNoise limits points by input size. For 10x10, it should output a positive number of points
	assert_bool(positions.size() > 0).is_true()
	
	node.free()
