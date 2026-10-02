# flow_spatial_shapes_test.gd
# WP2: every FlowSpatial shape, composites, to_points, project, sample_density,
# content_hash stability, immutability and acceleration-grid scaling.
# Headless only: geometry is built in code (Curve3D, ArrayMesh, BoxMesh, PlaneMesh,
# HeightMapShape3D, Image); nothing needs a renderer.
class_name FlowSpatialShapesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")

# --- builders -------------------------------------------------------------------

func _plane_surface(size : float = 10.0, subdiv : int = 9, y : float = 0.0) -> FlowMeshSurface:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv
	return FlowMeshSurface.from_meshes([plane], [Transform3D(Basis.IDENTITY, Vector3(0, y, 0))])

func _line_curve(a : Vector3, b : Vector3) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(a)
	c.add_point(b)
	return c

func _square_curve(half : float) -> Curve3D:
	var c := Curve3D.new()
	for p in [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half), Vector3(-half, 0, -half)]:
		c.add_point(p)
	return c

func _ramp_image() -> Image:
	var img := Image.create(5, 5, false, Image.FORMAT_RF)
	for y in 5:
		for x in 5:
			img.set_pixel(x, y, Color(float(x), 0, 0))
	return img

func _all_shapes() -> Array:
	var hm := HeightMapShape3D.new()
	hm.map_width = 3
	hm.map_depth = 3
	hm.map_data = PackedFloat32Array([0, 0, 0, 1, 1, 1, 2, 2, 2])
	var bm := BoxMesh.new()
	return [
		FlowSplineShape.new(_line_curve(Vector3(-5, 0, 0), Vector3(5, 0, 0)), Transform3D.IDENTITY, false, 1.0),
		FlowPolygonSurface.new(PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])),
		_plane_surface(),
		FlowHeightfieldSurface.from_heightmap_shape(hm),
		FlowHeightfieldSurface.from_image(_ramp_image()),
		FlowBoxVolume.from_aabb(AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))),
		FlowSphereVolume.at(Vector3.ZERO, 1.0),
		FlowMeshVolume.from_meshes([bm], [Transform3D.IDENTITY]),
		FlowPointsVolume.new(PackedVector3Array([Vector3(-1, -1, -1)]), PackedVector3Array([Vector3(1, 1, 1)])),
	]

# --- kinds, bounds, Data typing ------------------------------------------------------

func test_kinds() -> void:
	var kinds := _all_shapes().map(func(s): return s.get_kind())
	assert_array(kinds).is_equal([
		FlowData.Kind.Spline, FlowData.Kind.Surface, FlowData.Kind.Surface, FlowData.Kind.Surface,
		FlowData.Kind.Surface, FlowData.Kind.Volume, FlowData.Kind.Volume, FlowData.Kind.Volume, FlowData.Kind.Volume])

func test_data_kind_follows_shape_and_zero_points_allowed() -> void:
	for s in _all_shapes():
		var d := FlowDataScript.Data.from_shape(s)
		assert_int(d.kind).is_equal(s.get_kind())
		assert_int(d.size()).is_equal(0)
		assert_bool(d.has_shape()).is_true()

func test_data_shape_crosses_duplicate_filter_and_copy_meta() -> void:
	var s := FlowBoxVolume.from_aabb(AABB(Vector3.ZERO, Vector3.ONE))
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(3)
	d.shape = s
	assert_int(d.kind).is_equal(FlowData.Kind.Volume)
	assert_object(d.duplicate().shape).is_same(s)
	assert_object(d.filter(PackedInt32Array([1])).shape).is_same(s)
	assert_object(d.emptyLike().shape).is_same(s)
	var copy := FlowDataScript.Data.new().copy_meta_from(d)
	assert_object(copy.shape).is_same(s)
	assert_int(copy.kind).is_equal(FlowData.Kind.Volume)

