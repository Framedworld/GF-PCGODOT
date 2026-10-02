# spatial_consumer_nodes_test.gd
# WP2 consumers of spatial data: surface_sampler, volume_sampler, sample_spline,
# difference / intersection / union, projection (Surface mode),
# create_surface_from_spline / polygon (Shape mode) and filter_data_by_type.
class_name SpatialConsumerNodesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spatial/support/spatial_test_support.gd")

const SurfaceSamplerNode = preload("res://addons/flow_nodes_editor/nodes/surface_sampler.gd")
const SurfaceSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/surface_sampler_settings.gd")
const VolumeSamplerNode = preload("res://addons/flow_nodes_editor/nodes/volume_sampler.gd")
const VolumeSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/volume_sampler_settings.gd")
const SampleSplineNode = preload("res://addons/flow_nodes_editor/nodes/sample_spline.gd")
const SampleSplineSettings = preload("res://addons/flow_nodes_editor/nodes/sample_spline_settings.gd")
const DifferenceNode = preload("res://addons/flow_nodes_editor/nodes/difference.gd")
const IntersectionNode = preload("res://addons/flow_nodes_editor/nodes/intersection.gd")
const UnionNode = preload("res://addons/flow_nodes_editor/nodes/union.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")
const ProjectionNode = preload("res://addons/flow_nodes_editor/nodes/projection.gd")
const ProjectionSettings = preload("res://addons/flow_nodes_editor/nodes/projection_settings.gd")
const CSFSplineNode = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_spline.gd")
const CSFSplineSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_spline_settings.gd")
const CSFPolygonNode = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_polygon.gd")
const CSFPolygonSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_polygon_settings.gd")
const FilterByTypeNode = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_type.gd")
const FilterByTypeSettings = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_type_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	add_child(_owner)

func _plane_surface(size : float = 10.0, y : float = 0.0) -> FlowMeshSurface:
	return FlowMeshSurface.from_meshes([S.plane_mesh(size, 9)], [Transform3D(Basis.IDENTITY, Vector3(0, y, 0))])

func _shape_data(shape : FlowSpatial) -> FlowData.Data:
	return FlowDataScript.Data.from_shape(shape)

func _box(center : Vector3, half : Vector3, steep : float = 1.0) -> FlowBoxVolume:
	return FlowBoxVolume.new(Transform3D(Basis.IDENTITY, center), half, steep)

func _positions(d : FlowData.Data) -> PackedVector3Array:
	return d.getVector3Container(FlowData.AttrPosition)

func _densities(d : FlowData.Data) -> PackedFloat32Array:
	return d.getContainerChecked(FlowData.AttrDensity, FlowData.DataType.Float)

# --- surface_sampler -------------------------------------------------------------------

func test_surface_sampler_samples_surface_data() -> void:
	var s = SurfaceSamplerSettings.new()
	s.points_per_square_meter = 1.0
	var node = S.run(SurfaceSamplerNode, s, [_shape_data(_plane_surface(10.0, 3.0))])
	var d := S.output(node)
	assert_str(node.err).is_empty()
	assert_int(d.size()).is_equal(100)
	for p in _positions(d):
		assert_float(p.y).is_equal_approx(3.0, 1e-4)
	for stream in [FlowData.AttrDensity, FlowData.AttrSeed, FlowData.AttrNormal, FlowData.AttrSteepness, FlowData.AttrBoundsMin]:
		assert_bool(d.hasStream(stream)).is_true()
	assert_object(d.shape).is_null()
	S.release(node)

func test_surface_sampler_count_mode_and_seed() -> void:
	var s = SurfaceSamplerSettings.new()
	s.shape_sampling = SurfaceSamplerSettings.eShapeSampling.Count
	s.num_points = 33
	var a = S.run(SurfaceSamplerNode, s, [_shape_data(_plane_surface())])
	var b = S.run(SurfaceSamplerNode, s, [_shape_data(_plane_surface())], null, 42)
	assert_int(S.output(a).size()).is_equal(33)
	assert_int(S.output(a).content_hash()).is_not_equal(S.output(b).content_hash())
	S.release(a)
	S.release(b)

