# point_neighborhood_test.gd
class_name PointNeighborhoodTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointNeighborhoodNode = preload("res://addons/flow_nodes_editor/nodes/point_neighborhood.gd")
const PointNeighborhoodSettings = preload("res://addons/flow_nodes_editor/nodes/point_neighborhood_settings.gd")

func _make_point_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	return d

func _make_point_data_with_density(positions: PackedVector3Array, densities: PackedFloat32Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	d.registerStream("density", densities, FlowDataScript.DataType.Float)
	return d

func _run(inputs: Array, settings) -> PointNeighborhoodNode:
	var node = PointNeighborhoodNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

func test_neighbor_count_unlimited_distance() -> void:
	var s = PointNeighborhoodSettings.new()
	s.search_distance = 0.0
	s.include_self = false
	s.write_neighbor_count = true
	s.out_neighbor_count = "neighbor_count"
	s.write_distance_to_center = false
	s.write_average_center = false
	s.write_average_density = false
	s.write_average_color = false

	var positions := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(2, 0, 0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("neighbor_count")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_int(stream.container[0]).is_equal(2)
	assert_int(stream.container[1]).is_equal(2)
	assert_int(stream.container[2]).is_equal(2)

func test_neighbor_count_with_distance_limit() -> void:
	var s = PointNeighborhoodSettings.new()
	s.search_distance = 1.5
	s.include_self = false
	s.write_neighbor_count = true
	s.out_neighbor_count = "neighbor_count"
	s.write_distance_to_center = false
	s.write_average_center = false
	s.write_average_density = false
	s.write_average_color = false

	var positions := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(10, 0, 0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("neighbor_count")
	assert_object(stream).is_not_null()
	assert_int(stream.container[0]).is_equal(1)
	assert_int(stream.container[1]).is_equal(1)
	assert_int(stream.container[2]).is_equal(0)

func test_average_center_collinear_points() -> void:
	var s = PointNeighborhoodSettings.new()
	s.search_distance = 0.0
	s.include_self = false
	s.write_neighbor_count = false
	s.write_distance_to_center = false
	s.write_average_center = true
	s.out_average_center = "avg_center"
	s.write_average_density = false
	s.write_average_color = false

	var positions := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(2, 0, 0),
		Vector3(4, 0, 0),
	])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("avg_center")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	var center0 : Vector3 = stream.container[0]
	assert_float(center0.x).is_equal_approx(3.0, 0.001)
	var center1 : Vector3 = stream.container[1]
	assert_float(center1.x).is_equal_approx(2.0, 0.001)
	var center2 : Vector3 = stream.container[2]
	assert_float(center2.x).is_equal_approx(1.0, 0.001)

func test_average_density_computed() -> void:
	var s = PointNeighborhoodSettings.new()
	s.search_distance = 0.0
	s.include_self = false
	s.write_neighbor_count = false
	s.write_distance_to_center = false
	s.write_average_center = false
	s.write_average_density = true
	s.density_attribute = "density"
	s.out_average_density = "avg_density"
	s.write_average_color = false

	var positions := PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(2, 0, 0),
	])
	var densities := PackedFloat32Array([10.0, 20.0, 30.0])
	var node = _run([_make_point_data_with_density(positions, densities)], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("avg_density")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(25.0, 0.001)
	assert_float(stream.container[1]).is_equal_approx(20.0, 0.001)
	assert_float(stream.container[2]).is_equal_approx(15.0, 0.001)

func test_null_input_sets_error() -> void:
	var s = PointNeighborhoodSettings.new()
	s.write_neighbor_count = true
	s.write_distance_to_center = false
	s.write_average_center = false
	s.write_average_density = false
	s.write_average_color = false

	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

func test_missing_density_attribute_errors() -> void:
	var s = PointNeighborhoodSettings.new()
	s.search_distance = 0.0
	s.include_self = false
	s.write_neighbor_count = false
	s.write_distance_to_center = false
	s.write_average_center = false
	s.write_average_density = true
	s.density_attribute = "nonexistent_attr"
	s.out_average_density = "avg_density"
	s.write_average_color = false

	var positions := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	var node = _run([_make_point_data(positions)], s)
	assert_str(node.err).is_not_empty()
