@tool
extends FlowNodeBase

const DungeonRoomCandidatesSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_room_candidates_settings.gd")

func _init():
	meta_node = {
		"title" : "Dungeon Room Candidates",
		"settings" : DungeonRoomCandidatesSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["room candidates", "random rooms"],
		"category" : "Sampler",
		"tooltip" : "Generates a random set of room candidates snapped to grid, with priority, ID, and bounds.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var output := FlowData.Data.new()
	
	var w : int = getSettingValue(ctx, "grid_width", 24)
	var h : int = getSettingValue(ctx, "grid_height", 24)
	var cell_size : float = getSettingValue(ctx, "cell_size", 2.0)
	var n_candidates : int = getSettingValue(ctx, "candidate_count", 40)
	var r_min : int = getSettingValue(ctx, "min_room_size", 3)
	var r_max : int = getSettingValue(ctx, "max_room_size", 6)
	var seed_val : int = derive_seed(graph_seed, int(getSettingValue(ctx, "random_seed", 12345)))
	
	if r_min > r_max:
		setError("min_room_size (%d) must be <= max_room_size (%d)" % [r_min, r_max])
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	output.addCommonStreams(n_candidates)
	var spos = output.getVector3Container(FlowData.AttrPosition)
	var srot = output.getVector3Container(FlowData.AttrRotation)
	var ssize = output.getVector3Container(FlowData.AttrSize)
	
	var ids = PackedInt32Array()
	var widths = PackedFloat32Array()
	var heights = PackedFloat32Array()
	var priorities = PackedFloat32Array()
	
	ids.resize(n_candidates)
	widths.resize(n_candidates)
	heights.resize(n_candidates)
	priorities.resize(n_candidates)
	
	for i in range(n_candidates):
		# Clamp so the randi_range bounds below never invert (Godot silently
		# swaps inverted bounds, which would place rooms outside the margin).
		var rw = mini(rng.randi_range(r_min, r_max), w - 3)
		var rh = mini(rng.randi_range(r_min, r_max), h - 3)

		# Pick random bottom-left cell rx, ry (ensuring room fits within bounds)
		var rx = rng.randi_range(1, w - rw - 2)
		var ry = rng.randi_range(1, h - rh - 2)
		
		# Center cell coordinates
		var cx = rx + int(rw / 2.0)
		var cy = ry + int(rh / 2.0)
		
		spos[i] = Vector3(cx * cell_size, 0, cy * cell_size)
		srot[i] = Vector3.ZERO
		ssize[i] = Vector3(rw * cell_size, 1.0, rh * cell_size)
		
		ids[i] = i
		widths[i] = float(rw)
		heights[i] = float(rh)
		priorities[i] = rng.randf()
		
	output.registerStream("RoomID", ids, FlowData.DataType.Int)
	output.registerStream("RoomWidth", widths, FlowData.DataType.Float)
	output.registerStream("RoomHeight", heights, FlowData.DataType.Float)
	output.registerStream("RoomPriority", priorities, FlowData.DataType.Float)
	
	var types = PackedFloat32Array()
	types.resize(n_candidates)
	types.fill(4.0)
	output.registerStream("type", types, FlowData.DataType.Float)
	
	var b_selected = PackedByteArray()
	b_selected.resize(n_candidates)
	b_selected.fill(0) # false
	output.registerStream("bSelectedRoom", b_selected, FlowData.DataType.Bool)
	
	set_output(0, output)
