# sample_terrain_layers_test.gd
class_name SampleTerrainLayersTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SampleTerrainLayersNode = preload("res://addons/flow_nodes_editor/nodes/sample_terrain_layers.gd")
const SampleTerrainLayersSettings = preload("res://addons/flow_nodes_editor/nodes/sample_terrain_layers_settings.gd")

func _make_solid_texture(color: Color, width: int = 4, height: int = 4) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _make_layer_entry(name: String, texture: Texture2D) -> TerrainLayerEntry:
	var entry := TerrainLayerEntry.new()
	entry.layer_name = name
	entry.texture = texture
	return entry

func _make_world_xz_settings(layers: Array) -> SampleTerrainLayersNodeSettings:
	var s := SampleTerrainLayersSettings.new()
	s.use_world_xz = true
	s.world_min = Vector2(-100.0, -100.0)
	s.world_max = Vector2(100.0, 100.0)
	s.stream_prefix = "layer_"
	s.value_channel = SampleTerrainLayersNodeSettings.eValueChannel.R
	s.wrap_mode = SampleTerrainLayersNodeSettings.eWrapMode.Clamp
	s.layers.clear()
	for entry in layers:
		s.layers.append(entry)
	return s

func _make_uv_settings(layers: Array, uv_attr: String = "uv") -> SampleTerrainLayersNodeSettings:
	var s := SampleTerrainLayersSettings.new()
	s.use_world_xz = false
	s.uv_attribute_name = uv_attr
	s.stream_prefix = "layer_"
	s.value_channel = SampleTerrainLayersNodeSettings.eValueChannel.R
	s.wrap_mode = SampleTerrainLayersNodeSettings.eWrapMode.Clamp
	s.layers.clear()
	for entry in layers:
		s.layers.append(entry)
	return s

func _make_position_data(positions: PackedVector3Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowDataScript.DataType.Vector)
	return d

