@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Spawn Scenes",
		"settings" : SpawnScenesNodeSettings,
		"aliases" : ["Spawn Actor", "Scene Spawner"],
		"category" : "Spawner",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"is_final" : true,
		"tooltip" : "Similar to spawn meshes but a full scene is instantiated on each node.\nA set of properties can be transfered from the nodes to each instanced scene.\nproperty_overrides maps point attributes to (nested) property paths of the instance.",
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

func _build_variant_weights() -> Array[float]:
	var variants = settings.scene_variants
	if variants.is_empty():
		return []
	var weights : Array[float] = []
	weights.resize(variants.size())
	for i in range(variants.size()):
		var w = 1.0
		if i < settings.scene_variant_weights.size():
			w = maxf(0.0, float(settings.scene_variant_weights[i]))
		weights[i] = w
	var total = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		for i in range(weights.size()):
			weights[i] = 1.0
	return weights

func _pick_weighted_variant(weights : Array[float], rnd : float) -> int:
	var total = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var t = rnd * total
	var accum = 0.0
	for i in range(weights.size()):
		accum += weights[i]
		if t <= accum:
			return i
	return weights.size() - 1

func _resolve_scene_for_point(idx : int, scenes_stream, variants : Array[PackedScene], variant_weights : Array[float], selector_stream, point_seeds):
	if scenes_stream != null:
		var read_idx = FlowData.bcast_idx( scenes_stream.size(), idx )
		var scene_val = scenes_stream[read_idx] as PackedScene
		if scene_val != null:
			return scene_val
	if variants.is_empty():
		return settings.scene
	if settings.randomize_scene_variants:
		var local_rng := RandomNumberGenerator.new()
		if point_seeds != null:
			# Per-point seed stream present: derive the pick from it (UE parity)
			local_rng.seed = int(point_seeds[idx]) ^ effective_seed()
		else:
			local_rng.seed = effective_seed() + idx * 1237
		var ridx = _pick_weighted_variant(variant_weights, local_rng.randf())
		return variants[ridx]
	if selector_stream != null:
		var read_idx = FlowData.bcast_idx( selector_stream.container.size(), idx )
		if selector_stream.data_type == FlowData.DataType.Int:
			var int_idx = clampi(int(selector_stream.container[read_idx]), 0, variants.size() - 1)
			return variants[int_idx]
		var selector_value = float(selector_stream.container[read_idx])
		var sval = clampf(selector_value, 0.0, 1.0)
		var ridx = _pick_weighted_variant(variant_weights, sval)
		return variants[ridx]
	return variants[idx % variants.size()]
		
