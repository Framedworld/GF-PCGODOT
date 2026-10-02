@tool
extends FlowNodeBase

# UE PCG parity: Get Volume Data / Get Primitive Data. Outputs volume spatial
# data (Data.shape, zero points) from CollisionShape3D (directly or under an
# Area3D / physics body), CSG nodes and mesh bounds. Use it as the cutter of a
# Difference, the bound of an Intersection, or sample it with Volume Sampler /
# To Point.

const GetVolumeDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_volume_data_settings.gd")

func _init():
	meta_node = {
		"title" : "Get Volume Data",
		"settings" : GetVolumeDataSettings,
		"aliases" : ["Get Volume Data", "Get Primitive Data", "Volume Data", "PCG Volume"],
		"category" : "Input",
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Volume data from collision shapes (also inside Area3D / bodies), CSG nodes or mesh bounds.\nUse as a Difference cutter, an Intersection bound, or sample it with Volume Sampler / To Point.",
	}

func _accept( n : Node ) -> bool:
	if settings.include_collision_shapes and n is CollisionShape3D and n.shape != null and not n.disabled and not ( n.shape is HeightMapShape3D ):
		return true
	if settings.include_csg and n.is_class( "CSGShape3D" ):
		# Only CSG roots: children are folded into their root's mesh.
		return not n.has_method( "is_root_shape" ) or bool( n.call( "is_root_shape" ) )
	if settings.include_meshes and n is MeshInstance3D and n.mesh != null:
		return true
	return false

func _sources( ctx : FlowData.EvaluationContext ) -> Array:
	var owner_node = ctx.owner if ctx != null else null
	# Group members that are areas / bodies contribute their collision shapes
	# even without `recursive`.
	var found := FlowSpatialSources.collect( owner_node, str( getSettingValue( ctx, "group_name", "" ) ), bool( getSettingValue( ctx, "recursive", true ) ), settings.required_meta_bool, _accept )
	var group_name := str( getSettingValue( ctx, "group_name", "" ) )
	if group_name != "" and settings.include_collision_shapes and owner_node != null and owner_node.is_inside_tree():
		for member in owner_node.get_tree().get_nodes_in_group( group_name ):
			if member is CollisionObject3D:
				for child in member.get_children():
					if child is CollisionShape3D and _accept( child ) and not found.has( child ):
						found.append( child )
	return found

func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	if ctx == null or ctx.owner == null:
		return null
	return FlowSpatialSources.fingerprint( ctx.owner, _sources( ctx ) )

func _emit_empty() -> void:
	var empty := FlowData.Data.new()
	empty.kind = FlowData.Kind.Volume
	set_output( 0, empty )

func execute( ctx : FlowData.EvaluationContext ):
	if reportMissingOwner( ctx ) or ctx == null or ctx.owner == null:
		_emit_empty()
		return
	var steep : float = getSettingValue( ctx, "steepness", 1.0 )
	var closed_mesh : bool = settings.mesh_volume == GetVolumeDataSettings.eMeshVolume.ClosedMesh
	var volumes : Array = []
	var names : Array = []
	for n in _sources( ctx ):
		var v : FlowSpatial = null
		if n is CollisionShape3D:
			v = FlowSpatialSources.volume_from_collision_shape( n, steep )
		elif n is MeshInstance3D:
			v = FlowSpatialSources.volume_from_mesh_instance( n, closed_mesh, steep )
		elif n.is_class( "CSGShape3D" ):
			v = FlowSpatialSources.volume_from_csg( n, steep )
		if v == null:
			continue
		volumes.append( v )
		names.append( String( n.name ) )
	if volumes.is_empty():
		_emit_empty()
		return
	if settings.output_mode == GetVolumeDataSettings.eOutputMode.Merged:
		var merged := FlowData.Data.from_shape( FlowCompositeShape.union_of( volumes ) )
		merged.set_data_attr( "source_count", volumes.size(), FlowData.DataType.Int )
		set_output( 0, merged )
		return
	for i in range( volumes.size() ):
		var d := FlowData.Data.from_shape( volumes[i] )
		d.set_data_attr( "source", names[i], FlowData.DataType.String )
		set_output( 0, d )
