@tool
extends FlowNodeBase

const PointFromPlayerPawnSettings = preload("res://addons/flow_nodes_editor/nodes/point_from_player_pawn_settings.gd")

func _init():
	meta_node = {
		"title" : "Point From Player",
		"settings" : PointFromPlayerPawnSettings,
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["sample player", "player character", "player pawn", "source point", "scene source"],
		"tooltip" : "Emits one point from a Godot player/source Node3D. Resolves by explicit path, group, class/name, then optional camera fallback.",
	}

func _scene_root(ctx : FlowData.EvaluationContext) -> Node:
	if Engine.is_editor_hint():
		return EditorInterface.get_edited_scene_root()
	if ctx.owner and ctx.owner.get_tree():
		return ctx.owner.get_tree().current_scene
	return null

func _find_first_node3d(nodes : Array) -> Node3D:
	for node in nodes:
		if node is Node3D:
			return node
	return null

func _find_first_camera(root : Node) -> Node3D:
	if root == null:
		return null
	if root.get_viewport():
		var camera := root.get_viewport().get_camera_3d()
		if camera:
			return camera
	return _find_first_node3d(root.find_children("*", "Camera3D", true, false))

func _find_player(root : Node) -> Node3D:
	if root == null:
		return null
	if settings.player_node_path != NodePath():
		var explicit = root.get_node_or_null(settings.player_node_path)
		if explicit is Node3D:
			return explicit
	var group : String = settings.group_name.strip_edges()
	if group != "" and root.get_tree():
		var grouped := _find_first_node3d(root.get_tree().get_nodes_in_group(group))
		if grouped:
			return grouped
	var filter : String = settings.class_name_filter.strip_edges()
	var pattern : String = settings.name_pattern if settings.name_pattern.strip_edges() != "" else "*"
	var candidates = root.find_children(pattern, filter, true, false) if filter != "" else root.find_children(pattern, "Node3D", true, false)
	var matched := _find_first_node3d(candidates)
	if matched:
		return matched
	if settings.fallback_to_current_camera:
		var camera := _find_first_camera(root)
		if camera:
			return camera
	return root as Node3D

func execute(ctx : FlowData.EvaluationContext):
	var player := _find_player(_scene_root(ctx))
	if player == null:
		setError("No player/source Node3D found")
		set_output(0, FlowData.Data.new())
		return
	var out := FlowData.Data.new()
	out.addCommonStreams(1)
	out.getVector3Container(FlowData.AttrPosition)[0] = player.global_position
	out.getVector3Container(FlowData.AttrRotation)[0] = FlowData.basisToEuler(player.global_transform.basis)
	out.getVector3Container(FlowData.AttrSize)[0] = player.scale
	if settings.include_node_ref and settings.node_attribute.strip_edges() != "":
		out.registerStream(settings.node_attribute, [player], FlowData.DataType.NodePath)
	set_output(0, out)
