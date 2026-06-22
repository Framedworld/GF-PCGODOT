@tool
extends FlowNodeBase

# UE PCG parity: Attribute Noise (formerly Density Noise) — combines a random
# value with a numeric attribute per point. Per-point deterministic when the
# input carries a seed stream (PARITY_PLAN convention #3).

func _init():
	meta_node = {
		"title" : "Attribute Noise",
		"settings" : AttributeNoiseNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Attribute Noise", "Density Noise"],
		"category" : "Metadata",
		"tooltip" : "Combines a random value in [noise_min, noise_max] with the target attribute\nper point (Set/Minimum/Maximum/Add/Multiply). Creates the attribute if missing.",
	}

func _read_source_as_float( stream, index : int ) -> Dictionary:
	var size = stream.container.size()
	if size <= 0:
		return { "ok": false, "value": 0.0 }
	var read_idx := FlowData.bcast_idx(size, index)
	match stream.data_type:
		FlowData.DataType.Float:
			return { "ok": true, "value": float(stream.container[read_idx]) }
		FlowData.DataType.Int:
			return { "ok": true, "value": float(stream.container[read_idx]) }
		FlowData.DataType.Bool:
			return { "ok": true, "value": 1.0 if stream.container[read_idx] != 0 else 0.0 }
	return { "ok": false, "value": 0.0 }

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var out_data : FlowData.Data = in_data.duplicate()
	var num_points := in_data.size()
	if num_points == 0:
		set_output(0, out_data)
		return

	var attr : String = settings.target_attribute.strip_edges()
	if attr == "":
		setError("Target attribute can't be empty")
		return

	var is_density := attr == String(FlowData.AttrDensity)
	var stream = out_data.findStream(attr)
	if stream != null and stream.data_type != FlowData.DataType.Float \
			and stream.data_type != FlowData.DataType.Int \
			and stream.data_type != FlowData.DataType.Bool:
		setError("Target attribute '%s' must be numeric (Float/Int/Bool)" % attr)
		return

	var noise_min : float = getSettingValue(ctx, "noise_min", 0.0)
	var noise_max : float = getSettingValue(ctx, "noise_max", 1.0)
	var mode : int = settings.mode
	var invert_source : bool = settings.invert_source
	var clamp_result : bool = settings.clamp_result

	# Per-point seeds (UE parity): prefer the input seed stream, else hash the
	# point position; never the shared node RNG, so noise is stable under
	# reordering/count changes.
	var point_seeds = in_data.getContainerChecked(FlowData.AttrSeed, FlowData.DataType.Int)
	if point_seeds != null and point_seeds.size() == 0:
		point_seeds = null
	var positions = in_data.getVector3Container(FlowData.AttrPosition)
	if positions != null and positions.size() != num_points and positions.size() != 1:
		positions = null
	var node_seed : int = settings.random_seed
	var point_rng := RandomNumberGenerator.new()

	var results := PackedFloat32Array()
	results.resize(num_points)

	for i in range(num_points):
		point_rng.seed = FlowData.resolve_seed(point_seeds, positions, i, node_seed)
		var noise_val : float = point_rng.randf_range(noise_min, noise_max)

		# Missing attribute: density starts at 1.0, anything else at 0.0
		var source_val := 1.0 if is_density else 0.0
		if stream != null:
			var read = _read_source_as_float(stream, i)
			if not read.ok:
				setError("Couldn't read target attribute '%s' for point %d" % [attr, i])
				return
			source_val = read.value
		if invert_source:
			source_val = 1.0 - source_val

		var result : float
		match mode:
			AttributeNoiseNodeSettings.eMode.Minimum:
				result = minf(source_val, noise_val)
			AttributeNoiseNodeSettings.eMode.Maximum:
				result = maxf(source_val, noise_val)
			AttributeNoiseNodeSettings.eMode.Add:
				result = source_val + noise_val
			AttributeNoiseNodeSettings.eMode.Multiply:
				result = source_val * noise_val
			_: # Set
				result = noise_val
		if clamp_result:
			result = clampf(result, 0.0, 1.0)
		results[i] = result

	# Re-register as Float; drop an existing Int/Bool stream first so the type
	# change does not trigger the stream-conflict warning. Sub-component names
	# ("position.Y") write through registerStream's setSubStream path instead.
	if stream != null and stream.data_type != FlowData.DataType.Float and attr.find(".") == -1:
		out_data.delStream(attr)
	var err = out_data.registerStream(attr, results, FlowData.DataType.Float)
	if err:
		setError(str(err))
		return

	set_output(0, out_data)
