@tool
extends FlowNodeBase

const RandomColorNodeSettings = preload("res://addons/flow_nodes_editor/nodes/random_color_settings.gd")

func _init():
	meta_node = {
		"title" : "Random Color",
		"settings" : RandomColorNodeSettings,
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"category" : "Metadata",
		"tooltip" : "Generates random colors for each point.\nWhen the input carries a per-point 'seed' stream, colors are derived from it and stay stable per point.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx)
	if not in_data:
		return
	var out_data : FlowData.Data = in_data.duplicate()
	var in_size = in_data.size()

	var rng = RandomNumberGenerator.new()
	rng.seed = effective_seed()

	# Per-point seed consumption (UE $Seed parity): when the input carries an
	# AttrSeed Int stream, each point's randomness comes from its own seed so
	# colors stay stable when points are added/removed upstream.
	var point_seeds = in_data.getContainerChecked(FlowData.AttrSeed, FlowData.DataType.Int)
	if point_seeds != null and point_seeds.size() == 0:
		point_seeds = null

	var colors = PackedColorArray()
	colors.resize(in_size)

	var use_palette = settings.use_palette
	var palette = settings.palette
	var palette_size = palette.size()

	var h_min = settings.hue_min
	var h_max = settings.hue_max
	var s_min = settings.sat_min
	var s_max = settings.sat_max
	var v_min = settings.val_min
	var v_max = settings.val_max

	for i in range(in_size):
		if point_seeds != null:
			rng.seed = int(point_seeds[FlowData.bcast_idx(point_seeds.size(), i)]) ^ effective_seed()
		if use_palette and palette_size > 0:
			var idx = rng.randi_range(0, palette_size - 1)
			colors[i] = palette[idx]
		else:
			var h = rng.randf_range(h_min, h_max)
			var s = rng.randf_range(s_min, s_max)
			var v = rng.randf_range(v_min, v_max)
			colors[i] = Color.from_hsv(h, s, v, 1.0)

	var err = out_data.registerStream(settings.out_name, colors)
	if err:
		setError(err)
		return
		
	set_output(0, out_data)
