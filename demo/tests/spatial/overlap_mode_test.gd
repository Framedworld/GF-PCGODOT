# overlap_mode_test.gd
# WP6: overlap_mode (PointCenter | BoundsBox) for points against spatial data in
# difference / intersection / union, and the FlowSpatial.box_overlap contract
# (exact for axis-aligned boxes and true spheres, fixed sample set otherwise).
class_name SpatialOverlapModeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spatial/support/spatial_test_support.gd")
const DifferenceNode = preload("res://addons/flow_nodes_editor/nodes/difference.gd")
const IntersectionNode = preload("res://addons/flow_nodes_editor/nodes/intersection.gd")
const UnionNode = preload("res://addons/flow_nodes_editor/nodes/union.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")

const PC : int = 0	# DifferenceSettings.eOverlapMode.PointCenter
const BB : int = 1	# DifferenceSettings.eOverlapMode.BoundsBox

func _settings(op : int, fn : int, om : int = -1):
	var s = DifferenceSettings.new()
	s.operation = op
	s.density_function = fn
	if om >= 0:
		s.overlap_mode = om
	return s

func _run(script, a : FlowData.Data, b : FlowData.Data, op : int = 0, fn : int = 0, om : int = -1) -> FlowData.Data:
	var node = S.run(script, _settings(op, fn, om), [a, b])
	assert_str(node.err).is_empty()
	return S.output(node)

func _shape(shape : FlowSpatial) -> FlowData.Data:
	return FlowDataScript.Data.from_shape(shape)

func _positions(d : FlowData.Data) -> Array:
	return Array(d.getVector3Container(FlowData.AttrPosition))

func _densities(d : FlowData.Data) -> PackedFloat32Array:
	return d.getContainerChecked(FlowData.AttrDensity, FlowData.DataType.Float)

## Points with sizes and an optional steepness stream.
func _pts(positions : Array, sizes : Array, steepness : Array = [], densities : Array = []) -> FlowData.Data:
	var d := S.points(positions, sizes)
	if not steepness.is_empty():
		d.registerStream(FlowData.AttrSteepness, PackedFloat32Array(steepness), FlowData.DataType.Float)
	if not densities.is_empty():
		d.registerStream(FlowData.AttrDensity, PackedFloat32Array(densities), FlowData.DataType.Float)
	return d

# --- The motivating case ----------------------------------------------------------------

func test_default_is_bounds_box() -> void:
	assert_int(DifferenceSettings.new().overlap_mode).is_equal(DifferenceSettings.eOverlapMode.BoundsBox)

func test_large_point_with_centre_outside_is_removed_or_attenuated() -> void:
	# Box volume [-2, 2]^3. The point sits at x = 3.5 (outside) but its size of 4
	# along X makes its bounds [1.5, 5.5]: a quarter of it is inside the volume.
	var box := FlowBoxVolume.from_aabb(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)))
	var big := _pts([Vector3(3.5, 0, 0), Vector3(10, 0, 0)], [Vector3(4, 1, 1), Vector3(4, 1, 1)])
	# PointCenter (WP2 behaviour) keeps it; BoundsBox removes it.
	assert_array(_positions(_run(DifferenceNode, big, _shape(box), 0, 0, PC))).is_equal([Vector3(3.5, 0, 0), Vector3(10, 0, 0)])
	assert_array(_positions(_run(DifferenceNode, big, _shape(box)))).is_equal([Vector3(10, 0, 0)])
	# Hard point (steepness 1): any overlap is a full hit, as point-versus-point.
	var mul := _densities(_run(DifferenceNode, big, _shape(box), 0, DifferenceSettings.eDensityFunction.Multiply))
	assert_float(mul[0]).is_equal(0.0)
	assert_float(mul[1]).is_equal(1.0)
	# Soft point (steepness 0): attenuated by the covered fraction (0.5 of 4 on X).
	var soft := _pts([Vector3(3.5, 0, 0)], [Vector3(4, 1, 1)], [0.0])
	var sub := _densities(_run(DifferenceNode, soft, _shape(box), 0, DifferenceSettings.eDensityFunction.Subtract))
	assert_float(sub[0]).is_equal_approx(0.875, 1e-5)
	# Intersection / Union nodes default to BoundsBox too.
	assert_array(_positions(_run(IntersectionNode, big, _shape(box)))).is_equal([Vector3(3.5, 0, 0)])
	var uni := _densities(_run(UnionNode, _pts([Vector3(3.5, 0, 0)], [Vector3(4, 1, 1)], [], [0.0]), _shape(box)))
	assert_float(uni[0]).is_equal(1.0)

