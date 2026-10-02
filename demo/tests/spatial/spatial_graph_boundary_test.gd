# spatial_graph_boundary_test.gd
# WP2: shapes travel across graph boundaries (graph inputs, subgraph input and
# output nodes, component outputs) through Data.copy_meta_from, and a whole
# spatial chain (shape sources -> set operation -> sampler) evaluates as a graph.
class_name SpatialGraphBoundaryTest extends GdUnitTestSuite

const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")

func _eval(graph : FlowGraphResource, inputs : Dictionary = {}) -> Dictionary:
	return FlowNodeIO.evaluate_graph(graph, inputs, TestGraph.make_ctx(), {}, 0)

func _box_settings(size : Vector3, center : Vector3 = Vector3.ZERO) -> Dictionary:
	return {"output_mode": 1, "size": size, "center": center}

## inner: item (graph input) minus a small box, published as "result".
func _inner_cut_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Float) \
		.node("in_item", "input_item", {"name": "item", "data_type": FlowData.DataType.Float}) \
		.node("hole", "make_bounds", _box_settings(Vector3(2, 2, 2))) \
		.node("cut", "difference", {"operation": 0}) \
		.node("inner_out", "output", {"name": "result"}) \
		.link("in_item", 0, "cut", 0) \
		.link("hole", 0, "cut", 1) \
		.link("cut", 0, "inner_out", 0) \
		.build()

func test_shape_crosses_graph_input_and_output() -> void:
	var box := FlowBoxVolume.new(Transform3D.IDENTITY, Vector3(5, 5, 5))
	var item := FlowData.Data.from_shape(box)
	item.tags = PackedStringArray(["zone"])
	var outputs := _eval(_inner_cut_graph(), {"item": item})
	var result : FlowData.Data = outputs.get("result")
	assert_object(result).is_not_null()
	assert_object(result.shape).is_instanceof(FlowCompositeShape)
	assert_object(result.shape.a).is_same(box)
	assert_int(result.kind).is_equal(FlowData.Kind.Volume)
	assert_array(Array(result.tags)).is_equal(["zone"])
	assert_float(result.shape.sample_density(Vector3(3, 0, 0))).is_equal(1.0)
	assert_float(result.shape.sample_density(Vector3(0, 0, 0))).is_equal(0.0)

func test_shape_crosses_subgraph_boundary_both_ways() -> void:
	var graph = TestGraph.new() \
		.node("zone", "make_bounds", _box_settings(Vector3(10, 10, 10))) \
		.node("sub", "subgraph", {"graph": _inner_cut_graph()}) \
		.node("out", "output", {"name": "final"}) \
		.link("zone", 0, "sub", 0) \
		.link("sub", 0, "out", 0) \
		.build()
	var outputs := _eval(graph)
	var final : FlowData.Data = outputs.get("final")
	assert_object(final).is_not_null()
	assert_object(final.shape).is_instanceof(FlowCompositeShape)
	assert_int(final.shape.op).is_equal(FlowSpatial.Op.Difference)
	assert_int(final.size()).is_equal(0)
	assert_float(final.shape.sample_density(Vector3(4, 0, 0))).is_equal(1.0)
	assert_float(final.shape.sample_density(Vector3(0.5, 0, 0))).is_equal(0.0)
	# Content hash is stable across evaluations (fresh shapes, same geometry).
	assert_int(_eval(graph).get("final").content_hash()).is_equal(final.content_hash())

func test_spatial_chain_evaluates_as_graph() -> void:
	# Volume minus a hole, made concrete by to_point inside a graph.
	var graph = TestGraph.new() \
		.node("zone", "make_bounds", _box_settings(Vector3(4, 1, 4), Vector3(0, 0.5, 0))) \
		.node("hole", "make_bounds", _box_settings(Vector3(2, 1, 2), Vector3(0, 0.5, 0))) \
		.node("cut", "difference", {"operation": 0}) \
		.node("pts", "to_point", {"voxel_size": Vector3(1, 1, 1)}) \
		.node("out", "output", {"name": "points"}) \
		.link("zone", 0, "cut", 0) \
		.link("hole", 0, "cut", 1) \
		.link("cut", 0, "pts", 0) \
		.link("pts", 0, "out", 0) \
		.build()
	var pts : FlowData.Data = _eval(graph).get("points")
	assert_object(pts).is_not_null()
	assert_object(pts.shape).is_null()
	# One voxel layer (y in 0..1): 4x4 voxels in the zone minus the 2x2 hole.
	assert_int(pts.size()).is_equal(12)
