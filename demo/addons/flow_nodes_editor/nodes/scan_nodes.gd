@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Scan Nodes",
		"settings" : ScanNodesNodeSettings,
		"aliases" : ["Get Actor Data"],
		"category" : "Input",
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Generate points from existing non-flowgraph nodes in the scene\nCan filter by class name, node name (supports * and ? wildcards) or group.\nMetadata values can optionally be imported\nYou can also import properties of the nodes, even with a\nsubpath property like mesh:text if the nodes are a MeshInstance3D with meshes of type TextMesh.",
	}

# material[0]:albedo_color
# name

func _gather_descendants( node : Node, out : Array[Node] ) -> void:
	for child in node.get_children():
		out.append( child )
		_gather_descendants( child, out )

func _collect_scene_nodes( ctx : FlowData.EvaluationContext, filter_class_name : String ) -> Array[ Node3D ]:
	var scene_nodes : Array[ Node3D ] = []
	if ctx.owner == null:
		return scene_nodes

	var group_name = getSettingValue( ctx, "group_name" )
	var recursive : bool = getSettingValue( ctx, "recursive", true )
	var name_filter : String = String( getSettingValue( ctx, "filter_by_name", "" ) ).strip_edges()

	var all_nodes : Array[Node] = []
	if group_name:
		all_nodes = ctx.owner.get_tree().get_nodes_in_group( group_name )
	else:
		var root = getSceneRootNode3d( ctx.owner )
		if recursive:
			_gather_descendants( root, all_nodes )
		else:
			all_nodes = root.get_children()

	if settings.trace:
		print( "all_nodes", all_nodes )

	for node in all_nodes:
		var node3d := node as Node3D
		if node3d == null:
			continue
		if filter_class_name and not node3d.is_class( filter_class_name ):
			if settings.trace:
				print( "%s.%s discarted by class_name %s" % [ node3d.name, node3d.get_class(), filter_class_name ])
			continue
		if name_filter != "" and not String( node3d.name ).matchn( name_filter ):
			continue
		scene_nodes.append( node3d )
	return scene_nodes

func importMetaData( output, nodes ):
	var nsamples = nodes.size()
	for idx in range( nsamples ):
		var node = nodes[idx]
		var metas = node.get_meta_list()
		for meta in metas:
			var value = node.get_meta( meta )
			if value == null:
				continue
			var value_data_type = getFlowDataTypeFromObject( value )
			if value_data_type == FlowData.DataType.Invalid:
				continue
			if not output.hasStream( meta ):
				output.addStream( meta, value_data_type )
			var stream = output.findStream( meta )
			assert( stream )
			if stream.data_type != value_data_type:
				push_warning( "Node %d (%s), meta: %s has type %d but the registered stream has type %d" % [ idx, node.name, meta, value_data_type, stream.data_type ])
				continue
			if value_data_type == FlowData.DataType.Bool:
				value = 1 if value else 0
			stream.container[ idx ] = value
			#print( "Saved as %s" % [ stream.container[ idx ] ])

func get_property_path( current, path_parts ):
	for key in path_parts:
		if current == null:
			return null
		var current_type := typeof( current )
		if current_type == TYPE_DICTIONARY:
			current = current.get( key, null )
		elif current_type == TYPE_OBJECT:
			if settings.trace:
				print( "current is %s. (%s)" % [ current, key ] )
			# Custom hand-made solution
			if key == "material[0]" and current.has_method( "get_active_material" ):
				current = current.get_active_material(0)
			else:
				current = current.get(key)
		else:
			# Plain Variants (arrays, numbers, ...) have no sub-properties we can traverse
			if settings.trace:
				print( "obj %s can not be traversed with key %s" % [ current, key ])
			return null

		# Testing get_class to return the class_name of each node
		if typeof( current ) == TYPE_CALLABLE:
			current = current.call()

	if settings.trace:
		print( "Final %s returned value is %s Type:%d" % [ path_parts, current, typeof( current ) ] )
	return current

