# debug_draw_shapes_test.gd
# WP7 requirement 3: the data preparation of the viewport debug draw
# (FlowDebugShapes) checked numerically, the caps on draw cost, the pure
# colour helpers of NodeDrawDebug, and the NodeDrawDebug wiring (which lines a
# node's debug settings produce) without looking at pixels.
class_name DebugDrawShapesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const EPS := 1e-4

func _curve(points: Array, bake_interval := 0.2) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = bake_interval
	for p in points:
		c.add_point(p)
	return c

static func _approx(a: Vector3, b: Vector3, eps := EPS) -> bool:
	return a.distance_to(b) <= eps

## Segments of a category as [a, b] pairs.
static func _segments(lines, category := "") -> Array:
	var out := []
	for i in range(0, lines.points.size(), 2):
		out.append([lines.points[i], lines.points[i + 1], lines.colors[i]])
	return out


# --- Splines ------------------------------------------------------------------------

func test_spline_polyline_is_the_baked_curve_through_the_transform() -> void:
	var curve := _curve([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 2, 10)])
	var xform := Transform3D(Basis(Vector3.UP, PI / 2), Vector3(5, 1, 0))
	var shape := FlowSplineShape.new(curve, xform)
	var poly := FlowDebugShapes.spline_polyline(shape)
	var baked := shape.curve.get_baked_points()
	assert_int(poly.size()).is_equal(baked.size())
	for i in range(baked.size()):
		assert_bool(_approx(poly[i], xform * baked[i])).is_true()
	assert_bool(_approx(poly[0], xform * Vector3.ZERO)).is_true()
	assert_bool(_approx(poly[poly.size() - 1], xform * Vector3(10, 2, 10))).is_true()
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape), { "color": Color.RED })
	assert_int(lines.counts.get("spline", 0)).is_equal(baked.size() - 1)
	assert_int(lines.segment_count()).is_equal(baked.size() - 1)
	for c in lines.colors:
		assert_that(c).is_equal(Color.RED)
	assert_bool(lines.truncated).is_false()


func test_closed_spline_is_closed() -> void:
	var shape := FlowSplineShape.new(_curve([Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(4, 0, 4)]), Transform3D.IDENTITY, true)
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	var segs := _segments(lines)
	var first : Vector3 = segs[0][0]
	var last : Vector3 = segs[segs.size() - 1][1]
	assert_bool(_approx(first, last)).override_failure_message("closed spline ends at %s, starts at %s" % [last, first]).is_true()


func test_long_spline_is_subsampled_to_the_cap() -> void:
	# Many control points with a fine bake interval: tens of thousands of baked points.
	var pts := []
	for i in range(40):
		pts.append(Vector3(100 * i, 0, 50 * (i % 2)))
	var shape := FlowSplineShape.new(_curve(pts, 0.05))
	assert_int(shape.curve.get_baked_points().size()).is_greater(FlowDebugShapes.MAX_SPLINE_POINTS)
	var poly := FlowDebugShapes.spline_polyline(shape)
	assert_int(poly.size()).is_equal(FlowDebugShapes.MAX_SPLINE_POINTS)
	assert_bool(_approx(poly[0], Vector3.ZERO)).is_true()
	assert_bool(_approx(poly[poly.size() - 1], pts[39], 0.05)).is_true()


# --- Volumes ------------------------------------------------------------------------

func test_box_volume_is_its_twelve_oriented_edges() -> void:
	var xform := Transform3D(Basis(Vector3.UP, 0.3), Vector3(1, 2, 3))
	var shape := FlowBoxVolume.new(xform, Vector3(1, 2, 3))
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	assert_int(lines.counts.get("box", 0)).is_equal(12)
	var corners := FlowDebugShapes.box_corners(xform, Vector3(1, 2, 3))
	for seg in _segments(lines):
		var la : Vector3 = xform.affine_inverse() * seg[0]
		var lb : Vector3 = xform.affine_inverse() * seg[1]
		# Each edge runs between two corners that differ along exactly one axis.
		var diff := (lb - la).abs()
		var axes := int(diff.x > EPS) + int(diff.y > EPS) + int(diff.z > EPS)
		assert_int(axes).is_equal(1)
		assert_bool(corners.has(seg[0]) and corners.has(seg[1])).is_true()


