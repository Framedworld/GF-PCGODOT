@tool
extends FlowNodeBase

const PointsFromTileMapSettings = preload("res://addons/flow_nodes_editor/nodes/points_from_tilemap_settings.gd")

func _init():
	meta_node = {
		"title" : "Points From TileMap",
		"settings" : PointsFromTileMapSettings,
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"category" : "Sampler",
		"tooltip" : "Generates one point per used TileMapLayer cell (Godot-specific world extraction).\nTileMap positions are in 2D pixels — use Position Scale to convert them to world units so they match Cell Size/Cell Height.",
	}

func _collect_tilemaps(root : Node) -> Array:
	if root == null:
		return []
	var path = settings.tilemap_path.strip_edges()
	if path != "":
		var single = root.get_node_or_null(path)
		if single and single.is_class("TileMapLayer"):
			return [single]
		setError("TileMap path '%s' was not found or is not a TileMapLayer" % path)
		return []

	var group_name = settings.group_name.strip_edges()
	if group_name != "":
		var out : Array = []
		if root.get_tree():
			for n in root.get_tree().get_nodes_in_group(group_name):
				if n and n.is_class("TileMapLayer"):
					out.append(n)
		return out

	var found = root.find_children("*", "TileMapLayer", true, false)
	if found.is_empty() and not root.find_children("*", "TileMap", true, false).is_empty():
		setError("Scene only contains legacy TileMap nodes — this node supports TileMapLayer (Godot 4.3+) only")
	return found

func _tile_world_position(layer, cell : Vector2i) -> Vector3:
	var local_pos : Vector2 = layer.map_to_local(cell)
	var world_pos : Vector2 = layer.to_global(local_pos) * settings.position_scale
	return Vector3(world_pos.x, settings.height, world_pos.y)

func computeSceneFingerprint(_ctx : FlowData.EvaluationContext) -> Variant:
	var root = _ctx.owner if (_ctx and _ctx.owner) else editor_edited_scene_root()
	if root == null:
		return hashSceneNodesForFingerprint(_ctx, [])
	var layers = filterOutGeneratedNodes(_collect_tilemaps(root))
	var extra := []
	for layer in layers:
		var used_cells = layer.get_used_cells()
		extra.append(used_cells)
		for cell in used_cells:
			extra.append(layer.get_cell_source_id(cell))
			extra.append(layer.get_cell_alternative_tile(cell))
	return hashSceneNodesForFingerprint(_ctx, layers, extra)

func execute(_ctx : FlowData.EvaluationContext):
	# Owner-less runtime evaluation: report it, still emit an empty output.
	reportMissingOwner(_ctx)
	var root = _ctx.owner if (_ctx and _ctx.owner) else editor_edited_scene_root()
	if root == null:
		set_output(0, FlowData.Data.new())
		return

	var layers = _collect_tilemaps(root)
	if layers.is_empty():
		set_output(0, FlowData.Data.new())
		return

	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	var sizes := PackedVector3Array()
	var cells := PackedVector3Array()
	var source_ids := PackedInt32Array()
	var alt_ids := PackedInt32Array()
	var layer_refs : Array = []

	for layer in layers:
		var used_cells = layer.get_used_cells()
		for cell in used_cells:
			var sid = layer.get_cell_source_id(cell)
			if settings.source_id_filter >= 0 and sid != settings.source_id_filter:
				continue
			var aid = layer.get_cell_alternative_tile(cell)
			if settings.alternative_id_filter >= 0 and aid != settings.alternative_id_filter:
				continue

			positions.append(_tile_world_position(layer, cell))
			rotations.append(Vector3.ZERO)
			sizes.append(Vector3(settings.cell_size.x, settings.cell_height, settings.cell_size.y))
			cells.append(Vector3(cell.x, 0.0, cell.y))
			if settings.include_tile_ids:
				source_ids.append(sid)
				alt_ids.append(aid)
			if settings.include_layer_ref:
				layer_refs.append(layer)

	var out := FlowData.Data.new()
	out.addCommonStreams(positions.size())
	var op = out.getVector3Container(FlowData.AttrPosition)
	var orot = out.getVector3Container(FlowData.AttrRotation)
	var osize = out.getVector3Container(FlowData.AttrSize)
	for i in range(positions.size()):
		op[i] = positions[i]
		orot[i] = rotations[i]
		osize[i] = sizes[i]

	if settings.out_cell_attribute.strip_edges() != "":
		out.registerStream(settings.out_cell_attribute, cells, FlowData.DataType.Vector)
	if settings.include_tile_ids:
		if settings.out_source_id_attribute.strip_edges() != "":
			out.registerStream(settings.out_source_id_attribute, source_ids, FlowData.DataType.Int)
		if settings.out_alternative_id_attribute.strip_edges() != "":
			out.registerStream(settings.out_alternative_id_attribute, alt_ids, FlowData.DataType.Int)
	if settings.include_layer_ref and settings.out_layer_attribute.strip_edges() != "":
		out.registerStream(settings.out_layer_attribute, layer_refs, FlowData.DataType.NodePath)

	set_output(0, out)
