@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Create Spline",
		"settings" : CreateSplineNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Splines", "data_type": FlowData.DataType.NodePath }],
		"tooltip" : "Generates a spline from all the input points.",
		"aliases" : ["Create Spline"],
		"category" : "Spatial",
	}

func removeInstancedNodes( root : Node, ctx : FlowData.EvaluationContext = null ):
	removeOwnFlowContent( root, ctx )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx)
	if in_data == null:
		return
	if handleMissingOwner( ctx ):
		return
	var in_trs := in_data.getTransformsStream()
	if in_trs == null:
		setError( "Invalid input. Missing required attributes %s/%s/%s" % [ FlowData.AttrPosition, FlowData.AttrRotation, FlowData.AttrSize ])
		return

	var root = ctx.owner
	if root == null or root.get_tree() == null:
		if Engine.is_editor_hint():
			set_output( 0, FlowData.Data.new() )
			return
		setError( "Create Spline needs a scene owner to spawn the Path3D under" )
		return

	# Clean up splines spawned by previous evaluations of this node
	removeInstancedNodes( root, ctx )

	var scene_root = root.get_tree().current_scene
	var owner_of_spawned_nodes : Node = scene_root if scene_root else root

	var path := Path3D.new()
	path.name = "Spline"
	# Readable add: a taken name becomes "Spline2", as the rename after
	# add_child() always gave, without a transient "@Path3D@N" auto-name.
	root.add_child( path, true )
	# Owner must be set AFTER the node is inside the tree or it never persists
	assignSpawnOwner( path, owner_of_spawned_nodes, ctx )
	tagFlowContent( path, ctx )
	path.curve = Curve3D.new()
	var num_idxs : int = in_trs.size()
	for idx in range( num_idxs ):
		var pos : Vector3 = in_trs.positions[idx]
		var in_tan : Vector3 = Vector3.ZERO
		var out_tan : Vector3 = Vector3.ZERO
		if idx > 0 and idx < num_idxs - 1:
			var dir = in_trs.positions[idx+1] - in_trs.positions[idx-1]
			var ndir = dir.normalized() * 0.5
			in_tan = -ndir
			out_tan = ndir
		path.curve.add_point( pos, in_tan, out_tan )
		#print( "  pos[%d]: = %s" % [idx, pos ] )
	var output := FlowData.Data.new()
	output.registerStream( "node", [path], FlowData.DataType.NodePath )
	set_output( 0, output )
