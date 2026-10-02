@tool
extends FlowNodeBase

const ApplyOnActorSettings = preload("res://addons/flow_nodes_editor/nodes/apply_on_actor_settings.gd")

func _init():
	meta_node = {
		"title" : "Apply On Actor",
		"settings" : ApplyOnActorSettings,
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"is_final" : true,
		"tooltip" : "Applies point attributes and optional transforms onto existing scene nodes.\nWhen target count != point count, targets are reused cyclically (the last write wins).",
		"aliases" : ["Apply On Actor"],
		"category" : "Spawner",
	}

func _scene_root(ctx : FlowData.EvaluationContext) -> Node:
	if ctx.owner and ctx.owner.get_tree():
		return ctx.owner.get_tree().current_scene if ctx.owner.get_tree().current_scene else ctx.owner
	if Engine.is_editor_hint():
		return editor_edited_scene_root()
	return null

func _targets_from_stream(in_data : FlowData.Data) -> Array:
	var stream = in_data.findStream(settings.target_stream_attribute)
	if stream == null:
		return []
	if stream.data_type != FlowData.DataType.NodePath and stream.data_type != FlowData.DataType.NodeMesh:
		setError("Target stream '%s' must contain nodes" % settings.target_stream_attribute)
		return []
	var out : Array = []
	var num_valid := 0
	for value in stream.container:
		if value is Node:
			out.append(value)
			num_valid += 1
		else:
			out.append(null)
	if num_valid == 0 and not stream.container.is_empty():
		setError("Target stream '%s' contains no live Node references" % settings.target_stream_attribute)
		return []
	return out

func _targets_from_scene(root : Node) -> Array:
	if root == null:
		return []
	if settings.target_mode == ApplyOnActorSettings.eTargetMode.NodePath:
		if settings.target_node_path == NodePath():
			return []
		var node = root.get_node_or_null(settings.target_node_path)
		return [node] if node else []
	if settings.target_mode == ApplyOnActorSettings.eTargetMode.Group:
		var group : String = settings.group_name.strip_edges()
		if group == "":
			return []
		return root.get_tree().get_nodes_in_group(group)
	return []

func _resolve_assign_target(node : Node) -> Node:
	if node == null:
		return null
	if settings.target_child_path != NodePath():
		var child = node.get_node_or_null(settings.target_child_path)
		if child:
			return child
	return node

func _apply_transform(node : Node, in_data : FlowData.Data, idx : int) -> void:
	if not settings.apply_transform_to_node3d:
		return
	var node3d := node as Node3D
	if node3d == null:
		return
	var trs = in_data.getTransformsStream()
	if trs == null:
		return
	node3d.global_transform = trs.atIndex(idx)

func execute(ctx : FlowData.EvaluationContext):
	var in_data : FlowData.Data = require_input(0, ctx)
	if in_data == null:
		return
	if handleMissingOwner(ctx):
		return
	var in_size := in_data.size()
	if in_size == 0:
		set_output(0, in_data)
		return

	var root := _scene_root(ctx)
	var targets : Array = _targets_from_stream(in_data) if settings.target_mode == ApplyOnActorSettings.eTargetMode.FromNodeStream else _targets_from_scene(root)
	if targets.is_empty():
		setError("No target nodes found for Apply On Actor")
		return

	var streams_to_assign : Array = []
	for prop_name in settings.assign_attributes.keys():
		var stream_name : String = String(settings.assign_attributes[prop_name]).strip_edges()
		if stream_name == "":
			continue
		var stream = in_data.findStream(stream_name)
		if stream == null:
			continue
		var stream_size : int = stream.container.size()
		if stream_size != in_size and stream_size != 1:
			push_warning("Apply On Actor: stream '%s' has %d values but input has %d points — out-of-range points are skipped" % [stream_name, stream_size, in_size])
		streams_to_assign.append({ "property": String(prop_name), "stream": stream })

	var overrides : Array = []
	if not settings.property_overrides.is_empty():
		var prepared = FlowSpawnUtil.prepare_property_overrides(self, in_data, settings.property_overrides)
		if prepared == null:
			return
		overrides = prepared
	var override_problems := {}

	for i in range(in_size):
		var target_idx : int = i if targets.size() == in_size else i % targets.size()
		var target = _resolve_assign_target(targets[target_idx])
		if target == null:
			continue
		_apply_transform(target, in_data, i)
		for item in streams_to_assign:
			var stream = item.stream
			var read_idx : int = FlowData.bcast_idx(stream.container.size(), i)
			if read_idx < stream.container.size():
				target.set(item.property, stream.container[read_idx])
		# Property overrides resolve from the target actor itself (not
		# target_child_path), like Spawn Scenes resolves from the instance root.
		if not overrides.is_empty() and targets[target_idx] is Node:
			FlowSpawnUtil.apply_property_overrides(targets[target_idx], overrides, i, override_problems, false)
	FlowSpawnUtil.report_override_problems(self, override_problems)

	if Engine.is_editor_hint():
		editor_mark_scene_unsaved()
	set_output(0, in_data)
