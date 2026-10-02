@tool
extends FlowNodeBase

const DungeonGeneratorNodeSettings = preload("res://addons/flow_nodes_editor/nodes/dungeon_generator_settings.gd")

func _init():
	meta_node = {
		"title" : "Dungeon Generator",
		"settings" : DungeonGeneratorNodeSettings,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["dungeon", "rooms and corridors", "level generator"],
		"category" : "Sampler",
		"tooltip" : "Generates procedural floor, wall, pillar, torch, and chest layout points using a grid room-carving algorithm.\nThe 'type' stream encodes 0=Floor, 1=Wall, 2=Pillar, 3=Torch, 4=Chest.",
	}

func execute(ctx : FlowData.EvaluationContext):
	var output := FlowData.Data.new()
	
	# Get settings values safely
	var w : int = getSettingValue(ctx, "width", 20)
	var h : int = getSettingValue(ctx, "height", 20)
	var cell_size : float = getSettingValue(ctx, "cell_size", 2.0)
	var max_rooms : int = getSettingValue(ctx, "max_rooms", 8)
	var room_min : int = getSettingValue(ctx, "room_min_size", 4)
	var room_max : int = getSettingValue(ctx, "room_max_size", 8)
	var torch_prob : float = getSettingValue(ctx, "torch_probability", 0.15)
	var seed_val : int = derive_seed(graph_seed, int(getSettingValue(ctx, "random_seed", 12345)))
	
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	
	# Grid: 0 = Empty, 1 = Floor
	var grid = []
	grid.resize(w * h)
	grid.fill(0)
	
	var get_cell = func(x: int, y: int) -> int:
		if x < 0 or x >= w or y < 0 or y >= h:
			return 0
		return grid[y * w + x]
		
	var set_cell = func(x: int, y: int, val: int):
		if x >= 0 and x < w and y >= 0 and y < h:
			grid[y * w + x] = val

	if room_min > room_max:
		setError("room_min_size (%d) must be <= room_max_size (%d)" % [room_min, room_max])
		return

	var rooms = []

	# 1. Generate Rooms
	for i in range(max_rooms):
		# Clamp so the randi_range bounds below never invert (Godot silently
		# swaps inverted bounds, which would place rooms outside the margin).
		var rw = mini(rng.randi_range(room_min, room_max), w - 3)
		var rh = mini(rng.randi_range(room_min, room_max), h - 3)
		var rx = rng.randi_range(1, w - rw - 2)
		var ry = rng.randi_range(1, h - rh - 2)
		
		# Check overlap
		var overlap = false
		for r in rooms:
			if not (rx + rw + 1 < r.x or rx - 1 > r.x + r.w or ry + rh + 1 < r.y or ry - 1 > r.y + r.h):
				overlap = true
				break
				
		if not overlap:
			# Carve Room
			for dy in range(rh):
				for dx in range(rw):
					set_cell.call(rx + dx, ry + dy, 1)
			var cx = rx + int(rw / 2)
			var cy = ry + int(rh / 2)
			rooms.append({"x": rx, "y": ry, "w": rw, "h": rh, "cx": cx, "cy": cy})
			
	# 2. Generate Corridors (connect room centers)
	for i in range(1, rooms.size()):
		var r1 = rooms[i-1]
		var r2 = rooms[i]
		
		var cx1 = r1.cx
		var cy1 = r1.cy
		var cx2 = r2.cx
		var cy2 = r2.cy
		
		if rng.randf() > 0.5:
			# Horiz first
			var x_start = min(cx1, cx2)
			var x_end = max(cx1, cx2)
			for x in range(x_start, x_end + 1):
				set_cell.call(x, cy1, 1)
			# Vert
			var y_start = min(cy1, cy2)
			var y_end = max(cy1, cy2)
			for y in range(y_start, y_end + 1):
				set_cell.call(cx2, y, 1)
		else:
			# Vert first
			var y_start = min(cy1, cy2)
			var y_end = max(cy1, cy2)
			for y in range(y_start, y_end + 1):
				set_cell.call(cx1, y, 1)
			# Horiz
			var x_start = min(cx1, cx2)
			var x_end = max(cx1, cx2)
			for x in range(x_start, x_end + 1):
				set_cell.call(x, cy2, 1)

	# Now collect all outputs
	var out_positions = PackedVector3Array()
	var out_rotations = PackedVector3Array()
	var out_sizes = PackedVector3Array()
	var out_types = PackedFloat32Array() # 0=Floor, 1=Wall, 2=Pillar, 3=Torch, 4=Chest
	
	var add_point = func(pos: Vector3, rot: Vector3, p_type: float):
		out_positions.append(pos)
		out_rotations.append(rot)
		out_sizes.append(Vector3.ONE)
		out_types.append(p_type)

	# 1. Floor points
	for y in range(h):
		for x in range(w):
			if get_cell.call(x, y) == 1:
				var pos = Vector3(x * cell_size, 0, y * cell_size)
				add_point.call(pos, Vector3.ZERO, 0.0) # Type 0.0 = Floor
				
	# 2. Wall points and Torches
	# Check adjacent cells for empty to place walls
	# Rotations:
	# - North (dy=-1): wall stands on north edge, faces South (0 degrees)
	# - South (dy=1): wall stands on south edge, faces North (180 degrees)
	# - East (dx=1): wall stands on east edge, faces West (270 degrees)
	# - West (dx=-1): wall stands on west edge, faces East (90 degrees)
	# Rotation stream is Euler DEGREES (TransformsStream applies deg_to_rad on read).
	var dir_offsets = [
		{"dx": 0, "dy": -1, "rot": Vector3(0, 0, 0), "offset": Vector3(0, 0, -cell_size * 0.5)}, # North
		{"dx": 0, "dy": 1, "rot": Vector3(0, 180.0, 0), "offset": Vector3(0, 0, cell_size * 0.5)},  # South
		{"dx": 1, "dy": 0, "rot": Vector3(0, -90.0, 0), "offset": Vector3(cell_size * 0.5, 0, 0)}, # East
		{"dx": -1, "dy": 0, "rot": Vector3(0, 90.0, 0), "offset": Vector3(-cell_size * 0.5, 0, 0)} # West
	]
	
	for y in range(h):
		for x in range(w):
			if get_cell.call(x, y) == 1: # Floor cell
				var cell_center = Vector3(x * cell_size, 0, y * cell_size)
				for d in dir_offsets:
					var nx = x + d.dx
					var ny = y + d.dy
					if get_cell.call(nx, ny) == 0: # Neighbor is empty, spawn wall!
						var wall_pos = cell_center + d.offset
						add_point.call(wall_pos, d.rot, 1.0) # Type 1.0 = Wall
						
						# Spawn torch on this wall occasionally
						if rng.randf() < torch_prob:
							# Offset slightly inwards from the wall towards the center of the cell, and raise it
							var torch_pos = cell_center + d.offset * 0.9 + Vector3(0, 1.45, 0)
							add_point.call(torch_pos, d.rot, 3.0) # Type 3.0 = Torch

	# 3. Pillar points
	for y in range(h - 1):
		for x in range(w - 1):
			var c00 = get_cell.call(x, y)
			var c10 = get_cell.call(x + 1, y)
			var c01 = get_cell.call(x, y + 1)
			var c11 = get_cell.call(x + 1, y + 1)
			var total = c00 + c10 + c01 + c11
			# Place pillars only on true corners, not on straight boundaries.
			if total == 1 or total == 3:
				var pillar_pos = Vector3((x + 0.5) * cell_size, 0, (y + 0.5) * cell_size)
				add_point.call(pillar_pos, Vector3.ZERO, 2.0) # Type 2.0 = Pillar

	# 4. Chest points
	for r in rooms:
		var chest_pos = Vector3(r.cx * cell_size, 0, r.cy * cell_size)
		var chest_rot = Vector3(0, rng.randf_range(0.0, 360.0), 0)
		add_point.call(chest_pos, chest_rot, 4.0) # Type 4.0 = Chest

	# Register outputs
	var nsamples = out_positions.size()
	output.addCommonStreams(nsamples)
	
	var spos = output.getVector3Container(FlowData.AttrPosition)
	var srot = output.getVector3Container(FlowData.AttrRotation)
	var ssize = output.getVector3Container(FlowData.AttrSize)
	assert(spos != null)
	
	for idx in range(nsamples):
		spos[idx] = out_positions[idx]
		srot[idx] = out_rotations[idx]
		ssize[idx] = out_sizes[idx]
		
	var err = output.registerStream("type", out_types, FlowData.DataType.Float)
	if err:
		setError(err)
		return
		
	set_output(0, output)
