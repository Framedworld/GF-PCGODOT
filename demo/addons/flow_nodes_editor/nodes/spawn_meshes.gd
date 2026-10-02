@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Spawn Meshes",
		"settings" : SpawnMeshesNodeSettings,
		"aliases" : ["Static Mesh Spawner"],
		"category" : "Spawner",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"is_final" : true,
		"tooltip" : "Spawns a Mesh Instance on each point, applying the translation, rotation and scale.\nThe instanced mesh can be specified by point if a stream contains the mesh resource to be spawned.\nThe generates meshes are MultiMeshInstance3D.\nMesh entries (FlowMeshSpawnEntry) add per-entry weight, material, shadows, visibility range, layers, GI, custom data and collision.",
	}

func removeInstancedComponents( root : Node3D, ctx : FlowData.EvaluationContext = null ):
	removeOwnFlowContent( root, ctx, func( child ): return child is MultiMeshInstance3D )

func spawnNode( class_to_spawn, ctx : FlowData.EvaluationContext = null ):
	var new_node = class_to_spawn.new()
	tagFlowContent( new_node, ctx )
	return new_node

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
	var variants = settings.mesh_variants
	if variants.is_empty():
		return []
	var weights : Array[float] = []
	weights.resize(variants.size())
	for i in range(variants.size()):
		var w = 1.0
		if i < settings.mesh_variant_weights.size():
			w = maxf(0.0, float(settings.mesh_variant_weights[i]))
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

