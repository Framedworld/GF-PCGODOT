@tool
extends FlowNodeBase

const PointNeighborhoodNodeSettings = preload("res://addons/flow_nodes_editor/nodes/point_neighborhood_settings.gd")

func _init():
	meta_node = {
		"title" : "Point Neighborhood",
		"settings" : PointNeighborhoodNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Computes neighborhood-derived values such as average center, average density, and distance to center.",
	}

func _validate_output_names() -> String:
	var used_names := {}
	var outputs = [
		{"enabled": settings.write_neighbor_count, "name": settings.out_neighbor_count, "label": "Neighbor count"},
		{"enabled": settings.write_distance_to_center, "name": settings.out_distance_to_center, "label": "Distance to center"},
		{"enabled": settings.write_average_center, "name": settings.out_average_center, "label": "Average center"},
		{"enabled": settings.write_average_density, "name": settings.out_average_density, "label": "Average density"},
		{"enabled": settings.write_average_color, "name": settings.out_average_color, "label": "Average color"},
	]
	for info in outputs:
		if not info.enabled:
			continue
		var out_name = String(info.name).strip_edges()
		if out_name == "":
			return "%s output name can't be empty when enabled" % info.label
		if used_names.has(out_name):
			return "Output name '%s' is assigned to multiple enabled outputs" % out_name
		used_names[out_name] = true
	return ""

func _read_density(stream, idx : int) -> float:
	if stream == null:
		return 0.0
	var n = stream.container.size()
	if n == 0:
		return 0.0
	var read_idx = idx if idx < n else (0 if n == 1 else -1)
	if read_idx < 0:
		return 0.0
	match stream.data_type:
		FlowData.DataType.Float:
			return stream.container[read_idx]
		FlowData.DataType.Int:
			return float(stream.container[read_idx])
	return 0.0

func _read_color_vec(stream, idx : int) -> Vector3:
	if stream == null:
		return Vector3.ZERO
	var n = stream.container.size()
	if n == 0:
		return Vector3.ZERO
	var read_idx = idx if idx < n else (0 if n == 1 else -1)
	if read_idx < 0:
		return Vector3.ZERO
	if stream.data_type == FlowData.DataType.Vector:
		return stream.container[read_idx]
	if stream.data_type == FlowData.DataType.Color:
		var c : Color = stream.container[read_idx]
		return Vector3(c.r, c.g, c.b)
	return Vector3.ZERO