func test_sphere_volume_is_three_great_circles() -> void:
	var shape := FlowSphereVolume.at(Vector3(2, 0, -1), 3.0)
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	assert_int(lines.counts.get("sphere", 0)).is_equal(3 * FlowDebugShapes.CIRCLE_SEGMENTS)
	for p in lines.points:
		assert_float(p.distance_to(Vector3(2, 0, -1))).is_equal_approx(3.0, EPS)
	# A scaled transform draws the ellipsoid.
	var squashed := FlowSphereVolume.new(Transform3D(Basis.from_scale(Vector3(2, 1, 1)), Vector3.ZERO), 1.0)
	var circles := FlowDebugShapes.sphere_circles(squashed.transform, squashed.radius)
	assert_int(circles.size()).is_equal(3)
	for poly in circles:
		for p in poly:
			assert_float(Vector3(p.x / 2.0, p.y, p.z).length()).is_equal_approx(1.0, EPS)


func test_mesh_volume_draws_triangle_edges_or_bounds() -> void:
	var box := BoxMesh.new()
	var shape := FlowMeshVolume.from_meshes([box], [Transform3D.IDENTITY])
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	assert_int(lines.counts.get("mesh_volume", 0)).is_equal(shape.grid.tri_count * 3)
	# A dense mesh falls back to its bounds box.
	var sphere := SphereMesh.new()
	sphere.radial_segments = 128
	sphere.rings = 64
	var dense := FlowMeshVolume.from_meshes([sphere], [Transform3D.IDENTITY])
	assert_int(dense.grid.tri_count * 3).is_greater(FlowDebugShapes.MAX_MESH_EDGES)
	var dense_lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(dense))
	assert_int(dense_lines.counts.get("mesh_volume", 0)).is_equal(12)
	assert_bool(dense_lines.truncated).is_true()


func test_points_volume_draws_one_box_per_point() -> void:
	var shape := FlowPointsVolume.new(PackedVector3Array([Vector3.ZERO, Vector3(5, 0, 0)]), PackedVector3Array([Vector3.ONE, Vector3(6, 1, 1)]))
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	assert_int(lines.counts.get("points_volume", 0)).is_equal(24)


# --- Surfaces -----------------------------------------------------------------------

func test_polygon_surface_outline_at_its_height() -> void:
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 3), Vector2(0, 3)])
	var shape := FlowPolygonSurface.new(poly, Transform3D(Basis.IDENTITY, Vector3(0, 2, 0)), 1.0)
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	assert_int(lines.counts.get("polygon", 0)).is_equal(4)
	for p in lines.points:
		assert_float(p.y).is_equal_approx(3.0, EPS)
	assert_bool(lines.points.has(Vector3(4, 3, 3))).is_true()


func test_heightfield_border_and_grid_follow_the_heights() -> void:
	var w := 5
	var d := 4
	var heights := PackedFloat32Array()
	for j in range(d):
		for i in range(w):
			heights.append(float(i + 10 * j))
	var xform := Transform3D(Basis.IDENTITY, Vector3(100, 0, 0))
	var shape := FlowHeightfieldSurface.new(heights, w, d, 2.0, Vector3(-1, 0, 0), xform)
	var polys := FlowDebugShapes.heightfield_polylines(shape)
	# Small grid: one line per row and per column.
	assert_int(polys.size()).is_equal(w + d)
	for poly in polys:
		for p in poly:
			var l : Vector3 = xform.affine_inverse() * p
			var i := int(round((l.x + 1.0) / 2.0))
			var j := int(round(l.z / 2.0))
			assert_float(l.y).is_equal_approx(shape.get_height(i, j), EPS)
	# The first row is the border along local X at j = 0.
	assert_bool(_approx(polys[0][0], xform * Vector3(-1, 0, 0))).is_true()
	assert_bool(_approx(polys[0][w - 1], xform * Vector3(-1 + 2 * (w - 1), w - 1, 0))).is_true()


func test_large_heightfield_is_capped() -> void:
	var w := 1025
	var heights := PackedFloat32Array()
	heights.resize(w * w)
	var shape := FlowHeightfieldSurface.new(heights, w, w, 1.0)
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	var grid := FlowDebugShapes.SURFACE_GRID + 1
	assert_int(lines.counts.get("heightfield", 0)).is_equal(2 * grid * (FlowDebugShapes.HEIGHTFIELD_LINE_POINTS - 1))
	assert_bool(lines.truncated).is_true()
	assert_int(lines.segment_count()).is_less_equal(FlowDebugShapes.MAX_SEGMENTS)