func test_surface_sampler_composite_inside_volume_before_points() -> void:
	# UE: sample the landscape only inside a volume, no points needed first.
	var comp := FlowCompositeShape.new(FlowSpatial.Op.Intersection, _plane_surface(), _box(Vector3.ZERO, Vector3(2, 5, 2)))
	var s = SurfaceSamplerSettings.new()
	s.points_per_square_meter = 1.0
	var node = S.run(SurfaceSamplerNode, s, [_shape_data(comp)])
	assert_int(S.output(node).size()).is_equal(16)
	S.release(node)

func test_surface_sampler_rejects_non_surface() -> void:
	var node = S.run(SurfaceSamplerNode, SurfaceSamplerSettings.new(), [_shape_data(_box(Vector3.ZERO, Vector3.ONE))])
	assert_str(node.err).contains("surface")
	S.release(node)

func test_surface_sampler_bounding_shape_pin() -> void:
	var s = SurfaceSamplerSettings.new()
	var node = SurfaceSamplerNode.new()
	node.settings = s
	assert_int(node.getMeta().ins.size()).is_equal(1)
	s.use_bounding_shape = true
	assert_int(node.getMeta().ins.size()).is_equal(2)
	S.release(node)
	s.points_per_square_meter = 1.0
	var bound := _shape_data(_box(Vector3(2, 0, 2), Vector3(1, 5, 1)))
	node = S.run(SurfaceSamplerNode, s, [_shape_data(_plane_surface()), bound])
	assert_int(S.output(node).size()).is_equal(4)
	S.release(node)
	# Point input + bounding shape: legacy samples kept only inside the bound.
	var region := S.points([Vector3.ZERO], [Vector3(10, 0.1, 10)])
	s.num_points = 200
	node = S.run(SurfaceSamplerNode, s, [region, bound])
	var d := S.output(node)
	assert_int(d.size()).is_greater(0)
	assert_int(d.size()).is_less(200)
	for p in _positions(d):
		assert_bool(absf(p.x - 2) <= 1.0 and absf(p.z - 2) <= 1.0).is_true()
	S.release(node)
	# Bounding shape from points (their boxes).
	node = S.run(SurfaceSamplerNode, s, [_shape_data(_plane_surface()), S.points([Vector3(0, 0, 0)], [Vector3(2, 2, 2)])])
	assert_int(S.output(node).size()).is_equal(4)
	S.release(node)

# --- volume_sampler -------------------------------------------------------------------------

func test_volume_sampler_samples_volume_data() -> void:
	var s = VolumeSamplerSettings.new()
	s.voxel_size = Vector3(0.5, 0.5, 0.5)
	var node = S.run(VolumeSamplerNode, s, [_shape_data(_box(Vector3.ZERO, Vector3.ONE))])
	var d := S.output(node)
	assert_int(d.size()).is_equal(64)
	assert_bool(d.hasStream(FlowData.AttrSeed)).is_true()
	S.release(node)
	var sphere_minus_box := FlowCompositeShape.new(FlowSpatial.Op.Difference, FlowSphereVolume.at(Vector3.ZERO, 2.0), _box(Vector3(2, 0, 0), Vector3(2, 3, 3)))
	node = S.run(VolumeSamplerNode, s, [_shape_data(sphere_minus_box)])
	for p in _positions(S.output(node)):
		assert_float(p.x).is_less(0.0)
	S.release(node)

# --- sample_spline --------------------------------------------------------------------------

