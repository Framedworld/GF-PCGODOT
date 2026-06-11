@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Distance",
		"settings" : DistanceNodeSettings,
		"ins" : [{ "label": "In" }, { "label": "Target" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Creates a new attribute where the value is\nthe minimum distance from each point to any of the points in the second set.\nThe value can be normalized to an optional Max Distance",
	}

func execute( ctx : FlowData.EvaluationContext ):
	
	if not settings.out_name:
		setError( "Output name can't be empty")
		return
		
	var in_dataA : FlowData.Data = get_input(0)
	# Empty A set (e.g. an upstream filter that matched nothing) legitimately has
	# no streams yet — pass the empty set through with the out attribute registered
	# so the rest of the branch keeps evaluating (mirrors attribute_filter_range).
	if in_dataA == null or in_dataA.size() == 0:
		var empty_data : FlowData.Data = FlowData.Data.new() if in_dataA == null else in_dataA.duplicate()
		empty_data.registerStream( settings.out_name, PackedFloat32Array() )
		set_output(0, empty_data)
		return
	if not in_dataA.hasStreamOfType( settings.in_nameA, FlowData.DataType.Vector ):
		if ctx.owner == null and Engine.is_editor_hint():
			var empty_data = FlowData.Data.new()
			set_output(0, empty_data)
			return
		setError( "Input A %s not found" % [settings.in_nameA])
		return

	var in_dataB : FlowData.Data = get_input(1)
	# An unwired Target port returns null — that's an authoring error, NOT a valid
	# empty set. Report it (or pass empty in editor preview, like the not-found paths)
	# instead of silently treating it as "no targets" and writing 1.0 distances for
	# every point, which would make downstream `dist >= X` filters pass everything.
	if in_dataB == null:
		if ctx.owner == null and Engine.is_editor_hint():
			var empty_data = FlowData.Data.new()
			set_output(0, empty_data)
			return
		setError( "Input B not connected" )
		return
	# Connected-but-empty B (e.g. an upstream filter that matched nothing) is the valid
	# empty case — handled by the far-fill below. Only a NON-empty B missing the stream
	# is an authoring error.
	var b_empty : bool = in_dataB.size() == 0
	if not b_empty and not in_dataB.hasStreamOfType( settings.in_nameB, FlowData.DataType.Vector ):
		if ctx.owner == null and Engine.is_editor_hint():
			var empty_data = FlowData.Data.new()
			set_output(0, empty_data)
			return
		setError( "Input B %s not found" % [settings.in_nameB])
		return

	var sA := in_dataA.getVector3Container( settings.in_nameA )
	var sB := in_dataB.getVector3Container( settings.in_nameB ) if not b_empty else PackedVector3Array()

	var size_A = in_dataA.size()

	# Empty B set: nothing to measure against — every A point is "infinitely far"
	# (normalized 1.0), so downstream `dist >= X` filters pass everything instead
	# of crashing on an out-of-bounds kd-tree index.
	if sB.is_empty():
		var far_data : FlowData.Data = in_dataA.duplicate()
		var far_container := PackedFloat32Array()
		far_container.resize( size_A )
		far_container.fill( 1.0 )
		far_data.registerStream( settings.out_name, far_container )
		set_output( 0, far_data )
		return

	var kdtree = GDKdTree.new()
	kdtree.set_points( sB )
	#print( "Populated kdtree with %d points. WIll check %d" % [in_dataB.size(), size_A])
	var nearest_indices : PackedInt32Array = kdtree.find_nearest_indices( sA )
	
	var inv_max_distance : float = 1.0 / settings.max_distance if settings.max_distance > 0 else 1.0
	
	var out_data : FlowData.Data = in_dataA.duplicate()
	var out_container := PackedFloat32Array()
	out_container.resize( size_A )
	for idx in range(size_A):
		var idxB := nearest_indices[ idx ]
		var delta := sA[ idx ] - sB[ idxB ]
		out_container[ idx ] = delta.length() * inv_max_distance
	
	var err = out_data.registerStream( settings.out_name, out_container )
	set_output( 0, out_data )
