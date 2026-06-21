# grid_fill_bounds_test.gd
class_name GridFillBoundsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GridFillBoundsNode = preload("res://addons/flow_nodes_editor/nodes/grid_fill_bounds.gd")
const GridFillBoundsSettings = preload("res://addons/flow_nodes_editor/nodes/grid_fill_bounds_settings.gd")

func _make_bounds_data(positions: PackedVector3Array, sizes: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(positions.size())
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	if sizes.size() > 0:
		d.registerStream(FlowData.AttrSize, sizes, FlowDataScript.DataType.Vector)
	return d

func _default_settings() -> GridFillBoundsNodeSettings:
	var s := GridFillBoundsSettings.new()
	s.use_input_bounds = false
	s.bounds_center = Vector3.ZERO
	s.bounds_size = Vector3(3.0, 1.0, 3.0)
	s.cell_size = Vector3.ONE
	s.fill_y_axis = false
	s.copy_input_attributes = false
	s.source_index_attribute = ""
	s.max_points = 100000
	return s

func _run(inputs: Array, settings) -> GridFillBoundsNode:
	var node = GridFillBoundsNode.new()
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

# bounds_size=(3,1,3), cell_size=(1,1,1), fill_y=false
# x: roundi(3/1)=3, y: single layer, z: roundi(3/1)=3 -> 3*1*3 = 9 cells
func test_static_bounds_2d_grid() -> void:
	var s := _default_settings()
	s.bounds_center = Vector3.ZERO
	s.bounds_size = Vector3(3.0, 1.0, 3.0)
	s.cell_size = Vector3.ONE
	s.fill_y_axis = false
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(9)
	node.free()

# bounds_size=(2,2,2), cell_size=(1,1,1), fill_y=true
# x: roundi(2/1)=2, y: roundi(2/1)=2, z: roundi(2/1)=2 -> 2*2*2 = 8 cells
func test_static_bounds_3d_grid_fill_y() -> void:
	var s := _default_settings()
	s.bounds_center = Vector3.ZERO
	s.bounds_size = Vector3(2.0, 2.0, 2.0)
	s.cell_size = Vector3.ONE
	s.fill_y_axis = true
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(8)
	node.free()

# Output must always contain position, size, rotation, density, and seed streams
func test_output_has_required_streams() -> void:
	var s := _default_settings()
	s.bounds_size = Vector3(2.0, 1.0, 2.0)
	s.cell_size = Vector3.ONE
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream(FlowData.AttrPosition)).is_not_null()
	assert_object(out.findStream(FlowData.AttrSize)).is_not_null()
	assert_object(out.findStream(FlowData.AttrRotation)).is_not_null()
	assert_object(out.findStream(FlowData.AttrDensity)).is_not_null()
	assert_object(out.findStream(FlowData.AttrSeed)).is_not_null()
	node.free()

# Each output size stream entry should equal cell_size
# bounds_size=(1,1,1), cell_size=(0.5,0.5,0.5), fill_y=false
# x: roundi(1/0.5)=2, z: roundi(1/0.5)=2 -> 2*1*2 = 4 cells
func test_cell_size_used_for_out_size_stream() -> void:
	var s := _default_settings()
	s.bounds_center = Vector3.ZERO
	s.bounds_size = Vector3(1.0, 1.0, 1.0)
	s.cell_size = Vector3(0.5, 0.5, 0.5)
	s.fill_y_axis = false
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var size_stream = out.findStream(FlowData.AttrSize)
	assert_object(size_stream).is_not_null()
	var sizes = size_stream.container
	for i in range(sizes.size()):
		assert_float(sizes[i].x).is_equal_approx(0.5, 0.0001)
		assert_float(sizes[i].z).is_equal_approx(0.5, 0.0001)
	node.free()

# max_points cap is enforced
func test_max_points_limit() -> void:
	var s := _default_settings()
	s.bounds_center = Vector3.ZERO
	s.bounds_size = Vector3(100.0, 1.0, 100.0)
	s.cell_size = Vector3.ONE
	s.fill_y_axis = false
	s.max_points = 5
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(5)
	node.free()