func test_sample_spline_shape_matches_path_input() -> void:
	var path := Path3D.new()
	path.curve = S.line_curve(Vector3.ZERO, Vector3(10, 0, 4))
	path.position = Vector3(1, 2, 3)
	_owner.add_child(path)
	var node_stream := FlowDataScript.Data.new()
	node_stream.registerStream("node", [path], FlowData.DataType.NodePath)
	for v in [{}, {"sample_segments_centers": true}, {"fill_curve": true}, {"sampling_mode": SampleSplineSettings.eSamplingMode.Random}]:
		var s = SampleSplineSettings.new()
		for k in v:
			s.set(k, v[k])
		var legacy = S.run(SampleSplineNode, s, [node_stream])
		var shaped = S.run(SampleSplineNode, s, [_shape_data(FlowSplineShape.from_path(path))])
		assert_bool(S.same_data(S.output(legacy), S.output(shaped))).override_failure_message(str(v)).is_true()
		S.release(legacy)
		S.release(shaped)
	# The shape's curve copy is never re-baked by the sampler.
	var shape := FlowSplineShape.from_path(path)
	var interval := shape.curve.bake_interval
	var n = S.run(SampleSplineNode, SampleSplineSettings.new(), [_shape_data(shape)])
	assert_float(shape.curve.bake_interval).is_equal(interval)
	S.release(n)

func test_sample_spline_union_of_splines_and_errors() -> void:
	var a := FlowSplineShape.new(S.line_curve(Vector3.ZERO, Vector3(4, 0, 0)))
	var b := FlowSplineShape.new(S.line_curve(Vector3(0, 0, 10), Vector3(4, 0, 10)))
	var s = SampleSplineSettings.new()
	s.uniform_interval = 1.0
	var na = S.run(SampleSplineNode, s, [_shape_data(a)])
	var nu = S.run(SampleSplineNode, s, [_shape_data(FlowCompositeShape.union_of([a, b]))])
	assert_int(S.output(nu).size()).is_equal(S.output(na).size() * 2)
	S.release(na)
	S.release(nu)
	var bad = S.run(SampleSplineNode, s, [_shape_data(_plane_surface())])
	assert_str(bad.err).contains("spline")
	S.release(bad)
	var empty := FlowDataScript.Data.new()
	empty.kind = FlowData.Kind.Spline
	var ne = S.run(SampleSplineNode, s, [empty])
	assert_str(ne.err).is_empty()
	assert_int(S.output(ne).size()).is_equal(0)
	S.release(ne)

# --- difference / intersection / union ---------------------------------------------------------

func _diff(script, a : FlowData.Data, b : FlowData.Data, op : int = 0, fn : int = 0) -> FlowData.Data:
	var s = DifferenceSettings.new()
	s.operation = op
	s.density_function = fn
	var node = S.run(script, s, [a, b])
	assert_str(node.err).is_empty()
	var d := S.output(node)
	S.release(node)
	return d

func test_shape_with_shape_gives_composites() -> void:
	var plane := _plane_surface()
	var box := _box(Vector3.ZERO, Vector3(2, 5, 2))
	var expected := {
		DifferenceSettings.eOperation.A_Minus_B: [FlowSpatial.Op.Difference, plane, box],
		DifferenceSettings.eOperation.B_Minus_A: [FlowSpatial.Op.Difference, box, plane],
		DifferenceSettings.eOperation.Intersection: [FlowSpatial.Op.Intersection, plane, box],
		DifferenceSettings.eOperation.Union: [FlowSpatial.Op.Union, plane, box],
	}
	for op in expected:
		for fn in range(4):
			var a := _shape_data(plane)
			a.tags = PackedStringArray(["ground"])
			var d := _diff(DifferenceNode, a, _shape_data(box), op, fn)
			assert_object(d.shape).is_instanceof(FlowCompositeShape)
			assert_int(d.shape.op).is_equal(expected[op][0])
			assert_object(d.shape.a).is_same(expected[op][1])
			assert_object(d.shape.b).is_same(expected[op][2])
			assert_int(d.shape.density_function).is_equal(fn)
			assert_int(d.size()).is_equal(0)
	var sym := _diff(DifferenceNode, _shape_data(plane), _shape_data(box), DifferenceSettings.eOperation.SymmetricDifference)
	assert_int(sym.shape.op).is_equal(FlowSpatial.Op.Union)
	assert_float(sym.shape.sample_density(Vector3(4, 0, 4))).is_equal(1.0)
	assert_float(sym.shape.sample_density(Vector3(0, 0, 0))).is_equal(0.0)