func test_bounds_are_world_space() -> void:
	var box := FlowBoxVolume.new(Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)), Vector3(1, 2, 3))
	assert_vector(box.get_bounds().position).is_equal_approx(Vector3(9, -2, -3), Vector3.ONE * 1e-5)
	assert_vector(box.get_bounds().size).is_equal_approx(Vector3(2, 4, 6), Vector3.ONE * 1e-5)
	var plane := _plane_surface(10.0, 1, 3.0)
	assert_float(plane.get_bounds().position.y).is_equal_approx(3.0, 1e-5)
	var sp := FlowSplineShape.new(_line_curve(Vector3.ZERO, Vector3(4, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)), false, 0.5)
	assert_bool(sp.get_bounds().has_point(Vector3(2, 5, 0))).is_true()
	assert_float(sp.get_bounds().position.y).is_equal_approx(4.5, 1e-4)

# --- sample_density -------------------------------------------------------------------

func test_box_density_and_steepness() -> void:
	var hard := FlowBoxVolume.new(Transform3D.IDENTITY, Vector3.ONE, 1.0)
	assert_float(hard.sample_density(Vector3(0.9, 0, 0))).is_equal(1.0)
	assert_float(hard.sample_density(Vector3(1.1, 0, 0))).is_equal(0.0)
	var soft := FlowBoxVolume.new(Transform3D.IDENTITY, Vector3.ONE, 0.5)
	assert_float(soft.sample_density(Vector3(0.25, 0, 0))).is_equal(1.0)
	assert_float(soft.sample_density(Vector3(0.75, 0, 0))).is_equal_approx(0.5, 1e-5)
	# Rotated box: the local frame is honoured.
	var rotated := FlowBoxVolume.new(Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3.ZERO), Vector3(2, 1, 0.1))
	assert_float(rotated.sample_density(Vector3(1.0, 0, -1.0))).is_equal(1.0)
	assert_float(rotated.sample_density(Vector3(1.0, 0, 1.0))).is_equal(0.0)

func test_sphere_density_and_steepness() -> void:
	var s := FlowSphereVolume.at(Vector3(0, 1, 0), 2.0, 0.0)
	assert_float(s.sample_density(Vector3(0, 1, 0))).is_equal(1.0)
	assert_float(s.sample_density(Vector3(1, 1, 0))).is_equal_approx(0.5, 1e-5)
	assert_float(s.sample_density(Vector3(3, 1, 0))).is_equal(0.0)

func test_spline_tube_density() -> void:
	var sp := FlowSplineShape.new(_line_curve(Vector3(-5, 0, 0), Vector3(5, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), false, 1.0, 0.5)
	assert_float(sp.sample_density(Vector3(0, 2, 0))).is_equal(1.0)
	assert_float(sp.sample_density(Vector3(0, 2.75, 0))).is_equal_approx(0.5, 1e-4)
	assert_float(sp.sample_density(Vector3(0, 3.5, 0))).is_equal(0.0)

func test_surface_density_is_footprint() -> void:
	var plane := _plane_surface()
	assert_float(plane.sample_density(Vector3(1, 100, 1))).is_equal(1.0)
	assert_float(plane.sample_density(Vector3(11, 0, 1))).is_equal(0.0)
	var poly := FlowPolygonSurface.new(PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]), Transform3D.IDENTITY, 0.0, 0.5)
	assert_float(poly.sample_density(Vector3(0, 0.4, 0))).is_equal(1.0)
	assert_float(poly.sample_density(Vector3(0, 0.6, 0))).is_equal(0.0)

func test_mesh_volume_inside_test() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 2, 2)
	var mv := FlowMeshVolume.from_meshes([bm], [Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))])
	assert_float(mv.sample_density(Vector3(5.1, 0.2, 0.3))).is_equal(1.0)
	assert_float(mv.sample_density(Vector3(6.5, 0, 0))).is_equal(0.0)
	assert_float(mv.sample_density(Vector3(5, 0.99, 0))).is_equal(1.0)
	assert_float(mv.sample_density(Vector3(5, 1.01, 0))).is_equal(0.0)