func test_mesh_surface_grid_sits_on_the_surface() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	var shape := FlowMeshSurface.from_meshes([plane], [Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))])
	var polys := FlowDebugShapes.surface_grid_polylines(shape, shape.get_bounds())
	assert_int(polys.size()).is_equal(2 * (FlowDebugShapes.SURFACE_GRID + 1))
	for poly in polys:
		for p in poly:
			assert_float(p.y).is_equal_approx(3.0, EPS)
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	assert_int(lines.counts.get("mesh_surface", 0)).is_equal(12 + 2 * (FlowDebugShapes.SURFACE_GRID + 1) * FlowDebugShapes.SURFACE_GRID)


func test_mesh_surface_grid_splits_at_misses() -> void:
	# A surface covering only part of the probed bounds: polylines stop at its edge.
	var plane := PlaneMesh.new()
	plane.size = Vector2(4, 4)
	var shape := FlowMeshSurface.from_meshes([plane], [Transform3D.IDENTITY])
	var polys := FlowDebugShapes.surface_grid_polylines(shape, AABB(Vector3(-10, -1, -10), Vector3(20, 2, 20)))
	assert_int(polys.size()).is_greater(0)
	for poly in polys:
		for p in poly:
			assert_bool(absf(p.x) <= 2.0 + EPS and absf(p.z) <= 2.0 + EPS).is_true()


# --- Composites ---------------------------------------------------------------------

func test_composite_draws_both_parts_and_a_combining_indicator() -> void:
	var a := FlowBoxVolume.from_aabb(AABB(Vector3.ZERO, Vector3(4, 4, 4)))
	var b := FlowSphereVolume.at(Vector3(4, 2, 2), 1.0)
	var color := Color(0.2, 0.4, 1.0, 1.0)
	var expected_tint := color.lerp(FlowDebugShapes.OP_COLORS[FlowSpatial.Op.Difference], 0.7)
	for op in [FlowSpatial.Op.Union, FlowSpatial.Op.Intersection, FlowSpatial.Op.Difference]:
		var shape := FlowCompositeShape.new(op, a, b)
		var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape), { "color": color })
		assert_int(lines.counts.get("box", 0)).is_equal(12)
		assert_int(lines.counts.get("sphere", 0)).is_equal(3 * FlowDebugShapes.CIRCLE_SEGMENTS)
		var glyph := 1 if op == FlowSpatial.Op.Difference else 2
		assert_int(lines.counts.get("composite", 0)).is_equal(12 * 8 + glyph)
		# Operand A keeps the colour; B is tinted by the operation.
		var first_sphere_vertex := 2 * 12
		assert_that(lines.colors[0]).is_equal(color)
		var tint := color.lerp(FlowDebugShapes.OP_COLORS[op], 0.7)
		assert_bool(lines.colors[first_sphere_vertex].is_equal_approx(tint)).is_true()
		# The indicator sits on the composite's bounds.
		var bounds := shape.get_bounds().grow(EPS)
		for i in range(lines.points.size() - 2 * lines.counts.composite, lines.points.size()):
			assert_bool(bounds.has_point(lines.points[i])).is_true()
	assert_bool(expected_tint != color).is_true()


func test_deep_composites_are_capped() -> void:
	var shape : FlowSpatial = FlowBoxVolume.from_aabb(AABB(Vector3.ZERO, Vector3.ONE))
	for i in range(FlowDebugShapes.MAX_COMPOSITE_DEPTH + 4):
		shape = FlowCompositeShape.new(FlowSpatial.Op.Union, shape, FlowBoxVolume.from_aabb(AABB(Vector3(i, 0, 0), Vector3.ONE)))
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape))
	assert_bool(lines.truncated).is_true()
	assert_int(lines.segment_count()).is_less_equal(FlowDebugShapes.MAX_SEGMENTS)


func test_unknown_shape_draws_its_bounds() -> void:
	var lines := FlowDebugShapes.Lines.new()
	FlowDebugShapes.add_shape(lines, FlowSpatial.new(), Color.WHITE)
	assert_int(lines.counts.get("bounds", 0)).is_equal(12)


