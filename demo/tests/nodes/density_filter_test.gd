# density_filter_test.gd
class_name DensityFilterTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DensityFilterNode = preload("res://addons/flow_nodes_editor/nodes/density_filter.gd")
const DensityFilterSettings = preload("res://addons/flow_nodes_editor/nodes/density_filter_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _make_data_with_density(densities: PackedFloat32Array) -> FlowData.Data:
	return _make_data("density", densities, FlowDataScript.DataType.Float)

func _run(inputs: Array, settings) -> DensityFilterNode:
	var node = DensityFilterNode.new()
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

func _output_at(node, bulk_idx: int, slot_idx: int) -> FlowData.Data:
	if node.generated_bulks.size() <= bulk_idx:
		return null
	var bulk = node.generated_bulks[bulk_idx]
	if bulk.size() <= slot_idx:
		return null
	return bulk[slot_idx]

func _in_filter(node) -> FlowData.Data:
	return _output_at(node, node.num_generated_bulks - 1, 0)

func _outside_filter(node) -> FlowData.Data:
	return _output_at(node, node.num_generated_bulks - 1, 1)

func test_basic_filter_splits_inside_and_outside() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 1.0
	var densities := PackedFloat32Array([0.2, 0.6, 0.9, 0.4, 1.0])
	var d := _make_data_with_density(densities)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	var outside = _outside_filter(node)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	var in_stream = inside.findStream("density")
	var out_stream = outside.findStream("density")
	assert_object(in_stream).is_not_null()
	assert_object(out_stream).is_not_null()
	assert_array(in_stream.container).is_equal(PackedFloat32Array([0.6, 0.9, 1.0]))
	assert_array(out_stream.container).is_equal(PackedFloat32Array([0.2, 0.4]))
	node.free()

func test_missing_density_stream_defaults_to_one() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 1.0
	var d := FlowDataScript.Data.new()
	var positions := PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)])
	d.registerStream("position", positions, FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	assert_object(inside).is_not_null()
	assert_int(inside.size()).is_equal(2)
	node.free()

func test_invert_filter_swaps_outputs() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 1.0
	s.invert_filter = true
	var densities := PackedFloat32Array([0.2, 0.6, 0.9, 0.4, 1.0])
	var d := _make_data_with_density(densities)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	var outside = _outside_filter(node)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	var in_stream = inside.findStream("density")
	var out_stream = outside.findStream("density")
	assert_array(in_stream.container).is_equal(PackedFloat32Array([0.2, 0.4]))
	assert_array(out_stream.container).is_equal(PackedFloat32Array([0.6, 0.9, 1.0]))
	node.free()

func test_empty_input_produces_empty_outputs() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 1.0
	var d := FlowDataScript.Data.new()
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	var outside = _outside_filter(node)
	assert_object(inside).is_not_null()
	assert_object(outside).is_not_null()
	assert_int(inside.size()).is_equal(0)
	assert_int(outside.size()).is_equal(0)
	node.free()

func test_missing_input_produces_error() -> void:
	var s = DensityFilterSettings.new()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_all_points_inside_range() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.0
	s.upper_bound = 1.0
	var densities := PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	var d := _make_data_with_density(densities)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	var outside = _outside_filter(node)
	assert_int(inside.size()).is_equal(5)
	assert_int(outside.size()).is_equal(0)
	node.free()

func test_all_points_outside_range() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.6
	s.upper_bound = 0.8
	var densities := PackedFloat32Array([0.1, 0.2, 0.9, 1.0])
	var d := _make_data_with_density(densities)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	var outside = _outside_filter(node)
	assert_int(inside.size()).is_equal(0)
	assert_int(outside.size()).is_equal(4)
	node.free()

func test_single_point_inside() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 1.0
	var densities := PackedFloat32Array([0.7])
	var d := _make_data_with_density(densities)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	var outside = _outside_filter(node)
	assert_int(inside.size()).is_equal(1)
	assert_int(outside.size()).is_equal(0)
	node.free()

func test_single_point_outside() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 1.0
	var densities := PackedFloat32Array([0.3])
	var d := _make_data_with_density(densities)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	var outside = _outside_filter(node)
	assert_int(inside.size()).is_equal(0)
	assert_int(outside.size()).is_equal(1)
	node.free()

func test_boundary_values_inclusive() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 0.8
	var densities := PackedFloat32Array([0.5, 0.8])
	var d := _make_data_with_density(densities)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	assert_int(inside.size()).is_equal(1)
	node.free()

func test_additional_streams_preserved_on_filtered_output() -> void:
	var s = DensityFilterSettings.new()
	s.lower_bound = 0.5
	s.upper_bound = 1.0
	var d := FlowDataScript.Data.new()
	d.registerStream("density", PackedFloat32Array([0.2, 0.7, 0.9]), FlowDataScript.DataType.Float)
	d.registerStream("position", PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(2,0,0)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var inside = _in_filter(node)
	assert_object(inside).is_not_null()
	assert_int(inside.size()).is_equal(2)
	var pos_stream = inside.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_array(pos_stream.container).is_equal(PackedVector3Array([Vector3(1,0,0), Vector3(2,0,0)]))
	node.free()