func test_points_volume_density() -> void:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(2)
	var pos := d.getVector3Container(FlowData.AttrPosition)
	pos[0] = Vector3.ZERO
	pos[1] = Vector3(10, 0, 0)
	d.registerStream(FlowData.AttrDensity, PackedFloat32Array([1.0, 0.25]), FlowData.DataType.Float)
	var pv := FlowPointsVolume.from_data(d)
	assert_float(pv.sample_density(Vector3(0.4, 0, 0))).is_equal(1.0)
	assert_float(pv.sample_density(Vector3(10.2, 0, 0))).is_equal_approx(0.25, 1e-5)
	assert_float(pv.sample_density(Vector3(5, 0, 0))).is_equal(0.0)

# --- project -------------------------------------------------------------------------

func test_mesh_surface_project_vertical_and_nearest() -> void:
	var plane := _plane_surface(10.0, 9, 2.0)
	var hit := plane.project(Vector3(1.3, 50, 2.1))
	assert_vector(hit.position).is_equal_approx(Vector3(1.3, 2, 2.1), Vector3.ONE * 1e-4)
	assert_vector(hit.normal).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-4)
	assert_float(hit.density).is_equal(1.0)
	# Outside the footprint: nearest point on the mesh.
	var far := plane.project(Vector3(20, 5, 0))
	assert_vector(far.position).is_equal_approx(Vector3(5, 2, 0), Vector3.ONE * 1e-4)

func test_heightfield_from_image_and_shape_project() -> void:
	var hf := FlowHeightfieldSurface.from_image(_ramp_image(), 2.0, 1.0)
	var hit := hf.project(Vector3(1, 50, 0))
	assert_vector(hit.position).is_equal_approx(Vector3(1, 2.5, 0), Vector3.ONE * 1e-4)
	assert_float(hit.normal.x).is_less(0.0)
	assert_bool(hf.project(Vector3(100, 0, 0)).is_empty()).is_true()
	var hm := HeightMapShape3D.new()
	hm.map_width = 3
	hm.map_depth = 3
	hm.map_data = PackedFloat32Array([0, 0, 0, 1, 1, 1, 2, 2, 2])
	var hs := FlowHeightfieldSurface.from_heightmap_shape(hm, Transform3D(Basis.IDENTITY, Vector3(0, 10, 0)))
	var h2 := hs.project_vertical(0.5, 0.5)
	assert_vector(h2.position).is_equal_approx(Vector3(0.5, 11.5, 0.5), Vector3.ONE * 1e-4)

func test_polygon_project() -> void:
	var poly := FlowPolygonSurface.new(PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]), Transform3D(Basis.IDENTITY, Vector3(0, 3, 0)), 0.5)
	assert_vector(poly.project(Vector3(0.2, -7, 0.3)).position).is_equal_approx(Vector3(0.2, 3.5, 0.3), Vector3.ONE * 1e-5)
	assert_bool(poly.project(Vector3(2, 0, 0)).is_empty()).is_true()

func test_volumes_and_splines_do_not_project() -> void:
	assert_bool(FlowBoxVolume.new().project(Vector3.ZERO).is_empty()).is_true()
	assert_bool(FlowSphereVolume.new().project(Vector3.ZERO).is_empty()).is_true()
	assert_bool(FlowSplineShape.new(_line_curve(Vector3.ZERO, Vector3.ONE)).project(Vector3.ZERO).is_empty()).is_true()

# --- composites --------------------------------------------------------------------

func test_density_function_constants_match_difference_settings() -> void:
	assert_int(FlowSpatial.DENSITY_BINARY).is_equal(DifferenceSettings.eDensityFunction.Binary)
	assert_int(FlowSpatial.DENSITY_MINIMUM).is_equal(DifferenceSettings.eDensityFunction.Minimum)
	assert_int(FlowSpatial.DENSITY_MULTIPLY).is_equal(DifferenceSettings.eDensityFunction.Multiply)
	assert_int(FlowSpatial.DENSITY_SUBTRACT).is_equal(DifferenceSettings.eDensityFunction.Subtract)

