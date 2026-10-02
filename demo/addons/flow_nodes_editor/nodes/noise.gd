@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Noise",
		"settings" : NoiseNodeSettings,
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Spatial Noise"],
		"category" : "Density",
		"tooltip" : "Outputs an attribute with Noise values",
	}

func _map_noise_type() -> int:
	match settings.noise_type:
		NoiseNodeSettings.eNoiseType.ValueCubic:
			return FastNoiseLite.NoiseType.TYPE_VALUE_CUBIC
		NoiseNodeSettings.eNoiseType.Perlin:
			return FastNoiseLite.NoiseType.TYPE_PERLIN
		NoiseNodeSettings.eNoiseType.Cellular:
			return FastNoiseLite.NoiseType.TYPE_CELLULAR
		NoiseNodeSettings.eNoiseType.Simplex:
			return FastNoiseLite.NoiseType.TYPE_SIMPLEX
		NoiseNodeSettings.eNoiseType.SimplexSmooth:
			return FastNoiseLite.NoiseType.TYPE_SIMPLEX_SMOOTH
		_:
			return FastNoiseLite.NoiseType.TYPE_VALUE

func _map_fractal_type() -> int:
	match settings.fractal_type:
		NoiseNodeSettings.eFractalType.FBM:
			return FastNoiseLite.FractalType.FRACTAL_FBM
		NoiseNodeSettings.eFractalType.Ridged:
			return FastNoiseLite.FractalType.FRACTAL_RIDGED
		NoiseNodeSettings.eFractalType.PingPong:
			return FastNoiseLite.FractalType.FRACTAL_PING_PONG
		_:
			return FastNoiseLite.FractalType.FRACTAL_NONE

func _resolve_sample_positions(in_data : FlowData.Data) -> PackedVector3Array:
	var sample_name = settings.sample_attribute.strip_edges()
	if sample_name == "":
		sample_name = FlowData.AttrPosition
	var sample_stream = in_data.findStream(sample_name)
	if sample_stream and sample_stream.data_type == FlowData.DataType.Vector:
		var size = in_data.size()
		var stream_size = sample_stream.container.size()
		var values : PackedVector3Array = sample_stream.container
		if stream_size == size:
			return values
		if stream_size == 1 and size > 0:
			var expanded := PackedVector3Array()
			expanded.resize(size)
			for i in range(size):
				expanded[i] = values[0]
			return expanded
	return in_data.getVector3Container(FlowData.AttrPosition)

func _sample_noise(noise : FastNoiseLite, p : Vector3) -> float:
	if settings.sample_space == NoiseNodeSettings.eSampleSpace.XZ2D:
		return noise.get_noise_2d(p.x, p.z)
	return noise.get_noise_3d(p.x, p.y, p.z)

