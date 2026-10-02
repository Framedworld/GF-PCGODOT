# wp13_r2_spatial_review_test.gd
# Round 2 adversarial review (WP13, reviewer R2) of the spatial shapes, the
# terrain adapters and the nodes that use them. Every test here was written
# before its fix: the "regression" tests failed on the reviewed code and name
# the bug in their comment; the "coverage" tests compare the accelerated paths
# with brute force on random (seeded, deterministic) cases.
class_name WP13R2SpatialReviewTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spatial/support/spatial_test_support.gd")
const Fakes = preload("res://tests/terrain/support/fake_terrain_plugins.gd")
const DifferenceNode = preload("res://addons/flow_nodes_editor/nodes/difference.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")
const ToPoint = preload("res://addons/flow_nodes_editor/nodes/to_point.gd")
const ToPointSettings = preload("res://addons/flow_nodes_editor/nodes/to_point_settings.gd")
const GetVolumeData = preload("res://addons/flow_nodes_editor/nodes/get_volume_data.gd")
const GetVolumeDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_volume_data_settings.gd")
const GetSplineData = preload("res://addons/flow_nodes_editor/nodes/get_spline_data.gd")
const GetSplineDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_spline_data_settings.gd")
const GetSurfaceData = preload("res://addons/flow_nodes_editor/nodes/get_surface_data.gd")
const GetSurfaceDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_surface_data_settings.gd")
const ProjectionNode = preload("res://addons/flow_nodes_editor/nodes/projection.gd")

const PC : int = 0	# DifferenceSettings.eOverlapMode.PointCenter
const BB : int = 1	# DifferenceSettings.eOverlapMode.BoundsBox

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	add_child(_owner)

func _grouped(node : Node, group : String) -> Node:
	_owner.add_child(node)
	if group != "":
		node.add_to_group(group)
	return node

func _diff(points : FlowData.Data, shape : FlowSpatial, op : int, fn : int, om : int) -> FlowData.Data:
	var s = DifferenceSettings.new()
	s.operation = op
	s.density_function = fn
	s.overlap_mode = om
	var node = S.run(DifferenceNode, s, [points, FlowDataScript.Data.from_shape(shape)])
	assert_str(node.err).is_empty()
	return S.output(node)

func _positions(d : FlowData.Data) -> Array:
	return Array(d.getVector3Container(FlowData.AttrPosition))

## Depth of a composite tree (a leaf is 1).
func _depth(shape : FlowSpatial) -> int:
	if shape is FlowCompositeShape:
		return 1 + maxi(_depth(shape.a), _depth(shape.b))
	return 1

# --- Regression: sampler candidate counts overflowed int64 ----------------------------------
#
# sample_volume multiplied three int64 voxel counts; a 2^22-voxel-wide sphere
# made the product wrap to 0, the max_candidates cap passed and the loop ran
# 2^66 times (the evaluation hung). sample_surface had the same int product.

func test_volume_sampling_cap_is_not_bypassed_by_int_overflow() -> void:
	var huge := FlowSphereVolume.at(Vector3.ZERO, 2097152.0)	# 2^21: 2^22 voxels per axis
	var errors : Array = []
	var out := FlowSpatial.sample_volume(huge, {}, errors)
	assert_int(out.size()).is_equal(0)
	assert_int(errors.size()).is_equal(1)
	assert_str(str(errors[0])).contains("voxel")

func test_surface_sampling_cap_is_not_bypassed_by_int_overflow() -> void:
	# A 2 x 2 grid whose footprint is (2^32 - 512) m wide: 4294966785 cells per
	# axis at 1 point per m^2, whose square wraps to a negative int64.
	var hf := FlowHeightfieldSurface.new(PackedFloat32Array([0, 0, 0, 0]), 2, 2, 4294966784.0)
	var errors : Array = []
	var out := FlowSpatial.sample_surface(hf, { "points_per_square_meter": 1.0 }, errors)
	assert_int(out.size()).is_equal(0)
	assert_int(errors.size()).is_equal(1)
	assert_str(str(errors[0])).contains("candidates")

func test_sampling_non_finite_bounds_reports_instead_of_silently_empty() -> void:
	var inf_box := FlowBoxVolume.new(Transform3D.IDENTITY, Vector3(INF, 1, 1))
	var errors : Array = []
	var out := FlowSpatial.sample_volume(inf_box, {}, errors)
	assert_int(out.size()).is_equal(0)
	assert_int(errors.size()).is_equal(1)