func test_combine_density_table() -> void:
	var D := FlowSpatial.Op.Difference
	var I := FlowSpatial.Op.Intersection
	var U := FlowSpatial.Op.Union
	var a := 0.8
	var b := 0.5
	var expected := {
		[D, 0]: 0.0, [D, 1]: 0.5, [D, 2]: 0.4, [D, 3]: 0.3,
		[I, 0]: 0.8, [I, 1]: 0.5, [I, 2]: 0.4, [I, 3]: 0.3,
		[U, 0]: 1.0, [U, 1]: 0.8, [U, 2]: 0.9, [U, 3]: 1.0,
	}
	for key in expected:
		assert_float(FlowSpatial.combine_density(key[0], key[1], a, b)).override_failure_message(str(key)).is_equal_approx(expected[key], 1e-5)
	# Difference matches BoundsOverlapUtil.fold_density (the points path of difference).
	for fn in [1, 2, 3]:
		assert_float(FlowSpatial.combine_density(D, fn, a, b)).is_equal_approx(BoundsOverlapUtil.fold_density(a, b, fn, 1, 2, 3), 1e-6)

func test_every_composite_op_and_density_function() -> void:
	var box := FlowBoxVolume.new(Transform3D.IDENTITY, Vector3.ONE, 1.0)
	var soft := FlowSphereVolume.at(Vector3(1, 0, 0), 1.0, 0.0)
	var p := Vector3(0.5, 0, 0)	# box: 1, soft sphere: 0.5
	var dens_a := box.sample_density(p)
	var dens_b := soft.sample_density(p)
	assert_float(dens_b).is_equal_approx(0.5, 1e-5)
	for op in [FlowSpatial.Op.Union, FlowSpatial.Op.Intersection, FlowSpatial.Op.Difference]:
		for fn in [0, 1, 2, 3]:
			var c := FlowCompositeShape.new(op, box, soft, fn)
			assert_float(c.sample_density(p)).is_equal_approx(FlowSpatial.combine_density(op, fn, dens_a, dens_b), 1e-6)
			assert_int(c.get_kind()).is_equal(FlowData.Kind.Volume)

func test_composite_kinds_and_bounds() -> void:
	var plane := _plane_surface()
	var box := FlowBoxVolume.from_aabb(AABB(Vector3(-2, -5, -2), Vector3(4, 10, 4)))
	var inter := FlowCompositeShape.new(FlowSpatial.Op.Intersection, box, plane)
	assert_int(inter.get_kind()).is_equal(FlowData.Kind.Surface)
	assert_vector(inter.get_bounds().size).is_equal_approx(Vector3(4, 0, 4), Vector3.ONE * 1e-5)
	assert_int(FlowCompositeShape.new(FlowSpatial.Op.Difference, plane, box).get_kind()).is_equal(FlowData.Kind.Surface)
	assert_int(FlowCompositeShape.new(FlowSpatial.Op.Union, plane, box).get_kind()).is_equal(FlowData.Kind.Volume)
	assert_int(FlowCompositeShape.new(FlowSpatial.Op.Union, plane, plane).get_kind()).is_equal(FlowData.Kind.Surface)
	var sp := FlowSplineShape.new(_line_curve(Vector3.ZERO, Vector3.ONE))
	assert_int(FlowCompositeShape.new(FlowSpatial.Op.Difference, sp, box).get_kind()).is_equal(FlowData.Kind.Volume)

func test_surface_sampled_inside_volume_before_points_exist() -> void:
	var plane := _plane_surface()
	var box := FlowBoxVolume.from_aabb(AABB(Vector3(-2, -5, -2), Vector3(4, 10, 4)))
	var settings := {"points_per_square_meter": 1.0}
	var full := plane.to_points(settings)
	var inside := FlowCompositeShape.new(FlowSpatial.Op.Intersection, plane, box).to_points(settings)
	var outside := FlowCompositeShape.new(FlowSpatial.Op.Difference, plane, box).to_points(settings)
	assert_int(full.size()).is_equal(100)
	assert_int(inside.size()).is_equal(16)
	assert_int(outside.size()).is_equal(84)
	for p in inside.getVector3Container(FlowData.AttrPosition):
		assert_bool(box.sample_density(p) > 0.0).is_true()

