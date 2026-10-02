# spatial_source_nodes_test.gd
# WP2 source nodes: get_spline_data, get_surface_data, get_volume_data, to_point,
# get_bounds and make_bounds (Shape mode). Scenes are built in code, headless.
class_name SpatialSourceNodesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spatial/support/spatial_test_support.gd")

const GetSplineData = preload("res://addons/flow_nodes_editor/nodes/get_spline_data.gd")
const GetSplineDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_spline_data_settings.gd")
const GetSurfaceData = preload("res://addons/flow_nodes_editor/nodes/get_surface_data.gd")
const GetSurfaceDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_surface_data_settings.gd")
const GetVolumeData = preload("res://addons/flow_nodes_editor/nodes/get_volume_data.gd")
const GetVolumeDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_volume_data_settings.gd")
const ToPoint = preload("res://addons/flow_nodes_editor/nodes/to_point.gd")
const ToPointSettings = preload("res://addons/flow_nodes_editor/nodes/to_point_settings.gd")
const GetBounds = preload("res://addons/flow_nodes_editor/nodes/get_bounds.gd")
const GetBoundsSettings = preload("res://addons/flow_nodes_editor/nodes/get_bounds_settings.gd")
const MakeBounds = preload("res://addons/flow_nodes_editor/nodes/make_bounds.gd")
const MakeBoundsSettings = preload("res://addons/flow_nodes_editor/nodes/make_bounds_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	add_child(_owner)

func _grouped(node : Node, group : String, parent : Node = null) -> Node:
	(parent if parent != null else _owner).add_child(node)
	if group != "":
		node.add_to_group(group)
	return node

func _path(curve : Curve3D, at : Vector3, group : String = "roads") -> Path3D:
	var p := Path3D.new()
	p.curve = curve
	p.position = at
	return _grouped(p, group)

# --- get_spline_data -------------------------------------------------------------------

func test_get_spline_data_per_spline() -> void:
	_path(S.line_curve(Vector3.ZERO, Vector3(10, 0, 0)), Vector3(0, 1, 0))
	_path(S.square_curve(2.0), Vector3(20, 0, 0))
	_path(S.line_curve(Vector3.ZERO, Vector3(1, 0, 0)), Vector3.ZERO, "")	# not in the group
	var s = GetSplineDataSettings.new()
	s.group_name = "roads"
	s.tube_half_width = 2.5
	var node = S.run(GetSplineData, s, [], _owner)
	var outs := S.outputs(node)
	assert_int(outs.size()).is_equal(2)
	for d in outs:
		assert_object(d.shape).is_instanceof(FlowSplineShape)
		assert_int(d.kind).is_equal(FlowData.Kind.Spline)
		assert_int(d.size()).is_equal(0)
		assert_float(d.shape.half_width).is_equal(2.5)
	assert_float(outs[0].get_data_attr("spline_length")).is_equal_approx(10.0, 1e-3)
	assert_str(outs[0].get_data_attr("source")).is_not_empty()
	# World transform is applied.
	assert_float(outs[0].shape.sample_density(Vector3(5, 1, 0))).is_equal(1.0)
	S.release(node)

func test_get_spline_data_merged_and_copies_curve() -> void:
	var p := _path(S.line_curve(Vector3.ZERO, Vector3(10, 0, 0)), Vector3.ZERO)
	_path(S.line_curve(Vector3.ZERO, Vector3(0, 0, 10)), Vector3(30, 0, 0))
	var s = GetSplineDataSettings.new()
	s.group_name = "roads"
	s.output_mode = GetSplineDataSettings.eOutputMode.Merged
	var node = S.run(GetSplineData, s, [], _owner)
	var outs := S.outputs(node)
	assert_int(outs.size()).is_equal(1)
	assert_int(outs[0].shape.union_leaves().size()).is_equal(2)
	assert_int(outs[0].get_data_attr("spline_count")).is_equal(2)
	var h : int = outs[0].content_hash()
	p.curve.set_point_position(1, Vector3(0, 50, 0))	# scene edit after generation
	assert_int(outs[0].content_hash()).is_equal(h)
	S.release(node)

func test_get_spline_data_fingerprint_tracks_curve_edits() -> void:
	var p := _path(S.line_curve(Vector3.ZERO, Vector3(10, 0, 0)), Vector3.ZERO)
	var s = GetSplineDataSettings.new()
	s.group_name = "roads"
	var node = S.run(GetSplineData, s, [], _owner)
	var ctx := FlowDataScript.EvaluationContext.new()
	ctx.owner = _owner
	var f1 = node.computeSceneFingerprint(ctx)
	p.curve.add_point(Vector3(20, 0, 0))
	assert_bool(node.computeSceneFingerprint(ctx) != f1).is_true()
	S.release(node)

func test_get_spline_data_ownerless_reports_and_emits_empty() -> void:
	var node = S.run(GetSplineData, GetSplineDataSettings.new(), [], null)
	assert_str(node.err).contains("owner")
	assert_int(S.outputs(node).size()).is_equal(1)
	assert_object(S.output(node).shape).is_null()
	S.release(node)

# --- get_surface_data ------------------------------------------------------------------

func _heightmap_shape_node(at : Vector3, group : String) -> CollisionShape3D:
	var hm := HeightMapShape3D.new()
	hm.map_width = 3
	hm.map_depth = 3
	hm.map_data = PackedFloat32Array([0, 0, 0, 1, 1, 1, 2, 2, 2])
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.position = at
	return _grouped(cs, group)

func test_get_surface_data_meshes_and_heightmaps() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = S.plane_mesh(10.0, 1)
	mi.position = Vector3(0, 2, 0)
	_grouped(mi, "ground")
	_heightmap_shape_node(Vector3(40, 0, 0), "ground")
	var s = GetSurfaceDataSettings.new()
	s.group_name = "ground"
	s.output_mode = GetSurfaceDataSettings.eOutputMode.PerSource
	var node = S.run(GetSurfaceData, s, [], _owner)
	var outs := S.outputs(node)
	assert_int(outs.size()).is_equal(2)
	assert_object(outs[0].shape).is_instanceof(FlowMeshSurface)
	assert_object(outs[1].shape).is_instanceof(FlowHeightfieldSurface)
	assert_float(outs[0].shape.project(Vector3(1, 50, 1)).position.y).is_equal_approx(2.0, 1e-4)
	assert_float(outs[1].shape.project_vertical(40.5, 0.5).position.y).is_equal_approx(1.5, 1e-4)
	S.release(node)
	s.output_mode = GetSurfaceDataSettings.eOutputMode.Merged
	node = S.run(GetSurfaceData, s, [], _owner)
	outs = S.outputs(node)
	assert_int(outs.size()).is_equal(1)
	assert_int(outs[0].kind).is_equal(FlowData.Kind.Surface)
	assert_object(outs[0].shape).is_instanceof(FlowCompositeShape)
	assert_int(outs[0].get_data_attr("source_count")).is_equal(2)
	S.release(node)

func test_get_surface_data_heightmap_image() -> void:
	var img := Image.create(5, 5, false, Image.FORMAT_RF)
	for y in 5:
		for x in 5:
			img.set_pixel(x, y, Color(float(x), 0, 0))
	var s = GetSurfaceDataSettings.new()
	s.source = GetSurfaceDataSettings.eSource.HeightmapImage
	s.heightmap_image = img
	s.image_cell_size = 2.0
	s.image_height_scale = 3.0
	var node = S.run(GetSurfaceData, s, [], null)	# no scene needed
	var d := S.output(node)
	assert_str(node.err).is_empty()
	assert_object(d.shape).is_instanceof(FlowHeightfieldSurface)
	assert_float(d.shape.project(Vector3(1, 0, 0)).position.y).is_equal_approx(7.5, 1e-4)
	S.release(node)
	s.heightmap_image = null
	node = S.run(GetSurfaceData, s, [], null)
	assert_str(node.err).is_not_empty()
	S.release(node)

# --- get_volume_data ---------------------------------------------------------------------

func _collision(shape : Shape3D, at : Vector3, group : String, parent : Node = null) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = at
	return _grouped(cs, group, parent)

func test_get_volume_data_collision_shapes_area_csg_and_meshes() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	_collision(box, Vector3(0, 0, 0), "vols")
	var sphere := SphereShape3D.new()
	sphere.radius = 1.5
	_collision(sphere, Vector3(10, 0, 0), "vols")
	var capsule := CapsuleShape3D.new()
	_collision(capsule, Vector3(20, 0, 0), "vols")
	var area := Area3D.new()
	area.position = Vector3(30, 0, 0)
	_grouped(area, "vols")
	var area_box := BoxShape3D.new()
	_collision(area_box, Vector3.ZERO, "", area)
	var csg := CSGBox3D.new()
	csg.size = Vector3(4, 1, 4)
	csg.position = Vector3(40, 0, 0)
	_grouped(csg, "vols")
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.position = Vector3(50, 0, 0)
	_grouped(mi, "vols")
	var s = GetVolumeDataSettings.new()
	s.group_name = "vols"
	s.include_meshes = true
	s.output_mode = GetVolumeDataSettings.eOutputMode.PerVolume
	var node = S.run(GetVolumeData, s, [], _owner)
	var outs := S.outputs(node)
	assert_int(outs.size()).is_equal(6)
	var types := outs.map(func(d): return d.shape.get_type_name())
	assert_array(types).contains(["Box Volume", "Sphere Volume", "Mesh Volume"])
	var merged_shapes := outs.map(func(d): return d.shape)
	var u := FlowCompositeShape.union_of(merged_shapes)
	for probe in [Vector3(0.9, 0, 0), Vector3(11.4, 0, 0), Vector3(20, 0.5, 0), Vector3(30.4, 0, 0), Vector3(41.9, 0, 0), Vector3(50.4, 0, 0)]:
		assert_float(u.sample_density(probe)).override_failure_message(str(probe)).is_equal(1.0)
	for probe in [Vector3(1.1, 0, 0), Vector3(5, 0, 0), Vector3(42.1, 0, 0)]:
		assert_float(u.sample_density(probe)).override_failure_message(str(probe)).is_equal(0.0)
	S.release(node)
	s.output_mode = GetVolumeDataSettings.eOutputMode.Merged
	node = S.run(GetVolumeData, s, [], _owner)
	assert_int(S.outputs(node).size()).is_equal(1)
	assert_int(S.output(node).kind).is_equal(FlowData.Kind.Volume)
	S.release(node)

func test_get_volume_data_steepness() -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	_collision(box, Vector3.ZERO, "soft")
	var s = GetVolumeDataSettings.new()
	s.group_name = "soft"
	s.steepness = 0.5
	var node = S.run(GetVolumeData, s, [], _owner)
	assert_float(S.output(node).shape.sample_density(Vector3(0.75, 0, 0))).is_equal_approx(0.5, 1e-5)
	S.release(node)

# --- to_point ------------------------------------------------------------------------------

func test_to_point_every_kind() -> void:
	var shapes := [
		FlowSplineShape.new(S.line_curve(Vector3.ZERO, Vector3(10, 0, 0))),
		FlowMeshSurface.from_meshes([S.plane_mesh()], [Transform3D.IDENTITY]),
		FlowBoxVolume.new(Transform3D.IDENTITY, Vector3(2, 2, 2)),
		FlowCompositeShape.new(FlowSpatial.Op.Intersection, FlowMeshSurface.from_meshes([S.plane_mesh()], [Transform3D.IDENTITY]), FlowSphereVolume.at(Vector3.ZERO, 3.0)),
	]
	for shape in shapes:
		var s = ToPointSettings.new()
		s.points_per_square_meter = 1.0
		var input := FlowDataScript.Data.from_shape(shape)
		input.tags = PackedStringArray(["keep"])
		input.set_data_attr("level", 3)
		var node = S.run(ToPoint, s, [input])
		var d := S.output(node)
		assert_str(node.err).is_empty()
		assert_int(d.size()).override_failure_message(shape.get_type_name()).is_greater(0)
		assert_object(d.shape).is_null()
		assert_int(d.kind).is_equal(FlowData.Kind.Points)
		assert_array(Array(d.tags)).is_equal(["keep"])
		assert_int(d.get_data_attr("level")).is_equal(3)
		for p in d.getVector3Container(FlowData.AttrPosition):
			assert_bool(shape.sample_density(p) > 0.0).is_true()
		S.release(node)

func test_to_point_passes_points_through_and_reports_caps() -> void:
	var pts := S.points([Vector3.ONE])
	var node = S.run(ToPoint, ToPointSettings.new(), [pts])
	assert_object(S.output(node)).is_same(pts)
	S.release(node)
	var s = ToPointSettings.new()
	s.voxel_size = Vector3(0.01, 0.01, 0.01)
	s.max_candidates = 1000
	node = S.run(ToPoint, s, [FlowDataScript.Data.from_shape(FlowBoxVolume.new(Transform3D.IDENTITY, Vector3(5, 5, 5)))])
	assert_str(node.err).contains("voxel")
	S.release(node)

func test_to_point_is_seeded() -> void:
	var shape := FlowMeshSurface.from_meshes([S.plane_mesh(20.0, 1)], [Transform3D.IDENTITY])
	var s1 = ToPointSettings.new()
	var s2 = ToPointSettings.new()
	s2.random_seed = 777
	var a = S.run(ToPoint, s1, [FlowDataScript.Data.from_shape(shape)])
	var b = S.run(ToPoint, s1, [FlowDataScript.Data.from_shape(shape)])
	var c = S.run(ToPoint, s2, [FlowDataScript.Data.from_shape(shape)])
	assert_int(S.output(a).content_hash()).is_equal(S.output(b).content_hash())
	assert_int(S.output(a).content_hash()).is_not_equal(S.output(c).content_hash())
	for n in [a, b, c]:
		S.release(n)

# --- get_bounds / make_bounds ----------------------------------------------------------------

func test_get_bounds_of_shape_and_points() -> void:
	var box := FlowBoxVolume.new(Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)), Vector3(1, 2, 3))
	var node = S.run(GetBounds, GetBoundsSettings.new(), [FlowDataScript.Data.from_shape(box)])
	var d := S.output(node)
	assert_int(d.size()).is_equal(1)
	assert_vector(d.getVector3Container(FlowData.AttrPosition)[0]).is_equal_approx(Vector3(10, 0, 0), Vector3.ONE * 1e-5)
	assert_vector(d.getVector3Container(FlowData.AttrBoundsMax)[0]).is_equal_approx(Vector3(1, 2, 3), Vector3.ONE * 1e-5)
	assert_vector(d.get_data_attr("bounds_min")).is_equal_approx(Vector3(9, -2, -3), Vector3.ONE * 1e-5)
	S.release(node)
	node = S.run(GetBounds, GetBoundsSettings.new(), [S.points([Vector3(0, 0, 0), Vector3(4, 0, 0)])])
	assert_vector(S.output(node).get_data_attr("bounds_max")).is_equal_approx(Vector3(4.5, 0.5, 0.5), Vector3.ONE * 1e-5)
	S.release(node)
	var s = GetBoundsSettings.new()
	s.output_mode = GetBoundsSettings.eOutputMode.Shape
	node = S.run(GetBounds, s, [S.points([Vector3(0, 0, 0), Vector3(4, 0, 0)])])
	assert_object(S.output(node).shape).is_instanceof(FlowBoxVolume)
	assert_float(S.output(node).shape.sample_density(Vector3(2, 0, 0))).is_equal(1.0)
	S.release(node)

func test_make_bounds_shape_mode() -> void:
	var s = MakeBoundsSettings.new()
	s.output_mode = MakeBoundsSettings.eOutputMode.Shape
	s.size = Vector3(4, 2, 4)
	s.center = Vector3(1, 0, 0)
	var node = S.run(MakeBounds, s, [])
	var d := S.output(node)
	assert_int(d.size()).is_equal(0)
	assert_int(d.kind).is_equal(FlowData.Kind.Volume)
	assert_float(d.shape.sample_density(Vector3(2.9, 0, 0))).is_equal(1.0)
	assert_float(d.shape.sample_density(Vector3(3.1, 0, 0))).is_equal(0.0)
	S.release(node)