func test_volume_sampling_far_from_the_origin_keeps_its_voxel_indices() -> void:
	# Voxel indices beyond 2^31 (x = 300 km at 0.1 mm voxels) wrapped in Vector3i.
	var box := FlowBoxVolume.new(Transform3D(Basis.IDENTITY, Vector3(300000, 0, 0)), Vector3(0.5, 0.5, 0.5))
	var errors : Array = []
	var out := FlowSpatial.sample_volume(box, { "voxel_size": Vector3(0.0001, 1, 1) }, errors)
	assert_array(errors).is_empty()
	assert_int(out.size()).is_greater(9000)
	for p in out.getVector3Container(FlowData.AttrPosition):
		assert_bool(p.x >= 299999.4 and p.x <= 300000.6).override_failure_message(str(p)).is_true()

# --- Regression: BoundsBox ignored the column of non-Y-up surfaces --------------------------
#
# The XZ broad phase of FlowSpatial.box_overlap assumed every surface column is
# the world Y axis. An XY polygon (create_surface_from_* with plane = XY) is a
# column along world Z, so a point whose centre has density 1 was rejected by
# the broad phase: BoundsBox (the default) and PointCenter disagreed even for
# vanishingly small points.

func test_bounds_box_agrees_with_point_center_on_vertical_polygons() -> void:
	var outline := PackedVector3Array([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 4, 0), Vector3(0, 4, 0)])
	for plane in [1, 2]:
		var pts := outline.duplicate()
		if plane == 2:
			for i in pts.size():
				pts[i] = Vector3(0, pts[i].x, pts[i].y)	# the same square on the YZ plane
		var poly := FlowPolygonSurface.from_world_points(pts, plane)
		var probes := [Vector3(2, 2, 5), Vector3(2, 2, -3), Vector3(6, 2, 5), Vector3(0, 2, 2), Vector3(7, 2, 2), Vector3(5, 6, 6)]
		var tiny := []
		for p in probes:
			tiny.append(Vector3(0.001, 0.001, 0.001))
		var data := S.points(probes, tiny)
		for op in [DifferenceSettings.eOperation.A_Minus_B, DifferenceSettings.eOperation.Intersection]:
			var pc := _positions(_diff(data, poly, op, 0, PC))
			var bb := _positions(_diff(data, poly, op, 0, BB))
			assert_array(bb).override_failure_message("plane %d op %d: BoundsBox %s vs PointCenter %s" % [plane, op, bb, pc]).is_equal(pc)

func test_bounds_box_agrees_with_point_center_on_tilted_heightfields() -> void:
	var tilt := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO)	# local Y -> world Z
	var hf := FlowHeightfieldSurface.new(PackedFloat32Array([0, 0, 0, 0]), 2, 2, 4.0, Vector3.ZERO, tilt)
	var probe := Vector3(2, -2, 9)	# far along the column, inside the footprint
	assert_float(hf.sample_density(probe)).is_equal(1.0)
	assert_float(hf.box_overlap(probe - Vector3.ONE * 0.01, probe + Vector3.ONE * 0.01).x).is_equal(1.0)

# --- Regression: Merged sources hardened soft volumes ----------------------------------------
#
# get_volume_data and get_spline_data (Merged, the volume default) joined their
# shapes with a Binary union, which is 1 wherever any operand is > 0: with two
# or more sources the `steepness` / `tube_steepness` falloff vanished, while a
# single source kept it.

func _sphere_cs(at : Vector3, radius : float, group : String) -> CollisionShape3D:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	cs.position = at
	return _grouped(cs, group)

func test_merged_volume_data_keeps_the_steepness_falloff() -> void:
	_sphere_cs(Vector3.ZERO, 2.0, "soft")
	_sphere_cs(Vector3(10, 0, 0), 2.0, "soft")
	var s = GetVolumeDataSettings.new()
	s.group_name = "soft"
	s.steepness = 0.5
	s.output_mode = GetVolumeDataSettings.eOutputMode.Merged
	var node = S.run(GetVolumeData, s, [], _owner)
	var merged : FlowSpatial = S.output(node).shape
	var single := FlowSphereVolume.at(Vector3.ZERO, 2.0, 0.5)
	for p in [Vector3(1.5, 0, 0), Vector3(11.8, 0, 0), Vector3(0, 0.5, 0), Vector3(5, 0, 0)]:
		var expected := maxf(single.sample_density(p), single.sample_density(p - Vector3(10, 0, 0)))
		assert_float(merged.sample_density(p)).override_failure_message(str(p)).is_equal_approx(expected, 1e-6)
	S.release(node)