func importProperty( output, nodes, prop_path ):
	var nsamples = nodes.size()
	var stream = null

	var parts = prop_path.split( ":" )
	var stream_name = parts[ parts.size() - 1 ]

	for idx in range( nsamples ):
		var node = nodes[idx]
		var value = get_property_path( node, parts )
		if value == null:
			continue
		var value_data_type = getFlowDataTypeFromObject( value )
		if value_data_type == FlowData.DataType.Invalid:
			# Special conversion StringName becomes a String. For example reading name
			if typeof( value ) == TYPE_STRING_NAME:
				value_data_type = FlowData.DataType.String
				value = String( value )
			elif typeof( value ) == TYPE_COLOR:
				value_data_type = FlowData.DataType.Vector
				value = Vector3( value.r, value.g, value.b )	# Alpha is not read!
			else:
				continue
		if not stream:
			output.addStream( stream_name, value_data_type )
			stream = output.findStream( stream_name )

		if stream.data_type != value_data_type:
			push_warning( "Node %d (%s), property: %s has type %d but the registered stream has type %d" % [ idx, node.name, prop_path, value_data_type, stream.data_type ])
			continue

		# Special cases
		if value_data_type == FlowData.DataType.Bool:
			value = 1 if value else 0

		stream.container[ idx ] = value

# Returns the AABB of the node in the node's own LOCAL space
func get_aabb_of_node( node3d : Node3D ) -> AABB:
	var combined_aabb := AABB()  # Starts as invalid (zero size)
	if node3d is MeshInstance3D:
		if node3d.mesh:
			return node3d.mesh.get_aabb()
	elif node3d is Path3D:
		if node3d.curve == null:
			return combined_aabb
		var points : PackedVector3Array = node3d.curve.get_baked_points()
		if points.size() > 0:
			var pmin = points[0]
			var pmax = points[0]
			for p in points:
				pmin = pmin.min( p )
				pmax = pmax.max( p )
			var full_size = ( pmax - pmin )
			return AABB( pmin, full_size )

	elif node3d is CollisionShape3D:
		var shape = node3d.shape
		if shape:
			if shape is BoxShape3D:
				var box_shape = shape as BoxShape3D
				# Shape-local space: the box is centered on the node origin
				return AABB( -box_shape.size * 0.5, box_shape.size )

	return combined_aabb

func get_combined_aabb(root: Node3D) -> AABB:
	var combined_aabb := get_aabb_of_node( root )
	for child in root.get_children():
		var child3d := child as Node3D
		if child3d == null:
			continue
		var child_aabb := get_aabb_of_node( child3d )
		if child_aabb.size == Vector3.ZERO:
			continue
		# Bring the child AABB into the root's local space
		child_aabb = child3d.transform * child_aabb
		if combined_aabb.size == Vector3.ZERO:
			combined_aabb = child_aabb
		else:
			combined_aabb = combined_aabb.merge(child_aabb)
	return combined_aabb

# Also inherited by points_from_scene.gd
func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	var filter_by_class_name = getSettingValue( ctx, "filter_by_class_name" )
	var nodes = filterOutGeneratedNodes( _collect_scene_nodes( ctx, filter_by_class_name ) )
	var extra := []
	if getSettingValue( ctx, "import_metadata" ) as bool:
		for node in nodes:
			for meta in node.get_meta_list():
				extra.append( meta )
				extra.append( node.get_meta( meta ) )
	for prop_path in settings.import_properties:
		if prop_path:
			var parts = prop_path.split( ":" )
			for node in nodes:
				extra.append( get_property_path( node, parts ) )
	if settings.size_to_bounds:
		for node in nodes:
			extra.append( get_combined_aabb( node ) )
	return hashSceneNodesForFingerprint( ctx, nodes, extra )

func execute( ctx : FlowData.EvaluationContext ):
	var output := FlowData.Data.new()

	var filter_by_class_name = getSettingValue( ctx, "filter_by_class_name" )
	# Never scan content a flow graph generated (flow_owner meta): the editor
	# removes it before every regen, but at runtime a second component's scan
	# would otherwise pick up the first one's spawned nodes, and their
	# auto-generated names make the result non-deterministic.
	var nodes = filterOutGeneratedNodes( _collect_scene_nodes( ctx, filter_by_class_name ) )

	var nsamples = nodes.size()
	output.addCommonStreams( nsamples )

	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var ssize := output.getVector3Container( FlowData.AttrSize )
	for idx in range( nsamples ):
		var node = nodes[idx]
		spos[idx] = node.global_position
		ssize[idx] = node.scale
		var b : Basis = node.global_transform.basis
		srot[idx] = FlowData.basisToEuler( b )

		if settings.size_to_bounds:
			var aabb = get_combined_aabb( node )
			ssize[idx] = aabb.size * b.get_scale()
			spos[idx] = node.global_transform * ( aabb.position + aabb.size * 0.5 )

	if getSettingValue( ctx, "import_metadata" ) as bool:
		importMetaData( output, nodes )

	for prop_name in settings.import_properties:
		if prop_name:
			importProperty( output, nodes, prop_name )

	set_output( 0, output )
