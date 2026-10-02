@tool
extends FlowNodeBase

# UE PCG parity: Get Landscape Data / Get Surface Data. Outputs surface spatial
# data (Data.shape, zero points): FlowMeshSurface from MeshInstance3D nodes,
# FlowHeightfieldSurface from HeightMapShape3D collision shapes or from a
# heightmap image. Feed it to Surface Sampler, To Point, Projection (Surface
# mode) or the spatial set operations.

const GetSurfaceDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_surface_data_settings.gd")

func _init():
	meta_node = {
		"title" : "Get Surface Data",
		"settings" : GetSurfaceDataSettings,
		"aliases" : ["Get Landscape Data", "Get Surface Data", "Landscape Data", "Get Heightmap Data"],
		"category" : "Input",
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out", "data_type" : FlowData.DataType.NodeMesh }],	# pin colour of the legacy mesh stream
		"tooltip" : "Surface data from MeshInstance3D nodes, HeightMapShape3D collision shapes or a heightmap image.\nNothing is sampled here: feed it to Surface Sampler, To Point, Projection or Difference/Intersection.",
	}

func _accept( n : Node ) -> bool:
	if settings.include_meshes and n is MeshInstance3D and n.mesh != null:
		return true
	if settings.include_heightmap_shapes and n is CollisionShape3D and n.shape is HeightMapShape3D and not n.disabled:
		return true
	return false

func _sources( ctx : FlowData.EvaluationContext ) -> Array:
	var owner_node = ctx.owner if ctx != null else null
	return FlowSpatialSources.collect( owner_node, str( getSettingValue( ctx, "group_name", "" ) ), bool( getSettingValue( ctx, "recursive", true ) ), settings.required_meta_bool, _accept )

func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	if settings.source == GetSurfaceDataSettings.eSource.HeightmapImage:
		return SCENE_INDEPENDENT
	if ctx == null or ctx.owner == null:
		return null
	return FlowSpatialSources.fingerprint( ctx.owner, _sources( ctx ) )

func _image() -> Image:
	if settings.heightmap_image != null and not settings.heightmap_image.is_empty():
		return settings.heightmap_image
	if settings.heightmap_texture != null:
		return settings.heightmap_texture.get_image()
	return null

func _emit_empty() -> void:
	var empty := FlowData.Data.new()
	empty.kind = FlowData.Kind.Surface
	set_output( 0, empty )

func execute( ctx : FlowData.EvaluationContext ):
	var tolerance : float = getSettingValue( ctx, "vertical_tolerance", -1.0 )
	if settings.source == GetSurfaceDataSettings.eSource.HeightmapImage:
		var img := _image()
		if img == null:
			setError( "Get Surface Data: no heightmap image (set heightmap_image, or a heightmap_texture with a readable image)" )
			_emit_empty()
			return
		var hf := FlowHeightfieldSurface.from_image( img, getSettingValue( ctx, "image_cell_size", 1.0 ), getSettingValue( ctx, "image_height_scale", 1.0 ), settings.image_transform, settings.image_centered )
		if tolerance > 0.0:
			hf = FlowHeightfieldSurface.new( hf.heights, hf.width, hf.depth, hf.cell_size, hf.origin, hf.transform, tolerance )
		set_output( 0, FlowData.Data.from_shape( hf ) )
		return

	if reportMissingOwner( ctx ) or ctx == null or ctx.owner == null:
		_emit_empty()
		return
	var meshes : Array = []
	var mesh_xforms : Array = []
	var mesh_names : Array = []
	var heightfields : Array = []
	var hf_names : Array = []
	for n in _sources( ctx ):
		if n is MeshInstance3D:
			meshes.append( n.mesh )
			mesh_xforms.append( FlowSpatialSources.world_transform( n ) )
			mesh_names.append( String( n.name ) )
		elif n is CollisionShape3D:
			var hf := FlowHeightfieldSurface.from_heightmap_shape( n.shape, FlowSpatialSources.world_transform( n ) )
			if tolerance > 0.0:
				hf = FlowHeightfieldSurface.new( hf.heights, hf.width, hf.depth, hf.cell_size, hf.origin, hf.transform, tolerance )
			heightfields.append( hf )
			hf_names.append( String( n.name ) )
	if meshes.is_empty() and heightfields.is_empty():
		_emit_empty()
		return

	if settings.output_mode == GetSurfaceDataSettings.eOutputMode.Merged:
		var parts : Array = []
		if not meshes.is_empty():
			parts.append( FlowMeshSurface.from_meshes( meshes, mesh_xforms, tolerance ) )
		parts.append_array( heightfields )
		var merged := FlowData.Data.from_shape( FlowCompositeShape.union_of( parts ) )
		merged.set_data_attr( "source_count", meshes.size() + heightfields.size(), FlowData.DataType.Int )
		set_output( 0, merged )
		return
	for i in range( meshes.size() ):
		var d := FlowData.Data.from_shape( FlowMeshSurface.from_meshes( [ meshes[i] ], [ mesh_xforms[i] ], tolerance ) )
		d.set_data_attr( "source", mesh_names[i], FlowData.DataType.String )
		set_output( 0, d )
	for i in range( heightfields.size() ):
		var d := FlowData.Data.from_shape( heightfields[i] )
		d.set_data_attr( "source", hf_names[i], FlowData.DataType.String )
		set_output( 0, d )