# --- Point bounds -------------------------------------------------------------------

func _points_with_bounds(n: int) -> FlowData.Data:
	var d := FlowData.Data.new()
	d.addCommonStreams(n)
	var pos : PackedVector3Array = d.getVector3Container(FlowData.AttrPosition)
	var rot : PackedVector3Array = d.getVector3Container(FlowData.AttrRotation)
	for i in range(n):
		pos[i] = Vector3(10 * i, 0, 0)
		rot[i] = Vector3(0, 90, 0)
	var bmin := PackedVector3Array()
	var bmax := PackedVector3Array()
	bmin.resize(n)
	bmax.resize(n)
	for i in range(n):
		bmin[i] = Vector3(0, 0, -1)
		bmax[i] = Vector3(2, 1, 1)
	d.registerStream(FlowData.AttrBoundsMin, bmin, FlowData.DataType.Vector)
	d.registerStream(FlowData.AttrBoundsMax, bmax, FlowData.DataType.Vector)
	return d


func test_point_bounds_boxes_follow_bounds_and_rotation() -> void:
	var d := _points_with_bounds(2)
	var boxes := FlowDebugShapes.point_bounds_boxes(d, 10)
	assert_int(boxes.size()).is_equal(2)
	var basis := FlowData.eulerToBasis(Vector3(0, 90, 0))
	for k in range(2):
		var corners : PackedVector3Array = boxes[k].corners
		var origin := Vector3(10 * k, 0, 0)
		for lc in [Vector3(0, 0, -1), Vector3(2, 1, 1), Vector3(2, 0, -1)]:
			var expected : Vector3 = origin + basis * lc
			var found := false
			for c in corners:
				if _approx(c, expected):
					found = true
			assert_bool(found).override_failure_message("corner %s of point %d missing in %s" % [expected, k, corners]).is_true()


func test_point_bounds_colours_selection_and_cap() -> void:
	var d := _points_with_bounds(3)
	var colours := PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var lines := FlowDebugShapes.build_for_data(d, { "point_colors": colours, "selected_row": 1, "selection_color": Color.MAGENTA })
	assert_int(lines.counts.get("point_bounds", 0)).is_equal(36)
	assert_that(lines.colors[0]).is_equal(Color.RED)
	assert_that(lines.colors[24]).is_equal(Color.MAGENTA)
	assert_that(lines.colors[48]).is_equal(Color.BLUE)
	# Turned off (NodeDrawDebug does so outside EXTENDS mode).
	var off := FlowDebugShapes.build_for_data(d, { "draw_point_bounds": false })
	assert_int(off.segment_count()).is_equal(0)
	# Without bounds streams nothing is drawn for points.
	var plain := FlowData.Data.new()
	plain.addCommonStreams(3)
	assert_int(FlowDebugShapes.build_for_data(plain).segment_count()).is_equal(0)
	# Cap.
	var many := _points_with_bounds(FlowDebugShapes.MAX_POINT_BOXES + 10)
	var capped := FlowDebugShapes.build_for_data(many, { "selected_row": FlowDebugShapes.MAX_POINT_BOXES + 5 })
	assert_int(capped.counts.point_bounds).is_equal(12 * (FlowDebugShapes.MAX_POINT_BOXES + 1))
	assert_bool(capped.truncated).is_true()


func test_segment_cap_truncates() -> void:
	var shape := FlowSphereVolume.at(Vector3.ZERO, 1.0)
	var lines := FlowDebugShapes.build_for_data(FlowData.Data.from_shape(shape), { "max_segments": 10 })
	assert_int(lines.segment_count()).is_equal(10)
	assert_bool(lines.truncated).is_true()


# --- NodeDrawDebug ------------------------------------------------------------------

func test_grayscale_colours_match_the_point_cube_rule() -> void:
	var colours := NodeDrawDebug.grayscale_colors(PackedFloat32Array([0.0, 5.0, 10.0]), 0.5)
	assert_float(colours[0].r).is_equal_approx(0.08, EPS)
	assert_float(colours[1].r).is_equal_approx(lerpf(0.08, 1.0, 0.5), EPS)
	assert_float(colours[2].r).is_equal_approx(1.0, EPS)
	assert_float(colours[2].a).is_equal_approx(0.5, EPS)
	# Equal values are clamped to 0..1 instead of normalised.
	var flat := NodeDrawDebug.grayscale_colors(PackedFloat32Array([0.25, 0.25]), 1.0)
	assert_float(flat[0].r).is_equal_approx(lerpf(0.08, 1.0, 0.25), EPS)


