# compute_kernel_cleanup_test.gd
# WP14-S: compute_kernel frees its RenderingDevice RIDs dependents first
# (uniform set, buffers, pipeline, shader), checks the uniform set and pipeline
# are still valid before freeing them, and never double-frees. On a real GPU
# the old creation-order cleanup freed the shader (and buffers) first, which
# implicitly freed the uniform set and pipeline; the explicit free_rid() on
# them then logged "Attempted to free invalid ID" twice.
#
# There is no GPU headless, so the device is a double that models
# RenderingDevice's dependency tracking (support/fake_rendering_device.gd).
class_name ComputeKernelCleanupTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ComputeKernelNode = preload("res://addons/flow_nodes_editor/nodes/compute_kernel.gd")
const InjectedKernel = preload("res://tests/review_wp14/support/injected_compute_kernel.gd")
const FakeRD = preload("res://tests/review_wp14/support/fake_rendering_device.gd")

const SHADER := "#version 450\nlayout(local_size_x = 64) in;\nvoid main() {}\n"

func _settings() -> ComputeKernelNodeSettings:
	var s = ComputeKernelNodeSettings.new()
	s.shader_mode = ComputeKernelNodeSettings.eShaderMode.INLINE
	s.shader_source = SHADER
	s.input_bindings = PackedStringArray(["value:0"])
	s.output_bindings = PackedStringArray(["1:result:float"])
	s.bind_point_count = true
	s.point_count_binding = 7
	s.local_size_x = 64
	return s

func _data(values : PackedFloat32Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream("value", values, FlowDataScript.DataType.Float)
	return d

func _run(node, data : FlowData.Data):
	node.name = "ck_cleanup"
	node.inputs = [data]
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty() or node.generated_bulks[0].is_empty():
		return null
	return node.generated_bulks[0][0]

func _events_of(events : Array, tag : String) -> Array:
	var out : Array = []
	for e in events:
		if e[0] == tag:
			out.append(e)
	return out

# Kinds of the explicit (non-cascaded) frees, in order.
func _free_order(events : Array) -> Array:
	var out : Array = []
	for e in events:
		if e[0] == "free":
			out.append(e[1])
	return out

func _assert_clean(events : Array) -> void:
	assert_array(_events_of(events, "invalid_free")).is_empty()
	assert_array(_events_of(events, "cascade_free")).is_empty()
	assert_array(_events_of(events, "leak")).is_empty()
	assert_int(_events_of(events, "device_freed").size()).is_equal(1)
	# Every RID created was freed exactly once.
	assert_int(_events_of(events, "free").size()).is_equal(_events_of(events, "create").size())

func _kernel_with_fake(events : Array, fail_at : String = ""):
	var node = InjectedKernel.new()
	node.settings = _settings()
	var rd = FakeRD.new(events, 1)
	rd.fail_at = fail_at
	node.fake_rd = rd
	return node

# --- The double reproduces the reported bug --------------------------------

# Freeing in creation order (shader, buffers, uniform set, pipeline), as the
# old cleanup did, gives exactly the two invalid frees seen on a real GPU.
func test_double_reproduces_creation_order_double_free() -> void:
	var events : Array = []
	var rd = FakeRD.new(events, 1)
	var rids : Array = []
	var shader : RID = rd.shader_create_from_spirv(RDShaderSPIRV.new())
	rids.append(shader)
	var uniforms : Array = []
	for i in 3:
		var buf : RID = rd.storage_buffer_create(4)
		rids.append(buf)
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buf)
		uniforms.append(u)
	rids.append(rd.uniform_set_create(uniforms, shader, 0))
	rids.append(rd.compute_pipeline_create(shader))
	for rid in rids:
		rd.free_rid(rid)
	rd.free()
	assert_int(_events_of(events, "invalid_free").size()).is_equal(2)
	assert_array(_events_of(events, "leak")).is_empty()

# --- Node cleanup through the double ----------------------------------------

func test_success_frees_dependents_first_without_invalid_frees() -> void:
	var events : Array = []
	var node = _kernel_with_fake(events)
	_run(node, _data(PackedFloat32Array([1.0, 2.0, 3.0])))
	assert_str(node.err).is_empty()
	_assert_clean(events)
	# 1 input + 1 output + 1 point_count buffer.
	assert_array(_free_order(events)).is_equal(
		["uniform_set", "buffer", "buffer", "buffer", "pipeline", "shader"])
	# The dispatch saw live resources and the readback registered the stream.
	assert_array(_events_of(events, "bind_pipeline")).is_equal([["bind_pipeline", true]])
	assert_array(_events_of(events, "bind_uniform_set")).is_equal([["bind_uniform_set", true]])
	var out = _output(node)
	assert_object(out).is_not_null()
	var result = out.findStream("result")
	assert_object(result).is_not_null()
	assert_array(Array(result.container)).is_equal([0.0, 0.0, 0.0])

