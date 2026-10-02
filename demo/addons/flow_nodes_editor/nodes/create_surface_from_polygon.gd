@tool
extends FlowNodeBase

const CreateSurfaceFromPolygonSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_polygon_settings.gd")

func _init():
	meta_node = {
		"title" : "Create Surface From Polygon",
		"settings" : CreateSurfaceFromPolygonSettings,
		"ins" : [{ "label" : "Polygon Points" }],
		"outs" : [{ "label" : "Surfaces" }],
		"tooltip" : "Creates bounds-style surface points from ordered polygon point streams.\nShape mode outputs real surface data (a polygon surface per group) instead.\nOutput is an axis-aligned bounding-box point (rotation is always zero).\nArea uses the shoelace formula: points must be ordered, planar and non-self-intersecting.",
		"category" : "Spatial",
	}

func _to_plane(v : Vector3) -> Vector2:
	match settings.plane:
		CreateSurfaceFromPolygonSettings.ePlane.XY:
			return Vector2(v.x, v.y)
		CreateSurfaceFromPolygonSettings.ePlane.YZ:
			return Vector2(v.y, v.z)
		_:
			return Vector2(v.x, v.z)

func _area(points : PackedVector3Array) -> float:
	if points.size() < 3:
		return 0.0
	var sum := 0.0
	for i in range(points.size()):
		var a := _to_plane(points[i])
		var b := _to_plane(points[(i + 1) % points.size()])
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5

func _perimeter(points : PackedVector3Array) -> float:
	if points.size() < 2:
		return 0.0
	var sum := 0.0
	for i in range(points.size()):
		sum += points[i].distance_to(points[(i + 1) % points.size()])
	return sum

func _bounds(points : PackedVector3Array) -> AABB:
	var aabb := AABB(points[0], Vector3.ZERO)
	for p in points:
		aabb = aabb.expand(p)
	var min_t := maxf(0.0, settings.minimum_thickness)
	if aabb.size.x < min_t:
		aabb.size.x = min_t
	if aabb.size.y < min_t:
		aabb.size.y = min_t
	if aabb.size.z < min_t:
		aabb.size.z = min_t
	return aabb

# Returns the grouped point arrays, or null after setError on a malformed group stream
func _group_points(in_data : FlowData.Data, positions : PackedVector3Array):
	var group_attr : String = settings.group_attribute.strip_edges()
	if group_attr == "":
		return [positions]
	var stream = in_data.findStream(group_attr)
	if stream == null:
		return [positions]
	var stream_size : int = stream.container.size()
	if stream_size != positions.size() and stream_size != 1:
		setError("Group attribute '%s' has %d values but input has %d points (expected %d or 1)" % [group_attr, stream_size, positions.size(), positions.size()])
		return null
	var groups := {}
	var order : Array = []
	for i in range(positions.size()):
		var key = stream.container[FlowData.bcast_idx(stream_size, i)]
		if not groups.has(key):
			groups[key] = PackedVector3Array()
			order.append(key)
		groups[key].append(positions[i])
	var out : Array = []
	for key in order:
		out.append(groups[key])
	return out

## Shape mode: one Data per surface (or one union Data with merge_shapes), each
## with @data area / perimeter attributes named like the Points mode streams.
func _emit_shapes(surfaces : Array, areas : PackedFloat32Array, perimeters : PackedFloat32Array) -> void:
	if surfaces.is_empty():
		var empty := FlowData.Data.new()
		empty.kind = FlowData.Kind.Surface
		set_output(0, empty)
		return
	var area_attr : String = settings.out_area_attribute.strip_edges()
	var perimeter_attr : String = settings.out_perimeter_attribute.strip_edges()
	if settings.merge_shapes:
		var merged := FlowData.Data.from_shape(FlowCompositeShape.union_of(surfaces))
		if area_attr != "":
			var total := 0.0
			for a in areas:
				total += a
			merged.set_data_attr(area_attr, total, FlowData.DataType.Float)
		set_output(0, merged)
		return
	for i in range(surfaces.size()):
		var d := FlowData.Data.from_shape(surfaces[i])
		if area_attr != "":
			d.set_data_attr(area_attr, areas[i], FlowData.DataType.Float)
		if perimeter_attr != "":
			d.set_data_attr(perimeter_attr, perimeters[i], FlowData.DataType.Float)
		set_output(0, d)

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, _ctx, "Polygon Points input")
	if in_data == null:
		return
	var positions := in_data.getVector3Container(FlowData.AttrPosition)
	if positions.size() != in_data.size() or positions.size() < 3:
		setError("Polygon input must provide at least three position points")
		return

	var out_positions := PackedVector3Array()
	var out_rotations := PackedVector3Array()
	var out_sizes := PackedVector3Array()
	var areas := PackedFloat32Array()
	var perimeters := PackedFloat32Array()
	var counts := PackedInt32Array()

	var groups = _group_points(in_data, positions)
	if groups == null:
		return
	if settings.output_mode == CreateSurfaceFromPolygonSettings.eOutputMode.Shape:
		var surfaces : Array = []
		var shape_areas := PackedFloat32Array()
		var shape_perimeters := PackedFloat32Array()
		for group in groups:
			var pts : PackedVector3Array = group
			if pts.size() < 3:
				continue
			surfaces.append(FlowPolygonSurface.from_world_points(pts, settings.plane))
			shape_areas.append(_area(pts))
			shape_perimeters.append(_perimeter(pts))
		_emit_shapes(surfaces, shape_areas, shape_perimeters)
		return
	var dropped_groups := 0
	for group in groups:
		var pts : PackedVector3Array = group
		if pts.size() < 3:
			dropped_groups += 1
			continue
		var aabb := _bounds(pts)
		out_positions.append(aabb.position + aabb.size * 0.5)
		out_rotations.append(Vector3.ZERO)
		out_sizes.append(aabb.size)
		areas.append(_area(pts))
		perimeters.append(_perimeter(pts))
		counts.append(pts.size())

	if dropped_groups > 0:
		push_warning("Create Surface From Polygon: %d group(s) with fewer than 3 points were dropped" % dropped_groups)

	var out := FlowData.Data.new()
	out.addCommonStreams(out_positions.size())
	var op := out.getVector3Container(FlowData.AttrPosition)
	var orot := out.getVector3Container(FlowData.AttrRotation)
	var osize := out.getVector3Container(FlowData.AttrSize)
	# UE parity: unit scale; the polygon AABB extent is recorded as bounds. The
	# opt-in legacy bridge keeps size = extent (old size-as-scale) when requested.
	var legacy : bool = settings.legacy_scale_from_extent
	for i in range(out_positions.size()):
		op[i] = out_positions[i]
		orot[i] = out_rotations[i]
		osize[i] = out_sizes[i] if legacy else Vector3.ONE
	if not legacy:
		out.setSymmetricBounds(out_sizes)
	if settings.out_area_attribute.strip_edges() != "":
		out.registerStream(settings.out_area_attribute, areas, FlowData.DataType.Float)
	if settings.out_perimeter_attribute.strip_edges() != "":
		out.registerStream(settings.out_perimeter_attribute, perimeters, FlowData.DataType.Float)
	if settings.out_point_count_attribute.strip_edges() != "":
		out.registerStream(settings.out_point_count_attribute, counts, FlowData.DataType.Int)
	set_output(0, out)
