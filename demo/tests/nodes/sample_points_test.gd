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
	

# ---------------------------------------------------------------------------
# inherit_attributes
# ---------------------------------------------------------------------------

## Two parent points far apart (x = 0 and x = 100) with per-point attributes,
## a broadcast attribute and a density that must NOT override the sampler's.
func _parents_with_attributes() -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrPosition, PackedVector3Array([Vector3.ZERO, Vector3(100, 0, 0)]), FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrRotation, PackedVector3Array([Vector3.ZERO, Vector3.ZERO]), FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrSize, PackedVector3Array([Vector3(2, 2, 2), Vector3(2, 2, 2)]), FlowDataScript.DataType.Vector)
	d.registerStream(FlowDataScript.AttrDensity, PackedFloat32Array([0.2, 0.3]), FlowDataScript.DataType.Float)
	d.registerStream("room", PackedInt32Array([7, 9]), FlowDataScript.DataType.Int)
	d.registerStream("label", PackedStringArray(["west", "east"]), FlowDataScript.DataType.String)
	d.registerStream("zone", PackedFloat32Array([3.5]), FlowDataScript.DataType.Float)
	return d

func _configure_small(s) -> void:
	s.sampling_distance = 1.0
	var groups : Array[int] = [5]
	s.groups = groups
	s.num_samples = 16

func test_inherit_attributes_default_off_keeps_common_streams_only() -> void:
	assert_bool(SamplePointsSettings.new().inherit_attributes).is_false()
	var node = _run_sample_points(_parents_with_attributes(), SamplePointsSettings.eDistribution.QuasiRandom2D, _configure_small)
	var out = _get_output_data(node)
	assert_array(out.streams.keys()).is_equal(["position", "rotation", "size", "density", "seed"])

func test_inherit_attributes_copies_parent_values() -> void:
	for distribution in [
			SamplePointsSettings.eDistribution.UniformGrid,
			SamplePointsSettings.eDistribution.QuasiRandom2D,
			SamplePointsSettings.eDistribution.QuasiRandom3D,
			SamplePointsSettings.eDistribution.BlueNoise2D]:
		var node = _run_sample_points(_parents_with_attributes(), distribution, func(s):
			_configure_small(s)
			s.inherit_attributes = true
		)
		assert_str(node.err).is_empty()
		var out = _get_output_data(node)
		var positions = out.getVector3Container(FlowDataScript.AttrPosition)
		var n : int = positions.size()
		assert_int(n).override_failure_message("distribution %d produced no samples" % distribution).is_greater(1)
		var room = out.findStream("room")
		var label = out.findStream("label")
		assert_int(room.data_type).is_equal(FlowDataScript.DataType.Int)
		assert_int(room.container.size()).is_equal(n)
		assert_int(label.container.size()).is_equal(n)
		var saw_west := false
		var saw_east := false
		for i in range(n):
			var east : bool = positions[i].x > 50.0
			saw_east = saw_east or east
			saw_west = saw_west or not east
			assert_int(room.container[i]).is_equal(9 if east else 7)
			assert_str(label.container[i]).is_equal("east" if east else "west")
		assert_bool(saw_west and saw_east).is_true()
		# Broadcast stays broadcast.
		var zone = out.findStream("zone")
		assert_int(zone.container.size()).is_equal(1)
		assert_float(zone.container[0]).is_equal(3.5)
		# Sampler-generated streams win over the parent's.
		for d in out.findStream(FlowDataScript.AttrDensity).container:
			assert_float(d).is_equal(1.0)
		assert_int(out.findStream(FlowDataScript.AttrSeed).container.size()).is_equal(n)

func test_inherit_attributes_does_not_change_generated_points() -> void:
	var off = _run_sample_points(_parents_with_attributes(), SamplePointsSettings.eDistribution.BlueNoise2D, _configure_small)
	var on = _run_sample_points(_parents_with_attributes(), SamplePointsSettings.eDistribution.BlueNoise2D, func(s):
		_configure_small(s)
		s.inherit_attributes = true
	)
	for stream_name in ["position", "rotation", "size", "density", "seed"]:
		assert_array(Array(_get_output_data(on).findStream(stream_name).container)) \
			.is_equal(Array(_get_output_data(off).findStream(stream_name).container))

func test_inherit_attributes_empty_input_keeps_schema() -> void:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowDataScript.AttrPosition, PackedVector3Array(), FlowDataScript.DataType.Vector)
	d.registerStream("room", PackedInt32Array(), FlowDataScript.DataType.Int)
	var node = _run_sample_points(d, SamplePointsSettings.eDistribution.QuasiRandom2D, func(s):
		s.inherit_attributes = true
	)
	var out = _get_output_data(node)
	assert_bool(out.hasStream("room")).is_true()
	assert_int(out.size()).is_equal(0)


func test_legacy_scale_from_extent_writes_no_bounds_streams() -> void:
	# Legacy bridge = pre-bounds output exactly: extent in `size`, no bounds streams.
	var in_data := FlowDataScript.Data.new()
	in_data.addCommonStreams(1)
	in_data.getVector3Container(FlowDataScript.AttrSize)[0] = Vector3(10, 1, 10)
	var node = _run_sample_points(in_data, SamplePointsSettings.eDistribution.UniformGrid, func(s):
		s.legacy_scale_from_extent = true
	)
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	assert_bool(out.hasStream(FlowDataScript.AttrBoundsMin)).is_false()
	assert_bool(out.hasStream(FlowDataScript.AttrBoundsMax)).is_false()

	var node_b = _run_sample_points(in_data, SamplePointsSettings.eDistribution.UniformGrid)
	var out_b = _get_output_data(node_b)
	assert_bool(out_b.hasStream(FlowDataScript.AttrBoundsMin)).is_true()