# --- BoundsBox equals point-versus-point for a hard axis-aligned box ------------------

func _cases() -> Array:
	# Mixed sizes, steepness and positions: inside, partly inside (centre outside),
	# outside, overlapping on Y only.
	var sized := _pts(
		[Vector3(0, 0, 0), Vector3(2.6, 0, 0), Vector3(3.5, 0, 0), Vector3(10, 0, 0), Vector3(0, 2.5, 0.3), Vector3(-2.9, 0.4, -1.8)],
		[Vector3(1, 1, 1), Vector3(2, 2, 2), Vector3(4, 1, 1), Vector3(1, 1, 1), Vector3(2, 2, 2), Vector3(3, 1.5, 1)],
		[1.0, 0.5, 0.0, 1.0, 0.3, 0.8],
		[1.0, 0.9, 0.8, 1.0, 0.7, 0.6])
	# Asymmetric per-point bounds (bounds_min / bounds_max win over size).
	var bounded := _pts([Vector3(-4, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 5)], [Vector3.ONE, Vector3.ONE, Vector3.ONE], [0.0, 1.0, 0.4])
	bounded.registerStream(FlowData.AttrBoundsMin, PackedVector3Array([Vector3(0, -0.5, -0.5), Vector3(-1, -0.5, -0.5), Vector3(-0.5, -0.5, -3.5)]), FlowData.DataType.Vector)
	bounded.registerStream(FlowData.AttrBoundsMax, PackedVector3Array([Vector3(3, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5), Vector3(0.5, 0.5, -2.0)]), FlowData.DataType.Vector)
	return [sized, bounded]

func test_bounds_box_matches_point_versus_point_difference() -> void:
	var aabb := AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	var box_shape := _shape(FlowBoxVolume.from_aabb(aabb))
	var box_point := S.points([aabb.get_center()], [aabb.size])
	for pts in _cases():
		for fn in range(4):
			var via_shape := _run(DifferenceNode, pts, box_shape, 0, fn)
			var via_points := _run(DifferenceNode, pts, box_point, 0, fn)
			assert_array(_positions(via_shape)).is_equal(_positions(via_points))
			if fn != 0:
				var ds := _densities(via_shape)
				var dp := _densities(via_points)
				assert_int(ds.size()).is_equal(dp.size())
				for i in ds.size():
					assert_float(ds[i]).is_equal_approx(dp[i], 1e-5)

func test_bounds_box_honours_bounds_streams_and_size() -> void:
	var box := _shape(FlowBoxVolume.from_aabb(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))))
	var pts : FlowData.Data = _cases()[1]
	# Point 0: centre (-4, 0, 0) outside, bounds [-4, -1] on X overlap -> removed.
	# Point 1: centre (4, 0, 0), bounds [3, 3.5] -> stays outside -> kept.
	# Point 2: centre (0, 0, 5), bounds [1.5, 3] on Z -> overlaps -> removed.
	assert_array(_positions(_run(DifferenceNode, pts, box))).is_equal([Vector3(4, 0, 0)])
	# Without the bounds streams the size (1) is used: only the centre region counts.
	var sized := S.points([Vector3(-4, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 5), Vector3(2.4, 0, 0)])
	assert_array(_positions(_run(DifferenceNode, sized, box))).is_equal([Vector3(-4, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 5)])

func test_point_steepness_shapes_partial_overlap() -> void:
	var box := _shape(FlowBoxVolume.from_aabb(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))))
	# Same box overlap (half of the point inside), steepness 1, 0.5 and 0.
	var pts := _pts([Vector3(2, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 0)], [Vector3(2, 1, 1), Vector3(2, 1, 1), Vector3(2, 1, 1)], [1.0, 0.5, 0.0])
	var d := _densities(_run(DifferenceNode, pts, box, 0, DifferenceSettings.eDensityFunction.Multiply))
	assert_float(d[0]).is_equal(0.0)
	assert_float(d[2]).is_equal_approx(0.5, 1e-5)
	assert_bool(d[1] > d[0] and d[1] < d[2]).is_true()
	assert_float(d[1]).is_equal_approx(1.0 - BoundsOverlapUtil.shape_factor(0.5, 0.5), 1e-5)