func test_intersection_and_union_nodes_route_shapes() -> void:
	var plane := _plane_surface()
	var box := _box(Vector3.ZERO, Vector3(2, 5, 2))
	assert_int(_diff(IntersectionNode, _shape_data(plane), _shape_data(box)).shape.op).is_equal(FlowSpatial.Op.Intersection)
	assert_int(_diff(UnionNode, _shape_data(plane), _shape_data(box)).shape.op).is_equal(FlowSpatial.Op.Union)

func _row() -> FlowData.Data:
	var d := S.points([Vector3(0, 0, 0), Vector3(1.5, 0, 0), Vector3(3, 0, 0), Vector3(10, 0, 0)])
	d.registerStream(FlowData.AttrDensity, PackedFloat32Array([1.0, 1.0, 0.6, 1.0]), FlowData.DataType.Float)
	d.tags = PackedStringArray(["trees"])
	return d

func test_points_minus_shape_binary_and_density_functions() -> void:
	# Soft sphere at x=0, r=3, steepness 0: density 1, 0.5, 0, 0 at x = 0, 1.5, 3, 10.
	var sphere := FlowSphereVolume.at(Vector3.ZERO, 3.0, 0.0)
	var binary := _diff(DifferenceNode, _row(), _shape_data(sphere))
	assert_array(Array(_positions(binary))).is_equal([Vector3(3, 0, 0), Vector3(10, 0, 0)])
	assert_array(Array(binary.tags)).is_equal(["trees"])
	assert_object(binary.shape).is_null()
	var sub := _diff(DifferenceNode, _row(), _shape_data(sphere), 0, DifferenceSettings.eDensityFunction.Subtract)
	assert_int(sub.size()).is_equal(4)
	var dens := _densities(sub)
	assert_float(dens[0]).is_equal_approx(0.0, 1e-5)
	assert_float(dens[1]).is_equal_approx(0.5, 1e-5)
	assert_float(dens[2]).is_equal_approx(0.6, 1e-5)
	var mul := _densities(_diff(DifferenceNode, _row(), _shape_data(sphere), 0, DifferenceSettings.eDensityFunction.Multiply))
	assert_float(mul[1]).is_equal_approx(0.5, 1e-5)
	var mn := _densities(_diff(DifferenceNode, _row(), _shape_data(sphere), 0, DifferenceSettings.eDensityFunction.Minimum))
	assert_float(mn[0]).is_equal_approx(0.0, 1e-5)
	# B_Minus_A with points on B: same as A_Minus_B with sides swapped.
	var swapped := _diff(DifferenceNode, _shape_data(sphere), _row(), DifferenceSettings.eOperation.B_Minus_A)
	assert_bool(S.same_data(swapped, binary)).is_true()

