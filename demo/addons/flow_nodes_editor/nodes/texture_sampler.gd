@tool
extends FlowNodeBase

const TextureSamplerNodeSettings = preload("res://addons/flow_nodes_editor/nodes/texture_sampler_settings.gd")

func _init():
	meta_node = {
		"title" : "Texture Sampler",
		"settings" : TextureSamplerNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Get Texture Data", "Texture Sampler"],
		"category" : "Sampler",
		"tooltip" : "Samples a texture using UV or position-derived coordinates and writes sampled attributes.",
	}

# Sampler parity: points leaving a sampler always carry density + seed streams.
# This node passes points through, so upstream values are kept when present.
func _ensure_density_seed(out_data : FlowData.Data):
	var num_points := out_data.size()
	if num_points == 0:
		return
	if not out_data.hasStream(FlowData.AttrDensity):
		var sdensity := PackedFloat32Array()
		sdensity.resize(num_points)
		sdensity.fill(1.0)
		out_data.registerStream(FlowData.AttrDensity, sdensity, FlowData.DataType.Float)
	if not out_data.hasStream(FlowData.AttrSeed):
		var spos := out_data.getVector3Container(FlowData.AttrPosition)
		if spos.size() == num_points:
			var node_seed : int = effective_seed()
			var sseed := PackedInt32Array()
			sseed.resize(num_points)
			for i in range(num_points):
				sseed[i] = FlowData.point_seed(spos[i], node_seed)
			out_data.registerStream(FlowData.AttrSeed, sseed, FlowData.DataType.Int)

func _get_numeric_from_stream(stream, index : int) -> Dictionary:
	var size = stream.container.size()
	if size <= 0:
		return { "ok": false, "value": 0.0 }
	var read_idx = index if size > 1 else 0
	match stream.data_type:
		FlowData.DataType.Float:
			return { "ok": true, "value": float(stream.container[read_idx]) }
		FlowData.DataType.Int:
			return { "ok": true, "value": float(stream.container[read_idx]) }
		FlowData.DataType.Bool:
			return { "ok": true, "value": 1.0 if stream.container[read_idx] != 0 else 0.0 }
	return { "ok": false, "value": 0.0 }

func _read_uv_from_stream(stream, index : int) -> Dictionary:
	var size = stream.container.size()
	if size <= 0:
		return { "ok": false, "uv": Vector2.ZERO }
	var read_idx = index if size > 1 else 0
	match stream.data_type:
		FlowData.DataType.Vector:
			var v : Vector3 = stream.container[read_idx]
			return { "ok": true, "uv": Vector2(v.x, v.y) }
		FlowData.DataType.Color:
			var c : Color = stream.container[read_idx]
			return { "ok": true, "uv": Vector2(c.r, c.g) }
	return { "ok": false, "uv": Vector2.ZERO }

func _resolve_uv(in_data : FlowData.Data, index : int, uv_stream, pos_stream) -> Dictionary:
	if uv_stream != null:
		var uv_read = _read_uv_from_stream(uv_stream, index)
		if uv_read.ok:
			return { "ok": true, "uv": uv_read.uv }

	if not settings.use_position_if_uv_missing or pos_stream == null:
		return { "ok": false, "uv": Vector2.ZERO }

	var size = pos_stream.container.size()
	if size <= 0:
		return { "ok": false, "uv": Vector2.ZERO }
	var read_idx = index if size > 1 else 0
	var p : Vector3 = pos_stream.container[read_idx]
	var base = Vector2(p.x, p.z) if settings.use_xz_for_position else Vector2(p.x, p.y)
	return { "ok": true, "uv": base * settings.uv_scale + settings.uv_offset }

func _apply_wrap(uv : Vector2) -> Vector2:
	if settings.wrap_mode == TextureSamplerNodeSettings.eWrapMode.Clamp:
		return Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))
	return Vector2(uv.x - floor(uv.x), uv.y - floor(uv.y))

