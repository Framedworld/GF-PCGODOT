# spatial_legacy_paths_test.gd
# WP2 back-compat: every node WP2 extended must produce byte-identical output to
# the pre-WP2 node (frozen copies in tests/spatial/legacy, base commit 17c4524)
# for point / Path3D / mesh-node inputs and default settings (output_mode =
# Points, projection_mode = Physics, use_bounding_shape = false, ...).
class_name SpatialLegacyPathsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spatial/support/spatial_test_support.gd")

const SurfaceSamplerNode = preload("res://addons/flow_nodes_editor/nodes/surface_sampler.gd")
const SurfaceSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/surface_sampler_settings.gd")
const VolumeSamplerNode = preload("res://addons/flow_nodes_editor/nodes/volume_sampler.gd")
const VolumeSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/volume_sampler_settings.gd")
const SampleSplineNode = preload("res://addons/flow_nodes_editor/nodes/sample_spline.gd")
const SampleSplineSettings = preload("res://addons/flow_nodes_editor/nodes/sample_spline_settings.gd")
const CSFSplineNode = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_spline.gd")
const CSFSplineSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_spline_settings.gd")
const CSFPolygonNode = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_polygon.gd")
const CSFPolygonSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_polygon_settings.gd")
const ProjectionNode = preload("res://addons/flow_nodes_editor/nodes/projection.gd")
const ProjectionSettings = preload("res://addons/flow_nodes_editor/nodes/projection_settings.gd")
const DifferenceNode = preload("res://addons/flow_nodes_editor/nodes/difference.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")
const FilterByTypeNode = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_type.gd")
const FilterByTypeSettings = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_type_settings.gd")
const MakeBoundsNode = preload("res://addons/flow_nodes_editor/nodes/make_bounds.gd")
const MakeBoundsSettings = preload("res://addons/flow_nodes_editor/nodes/make_bounds_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	add_child(_owner)

## Runs the frozen legacy node and the current node on fresh inputs and settings
## from the builders; asserts identical bulks, Data and error text.
func _assert_same(legacy_name : String, current_script, make_settings : Callable, make_inputs : Callable, graph_seed : int = 0, label : String = "") -> void:
	var legacy_node = S.run(S.legacy(legacy_name), make_settings.call(), make_inputs.call(), _owner, graph_seed)
	var current_node = S.run(current_script, make_settings.call(), make_inputs.call(), _owner, graph_seed)
	assert_bool(S.same_node_output(legacy_node, current_node)).override_failure_message("%s %s differs from the pre-WP2 node" % [legacy_name, label]).is_true()
	# Something was produced or reported, so the comparison is not vacuous.
	assert_bool(current_node.generated_bulks.size() > 0 or current_node.err != "").is_true()
	S.release(legacy_node)
	S.release(current_node)

func _pts() -> FlowData.Data:
	var d := S.points([Vector3(0, 0, 0), Vector3(3, 1, -2), Vector3(-4, 0, 5)], [Vector3(4, 1, 4), Vector3(2, 2, 2), Vector3(6, 1, 3)])
	var rot := d.getVector3Container(FlowData.AttrRotation)
	rot[1] = Vector3(0, 45, 0)
	return d

func _path(curve : Curve3D, at : Vector3 = Vector3.ZERO) -> Path3D:
	var p := Path3D.new()
	p.curve = curve
	p.position = at
	_owner.add_child(p)
	return p

func _node_stream(nodes : Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("node", nodes, FlowData.DataType.NodePath)
	return d

# The comparator itself must catch a one-bit difference, or every test below is vacuous.
func test_comparator_detects_differences() -> void:
	var a := _pts()
	assert_bool(S.same_data(a, _pts())).is_true()
	var b := _pts()
	b.getVector3Container(FlowData.AttrPosition)[2] = Vector3(-4, 0, 5.0000005)
	assert_bool(S.same_data(a, b)).is_false()
	var c := _pts()
	c.tags = PackedStringArray(["t"])
	assert_bool(S.same_data(a, c)).is_false()
	var d := _pts()
	d.shape = FlowBoxVolume.new()
	assert_bool(S.same_data(a, d)).is_false()

# --- surface_sampler ---------------------------------------------------------------

func test_surface_sampler_point_input() -> void:
	_assert_same("surface_sampler", SurfaceSamplerNode, func(): return SurfaceSamplerSettings.new(), func(): return [_pts()])
	_assert_same("surface_sampler", SurfaceSamplerNode, func():
		var s = SurfaceSamplerSettings.new()
		s.num_points = 17
		s.random_seed = 5
		s.point_size = Vector3(2, 1, 2)
		return s, func(): return [_pts()], 99, "custom")

func test_surface_sampler_mesh_node_stream_and_edges() -> void:
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	a.position = Vector3(5, 0, 0)
	_owner.add_child(a)
	var b := MeshInstance3D.new()
	b.mesh = S.plane_mesh(4.0, 1)
	b.rotation_degrees = Vector3(0, 30, 0)
	_owner.add_child(b)
	var nodes := [a, b]
	_assert_same("surface_sampler", SurfaceSamplerNode, func(): return SurfaceSamplerSettings.new(), func():
		var d := FlowDataScript.Data.new()
		d.registerStream("node", nodes, FlowData.DataType.NodeMesh)
		return [d], 0, "mesh nodes")
	_assert_same("surface_sampler", SurfaceSamplerNode, func(): return SurfaceSamplerSettings.new(), func(): return [FlowDataScript.Data.new()], 0, "empty")
	_assert_same("surface_sampler", SurfaceSamplerNode, func(): return SurfaceSamplerSettings.new(), func(): return [S.points([])], 0, "zero points")

# --- volume_sampler ----------------------------------------------------------------

func test_volume_sampler_point_input_all_distributions() -> void:
	for dist in [SamplePointsNodeSettings.eDistribution.UniformGrid, SamplePointsNodeSettings.eDistribution.QuasiRandom2D, SamplePointsNodeSettings.eDistribution.QuasiRandom3D, SamplePointsNodeSettings.eDistribution.BlueNoise2D]:
		_assert_same("volume_sampler", VolumeSamplerNode, func():
			var s = VolumeSamplerSettings.new()
			s.distribution = dist
			s.sampling_distance = 0.5
			return s, func(): return [_pts()], 0, str(dist))

# --- sample_spline -------------------------------------------------------------------

func test_sample_spline_path_input_all_modes() -> void:
	var p1 := _path(S.line_curve(Vector3(0, 0, 0), Vector3(10, 0, 3)), Vector3(1, 2, 3))
	var p2 := _path(S.square_curve(4.0), Vector3(-20, 0, 0))
	var nodes := [p1, p2]
	var variants := [
		{},
		{"adjust_to_borders": false},
		{"sample_segments_centers": true, "uniform_interval": 1.5},
		{"sampling_mode": SampleSplineSettings.eSamplingMode.Random, "num_random_samples": 13},
		{"fill_curve": true},
		{"fill_curve": true, "fill_mode": SampleSplineSettings.eFillMode.Random, "num_random_samples": 30},
		{"fill_curve": true, "fill_mode": SampleSplineSettings.eFillMode.Poisson, "uniform_interval": 0.7},
		{"legacy_scale_from_extent": true},
	]
	for v in variants:
		_assert_same("sample_spline", SampleSplineNode, func():
			var s = SampleSplineSettings.new()
			for k in v:
				s.set(k, v[k])
			return s, func(): return [_node_stream(nodes)], 7, str(v))

func test_sample_spline_edge_inputs() -> void:
	_assert_same("sample_spline", SampleSplineNode, func(): return SampleSplineSettings.new(), func(): return [_node_stream([])], 0, "empty stream")
	_assert_same("sample_spline", SampleSplineNode, func(): return SampleSplineSettings.new(), func(): return [S.points([Vector3.ZERO])], 0, "no node stream")

# --- create_surface_from_* -------------------------------------------------------------

func test_create_surface_from_spline_points_mode() -> void:
	var p1 := _path(S.square_curve(3.0), Vector3(2, 1, 0))
	var p2 := _path(S.line_curve(Vector3.ZERO, Vector3(5, 0, 0)))
	var nodes := [p1, p2]
	for v in [{}, {"plane": 1}, {"legacy_scale_from_extent": true}, {"include_spline_ref": false}]:
		_assert_same("create_surface_from_spline", CSFSplineNode, func():
			var s = CSFSplineSettings.new()
			for k in v:
				s.set(k, v[k])
			return s, func(): return [_node_stream(nodes)], 0, str(v))
	_assert_same("create_surface_from_spline", CSFSplineNode, func(): return CSFSplineSettings.new(), func(): return [S.points([Vector3.ZERO])], 0, "bad input")

func test_create_surface_from_polygon_points_mode() -> void:
	var make := func():
		var d := S.points([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4), Vector3(10, 0, 0), Vector3(12, 0, 0), Vector3(11, 0, 2)])
		d.registerStream("grp", PackedInt32Array([0, 0, 0, 0, 1, 1, 1]), FlowData.DataType.Int)
		return [d]
	for v in [{}, {"group_attribute": "grp"}, {"plane": 2, "legacy_scale_from_extent": true}]:
		_assert_same("create_surface_from_polygon", CSFPolygonNode, func():
			var s = CSFPolygonSettings.new()
			for k in v:
				s.set(k, v[k])
			return s, make, 0, str(v))
	_assert_same("create_surface_from_polygon", CSFPolygonNode, func(): return CSFPolygonSettings.new(), func(): return [S.points([Vector3.ZERO])], 0, "too few")

# --- projection (physics, default mode) ---------------------------------------------------

func test_projection_physics_mode() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	col.shape = box
	body.add_child(col)
	_owner.add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var make := func(): return [S.points([Vector3(0, 5, 0), Vector3(3, 2, 1), Vector3(50, 5, 0)])]
	for v in [{}, {"discard_misses": true}, {"align_to_normal": false}]:
		_assert_same("projection", ProjectionNode, func():
			var s = ProjectionSettings.new()
			for k in v:
				s.set(k, v[k])
			return s, make, 0, str(v))

# --- difference / intersection / union (points) -------------------------------------------

func test_difference_points_all_ops_and_density_functions() -> void:
	var make := func():
		var a := S.points([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(5, 0, 0), Vector3(9, 0, 0)])
		a.registerStream(FlowData.AttrDensity, PackedFloat32Array([1.0, 0.5, 0.8, 1.0]), FlowData.DataType.Float)
		var b := S.points([Vector3(0.4, 0, 0), Vector3(5.2, 0, 0.3)], [Vector3(1, 1, 1), Vector3(2, 2, 2)])
		return [a, b]
	for op in range(5):
		for fn in range(4):
			_assert_same("difference", DifferenceNode, func():
				var s = DifferenceSettings.new()
				s.operation = op
				s.density_function = fn
				return s, make, 0, "op %d fn %d" % [op, fn])
	_assert_same("difference", DifferenceNode, func(): return DifferenceSettings.new(), func(): return [FlowDataScript.Data.new(), S.points([Vector3.ZERO])], 0, "empty A")
	_assert_same("difference", DifferenceNode, func():
		var s = DifferenceSettings.new()
		s.operation = DifferenceSettings.eOperation.Union
		return s, func(): return [S.points([Vector3.ZERO]), FlowDataScript.Data.new()], 0, "empty B")

# --- filter_data_by_type ----------------------------------------------------------------

func test_filter_data_by_type_legacy_classification() -> void:
	var makers := [
		func(): return [_pts()],
		func(): return [_node_stream([NodePath("A")])],
		func():
			var d := FlowDataScript.Data.new()
			d.registerStream("x", PackedFloat32Array([1, 2]), FlowData.DataType.Float)
			return [d],
		func(): return [FlowDataScript.Data.new()],
		func():
			var d := FlowDataScript.Data.new()
			d.kind = FlowData.Kind.Spline
			d.registerStream("x", PackedFloat32Array([1]), FlowData.DataType.Float)
			return [d],
	]
	for target in range(3):
		for i in makers.size():
			_assert_same("filter_data_by_type", FilterByTypeNode, func():
				var s = FilterByTypeSettings.new()
				s.target_type = target
				return s, makers[i], 0, "target %d input %d" % [target, i])

# --- make_bounds -------------------------------------------------------------------------

func test_make_bounds_points_mode() -> void:
	_assert_same("make_bounds", MakeBoundsNode, func(): return MakeBoundsSettings.new(), func(): return [])
	_assert_same("make_bounds", MakeBoundsNode, func():
		var s = MakeBoundsSettings.new()
		s.size = Vector3(3, 4, 5)
		s.center = Vector3(1, 2, 3)
		return s, func(): return [], 0, "custom")