func test_points_intersect_and_union_shape() -> void:
	var sphere := FlowSphereVolume.at(Vector3.ZERO, 3.0, 0.0)
	var inter := _diff(DifferenceNode, _row(), _shape_data(sphere), DifferenceSettings.eOperation.Intersection)
	assert_int(inter.size()).is_equal(2)
	var inter_mul := _diff(DifferenceNode, _shape_data(sphere), _row(), DifferenceSettings.eOperation.Intersection, DifferenceSettings.eDensityFunction.Multiply)
	assert_float(_densities(inter_mul)[1]).is_equal_approx(0.5, 1e-5)
	assert_float(_densities(inter_mul)[3]).is_equal(0.0)
	var uni := _diff(DifferenceNode, _row(), _shape_data(sphere), DifferenceSettings.eOperation.Union)
	assert_array(Array(_densities(uni))).is_equal([1.0, 1.0, 1.0, 1.0])
	var uni_min := _diff(DifferenceNode, _row(), _shape_data(sphere), DifferenceSettings.eOperation.Union, DifferenceSettings.eDensityFunction.Minimum)
	assert_float(_densities(uni_min)[2]).is_equal_approx(0.6, 1e-5)
	var sym := _diff(DifferenceNode, _row(), _shape_data(sphere), DifferenceSettings.eOperation.SymmetricDifference)
	assert_int(sym.size()).is_equal(2)

func test_shape_minus_points_is_composite_with_points_volume() -> void:
	var cutter := S.points([Vector3(0, 0, 0)], [Vector3(4, 4, 4)])
	var d := _diff(DifferenceNode, _shape_data(_plane_surface()), cutter)
	assert_object(d.shape.b).is_instanceof(FlowPointsVolume)
	var pts := d.shape.to_points({"points_per_square_meter": 1.0})
	assert_int(pts.size()).is_equal(84)
	# Empty cutter: the shape passes through.
	var through := _diff(DifferenceNode, _shape_data(_plane_surface()), FlowDataScript.Data.new())
	assert_object(through.shape).is_instanceof(FlowMeshSurface)

func test_forest_minus_road_spline_soft_edge() -> void:
	# UE: Surface Sampler -> Difference(road spline) with a soft density function.
	var s = SurfaceSamplerSettings.new()
	s.points_per_square_meter = 4.0
	s.looseness = 0.0
	var forest_node = S.run(SurfaceSamplerNode, s, [_shape_data(_plane_surface(20.0))])
	var forest := S.output(forest_node)
	var road := FlowSplineShape.new(S.line_curve(Vector3(-10, 0, 0), Vector3(10, 0, 0)), Transform3D.IDENTITY, false, 2.0, 0.5)
	var out := _diff(DifferenceNode, forest, _shape_data(road), 0, DifferenceSettings.eDensityFunction.Subtract)
	assert_int(out.size()).is_equal(forest.size())
	var pos := _positions(out)
	var dens := _densities(out)
	var saw_partial := false
	for i in pos.size():
		var dz := absf(pos[i].z)
		if dz <= 1.0:
			assert_float(dens[i]).is_equal(0.0)
		elif dz >= 2.0:
			assert_float(dens[i]).is_equal(1.0)
		else:
			saw_partial = saw_partial or (dens[i] > 0.0 and dens[i] < 1.0)
	assert_bool(saw_partial).is_true()
	S.release(forest_node)

# --- projection (Surface mode) ---------------------------------------------------------------

func test_projection_surface_mode() -> void:
	var s = ProjectionSettings.new()
	var node = ProjectionNode.new()
	node.settings = s
	assert_int(node.getMeta().ins.size()).is_equal(1)
	s.projection_mode = ProjectionSettings.eProjectionMode.Surface
	assert_int(node.getMeta().ins.size()).is_equal(2)
	S.release(node)
	var hf := FlowHeightfieldSurface.new(PackedFloat32Array([0, 2, 0, 2]), 2, 2, 10.0)
	var pts := S.points([Vector3(5, 50, 5), Vector3(0, -3, 0), Vector3(50, 0, 0)])
	node = S.run(ProjectionNode, s, [pts, _shape_data(hf)], null)	# no owner, no physics
	var d := S.output(node)
	assert_str(node.err).is_empty()
	assert_float(_positions(d)[0].y).is_equal_approx(1.0, 1e-4)
	assert_float(_positions(d)[1].y).is_equal_approx(0.0, 1e-4)
	assert_vector(_positions(d)[2]).is_equal(Vector3(50, 0, 0))	# miss kept
	assert_bool(d.hasStream(FlowData.AttrNormal)).is_true()
	S.release(node)
	s.discard_misses = true
	node = S.run(ProjectionNode, s, [pts, _shape_data(hf)], null)
	assert_int(S.output(node).size()).is_equal(2)
	S.release(node)