func test_extended_types_can_modulate_the_debug_draw() -> void:
	var cases := {
		FlowData.DataType.Int64: [PackedInt64Array([1, 1 << 40]), [1.0, float(1 << 40)]],
		FlowData.DataType.Double: [PackedFloat64Array([0.5, 2.0]), [0.5, 2.0]],
		FlowData.DataType.Vector2: [PackedVector2Array([Vector2(3, 4), Vector2.ZERO]), [5.0, 0.0]],
		FlowData.DataType.Vector4: [PackedVector4Array([Vector4(0, 0, 3, 4), Vector4.ZERO]), [5.0, 0.0]],
		FlowData.DataType.Quaternion: [PackedVector4Array([Vector4(0, 0, 0, 1), Vector4(0, 0, 0, 1)]), [1.0, 1.0]],
	}
	for t in cases:
		var stream := { "data_type": t, "container": cases[t][0], "name": "s" }
		assert_bool(NodeDrawDebug._can_modulate_stream(stream)).is_true()
		var values := NodeDrawDebug._stream_to_intensities(stream, 2)
		assert_int(values.size()).is_equal(2)
		for i in range(2):
			assert_float(values[i]).is_equal_approx(cases[t][1][i], 1.0)
	assert_bool(NodeDrawDebug._can_modulate_stream({ "data_type": FlowData.DataType.Transform, "container": [], "name": "t" })).is_false()


func _debug_widget(data: FlowData.Data) -> FlowNodeWidget:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path("copy")).new()
	element.node_template = "copy"
	element.settings = element.getMeta().settings.new()
	var widget := FlowNodeWidget.new()
	widget.name = "dbg"
	widget.element = element
	element.generated_bulks = [[data]]
	widget.settings.debug_enabled = true
	widget.settings.debug_color = Color(1, 0.5, 0, 1)
	add_child(widget)
	return widget


func test_node_draw_debug_draws_shape_only_data() -> void:
	var shape := FlowBoxVolume.from_aabb(AABB(Vector3.ZERO, Vector3.ONE))
	var widget := _debug_widget(FlowData.Data.from_shape(shape))
	widget.setupDrawDebug()
	var lines = widget.draw_debug.last_lines
	assert_object(lines).is_not_null()
	assert_int(lines.counts.get("box", 0)).is_equal(12)
	assert_that(lines.colors[0]).is_equal(Color(1, 0.5, 0, 1))
	assert_bool(widget.draw_debug.lines_mesh_rid.is_valid()).is_true()
	# Turning debug off frees the line mesh.
	widget.settings.debug_enabled = false
	widget.refresh_ui()
	assert_bool(widget.draw_debug.lines_mesh_rid.is_valid()).is_false()
	remove_child(widget)
	widget.free()


func test_node_draw_debug_point_bounds_follow_the_debug_mode() -> void:
	var d := _points_with_bounds(3)
	var widget := _debug_widget(d)
	widget.debug_row = 2
	widget.setupDrawDebug()
	var lines = widget.draw_debug.last_lines
	assert_int(lines.counts.get("point_bounds", 0)).is_equal(36)
	# The selected row uses the selection colour.
	assert_that(lines.colors[48]).is_equal(widget.draw_debug.selection_color)
	# Colours follow the cubes' modulation: 'density' is the same for all, so
	# every box gets the same grey (density 1 clamps to white).
	var cube_colours : PackedColorArray = widget.draw_debug.compute_point_colors(d)
	assert_that(lines.colors[0]).is_equal(cube_colours[0])
	# ABSOLUTE mode draws fixed-size cubes and no bounds boxes.
	widget.settings.debug_mode = NodeSettings.eDebugMode.ABSOLUTE
	widget.setupDrawDebug()
	assert_int(widget.draw_debug.last_lines.segment_count()).is_equal(0)
	remove_child(widget)
	widget.free()
