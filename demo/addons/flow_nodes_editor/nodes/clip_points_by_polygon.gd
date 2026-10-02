@tool
extends FlowNodeBase

const ClipPointsByPolygonSettings = preload("res://addons/flow_nodes_editor/nodes/clip_points_by_polygon_settings.gd")

func _init():
	meta_node = {
		"title" : "Clip Points By Polygon",
		"settings" : ClipPointsByPolygonSettings,
		"ins" : [{ "label" : "Points" }, { "label" : "Polygon" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Filters points against one or more Path3D or point-list polygons.\nPoint-list polygons assume the input points are ordered as a single closed polygon;\nopen curves are treated as closed.",
		"category" : "Spatial",
	}

func _to_plane(v : Vector3) -> Vector2:
	match settings.plane:
		ClipPointsByPolygonSettings.ePlane.XY:
			return Vector2(v.x, v.y)
		ClipPointsByPolygonSettings.ePlane.YZ:
			return Vector2(v.y, v.z)
		_:
			return Vector2(v.x, v.z)

func _polygon_from_path(path : Path3D) -> PackedVector2Array:
	var poly := PackedVector2Array()
	if path == null or path.curve == null:
		return poly
	var points := path.curve.tessellate(2, 5)
	if points.size() < 3:
		points = path.curve.get_baked_points()
	for p in points:
		poly.append(_to_plane(path.global_transform * p))
	return poly

func _collect_polygons_from_data(data : FlowData.Data) -> Array:
	var polygons : Array = []
	if data == null:
		return polygons
	var stream = data.findStream(settings.spline_stream_attribute)
	if stream != null and stream.data_type == FlowData.DataType.NodePath:
		for node in stream.container:
			var path := node as Path3D
			var poly := _polygon_from_path(path)
			if poly.size() >= 3:
				polygons.append(poly)
		return polygons
	var positions := data.getVector3Container(FlowData.AttrPosition)
	if positions.size() >= 3:
		var poly := PackedVector2Array()
		for p in positions:
			poly.append(_to_plane(p))
		polygons.append(poly)
	return polygons

func _collect_polygons_from_settings(ctx : FlowData.EvaluationContext) -> Array:
	var polygons : Array = []
	if settings.polygon_node_path == NodePath():
		return polygons
	var root = ctx.owner if ctx.owner else editor_edited_scene_root()
	if root == null:
		return polygons
	var node = root.get_node_or_null(settings.polygon_node_path)
	var path := node as Path3D
	var poly := _polygon_from_path(path)
	if poly.size() >= 3:
		polygons.append(poly)
	return polygons

func _is_inside_any(p : Vector2, polygons : Array) -> bool:
	for poly in polygons:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false

# Editor dirty tracking: with a polygon_node_path the node reads a Path3D from
# the scene, so any scene edit may change its output (polygons wired through
# the Polygon input are covered by the node that scanned them).
func computeSceneFingerprint(ctx : FlowData.EvaluationContext) -> Variant:
	if settings == null or settings.polygon_node_path == NodePath():
		return SCENE_INDEPENDENT
	return null

func execute(ctx : FlowData.EvaluationContext):
	var points : FlowData.Data = require_input(0, ctx, "Points input")
	if points == null:
		return
	# An empty upstream (e.g. a filter that matched nothing) legitimately has no
	# streams yet — pass the empty set through instead of erroring on the missing
	# polygon (mirrors attribute_filter_range's empty-input policy).
	if points.size() == 0:
		set_output(0, points.duplicate())
		return
	var pos := points.getVector3Container(FlowData.AttrPosition)
	if pos.size() != points.size():
		setError("Points input must provide a position stream")
		return

	var polygon_data : FlowData.Data = get_input(1)
	var polygons := _collect_polygons_from_data(polygon_data)
	if polygons.is_empty():
		polygons = _collect_polygons_from_settings(ctx)
	if polygons.is_empty():
		setError("No polygon Path3D or polygon point list found")
		return

	var keep := PackedInt32Array()
	for i in range(pos.size()):
		var inside := _is_inside_any(_to_plane(pos[i]), polygons)
		if inside == settings.keep_inside:
			keep.append(i)
	set_output(0, points.filter(keep))