func test_projection_surface_density_and_targets() -> void:
	var s = ProjectionSettings.new()
	s.projection_mode = ProjectionSettings.eProjectionMode.Surface
	var soft := FlowCompositeShape.new(FlowSpatial.Op.Intersection, _plane_surface(), FlowSphereVolume.at(Vector3.ZERO, 4.0, 0.0), FlowSpatial.DENSITY_MULTIPLY)
	var node = S.run(ProjectionNode, s, [S.points([Vector3(0, 5, 0), Vector3(2, 5, 0), Vector3(4.5, 5, 0)]), _shape_data(soft)])
	var d := S.output(node)
	assert_float(_densities(d)[0]).is_equal_approx(1.0, 1e-5)
	assert_float(_densities(d)[1]).is_equal_approx(0.5, 1e-5)
	assert_float(_positions(d)[2].y).is_equal(5.0)	# density 0 = miss
	S.release(node)
	# A scan_meshes style 'node' stream works as a target.
	var mi := MeshInstance3D.new()
	mi.mesh = S.plane_mesh(10.0, 1)
	mi.position = Vector3(0, 7, 0)
	_owner.add_child(mi)
	var nodes := FlowDataScript.Data.new()
	nodes.registerStream("node", [mi], FlowData.DataType.NodeMesh)
	node = S.run(ProjectionNode, s, [S.points([Vector3(1, 0, 1)]), nodes])
	assert_float(_positions(S.output(node))[0].y).is_equal_approx(7.0, 1e-4)
	S.release(node)
	node = S.run(ProjectionNode, s, [S.points([Vector3.ZERO]), _shape_data(_box(Vector3.ZERO, Vector3.ONE))])
	assert_str(node.err).contains("surface")
	S.release(node)
	node = S.run(ProjectionNode, s, [S.points([Vector3.ZERO])])
	assert_str(node.err).contains("not connected")
	S.release(node)

# --- create_surface_from_* (Shape mode) ---------------------------------------------------------

func test_create_surface_from_spline_shape_mode() -> void:
	var path := Path3D.new()
	path.curve = S.square_curve(3.0)
	path.position = Vector3(10, 1, 0)
	_owner.add_child(path)
	var stream := FlowDataScript.Data.new()
	stream.registerStream("node", [path], FlowData.DataType.NodePath)
	var s = CSFSplineSettings.new()
	s.output_mode = CSFSplineSettings.eOutputMode.Shape
	var node = S.run(CSFSplineNode, s, [stream])
	var d := S.output(node)
	assert_object(d.shape).is_instanceof(FlowPolygonSurface)
	assert_int(d.kind).is_equal(FlowData.Kind.Surface)
	assert_float(d.get_data_attr("surface_area")).is_equal_approx(36.0, 0.1)
	assert_float(d.shape.sample_density(Vector3(10, 100, 0))).is_equal(1.0)
	assert_float(d.shape.sample_density(Vector3(14, 1, 0))).is_equal(0.0)
	S.release(node)
	# Spline spatial data input works in both modes.
	var spline := _shape_data(FlowSplineShape.from_path(path))
	node = S.run(CSFSplineNode, s, [spline])
	assert_object(S.output(node).shape).is_instanceof(FlowPolygonSurface)
	S.release(node)
	var points_mode = S.run(CSFSplineNode, CSFSplineSettings.new(), [spline])
	var legacy_mode = S.run(CSFSplineNode, CSFSplineSettings.new(), [stream])
	assert_vector(_positions(S.output(points_mode))[0]).is_equal_approx(_positions(S.output(legacy_mode))[0], Vector3.ONE * 1e-5)
	S.release(points_mode)
	S.release(legacy_mode)
	# Landscape inside the closed spline: intersect, then sample.
	var surf_node = S.run(CSFSplineNode, s, [stream])
	var inside := FlowCompositeShape.new(FlowSpatial.Op.Intersection, _plane_surface(40.0), S.output(surf_node).shape)
	var sampled := inside.to_points({"points_per_square_meter": 1.0})
	assert_int(sampled.size()).is_equal(36)
	S.release(surf_node)