func test_merged_spline_data_keeps_the_tube_falloff() -> void:
	for z in [0.0, 10.0]:
		var p := Path3D.new()
		p.curve = S.line_curve(Vector3(0, 0, z), Vector3(10, 0, z))
		_grouped(p, "roads")
	var s = GetSplineDataSettings.new()
	s.group_name = "roads"
	s.tube_half_width = 2.0
	s.tube_steepness = 0.5
	s.output_mode = GetSplineDataSettings.eOutputMode.Merged
	var node = S.run(GetSplineData, s, [], _owner)
	var merged : FlowSpatial = S.output(node).shape
	# 1.5 m from the first spline: falloff((1.5 / 2), 0.5) = 0.5.
	assert_float(merged.sample_density(Vector3(5, 0, 1.5))).is_equal_approx(0.5, 1e-4)
	S.release(node)

# --- Regression: To Point voxelised merged spline data ---------------------------------------
#
# A union of splines (get_spline_data Merged) reports kind Volume, so to_point
# sampled the tubes on a voxel grid; sample_spline, create_surface_from_spline
# and filter_data_by_type all treat it as spline data. To Point now samples each
# spline along its curve, the same points as sampling them one by one.

func test_to_point_samples_merged_splines_along_their_curves() -> void:
	var a := FlowSplineShape.new(S.line_curve(Vector3.ZERO, Vector3(10, 0, 0)))
	var b := FlowSplineShape.new(S.line_curve(Vector3(0, 0, 5), Vector3(0, 0, 12)))
	var settings = ToPointSettings.new()
	var expected := []
	for leaf in [a, b]:
		var one = S.run(ToPoint, settings, [FlowDataScript.Data.from_shape(leaf)])
		expected.append_array(_positions(S.output(one)))
		S.release(one)
	var node = S.run(ToPoint, settings, [FlowDataScript.Data.from_shape(FlowCompositeShape.union_of([a, b]))])
	assert_str(node.err).is_empty()
	var out := S.output(node)
	assert_array(_positions(out)).is_equal(expected)
	assert_int(out.getContainerChecked(FlowData.AttrSeed, FlowData.DataType.Int).size()).is_equal(expected.size())
	S.release(node)

# --- Regression: a coplanar nearest-point projection flipped the normal ----------------------
#
# FlowTriangleGrid.nearest orients the face normal towards the query point. For
# a point level with a flat mesh (beside it) the dot product is 0 and the raw
# winding won: Godot's clockwise front faces gave (0, -1, 0). Projection
# (Surface mode, align_to_normal) then turned such points upside down, and the
# mesh terrain adapter returned a downward normal in footprint gaps.

func test_nearest_projection_level_with_a_flat_mesh_points_up() -> void:
	var surface := FlowMeshSurface.from_meshes([S.plane_mesh(4.0, 1)], [Transform3D.IDENTITY])
	var hit := surface.project(Vector3(5, 0, 0))
	assert_bool(hit.is_empty()).is_false()
	assert_vector(hit.normal).is_equal(Vector3.UP)
	# Off the plane the normal still faces the query point.
	assert_vector(surface.project(Vector3(5, -1, 0)).normal).is_equal(Vector3.DOWN)
	assert_vector(surface.project(Vector3(5, 1, 0)).normal).is_equal(Vector3.UP)

func test_projection_surface_mode_beside_a_mesh_keeps_points_upright() -> void:
	var s = ProjectionNodeSettings.new()
	s.projection_mode = ProjectionNodeSettings.eProjectionMode.Surface
	s.align_to_normal = true
	var target := FlowDataScript.Data.from_shape(FlowMeshSurface.from_meshes([S.plane_mesh(4.0, 1)], [Transform3D.IDENTITY]))
	var node = S.run(ProjectionNode, s, [S.points([Vector3(5, 0, 0)]), target])
	assert_str(node.err).is_empty()
	var out := S.output(node)
	assert_vector(out.getVector3Container(FlowData.AttrNormal)[0]).is_equal(Vector3.UP)
	# Upright: the rotated Y axis is world up (it was world down before the fix).
	assert_vector(FlowData.eulerToBasis(out.getVector3Container(FlowData.AttrRotation)[0]).y).is_equal_approx(Vector3.UP, Vector3.ONE * 1e-4)
	S.release(node)

func test_mesh_terrain_normal_in_a_footprint_gap_points_up() -> void:
	# Two 2 x 2 quads forming an L; (3, 0, 3) is inside the bounds but over the gap.
	var verts := PackedVector3Array()
	for o in [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 0, 2)]:
		verts.append_array([o, o + Vector3(2, 0, 0), o + Vector3(2, 0, 2), o, o + Vector3(2, 0, 2), o + Vector3(0, 0, 2)])
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var adapter := FlowMeshTerrainAdapter.new([am], [Transform3D.IDENTITY])
	assert_vector(adapter.get_normal(3, 3)).is_equal(Vector3.UP)