func _resolve_mesh_for_point(idx : int, meshes_stream, variants : Array[Mesh], variant_weights : Array[float], selector_stream, point_seeds) -> Mesh:
	if meshes_stream != null:
		var read_idx = FlowData.bcast_idx( meshes_stream.size(), idx )
		var m = meshes_stream[read_idx] as Mesh
		if m != null:
			return m

	if variants.is_empty():
		return settings.mesh

	if settings.randomize_mesh_variants:
		var local_rng := RandomNumberGenerator.new()
		if point_seeds != null:
			# Per-point seed stream present: derive the pick from it (UE parity)
			local_rng.seed = int(point_seeds[idx]) ^ effective_seed()
		else:
			local_rng.seed = effective_seed() + idx * 19937
		var ridx = _pick_weighted_variant(variant_weights, local_rng.randf())
		return variants[ridx]

	if selector_stream != null:
		var read_idx = FlowData.bcast_idx( selector_stream.container.size(), idx )
		if selector_stream.data_type == FlowData.DataType.Int:
			# Int selectors are direct variant indices (consistent with Spawn Scenes)
			var int_idx = clampi(int(selector_stream.container[read_idx]), 0, variants.size() - 1)
			return variants[int_idx]
		var selector_value = float(selector_stream.container[read_idx])
		var sval = clampf(selector_value, 0.0, 1.0)
		var ridx = _pick_weighted_variant(variant_weights, sval)
		return variants[ridx]

	var cycle_idx = idx % variants.size()
	return variants[cycle_idx]

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx )
	if in_data == null:
		return
	if handleMissingOwner( ctx ):
		return

	if in_data.size() == 0:
		set_output(0, in_data)
		return

	if not settings.mesh_entries.is_empty():
		_execute_entries( ctx, in_data )
		return

	var meshes = null
	if settings.mesh_attribute:
		var stream_meshes = in_data.findStream( settings.mesh_attribute )
		if stream_meshes == null:
			setError( "Input does not have attribute '%s'" % settings.mesh_attribute)
			return
		if stream_meshes.data_type != FlowData.DataType.Resource:
			setError( "Attribute '%s' should be of type Resource" % settings.mesh_attribute)
			return
		meshes = stream_meshes.container
		if meshes.size() != in_data.size() and meshes.size() != 1:
			setError("Mesh attribute '%s' must have %d values or 1 value (got %d)" % [settings.mesh_attribute, in_data.size(), meshes.size()])
			return

	var selector_stream = null
	if settings.mesh_selector_attribute.strip_edges() != "":
		selector_stream = in_data.findStream(settings.mesh_selector_attribute)
		if selector_stream != null and selector_stream.data_type != FlowData.DataType.Int and selector_stream.data_type != FlowData.DataType.Float:
			setError("Mesh selector attribute '%s' must be Int or Float" % settings.mesh_selector_attribute)
			return
		if selector_stream != null:
			var sel_size = selector_stream.container.size()
			if sel_size != in_data.size() and sel_size != 1:
				setError("Mesh selector attribute '%s' must have %d values or 1 value (got %d)" % [settings.mesh_selector_attribute, in_data.size(), sel_size])
				return

	var variants : Array[Mesh] = []
	for v in settings.mesh_variants:
		if v != null:
			variants.append(v)
	var variant_weights = _build_variant_weights()
	
	var transforms := in_data.getTransformsStream()
	if transforms == null:
		setError("Missing transforms information")
		return

	var root = ctx.owner
	if not root:
		if Engine.is_editor_hint():
			set_output(0, in_data)
			return
		setError("Failed to find root")
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
	var clear_parents : Array = FlowSpawnUtil.unique_parents( point_parents, spawn_parent )
	var pool : FlowSpawnPool = null
	if settings.clear_previous_instances:
		if settings.reuse_instances:
			pool = FlowSpawnPool.collect( self, clear_parents, ctx, func( child ): return child is MultiMeshInstance3D )
		else:
			for parent in clear_parents:
				removeInstancedComponents( parent, ctx )

	# Find who is going to be the owner of the new nodes
	# (should be the parent root of the scene, not the parent)
	var node_tree = root.get_tree()
	if not node_tree:
		_release_pool( pool )
		setError("Invalid current scene")
		return

	var scene_root = node_tree.current_scene

	var owner_of_mmis : Node
	if scene_root:
		owner_of_mmis = scene_root
	else:
		# Fallback: find the top-most node with an owner
		owner_of_mmis = root
		while owner_of_mmis.get_parent() and owner_of_mmis.owner:
			owner_of_mmis = owner_of_mmis.get_parent()

	var default_mesh = getSettingValue(ctx, "mesh")
	if default_mesh != null and variants.is_empty():
		variants = [default_mesh]
	if variants.is_empty() and meshes == null:
		_release_pool( pool )
		setError("No mesh source configured. Provide mesh, mesh_attribute, or mesh_variants.")
		return

	# Per-point seed stream (UE parity): when present, randomized variant picks
	# derive from it instead of the index-based fallback
	var point_seeds = in_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
	if point_seeds != null and point_seeds.size() != in_size:
		point_seeds = null

	# Collect which indices use the same resource.
	var mmis := {}
	for idx in range( in_size ):
		var mesh = _resolve_mesh_for_point(idx, meshes, variants, variant_weights, selector_stream, point_seeds)
		if mesh == null:
			continue
		var key = mesh if point_parents.is_empty() else [ mesh, point_parents[idx] ]
		var mmi = mmis.get( key, null )
		if mmi == null:
			mmis[ key ] = []
		mmis[ key ].append( idx )
	
	var color_stream = in_data.findStream(settings.color_attribute)
	var has_colors = settings.use_vertex_colors and color_stream != null and color_stream.data_type == FlowData.DataType.Color
	if has_colors:
		var color_size = color_stream.container.size()
		if color_size != in_size and color_size != 1:
			_release_pool( pool )
			setError("Color attribute '%s' must have %d values or 1 value (got %d)" % [settings.color_attribute, in_size, color_size])
			return

	for group_key in mmis.keys():
		var res = group_key if point_parents.is_empty() else group_key[0]
		var group_parent : Node3D = spawn_parent if point_parents.is_empty() else group_key[1]
		var pool_key := ""
		var mmi : MultiMeshInstance3D = null
		if pool != null:
			pool_key = "mesh|%s|%d" % [ FlowSpawnPool.resource_key( res ), int( has_colors ) ]
			mmi = pool.take( pool_key, group_parent ) as MultiMeshInstance3D
		var reused := mmi != null
		if not reused:
			mmi = spawnNode( MultiMeshInstance3D, ctx )
		
		var multimesh := MultiMesh.new()
		if reused and mmi.multimesh != null:
			multimesh = mmi.multimesh
			multimesh.instance_count = 0
			multimesh.use_colors = false
		multimesh.mesh = res
		multimesh.transform_format = MultiMesh.TransformFormat.TRANSFORM_3D
		if has_colors:
			multimesh.use_colors = true
		var ids = mmis[group_key]
		multimesh.instance_count = ids.size()
		
		# We could also create a large buffer and perform a single update
		var idx := 0
		for id in ids:
			multimesh.set_instance_transform( idx, transforms.atIndex( id ) )
			if has_colors:
				var cidx = FlowData.bcast_idx( color_stream.container.size(), id )
				multimesh.set_instance_color( idx, color_stream.container[cidx] )
			idx += 1
			
		mmi.multimesh = multimesh
		if reused:
			mmi.material_override = null
		if has_colors:
			var mat = StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = 0.3
			mmi.material_override = mat
		if reused:
			FlowSpawnUtil.claim_spawned( self, mmi, owner_of_mmis, ctx )
			continue
		group_parent.add_child( mmi )
		assignSpawnOwner( mmi, owner_of_mmis, ctx )
		if pool != null:
			FlowSpawnPool.tag( mmi, pool_key )
	_release_pool( pool )

	if Engine.is_editor_hint():
		editor_mark_scene_unsaved()

	set_output(0, in_data)