func execute( _ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, _ctx)
	if in_data == null:
		return

	var out_data : FlowData.Data = in_data.duplicate()

	var ipos : PackedVector3Array = _resolve_sample_positions(in_data)
	if ipos.size() != in_data.size():
		setError("Noise source attribute '%s' must be a Vector stream with %d values (or 1 for broadcast)" % [settings.sample_attribute, in_data.size()])
		return
		
	var noise := FastNoiseLite.new()
	noise.seed = effective_seed()
	noise.noise_type = _map_noise_type()
	noise.fractal_type = _map_fractal_type()
	noise.fractal_octaves = maxi(1, settings.fractal_octaves)
	noise.fractal_lacunarity = settings.fractal_lacunarity
	noise.fractal_gain = settings.fractal_gain
	noise.fractal_ping_pong_strength = settings.fractal_ping_pong_strength
	
	var in_scale : float = settings.in_scale
	var noise_bias : float = settings.noise_bias
	var noise_amplitude : float = settings.noise_amplitude
	
	var in_size := in_data.size()
	
	var target_exists := false
	var existing_stream = out_data.findStream(settings.out_name)
	if existing_stream != null and settings.mode == NoiseNodeSettings.eMode.Add:
		var existing_size : int = existing_stream.container.size()
		if existing_size == in_size or existing_size == 1:
			target_exists = true
		else:
			push_warning("Noise '%s': existing stream '%s' has %d values but input has %d points — Add mode falls back to Override" % [name, settings.out_name, existing_size, in_size])

	var out_container
	
	if settings.output_type == NoiseNodeSettings.eOutputType.Vector3:
		var sout_generated := PackedVector3Array()
		sout_generated.resize(in_size)
		for i in range(in_size):
			var pos := ipos[i] * in_scale
			var raw_x := _sample_noise(noise, pos)
			var raw_y := _sample_noise(noise, pos + Vector3(100.0, 100.0, 100.0))
			var raw_z := _sample_noise(noise, pos + Vector3(200.0, 200.0, 200.0))
			
			var val_x := noise_bias + clampf((raw_x + 1.0) * 0.5, 0.0, 1.0) * noise_amplitude
			var val_y := noise_bias + clampf((raw_y + 1.0) * 0.5, 0.0, 1.0) * noise_amplitude
			var val_z := noise_bias + clampf((raw_z + 1.0) * 0.5, 0.0, 1.0) * noise_amplitude
			
			sout_generated[i] = Vector3(val_x, val_y, val_z)
			
		if target_exists:
			var existing_container = existing_stream.container
			var existing_size : int = existing_container.size()
			if existing_stream.data_type == FlowData.DataType.Vector:
				var out_vec := PackedVector3Array()
				out_vec.resize(in_size)
				for i in range(in_size):
					out_vec[i] = existing_container[FlowData.bcast_idx(existing_size, i)] + sout_generated[i]
				out_container = out_vec
			elif existing_stream.data_type == FlowData.DataType.Float:
				var out_vec := PackedVector3Array()
				out_vec.resize(in_size)
				for i in range(in_size):
					var e : float = existing_container[FlowData.bcast_idx(existing_size, i)]
					out_vec[i] = Vector3(e, e, e) + sout_generated[i]
				out_container = out_vec
			else:
				push_warning("Noise '%s': Add mode only supports Float/Vector streams — '%s' is overridden" % [name, settings.out_name])
				out_container = sout_generated
		else:
			out_container = sout_generated
	else:
		var sout_generated := PackedFloat32Array()
		sout_generated.resize(in_size)
		for i in range(in_size):
			var pos := ipos[i] * in_scale
			var raw_noise := _sample_noise(noise, pos)
			var noise_01 := (raw_noise + 1.0) * 0.5
			var nval := clampf(noise_01, 0.0, 1.0)
			sout_generated[i] = noise_bias + nval * noise_amplitude
			
		if target_exists:
			var existing_container = existing_stream.container
			var existing_size : int = existing_container.size()
			if existing_stream.data_type == FlowData.DataType.Float:
				var out_floats := PackedFloat32Array()
				out_floats.resize(in_size)
				for i in range(in_size):
					out_floats[i] = existing_container[FlowData.bcast_idx(existing_size, i)] + sout_generated[i]
				out_container = out_floats
			elif existing_stream.data_type == FlowData.DataType.Vector:
				var out_vec := PackedVector3Array()
				out_vec.resize(in_size)
				for i in range(in_size):
					out_vec[i] = existing_container[FlowData.bcast_idx(existing_size, i)] + Vector3(sout_generated[i], sout_generated[i], sout_generated[i])
				out_container = out_vec
			else:
				push_warning("Noise '%s': Add mode only supports Float/Vector streams — '%s' is overridden" % [name, settings.out_name])
				out_container = sout_generated
		else:
			out_container = sout_generated
			
	var err = out_data.registerStream(settings.out_name, out_container)
	if err:
		setError(err)
		return
		
	set_output(0, out_data)