# --- Regression: an empty spline had a 2 m bounding box at the origin ------------------------

func test_empty_spline_has_empty_bounds() -> void:
	assert_vector(FlowSplineShape.new().get_bounds().size).is_equal(Vector3.ZERO)
	assert_vector(FlowSplineShape.new(Curve3D.new(), Transform3D(Basis.IDENTITY, Vector3(7, 0, 0))).get_bounds().size).is_equal(Vector3.ZERO)
	# A one-point spline is a ball of half_width around its point.
	var one := Curve3D.new()
	one.add_point(Vector3(1, 2, 3))
	var ball := FlowSplineShape.new(one, Transform3D.IDENTITY, false, 0.5)
	assert_vector(ball.get_bounds().position).is_equal_approx(Vector3(0.5, 1.5, 2.5), Vector3.ONE * 1e-5)
	assert_vector(ball.get_bounds().size).is_equal_approx(Vector3.ONE, Vector3.ONE * 1e-5)

# --- Regression: union_of built a left-deep chain ---------------------------------------------
#
# Every query recursed once per operand, so Merged sources with about a thousand
# shapes (get_volume_data on a forest of colliders) exceeded GDScript's call
# depth and the engine printed "Stack underflow" errors. union_of now builds a
# balanced tree with the same leaves in the same order.

func test_union_of_is_balanced_and_keeps_leaf_order() -> void:
	var shapes := []
	for i in 1500:
		shapes.append(FlowSphereVolume.at(Vector3(i * 3.0, 0, 0), 1.0))
	var u := FlowCompositeShape.union_of(shapes)
	assert_int(_depth(u)).is_less_equal(12)
	var leaves := u.union_leaves()
	assert_int(leaves.size()).is_equal(1500)
	for i in [0, 1, 749, 1498, 1499]:
		assert_object(leaves[i]).is_same(shapes[i])
	assert_float(u.sample_density(Vector3(1499 * 3.0, 0, 0))).is_equal(1.0)
	assert_float(u.sample_density(Vector3(1.5, 0, 0))).is_equal(0.0)
	assert_object(FlowCompositeShape.union_of([shapes[0]])).is_same(shapes[0])
	assert_object(FlowCompositeShape.union_of([])).is_null()
	assert_object(FlowCompositeShape.union_of([null, shapes[2], null])).is_same(shapes[2])

# --- Regression: get_surface_data accepted a non-positive image cell size --------------------
#
# image_cell_size 0 or negative silently produced a microscopic grid (the cell
# is clamped to 1e-6) placed at an origin computed from the raw negative value.

func test_get_surface_data_rejects_non_positive_image_cell_size() -> void:
	for cell in [0.0, -1.0]:
		var s = GetSurfaceDataSettings.new()
		s.source = GetSurfaceDataSettings.eSource.HeightmapImage
		s.heightmap_image = Image.create(4, 4, false, Image.FORMAT_RF)
		s.image_cell_size = cell
		var node = S.run(GetSurfaceData, s, [])
		assert_str(node.err).contains("image_cell_size")
		assert_object(S.output(node).shape).is_null()
		S.release(node)

# --- Regression: Terrain3D snapshots overshot the terrain on the short axis -------------------
#
# The default to_surface() grid used one square cell for both axes, so on a
# non-square terrain the short axis spilled up to one cell past the terrain,
# with clamped heights and density 1 where there is no terrain.

func test_terrain_snapshot_footprint_matches_the_terrain_bounds() -> void:
	var t = Fakes.terrain3d([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])	# 3 x 1 regions
	_grouped(t, "")
	var adapter := FlowTerrainAdapter.for_node(t, { "max_resolution": 8 })
	assert_str(adapter.error).is_empty()
	var b := adapter.get_bounds()
	var surface := adapter.to_surface()
	var sb := surface.get_bounds()
	assert_float(sb.position.x).is_equal_approx(b.position.x, 1e-3)
	assert_float(sb.end.x).is_equal_approx(b.end.x, 1e-3)
	assert_float(sb.position.z).is_equal_approx(b.position.z, 1e-3)
	assert_float(sb.end.z).is_equal_approx(b.end.z, 1e-3)
	# Inside: the live height; beyond the short edge: no surface.
	var probe := Vector2(b.position.x + 0.3 * b.size.x, b.position.z + 0.6 * b.size.z)
	assert_float(surface.project_vertical(probe.x, probe.y).position.y).is_equal_approx(adapter.get_height(probe.x, probe.y), 0.5)
	assert_bool(surface.project_vertical(probe.x, b.end.z + 1.0).is_empty()).is_true()

