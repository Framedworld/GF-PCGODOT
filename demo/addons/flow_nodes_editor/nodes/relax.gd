@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Relax",
		"settings" : RelaxNodeSettings,
		"ins" : [{"label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Relax Points"],
		"category" : "Spatial",
		"tooltip" : "Relax distance between points\nPoints push apart while closer than their combined size radius plus the padding.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx )
	if in_data == null:
		return
	var out_data : FlowData.Data = in_data.duplicate()
	var cloned = out_data.cloneStream( FlowData.AttrPosition )
	if cloned == null:
		setError( "Input must provide a %s stream" % FlowData.AttrPosition )
		return
	var spos : PackedVector3Array = cloned
	var strength : float = getSettingValue( ctx, "strength" )
	var num_iterations : int = getSettingValue( ctx, "num_iterations" )
	var padding : float = getSettingValue( ctx, "padding" )
	#print( "Iterating %d" % [num_iterations])

	var tA = GDRTree.new()
	var num_points = spos.size()
	var szA = in_data.getVector3Container( FlowData.AttrSize )
	if szA.size() != num_points:
		# Missing/mismatched size stream — fall back to unit-sized points.
		szA = PackedVector3Array()
		szA.resize( num_points )
		szA.fill( Vector3.ONE )

	# Deterministic tie-break direction for coincident points.
	var rng = RandomNumberGenerator.new()
	rng.seed = effective_seed()

	var candidate_pos : PackedVector3Array
	var candidate_size : PackedVector3Array
	candidate_pos.resize(1)
	candidate_size.resize(1)

	for iter in num_iterations:
		var acc_deltas : PackedVector3Array
		acc_deltas.resize( num_points )

		tA.clear()
		tA.add(spos, szA)
		var num_modifies : int = 0
		#print( "Pos sz:%d sizes:%d" % [ posA.size(), szA.size()] )

		for i in spos.size():
			candidate_pos[0] = spos[i]
			# Search box covers the point's own size plus the padding on every
			# side. (The old formula multiplied by padding, so the default
			# padding of 0 produced a zero-sized box and the node was a no-op.)
			candidate_size[0] = ( szA[i] + Vector3.ONE * padding ) * 2.0
			var result = tA.overlaps( candidate_pos, candidate_size, true )

			for j in result.idxs_overlapped:
				if j <= i:
					continue

				var vij : Vector3 = spos[j] - spos[i]
				var dij = vij.length()
				var dir = vij / dij if dij > 0.0001 else Vector3(rng.randf(), rng.randf(), rng.randf()).normalized()

				var radius = (szA[i] + szA[j]).length() * 0.5 + padding
				if dij >= radius:
					continue  # too far

				var amount = (1.0 - dij / radius) * 0.5 * strength					
				if amount < 0.01:
					continue
				
				acc_deltas[ i ] -= dir * amount
				acc_deltas[ j ] += dir * amount
				num_modifies += 1
				#print( "Vertex %d modifies vtx %d by %f" % [ i, j, amount ])
	
		if num_modifies == 0:
			#print( "Stop at iteration %d/%d" % [ iter, num_iterations ])
			break

		for i in spos.size():
			spos[i] += acc_deltas[i]
	set_output( 0, out_data )