# --- PointCenter reproduces the WP2 output exactly ------------------------------------------

func _shapes() -> Array:
	var rot := Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3(0.5, 0, 0))
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	var cube := BoxMesh.new()
	cube.size = Vector3(3, 3, 3)
	var cutter := S.points([Vector3(1, 0, 1)], [Vector3(2, 2, 2)])
	return [
		FlowBoxVolume.from_aabb(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))),
		FlowBoxVolume.new(rot, Vector3(1.5, 1, 1), 0.4),
		FlowSphereVolume.at(Vector3.ZERO, 2.5, 0.0),
		FlowSphereVolume.new(Transform3D(Basis().scaled(Vector3(2, 1, 1)), Vector3.ZERO), 1.5, 0.5),
		FlowMeshSurface.from_meshes([plane], [Transform3D.IDENTITY]),
		FlowMeshVolume.from_meshes([cube], [Transform3D.IDENTITY]),
		FlowSplineShape.new(S.line_curve(Vector3(-5, 0, 0), Vector3(5, 0, 0)), Transform3D.IDENTITY, false, 1.0, 0.5),
		FlowPointsVolume.from_data(cutter),
		FlowCompositeShape.new(FlowSpatial.Op.Difference, FlowBoxVolume.from_aabb(AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))), FlowSphereVolume.at(Vector3.ZERO, 1.0), FlowSpatial.DENSITY_MULTIPLY),
	]

func _grid_points() -> FlowData.Data:
	var positions := []
	var sizes := []
	for x in range(-4, 5):
		for z in range(-1, 2):
			positions.append(Vector3(x * 0.9, 0.2 * z, z * 1.3))
			sizes.append(Vector3(1.0 + absf(x) * 0.3, 1, 1.5))
	var d := S.points(positions, sizes)
	var dens := PackedFloat32Array()
	for i in positions.size():
		dens.append(0.5 + 0.5 * float(i % 3) / 2.0)
	d.registerStream(FlowData.AttrDensity, dens, FlowData.DataType.Float)
	return d

## Byte equality of every output, with shapes compared by type and content hash
## (shape minus points builds a fresh composite on each run).
func _same_output(a, b) -> bool:
	if a.err != b.err or a.generated_bulks.size() != b.generated_bulks.size():
		return false
	for i in a.generated_bulks.size():
		var da : FlowData.Data = a.generated_bulks[i][0]
		var db : FlowData.Data = b.generated_bulks[i][0]
		if (da.shape == null) != (db.shape == null):
			return false
		if da.shape != null and (da.shape.get_type_name() != db.shape.get_type_name() or da.shape.content_hash() != db.shape.content_hash()):
			return false
		var sa = da.shape
		var sb = db.shape
		da.shape = null
		db.shape = null
		var same := S.same_data(da, db)
		da.shape = sa
		db.shape = sb
		if not same:
			return false
	return true

func test_point_center_reproduces_wp2_output_exactly() -> void:
	var legacy = S.legacy("difference_wp2")
	assert_object(legacy).is_not_null()
	var checked := 0
	for shape in _shapes():
		for op in range(5):
			for fn in range(4):
				for points_first in [true, false]:
					var a := _grid_points() if points_first else _shape(shape)
					var b := _shape(shape) if points_first else _grid_points()
					var now = S.run(DifferenceNode, _settings(op, fn, PC), [a, b])
					var then = S.run(legacy, _settings(op, fn), [a, b])
					assert_bool(_same_output(now, then)).override_failure_message("%s op %d fn %d" % [shape.get_type_name(), op, fn]).is_true()
					checked += 1
	assert_int(checked).is_equal(_shapes().size() * 40)

# --- box_overlap: exact paths --------------------------------------------------------------

func _brute_mean(shape : FlowSpatial, lo : Vector3, hi : Vector3, n : int = 24) -> float:
	var total := 0.0
	for i in n:
		for j in n:
			for k in n:
				var t := Vector3((i + 0.5) / n, (j + 0.5) / n, (k + 0.5) / n)
				total += shape.sample_density(lo + (hi - lo) * t)
	return total / float(n * n * n)

