@tool
extends FlowNodeBase

const CreateSurfaceFromSplineSettings = preload("res://addons/flow_nodes_editor/nodes/create_surface_from_spline_settings.gd")

func _init():
	meta_node = {
		"title" : "Create Surface From Spline",
		"settings" : CreateSurfaceFromSplineSettings,
		"ins" : [{ "label" : "Splines", "data_type" : FlowData.DataType.NodePath }],
		"outs" : [{ "label" : "Surfaces" }],
		"tooltip" : "Creates one bounds-style surface point from each Path3D polygon/spline.\nOutput is an axis-aligned bounding-box point (rotation is always zero).\nShape mode outputs real surface data (a polygon surface per spline) instead.\nAccepts a Path3D 'node' stream or spline data (Get Spline Data).",
		"category" : "Spatial",
	}

func _to_plane(v : Vector3) -> Vector2:
	match settings.plane:
		CreateSurfaceFromSplineSettings.ePlane.XY:
			return Vector2(v.x, v.y)
		CreateSurfaceFromSplineSettings.ePlane.YZ:
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

## World outlines (tessellated, as Points mode computes them) of spline spatial
## data: a FlowSplineShape or a union of them. null after setError.
func _shape_outlines(shape : FlowSpatial):
	var outlines : Array = []
	for leaf in shape.union_leaves():
		if not (leaf is FlowSplineShape):
			setError("Create Surface From Spline needs spline data; input shape is %s" % shape.get_type_name())
			return null
		var pts : PackedVector3Array = leaf.curve.tessellate(2, 5)
		if pts.size() < 3:
			pts = leaf.curve.get_baked_points()
		for i in range(pts.size()):
			pts[i] = leaf.transform * pts[i]
		outlines.append(pts)
	return outlines

func _execute_outlines(outlines : Array) -> void:
	# Shared by spline spatial data inputs (both modes) and Shape mode.
	var shape_mode : bool = settings.output_mode == CreateSurfaceFromSplineSettings.eOutputMode.Shape
	var positions := PackedVector3Array()
	var sizes := PackedVector3Array()
	var areas := PackedFloat32Array()
	var perimeters := PackedFloat32Array()
	var surfaces : Array = []
	for world_points in outlines:
		if world_points.size() == 0:
			continue
		var aabb := _bounds(world_points)
		positions.append(aabb.position + aabb.size * 0.5)
		sizes.append(aabb.size)
		areas.append(_area(world_points))
		perimeters.append(_perimeter(world_points))
		if shape_mode:
			surfaces.append(FlowPolygonSurface.from_world_points(world_points, settings.plane))
	if shape_mode:
		_emit_shapes(surfaces, areas, perimeters)
		return
	var out := FlowData.Data.new()
	out.addCommonStreams(positions.size())
	var op := out.getVector3Container(FlowData.AttrPosition)
	var osize := out.getVector3Container(FlowData.AttrSize)
	var legacy : bool = settings.legacy_scale_from_extent
	for i in range(positions.size()):
		op[i] = positions[i]
		osize[i] = sizes[i] if legacy else Vector3.ONE
	if not legacy:
		out.setSymmetricBounds(sizes)
	if settings.out_area_attribute.strip_edges() != "":
		out.registerStream(settings.out_area_attribute, areas, FlowData.DataType.Float)
	if settings.out_perimeter_attribute.strip_edges() != "":
		out.registerStream(settings.out_perimeter_attribute, perimeters, FlowData.DataType.Float)
	set_output(0, out)

func execute(_ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, _ctx, "Splines input")
	if in_data == null:
		return
	if in_data.shape != null:
		var outlines = _shape_outlines(in_data.shape)
		if outlines != null:
			_execute_outlines(outlines)
		return
	var stream = in_data.findStream(settings.spline_stream_attribute)
	if stream == null or stream.data_type != FlowData.DataType.NodePath:
		setError("Input must provide a Path3D node stream named '%s'" % settings.spline_stream_attribute)
		return
	if settings.output_mode == CreateSurfaceFromSplineSettings.eOutputMode.Shape:
		var outlines : Array = []
		for node in stream.container:
			var path := node as Path3D
			if path == null or path.curve == null:
				continue
			var local_points := path.curve.tessellate(2, 5)
			if local_points.size() < 3:
				local_points = path.curve.get_baked_points()
			var world_points := PackedVector3Array()
			for p in local_points:
				world_points.append(path.global_transform * p)
			outlines.append(world_points)
		_execute_outlines(outlines)
		return

	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var sizes := PackedVector3Array()
	var areas := PackedFloat32Array()
	var perimeters := PackedFloat32Array()
	var refs : Array = []

	var skipped := 0
	for node in stream.container:
		var path := node as Path3D
		if path == null or path.curve == null:
			skipped += 1
			continue
		var local_points := path.curve.tessellate(2, 5)
		if local_points.size() < 3:
			local_points = path.curve.get_baked_points()
		if local_points.size() == 0:
			skipped += 1
			continue
		var world_points := PackedVector3Array()
		for p in local_points:
			world_points.append(path.global_transform * p)
		var aabb := _bounds(world_points)
		positions.append(aabb.position + aabb.size * 0.5)
		rotations.append(Vector3.ZERO)
		sizes.append(aabb.size)
		areas.append(_area(world_points))
		perimeters.append(_perimeter(world_points))
		if settings.include_spline_ref:
			refs.append(path)

	if skipped > 0:
		push_warning("Create Surface From Spline: %d entries were skipped (null, curve-less or empty Path3D)" % skipped)

	var out := FlowData.Data.new()
	out.addCommonStreams(positions.size())
	var op := out.getVector3Container(FlowData.AttrPosition)
	var orot := out.getVector3Container(FlowData.AttrRotation)
	var osize := out.getVector3Container(FlowData.AttrSize)
	# UE parity: unit scale; the surface AABB extent is recorded as bounds. The
	# opt-in legacy bridge keeps size = extent (old size-as-scale) when requested.
	var legacy : bool = settings.legacy_scale_from_extent
	for i in range(positions.size()):
		op[i] = positions[i]
		orot[i] = rotations[i]
		osize[i] = sizes[i] if legacy else Vector3.ONE
	if not legacy:
		out.setSymmetricBounds(sizes)
	if settings.out_area_attribute.strip_edges() != "":
		out.registerStream(settings.out_area_attribute, areas, FlowData.DataType.Float)
	if settings.out_perimeter_attribute.strip_edges() != "":
		out.registerStream(settings.out_perimeter_attribute, perimeters, FlowData.DataType.Float)
	if settings.include_spline_ref and settings.out_spline_attribute.strip_edges() != "":
		out.registerStream(settings.out_spline_attribute, refs, FlowData.DataType.NodePath)
	set_output(0, out)