func test_create_surface_from_polygon_shape_mode_groups_and_merge() -> void:
	var d := S.points([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4), Vector3(0, 0, 4), Vector3(10, 0, 0), Vector3(12, 0, 0), Vector3(11, 0, 2)])
	d.registerStream("grp", PackedInt32Array([0, 0, 0, 0, 1, 1, 1]), FlowData.DataType.Int)
	var s = CSFPolygonSettings.new()
	s.output_mode = CSFPolygonSettings.eOutputMode.Shape
	s.group_attribute = "grp"
	var node = S.run(CSFPolygonNode, s, [d])
	var outs := S.outputs(node)
	assert_int(outs.size()).is_equal(2)
	assert_float(outs[0].get_data_attr("surface_area")).is_equal_approx(16.0, 1e-4)
	assert_float(outs[1].shape.sample_density(Vector3(11, 0, 0.5))).is_equal(1.0)
	S.release(node)
	s.merge_shapes = true
	node = S.run(CSFPolygonNode, s, [d])
	outs = S.outputs(node)
	assert_int(outs.size()).is_equal(1)
	assert_float(outs[0].get_data_attr("surface_area")).is_equal_approx(18.0, 1e-4)
	assert_float(outs[0].shape.sample_density(Vector3(2, 0, 2))).is_equal(1.0)
	S.release(node)

# --- filter_data_by_type ------------------------------------------------------------------------

func _classify(d : FlowData.Data, target : int) -> bool:
	var s = FilterByTypeSettings.new()
	s.target_type = target
	var node = S.run(FilterByTypeNode, s, [d])
	var inside := S.output(node, 0)
	S.release(node)
	return inside == d

func test_filter_data_by_type_classifies_by_shape() -> void:
	var T = FilterByTypeSettings.eTargetType
	var spline := _shape_data(FlowSplineShape.new(S.line_curve(Vector3.ZERO, Vector3.ONE)))
	var merged := _shape_data(FlowCompositeShape.union_of([FlowSplineShape.new(S.line_curve(Vector3.ZERO, Vector3.ONE)), FlowSplineShape.new(S.line_curve(Vector3.ONE, Vector3(2, 0, 0)))]))
	var surface := _shape_data(_plane_surface())
	var volume := _shape_data(_box(Vector3.ZERO, Vector3.ONE))
	var composite_surface := _shape_data(FlowCompositeShape.new(FlowSpatial.Op.Intersection, _plane_surface(), _box(Vector3.ZERO, Vector3.ONE)))
	# A shape-bearing Data that also has point streams is still classified by its shape.
	var shaped_points := S.points([Vector3.ZERO])
	shaped_points.shape = _box(Vector3.ZERO, Vector3.ONE)
	var table := [
		[spline, [T.SplineData, T.SpatialData]],
		[merged, [T.SplineData, T.SpatialData]],
		[surface, [T.SurfaceData, T.SpatialData]],
		[composite_surface, [T.SurfaceData, T.SpatialData]],
		[volume, [T.VolumeData, T.SpatialData]],
		[shaped_points, [T.VolumeData, T.SpatialData]],
		[S.points([Vector3.ZERO]), [T.PointData]],
	]
	for row in table:
		for target in T.values():
			assert_bool(_classify(row[0], target)).override_failure_message("%s target %d" % [row[0].shape, target]).is_equal(target in row[1])