func _sample_value_channel(color : Color) -> float:
	match settings.value_channel:
		TextureSamplerNodeSettings.eValueChannel.R:
			return color.r
		TextureSamplerNodeSettings.eValueChannel.G:
			return color.g
		TextureSamplerNodeSettings.eValueChannel.B:
			return color.b
		TextureSamplerNodeSettings.eValueChannel.A:
			return color.a
		_:
			return color.get_luminance()

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, _ctx, "Input 'In'")
	if in_data == null:
		return

	var should_write_color = settings.write_color_attribute
	var should_write_value = settings.write_value_attribute
	if not should_write_color and not should_write_value:
		var passthrough = in_data.duplicate()
		_ensure_density_seed(passthrough)
		set_output(0, passthrough)
		return

	if settings.texture == null:
		setError("Texture is not assigned")
		return

	var image = settings.texture.get_image()
	if image == null:
		setError("Failed to read texture image data")
		return
	if image.is_compressed():
		# Imported textures often arrive VRAM-compressed; get_pixel needs raw data.
		# Duplicate first so decompress() never mutates the shared texture asset.
		image = image.duplicate()
		if image.decompress() != OK:
			setError("Texture image is compressed and could not be decompressed")
			return
	var width = image.get_width()
	var height = image.get_height()
	if width <= 0 or height <= 0:
		setError("Texture image has invalid size")
		return

	var num_points = in_data.size()
	if num_points == 0:
		set_output(0, in_data.duplicate())
		return

	var uv_stream = null
	var uv_name = settings.uv_attribute_name.strip_edges()
	if uv_name != "":
		uv_stream = in_data.findStream(uv_name)
		if uv_stream != null and uv_stream.data_type != FlowData.DataType.Vector and uv_stream.data_type != FlowData.DataType.Color:
			setError("UV attribute '%s' must be Vector or Color" % uv_name)
			return
		if uv_stream != null:
			var uv_size = uv_stream.container.size()
			if uv_size != num_points and uv_size != 1:
				setError("UV attribute '%s' must have %d values or 1 value (got %d)" % [uv_name, num_points, uv_size])
				return

	var pos_stream = null
	if settings.use_position_if_uv_missing:
		var pos_name = settings.position_attribute_name.strip_edges()
		if pos_name != "":
			pos_stream = in_data.findStream(pos_name)
		if pos_stream != null:
			if pos_stream.data_type != FlowData.DataType.Vector:
				setError("Position fallback attribute '%s' must be Vector" % pos_name)
				return
			var pos_size = pos_stream.container.size()
			if pos_size != num_points and pos_size != 1:
				setError("Position fallback attribute '%s' must have %d values or 1 value (got %d)" % [pos_name, num_points, pos_size])
				return

	var out_colors := PackedColorArray()
	var out_values := PackedFloat32Array()
	if should_write_color:
		out_colors.resize(num_points)
	if should_write_value:
		out_values.resize(num_points)

	for i in range(num_points):
		var uv_res = _resolve_uv(in_data, i, uv_stream, pos_stream)
		if not uv_res.ok:
			setError("Couldn't resolve UV for point %d. Provide UV attribute or enable position fallback." % i)
			return
		var uv = _apply_wrap(uv_res.uv)

		var px = int(floor(uv.x * float(width - 1)))
		var py = int(floor(uv.y * float(height - 1)))
		px = clampi(px, 0, width - 1)
		py = clampi(py, 0, height - 1)
		var c = image.get_pixel(px, py)

		if should_write_color:
			out_colors[i] = c
		if should_write_value:
			out_values[i] = _sample_value_channel(c)

	var out_data = in_data.duplicate()
	if should_write_color:
		var out_color_name = settings.out_color_attribute_name.strip_edges()
		if out_color_name == "":
			setError("Output color attribute name can't be empty")
			return
		var err = out_data.registerStream(out_color_name, out_colors, FlowData.DataType.Color)
		if err:
			setError(err)
			return

	if should_write_value:
		var out_value_name = settings.out_value_attribute_name.strip_edges()
		if out_value_name == "":
			setError("Output value attribute name can't be empty")
			return
		var err = out_data.registerStream(out_value_name, out_values, FlowData.DataType.Float)
		if err:
			setError(err)
			return

	_ensure_density_seed(out_data)
	set_output(0, out_data)
