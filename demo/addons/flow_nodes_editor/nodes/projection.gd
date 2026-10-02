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
		"tooltip" : "Projects points along a direction onto colliders.\nSnaps point positions, writes the hit normal, and optionally aligns rotations to it.\nSurface mode projects onto surface data (Get Surface Data, composites) instead.",
	}

## Surface mode adds the "Projection Target" input. Physics mode (default)
## keeps today's single input, so saved parameter-port links keep their indices.
func getMeta() -> Dictionary:
	if settings != null and settings.get( "projection_mode" ) == ProjectionNodeSettings.eProjectionMode.Surface:
		meta_node.ins = [{ "label": "In" }, { "label": "Projection Target" }]
	else:
		meta_node.ins = [{ "label": "In" }]
	return meta_node

## Rebuild the ports when the setting that changes them is edited (same
## pattern as sample_points). Guarded with has_method so the element stays valid
## when the port-building code lives on an editor widget.
func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "projection_mode" and has_method( "initFromScript" ):
		call( "initFromScript" )

## Surface target of Surface mode: the target's shape, or a mesh surface built
## from a scan_meshes 'node' stream. null after setError when unusable.
func _target_surface( target ) -> FlowSpatial:
	if not ( target is FlowData.Data ):
		setError( "Projection Target not connected" )
		return null
	if target.shape != null:
		if target.shape.get_kind() != FlowData.Kind.Surface:
			setError( "Projection Target must be surface data; got %s" % target.shape.get_type_name() )
			return null
		return target.shape
	var nodes = target.findStream( "node" )
	if nodes != null:
		var instances := []
		for n in nodes.container:
			if n is MeshInstance3D and is_instance_valid( n ):
				instances.append( n )
		if not instances.is_empty():
			return FlowMeshSurface.from_mesh_instances( instances )
	setError( "Projection Target has no surface data (wire Get Surface Data, a surface composite or Scan Meshes)" )
	return null

## UE Projection onto surface data: each point goes to shape.project(position)
## (vertical hit, nearest point for meshes), takes the hit normal (and rotation
## with align_to_normal) and, with project_density, the surface density. A miss
## (or a hit of density 0) keeps the point unchanged unless discard_misses.
func _execute_surface( ctx : FlowData.EvaluationContext, in_data : FlowData.Data ) -> void:
	var surface := _target_surface( get_optional_input( 1 ) )
	if surface == null:
		return
	var out_data : FlowData.Data = in_data.duplicate()
	var n := in_data.size()
	if n == 0:
		set_output( 0, out_data )
		return
	var pos_stream := in_data.getVector3Container( FlowData.AttrPosition )
	if pos_stream.size() != n:
		setError( "Input data is missing the 'position' stream" )
		return
	var rot_stream := PackedVector3Array()
	if in_data.hasStreamOfType( FlowData.AttrRotation, FlowData.DataType.Vector ):
		rot_stream = in_data.getVector3Container( FlowData.AttrRotation )
	else:
		rot_stream.resize( n )
	var in_normals := PackedVector3Array()
	if in_data.hasStreamOfType( FlowData.AttrNormal, FlowData.DataType.Vector ):
		in_normals = in_data.getVector3Container( FlowData.AttrNormal )
	var dsrc = in_data.getContainerChecked( FlowData.AttrDensity, FlowData.DataType.Float )
	var align : bool = settings.align_to_normal
	var discard : bool = settings.discard_misses
	var with_density : bool = getSettingValue( ctx, "project_density", true )
	var out_pos := PackedVector3Array()
	var out_rot := PackedVector3Array()
	var out_nrm := PackedVector3Array()
	var out_den := PackedFloat32Array()
	out_pos.resize( n )
	out_rot.resize( n )
	out_nrm.resize( n )
	out_den.resize( n )
	var keep := PackedInt32Array()
	for i in range( n ):
		var p := pos_stream[i]
		var rot := rot_stream[FlowData.bcast_idx( rot_stream.size(), i )]
		var d : float = dsrc[FlowData.bcast_idx( dsrc.size(), i )] if dsrc != null and dsrc.size() > 0 else 1.0
		var hit := surface.project( p )
		if not hit.is_empty() and float( hit.get( "density", 1.0 ) ) > 0.0:
			out_pos[i] = hit.position
			out_nrm[i] = hit.normal
			out_rot[i] = FlowData.basisToEuler( FlowData.basisFromNormal( hit.normal, Vector3.UP, "y" ) ) if align else rot
			out_den[i] = d * float( hit.density ) if with_density else d
			keep.append( i )
		else:
			out_pos[i] = p
			out_rot[i] = rot
			out_nrm[i] = in_normals[FlowData.bcast_idx( in_normals.size(), i )] if in_normals.size() > 0 else FlowData.eulerToBasis( rot ).y
			out_den[i] = d
			if not discard:
				keep.append( i )
	out_data.registerStream( FlowData.AttrPosition, out_pos, FlowData.DataType.Vector )
	out_data.registerStream( FlowData.AttrRotation, out_rot, FlowData.DataType.Vector )
	out_data.registerStream( FlowData.AttrNormal, out_nrm, FlowData.DataType.Vector )
	if dsrc != null or with_density:
		out_data.registerStream( FlowData.AttrDensity, out_den, FlowData.DataType.Float )
	if keep.size() < n:
		out_data = out_data.filter( keep )
	set_output( 0, out_data )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	if settings.get( "projection_mode" ) == ProjectionNodeSettings.eProjectionMode.Surface:
		_execute_surface( ctx, in_data )
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
