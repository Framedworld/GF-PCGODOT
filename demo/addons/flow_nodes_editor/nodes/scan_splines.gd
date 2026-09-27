@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Scan Splines",
		"settings" : ScanSplinesNodeSettings,
		"aliases" : ["Get Spline Data"],
		"category" : "Input",
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out", "data_type" : FlowData.DataType.NodePath }],
		"tooltip" : "Collects Path3D nodes from the scene and outputs a 'node' stream plus a 'curve' Resource stream.\nFilter by group and/or a boolean metadata flag. Recursive scan can be disabled to inspect only direct children of the scene root.",
	}

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
	var required_meta : StringName = settings.required_meta_bool

	var all_nodes : Array[Node] = []
	if group_name:
		if ctx.owner.is_inside_tree():
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
		if required_meta != &"" and not ( node3d.has_meta( required_meta ) and bool( node3d.get_meta( required_meta ) ) ):
			continue
		scene_nodes.append( node3d )
	return scene_nodes

func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	var nodes = filterOutGeneratedNodes( _collect_scene_nodes( ctx, "Path3D" ) )
	var extra := []
	for node in nodes:
		var curve : Curve3D = node.curve
		if curve:
			extra.append( curve.get_instance_id() )
			extra.append( curve.get_point_count() )
			extra.append( curve.get_baked_length() )
		else:
			extra.append( 0 )
	return hashSceneNodesForFingerprint( ctx, nodes, extra )

func execute( ctx : FlowData.EvaluationContext ):
	# Owner-less runtime evaluation: report it, still emit the empty schema.
	reportMissingOwner( ctx )
	var nodes = _collect_scene_nodes( ctx, "Path3D" )
	# Drop paths without a curve so 'node' and 'curve' streams stay aligned and
	# downstream nodes (e.g. sample_spline) never null-deref on path.curve.
	nodes = nodes.filter( func( obj ): return obj.curve != null )
	var output := FlowData.Data.new()
	output.registerStream( "node", nodes, FlowData.DataType.NodePath )
	var curves = nodes.map( func( obj ): return obj.curve )
	output.registerStream( "curve", curves, FlowData.DataType.Resource )
	set_output( 0, output )