func _release_pool( pool : FlowSpawnPool ) -> void:
	if pool != null:
		pool.release_unused()

const _VERTEX_COLOR_ROUGHNESS := 0.3

## Spawn path for settings.mesh_entries (FlowMeshSpawnEntry descriptors).
## Points pick an entry (FlowSpawnUtil.select_entries); points whose entries
## share a group key (FlowSpawnUtil.entry_group_key: mesh, material, shadow,
## visibility range, layers, GI, custom data and collision settings) and spawn
## parent go into one MultiMeshInstance3D. Configuration errors are reported
## before anything is cleared.
func _execute_entries( ctx : FlowData.EvaluationContext, in_data : FlowData.Data ) -> void:
	var transforms := in_data.getTransformsStream()
	if transforms == null:
		setError("Missing transforms information")
		return
	var root = ctx.owner
	if not root:
		if Engine.is_editor_hint():
			set_output(0, in_data)
			return
		setError("Failed to find root")
		return
	if root.get_tree() == null:
		setError("Invalid current scene")
		return
	var in_size := in_data.size()
	var entries : Array = settings.mesh_entries
	var picks = FlowSpawnUtil.select_entries( self, in_data, entries, settings.entry_selection, settings.entry_attribute, effective_seed() )
	if picks == null:
		return

	var color_stream = null
	if settings.use_vertex_colors and in_data.container( settings.color_attribute ) != null:
		color_stream = in_data.findStream( settings.color_attribute )
	var has_colors : bool = color_stream != null and color_stream.data_type == FlowData.DataType.Color
	if has_colors:
		var color_size : int = color_stream.container.size()
		if color_size != in_size and color_size != 1:
			setError("Color attribute '%s' must have %d values or 1 value (got %d)" % [settings.color_attribute, in_size, color_size])
			return

	# Per-entry group keys and custom data, validated before anything is cleared.
	var group_keys := {}
	var custom_by_entry := {}
	for e in range( entries.size() ):
		var entry = entries[e]
		if entry == null or entry.mesh == null:
			continue
		group_keys[e] = FlowSpawnUtil.entry_group_key( entry )
		var custom = FlowSpawnUtil.prepare_custom_data( self, in_data, entry.custom_data_attributes )
		if custom == null:
			return
		custom_by_entry[e] = custom

	var spawn_parent = _resolve_spawn_parent(root)
	var point_parents : Array = []
	if settings.spawn_parent_attribute.strip_edges() != "":
		var parents_res := FlowSpawnUtil.resolve_attribute_parents( self, in_data, settings.spawn_parent_attribute, root, spawn_parent )
		if not parents_res.ok:
			return
		point_parents = parents_res.parents
	var scene_owner := FlowSpawnUtil.scene_owner_for( root )

	var clear_parents : Array = FlowSpawnUtil.unique_parents( point_parents, spawn_parent )
	var pool : FlowSpawnPool = null
	if settings.clear_previous_instances:
		if settings.reuse_instances:
			pool = FlowSpawnPool.collect( self, clear_parents, ctx, func( child ): return child is MultiMeshInstance3D )
		else:
			for parent in clear_parents:
				removeInstancedComponents( parent, ctx )

	# group key (entry key + parent) -> { entry index, parent, ids }
	var groups := {}
	for idx in range( in_size ):
		var e : int = picks[idx]
		if e < 0 or not group_keys.has( e ):
			continue
		var parent : Node3D = spawn_parent if point_parents.is_empty() else point_parents[idx]
		var key : Array = group_keys[e] + [ parent ]
		var group = groups.get( key, null )
		if group == null:
			group = { "entry": e, "parent": parent, "ids": PackedInt32Array() }
			groups[key] = group
		group.ids.append( idx )

	var shapes := {}
	for key in groups.keys():
		var group : Dictionary = groups[key]
		var entry = entries[group.entry]
		var parent : Node3D = group.parent
		var ids : PackedInt32Array = group.ids
		var custom : Array = custom_by_entry[group.entry]
		var has_custom := not custom.is_empty()

		var pool_key := ""
		var mmi : MultiMeshInstance3D = null
		if pool != null:
			pool_key = FlowSpawnUtil.group_pool_key( key.slice( 0, key.size() - 1 ), "colors=%d" % int( has_colors ) )
			mmi = pool.take( pool_key, parent ) as MultiMeshInstance3D
		var reused := mmi != null
		if not reused:
			mmi = spawnNode( MultiMeshInstance3D, ctx )

		var multimesh : MultiMesh = mmi.multimesh if reused and mmi.multimesh != null else MultiMesh.new()
		multimesh.instance_count = 0
		multimesh.mesh = entry.mesh
		multimesh.transform_format = MultiMesh.TransformFormat.TRANSFORM_3D
		multimesh.use_colors = has_colors
		multimesh.use_custom_data = has_custom
		multimesh.instance_count = ids.size()
		var local_transforms : Array[Transform3D] = []
		local_transforms.resize( ids.size() )
		for i in range( ids.size() ):
			var id : int = ids[i]
			var xf := transforms.atIndex( id )
			local_transforms[i] = xf
			multimesh.set_instance_transform( i, xf )
			if has_colors:
				multimesh.set_instance_color( i, color_stream.container[ FlowData.bcast_idx( color_stream.container.size(), id ) ] )
			if has_custom:
				multimesh.set_instance_custom_data( i, FlowSpawnUtil.custom_data_at( custom, id ) )
		mmi.multimesh = multimesh

		mmi.material_override = null
		if has_colors and entry.material_override == null:
			var mat = StandardMaterial3D.new()
			mat.vertex_color_use_as_albedo = true
			mat.roughness = _VERTEX_COLOR_ROUGHNESS
			mmi.material_override = mat
		FlowSpawnUtil.apply_render_settings( mmi, entry )

		if reused:
			FlowSpawnUtil.clear_collision( mmi )
			FlowSpawnUtil.claim_spawned( self, mmi, scene_owner, ctx )
		else:
			parent.add_child( mmi )
			assignSpawnOwner( mmi, scene_owner, ctx )
			if pool != null:
				FlowSpawnPool.tag( mmi, pool_key )

		if entry.has_collision():
			var shape_key := [ entry.mesh, int( entry.collision_mode ) ]
			if not shapes.has( shape_key ):
				shapes[shape_key] = FlowSpawnUtil.build_collision_shape( entry.mesh, entry.collision_mode )
			FlowSpawnUtil.build_collision( self, mmi, entry, shapes[shape_key], local_transforms, scene_owner, ctx )
	_release_pool( pool )

	if Engine.is_editor_hint():
		editor_mark_scene_unsaved()
	set_output(0, in_data)