# --- Regression: Union with an empty point input dropped the shape ----------------------------
#
# Points with a shape give points, so Union(shape, points) returned the points
# folded by the shape. With an empty point input that was an empty Data: a
# Union or Symmetric Difference whose other pin received no points silently
# lost the shape, while Difference (shape minus empty points) already passed
# the shape through. A union with nothing is the shape itself.

func test_union_and_symmetric_difference_with_empty_points_keep_the_shape() -> void:
	var box := FlowBoxVolume.from_aabb(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	var shaped := FlowDataScript.Data.from_shape(box)
	shaped.tags = PackedStringArray(["vol"])
	for op in [DifferenceSettings.eOperation.Union, DifferenceSettings.eOperation.SymmetricDifference, DifferenceSettings.eOperation.A_Minus_B]:
		for shape_first in [true, false]:
			var s = DifferenceSettings.new()
			s.operation = op
			if op == DifferenceSettings.eOperation.A_Minus_B and not shape_first:
				s.operation = DifferenceSettings.eOperation.B_Minus_A
			var inputs := [shaped, FlowDataScript.Data.new()] if shape_first else [FlowDataScript.Data.new(), shaped]
			var node = S.run(DifferenceNode, s, inputs)
			assert_str(node.err).is_empty()
			var out := S.output(node)
			assert_object(out.shape).override_failure_message("op %d shape_first %s" % [op, shape_first]).is_same(box)
			assert_array(Array(out.tags)).is_equal(["vol"])
			S.release(node)
	# Intersection with nothing stays empty.
	var si = DifferenceSettings.new()
	si.operation = DifferenceSettings.eOperation.Intersection
	var inode = S.run(DifferenceNode, si, [shaped, FlowDataScript.Data.new()])
	assert_object(S.output(inode).shape).is_null()
	assert_int(S.output(inode).size()).is_equal(0)
	S.release(inode)

# --- Regression: spline tubes under a non-uniform scale -----------------------------------------
#
# FlowSplineShape found the closest point in curve space and transformed it to
# world space. Under a non-uniform scale (a scaled Path3D) the curve-space
# metric is distorted and picks the wrong segment: a point 3 m from the road
# measured 5 m, outside a 4 m tube. Conformal transforms are unchanged.

func test_spline_tube_under_non_uniform_scale_uses_world_distance() -> void:
	var c := Curve3D.new()
	for p in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 5)]:
		c.add_point(p)
	# World polyline: (0,0,0) -> (10,0,0) -> (10,0,5).
	var spline := FlowSplineShape.new(c, Transform3D(Basis.from_scale(Vector3(10, 1, 1)), Vector3.ZERO), false, 4.0)
	assert_vector(spline.closest_point(Vector3(5, 0, 3))).is_equal_approx(Vector3(5, 0, 0), Vector3.ONE * 1e-3)
	assert_float(spline.sample_density(Vector3(5, 0, 3))).is_equal(1.0)
	assert_float(spline.sample_density(Vector3(5, 0, 4.5))).is_equal(0.0)
	# A closed square scaled 3 x 1: the closing edge (x = 0) counts too.
	var sq := S.square_curve(1.0, false)
	var closed := FlowSplineShape.new(sq, Transform3D(Basis.from_scale(Vector3(3, 1, 1)), Vector3.ZERO), true, 0.5)
	assert_float(closed.sample_density(Vector3(-3.2, 0, 0))).is_equal(1.0)
	assert_float(closed.sample_density(Vector3(0, 0, 0))).is_equal(0.0)
	# Brute force over the world polyline on random probes.
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var baked := sq.get_baked_points()
	for i in 60:
		var p := Vector3(rng.randf_range(-5, 5), rng.randf_range(-1, 1), rng.randf_range(-2, 2))
		var q := closed.closest_point(p)
		var best := INF
		var world := PackedVector3Array()
		for b in closed.curve.get_baked_points():
			world.append(closed.transform * b)
		for k in world.size() - 1:
			best = minf(best, p.distance_to(Geometry3D.get_closest_point_to_segment(p, world[k], world[k + 1])))
		assert_float(p.distance_to(q)).is_equal_approx(best, 1e-4)

# --- Coverage: accelerated queries against brute force -------------------------------------