func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		setError("Input not found")
		return

	var num_points = in_data.size()
	if num_points == 0:
		set_output(0, in_data.duplicate())
		return

	var positions = in_data.getVector3Container(FlowData.AttrPosition)
	if positions.size() != num_points:
		setError("Input must provide %s with %d elements (got %d)" % [FlowData.AttrPosition, num_points, positions.size()])
		return

	var name_error = _validate_output_names()
	if name_error != "":
		setError(name_error)
		return

	var write_count = settings.write_neighbor_count
	var write_dist_to_center = settings.write_distance_to_center
	var write_avg_center = settings.write_average_center
	var write_avg_density = settings.write_average_density
	var write_avg_color = settings.write_average_color

	if not (write_count or write_dist_to_center or write_avg_center or write_avg_density or write_avg_color):
		set_output(0, in_data.duplicate())
		return

	var max_dist : float = maxf(0.0, getSettingValue(ctx, "search_distance", settings.search_distance))
	var max_dist_sq : float = max_dist * max_dist
	var has_distance_limit = max_dist_sq > 0.0
	var include_self : bool = getSettingValue(ctx, "include_self")

	var density_stream = null
	if write_avg_density:
		if settings.density_attribute == "":
			setError("Density attribute name can't be empty when Average Density output is enabled")
			return
		density_stream = in_data.findStream(settings.density_attribute)
		if density_stream == null:
			setError("Density attribute '%s' not found" % settings.density_attribute)
			return
		if density_stream.data_type != FlowData.DataType.Float and density_stream.data_type != FlowData.DataType.Int:
			setError("Density attribute '%s' must be Float or Int" % settings.density_attribute)
			return
		var density_size = density_stream.container.size()
		if density_size != num_points and density_size != 1:
			setError("Density attribute '%s' must have %d elements or a single broadcast element (got %d)" % [settings.density_attribute, num_points, density_size])
			return

	var color_stream = null
	if write_avg_color:
		if settings.color_attribute == "":
			setError("Color attribute name can't be empty when Average Color output is enabled")
			return
		color_stream = in_data.findStream(settings.color_attribute)
		if color_stream == null:
			setError("Color attribute '%s' not found" % settings.color_attribute)
			return
		if color_stream.data_type != FlowData.DataType.Vector and color_stream.data_type != FlowData.DataType.Color:
			setError("Color attribute '%s' must be Vector or Color" % settings.color_attribute)
			return
		var color_size = color_stream.container.size()
		if color_size != num_points and color_size != 1:
			setError("Color attribute '%s' must have %d elements or a single broadcast element (got %d)" % [settings.color_attribute, num_points, color_size])
			return

	var out_count := PackedInt32Array()
	var out_dist_to_center := PackedFloat32Array()
	var out_avg_center := PackedVector3Array()
	var out_avg_density := PackedFloat32Array()
	var out_avg_color := PackedVector3Array()

	if write_count:
		out_count.resize(num_points)
	if write_dist_to_center:
		out_dist_to_center.resize(num_points)
	if write_avg_center:
		out_avg_center.resize(num_points)
	if write_avg_density:
		out_avg_density.resize(num_points)
	if write_avg_color:
		out_avg_color.resize(num_points)

	var use_tree = has_distance_limit and num_points > 1000
	var tA = GDRTree.new() if use_tree else null
	var candidate_pos : PackedVector3Array
	var candidate_size : PackedVector3Array
	if use_tree:
		candidate_pos.resize(1)
		candidate_size.resize(1)
		candidate_size[0] = Vector3.ONE * max_dist * 2.0
		var zero_sizes = PackedVector3Array()
		zero_sizes.resize(num_points)
		tA.add(positions, zero_sizes)

	for i in range(num_points):
		var pi = positions[i]
		var count = 0
		var acc_center = Vector3.ZERO
		var acc_density = 0.0
		var acc_color = Vector3.ZERO

		var neighbors
		if use_tree:
			candidate_pos[0] = pi
			var result = tA.overlaps(candidate_pos, candidate_size, true)
			neighbors = result.get("idxs_overlapped", [])
		else:
			neighbors = range(num_points)

		for j in neighbors:
			if not include_self and i == j:
				continue
			if has_distance_limit and pi.distance_squared_to(positions[j]) > max_dist_sq:
				continue

			count += 1
			acc_center += positions[j]
			if write_avg_density:
				acc_density += _read_density(density_stream, j)
			if write_avg_color:
				acc_color += _read_color_vec(color_stream, j)

		var avg_center = pi
		if count > 0:
			avg_center = acc_center / float(count)

		if write_count:
			out_count[i] = count
		if write_dist_to_center:
			out_dist_to_center[i] = pi.distance_to(avg_center)
		if write_avg_center:
			out_avg_center[i] = avg_center
		if write_avg_density:
			out_avg_density[i] = acc_density / float(count) if count > 0 else 0.0
		if write_avg_color:
			out_avg_color[i] = acc_color / float(count) if count > 0 else Vector3.ZERO

	var out_data : FlowData.Data = in_data.duplicate()
	var err = null

	if write_count:
		err = out_data.registerStream(settings.out_neighbor_count, out_count, FlowData.DataType.Int)
		if err:
			setError(err)
			return
	if write_dist_to_center:
		err = out_data.registerStream(settings.out_distance_to_center, out_dist_to_center, FlowData.DataType.Float)
		if err:
			setError(err)
			return
	if write_avg_center:
		err = out_data.registerStream(settings.out_average_center, out_avg_center, FlowData.DataType.Vector)
		if err:
			setError(err)
			return
	if write_avg_density:
		err = out_data.registerStream(settings.out_average_density, out_avg_density, FlowData.DataType.Float)
		if err:
			setError(err)
			return
	if write_avg_color:
		err = out_data.registerStream(settings.out_average_color, out_avg_color, FlowData.DataType.Vector)
		if err:
			setError(err)
			return

	set_output(0, out_data)
