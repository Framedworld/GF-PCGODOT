# texture_sampler_test.gd
class_name TextureSamplerTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TextureSamplerNode = preload("res://addons/flow_nodes_editor/nodes/texture_sampler.gd")
const TextureSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/texture_sampler_settings.gd")

# Build a deterministic 2x2 texture:
#   (0,0)=red  (1,0)=green
#   (0,1)=blue (1,1)=white
func _make_texture() -> ImageTexture:
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(1, 0, 0, 1))
	img.set_pixel(1, 0, Color(0, 1, 0, 1))
	img.set_pixel(0, 1, Color(0, 0, 1, 1))
	img.set_pixel(1, 1, Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)

func _make_input(uvs: PackedVector3Array) -> FlowData.Data:
	var d = FlowDataScript.Data.new()
	d.registerStream("uv", uvs, FlowDataScript.DataType.Vector)
	return d

func _run(in_data, settings) -> TextureSamplerNode:
	var node = TextureSamplerNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = [in_data]
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

func _settings() -> TextureSamplerSettings:
	var s = TextureSamplerSettings.new()
	s.texture = _make_texture()
	s.uv_attribute_name = "uv"
	s.wrap_mode = TextureSamplerSettings.eWrapMode.Clamp
	s.write_color_attribute = true
	s.out_color_attribute_name = "sampled_color"
	s.write_value_attribute = true
	s.value_channel = TextureSamplerSettings.eValueChannel.R
	s.out_value_attribute_name = "sampled_value"
	return s

func test_samples_known_pixels_by_uv() -> void:
	var s = _settings()
	var node = _run(_make_input(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)
	])), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var colors = out.findStream("sampled_color")
	assert_object(colors).is_not_null()
	assert_array(colors.container).is_equal(PackedColorArray([
		Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1), Color(1, 1, 1, 1)
	]))
	node.free()

func test_value_channel_red() -> void:
	var s = _settings()
	var node = _run(_make_input(PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)
	])), s)
	assert_str(node.err).is_empty()
	var values = _output(node).findStream("sampled_value")
	assert_object(values).is_not_null()
	# R channel of red,green,blue,white = 1,0,0,1
	assert_array(values.container).is_equal(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
	node.free()

func test_unassigned_texture_errors() -> void:
	var s = _settings()
	s.texture = null
	var node = _run(_make_input(PackedVector3Array([Vector3(0, 0, 0)])), s)
	assert_str(node.err).is_equal("Texture is not assigned")
	node.free()

func test_missing_uv_without_fallback_errors() -> void:
	var s = _settings()
	s.use_position_if_uv_missing = false
	var d = FlowDataScript.Data.new()
	d.registerStream("other", PackedVector3Array([Vector3(0, 0, 0)]), FlowDataScript.DataType.Vector)
	var node = _run(d, s)
	assert_str(node.err).is_not_empty()
	node.free()

func test_passthrough_when_no_outputs() -> void:
	var s = _settings()
	s.write_color_attribute = false
	s.write_value_attribute = false
	var node = _run(_make_input(PackedVector3Array([Vector3(0, 0, 0)])), s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	# Passthrough still guarantees a density stream (sampler parity)
	assert_bool(out.hasStream("density")).is_true()
	node.free()
