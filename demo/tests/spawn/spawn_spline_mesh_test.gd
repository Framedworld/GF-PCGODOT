# spawn_spline_mesh_test.gd
# Spawn Spline Mesh: one MeshInstance3D per segment of each Path3D (or spline
# shape through the extraction hook), bent mesh cached, per-segment entries,
# collision, ownership, pooling and the owner-less contract.
class_name SpawnSplineMeshTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const SpawnSplineMeshNode = preload("res://addons/flow_nodes_editor/nodes/spawn_spline_mesh.gd")
const SpawnSplineMeshSettingsScript = preload("res://addons/flow_nodes_editor/nodes/spawn_spline_mesh_settings.gd")

const EPS := 1e-3

## Stand-in for a spline shape (WP2's FlowSplineShape): only the duck-typed
## surface the extraction hook reads.
class FakeSplineShape extends RefCounted:
	var curve : Curve3D
	var transform : Transform3D = Transform3D.IDENTITY
	func get_kind() -> int:
		return FlowData.Kind.Spline

var _owner : FlowGraphNode3D

func before_test() -> void:
	FlowSplineBend.clear_cache()
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SpawnOwner"
	add_child(_owner)

func _make(node_name := "spline_spawner") -> Node:
	var node = SpawnSplineMeshNode.new()
	node.name = node_name
	node.settings = SpawnSplineMeshSettingsScript.new()
	return auto_free(node)

func _path(points : Array, at := Vector3.ZERO, closed := false) -> Path3D:
	var path := Path3D.new()
	var c := Curve3D.new()
	for p in points:
		c.add_point(p)
	c.closed = closed
	path.curve = c
	path.position = at
	_owner.add_child(path)
	return path

func _splines(paths : Array) -> FlowData.Data:
	var d := FlowData.Data.new()
	d.registerStream("node", Array(paths, TYPE_OBJECT, "Node", null), FlowData.DataType.NodePath)
	return d

func _segments() -> Array:
	return S.spawned(_owner, MeshInstance3D)

func test_one_bent_mesh_per_control_point_segment() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 4), Vector3(0, 0, 10)])
	var node = _make()
	var input := _splines([path])
	S.run(node, input, _owner)
	assert_str(node.err).is_empty()
	var segs = _segments()
	assert_int(segs.size()).is_equal(2)
	assert_str(str(segs[0].name)).is_equal("SplineMesh_0000")
	assert_str(str(segs[1].name)).is_equal("SplineMesh_0001")
	for seg in segs:
		assert_object(seg.mesh).is_instanceof(ArrayMesh)
		assert_bool(seg.has_meta("flow_owner")).is_true()
		assert_dict(seg.get_meta("flow_owner")).contains_key_value("node", "spline_spawner")
	# The unit cube is stretched over each segment along Z.
	var a0 : AABB = segs[0].mesh.get_aabb()
	var a1 : AABB = segs[1].mesh.get_aabb()
	assert_vector(a0.position).is_equal_approx(Vector3(-0.5, -0.5, 0), Vector3(EPS, EPS, EPS))
	assert_vector(a0.size).is_equal_approx(Vector3(1, 1, 4), Vector3(EPS, EPS, EPS))
	assert_vector(a1.position).is_equal_approx(Vector3(-0.5, -0.5, 4), Vector3(EPS, EPS, EPS))
	assert_vector(a1.size).is_equal_approx(Vector3(1, 1, 6), Vector3(EPS, EPS, EPS))
	assert_object(S.out(node)).is_same(input)

func test_closed_curve_adds_the_closing_segment() -> void:
	var path := _path([Vector3.ZERO, Vector3(4, 0, 0), Vector3(4, 0, 4)], Vector3.ZERO, true)
	var node = _make()
	S.run(node, _splines([path]), _owner)
	assert_int(_segments().size()).is_equal(3)

func test_segments_follow_the_path_transform() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 2)], Vector3(5, 1, 0))
	var node = _make()
	S.run(node, _splines([path]), _owner)
	var seg : MeshInstance3D = _segments()[0]
	assert_vector(seg.transform.origin).is_equal_approx(Vector3(5, 1, 0), Vector3(EPS, EPS, EPS))

func test_tile_mesh_segmentation_repeats_the_mesh_along_the_spline() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 10)])
	var node = _make()
	node.settings.segmentation = SpawnSplineMeshSettingsScript.eSegmentation.TileMesh
	S.run(node, _splines([path]), _owner)
	assert_int(_segments().size()).is_equal(10)
	node.settings.scale_along = 2.0
	S.run(node, _splines([path]), _owner)
	var segs = _segments()
	assert_int(segs.size()).is_equal(5)
	var meta : Dictionary = segs[4].get_meta("spline_segment")
	assert_float(meta.from).is_equal_approx(8.0, EPS)
	assert_float(meta.to).is_equal_approx(10.0, EPS)

func test_segments_for_spline_is_pure_and_covers_the_whole_length() -> void:
	var c := Curve3D.new()
	c.add_point(Vector3.ZERO)
	c.add_point(Vector3(3, 0, 0))
	c.add_point(Vector3(3, 0, 7))
	var segs := SpawnSplineMeshNode.segments_for_spline(c, Transform3D.IDENTITY, SpawnSplineMeshSettingsScript.eSegmentation.ControlPoints, 1.0)
	assert_int(segs.size()).is_equal(2)
	assert_float(segs[0].from_offset).is_equal(0.0)
	assert_float(segs[0].to_offset).is_equal_approx(3.0, EPS)
	assert_float(segs[1].to_offset).is_equal_approx(c.get_baked_length(), EPS)
	assert_object(segs[0].curve).is_same(c)