# When source_index_attribute is set, all points should have index 0 (single static bounds)
func test_source_index_attribute_written() -> void:
	var s := _default_settings()
	s.bounds_size = Vector3(2.0, 1.0, 2.0)
	s.cell_size = Vector3.ONE
	s.source_index_attribute = "src_idx"
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var idx_stream = out.findStream("src_idx")
	assert_object(idx_stream).is_not_null()
	var indices = idx_stream.container
	for i in range(indices.size()):
		assert_int(indices[i]).is_equal(0)
	node.free()

# Input bounds mode with a single bound of size (3,1,3) -> 9 output cells
func test_use_input_bounds_single_bound() -> void:
	var s := _default_settings()
	s.use_input_bounds = true
	s.cell_size = Vector3.ONE
	s.fill_y_axis = false
	s.copy_input_attributes = false
	var positions := PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var sizes := PackedVector3Array([Vector3(3.0, 1.0, 3.0)])
	var in_data = _make_bounds_data(positions, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(9)
	node.free()

# Empty input data with use_input_bounds -> empty output, no error
func test_use_input_bounds_empty_input_returns_empty() -> void:
	var s := _default_settings()
	s.use_input_bounds = true
	s.cell_size = Vector3.ONE
	var empty_data := FlowDataScript.Data.new()
	var node = _run([empty_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)
	node.free()

# Input data with size stream but NO position stream -> error set
func test_use_input_bounds_missing_position_sets_error() -> void:
	var s := _default_settings()
	s.use_input_bounds = true
	s.cell_size = Vector3.ONE
	var bad_data := FlowDataScript.Data.new()
	var dummy_sizes := PackedVector3Array([Vector3(2.0, 1.0, 2.0)])
	bad_data.registerStream(FlowData.AttrSize, dummy_sizes, FlowDataScript.DataType.Vector)
	var node = _run([bad_data], s)
	assert_str(node.err).is_not_empty()
	node.free()

# copy_input_attributes copies custom streams into output, one value per cell
func test_copy_input_attributes_propagated() -> void:
	var s := _default_settings()
	s.use_input_bounds = true
	s.cell_size = Vector3.ONE
	s.fill_y_axis = false
	s.copy_input_attributes = true
	s.source_index_attribute = "src_idx"
	var positions := PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var sizes := PackedVector3Array([Vector3(2.0, 1.0, 2.0)])
	var in_data = _make_bounds_data(positions, sizes)
	var custom_vals := PackedFloat32Array([42.0])
	in_data.registerStream("custom", custom_vals, FlowDataScript.DataType.Float)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var custom_stream = out.findStream("custom")
	assert_object(custom_stream).is_not_null()
	var custom_out = custom_stream.container
	for i in range(custom_out.size()):
		assert_float(custom_out[i]).is_equal_approx(42.0, 0.0001)
	node.free()

# Two input bounds produce cells from both, source indices distinguish them
func test_use_input_bounds_two_bounds_source_indices() -> void:
	var s := _default_settings()
	s.use_input_bounds = true
	s.cell_size = Vector3.ONE
	s.fill_y_axis = false
	s.copy_input_attributes = false
	s.source_index_attribute = "src_idx"
	# First bound at (0,0,0) size (2,1,2) -> 4 cells; second at (10,0,10) size (2,1,2) -> 4 cells
	var positions := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 10.0)])
	var sizes := PackedVector3Array([Vector3(2.0, 1.0, 2.0), Vector3(2.0, 1.0, 2.0)])
	var in_data = _make_bounds_data(positions, sizes)
	var node = _run([in_data], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream(FlowData.AttrPosition)
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(8)
	var idx_stream = out.findStream("src_idx")
	assert_object(idx_stream).is_not_null()
	var indices = idx_stream.container
	# First 4 cells come from bound 0, last 4 from bound 1
	for i in range(4):
		assert_int(indices[i]).is_equal(0)
	for i in range(4, 8):
		assert_int(indices[i]).is_equal(1)
	node.free()

# Density stream defaults to 1.0 for all cells
func test_density_stream_defaults_to_one() -> void:
	var s := _default_settings()
	s.bounds_size = Vector3(2.0, 1.0, 2.0)
	s.cell_size = Vector3.ONE
	s.fill_y_axis = false
	var node = _run([null], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var density_stream = out.findStream(FlowData.AttrDensity)
	assert_object(density_stream).is_not_null()
	var densities = density_stream.container
	for i in range(densities.size()):
		assert_float(densities[i]).is_equal_approx(1.0, 0.0001)
	node.free()
