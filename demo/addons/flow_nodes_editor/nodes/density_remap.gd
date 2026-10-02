@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Density Remap",
		"category" : "Density",
		"settings" : DensityRemapNodeSettings,
		"ins" : [{ "label": "In" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Applies a linear transform to the point densities.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		setError("Input 'In' is not connected")
		return
	
	var out_data : FlowData.Data = in_data.duplicate()
	var s_density = in_data.findStream("density")
	
	var num_elems = in_data.size()
	var densities := PackedFloat32Array()
	densities.resize(num_elems)
	
	var in_container = s_density.container if s_density else null
	
	var in_min = settings.in_min
	var in_max = settings.in_max
	var out_min = settings.out_min
	var out_max = settings.out_max
	var clamp_val = settings.clamp_to_output_range
	
	var range_in = in_max - in_min
	if range_in == 0.0:
		range_in = 1.0
		
	for i in num_elems:
		var d = in_container[i] if in_container else 1.0
		var mapped = (out_max - out_min) * (d - in_min) / range_in + out_min
		if clamp_val:
			mapped = clamp(mapped, min(out_min, out_max), max(out_min, out_max))
		densities[i] = mapped
		
	out_data.registerStream("density", densities, FlowData.DataType.Float)
	set_output(0, out_data)
