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

func test_uniform_samples_have_unit_scale_and_interval_bounds() -> void:
	# UE parity (the original Flyn report): samples must keep UNIT scale so spawned
	# meshes are placed at their natural size, not stretched to the sample spacing.
	# The spacing/extent lives in bounds instead.
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(10, 0, 0))

	var node = _run_sample_spline(path_3d, false, func(s):
		s.sampling_mode = SampleSplineSettings.eSamplingMode.Uniform
		s.uniform_interval = 2.0
		s.adjust_to_borders = true
	)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	assert_object(out).is_not_null()

	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_bool(sizes.size() > 0).is_true()
	for sz in sizes:
		assert_bool(sz.is_equal_approx(Vector3.ONE)).is_true()

	# Bounds carry the spacing extent (~uniform_interval) instead.
	var bmin = out.getVector3Container(FlowDataScript.AttrBoundsMin)
	var bmax = out.getVector3Container(FlowDataScript.AttrBoundsMax)
	assert_int(bmin.size()).is_equal(sizes.size())
	var ext = bmax[0] - bmin[0]
	assert_float(ext.x).is_equal_approx(2.0, 0.001)

	node.free()
	path_3d.free()

func test_legacy_scale_from_extent_writes_size() -> void:
	# Opt-in bridge: with legacy_scale_from_extent on, size returns to the old
	# size-as-scale behavior (= the interval) so existing graphs render as before.
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(10, 0, 0))

	var node = _run_sample_spline(path_3d, false, func(s):
		s.sampling_mode = SampleSplineSettings.eSamplingMode.Uniform
		s.uniform_interval = 2.0
		s.adjust_to_borders = true
		s.legacy_scale_from_extent = true
	)
	assert_str(node.err).is_empty()
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	var sizes = out.getVector3Container(FlowDataScript.AttrSize)
	assert_bool(sizes.size() > 0).is_true()
	for sz in sizes:
		assert_float(sz.x).is_equal_approx(2.0, 0.001)  # size == interval (old behavior)
	# Bounds are still recorded too.
	assert_int(out.getVector3Container(FlowDataScript.AttrBoundsMin).size()).is_equal(sizes.size())
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

# ---------------------------------------------------------------------------
# Input validation. A typed but EMPTY `node` stream is valid (a road with no
# bridges) and yields an empty point set silently; entries that are not live
# Path3D nodes with a Curve3D are skipped with one warning; a missing or
# wrongly typed stream is an error naming the problem. None of these paths
# computes distances, so they do not depend on the native GDKdTree.
# ---------------------------------------------------------------------------