func test_box_overlap_exact_for_axis_aligned_boxes() -> void:
	# Scaled and axis-permuted (90 degrees about Y) box: still exact.
	var xform := Transform3D(Basis(Vector3.UP, PI / 2.0).scaled(Vector3(2, 1, 1)), Vector3(1, 0, 0))
	var box := FlowBoxVolume.new(xform, Vector3(1, 1, 1))
	assert_bool(FlowBoxVolume.basis_is_axis_aligned(xform.basis)).is_true()
	# World box: x [-1, 3], y [-1, 1], z [-1, 1]. Covered: 1 * 0.75 * 1/3.
	var lo := Vector3(0.0, -0.5, 0.5)
	var hi := Vector3(3.0, 1.5, 2.0)
	var ov := box.box_overlap(lo, hi)
	assert_float(ov.x).is_equal(1.0)
	assert_float(ov.y).is_equal_approx(0.25, 1e-5)
	assert_float(ov.y).is_equal_approx(_brute_mean(box, lo, hi), 0.01)
	# Fully inside: coverage 1; disjoint: (0, 0).
	assert_vector(box.box_overlap(Vector3(0.5, -0.5, -0.5), Vector3(1.5, 0.5, 0.5))).is_equal(Vector2(1, 1))
	assert_vector(box.box_overlap(Vector3(5, 5, 5), Vector3(6, 6, 6))).is_equal(Vector2.ZERO)
	# Soft box: the peak is the falloff at the nearest point of the point box.
	var soft := FlowBoxVolume.from_aabb(AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4)), 0.5)
	var sov := soft.box_overlap(Vector3(1.5, -0.5, -0.5), Vector3(3.0, 0.5, 0.5))
	assert_float(sov.x).is_equal_approx(FlowSpatial.falloff(0.75, 0.5), 1e-6)
	assert_bool(sov.y <= sov.x).is_true()
	# Rotated boxes use the sample set.
	var rotated := FlowBoxVolume.new(Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3.ZERO), Vector3.ONE)
	assert_bool(FlowBoxVolume.basis_is_axis_aligned(rotated.transform.basis)).is_false()
	assert_vector(rotated.box_overlap(lo, hi)).is_equal(FlowSpatial.box_overlap_sampled(rotated, lo, hi))

func test_box_overlap_exact_peak_for_spheres() -> void:
	var sphere := FlowSphereVolume.at(Vector3.ZERO, 2.0, 0.0)
	assert_float(sphere.box_overlap(Vector3(1, -0.5, -0.5), Vector3(3, 0.5, 0.5)).x).is_equal_approx(0.5, 1e-6)
	# Uniformly scaled and rotated sphere: same exact peak.
	var scaled := FlowSphereVolume.new(Transform3D(Basis(Vector3(1, 1, 0).normalized(), 0.7).scaled(Vector3(2, 2, 2)), Vector3.ZERO), 1.0, 0.0)
	assert_float(scaled.box_overlap(Vector3(1, -0.5, -0.5), Vector3(3, 0.5, 0.5)).x).is_equal_approx(0.5, 1e-5)
	# A small sphere inside a big point box between every sample: the exact peak
	# still sees it (the sample set alone would miss it).
	var small := FlowSphereVolume.at(Vector3(1, 1, 1), 0.5)
	assert_float(small.box_overlap(Vector3(-5, -5, -5), Vector3(5, 5, 5)).x).is_equal(1.0)
	assert_float(FlowSpatial.box_overlap_sampled(small, Vector3(-5, -5, -5), Vector3(5, 5, 5)).x).is_equal(0.0)
	# Ellipsoids fall back to the sample set.
	var ellipsoid := FlowSphereVolume.new(Transform3D(Basis().scaled(Vector3(2, 1, 1)), Vector3.ZERO), 1.0)
	var lo := Vector3(1.5, -0.5, -0.5)
	var hi := Vector3(3, 0.5, 0.5)
	assert_vector(ellipsoid.box_overlap(lo, hi)).is_equal(FlowSpatial.box_overlap_sampled(ellipsoid, lo, hi))

# --- box_overlap: fixed sample set -----------------------------------------------------------

