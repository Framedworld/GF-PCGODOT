# WP11 item 7: spawn_spline_mesh reads every spline part of a composite shape,
# so the Merged output of get_spline_data (a union composite) is spawned.
class_name SplineMeshCompositeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spawn/spawn_test_support.gd")
const SpawnSplineMeshNode = preload("res://addons/flow_nodes_editor/nodes/spawn_spline_mesh.gd")
const SpawnSplineMeshSettingsScript = preload("res://addons/flow_nodes_editor/nodes/spawn_spline_mesh_settings.gd")
const GetSplineData = preload("res://addons/flow_nodes_editor/nodes/get_spline_data.gd")
const GetSplineDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_spline_data_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	FlowSplineBend.clear_cache()
	_owner = auto_free(FlowGraphNode3D.new())
	_owner.name = "SplineOwner"
	add_child(_owner)

func _curve(points : Array) -> Curve3D:
	var c := Curve3D.new()
	for p in points:
		c.add_point(p)
	return c

func _spline(points : Array, at := Vector3.ZERO) -> FlowSplineShape:
	return FlowSplineShape.new(_curve(points), Transform3D(Basis.IDENTITY, at))

func _box() -> FlowSpatial:
	return FlowBoxVolume.new(Transform3D.IDENTITY, Vector3.ONE * 2.0)

func _origins(splines : Array) -> Array:
	var out := []
	for s in splines:
		out.append(s.transform.origin)
	return out

func test_union_composite_yields_every_spline_in_merge_order() -> void:
	var s0 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(0, 0, 0))
	var s1 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(10, 0, 0))
	var s2 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(20, 0, 0))
	var merged := FlowCompositeShape.union_of([s0, s1, s2])
	assert_int(merged.get_kind()).is_equal(FlowDataScript.Kind.Volume)
	var splines := SpawnSplineMeshNode.splines_from_shape(merged)
	assert_int(splines.size()).is_equal(3)
	assert_array(_origins(splines)).is_equal([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0)])
	assert_object(splines[1].curve).is_same(s1.curve)
	assert_object(splines[2].source).is_same(s2)

func test_difference_keeps_only_the_splines_of_its_first_operand() -> void:
	var s0 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(1, 0, 0))
	var s1 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(2, 0, 0))
	var kept := FlowCompositeShape.new(FlowSpatial.Op.Difference, s0, s1)
	assert_array(_origins(SpawnSplineMeshNode.splines_from_shape(kept))).is_equal([Vector3(1, 0, 0)])
	var cut_by_spline := FlowCompositeShape.new(FlowSpatial.Op.Difference, _box(), s0)
	assert_array(SpawnSplineMeshNode.splines_from_shape(cut_by_spline)).is_empty()

func test_intersection_and_nested_composites() -> void:
	var s0 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(1, 0, 0))
	var s1 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(2, 0, 0))
	var s2 := _spline([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(3, 0, 0))
	var inter := FlowCompositeShape.new(FlowSpatial.Op.Intersection, s0, _box())
	assert_array(_origins(SpawnSplineMeshNode.splines_from_shape(inter))).is_equal([Vector3(1, 0, 0)])
	var nested := FlowCompositeShape.new(FlowSpatial.Op.Union, FlowCompositeShape.new(FlowSpatial.Op.Union, s0, _box()), FlowCompositeShape.new(FlowSpatial.Op.Union, s1, s2))
	assert_array(_origins(SpawnSplineMeshNode.splines_from_shape(nested))).is_equal([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0)])
	# A composite without any spline part gives nothing.
	assert_array(SpawnSplineMeshNode.splines_from_shape(FlowCompositeShape.new(FlowSpatial.Op.Union, _box(), _box()))).is_empty()

func _path(points : Array, at : Vector3) -> Path3D:
	var path := Path3D.new()
	path.curve = _curve(points)
	path.position = at
	_owner.add_child(path)
	return path

func _run_get_spline_data(mode : int):
	var node = GetSplineData.new()
	node.name = "splines"
	var s = GetSplineDataSettings.new()
	s.output_mode = mode
	node.settings = s
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = _owner
	ctx.gedit_nodes_by_name = {}
	node.preExecute(ctx)
	node.inputs = []
	node.execute(ctx)
	assert_str(node.err).is_empty()
	return node.generated_bulks

func test_merged_get_spline_data_spawns_every_spline() -> void:
	_path([Vector3.ZERO, Vector3(0, 0, 4), Vector3(0, 0, 8)], Vector3(0, 0, 0))   # 2 segments
	_path([Vector3.ZERO, Vector3(0, 0, 4)], Vector3(10, 0, 0))                    # 1 segment
	_path([Vector3.ZERO, Vector3(4, 0, 0), Vector3(8, 0, 0)], Vector3(20, 0, 0))  # 2 segments
	var bulks = _run_get_spline_data(GetSplineDataSettings.eOutputMode.Merged)
	assert_int(bulks.size()).is_equal(1)
	var merged : FlowData.Data = bulks[0][0]
	assert_object(merged.shape).is_instanceof(FlowCompositeShape)
	var spawner = SpawnSplineMeshNode.new()
	spawner.name = "spline_spawner"
	spawner.settings = SpawnSplineMeshSettingsScript.new()
	S.run(spawner, merged, _owner)
	assert_str(spawner.err).is_empty()
	assert_int(S.spawned(_owner, MeshInstance3D).size()).is_equal(5)
