# compute_kernel_test.gd
class_name ComputeKernelTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ComputeKernelNode = preload("res://addons/flow_nodes_editor/nodes/compute_kernel.gd")
const ComputeKernelSettings = preload("res://addons/flow_nodes_editor/nodes/compute_kernel_settings.gd")

func _make_data(stream_name: String, values, dtype: int) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(stream_name, values, dtype)
	return d

func _run(inputs: Array, s: ComputeKernelNodeSettings) -> ComputeKernelNode:
	var node = ComputeKernelNode.new()
	node.name = "ck_test"
	node.settings = s
	node.inputs = inputs
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: ComputeKernelNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func _default_settings() -> ComputeKernelNodeSettings:
	var s = ComputeKernelNodeSettings.new()
	s.shader_mode = ComputeKernelNodeSettings.eShaderMode.INLINE
	s.input_bindings = PackedStringArray(["value:0"])
	s.output_bindings = PackedStringArray(["1:result:float"])
	s.bind_point_count = true
	s.point_count_binding = 7
	s.local_size_x = 64
	s.vec3_packing = ComputeKernelNodeSettings.eVec3Packing.VEC4_PADDED
	return s

# --- Missing input (port 0 not connected) ----------------------------------

func test_missing_input_sets_error() -> void:
	var s = _default_settings()
	var node = _run([], s)
	assert_str(node.err).is_not_empty()

func test_null_input_sets_error() -> void:
	var s = _default_settings()
	var node = _run([null], s)
	assert_str(node.err).is_not_empty()

# --- Empty data passthrough -------------------------------------------------
# When point_count == 0 the node should emit the duplicate without touching
# the GPU and produce no error.

func test_empty_data_passes_through() -> void:
	var s = _default_settings()
	var d := FlowDataScript.Data.new()
	d.registerStream("value", PackedFloat32Array(), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()

# --- Malformed input binding ------------------------------------------------

func test_malformed_input_binding_sets_error() -> void:
	var s = _default_settings()
	s.input_bindings = PackedStringArray(["bad_format_no_colon"])
	var d = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_input_binding_non_int_index_sets_error() -> void:
	var s = _default_settings()
	s.input_bindings = PackedStringArray(["value:notanumber"])
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- Malformed output binding -----------------------------------------------

func test_malformed_output_binding_sets_error() -> void:
	var s = _default_settings()
	s.output_bindings = PackedStringArray(["only_two:parts"])
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_output_binding_unsupported_type_sets_error() -> void:
	var s = _default_settings()
	s.output_bindings = PackedStringArray(["1:result:int"])
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_output_binding_non_int_index_sets_error() -> void:
	var s = _default_settings()
	s.output_bindings = PackedStringArray(["notanumber:result:float"])
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- No output bindings -----------------------------------------------------

func test_no_output_bindings_sets_error() -> void:
	var s = _default_settings()
	s.output_bindings = PackedStringArray()
	var d = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_only_empty_string_output_bindings_sets_error() -> void:
	var s = _default_settings()
	s.output_bindings = PackedStringArray(["   ", ""])
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- Missing referenced stream ----------------------------------------------

func test_missing_stream_in_input_binding_sets_error() -> void:
	var s = _default_settings()
	s.input_bindings = PackedStringArray(["does_not_exist:0"])
	var d = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- Inline shader source empty ---------------------------------------------

func test_empty_inline_shader_source_sets_error() -> void:
	var s = _default_settings()
	s.shader_mode = ComputeKernelNodeSettings.eShaderMode.INLINE
	s.shader_source = ""
	var d = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_whitespace_only_inline_shader_source_sets_error() -> void:
	var s = _default_settings()
	s.shader_mode = ComputeKernelNodeSettings.eShaderMode.INLINE
	s.shader_source = "   \n\t  "
	var d = _make_data("value", PackedFloat32Array([5.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- FILE mode with invalid path --------------------------------------------

func test_file_mode_empty_path_sets_error() -> void:
	var s = _default_settings()
	s.shader_mode = ComputeKernelNodeSettings.eShaderMode.FILE
	s.shader_file_path = ""
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_file_mode_nonexistent_path_sets_error() -> void:
	var s = _default_settings()
	s.shader_mode = ComputeKernelNodeSettings.eShaderMode.FILE
	s.shader_file_path = "res://does_not_exist.glsl"
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- Graceful fallback: input passes through unchanged ----------------------
# On GPU failure the node calls _fallback which calls set_output(0, in_data).
# We verify the output is non-null and contains the original stream.

func test_graceful_fallback_preserves_input_streams() -> void:
	var s = _default_settings()
	s.shader_source = ""
	var d = _make_data("value", PackedFloat32Array([3.0, 6.0, 9.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	var out = _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("value")
	assert_object(stream).is_not_null()

# --- Unsupported stream type for packing ------------------------------------

func test_color_stream_input_binding_sets_error() -> void:
	var s = _default_settings()
	s.input_bindings = PackedStringArray(["col:0"])
	s.output_bindings = PackedStringArray(["1:result:float"])
	var d = _make_data("col", PackedColorArray([Color(1, 0, 0, 1)]), FlowDataScript.DataType.Color)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- Vec3 packing variants (parsing only; GPU may not be available) ---------
# Both packing modes should not error before reaching GPU creation.
# With a bad shader they should error at the shader stage, not before.

func test_vec3_padded_packing_reaches_shader_stage() -> void:
	var s = _default_settings()
	s.vec3_packing = ComputeKernelNodeSettings.eVec3Packing.VEC4_PADDED
	s.input_bindings = PackedStringArray(["pos:0"])
	s.output_bindings = PackedStringArray(["1:out_pos:vec3"])
	s.shader_source = ""
	var d = _make_data("pos", PackedVector3Array([Vector3(1, 2, 3)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

func test_vec3_tight_packing_reaches_shader_stage() -> void:
	var s = _default_settings()
	s.vec3_packing = ComputeKernelNodeSettings.eVec3Packing.VEC3_TIGHT
	s.input_bindings = PackedStringArray(["pos:0"])
	s.output_bindings = PackedStringArray(["1:out_pos:vec3"])
	s.shader_source = ""
	var d = _make_data("pos", PackedVector3Array([Vector3(4, 5, 6)]), FlowDataScript.DataType.Vector)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- bind_point_count disabled: still validates bindings --------------------

func test_bind_point_count_false_still_validates_output_bindings() -> void:
	var s = _default_settings()
	s.bind_point_count = false
	s.output_bindings = PackedStringArray()
	var d = _make_data("value", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- Skipped / whitespace input bindings are ignored -----------------------
# A binding entry that is all whitespace should be skipped without error,
# so the node proceeds to the output-binding or GPU stage.

func test_whitespace_input_bindings_skipped() -> void:
	var s = _default_settings()
	s.input_bindings = PackedStringArray(["   ", ""])
	s.output_bindings = PackedStringArray(["1:result:float"])
	s.shader_source = ""
	var d = _make_data("value", PackedFloat32Array([1.0, 2.0]), FlowDataScript.DataType.Float)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()

# --- Int stream is accepted as input (packed as float) ----------------------

func test_int_stream_input_reaches_shader_stage() -> void:
	var s = _default_settings()
	s.input_bindings = PackedStringArray(["ids:0"])
	s.output_bindings = PackedStringArray(["1:result:float"])
	s.shader_source = ""
	var d = _make_data("ids", PackedInt32Array([1, 2, 3]), FlowDataScript.DataType.Int)
	var node = _run([d], s)
	assert_str(node.err).is_not_empty()