func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx )
	if in_data == null:
		return
	if handleMissingOwner( ctx ):
		return

	if in_data.size() == 0:
		set_output(0, in_data)
		return

	var scenes = null
	if settings.scene_attribute:
		var stream_scenes = in_data.findStream( settings.scene_attribute )
		if stream_scenes == null:
			setError( "Input does not have attribute '%s'" % settings.scene_attribute)
			return
		if stream_scenes.data_type != FlowData.DataType.Resource:
			setError( "Attribute '%s' should be of type Resource Packed Scene" % settings.scene_attribute)
			return
		scenes = stream_scenes.container
		if scenes.size() != in_data.size() and scenes.size() != 1:
			setError("Scene attribute '%s' must have %d values or 1 value (got %d)" % [settings.scene_attribute, in_data.size(), scenes.size()])
			return

	var selector_stream = null
	if settings.scene_selector_attribute.strip_edges() != "":
		selector_stream = in_data.findStream(settings.scene_selector_attribute)
		if selector_stream != null and selector_stream.data_type != FlowData.DataType.Int and selector_stream.data_type != FlowData.DataType.Float:
			setError("Scene selector attribute '%s' must be Int or Float" % settings.scene_selector_attribute)
			return
		if selector_stream != null:
			var sel_size = selector_stream.container.size()
			if sel_size != in_data.size() and sel_size != 1:
				setError("Scene selector attribute '%s' must have %d values or 1 value (got %d)" % [settings.scene_selector_attribute, in_data.size(), sel_size])
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
		if is_ownerless_preview(ctx):
			set_output(0, in_data)
			return
		setError("Missing required streams %s/%s" % [ FlowData.AttrPosition, FlowData.AttrRotation ])
		return
		
	var spawn_parent = _resolve_spawn_parent(root)
	var in_size = in_data.size()
	# Optional per-point / per-data parents (Create Target Node). Empty = today.
	var point_parents : Array = []
	if settings.spawn_parent_attribute.strip_edges() != "":
		var parents_res := FlowSpawnUtil.resolve_attribute_parents( self, in_data, settings.spawn_parent_attribute, root, spawn_parent )
		if not parents_res.ok:
			return
		point_parents = parents_res.parents
	var clear_parents : Array = FlowSpawnUtil.unique_parents( point_parents + previousContentParents( ctx ), spawn_parent )
	var pool : FlowSpawnPool = null
	if settings.clear_previous_instances:
		if settings.reuse_instances:
			pool = FlowSpawnPool.collect( self, clear_parents, ctx )
		else:
			for parent in clear_parents:
				removeInstancedNodes( parent, ctx )

	# Find who is going to be the owner of the new nodes
	# (shoulw be the parent root of the scene, not the parent)
	var node_tree = root.get_tree()
	if not node_tree:
		_release_pool( pool )
		setError("Invalid current scene")
		return
		
	var scene_root = node_tree.current_scene
	if not root.get_tree():
		setError("Invalid scene_root scene")
		return
		
	var owner_of_spawned_nodes : Node
	if scene_root:
		owner_of_spawned_nodes = scene_root
	else:
		# Fallback: find the top-most node with an owner
		owner_of_spawned_nodes = root
		while owner_of_spawned_nodes.get_parent() and owner_of_spawned_nodes.owner:
			owner_of_spawned_nodes = owner_of_spawned_nodes.get_parent()

	var streams_to_assign = []
	for node_property in settings.assign_attributes:
		var stream_name = settings.assign_attributes[ node_property ]
		var stream = in_data.findStream( stream_name )
		if stream:
			streams_to_assign.append( { "node_property" : node_property, "container" : stream.container } )

	var variants : Array[PackedScene] = []
	for v in settings.scene_variants:
		if v != null:
			variants.append(v)
	if variants.is_empty() and settings.scene != null:
		variants = [settings.scene]
	var variant_weights = _build_variant_weights()
	if variants.is_empty() and scenes == null:
		_release_pool( pool )
		setError("No scene source configured. Provide scene, scene_attribute, or scene_variants.")
		return

	var overrides : Array = []
	if not settings.property_overrides.is_empty():
		var prepared = FlowSpawnUtil.prepare_property_overrides( self, in_data, settings.property_overrides )
		if prepared == null:
			_release_pool( pool )
			return
		overrides = prepared
	var override_problems := {}

	# Per-point seed stream (UE parity): present when a sampler emitted AttrSeed
	var point_seeds = null
	var seed_stream = in_data.findStream( FlowData.AttrSeed )
	if seed_stream != null and seed_stream.data_type == FlowData.DataType.Int and seed_stream.container.size() == in_size:
		point_seeds = seed_stream.container

	# Collect which indices use the same by resource type
	for idx in range( in_size ):
		var packed_scene : PackedScene = _resolve_scene_for_point(idx, scenes, variants, variant_weights, selector_stream, point_seeds)
		if not packed_scene:
			continue
		var parent : Node3D = spawn_parent if point_parents.is_empty() else point_parents[idx]
		var pool_key := ""
		var node : Node3D = null
		if pool != null:
			pool_key = "scene|" + FlowSpawnPool.resource_key( packed_scene )
			node = pool.take( pool_key, parent ) as Node3D
		var reused := node != null
		if not reused:
			var created = packed_scene.instantiate()
			node = created as Node3D
			if node == null:
				if created:
					created.queue_free()
				_release_pool( pool )
				setError("Instanced scene is not a Node3D at index %d" % idx)
				return
		node.transform = transforms.atIndex( idx )
		FlowSpawnUtil.set_spawned_name( node, "Scene_%04d" % idx )
		if reused:
			FlowSpawnUtil.claim_spawned( self, node, owner_of_spawned_nodes, ctx )
		else:
			FlowSpawnUtil.add_spawned_child( parent, node )
			assignSpawnOwner( node, owner_of_spawned_nodes, ctx )
			tagFlowContent( node, ctx )
			if pool != null:
				FlowSpawnPool.tag( node, pool_key )
		var assign_target : Node = node
		var assign_target_path = settings.assign_target_path.strip_edges()
		if assign_target_path != "":
			var target_node = node.get_node_or_null(assign_target_path)
			if target_node:
				assign_target = target_node
		for s in streams_to_assign:
			var read_idx = idx if s.container.size() > 1 else 0
			assign_target.set( s.node_property, s.container[ read_idx ])
		if not overrides.is_empty():
			FlowSpawnUtil.apply_property_overrides( node, overrides, idx, override_problems )
	_release_pool( pool )
	FlowSpawnUtil.report_override_problems( self, override_problems )

	if Engine.is_editor_hint():
		editor_mark_scene_unsaved()

	set_output(0, in_data)

func _release_pool( pool : FlowSpawnPool ) -> void:
	if pool != null:
		pool.release_unused()
