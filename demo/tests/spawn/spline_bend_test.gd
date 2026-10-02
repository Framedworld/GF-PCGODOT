# spline_bend_test.gd
# Numerical tests of the spline-mesh bend math (FlowSplineBend, pure functions):
# a straight segment leaves a mesh unchanged up to the stretch along the
# forward axis and a translation; a quarter circle maps the forward axis onto
# the arc by arc length; cross-section scaling, Linear tangents, normals and
# the bent-mesh cache.
class_name SplineBendTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const EPS := 1e-3

func before_test() -> void:
	FlowSplineBend.clear_cache()

func _line(from : Vector3, to : Vector3) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(from)
	c.add_point(to)
	return c

## Quarter circle of radius r in the XZ plane, from (r,0,0) to (0,0,r).
func _quarter_circle(r : float) -> Curve3D:
	var k := 0.5522847498 * r
	var c := Curve3D.new()
	c.bake_interval = 0.05
	c.add_point(Vector3(r, 0, 0), Vector3.ZERO, Vector3(0, 0, k))
	c.add_point(Vector3(0, 0, r), Vector3(k, 0, 0), Vector3.ZERO)
	return c

func _box_vertices() -> PackedVector3Array:
	return BoxMesh.new().get_mesh_arrays()[Mesh.ARRAY_VERTEX]

func _opts(axis : int, extra := {}) -> Dictionary:
	var o := { "forward_axis": axis }
	o.merge(extra, true)
	return o

func test_local_basis_is_a_proper_rotation_for_every_axis() -> void:
	for axis in [FlowSplineBend.eAxis.X, FlowSplineBend.eAxis.Y, FlowSplineBend.eAxis.Z]:
		var b := FlowSplineBend.local_basis(axis)
		assert_float(b.determinant()).is_equal_approx(1.0, 1e-6)
		assert_vector(b.z).is_equal(FlowSplineBend.axis_vector(axis))

func test_straight_segment_along_z_only_stretches_the_forward_axis() -> void:
	var length := 4.0
	var curve := _line(Vector3.ZERO, Vector3(0, 0, length))
	var verts := _box_vertices()
	var bent := FlowSplineBend.bend_positions(verts, curve, 0.0, curve.get_baked_length(), Vector2(-0.5, 0.5), _opts(FlowSplineBend.eAxis.Z))
	for i in range(verts.size()):
		var expected := Vector3(verts[i].x, verts[i].y, (verts[i].z + 0.5) * length)
		assert_vector(bent[i]).is_equal_approx(expected, Vector3(EPS, EPS, EPS))

func test_straight_segment_along_x_only_stretches_the_forward_axis() -> void:
	var length := 3.0
	var origin := Vector3(10, 2, -5)
	var curve := _line(origin, origin + Vector3(length, 0, 0))
	var verts := _box_vertices()
	var bent := FlowSplineBend.bend_positions(verts, curve, 0.0, curve.get_baked_length(), Vector2(-0.5, 0.5), _opts(FlowSplineBend.eAxis.X))
	for i in range(verts.size()):
		var expected := origin + Vector3((verts[i].x + 0.5) * length, verts[i].y, verts[i].z)
		assert_vector(bent[i]).is_equal_approx(expected, Vector3(EPS, EPS, EPS))

func test_straight_segment_world_up_matches_curve_up_on_flat_curves() -> void:
	var curve := _line(Vector3.ZERO, Vector3(0, 0, 2))
	var verts := _box_vertices()
	var a := FlowSplineBend.bend_positions(verts, curve, 0.0, 2.0, Vector2(-0.5, 0.5), _opts(FlowSplineBend.eAxis.Z, { "up_mode": FlowSplineBend.eUpMode.CurveUp }))
	var b := FlowSplineBend.bend_positions(verts, curve, 0.0, 2.0, Vector2(-0.5, 0.5), _opts(FlowSplineBend.eAxis.Z, { "up_mode": FlowSplineBend.eUpMode.WorldUp }))
	for i in range(verts.size()):
		assert_vector(a[i]).is_equal_approx(b[i], Vector3(EPS, EPS, EPS))

func test_partial_segment_maps_onto_its_offsets() -> void:
	var curve := _line(Vector3.ZERO, Vector3(0, 0, 10))
	var p := FlowSplineBend.bend_point(Vector3(0, 0, -0.5), curve, 2.0, 6.0, Vector2(-0.5, 0.5), {})
	var q := FlowSplineBend.bend_point(Vector3(0, 0, 0.5), curve, 2.0, 6.0, Vector2(-0.5, 0.5), {})
	assert_vector(p).is_equal_approx(Vector3(0, 0, 2), Vector3(EPS, EPS, EPS))
	assert_vector(q).is_equal_approx(Vector3(0, 0, 6), Vector3(EPS, EPS, EPS))

func test_quarter_circle_maps_the_forward_axis_onto_the_arc_by_arc_length() -> void:
	var r := 5.0
	var curve := _quarter_circle(r)
	var total := curve.get_baked_length()
	assert_float(total).is_equal_approx(PI * r / 2.0, 0.01)
	for step in range(11):
		var t := step / 10.0
		var local := Vector3(0, 0, t - 0.5)
		var p := FlowSplineBend.bend_point(local, curve, 0.0, total, Vector2(-0.5, 0.5), {})
		assert_float(Vector2(p.x, p.z).length()).is_equal_approx(r, 0.01)
		assert_float(p.y).is_equal_approx(0.0, 1e-4)
		var angle := atan2(p.z, p.x)
		assert_float(angle).is_equal_approx(t * PI / 2.0, 0.005)

