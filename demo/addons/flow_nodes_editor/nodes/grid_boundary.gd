@tool
extends FlowNodeBase

const GridBoundaryNodeSettings = preload("res://addons/flow_nodes_editor/nodes/grid_boundary_settings.gd")

func _init():
	meta_node = {
		"title" : "Grid Boundary",
		"settings" : GridBoundaryNodeSettings,
		"ins" : [{ "label": "Filled Cells" }],
		"outs" : [{ "label" : "Edges" }, { "label" : "Corners" }, { "label" : "All" }],
		"tooltip" : "Extracts exposed edge and corner points from filled grid cells.",
	}

func _safe_cell_size() -> Vector3:
	return Vector3(
		maxf(absf(settings.cell_size.x), 0.0001),
		maxf(absf(settings.cell_size.y), 0.0001),
		maxf(absf(settings.cell_size.z), 0.0001)
	)

func _key(cell : Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

func _to_cell(pos : Vector3, cell_size : Vector3) -> Vector3i:
	return Vector3i(roundi(pos.x / cell_size.x), roundi(pos.y / cell_size.y), roundi(pos.z / cell_size.z))

func _to_pos(cell : Vector3i, cell_size : Vector3) -> Vector3:
	return Vector3(float(cell.x) * cell_size.x, float(cell.y) * cell_size.y, float(cell.z) * cell_size.z)

func _is_occupied(occupied : Dictionary, cell : Vector3i) -> bool:
	return occupied.has(_key(cell))

func _is_corner_vertex(occupied : Dictionary, cell : Vector3i, sx : int, sz : int) -> bool:
	var samples : Array[bool] = [
		_is_occupied(occupied, cell),
		_is_occupied(occupied, cell + Vector3i(sx, 0, 0)),
		_is_occupied(occupied, cell + Vector3i(0, 0, sz)),
		_is_occupied(occupied, cell + Vector3i(sx, 0, sz)),
	]
	var occupied_count := 0
	for filled : bool in samples:
		if filled:
			occupied_count += 1
	if occupied_count == 1 or occupied_count == 3:
		return true
	if occupied_count != 2:
		return false
	return samples[0] == samples[3] and samples[1] == samples[2]

func _append_record(records : Array, pos : Vector3, rot : Vector3, size : Vector3, normal : Vector3, type_name : String) -> void:
	records.append({
		"position": pos,
		"rotation": rot,
		"size": size,
		"normal": normal,
		"type": type_name,
	})

func _records_to_data(records : Array) -> FlowData.Data:
	var out_data := FlowData.Data.new()
	out_data.addCommonStreams(records.size())
	var positions := out_data.getVector3Container(FlowData.AttrPosition)
	var rotations := out_data.getVector3Container(FlowData.AttrRotation)
	var sizes := out_data.getVector3Container(FlowData.AttrSize)
	var normals := PackedVector3Array()
	var types := PackedStringArray()
	normals.resize(records.size())
	types.resize(records.size())
	for idx : int in range(records.size()):
		var record : Dictionary = records[idx]
		positions[idx] = record.position
		rotations[idx] = record.rotation
		sizes[idx] = record.size
		normals[idx] = record.normal
		types[idx] = record.type
	if settings.normal_attribute != "":
		out_data.registerStream(settings.normal_attribute, normals, FlowData.DataType.Vector)
	if settings.type_attribute != "":
		out_data.registerStream(settings.type_attribute, types, FlowData.DataType.String)
	return out_data

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		if Engine.is_editor_hint() and _ctx.owner == null:
			var empty := FlowData.Data.new()
			set_output(0, empty)
			set_output(1, empty)
			set_output(2, empty)
			return
		setError("Input not found")
		return
	var in_positions := in_data.getVector3Container(FlowData.AttrPosition)
	if in_positions.size() != in_data.size():
		if Engine.is_editor_hint() and _ctx.owner == null:
			var empty := FlowData.Data.new()
			set_output(0, empty)
			set_output(1, empty)
			set_output(2, empty)
			return
		setError("Input must provide position for each filled cell")
		return

	var cell_size := _safe_cell_size()
	var occupied := {}
	var cells : Array[Vector3i] = []
	for idx : int in range(in_positions.size()):
		var cell := _to_cell(in_positions[idx], cell_size)
		var key := _key(cell)
		if occupied.has(key):
			continue
		occupied[key] = true
		cells.append(cell)

	var edge_records : Array = []
	var corner_records : Array = []
	var corner_seen := {}
	var dirs : Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]

	for cell : Vector3i in cells:
		var center := _to_pos(cell, cell_size)
		for dir : Vector3i in dirs:
			var neighbor := cell + dir
			if occupied.has(_key(neighbor)):
				continue
			var normal := Vector3(float(dir.x), 0.0, float(dir.z))
			var edge_pos := center + Vector3(
				float(dir.x) * cell_size.x * 0.5,
				0.0,
				float(dir.z) * cell_size.z * 0.5
			)
			var edge_rot := Vector3.ZERO
			var edge_size := Vector3(cell_size.x, settings.wall_height, settings.wall_thickness)
			if dir.x != 0:
				edge_rot.y = 90.0
				edge_size = Vector3(settings.wall_thickness, settings.wall_height, cell_size.z)
			_append_record(edge_records, edge_pos, edge_rot, edge_size, normal, "edge")

		if settings.include_corners:
			for sx : int in [-1, 1]:
				for sz : int in [-1, 1]:
					var corner_key := "%d,%d,%d" % [cell.x * 2 + sx, cell.y, cell.z * 2 + sz]
					if corner_seen.has(corner_key):
						continue
					if not _is_corner_vertex(occupied, cell, sx, sz):
						continue
					corner_seen[corner_key] = true
					var corner_pos := center + Vector3(
						float(sx) * cell_size.x * 0.5,
						0.0,
						float(sz) * cell_size.z * 0.5
					)
					var corner_size := Vector3(settings.wall_thickness, settings.wall_height, settings.wall_thickness)
					var corner_normal := Vector3(float(sx), 0.0, float(sz)).normalized()
					_append_record(corner_records, corner_pos, Vector3.ZERO, corner_size, corner_normal, "corner")

	var all_records : Array = []
	all_records.append_array(edge_records)
	all_records.append_array(corner_records)
	set_output(0, _records_to_data(edge_records))
	set_output(1, _records_to_data(corner_records))
	set_output(2, _records_to_data(all_records))
