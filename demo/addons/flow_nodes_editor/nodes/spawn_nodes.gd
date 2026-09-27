@tool
extends FlowNodeBase

const SpawnNodesNodeSettings = preload("res://addons/flow_nodes_editor/nodes/spawn_nodes_settings.gd")

func _init():
	meta_node = {
		"title" : "Spawn Nodes",
		"settings" : SpawnNodesNodeSettings,
		"aliases" : ["Spawn Actor (Nodes)"],
		"category" : "Spawner",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"is_final" : true,
		"tooltip" : "Dynamically instantiates a raw Godot class or custom script node on each point.\nProperties can be transferred from point attributes to node properties.",
	}

func removeInstancedNodes( root : Node3D, ctx : FlowData.EvaluationContext = null ):
	removeOwnFlowContent( root, ctx )

func _resolve_spawn_parent(root : Node3D) -> Node3D:
	var path = settings.spawn_parent_path.strip_edges()
	if path == "":
		return root
	var n = root.get_node_or_null(path)
	if n is Node3D:
		return n
	setError("Spawn parent path '%s' is invalid or not a Node3D" % path)
	return root

func _build_trimmed_variants() -> Array[String]:
	var variants : Array[String] = []
	for entry in settings.node_class_variants:
		var trimmed = String(entry).strip_edges()
		if trimmed != "":
			variants.append(trimmed)
	return variants

func _resolve_class_name_for_point(idx : int, variants : Array[String], selector_stream, point_seeds) -> String:
	if variants.is_empty():
		return settings.node_class.strip_edges()

	if settings.randomize_node_variants:
		var rng_local := RandomNumberGenerator.new()
		if point_seeds != null:
			# Per-point seed stream present: derive the pick from it (UE parity)
			rng_local.seed = int(point_seeds[idx]) ^ effective_seed()
		else:
			rng_local.seed = effective_seed() + idx * 811
		return variants[rng_local.randi_range(0, variants.size() - 1)]

	if selector_stream != null:
		var read_idx = FlowData.bcast_idx( selector_stream.container.size(), idx )
		var val = int(absf(float(selector_stream.container[read_idx])))
		return variants[val % variants.size()]

	return variants[idx % variants.size()]

func _instantiate_class_or_script(class_name_to_spawn : String) -> Node:
	if class_name_to_spawn == "":
		return null
	var is_script_path = class_name_to_spawn.begins_with("res://") and class_name_to_spawn.ends_with(".gd")
	if is_script_path:
		var script = load(class_name_to_spawn)
		if script == null:
			return null
		return script.new()
	if not ClassDB.class_exists(class_name_to_spawn):
		return null
	if not ClassDB.can_instantiate(class_name_to_spawn):
		return null
	return ClassDB.instantiate(class_name_to_spawn)

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx )
	if in_data == null:
		return
	if handleMissingOwner( ctx ):
		return

	if in_data.size() == 0:
		set_output(0, in_data)
		return

	var root = ctx.owner
	if not root:
		if Engine.is_editor_hint():
			set_output(0, in_data)
			return
		setError("Failed to find root")
		return

	var transforms = in_data.getTransformsStream()
	if transforms == null:
		setError("Missing required transforms stream")
		return
		
	var spawn_parent = _resolve_spawn_parent(root)
	var in_size = in_data.size()
	if settings.clear_previous_instances:
		removeInstancedNodes( spawn_parent, ctx )

	# Find who is going to be the owner of the new nodes
	var node_tree = root.get_tree()
	if not node_tree:
		setError("Invalid current scene")
		return

	var scene_root = node_tree.current_scene

	var owner_of_spawned_nodes : Node
	if scene_root:
		owner_of_spawned_nodes = scene_root
	else:
		owner_of_spawned_nodes = root
		while owner_of_spawned_nodes.get_parent() and owner_of_spawned_nodes.owner:
			owner_of_spawned_nodes = owner_of_spawned_nodes.get_parent()

	var selector_stream = null
	if settings.node_selector_attribute.strip_edges() != "":
		selector_stream = in_data.findStream(settings.node_selector_attribute)
		if selector_stream != null and selector_stream.data_type != FlowData.DataType.Int and selector_stream.data_type != FlowData.DataType.Float:
			setError("Node selector attribute '%s' must be Int or Float" % settings.node_selector_attribute)
			return
		if selector_stream != null:
			var sel_size = selector_stream.container.size()
			if sel_size != in_data.size() and sel_size != 1:
				setError("Node selector attribute '%s' must have %d values or 1 value (got %d)" % [settings.node_selector_attribute, in_data.size(), sel_size])
				return

	# Setup property mapping streams
	var streams_to_assign = []
	for node_property in settings.assign_attributes:
		var stream_name = settings.assign_attributes[ node_property ]
		var stream = in_data.findStream( stream_name )
		if stream:
			var s_size = stream.container.size()
			if s_size != in_size and s_size != 1:
				setError("Assign attribute '%s' must have %d values or 1 value (got %d)" % [stream_name, in_size, s_size])
				return
			streams_to_assign.append( { "node_property" : node_property, "container" : stream.container } )

	# Per-point seed stream (UE parity): when present, randomized variant picks
	# derive from it instead of the index-based fallback
	var point_seeds = in_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
	if point_seeds != null and point_seeds.size() != in_size:
		point_seeds = null

	var variants : Array[String] = _build_trimmed_variants()

	# Spawn nodes
	for idx in range( in_size ):
		var class_name_to_spawn = _resolve_class_name_for_point(idx, variants, selector_stream, point_seeds)
		var node : Node = _instantiate_class_or_script(class_name_to_spawn)

		if not node:
			setError("Failed to instantiate '%s'" % class_name_to_spawn)
			return

		var node3d = node as Node3D
		if not node3d:
			node.queue_free()
			setError("Instantiated node '%s' is not a Node3D subclass" % class_name_to_spawn)
			return

		node3d.transform = transforms.atIndex( idx )
		node3d.name = "%s_%04d" % [class_name_to_spawn.get_file().get_basename(), idx]
		spawn_parent.add_child( node3d )
		assignSpawnOwner( node3d, owner_of_spawned_nodes, ctx )
		node3d.set_meta("flow_owner", flowOwnerMeta( ctx ) )
		var assign_target : Node = node3d
		var assign_target_path = settings.assign_target_path.strip_edges()
		if assign_target_path != "":
			var target_node = node3d.get_node_or_null(assign_target_path)
			if target_node:
				assign_target = target_node

		# Assign mapped attributes to properties
		for s in streams_to_assign:
			var read_idx = FlowData.bcast_idx( s.container.size(), idx )
			assign_target.set( s.node_property, s.container[ read_idx ])
	
	if Engine.is_editor_hint():
		editor_mark_scene_unsaved()
	set_output(0, in_data)
