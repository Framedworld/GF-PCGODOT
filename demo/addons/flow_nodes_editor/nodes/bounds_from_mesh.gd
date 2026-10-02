@tool
extends FlowNodeBase

# UE PCG parity: Bounds From Mesh. Writes each point's bounds_min/bounds_max
# from a mesh's local AABB (the settings mesh, or a per-point Mesh attribute),
# so bounds-driven nodes (self_pruning, difference, split_points, ...) see the
# footprint of the mesh that will be spawned there. Transforms are unchanged.

func _init():
	meta_node = {
		"title" : "Bounds From Mesh",
		"settings" : BoundsFromMeshNodeSettings,
		"aliases" : ["Bounds From Mesh", "Set Bounds From Mesh", "Mesh Bounds"],
		"category" : "Spatial",
		# Main thread, not cached: Mesh.get_aabb() on a PrimitiveMesh with a
		# pending change runs its lazy update (RenderingServer, own state).
		"pure" : false,
		"main_thread" : true,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Sets every point's bounds_min/bounds_max to the local AABB of a mesh: the 'mesh' setting,\nor per point the Mesh in 'mesh_attribute' (falling back to 'mesh').\nPoints without any mesh keep their current bounds. Transforms and size are untouched.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return

	var mesh : Mesh = settings.mesh
	var attr : String = String( settings.mesh_attribute ).strip_edges()
	var mesh_stream = null
	if attr != "":
		mesh_stream = in_data.findStream( attr )
		if mesh_stream == null:
			setError( "Mesh attribute '%s' not found" % attr )
			return
		if mesh_stream.data_type != FlowData.DataType.Resource:
			setError( "Mesh attribute '%s' must be a Resource attribute" % attr )
			return
	elif mesh == null:
		setError( "Set 'mesh' or 'mesh_attribute'" )
		return

	var n := in_data.size()
	var eff := in_data.getEffectiveBounds()
	var new_min : PackedVector3Array = eff.min
	var new_max : PackedVector3Array = eff.max
	var fixed_aabb : AABB = mesh.get_aabb() if mesh != null else AABB()
	for i in range( n ):
		var point_mesh : Mesh = mesh
		if mesh_stream != null and mesh_stream.container.size() > 0:
			var candidate = mesh_stream.container[ FlowData.bcast_idx( mesh_stream.container.size(), i ) ]
			if candidate is Mesh:
				point_mesh = candidate
		if point_mesh == null:
			continue
		var aabb : AABB = fixed_aabb if point_mesh == mesh else point_mesh.get_aabb()
		new_min[i] = aabb.position
		new_max[i] = aabb.end

	var out_data : FlowData.Data = in_data.duplicate()
	var err = out_data.registerStream( FlowData.AttrBoundsMin, new_min, FlowData.DataType.Vector )
	if err == null:
		err = out_data.registerStream( FlowData.AttrBoundsMax, new_max, FlowData.DataType.Vector )
	if err:
		setError( err )
		return
	set_output( 0, out_data )
