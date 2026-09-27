@tool
extends FlowNodeBase

# UE PCG parity: Projection — projects points onto physics geometry along a
# direction, optionally aligning rotation to the hit normal. Writes the hit
# normal into the 'normal' stream.

func _init():
	meta_node = {
		"title" : "Projection",
		"settings" : ProjectionNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Projection"],
		"category" : "Spatial",
		"queries_physics" : true,
		"tooltip" : "Projects points along a direction onto colliders.\nSnaps point positions, writes the hit normal, and optionally aligns rotations to it.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	if handleMissingOwner(ctx):
		return

	var root = ctx.owner if (ctx and ctx.owner) else editor_edited_scene_root()
	if not root:
		setError("Cannot project points: no valid scene root context found")
		return

	var world = root.get_world_3d()
	if not world:
		setError("Cannot project points: no World3D found")
		return

	var space_state = world.direct_space_state

	var out_data : FlowData.Data = in_data.duplicate()
	var in_size := in_data.size()
	if in_size == 0:
		set_output(0, out_data)
		return

	var pos_stream := in_data.getVector3Container(FlowData.AttrPosition)
	if pos_stream.size() != in_size:
		setError("Input data is missing the 'position' stream")
		return

	var rot_stream : PackedVector3Array
	if in_data.hasStreamOfType(FlowData.AttrRotation, FlowData.DataType.Vector):
		rot_stream = in_data.getVector3Container(FlowData.AttrRotation)
	else:
		rot_stream = PackedVector3Array()
		rot_stream.resize(in_size)
		rot_stream.fill(Vector3.ZERO)

	var in_normals := PackedVector3Array()
	if in_data.hasStreamOfType(FlowData.AttrNormal, FlowData.DataType.Vector):
		in_normals = in_data.getVector3Container(FlowData.AttrNormal)

	var out_pos := PackedVector3Array()
	var out_rot := PackedVector3Array()
	var out_nrm := PackedVector3Array()
	out_pos.resize(in_size)
	out_rot.resize(in_size)
	out_nrm.resize(in_size)

	var valid_indices := PackedInt32Array()

	var query := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO)
	query.collision_mask = settings.collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var dir : Vector3 = settings.direction.normalized()
	if dir.length_squared() < 0.1:
		dir = Vector3(0, -1, 0)

	var align_to_normal : bool = settings.align_to_normal
	var discard_misses : bool = settings.discard_misses
	var ray_length : float = getSettingValue(ctx, "ray_length", 1000.0)

	for i in range(in_size):
		var p := pos_stream[i]
		var rot_idx := FlowData.bcast_idx(rot_stream.size(), i)
		query.from = p - dir * 1.0 # Slight backwards offset to avoid starting inside the surface
		query.to = p + dir * ray_length

		var result = space_state.intersect_ray(query)
		if result:
			out_pos[i] = result.position
			out_nrm[i] = result.normal
			if align_to_normal:
				# Align the point's up vector (Y) to the hit normal — degrees, like every rotation stream.
				out_rot[i] = FlowData.basisToEuler(FlowData.basisFromNormal(result.normal, Vector3.UP, "y"))
			else:
				out_rot[i] = rot_stream[rot_idx]
			valid_indices.append(i)
		else:
			out_pos[i] = p
			out_rot[i] = rot_stream[rot_idx]
			if in_normals.size() > 0:
				out_nrm[i] = in_normals[FlowData.bcast_idx(in_normals.size(), i)]
			else:
				out_nrm[i] = FlowData.eulerToBasis(rot_stream[rot_idx]).y
			if not discard_misses:
				valid_indices.append(i)

	out_data.registerStream(FlowData.AttrPosition, out_pos, FlowData.DataType.Vector)
	out_data.registerStream(FlowData.AttrRotation, out_rot, FlowData.DataType.Vector)
	out_data.registerStream(FlowData.AttrNormal, out_nrm, FlowData.DataType.Vector)

	# When discarding misses, keep only the points that hit something
	if discard_misses and valid_indices.size() < in_size:
		out_data = out_data.filter(valid_indices)

	set_output(0, out_data)