func _run(input: FlowData.Data, s: SampleTerrainLayersNodeSettings) -> SampleTerrainLayersNode:
	var node := SampleTerrainLayersNode.new()
	node.name = "test_sample_terrain_layers"
	node.settings = s
	node.inputs = [input]
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: SampleTerrainLayersNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_world_xz_single_layer_solid_red_texture() -> void:
	var tex := _make_solid_texture(Color(0.75, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_world_xz_settings([entry])

	var positions := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0),
		Vector3(50.0, 0.0, 50.0),
		Vector3(-50.0, 0.0, -50.0),
	])
	var in_data := _make_position_data(positions)
	var node := _run(in_data, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("layer_grass")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(3)
	assert_float(stream.container[0]).is_equal_approx(0.75, 0.02)
	assert_float(stream.container[1]).is_equal_approx(0.75, 0.02)
	assert_float(stream.container[2]).is_equal_approx(0.75, 0.02)
	node.free()

func test_world_xz_multiple_layers_independent_streams() -> void:
	var tex_grass := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var tex_rock := _make_solid_texture(Color(0.5, 0.0, 0.0, 1.0))
	var entry_grass := _make_layer_entry("grass", tex_grass)
	var entry_rock := _make_layer_entry("rock", tex_rock)
	var s := _make_world_xz_settings([entry_grass, entry_rock])

	var positions := PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(25.0, 0.0, 25.0)])
	var in_data := _make_position_data(positions)
	var node := _run(in_data, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream_grass = out.findStream("layer_grass")
	var stream_rock = out.findStream("layer_rock")
	assert_object(stream_grass).is_not_null()
	assert_object(stream_rock).is_not_null()
	assert_int(stream_grass.container.size()).is_equal(2)
	assert_int(stream_rock.container.size()).is_equal(2)
	assert_float(stream_grass.container[0]).is_equal_approx(1.0, 0.02)
	assert_float(stream_rock.container[0]).is_equal_approx(0.5, 0.02)
	node.free()

func test_uv_attribute_vector_stream() -> void:
	var tex := _make_solid_texture(Color(0.6, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("sand", tex)
	var s := _make_uv_settings([entry], "uv")

	var d := FlowDataScript.Data.new()
	d.registerStream("uv", PackedVector3Array([Vector3(0.5, 0.5, 0.0), Vector3(0.0, 0.0, 0.0)]), FlowDataScript.DataType.Vector)
	var node := _run(d, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("layer_sand")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(2)
	assert_float(stream.container[0]).is_equal_approx(0.6, 0.02)
	assert_float(stream.container[1]).is_equal_approx(0.6, 0.02)
	node.free()

func test_uv_attribute_color_stream() -> void:
	var tex := _make_solid_texture(Color(0.4, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("snow", tex)
	var s := _make_uv_settings([entry], "uv_color")

	var d := FlowDataScript.Data.new()
	d.registerStream("uv_color", PackedColorArray([Color(0.5, 0.5, 0.0, 1.0)]), FlowDataScript.DataType.Color)
	var node := _run(d, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("layer_snow")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(stream.container[0]).is_equal_approx(0.4, 0.02)
	node.free()

func test_value_channel_green() -> void:
	var tex := _make_solid_texture(Color(0.0, 0.8, 0.0, 1.0))
	var entry := _make_layer_entry("moss", tex)
	var s := _make_world_xz_settings([entry])
	s.value_channel = SampleTerrainLayersNodeSettings.eValueChannel.G

	var in_data := _make_position_data(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	var node := _run(in_data, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	var stream = out.findStream("layer_moss")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal_approx(0.8, 0.02)
	node.free()

func test_custom_stream_prefix() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("dirt", tex)
	var s := _make_world_xz_settings([entry])
	s.stream_prefix = "terrain_"

	var in_data := _make_position_data(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	var node := _run(in_data, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream("terrain_dirt")).is_not_null()
	assert_object(out.findStream("layer_dirt")).is_null()
	node.free()

func test_empty_input_data_passthrough() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_world_xz_settings([entry])

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array([]), FlowDataScript.DataType.Vector)
	var node := _run(in_data, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_error_missing_input() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_world_xz_settings([entry])

	var node := SampleTerrainLayersNode.new()
	node.name = "test_missing_input"
	node.settings = s
	node.inputs = []
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_no_layers_defined() -> void:
	var s := _make_world_xz_settings([])

	var in_data := _make_position_data(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_empty_layer_name() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("", tex)
	var s := _make_world_xz_settings([entry])

	var in_data := _make_position_data(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_duplicate_layer_name() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry_a := _make_layer_entry("grass", tex)
	var entry_b := _make_layer_entry("grass", tex)
	var s := _make_world_xz_settings([entry_a, entry_b])

	var in_data := _make_position_data(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_missing_position_stream_for_world_xz() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_world_xz_settings([entry])

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("density", PackedFloat32Array([1.0, 1.0]), FlowDataScript.DataType.Float)
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_degenerate_world_bounds() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_world_xz_settings([entry])
	s.world_min = Vector2(0.0, 0.0)
	s.world_max = Vector2(0.0, 100.0)

	var in_data := _make_position_data(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_missing_uv_attribute() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_uv_settings([entry], "uv")

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("density", PackedFloat32Array([1.0]), FlowDataScript.DataType.Float)
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_uv_attribute_wrong_type() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_uv_settings([entry], "uv")

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream("uv", PackedFloat32Array([0.5, 0.5]), FlowDataScript.DataType.Float)
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_error_null_texture() -> void:
	var entry := _make_layer_entry("grass", null)
	var s := _make_world_xz_settings([entry])

	var in_data := _make_position_data(PackedVector3Array([Vector3(0.0, 0.0, 0.0)]))
	var node := _run(in_data, s)

	assert_str(node.err).is_not_empty()
	node.free()

func test_output_preserves_existing_streams() -> void:
	var tex := _make_solid_texture(Color(1.0, 0.0, 0.0, 1.0))
	var entry := _make_layer_entry("grass", tex)
	var s := _make_world_xz_settings([entry])

	var in_data := FlowDataScript.Data.new()
	in_data.registerStream(FlowData.AttrPosition, PackedVector3Array([Vector3(0.0, 0.0, 0.0), Vector3(10.0, 0.0, 10.0)]), FlowDataScript.DataType.Vector)
	in_data.registerStream("density", PackedFloat32Array([0.5, 0.8]), FlowDataScript.DataType.Float)
	var node := _run(in_data, s)

	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_object(out.findStream(FlowData.AttrPosition)).is_not_null()
	assert_object(out.findStream("density")).is_not_null()
	assert_object(out.findStream("layer_grass")).is_not_null()
	node.free()
