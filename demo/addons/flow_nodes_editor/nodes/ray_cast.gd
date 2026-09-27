@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Ray Cast",
		"settings" : RayCastNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["World Ray Hit Query", "Raycast"],
		"category" : "Spatial",
		"queries_physics" : true,
		"tooltip" : "Traces a physics ray per point from the point position (the source attribute can be redefined).\n" +
					"The hit position, rotation, normal, distance, collider and hit flag can be stored as attributes.\n" +
					"Filter on the hit attribute (True / 1) to remove the points where the trace failed.\n"
	}

func _resolve_direction_stream(in_data : FlowData.Data, in_size : int):
	if settings.direction_mode != RayCastNodeSettings.eDirectionMode.FromAttribute:
		return null
	var attr_name = settings.direction_attribute.strip_edges()
	if attr_name == "":
		return null
	var stream = in_data.findStream(attr_name)
	if stream == null:
		return null
	if stream.data_type != FlowData.DataType.Vector:
		setError("Direction attribute '%s' must be Vector" % attr_name)
		return null
	var n = stream.container.size()
	if n != in_size and n != 1:
		setError("Direction attribute '%s' must have %d values or 1 value (got %d)" % [attr_name, in_size, n])
		return null
	return stream.container

func _resolve_distance_stream(in_data : FlowData.Data, in_size : int):
	var attr_name = settings.distance_attribute.strip_edges()
	if attr_name == "":
		return null
	var stream = in_data.findStream(attr_name)
	if stream == null:
		setError("Distance attribute '%s' not found" % attr_name)
		return null
	if stream.data_type != FlowData.DataType.Float and stream.data_type != FlowData.DataType.Int:
		setError("Distance attribute '%s' must be Float or Int" % attr_name)
		return null
	var n = stream.container.size()
	if n != in_size and n != 1:
		setError("Distance attribute '%s' must have %d values or 1 value (got %d)" % [attr_name, in_size, n])
		return null
	return stream

func _read_distance(stream, idx : int) -> float:
	if stream == null:
		return settings.max_distance
	var read_idx = idx if stream.container.size() > 1 else 0
	var v = float(stream.container[read_idx])
	return maxf(0.0, v)

func _read_direction(direction_stream, idx : int) -> Vector3:
	if direction_stream == null:
		return settings.dir
	var read_idx = idx if direction_stream.size() > 1 else 0
	var d : Vector3 = direction_stream[read_idx]
	if settings.normalize_direction:
		if d.length_squared() <= 0.0000001:
			return Vector3.ZERO
		return d.normalized()
	return d

func _build_exclude_rids(root : Node) -> Array:
	var excludes : Array = []
	var group_name = settings.exclude_nodes_group.strip_edges()
	if group_name == "":
		return excludes
	var tree = root.get_tree()
	if tree == null:
		return excludes
	for n in tree.get_nodes_in_group(group_name):
		var body = n as CollisionObject3D
		if body:
			excludes.append(body.get_rid())
	return excludes

func execute( _ctx : FlowData.EvaluationContext ):

	var in_data : FlowData.Data = require_input(0, _ctx)
	if in_data == null:
		return
	if handleMissingOwner(_ctx):
		return

	var root = _ctx.owner if (_ctx and _ctx.owner) else (EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null)
	if not root:
		setError("No scene root available to ray cast against")
		return
	if not root.has_method("get_world_3d"):
		setError("Scene root '%s' is not a Node3D — no 3D physics world to ray cast against" % root.name)
		return

	var world = root.get_world_3d()
	if not world:
		setError("Scene root has no 3D world to ray cast against")
		return
	var space_state = world.direct_space_state

	var in_size = in_data.size()
	var out_data : FlowData.Data = in_data.duplicate()
	var ipos = in_data.getContainerChecked( settings.from_attribute, FlowData.DataType.Vector )
	if not ipos:
		setError( "Stream %s of type Vector not found in input data" % settings.from_attribute )
		return
	var source_container : PackedVector3Array = ipos
	var pos_size : int = source_container.size()
	if pos_size != in_size and pos_size != 1:
		setError("Source attribute '%s' must have %d values or 1 value (got %d)" % [settings.from_attribute, in_size, pos_size])
		return
	var direction_stream = _resolve_direction_stream(in_data, in_size)
	if settings.direction_mode == RayCastNodeSettings.eDirectionMode.FromAttribute and direction_stream == null:
		setError("Direction mode is FromAttribute but direction stream is missing or invalid")
		return
	var distance_stream = _resolve_distance_stream(in_data, in_size)
	if settings.distance_attribute.strip_edges() != "" and distance_stream == null:
		return

	var opos : PackedVector3Array
	var orot : PackedVector3Array
	var onormal : PackedVector3Array
	var ohit : PackedByteArray
	var odistance : PackedFloat32Array
	var ocollider : Array = []
	# Assign initial values for the rotation.
	if in_data.hasStreamOfType( FlowData.AttrRotation, FlowData.DataType.Vector ):
		var irot = in_data.getContainerChecked( FlowData.AttrRotation, FlowData.DataType.Vector )
		if irot.size() == 1 and in_size > 1:
			# Broadcast rotation stream — expand it.
			orot.resize( in_size )
			orot.fill( irot[0] )
		else:
			orot.append_array( irot )
	if orot.size() != in_size:
		orot.resize( in_size )
	if pos_size == in_size:
		opos.append_array( ipos )
	else:
		# Broadcast (size-1) source stream — expand so misses keep the source position.
		opos.resize( in_size )
		opos.fill( source_container[0] )
	onormal.resize(in_size)
	ohit.resize( in_size )
	odistance.resize(in_size)
	ocollider.resize(in_size)
	
	var query = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	query.collision_mask = settings.collision_mask
	query.collide_with_bodies = settings.collide_with_bodies
	query.collide_with_areas = settings.collide_with_areas
	query.hit_from_inside = settings.hit_from_inside
	query.exclude = _build_exclude_rids(root)

	for i in range(in_size):
		var d = _read_direction(direction_stream, i)
		var ray_dist = _read_distance(distance_stream, i)
		if ray_dist <= 0.0 or d.length_squared() <= 0.0000001:
			ohit[i] = 0
			odistance[i] = 0.0
			continue
		query.from = source_container[FlowData.bcast_idx(pos_size, i)]
		query.to = query.from + d * ray_dist
		var result : Dictionary = space_state.intersect_ray(query)
		if result:
			opos[i] = result.position
			onormal[i] = result.normal
			ohit[i] = 1
			odistance[i] = query.from.distance_to(result.position)
			ocollider[i] = result.get("collider", null)
		else:
			ohit[i] = 0
			odistance[i] = 0.0
	
	if settings.out_position_attribute:
		out_data.registerStream( settings.out_position_attribute, opos )
	if settings.out_rotation_attribute:
		for i in in_size:
			if ohit[i]:
				orot[i] = FlowData.basisToEuler( FlowData.basisFromNormal( onormal[i] ) ) + Vector3( 90,0,0 )
		out_data.registerStream( settings.out_rotation_attribute, orot )
	if settings.out_normal_attribute:
		out_data.registerStream(settings.out_normal_attribute, onormal, FlowData.DataType.Vector)
	if settings.out_distance_attribute:
		out_data.registerStream(settings.out_distance_attribute, odistance, FlowData.DataType.Float)
	if settings.out_collider_attribute:
		out_data.registerStream(settings.out_collider_attribute, ocollider, FlowData.DataType.NodePath)
	if settings.out_result_attribute:
		out_data.registerStream( settings.out_result_attribute, ohit )
	set_output( 0, out_data )