func _run_with_input(in_data: FlowData.Data, custom_settings_cb: Callable = Callable()) -> SampleSplineNode:
	var node = SampleSplineNode.new()
	node.name = "sample_spline_test_node"
	node.settings = SampleSplineSettings.new()
	if custom_settings_cb.is_valid():
		custom_settings_cb.call(node.settings)
	node.inputs = [in_data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy_owner = FlowGraphNode3D.new()
	ctx.owner = dummy_owner
	node.preExecute(ctx)
	node.execute(ctx)
	dummy_owner.free()
	return node

func _node_stream_input(entries: Array[Node]) -> FlowData.Data:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("node", entries, FlowDataScript.DataType.NodePath)
	return in_data

func _line_path() -> Path3D:
	var path_3d = Path3D.new()
	path_3d.curve = Curve3D.new()
	path_3d.curve.add_point(Vector3(0, 0, 0))
	path_3d.curve.add_point(Vector3(10, 0, 0))
	return path_3d

## [warnings, errors] pushed while `fn` runs.
func _log_during(fn: Callable) -> Array:
	var logger := GodotGdErrorMonitor.GdUnitLogger.new(true, false)
	fn.call()
	OS.remove_logger(logger)
	var warnings := PackedStringArray()
	var errors := PackedStringArray()
	for entry in logger.entries():
		if entry._type == ErrorLogEntry.TYPE.PUSH_WARNING:
			warnings.append(entry._message)
		elif entry._type == ErrorLogEntry.TYPE.PUSH_ERROR or entry._type == ErrorLogEntry.TYPE.SCRIPT_ERROR:
			errors.append(entry._message)
	return [warnings, errors]

func _uniform_settings(s) -> void:
	s.sampling_mode = SampleSplineSettings.eSamplingMode.Uniform
	s.uniform_interval = 2.0
	s.adjust_to_borders = true

func test_empty_node_stream_yields_empty_data_silently() -> void:
	var modes := [
		func(s): _uniform_settings(s),
		func(s):
			s.sampling_mode = SampleSplineSettings.eSamplingMode.Random
			s.num_random_samples = 5,
		func(s):
			s.fill_curve = true
			s.fill_mode = 0,
		func(s):
			s.fill_curve = true
			s.fill_mode = 2
			s.distance_attribute = "dist",
	]
	for cb in modes:
		var empty: Array[Node] = []
		var holder := [null]
		var log := _log_during(func(): holder[0] = _run_with_input(_node_stream_input(empty), cb))
		var node = holder[0]
		assert_str(node.err).is_empty()
		assert_array(log[0]).is_empty()
		assert_array(log[1]).is_empty()
		var out = _get_output_data(node)
		assert_object(out).is_not_null()
		if out != null:
			assert_int(out.size()).is_equal(0)
			for stream_name in [FlowDataScript.AttrPosition, FlowDataScript.AttrRotation, FlowDataScript.AttrSize,
					FlowDataScript.AttrDensity, FlowDataScript.AttrSeed]:
				assert_object(out.findStream(stream_name)).override_failure_message("missing %s" % stream_name).is_not_null()
		node.free()

func test_invalid_node_entries_are_skipped_with_one_warning() -> void:
	var valid := _line_path()
	var reference = _run_sample_spline(valid, false, func(s): _uniform_settings(s))
	var expected: PackedVector3Array = _get_output_data(reference).getVector3Container(FlowDataScript.AttrPosition)
	reference.free()

	var freed := Path3D.new()
	freed.curve = Curve3D.new()
	var not_a_path := Node3D.new()
	var no_curve := Path3D.new()
	no_curve.curve = null
	var entries: Array[Node] = [null, valid, freed, not_a_path, no_curve]
	# Freed after the stream was built, as when a scene node goes away between
	# gathering and sampling.
	freed.free()
	var holder := [null]
	var log := _log_during(func(): holder[0] = _run_with_input(_node_stream_input(entries), func(s): _uniform_settings(s)))
	var node = holder[0]
	assert_str(node.err).is_empty()
	assert_array(log[1]).is_empty()
	assert_int(log[0].size()).is_equal(1)
	if log[0].size() == 1:
		assert_str(log[0][0]).contains("skipped 4")
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	if out != null:
		assert_array(out.getVector3Container(FlowDataScript.AttrPosition)).is_equal(expected)
	node.free()
	not_a_path.free()
	no_curve.free()
	valid.free()

func test_only_invalid_entries_yield_empty_data() -> void:
	var not_a_path := Node3D.new()
	var entries: Array[Node] = [not_a_path]
	var holder := [null]
	var log := _log_during(func(): holder[0] = _run_with_input(_node_stream_input(entries), func(s): _uniform_settings(s)))
	var node = holder[0]
	assert_str(node.err).is_empty()
	assert_int(log[0].size()).is_equal(1)
	var out = _get_output_data(node)
	assert_object(out).is_not_null()
	if out != null:
		assert_int(out.size()).is_equal(0)
	node.free()
	not_a_path.free()

func test_missing_node_stream_errors() -> void:
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowDataScript.AttrPosition, PackedVector3Array([Vector3.ZERO]), FlowDataScript.DataType.Vector)
	var node = _run_with_input(in_data)
	assert_str(node.err).contains("Input has no 'node' stream")
	node.free()

func test_wrong_node_stream_type_errors() -> void:
	var mi := MeshInstance3D.new()
	var in_data := FlowDataScript.Data.new()
	var meshes: Array[Node] = [mi]
	in_data.registerStream("node", meshes, FlowDataScript.DataType.NodeMesh)
	var node = _run_with_input(in_data)
	assert_str(node.err).contains("'node' stream must be NodePath/Node typed (got NodeMesh)")
	node.free()
	mi.free()