func test_surface_sampled_inside_another_surface() -> void:
	# Landscape (heightfield) restricted to a closed polygon: UE's
	# "sample the landscape inside a closed spline".
	var hf := FlowHeightfieldSurface.from_image(_ramp_image(), 2.0, 1.0)
	var poly := FlowPolygonSurface.from_world_points(PackedVector3Array([Vector3(-2, 0, -2), Vector3(2, 0, -2), Vector3(2, 0, 2), Vector3(-2, 0, 2)]))
	var pts := FlowCompositeShape.new(FlowSpatial.Op.Intersection, hf, poly).to_points({"points_per_square_meter": 1.0})
	assert_int(pts.size()).is_equal(16)
	for p in pts.getVector3Container(FlowData.AttrPosition):
		assert_float(p.y).is_equal_approx(hf.project(p).position.y, 1e-4)

func test_soft_composite_writes_density_and_steepness() -> void:
	var plane := _plane_surface()
	var soft := FlowSphereVolume.at(Vector3.ZERO, 3.0, 0.0)
	var pts := FlowCompositeShape.new(FlowSpatial.Op.Intersection, plane, soft, FlowSpatial.DENSITY_MULTIPLY).to_points({"points_per_square_meter": 1.0, "looseness": 0.0})
	var dens : PackedFloat32Array = pts.getContainerChecked(FlowData.AttrDensity, FlowData.DataType.Float)
	var found_partial := false
	for d in dens:
		assert_bool(d > 0.0 and d <= 1.0).is_true()
		if d < 0.99:
			found_partial = true
	assert_bool(found_partial).is_true()
	assert_bool(pts.hasStream(FlowData.AttrSteepness)).is_true()

func test_union_leaves() -> void:
	var a := FlowSplineShape.new(_line_curve(Vector3.ZERO, Vector3.ONE))
	var b := FlowSplineShape.new(_line_curve(Vector3.ONE, Vector3(2, 0, 0)))
	var c := FlowSplineShape.new(_line_curve(Vector3.ZERO, Vector3(0, 0, 3)))
	var u := FlowCompositeShape.union_of([a, b, c])
	assert_array(u.union_leaves()).is_equal([a, b, c])
	assert_array(a.union_leaves()).is_equal([a])

# --- to_points ------------------------------------------------------------------------

func test_to_points_every_shape_produces_sampler_streams() -> void:
	for s in _all_shapes():
		var settings := {"interval": 0.5, "points_per_square_meter": 4.0, "voxel_size": Vector3(0.5, 0.5, 0.5), "seed": 7}
		var pts : FlowData.Data = s.to_points(settings)
		assert_int(pts.size()).override_failure_message(s.get_type_name()).is_greater(0)
		for stream in [FlowData.AttrPosition, FlowData.AttrRotation, FlowData.AttrSize, FlowData.AttrDensity, FlowData.AttrSeed, FlowData.AttrBoundsMin, FlowData.AttrBoundsMax]:
			assert_bool(pts.hasStream(stream)).override_failure_message("%s %s" % [s.get_type_name(), stream]).is_true()
		assert_object(pts.shape).is_null()
		assert_int(pts.kind).is_equal(FlowData.Kind.Points)

func test_to_points_is_deterministic_and_world_anchored() -> void:
	var small := _plane_surface(10.0)
	var big := _plane_surface(20.0)
	var settings := {"points_per_square_meter": 0.5, "seed": 3}
	var a := small.to_points(settings)
	assert_int(a.content_hash()).is_equal(small.to_points(settings).content_hash())
	# Points of the small plane are a subset of the big plane's (same cells, same jitter).
	var big_set := {}
	for p in big.to_points(settings).getVector3Container(FlowData.AttrPosition):
		big_set[p] = true
	for p in a.getVector3Container(FlowData.AttrPosition):
		assert_bool(big_set.has(p)).is_true()

func test_spline_to_points_spacing() -> void:
	var sp := FlowSplineShape.new(_line_curve(Vector3.ZERO, Vector3(10, 0, 0)))
	var pts := sp.to_points({"interval": 2.0})
	assert_int(pts.size()).is_equal(6)
	assert_vector(pts.getVector3Container(FlowData.AttrPosition)[5]).is_equal_approx(Vector3(10, 0, 0), Vector3.ONE * 1e-3)

func test_count_mode_sampling() -> void:
	var pts := FlowSpatial.sample_surface(_plane_surface(), {"num_points": 25, "seed": 1})
	assert_int(pts.size()).is_equal(25)

