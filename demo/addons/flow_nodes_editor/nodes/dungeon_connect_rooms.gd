@tool
extends FlowNodeBase

const DungeonConnectRoomsSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_connect_rooms_settings.gd")

func _init():
	meta_node = {
		"title" : "Dungeon Connect Rooms",
		"settings" : DungeonConnectRoomsSettings,
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["corridors", "connect rooms", "L corridor"],
		"category" : "Spatial",
		"tooltip" : "Generates sequential L-shaped corridor floor points between consecutive input room points (in input order).",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	if in_data.size() < 2:
		set_output(0, FlowData.Data.new())
		return
	# size() is the length of the first stream, so rows without positions get
	# here too.
	if not in_data.hasStream(FlowData.AttrPosition):
		setError("Input must provide a position stream")
		return

	var cell_size : float = getSettingValue(ctx, "cell_size", 2.0)
	var seed_val : int = derive_seed(graph_seed, int(getSettingValue(ctx, "random_seed", 12345)))

	var in_size = in_data.size()
	var in_pos = in_data.getVector3Container(FlowData.AttrPosition)

	var out_positions = PackedVector3Array()
	var out_cell_types = PackedStringArray()
	var out_connection_ids = PackedInt32Array()

	# Deduplicate corridor cells: the corner cell of each L is visited by both
	# legs, and overlapping corridors would otherwise stack duplicate points.
	var seen_cells := {}
	var add_cell = func(x: int, y: int, conn_id: int):
		var key := Vector2i(x, y)
		if seen_cells.has(key):
			return
		seen_cells[key] = true
		var pos = Vector3(x * cell_size, 0, y * cell_size)
		out_positions.append(pos)
		out_cell_types.append("Corridor")
		out_connection_ids.append(conn_id)
		
	var rng := RandomNumberGenerator.new()
	
	for i in range(1, in_size):
		var p1 = in_pos[i-1]
		var p2 = in_pos[i]
		
		var cx1 = int(round(p1.x / cell_size))
		var cy1 = int(round(p1.z / cell_size))
		var cx2 = int(round(p2.x / cell_size))
		var cy2 = int(round(p2.z / cell_size))
		
		# Seed RNG per connection to make it reproducible
		rng.seed = seed_val + i
		
		var conn_id = i - 1
		if rng.randf() > 0.5:
			# Horizontal first
			var x_start = min(cx1, cx2)
			var x_end = max(cx1, cx2)
			for x in range(x_start, x_end + 1):
				add_cell.call(x, cy1, conn_id)
			# Vertical
			var y_start = min(cy1, cy2)
			var y_end = max(cy1, cy2)
			for y in range(y_start, y_end + 1):
				add_cell.call(cx2, y, conn_id)
		else:
			# Vertical first
			var y_start = min(cy1, cy2)
			var y_end = max(cy1, cy2)
			for y in range(y_start, y_end + 1):
				add_cell.call(cx1, y, conn_id)
			# Horizontal
			var x_start = min(cx1, cx2)
			var x_end = max(cx1, cx2)
			for x in range(x_start, x_end + 1):
				add_cell.call(x, cy2, conn_id)
				
	var n_points = out_positions.size()
	var output := FlowData.Data.new()
	output.addCommonStreams(n_points)
	
	var spos = output.getVector3Container(FlowData.AttrPosition)
	var srot = output.getVector3Container(FlowData.AttrRotation)
	var ssize = output.getVector3Container(FlowData.AttrSize)
	
	for idx in range(n_points):
		spos[idx] = out_positions[idx]
		srot[idx] = Vector3.ZERO
		ssize[idx] = Vector3(cell_size, 1.0, cell_size)
		
	output.registerStream("CellType", out_cell_types, FlowData.DataType.String)
	output.registerStream("ConnectionID", out_connection_ids, FlowData.DataType.Int)
	
	var out_types = PackedFloat32Array()
	out_types.resize(n_points)
	out_types.fill(0.0)
	output.registerStream("type", out_types, FlowData.DataType.Float)
	
	set_output(0, output)