func test_quarter_circle_cross_section_stays_radial() -> void:
	var r := 5.0
	var curve := _quarter_circle(r)
	var total := curve.get_baked_length()
	for step in range(11):
		var t := step / 10.0
		# side +0.5 (local +X) lands outside the arc, side -0.5 inside it,
		# up +0.5 (local +Y) straight above the centreline.
		var outer := FlowSplineBend.bend_point(Vector3(0.5, 0, t - 0.5), curve, 0.0, total, Vector2(-0.5, 0.5), {})
		var inner := FlowSplineBend.bend_point(Vector3(-0.5, 0, t - 0.5), curve, 0.0, total, Vector2(-0.5, 0.5), {})
		var above := FlowSplineBend.bend_point(Vector3(0, 0.5, t - 0.5), curve, 0.0, total, Vector2(-0.5, 0.5), {})
		assert_float(Vector2(outer.x, outer.z).length()).is_equal_approx(r + 0.5, 0.01)
		assert_float(Vector2(inner.x, inner.z).length()).is_equal_approx(r - 0.5, 0.01)
		assert_float(Vector2(above.x, above.z).length()).is_equal_approx(r, 0.01)
		assert_float(above.y).is_equal_approx(0.5, 1e-3)

func test_linear_tangent_mode_follows_the_chord() -> void:
	var r := 5.0
	var curve := _quarter_circle(r)
	var total := curve.get_baked_length()
	var o := { "tangent_mode": FlowSplineBend.eTangentMode.Linear }
	var mid := FlowSplineBend.bend_point(Vector3(0, 0, 0), curve, 0.0, total, Vector2(-0.5, 0.5), o)
	assert_vector(mid).is_equal_approx(Vector3(r / 2.0, 0, r / 2.0), Vector3(EPS, EPS, EPS))

func test_scale_across_interpolates_from_start_to_end() -> void:
	var curve := _line(Vector3.ZERO, Vector3(0, 0, 2))
	var o := { "scale_start": Vector2(2, 1), "scale_end": Vector2(4, 3) }
	var start := FlowSplineBend.bend_point(Vector3(0.5, 0.5, -0.5), curve, 0.0, 2.0, Vector2(-0.5, 0.5), o)
	var finish := FlowSplineBend.bend_point(Vector3(0.5, 0.5, 0.5), curve, 0.0, 2.0, Vector2(-0.5, 0.5), o)
	assert_vector(start).is_equal_approx(Vector3(1.0, 0.5, 0), Vector3(EPS, EPS, EPS))
	assert_vector(finish).is_equal_approx(Vector3(2.0, 1.5, 2), Vector3(EPS, EPS, EPS))

func test_bend_arrays_keeps_normals_on_a_straight_segment_and_other_arrays() -> void:
	var arrays := BoxMesh.new().get_mesh_arrays()
	var curve := _line(Vector3.ZERO, Vector3(0, 0, 3))
	var out := FlowSplineBend.bend_arrays(arrays, curve, 0.0, 3.0, Vector2(-0.5, 0.5), {})
	var n_in : PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var n_out : PackedVector3Array = out[Mesh.ARRAY_NORMAL]
	for i in range(n_in.size()):
		assert_vector(n_out[i]).is_equal_approx(n_in[i], Vector3(EPS, EPS, EPS))
	assert_array(Array(out[Mesh.ARRAY_TEX_UV])).is_equal(Array(arrays[Mesh.ARRAY_TEX_UV]))
	assert_array(Array(out[Mesh.ARRAY_INDEX])).is_equal(Array(arrays[Mesh.ARRAY_INDEX]))
	# The input arrays are not modified.
	assert_array(Array(arrays[Mesh.ARRAY_VERTEX])).is_equal(Array(BoxMesh.new().get_mesh_arrays()[Mesh.ARRAY_VERTEX]))

func test_bend_mesh_keeps_surfaces_and_bounds() -> void:
	var curve := _line(Vector3.ZERO, Vector3(0, 0, 5))
	var src := BoxMesh.new()
	src.material = StandardMaterial3D.new()
	var bent := FlowSplineBend.bend_mesh(src, curve, 0.0, 5.0, {})
	assert_int(bent.get_surface_count()).is_equal(1)
	assert_object(bent.surface_get_material(0)).is_same(src.material)
	var aabb := bent.get_aabb()
	assert_vector(aabb.position).is_equal_approx(Vector3(-0.5, -0.5, 0), Vector3(EPS, EPS, EPS))
	assert_vector(aabb.size).is_equal_approx(Vector3(1, 1, 5), Vector3(EPS, EPS, EPS))

func test_bent_mesh_cache_hits_for_identical_segments_and_misses_otherwise() -> void:
	var curve := _line(Vector3.ZERO, Vector3(0, 0, 5))
	var mesh := BoxMesh.new()
	var a := FlowSplineBend.bent_mesh_cached(mesh, curve, 0.0, 5.0, {})
	var b := FlowSplineBend.bent_mesh_cached(mesh, curve, 0.0, 5.0, {})
	assert_object(b).is_same(a)
	assert_int(FlowSplineBend.cache_hits).is_equal(1)
	var c := FlowSplineBend.bent_mesh_cached(mesh, curve, 0.0, 2.5, {})
	assert_object(c).is_not_same(a)
	# Editing the curve changes its content hash: no stale hit.
	curve.set_point_position(1, Vector3(0, 0, 6))
	var d := FlowSplineBend.bent_mesh_cached(mesh, curve, 0.0, 5.0, {})
	assert_object(d).is_not_same(a)
	assert_int(FlowSplineBend.cache_misses).is_equal(3)
	assert_int(FlowSplineBend.cache_size()).is_equal(3)
	FlowSplineBend.clear_cache()
	assert_int(FlowSplineBend.cache_size()).is_equal(0)