func test_sampler_cap_reports_error() -> void:
	var errors := []
	var pts := FlowSpatial.sample_surface(_plane_surface(), {"points_per_square_meter": 1000.0, "max_candidates": 100}, errors)
	assert_int(pts.size()).is_equal(0)
	assert_int(errors.size()).is_equal(1)

# --- immutability and content hash ------------------------------------------------

func test_spline_copies_curve() -> void:
	var c := _line_curve(Vector3.ZERO, Vector3(10, 0, 0))
	var sp := FlowSplineShape.new(c)
	var h := sp.content_hash()
	var before := sp.to_points({"interval": 1.0}).content_hash()
	c.set_point_position(1, Vector3(0, 0, 50))
	assert_int(sp.content_hash()).is_equal(h)
	assert_int(sp.to_points({"interval": 1.0}).content_hash()).is_equal(before)
	assert_int(FlowSplineShape.new(c).content_hash()).is_not_equal(h)

func test_mesh_and_heightfield_copy_geometry() -> void:
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var ms := FlowMeshSurface.from_meshes([am], [Transform3D.IDENTITY])
	var h := ms.content_hash()
	am.clear_surfaces()
	assert_int(ms.get_triangle_count()).is_equal(1)
	assert_int(ms.content_hash()).is_equal(h)
	var heights := PackedFloat32Array([0, 1, 2, 3])
	var hf := FlowHeightfieldSurface.new(heights, 2, 2)
	var hh := hf.content_hash()
	heights[0] = 99.0
	assert_int(hf.content_hash()).is_equal(hh)
	assert_float(hf.get_height(0, 0)).is_equal(0.0)

func test_content_hash_reflects_geometry_and_transform() -> void:
	var a := _all_shapes()
	var b := _all_shapes()
	for i in a.size():
		assert_int(a[i].content_hash()).override_failure_message(a[i].get_type_name()).is_equal(b[i].content_hash())
	var t1 := Transform3D(Basis.IDENTITY, Vector3(1, 0, 0))
	assert_int(FlowBoxVolume.new(t1).content_hash()).is_not_equal(FlowBoxVolume.new().content_hash())
	assert_int(FlowSphereVolume.new(t1).content_hash()).is_not_equal(FlowSphereVolume.new().content_hash())
	var c := _line_curve(Vector3.ZERO, Vector3.ONE)
	assert_int(FlowSplineShape.new(c, t1).content_hash()).is_not_equal(FlowSplineShape.new(c).content_hash())
	assert_int(_plane_surface(10, 1, 1.0).content_hash()).is_not_equal(_plane_surface(10, 1, 0.0).content_hash())
	var box := FlowBoxVolume.new()
	var sph := FlowSphereVolume.new()
	assert_int(FlowCompositeShape.new(FlowSpatial.Op.Union, box, sph).content_hash()).is_not_equal(FlowCompositeShape.new(FlowSpatial.Op.Intersection, box, sph).content_hash())
	assert_int(FlowCompositeShape.new(FlowSpatial.Op.Union, box, sph, 1).content_hash()).is_not_equal(FlowCompositeShape.new(FlowSpatial.Op.Union, box, sph, 2).content_hash())
	# Data.content_hash includes the shape.
	var d1 := FlowDataScript.Data.from_shape(FlowBoxVolume.new())
	var d2 := FlowDataScript.Data.from_shape(FlowBoxVolume.new(t1))
	assert_int(d1.content_hash()).is_not_equal(d2.content_hash())
	assert_int(d1.content_hash()).is_equal(FlowDataScript.Data.from_shape(FlowBoxVolume.new()).content_hash())

# --- acceleration (benchmark-style scaling assertions) ---------------------------------
# Benchmark (build container, Godot 4.6 headless): 1000 vertical projections take
# 11 ms on 200 triangles, 12.5 ms on 20 000 and 13.4 ms on 180 000; the most
# triangles any single query tested was 8, 18 and 18. A 1025x1025 heightfield
# answers 1000 queries in about 4 ms (direct indexing). A brute-force projection
# would test every triangle per sample (200 / 20 000 / 180 000).