func test_triangle_grid_matches_brute_force_on_random_queries() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var verts := PackedVector3Array()
	for i in 300:
		var c := Vector3(rng.randf_range(-50, 50), rng.randf_range(-5, 5), rng.randf_range(-30, 30))
		for k in 3:
			verts.append(c + Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)))
	# A few degenerate (zero-area and collinear) triangles must not break anything.
	verts.append_array([Vector3(1, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(2, 1, 0)])
	var g := FlowTriangleGrid.new(verts)
	for i in 150:
		var p := Vector3(rng.randf_range(-80, 80), rng.randf_range(-20, 20), rng.randf_range(-60, 60))
		if i % 3 == 0:
			p.x = g._x0 + round((p.x - g._x0) / g._cell) * g._cell	# exactly on a cell boundary
		var best := INF
		var top := -INF
		for t in g.tri_count:
			best = minf(best, p.distance_to(FlowSpatial.closest_point_on_triangle(p, verts[t * 3], verts[t * 3 + 1], verts[t * 3 + 2])))
			var y := g._vertical_y(t, p.x, p.z)
			if not is_nan(y):
				top = maxf(top, y)
		var near := g.nearest(p)
		assert_float(float(near.distance)).override_failure_message("nearest %s" % p).is_equal_approx(best, 1e-3)
		assert_bool(is_finite(near.position.x)).is_true()
		var hit := g.vertical_hit(p.x, p.z)
		if is_inf(top):
			assert_bool(hit.is_empty()).override_failure_message("vertical %s" % p).is_true()
		else:
			assert_float(hit.position.y).override_failure_message("vertical %s" % p).is_equal_approx(top, 1e-4)

func test_polygon_contains_matches_brute_force_any_winding() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for trial in 20:
		var poly := PackedVector2Array()
		var n := rng.randi_range(3, 30)
		for i in n:
			poly.append(Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10)))	# concave and self-intersecting
		var rev := poly.duplicate()
		rev.reverse()
		var cw := FlowPolygonSurface.new(poly)
		var ccw := FlowPolygonSurface.new(rev)
		for k in 100:
			var q := Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
			if k % 7 == 0:
				q.y = poly[rng.randi() % n].y	# level with a vertex
			var inside := false
			for i in n:
				var a := poly[i]
				var b := poly[(i + 1) % n]
				if (a.y > q.y) != (b.y > q.y) and q.x < a.x + (q.y - a.y) * (b.x - a.x) / (b.y - a.y):
					inside = not inside
			assert_bool(cw.contains_local(q.x, q.y)).is_equal(inside)
			assert_bool(ccw.contains_local(q.x, q.y)).is_equal(inside)

func test_box_and_sphere_overlap_match_dense_sampling() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	const N := 12
	for trial in 40:
		var c := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var mirror := Vector3(-1 if trial % 3 == 0 else 1, 1, -1 if trial % 4 == 0 else 1)
		var box := FlowBoxVolume.new(Transform3D(Basis.from_scale(mirror * rng.randf_range(0.5, 2.0)), c), Vector3(rng.randf_range(0.1, 3), rng.randf_range(0.1, 3), rng.randf_range(0.1, 3)), 1.0 if trial % 2 == 0 else rng.randf_range(0.1, 0.9))
		var sphere := FlowSphereVolume.new(Transform3D(Basis(Vector3(0.3, 1, 0.2).normalized(), rng.randf_range(0, 6)).scaled(mirror * rng.randf_range(0.5, 2.0)), c), rng.randf_range(0.2, 3), rng.randf_range(0.2, 1.0))
		var mn := Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		var mx := mn + Vector3(rng.randf_range(0.01, 4), rng.randf_range(0.01, 4), rng.randf_range(0.01, 4))
		var ob := box.box_overlap(mn, mx)
		var os := sphere.box_overlap(mn, mx)
		var bpeak := 0.0
		var btotal := 0.0
		var speak := 0.0
		for ix in N:
			for iy in N:
				for iz in N:
					var p := mn + (mx - mn) * Vector3((ix + 0.5) / N, (iy + 0.5) / N, (iz + 0.5) / N)
					var d := box.sample_density(p)
					bpeak = maxf(bpeak, d)
					btotal += d
					speak = maxf(speak, sphere.sample_density(p))
		assert_bool(bpeak <= ob.x + 1e-6).override_failure_message("box peak %s < sampled %f" % [ob, bpeak]).is_true()
		assert_bool(speak <= os.x + 1e-6).override_failure_message("sphere peak %s < sampled %f" % [os, speak]).is_true()
		assert_bool(ob.y <= ob.x + 1e-6 and os.y <= os.x + 1e-6).is_true()
		if box.steepness >= 1.0:
			assert_float(ob.y).override_failure_message("box coverage").is_equal_approx(btotal / (N * N * N), 0.1)

