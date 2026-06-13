@tool
extends FlowNodeBase

const SampleTerrainLayersNodeSettings = preload("res://addons/flow_nodes_editor/nodes/sample_terrain_layers_settings.gd")

func _init():
	meta_node = {
		"title"    : "Sample Terrain Layers",
		"settings" : SampleTerrainLayersNodeSettings,
		"ins"      : [{ "label": "In" }],
		"outs"     : [{ "label": "Out" }],
		"aliases"  : ["Get Landscape Data", "Landscape Layers", "Splat Sampler"],
		"category" : "Sampler",
		"tooltip"  : "Samples N user-assigned mask textures at each point's world-XZ (or UV) position and writes one Float stream per layer (0..1).\nUse density_filter or attribute_filter_range downstream to filter by layer weight.",
	}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Extract a single float from a Color using the configured channel.
func _channel_value(c : Color) -> float:
	match settings.value_channel:
		SampleTerrainLayersNodeSettings.eValueChannel.R:
			return c.r
		SampleTerrainLayersNodeSettings.eValueChannel.G:
			return c.g
		SampleTerrainLayersNodeSettings.eValueChannel.B:
			return c.b
		SampleTerrainLayersNodeSettings.eValueChannel.A:
			return c.a
		_: # Luminance
			return c.get_luminance()

## Apply wrap/clamp to a UV coordinate.
func _apply_wrap(uv : Vector2) -> Vector2:
	if settings.wrap_mode == SampleTerrainLayersNodeSettings.eWrapMode.Clamp:
		return Vector2(clampf(uv.x, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))
	# Wrap: fract
	return Vector2(uv.x - floor(uv.x), uv.y - floor(uv.y))

## Compute the [0,1] UV for a single point given the mapping mode.
##
## Returns { "ok": bool, "uv": Vector2 }.
func _resolve_uv(pos_stream, uv_stream, i : int) -> Dictionary:
	if settings.use_world_xz:
		# World XZ → UV via configured bounds
		if pos_stream == null:
			return { "ok": false, "uv": Vector2.ZERO }
		var pos_size : int = pos_stream.container.size()
		if pos_size == 0:
			return { "ok": false, "uv": Vector2.ZERO }
		var read_idx : int = FlowData.bcast_idx(pos_size, i)
		var p : Vector3 = pos_stream.container[read_idx]
		var wmin : Vector2 = settings.world_min
		var wmax : Vector2 = settings.world_max
		var range_x : float = wmax.x - wmin.x
		var range_z : float = wmax.y - wmin.y
		if abs(range_x) < 1e-6 or abs(range_z) < 1e-6:
			return { "ok": false, "uv": Vector2.ZERO }
		var uv := Vector2(
			(p.x - wmin.x) / range_x,
			(p.z - wmin.y) / range_z
		)
		return { "ok": true, "uv": uv }
	else:
		# Explicit UV attribute
		if uv_stream == null:
			return { "ok": false, "uv": Vector2.ZERO }
		var uv_size : int = uv_stream.container.size()
		if uv_size == 0:
			return { "ok": false, "uv": Vector2.ZERO }
		var read_idx : int = FlowData.bcast_idx(uv_size, i)
		match uv_stream.data_type:
			FlowData.DataType.Vector:
				var v : Vector3 = uv_stream.container[read_idx]
				return { "ok": true, "uv": Vector2(v.x, v.y) }
			FlowData.DataType.Color:
				var c : Color = uv_stream.container[read_idx]
				return { "ok": true, "uv": Vector2(c.r, c.g) }
			_:
				return { "ok": false, "uv": Vector2.ZERO }

## Load and decompress an Image from a Texture2D.
## Returns null and calls setError on failure.
func _load_image(texture : Texture2D, layer_name : String):
	if texture == null:
		setError("Layer '%s': texture is not assigned" % layer_name)
		return null
	var image : Image = texture.get_image()
	if image == null:
		setError("Layer '%s': failed to read texture image data (texture may not be imported yet)" % layer_name)
		return null
	if image.is_compressed():
		if image.decompress() != OK:
			setError("Layer '%s': texture is compressed and could not be decompressed" % layer_name)
			return null
	if image.get_width() <= 0 or image.get_height() <= 0:
		setError("Layer '%s': texture has invalid size" % layer_name)
		return null
	return image

## Sample an already-loaded Image at a normalised [0,1] UV.
func _sample_image(image : Image, uv : Vector2) -> float:
	var w : int = image.get_width()
	var h : int = image.get_height()
	var px : int = clampi(int(floor(uv.x * float(w - 1))), 0, w - 1)
	var py : int = clampi(int(floor(uv.y * float(h - 1))), 0, h - 1)
	return _channel_value(image.get_pixel(px, py))

