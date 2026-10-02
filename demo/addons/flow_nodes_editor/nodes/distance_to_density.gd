@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Distance to Density",
		"category" : "Density",
		"settings" : DistanceToDensityNodeSettings,
		"ins" : [{ "label": "In" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Sets the point density according to the distance of each point from a reference point.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		setError("Input 'In' is not connected")
		return
	
	var spos = in_data.getContainerChecked(FlowData.AttrPosition, FlowData.DataType.Vector)
	if spos == null:
		setError("Input points do not have a position stream")
		return
		
	var out_data : FlowData.Data = in_data.duplicate()
	var num_elems = in_data.size()
	var densities := PackedFloat32Array()
	densities.resize(num_elems)
	
	var ref_pos = settings.reference_position
	var min_dist = settings.min_distance
	var max_dist = settings.max_distance
	var min_dens = settings.min_density
	var max_dens = settings.max_density
	var invert = settings.invert
	
	var range_dist = max_dist - min_dist
	if range_dist == 0.0:
		range_dist = 1.0
		
	for i in num_elems:
		var dist = spos[i].distance_to(ref_pos)
		var t = clamp((dist - min_dist) / range_dist, 0.0, 1.0)
		if invert:
			t = 1.0 - t
		densities[i] = lerpf(min_dens, max_dens, t)
		
	out_data.registerStream("density", densities, FlowData.DataType.Float)
	set_output(0, out_data)