# --- Coverage: shapes are thread safe and immutable ------------------------------------------

var _thread_shapes : Array = []
var _thread_queries := PackedVector3Array()
var _thread_results : Array = []

func _thread_query(task : int) -> void:
	var s : FlowSpatial = _thread_shapes[task % _thread_shapes.size()]
	var out := PackedFloat64Array()
	for p in _thread_queries:
		out.append(s.sample_density(p))
		var pr := s.project(p)
		out.append(pr.position.y if not pr.is_empty() else -1.0)
	_thread_results[task] = out

func test_concurrent_queries_match_sequential_ones() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3(-20, 0, 0), Vector3.ZERO, Vector3(5, 0, 5))
	c.add_point(Vector3(20, 0, 0), Vector3(-5, 0, 5))
	var spline := FlowSplineShape.new(c, Transform3D.IDENTITY, false, 3.0, 0.5)
	var mesh := FlowMeshSurface.from_meshes([S.plane_mesh(40.0, 20)], [Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3.ZERO)])
	var hf := FlowHeightfieldSurface.new(PackedFloat32Array([0, 1, 2, 1, 2, 3, 2, 3, 4]), 3, 3, 10.0, Vector3(-10, 0, -10))
	_thread_shapes = [spline, mesh, hf, FlowCompositeShape.new(FlowSpatial.Op.Difference, mesh, spline, 1),
		FlowPointsVolume.from_data(S.points([Vector3(1, 0, 1), Vector3(5, 0, 5)], [Vector3(4, 4, 4), Vector3(2, 2, 2)]))]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_thread_queries = PackedVector3Array()
	for i in 150:
		_thread_queries.append(Vector3(rng.randf_range(-25, 25), rng.randf_range(-5, 5), rng.randf_range(-25, 25)))
	var n := 20
	_thread_results = []
	_thread_results.resize(n)
	WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(_thread_query, n, -1, true))
	var threaded := _thread_results.duplicate()
	_thread_results = []
	_thread_results.resize(n)
	for t in n:
		_thread_query(t)
	for t in n:
		assert_bool(threaded[t] == _thread_results[t]).override_failure_message("task %d" % t).is_true()

func test_editing_the_source_curve_does_not_change_the_shape() -> void:
	var c := S.line_curve(Vector3.ZERO, Vector3(10, 0, 0))
	var spline := FlowSplineShape.new(c, Transform3D.IDENTITY, false, 1.0, 0.5)
	var h := spline.content_hash()
	var d := spline.sample_density(Vector3(5, 0, 0.7))
	c.set_point_position(1, Vector3(0, 0, 10))
	c.bake_interval = 0.05
	assert_int(spline.content_hash()).is_equal(h)
	assert_float(spline.sample_density(Vector3(5, 0, 0.7))).is_equal(d)

# --- Coverage: falloff, hashes ------------------------------------------------------------------

func test_falloff_is_continuous_and_monotonic() -> void:
	for s in [0.0, 0.25, 0.5, 0.99, 1.0]:
		var prev := FlowSpatial.falloff(0.0, s)
		assert_float(prev).is_equal(1.0)
		for i in range(1, 1001):
			var t := i / 1000.0
			var v := FlowSpatial.falloff(t, s)
			assert_bool(v <= prev + 1e-9).override_failure_message("s %f t %f" % [s, t]).is_true()
			if s < 1.0:
				assert_bool(prev - v <= 1.0 / (1000.0 * (1.0 - s)) + 1e-6).override_failure_message("jump at s %f t %f" % [s, t]).is_true()
			prev = v
		assert_float(FlowSpatial.falloff(1.0001, s)).is_equal(0.0)
	assert_float(FlowSpatial.falloff(NAN, 0.5)).is_equal(0.0)