func test_vec3_and_no_point_count_frees_in_order() -> void:
	var events : Array = []
	var node = _kernel_with_fake(events)
	node.settings.bind_point_count = false
	node.settings.output_bindings = PackedStringArray(["1:a:float", "2:b:vec3"])
	_run(node, _data(PackedFloat32Array([1.0, 2.0])))
	assert_str(node.err).is_empty()
	_assert_clean(events)
	assert_array(_free_order(events)).is_equal(
		["uniform_set", "buffer", "buffer", "buffer", "pipeline", "shader"])

func test_pipeline_failure_cleans_up_and_passes_through() -> void:
	var events : Array = []
	var node = _kernel_with_fake(events, "pipeline")
	_run(node, _data(PackedFloat32Array([4.0, 5.0])))
	assert_str(node.err).contains("compute_pipeline_create")
	_assert_clean(events)
	assert_array(_free_order(events)).is_equal(["uniform_set", "buffer", "buffer", "buffer", "shader"])
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("value")).is_not_null()
	assert_object(out.findStream("result")).is_null()

func test_uniform_set_failure_cleans_up() -> void:
	var events : Array = []
	var node = _kernel_with_fake(events, "uniform_set")
	_run(node, _data(PackedFloat32Array([4.0])))
	assert_str(node.err).contains("uniform_set_create")
	_assert_clean(events)
	assert_array(_free_order(events)).is_equal(["buffer", "buffer", "buffer", "shader"])

func test_output_buffer_failure_cleans_up() -> void:
	var events : Array = []
	var node = _kernel_with_fake(events, "output_buffer")
	_run(node, _data(PackedFloat32Array([4.0])))
	assert_str(node.err).contains("output storage buffer")
	_assert_clean(events)
	assert_array(_free_order(events)).is_equal(["buffer", "shader"])

func test_shader_failure_frees_nothing_but_the_device() -> void:
	var events : Array = []
	var node = _kernel_with_fake(events, "shader")
	_run(node, _data(PackedFloat32Array([4.0])))
	assert_str(node.err).is_not_empty()
	_assert_clean(events)
	assert_array(_free_order(events)).is_empty()

# --- _free_gpu_resources on its own -------------------------------------------

func _full_resources(rd) -> Dictionary:
	var res : Dictionary = ComputeKernelNode._new_gpu_resources()
	res.shader = rd.shader_create_from_spirv(RDShaderSPIRV.new())
	var uniforms : Array = []
	for i in 2:
		var buf : RID = rd.storage_buffer_create(4)
		res.buffers.append(buf)
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i
		u.add_id(buf)
		uniforms.append(u)
	res.uniform_set = rd.uniform_set_create(uniforms, res.shader, 0)
	res.pipeline = rd.compute_pipeline_create(res.shader)
	return res

func test_free_is_idempotent() -> void:
	var events : Array = []
	var rd = FakeRD.new(events, 0)
	var res := _full_resources(rd)
	ComputeKernelNode._free_gpu_resources(rd, res)
	var frees_after_first := _events_of(events, "free").size()
	ComputeKernelNode._free_gpu_resources(rd, res)
	assert_int(_events_of(events, "free").size()).is_equal(frees_after_first)
	assert_int(rd.live_count()).is_equal(0)
	assert_bool(res.uniform_set.is_valid()).is_false()
	assert_bool(res.pipeline.is_valid()).is_false()
	assert_bool(res.shader.is_valid()).is_false()
	assert_array(res.buffers).is_empty()
	rd.free()
	_assert_clean(events)

# A uniform set that the device already dropped (one of its buffers was freed
# elsewhere) is skipped by the validity check instead of double-freed.
func test_free_skips_uniform_set_the_device_already_dropped() -> void:
	var events : Array = []
	var rd = FakeRD.new(events, 0)
	var res := _full_resources(rd)
	var dropped : RID = res.buffers.pop_front()
	rd.free_rid(dropped)	# cascades to the uniform set
	assert_bool(rd.uniform_set_is_valid(res.uniform_set)).is_false()
	ComputeKernelNode._free_gpu_resources(rd, res)
	assert_array(_events_of(events, "invalid_free")).is_empty()
	assert_int(rd.live_count()).is_equal(0)
	rd.free()

func test_free_with_null_device_is_a_no_op() -> void:
	var res : Dictionary = ComputeKernelNode._new_gpu_resources()
	res.shader = rid_from_int64(5)
	ComputeKernelNode._free_gpu_resources(null, res)
	assert_bool(res.shader.is_valid()).is_true()

# --- Headless path unchanged ------------------------------------------------

# Without a GPU the real device is null and the node passes the input through
# with the same message as before; nothing is created or freed.
func test_headless_null_device_falls_back() -> void:
	if RenderingServer.get_rendering_device() != null:
		return	# a real GPU: the null-device path cannot be exercised here
	var node = ComputeKernelNode.new()
	node.settings = _settings()
	_run(node, _data(PackedFloat32Array([1.0, 2.0])))
	assert_str(node.err).contains("create_local_rendering_device() returned null")
	var out = _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("value")).is_not_null()
	assert_object(out.findStream("result")).is_null()
