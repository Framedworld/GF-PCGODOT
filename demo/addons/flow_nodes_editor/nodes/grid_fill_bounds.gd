@tool
extends FlowNodeBase

const GridFillBoundsNodeSettings = preload("res://addons/flow_nodes_editor/nodes/grid_fill_bounds_settings.gd")

func _init():
	meta_node = {
		"title" : "Grid Fill Bounds",
		"settings" : GridFillBoundsNodeSettings,
		"ins" : [{ "label": "Bounds" }],
		"outs" : [{ "label" : "Cells" }],
		"category" : "Sampler",
		"tooltip" : "Creates one point per grid cell inside input bounds, or inside configured bounds when no input is connected.\nWorld Anchored puts the cells on world multiples of cell_size (partition-invariant) instead of centring them on each box.",
	}

func _safe_cell_size() -> Vector3:
	return Vector3(
		maxf(absf(settings.cell_size.x), 0.0001),
		maxf(absf(settings.cell_size.y), 0.0001),
		maxf(absf(settings.cell_size.z), 0.0001)
	)

func _axis_positions(center : float, size : float, step : float) -> PackedFloat32Array:
	if settings.world_anchored:
		return _anchored_axis_positions(center, size, step)
	var count : int = maxi(1, roundi(absf(size) / step))
	var positions := PackedFloat32Array()
	positions.resize(count)
	var first := center - (float(count - 1) * step * 0.5)
	for idx : int in range(count):
		positions[idx] = first + float(idx) * step
	return positions

# World-anchored: every k * step with min <= k * step <= max (a tolerance of
# 1e-4 step on both edges absorbs float error), so the positions depend only on
# k and step, never on where the box starts.
func _anchored_axis_positions(center : float, size : float, step : float) -> PackedFloat32Array:
	var half := absf(size) * 0.5
	var eps := step * 1e-4
	var k_min := ceili((center - half - eps) / step)
	var k_max := floori((center + half + eps) / step)
	var positions := PackedFloat32Array()
	for k : int in range(k_min, k_max + 1):
		positions.append(float(k) * step)
	return positions

func _cell_key(pos : Vector3, cell_size : Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(pos.x / cell_size.x),
		roundi(pos.y / cell_size.y),
		roundi(pos.z / cell_size.z)
	]

func _append_bounds(center : Vector3, size : Vector3, cell_size : Vector3, out_positions : PackedVector3Array, source_indices : PackedInt32Array, seen : Dictionary, source_idx : int) -> PackedVector3Array:
	var xs := _axis_positions(center.x, size.x, cell_size.x)
	var ys := _axis_positions(center.y, size.y, cell_size.y) if settings.fill_y_axis else PackedFloat32Array([center.y])
	var zs := _axis_positions(center.z, size.z, cell_size.z)

	for x : float in xs:
		for y : float in ys:
			for z : float in zs:
				var pos := Vector3(x, y, z)
				var key := _cell_key(pos, cell_size)
				if seen.has(key):
					continue
				seen[key] = true
				out_positions.append(pos)
				source_indices.append(source_idx)
				if out_positions.size() >= settings.max_points:
					return out_positions
	return out_positions

func _copy_input_streams(in_data : FlowData.Data, source_indices : PackedInt32Array) -> FlowData.Data:
	var out_data := FlowData.Data.new()
	for stream_name in in_data.streams:
		var stream = in_data.streams[stream_name]
		var out_container = FlowData.Data.newContainerOfType(stream.data_type)
		out_container.resize(source_indices.size())
		for out_idx : int in range(source_indices.size()):
			out_container[out_idx] = stream.container[source_indices[out_idx]]
		out_data.registerStream(stream.name, out_container, stream.data_type)
	out_data.tags = in_data.tags.duplicate()
	return out_data

func execute(_ctx : FlowData.EvaluationContext):
	var cell_size := _safe_cell_size()
	var positions := PackedVector3Array()
	var source_indices := PackedInt32Array()
	var seen := {}
	var in_data : FlowData.Data = get_optional_input(0)

	if settings.use_input_bounds and in_data != null and in_data.size() > 0:
		var in_positions := in_data.getVector3Container(FlowData.AttrPosition)
		var in_sizes := in_data.getVector3Container(FlowData.AttrSize)
		if in_positions.size() != in_data.size():
			if is_ownerless_preview(_ctx):
				set_output(0, FlowData.Data.new())
				return
			setError("Input bounds must provide position for each point")
			return
		for idx : int in range(in_data.size()):
			var size : Vector3 = settings.bounds_size
			if in_sizes.size() == in_data.size():
				size = in_sizes[idx]
			elif in_sizes.size() == 1:
				size = in_sizes[0]
			positions = _append_bounds(in_positions[idx], size, cell_size, positions, source_indices, seen, idx)
			if positions.size() >= settings.max_points:
				break
	elif settings.use_input_bounds and in_data != null and in_data.size() == 0:
		set_output(0, FlowData.Data.new())
		return
	else:
		positions = _append_bounds(settings.bounds_center, settings.bounds_size, cell_size, positions, source_indices, seen, 0)

	var out_data := FlowData.Data.new()
	if settings.copy_input_attributes and in_data != null and in_data.size() > 0:
		out_data = _copy_input_streams(in_data, source_indices)
	else:
		out_data.addCommonStreams(positions.size())
	var out_positions = out_data.cloneStream(FlowData.AttrPosition)
	if out_positions == null:
		out_positions = out_data.addStream(FlowData.AttrPosition, FlowData.DataType.Vector)
		out_positions.resize(positions.size())
	var out_sizes = out_data.cloneStream(FlowData.AttrSize)
	if out_sizes == null:
		out_sizes = out_data.addStream(FlowData.AttrSize, FlowData.DataType.Vector)
		out_sizes.resize(positions.size())
	if not out_data.hasStream(FlowData.AttrRotation):
		var out_rotations = out_data.addStream(FlowData.AttrRotation, FlowData.DataType.Vector)
		out_rotations.resize(positions.size())
	for idx : int in range(positions.size()):
		out_positions[idx] = positions[idx]
		out_sizes[idx] = cell_size
	if settings.source_index_attribute != "":
		out_data.registerStream(settings.source_index_attribute, source_indices, FlowData.DataType.Int)

	# Density + per-point seed streams (UE parity). Density copied from the
	# source bounds (copy_input_attributes) is kept; seeds are always
	# recomputed because the cell positions are new points.
	var num_cells : int = positions.size()
	if not out_data.hasStream(FlowData.AttrDensity):
		var sdensity := PackedFloat32Array()
		sdensity.resize(num_cells)
		sdensity.fill(1.0)
		out_data.registerStream(FlowData.AttrDensity, sdensity, FlowData.DataType.Float)
	var node_seed : int = effective_seed()
	var sseed := PackedInt32Array()
	sseed.resize(num_cells)
	for idx : int in range(num_cells):
		sseed[idx] = FlowData.point_seed(positions[idx], node_seed)
	out_data.registerStream(FlowData.AttrSeed, sseed, FlowData.DataType.Int)

	set_output(0, out_data)