func test_content_hash_covers_every_parameter() -> void:
	var c := S.line_curve(Vector3.ZERO, Vector3(10, 0, 0))
	var base := FlowSplineShape.new(c, Transform3D.IDENTITY, false, 1.0, 1.0).content_hash()
	assert_int(FlowSplineShape.new(c, Transform3D.IDENTITY, false, 1.0, 1.0).content_hash()).is_equal(base)
	for other in [FlowSplineShape.new(c, Transform3D(Basis.IDENTITY, Vector3.UP), false, 1.0, 1.0), FlowSplineShape.new(c, Transform3D.IDENTITY, true, 1.0, 1.0),
			FlowSplineShape.new(c, Transform3D.IDENTITY, false, 2.0, 1.0), FlowSplineShape.new(c, Transform3D.IDENTITY, false, 1.0, 0.5),
			FlowSplineShape.new(S.line_curve(Vector3.ZERO, Vector3(10, 0, 1)), Transform3D.IDENTITY, false, 1.0, 1.0)]:
		assert_int(other.content_hash()).is_not_equal(base)
	var hs := PackedFloat32Array([0, 1, 2, 3])
	var hbase := FlowHeightfieldSurface.new(hs, 2, 2, 1.0).content_hash()
	var hs2 := hs.duplicate()
	hs2[3] = 4.0
	for other in [FlowHeightfieldSurface.new(hs2, 2, 2, 1.0), FlowHeightfieldSurface.new(hs, 2, 2, 2.0), FlowHeightfieldSurface.new(hs, 2, 2, 1.0, Vector3.UP),
			FlowHeightfieldSurface.new(hs, 2, 2, 1.0, Vector3.ZERO, Transform3D(Basis.IDENTITY, Vector3.UP)), FlowHeightfieldSurface.new(hs, 2, 2, 1.0, Vector3.ZERO, Transform3D.IDENTITY, 0.5),
			FlowHeightfieldSurface.new(hs, 4, 1, 1.0)]:
		assert_int(other.content_hash()).is_not_equal(hbase)
	var box := FlowBoxVolume.new(Transform3D.IDENTITY, Vector3.ONE, 1.0)
	var sph := FlowSphereVolume.new(Transform3D.IDENTITY, 1.0, 1.0)
	assert_int(FlowBoxVolume.new(Transform3D.IDENTITY, Vector3.ONE, 0.5).content_hash()).is_not_equal(box.content_hash())
	assert_int(FlowSphereVolume.new(Transform3D.IDENTITY, 1.0, 0.5).content_hash()).is_not_equal(sph.content_hash())
	var comps := [FlowCompositeShape.new(FlowSpatial.Op.Union, box, sph), FlowCompositeShape.new(FlowSpatial.Op.Union, sph, box),
		FlowCompositeShape.new(FlowSpatial.Op.Difference, box, sph), FlowCompositeShape.new(FlowSpatial.Op.Union, box, sph, 1)]
	for i in comps.size():
		for j in range(i + 1, comps.size()):
			assert_int(comps[i].content_hash()).is_not_equal(comps[j].content_hash())
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	var pbase := FlowPolygonSurface.new(poly).content_hash()
	assert_int(FlowPolygonSurface.new(poly, Transform3D.IDENTITY, 1.0).content_hash()).is_not_equal(pbase)
	assert_int(FlowPolygonSurface.new(poly, Transform3D.IDENTITY, 0.0, 2.0).content_hash()).is_not_equal(pbase)

# --- Coverage: composites ------------------------------------------------------------------------

func test_shape_combined_with_itself_and_nested_composites() -> void:
	var soft := FlowSphereVolume.at(Vector3.ZERO, 2.0, 0.5)
	var probes := [Vector3.ZERO, Vector3(1.5, 0, 0), Vector3(1.9, 0, 0), Vector3(3, 0, 0)]
	for p in probes:
		var d := soft.sample_density(p)
		assert_float(FlowCompositeShape.new(FlowSpatial.Op.Intersection, soft, soft, FlowSpatial.DENSITY_MINIMUM).sample_density(p)).is_equal_approx(d, 1e-9)
		assert_float(FlowCompositeShape.new(FlowSpatial.Op.Union, soft, soft, FlowSpatial.DENSITY_MINIMUM).sample_density(p)).is_equal_approx(d, 1e-9)
		assert_float(FlowCompositeShape.new(FlowSpatial.Op.Difference, soft, soft, FlowSpatial.DENSITY_BINARY).sample_density(p)).is_equal(0.0)
	# (A - B) inside C, nested three deep, against the density table by hand.
	var a := FlowBoxVolume.from_aabb(AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10)))
	var b := FlowSphereVolume.at(Vector3.ZERO, 2.0)
	var c := FlowBoxVolume.from_aabb(AABB(Vector3(0, -5, -5), Vector3(10, 10, 10)))
	var nested := FlowCompositeShape.new(FlowSpatial.Op.Intersection, FlowCompositeShape.new(FlowSpatial.Op.Difference, a, b), c)
	assert_float(nested.sample_density(Vector3(3, 0, 0))).is_equal(1.0)
	assert_float(nested.sample_density(Vector3(1, 0, 0))).is_equal(0.0)
	assert_float(nested.sample_density(Vector3(-3, 0, 0))).is_equal(0.0)
	assert_int(nested.get_kind()).is_equal(FlowData.Kind.Volume)