func test_per_segment_entries_cycle() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 2), Vector3(0, 0, 4), Vector3(0, 0, 6)])
	var node = _make()
	var red := S.entry(BoxMesh.new())
	red.material_override = StandardMaterial3D.new()
	var blue := S.entry(BoxMesh.new())
	blue.material_override = StandardMaterial3D.new()
	blue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.settings.mesh_entries = [red, blue] as Array[FlowMeshSpawnEntry]
	S.run(node, _splines([path]), _owner)
	var segs = _segments()
	assert_int(segs.size()).is_equal(3)
	assert_object(segs[0].material_override).is_same(red.material_override)
	assert_object(segs[1].material_override).is_same(blue.material_override)
	assert_int(segs[1].cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_object(segs[2].material_override).is_same(red.material_override)

func test_weighted_segment_selection_is_deterministic() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 2), Vector3(0, 0, 4), Vector3(0, 0, 6), Vector3(0, 0, 8)])
	var node = _make()
	var a := S.entry(BoxMesh.new())
	a.material_override = StandardMaterial3D.new()
	var b := S.entry(BoxMesh.new(), 0.0)
	b.material_override = StandardMaterial3D.new()
	node.settings.mesh_entries = [a, b] as Array[FlowMeshSpawnEntry]
	node.settings.segment_selection = SpawnSplineMeshSettingsScript.eSegmentSelection.Weighted
	S.run(node, _splines([path]), _owner)
	for seg in _segments():
		assert_object(seg.material_override).is_same(a.material_override)

func test_bent_meshes_are_cached_across_runs() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 4)])
	var node = _make()
	S.run(node, _splines([path]), _owner)
	var first : Mesh = _segments()[0].mesh
	S.run(node, _splines([path]), _owner)
	assert_object(_segments()[0].mesh).is_same(first)
	assert_int(FlowSplineBend.cache_hits).is_equal(1)

func test_segment_collision_from_the_bent_mesh() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 4)])
	var node = _make()
	var e := S.entry(BoxMesh.new())
	e.collision_mode = FlowMeshSpawnEntry.eCollisionMode.Trimesh
	e.collision_bodies = FlowMeshSpawnEntry.eCollisionBodies.PerInstance
	e.collision_layer = 2
	node.settings.mesh_entries = [e] as Array[FlowMeshSpawnEntry]
	S.run(node, _splines([path]), _owner)
	var seg : MeshInstance3D = _segments()[0]
	assert_int(seg.get_child_count()).is_equal(1)
	var body : StaticBody3D = seg.get_child(0)
	assert_int(body.collision_layer).is_equal(2)
	var shape : ConcavePolygonShape3D = body.get_node("Shape").shape
	var zmax := -INF
	for v in shape.get_faces():
		zmax = maxf(zmax, v.z)
	assert_float(zmax).is_equal_approx(4.0, EPS)

func test_shape_hook_accepts_a_duck_typed_spline_shape() -> void:
	var shape := FakeSplineShape.new()
	shape.curve = Curve3D.new()
	shape.curve.add_point(Vector3.ZERO)
	shape.curve.add_point(Vector3(0, 0, 3))
	shape.transform = Transform3D(Basis.IDENTITY, Vector3(1, 0, 0))
	var splines := SpawnSplineMeshNode.splines_from_shape(shape)
	assert_int(splines.size()).is_equal(1)
	assert_object(splines[0].curve).is_same(shape.curve)
	assert_vector(splines[0].transform.origin).is_equal(Vector3(1, 0, 0))
	assert_array(SpawnSplineMeshNode.splines_from_shape(null)).is_empty()
	assert_array(SpawnSplineMeshNode.splines_from_shape(RefCounted.new())).is_empty()

func test_missing_spline_stream_is_an_error() -> void:
	var node = _make()
	S.run(node, S.points(2), _owner)
	assert_str(node.err).contains("'node'")
	assert_int(_segments().size()).is_equal(0)

func test_unconnected_input_is_an_error() -> void:
	var node = _make()
	S.run(node, null, _owner)
	assert_str(node.err).contains("not connected")

func test_owner_less_reports_error_and_passes_input_through() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 4)])
	var node = _make()
	var input := _splines([path])
	S.run(node, input, null)
	assert_str(node.err).contains("needs an owner node")
	assert_object(S.out(node)).is_same(input)
	assert_int(_segments().size()).is_equal(0)

func test_clear_and_pool_reuse() -> void:
	var path := _path([Vector3.ZERO, Vector3(0, 0, 4), Vector3(0, 0, 8)])
	var node = _make()
	S.run(node, _splines([path]), _owner)
	var first = _segments()
	S.run(node, _splines([path]), _owner)
	assert_bool(first[0].is_queued_for_deletion()).is_true()
	node.settings.reuse_instances = true
	S.run(node, _splines([path]), _owner)
	var pooled = S.ids(_segments())
	S.run(node, _splines([path]), _owner)
	assert_array(S.ids(_segments())).is_equal(pooled)
	assert_str(str(_segments()[1].name)).is_equal("SplineMesh_0001")
