@tool
extends FlowNodeBase

# Weighted Point Sampler: picks `count` points with probability proportional to
# a weight attribute, with or without replacement.
#
# Determinism: every random number derives from FlowData.resolve_seed (the
# point's own seed, else its position) combined with effective_seed(), so the
# picked set does not depend on input order and changes with the graph seed.
#  - Without replacement: Efraimidis-Spirakis keys, key_i = -ln(u_i) / w_i with
#    u_i drawn from the point's resolved seed; the `count` smallest keys win,
#    output in key order.
#  - With replacement: the eligible points are put in a canonical order (by
#    resolved seed, then position); `count` draws from one RNG seeded with
#    effective_seed() walk the cumulative weights.

func _init():
	meta_node = {
		"title" : "Weighted Point Sampler",
		"settings" : WeightedPointSamplerNodeSettings,
		"aliases" : ["Weighted Point Sampler", "Weighted Random Points", "Weighted Sample", "Pick Points By Weight", "Random Choice"],
		"category" : "Filter",
		"pure" : true,
		"main_thread" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }, { "label" : "Not Selected" }],
		"tooltip" : "Picks 'count' points with probability proportional to 'weight_attribute' (uniform when empty or all zero).\nWithout replacement the picks are distinct; with replacement a point can be picked several times\n(copies get mutated seeds). Seeded per point, so the result is stable under reordering and follows the graph seed.\n'Not Selected' gets the points never picked, in input order.",
	}

var _canon_seed : PackedInt32Array
var _canon_pos : PackedVector3Array
var _canon_key : PackedFloat64Array

func _canon_less( a : int, b : int ) -> bool:
	if _canon_key.size() > 0 and _canon_key[a] != _canon_key[b]:
		return _canon_key[a] < _canon_key[b]
	if _canon_seed[a] != _canon_seed[b]:
		return _canon_seed[a] < _canon_seed[b]
	var pa : Vector3 = _canon_pos[a] if _canon_pos.size() > 0 else Vector3.ZERO
	var pb : Vector3 = _canon_pos[b] if _canon_pos.size() > 0 else Vector3.ZERO
	if pa.x != pb.x:
		return pa.x < pb.x
	if pa.y != pb.y:
		return pa.y < pb.y
	if pa.z != pb.z:
		return pa.z < pb.z
	return a < b

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		if num_generated_bulks > 0 and generated_bulks[num_generated_bulks - 1].size() == 1:
			set_output( 1, FlowData.Data.new() )
		return

	var n := in_data.size()
	var count : int = maxi( 0, int( getSettingValue( ctx, "count", settings.count ) ) )

	# Weights (broadcast-aware); null = uniform.
	var weights := PackedFloat64Array()
	weights.resize( n )
	weights.fill( 1.0 )
	var attr : String = String( getSettingValue( ctx, "weight_attribute", settings.weight_attribute ) ).strip_edges()
	if attr != "" and n > 0:
		var stream = in_data.findStream( attr )
		if stream == null:
			setError( "Weight attribute '%s' not found" % attr )
			return
		if not ( stream.data_type in [ FlowData.DataType.Float, FlowData.DataType.Int, FlowData.DataType.Bool ] ):
			setError( "Weight attribute '%s' must be numeric (Float, Int or Bool)" % attr )
			return
		var any_positive := false
		for i in range( n ):
			var w := maxf( 0.0, float( stream.container[ FlowData.bcast_idx( stream.container.size(), i ) ] ) )
			weights[i] = w
			any_positive = any_positive or w > 0.0
		if not any_positive:
			weights.fill( 1.0 )

	# Per-point resolved seeds. A broadcast seed stream carries no per-point
	# identity, so positions are used instead.
	var node_seed := effective_seed()
	var seed_stream = in_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
	var point_seeds = seed_stream if seed_stream != null and seed_stream.size() == n and n > 0 else null
	var positions : PackedVector3Array = in_data.getVector3Container( FlowData.AttrPosition )
	var pos_for_seed = positions if positions.size() == n and n > 0 else null
	var resolved := PackedInt32Array()
	resolved.resize( n )
	for i in range( n ):
		resolved[i] = FlowData.resolve_seed( point_seeds, pos_for_seed, i, node_seed )

	_canon_seed = resolved
	_canon_pos = positions if positions.size() == n else PackedVector3Array()
	_canon_key = PackedFloat64Array()

	var eligible : Array = []
	for i in range( n ):
		if weights[i] > 0.0:
			eligible.append( i )

	var picked := PackedInt32Array()
	if settings.with_replacement:
		eligible.sort_custom( _canon_less )
		var cumulative := PackedFloat64Array()
		var total := 0.0
		for i in eligible:
			total += weights[i]
			cumulative.append( total )
		if total > 0.0:
			var rng := RandomNumberGenerator.new()
			rng.seed = node_seed
			for _draw in range( count ):
				var target := rng.randf() * total
				var k := cumulative.bsearch( target, false )
				k = mini( k, eligible.size() - 1 )
				picked.append( eligible[k] )
	else:
		var keys := PackedFloat64Array()
		keys.resize( n )
		var prng := RandomNumberGenerator.new()
		for i in eligible:
			prng.seed = resolved[i]
			var u := prng.randf_range( 1e-12, 1.0 )
			keys[i] = -log( u ) / weights[i]
		_canon_key = keys
		eligible.sort_custom( _canon_less )
		for t in range( mini( count, eligible.size() ) ):
			picked.append( eligible[t] )

	_canon_seed = PackedInt32Array()
	_canon_pos = PackedVector3Array()
	_canon_key = PackedFloat64Array()

	var out_data : FlowData.Data = in_data.filter( picked )

	if settings.with_replacement and settings.mutate_duplicate_seeds and seed_stream != null and seed_stream.size() == n and n > 0:
		var seen := {}
		var new_seeds := PackedInt32Array()
		new_seeds.resize( picked.size() )
		for r in range( picked.size() ):
			var src : int = picked[r]
			var copy : int = seen.get( src, 0 )
			seen[src] = copy + 1
			new_seeds[r] = seed_stream[src] if copy == 0 else int( hash( [ seed_stream[src], copy ] ) & 0x7fffffff )
		out_data.registerStream( FlowData.AttrSeed, new_seeds, FlowData.DataType.Int )

	var index_attr : String = String( settings.sample_index_attribute ).strip_edges()
	if index_attr != "":
		var order := PackedInt32Array()
		order.resize( picked.size() )
		for r in range( picked.size() ):
			order[r] = r
		var err = out_data.registerStream( index_attr, order, FlowData.DataType.Int )
		if err:
			setError( err )
			return

	var used := {}
	for i in picked:
		used[i] = true
	var rest := PackedInt32Array()
	for i in range( n ):
		if not used.has( i ):
			rest.append( i )

	set_output( 0, out_data )
	set_output( 1, in_data.filter( rest ) )
