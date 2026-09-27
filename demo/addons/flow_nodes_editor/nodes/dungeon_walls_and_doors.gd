@tool
extends FlowNodeBase

const DungeonWallsAndDoorsSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_walls_and_doors_settings.gd")

func _init():
	meta_node = {
		"title" : "Dungeon Walls and Doors",
		"settings" : DungeonWallsAndDoorsSettings,
		"ins" : [{ "label" : "FloorPoints" }],
		"outs" : [
			{ "label" : "Walls" },
			{ "label" : "Doors" },
			{ "label" : "Torches" },
			{ "label" : "Pillars" }
		],
		"aliases" : ["dungeon walls", "dungeon doors", "wall builder"],
		"category" : "Spatial",
		"tooltip" : "Analyzes the FloorPoints set to output walls, doors, torches, and pillars.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'FloorPoints'")
	if in_data == null:
		return
	if in_data.size() == 0:
		set_output(0, FlowData.Data.new())
		set_output(1, FlowData.Data.new())
		set_output(2, FlowData.Data.new())
		set_output(3, FlowData.Data.new())
		return
		
	var cell_size : float = getSettingValue(ctx, "cell_size", 2.0)
	var torch_prob : float = getSettingValue(ctx, "torch_probability", 0.15)
	var seed_val : int = derive_seed(graph_seed, int(getSettingValue(ctx, "random_seed", 12345)))
	var wall_inset : float = getSettingValue(ctx, "wall_inset", 0.0)
	var include_concave_pillars : bool = getSettingValue(ctx, "include_concave_pillars", true)
	var output_scale : Vector3 = getSettingValue(ctx, "output_scale", Vector3.ONE)
	
	var in_size = in_data.size()
	var in_pos = in_data.getVector3Container(FlowData.AttrPosition)
	var s_cell_type = in_data.findStream("CellType")
	
	if s_cell_type == null:
		setError("Input points must have a CellType attribute")
		return
		
	var rng := RandomNumberGenerator.new()
	
	# Build lookup map of existing floors
	var floor_map = {}
	for i in range(in_size):
		var pos = in_pos[i]
		var cx = int(round(pos.x / cell_size))
		var cy = int(round(pos.z / cell_size))
		floor_map[Vector2i(cx, cy)] = {
			"pos": pos,
			"cell_type": s_cell_type.container[i]
		}
		
	# North, South, East, West offsets
	# Rotation stream is Euler DEGREES (TransformsStream applies deg_to_rad on read).
	var dir_offsets = [
		{"dx": 0, "dy": -1, "rot": Vector3(0, 0, 0), "offset": Vector3(0, 0, -cell_size * 0.5)}, # North
		{"dx": 0, "dy": 1, "rot": Vector3(0, 180.0, 0), "offset": Vector3(0, 0, cell_size * 0.5)},  # South
		{"dx": 1, "dy": 0, "rot": Vector3(0, -90.0, 0), "offset": Vector3(cell_size * 0.5, 0, 0)}, # East
		{"dx": -1, "dy": 0, "rot": Vector3(0, 90.0, 0), "offset": Vector3(-cell_size * 0.5, 0, 0)} # West
	]
	
	var wall_positions = PackedVector3Array()
	var wall_rotations = PackedVector3Array()
	
	var door_positions = PackedVector3Array()
	var door_rotations = PackedVector3Array()
	
	var torch_positions = PackedVector3Array()
	var torch_rotations = PackedVector3Array()
	
	for i in range(in_size):
		var pos = in_pos[i]
		var cx = int(round(pos.x / cell_size))
		var cy = int(round(pos.z / cell_size))
		var current_type = s_cell_type.container[i]
		
		# Seed generator based on position to keep torch randomness deterministic
		rng.seed = seed_val + cx * 31 + cy * 97
		
		for d in dir_offsets:
			var nx = cx + d.dx
			var ny = cy + d.dy
			var nkey = Vector2i(nx, ny)
			
			if not floor_map.has(nkey):
				# Neighbor is empty, place wall!
				var dir_vec : Vector3 = d.offset.normalized()
				var wall_pos = pos + d.offset - dir_vec * wall_inset
				wall_positions.append(wall_pos)
				wall_rotations.append(d.rot)
				
				# Torch placement
				if current_type == "Room" and rng.randf() < torch_prob:
					var torch_pos = wall_pos - dir_vec * (cell_size * 0.05) + Vector3(0, 1.45, 0)
					torch_positions.append(torch_pos)
					torch_rotations.append(d.rot)
			else:
				var neighbor = floor_map[nkey]
				if current_type == "Room" and neighbor.cell_type == "Corridor":
					# Transition from Room to Corridor: place door!
					var door_pos = pos + d.offset - d.offset.normalized() * wall_inset
					door_positions.append(door_pos)
					door_rotations.append(d.rot)
					
	# Pillar points
	var pillar_positions = PackedVector3Array()
	var pillar_rotations = PackedVector3Array()
	
	# Find bounds of the floor layout
	var min_c = Vector2i(999999, 999999)
	var max_c = Vector2i(-999999, -999999)
	for key in floor_map:
		min_c.x = min(min_c.x, key.x)
		min_c.y = min(min_c.y, key.y)
		max_c.x = max(max_c.x, key.x)
		max_c.y = max(max_c.y, key.y)
		
	# Loop over intersections
	for y in range(min_c.y - 1, max_c.y + 1):
		for x in range(min_c.x - 1, max_c.x + 1):
			var c00 = 1 if floor_map.has(Vector2i(x, y)) else 0
			var c10 = 1 if floor_map.has(Vector2i(x + 1, y)) else 0
			var c01 = 1 if floor_map.has(Vector2i(x, y + 1)) else 0
			var c11 = 1 if floor_map.has(Vector2i(x + 1, y + 1)) else 0
			var total = c00 + c10 + c01 + c11
			var is_convex_corner = (total == 1)
			var is_concave_corner = (total == 3)
			if is_convex_corner or (include_concave_pillars and is_concave_corner):
				pillar_positions.append(Vector3((x + 0.5) * cell_size, 0, (y + 0.5) * cell_size))
				pillar_rotations.append(Vector3.ZERO)
				
	# Construct output datasets
	var create_output_data = func(positions: PackedVector3Array, rotations: PackedVector3Array, p_type: float) -> FlowData.Data:
		var n_pts = positions.size()
		var out := FlowData.Data.new()
		out.addCommonStreams(n_pts)
		var spos = out.getVector3Container(FlowData.AttrPosition)
		var srot = out.getVector3Container(FlowData.AttrRotation)
		var ssize = out.getVector3Container(FlowData.AttrSize)
		for idx in range(n_pts):
			spos[idx] = positions[idx]
			srot[idx] = rotations[idx]
			ssize[idx] = output_scale
		var out_types = PackedFloat32Array()
		out_types.resize(n_pts)
		out_types.fill(p_type)
		out.registerStream("type", out_types, FlowData.DataType.Float)
		return out
		
	set_output(0, create_output_data.call(wall_positions, wall_rotations, 1.0))
	set_output(1, create_output_data.call(door_positions, door_rotations, 1.0))
	set_output(2, create_output_data.call(torch_positions, torch_rotations, 3.0))
	set_output(3, create_output_data.call(pillar_positions, pillar_rotations, 2.0))