# ---------------------------------------------------------------------------
# execute
# ---------------------------------------------------------------------------

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, _ctx, "Input 'In'")
	if in_data == null:
		return

	# --- Validate layer list ---
	var layer_list : Array = settings.layers
	if layer_list.is_empty():
		setError("No layers defined — add at least one layer entry in Settings")
		return

	# Validate each entry and collect names
	var seen_names : Dictionary = {}
	for i in range(layer_list.size()):
		var entry = layer_list[i]
		if entry == null:
			setError("Layer entry %d is null — remove or fill it" % i)
			return
		var lname : String = entry.layer_name
		if lname == "":
			setError("Layer entry %d has an empty name" % i)
			return
		if seen_names.has(lname):
			setError("Duplicate layer name '%s'" % lname)
			return
		seen_names[lname] = true

	var num_points : int = in_data.size()

	# Passthrough empty data
	if num_points == 0:
		set_output(0, in_data.duplicate())
		return

	# --- Resolve position / UV streams ---
	var pos_stream = null
	var uv_stream = null

	if settings.use_world_xz:
		pos_stream = in_data.findStream(FlowData.AttrPosition)
		if pos_stream == null:
			setError("Input has no 'position' stream required for world-XZ mapping")
			return
		if pos_stream.data_type != FlowData.DataType.Vector:
			setError("'position' stream must be of type Vector")
			return
	else:
		var uv_attr : String = settings.uv_attribute_name
		if uv_attr == "":
			setError("UV attribute name is empty — enter a name or enable World XZ mapping")
			return
		uv_stream = in_data.findStream(uv_attr)
		if uv_stream == null:
			setError("UV attribute '%s' not found on input data" % uv_attr)
			return
		if uv_stream.data_type != FlowData.DataType.Vector and uv_stream.data_type != FlowData.DataType.Color:
			setError("UV attribute '%s' must be of type Vector or Color" % uv_attr)
			return
		var uv_size : int = uv_stream.container.size()
		if uv_size != num_points and uv_size != 1:
			setError("UV attribute '%s' has %d values but expected %d or 1 (broadcast)" % [uv_attr, uv_size, num_points])
			return

	# --- Validate world bounds ---
	if settings.use_world_xz:
		var wmin : Vector2 = settings.world_min
		var wmax : Vector2 = settings.world_max
		if abs(wmax.x - wmin.x) < 1e-6 or abs(wmax.y - wmin.y) < 1e-6:
			setError("World bounds are degenerate — world_min and world_max must differ in both X and Z")
			return

	# --- Pre-load all images (fail fast before the per-point loop) ---
	var images : Array = []
	for entry in layer_list:
		var img = _load_image(entry.texture, entry.layer_name)
		if img == null:
			return   # setError was already called inside _load_image
		images.append(img)

	# --- Per-point sampling ---
	# Sample each layer independently to avoid GDScript PackedArray COW pitfalls.
	# We iterate per-layer (outer) per-point (inner) so the UV is resolved twice
	# only when there are 2+ layers; for the common 1-4 layer case this is fine.
	# The UV resolve is cheap (arithmetic); the image sample is the hot path.
	var prefix : String = settings.stream_prefix
	var num_layers : int = layer_list.size()

	# Build an output Data copy and register one stream per layer.
	# We fill a temporary PackedFloat32Array per layer and register it.
	var out_data : FlowData.Data = in_data.duplicate()

	for layer_idx in range(num_layers):
		var entry = layer_list[layer_idx]
		var img : Image = images[layer_idx]
		var values := PackedFloat32Array()
		values.resize(num_points)

		for pt_idx in range(num_points):
			var uv_res : Dictionary = _resolve_uv(pos_stream, uv_stream, pt_idx)
			if not uv_res.ok:
				if settings.use_world_xz:
					setError("Could not resolve world XZ UV for point %d (layer '%s')" % [pt_idx, entry.layer_name])
				else:
					setError("Could not resolve UV from attribute for point %d — attribute must be Vector or Color" % pt_idx)
				return
			values[pt_idx] = _sample_image(img, _apply_wrap(uv_res.uv))

		var stream_name : String = prefix + entry.layer_name
		var err = out_data.registerStream(stream_name, values, FlowData.DataType.Float)
		if err:
			setError("Failed to register stream '%s': %s" % [stream_name, err])
			return

	set_output(0, out_data)
