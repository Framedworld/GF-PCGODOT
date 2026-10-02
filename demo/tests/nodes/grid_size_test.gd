# grid_size_test.gd
class_name GridSizeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const GridSizeNode = preload("res://addons/flow_nodes_editor/nodes/grid_size.gd")
const GridSizeSettings = preload("res://addons/flow_nodes_editor/nodes/grid_size_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, settings) -> Dictionary:
	var node = GridSizeNode.new()
	node.name = "test_grid_size"
	node.settings = settings
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return { "node": node, "ctx": ctx }

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_passthrough_no_input_produces_empty_data() -> void:
	var s = GridSizeSettings.new()
	var result = _run([null], s)
	var node = result["node"]
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_int(out.size()).is_equal(0)

func test_passthrough_float_stream_unchanged() -> void:
	var s = GridSizeSettings.new()
	var in_data = _make_data("pts", PackedFloat32Array([1.0, 2.0, 3.0]), FlowDataScript.DataType.Float)
	var result = _run([in_data], s)
	var node = result["node"]
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("pts")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedFloat32Array([1.0, 2.0, 3.0]))

func test_passthrough_vector_stream_unchanged() -> void:
	var s = GridSizeSettings.new()
	var in_data = _make_data("pos", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var result = _run([in_data], s)
	var node = result["node"]
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("pos")
	assert_object(stream).is_not_null()
	assert_array(stream.container).is_equal(PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]))

func test_default_cell_size_written_to_ctx() -> void:
	var s = GridSizeSettings.new()
	var result = _run([null], s)
	var node = result["node"]
	var ctx = result["ctx"]
	assert_str(node.err).is_empty()
	assert_bool(ctx.variables.has(GridSizeNodeSettings.CTX_KEY)).is_true()
	assert_float(ctx.variables[GridSizeNodeSettings.CTX_KEY]).is_equal(64.0)

func test_custom_cell_size_written_to_ctx() -> void:
	var s = GridSizeSettings.new()
	s.cell_size = 128.0
	var result = _run([null], s)
	var node = result["node"]
	var ctx = result["ctx"]
	assert_str(node.err).is_empty()
	assert_float(ctx.variables[GridSizeNodeSettings.CTX_KEY]).is_equal(128.0)

func test_cell_size_snaps_to_nearest_power_of_two() -> void:
	var s = GridSizeSettings.new()
	s.cell_size = 100.0
	assert_float(s.cell_size).is_equal(128.0)

	s.cell_size = 50.0
	assert_float(s.cell_size).is_equal(64.0)

	s.cell_size = 1.0
	assert_float(s.cell_size).is_equal(1.0)

	s.cell_size = 0.5
	assert_float(s.cell_size).is_equal(1.0)

	s.cell_size = 33.0
	assert_float(s.cell_size).is_equal(32.0)

func test_cell_size_snap_written_to_ctx() -> void:
	var s = GridSizeSettings.new()
	s.cell_size = 200.0
	var result = _run([null], s)
	var node = result["node"]
	var ctx = result["ctx"]
	assert_str(node.err).is_empty()
	assert_float(ctx.variables[GridSizeNodeSettings.CTX_KEY]).is_equal(256.0)

func test_no_settings_defaults_cell_size_to_one() -> void:
	var result = _run([null], null)
	var node = result["node"]
	var ctx = result["ctx"]
	assert_str(node.err).is_empty()
	assert_float(ctx.variables[GridSizeNodeSettings.CTX_KEY]).is_equal(1.0)

func test_passthrough_preserves_multiple_streams() -> void:
	var s = GridSizeSettings.new()
	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("pos", PackedVector3Array([Vector3(0, 0, 0)]), FlowDataScript.DataType.Vector)
	in_data.registerStream("density", PackedFloat32Array([0.5]), FlowDataScript.DataType.Float)
	in_data.registerStream("idx", PackedInt32Array([7]), FlowDataScript.DataType.Int)
	var result = _run([in_data], s)
	var node = result["node"]
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("pos")).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("idx")).is_not_null()