func test_mesh_grid_query_cost_does_not_scale_with_triangle_count() -> void:
	var small := _plane_surface(10.0, 9)		# 200 triangles
	var large := _plane_surface(10.0, 99)		# 20000 triangles
	assert_int(large.get_triangle_count()).is_equal(20000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var max_small := 0
	var max_large := 0
	for i in 200:
		var x := rng.randf_range(-4.9, 4.9)
		var z := rng.randf_range(-4.9, 4.9)
		max_small = maxi(max_small, small.grid.count_column_candidates(x, z))
		max_large = maxi(max_large, large.grid.count_column_candidates(x, z))
	assert_int(max_small).is_less_equal(16)
	assert_int(max_large).is_less_equal(16)
	# Time: 1000 vertical projections on 20k triangles stays well below brute force.
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		large.project_vertical(rng.randf_range(-4.9, 4.9), rng.randf_range(-4.9, 4.9))
	var elapsed_ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_float(elapsed_ms).is_less(2000.0)

func test_nearest_matches_brute_force() -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 24
	sphere.rings = 12
	var grid := FlowTriangleGrid.new(FlowTriangleGrid.mesh_world_vertices(sphere, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 40:
		var p := Vector3(rng.randf_range(-3, 5), rng.randf_range(-2, 6), rng.randf_range(-1, 7))
		var best := INF
		for t in grid.tri_count:
			var q := FlowSpatial.closest_point_on_triangle(p, grid.vertices[t * 3], grid.vertices[t * 3 + 1], grid.vertices[t * 3 + 2])
			best = minf(best, p.distance_to(q))
		assert_float(grid.nearest(p).distance).is_equal_approx(best, 1e-5)

# Off-footprint projection falls back to nearest(); with the ring and cell lower
# bounds it stays local. Measured: 200 queries on a 20k-triangle plane went from
# 24 s (ring bound without the projection term) to about 3 ms, same as on 200 triangles.
func test_nearest_off_mesh_stays_local() -> void:
	var large := _plane_surface(10.0, 99)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var t0 := Time.get_ticks_usec()
	for i in 200:
		var hit := large.project(Vector3(rng.randf_range(10, 20), 3, rng.randf_range(-20, 20)))
		assert_float(hit.position.x).is_equal_approx(5.0, 1e-4)
	assert_float((Time.get_ticks_usec() - t0) / 1000.0).is_less(1000.0)

func test_mesh_volume_uses_column_cells() -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 64
	sphere.rings = 32
	var mv := FlowMeshVolume.from_meshes([sphere], [Transform3D.IDENTITY])
	assert_int(mv.grid.tri_count).is_greater(3000)
	assert_int(mv.grid.count_column_candidates(0.1, 0.1)).is_less(mv.grid.tri_count / 20)
	assert_float(mv.sample_density(Vector3(0.1, 0.1, 0.1))).is_equal(1.0)
	assert_float(mv.sample_density(Vector3(0.6, 0, 0))).is_equal(0.0)

func test_heightfield_query_is_direct_index() -> void:
	var w := 257
	var values := PackedFloat32Array()
	values.resize(w * w)
	for j in w:
		for i in w:
			values[j * w + i] = float(i + j) * 0.01
	var hf := FlowHeightfieldSurface.new(values, w, w, 1.0)
	var hit := hf.project_vertical(100.5, 20.25)
	assert_float(hit.position.y).is_equal_approx((100.5 + 20.25) * 0.01, 1e-4)

func test_polygon_band_tests_do_not_scale_with_edges() -> void:
	var pts := PackedVector2Array()
	for i in 1000:
		var a := TAU * i / 1000.0
		pts.append(Vector2(cos(a), sin(a)) * 10.0)
	var poly := FlowPolygonSurface.new(pts)
	assert_int(poly.count_edge_tests(0, 0)).is_less(100)
	assert_float(poly.sample_density(Vector3(0, 0, 0))).is_equal(1.0)
	assert_float(poly.sample_density(Vector3(9.9, 0, 0))).is_equal(1.0)
	assert_float(poly.sample_density(Vector3(10.1, 0, 0))).is_equal(0.0)