func test_sample_set_is_centre_corners_and_face_centres() -> void:
	var samples := FlowSpatial.box_sample_points(Vector3(-1, -2, -3), Vector3(1, 2, 3))
	assert_int(samples.size()).is_equal(15)
	assert_vector(samples[0]).is_equal(Vector3.ZERO)
	for corner in [Vector3(-1, -2, -3), Vector3(1, 2, 3), Vector3(1, -2, 3)]:
		assert_bool(samples.has(corner)).is_true()
	for face in [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -2, 0), Vector3(0, 2, 0), Vector3(0, 0, -3), Vector3(0, 0, 3)]:
		assert_bool(samples.has(face)).is_true()
	# Deterministic.
	assert_array(Array(FlowSpatial.box_sample_points(Vector3(-1, -2, -3), Vector3(1, 2, 3)))).is_equal(Array(samples))

func test_sample_set_catches_partial_overlaps_for_other_shapes() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3(2, 2, 2)
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	var cases := [
		# [shape, point centre outside the shape, point size]
		[FlowBoxVolume.new(Transform3D(Basis(Vector3.UP, PI / 4.0), Vector3.ZERO), Vector3.ONE), Vector3(2.2, 0, 0), Vector3(2, 2, 2)],
		[FlowMeshVolume.from_meshes([cube], [Transform3D.IDENTITY]), Vector3(1.6, 0, 0), Vector3(2, 1, 1)],
		[FlowMeshSurface.from_meshes([plane], [Transform3D.IDENTITY]), Vector3(5.6, 0, 0), Vector3(2, 1, 1)],
		[FlowSplineShape.new(S.line_curve(Vector3(-5, 0, 0), Vector3(5, 0, 0)), Transform3D.IDENTITY, false, 1.0, 1.0), Vector3(0, 0, 1.8), Vector3(1, 1, 2)],
		[FlowCompositeShape.new(FlowSpatial.Op.Union, FlowSphereVolume.at(Vector3(-3, 0, 0), 1.0), FlowSphereVolume.new(Transform3D(Basis().scaled(Vector3(1, 2, 1)), Vector3(3, 0, 0)), 1.0)), Vector3(4.6, 0, 0), Vector3(2, 1, 1)],
	]
	for c in cases:
		var shape : FlowSpatial = c[0]
		var p := S.points([c[1]], [c[2]])
		assert_float(shape.sample_density(c[1])).override_failure_message(shape.get_type_name()).is_equal(0.0)
		assert_int(_run(DifferenceNode, p, _shape(shape), 0, 0, PC).size()).override_failure_message(shape.get_type_name()).is_equal(1)
		assert_int(_run(DifferenceNode, p, _shape(shape)).size()).override_failure_message(shape.get_type_name()).is_equal(0)
		assert_int(_run(DifferenceNode, p, _shape(shape), DifferenceSettings.eOperation.Intersection).size()).override_failure_message(shape.get_type_name()).is_equal(1)

func test_surface_column_is_not_rejected_on_y() -> void:
	# Surfaces are densities over their whole column (vertical_tolerance <= 0):
	# a point high above the plane overlaps it in both modes.
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	var surf := FlowMeshSurface.from_meshes([plane], [Transform3D.IDENTITY])
	var p := S.points([Vector3(0, 50, 0)])
	assert_int(_run(DifferenceNode, p, _shape(surf), 0, 0, PC).size()).is_equal(0)
	assert_int(_run(DifferenceNode, p, _shape(surf)).size()).is_equal(0)

func test_overlap_factor() -> void:
	assert_float(FlowSpatial.overlap_factor(Vector2(0.0, 0.0), 0.0)).is_equal(0.0)
	assert_float(FlowSpatial.overlap_factor(Vector2(0.8, 0.2), 1.0)).is_equal_approx(0.8, 1e-6)
	assert_float(FlowSpatial.overlap_factor(Vector2(1.0, 0.5), 0.0)).is_equal_approx(0.5, 1e-6)
	assert_float(FlowSpatial.overlap_factor(Vector2(0.5, 0.25), 0.0)).is_equal_approx(0.25, 1e-6)
	# Hard shape: identical to the point-versus-point factor of the penetration ratio.
	for s in [0.0, 0.3, 0.7]:
		assert_float(FlowSpatial.overlap_factor(Vector2(1.0, 0.4), s)).is_equal_approx(BoundsOverlapUtil.shape_factor(0.4, s), 1e-6)
