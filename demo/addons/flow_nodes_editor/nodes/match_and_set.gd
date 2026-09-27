@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Match And Set",
		"settings" : MatchAndSetNodeSettings,
		"ins" : [{ "label" : "In" }, { "label" : "Attributes" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Match And Set Attributes"],
		"category" : "Metadata",
		"tooltip" : "Copies attributes into input data set based on a match_attr." +
					"\nThe match_attr is used to pick an asset where the match attribute is the sample in the In and Attributes stream." + 
					"\nThe weight_attr controls if some assets should be picked more frequently than others." + 
					"\nIf none are set, a random point from the Attributes entry is picked and assigned to each In point" +
					"\nNumeric keys: when a value has no exact (string) match and both it and a key are numeric" +
					"\n(int/float, or a string that parses as one), they match as floats (3 == 3.0 == \"3\")."
	}

## Returns `value` as a float when it is numeric (int/float, or a String that
## parses as an int/float), else null. Bools are not treated as numbers.
static func _as_number( value ):
	match typeof( value ):
		TYPE_INT, TYPE_FLOAT:
			return float( value )
		TYPE_STRING, TYPE_STRING_NAME:
			var text := String( value ).strip_edges()
			if text.is_valid_int() or text.is_valid_float():
				return float( text )
	return null

## Numeric fallback for a value with no exact string key: returns the first
## LUT key (in first-seen order) that is numerically equal (is_equal_approx),
## or null when the value is not numeric or nothing matches. Memoized per value.
static func _numeric_lut_key( value, numeric_keys : Array, memo : Dictionary ):
	var value_str := str( value )
	if memo.has( value_str ):
		return memo[ value_str ]
	var resolved = null
	var number = _as_number( value )
	if number != null:
		for entry in numeric_keys:
			if is_equal_approx( entry[0], number ):
				resolved = entry[1]
				break
	memo[ value_str ] = resolved
	return resolved

## RNG for point `idx`. With a seed stream: (point seed ^ node seed), as
## before. Without one: FlowData.resolve_seed (position hash, then index),
## unless `legacy_global_rng` asks for the node-global rng in draw order.
func _point_rng( idx : int, seed_container, positions, node_seed : int, legacy_global_rng : bool, point_rng : RandomNumberGenerator ) -> RandomNumberGenerator:
	if seed_container != null:
		if idx < seed_container.size():
			point_rng.seed = (int(seed_container[idx]) ^ node_seed) & 0x7fffffff
			return point_rng
		return rng
	if legacy_global_rng:
		return rng
	point_rng.seed = FlowData.resolve_seed( null, positions, idx, node_seed )
	return point_rng

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	var attrs_data : FlowData.Data = require_input(1, ctx, "Input 'Attributes'")
	if attrs_data == null:
		return

	# Per-point seed consumption (UE $Seed parity): when the input carries an
	# AttrSeed stream, each point's random pick derives from point_seed ^ node
	# seed. When it is absent, each point's seed comes from
	# FlowData.resolve_seed (position hash, then index), like the other
	# stochastic nodes. `legacy_global_rng` restores the old behaviour: points
	# without a seed stream draw from the node-global rng in index order.
	var seed_stream = in_data.streams.get(FlowData.AttrSeed, null)
	var seed_container = seed_stream.container if seed_stream != null else null
	var node_seed : int = effective_seed()
	var point_rng := RandomNumberGenerator.new()
	var legacy_global_rng : bool = getSettingValue( ctx, "legacy_global_rng" )
	var positions = null
	if seed_container == null and not legacy_global_rng:
		positions = in_data.getContainerChecked( FlowData.AttrPosition, FlowData.DataType.Vector )

	var using_lut := false
	var lut := {}
	var numeric_keys := []	# [ float, lut key ] for every numeric LUT key
	var numeric_memo := {}
	var input_lut_container
	var match_attr : String = getSettingValue( ctx, "match_attr" )
	if match_attr:
		var match_stream = attrs_data.findStream( match_attr )
		if match_stream == null:
			setError( "Can't find attribute %s in Attributes input" % match_attr )
			return
		var input_lut_stream = in_data.findStream( match_attr )
		if input_lut_stream == null:
			setError( "Can't find attribute %s in In input" % match_attr )
			return
		input_lut_container = input_lut_stream.container
		var attr_index := 0
		for value in match_stream.container:
			var value_str := str(value)
			if not value_str in lut:
				var empty_int_array: Array[int] = []
				lut[ value_str ] = empty_int_array
				var number = _as_number( value )
				if number != null:
					numeric_keys.append( [ number, value_str ] )
			lut[ value_str ].append( attr_index )
			attr_index += 1
		using_lut = true
	
	var weight_attr : String = getSettingValue( ctx, "weight_attr" )
	var weight_stream = null
	if weight_attr:
		weight_stream = attrs_data.findStream( weight_attr )
		if weight_stream == null:
			setError( "Can't find weight attribute %s in Attributes input" % weight_attr )
			return

	# Create the new streams
	var out_data : FlowData.Data = in_data.duplicate()
	var in_containers = []
	var out_containers = []
	for attr_stream in attrs_data.streams.values():
		var new_container = out_data.addStream( attr_stream.name, attr_stream.data_type )
		# print( "new_container: ", attr_stream, " Sz:", new_container.size())
		in_containers.append( attr_stream.container )
		out_containers.append( new_container )
		
	var num_new_streams := out_containers.size()
	if using_lut:
		for idx in range( out_data.size() ):
			var prng : RandomNumberGenerator = _point_rng( idx, seed_container, positions, node_seed, legacy_global_rng, point_rng )
			var in_lut_value : String = str(input_lut_container[ idx ])
			if not lut.has( in_lut_value ) and not numeric_keys.is_empty():
				var numeric_key = _numeric_lut_key( input_lut_container[ idx ], numeric_keys, numeric_memo )
				if numeric_key != null:
					in_lut_value = numeric_key
			if lut.has( in_lut_value ):
				var candidate_indices : Array[int] = lut[in_lut_value]
				var num_choices := candidate_indices.size()
				var choice_index := 0
				if weight_stream != null:
					var weights : Array[float] = []
					var total_weight : float = 0.0
					for c_idx in candidate_indices:
						var w : float = float(weight_stream.container[c_idx])
						if w < 0.0:
							w = 0.0
						weights.append(w)
						total_weight += w

					if total_weight > 0.0:
						var r := prng.randf() * total_weight
						var accumulated := 0.0
						for i in range(num_choices):
							accumulated += weights[i]
							if r <= accumulated:
								choice_index = i
								break
					else:
						choice_index = prng.randi_range( 0, num_choices - 1 )
				else:
					choice_index = prng.randi_range( 0, num_choices - 1 )

				var attr_idx := candidate_indices[ choice_index ]
				#print( "OutPoint: %d Using attr index %d" % [ idx, attr_idx ])
				for j in range(num_new_streams):
					out_containers[ j ][ idx ] = in_containers[ j ][ attr_idx ]
			# Points whose match value has no LUT entry keep their default
			# (zero-filled) values for every copied stream.

	else:
		var num_choices = attrs_data.size()
		if num_choices > 0 && num_new_streams > 0:
			var weights : Array[float] = []
			var total_weight : float = 0.0
			var has_weights := weight_stream != null
			
			if has_weights:
				for idx in range(num_choices):
					var w : float = float(weight_stream.container[idx])
					if w < 0.0:
						w = 0.0
					weights.append(w)
					total_weight += w
			
			for idx in range( out_data.size() ):
				var prng : RandomNumberGenerator = _point_rng( idx, seed_container, positions, node_seed, legacy_global_rng, point_rng )
				var attr_idx : int = -1
				if has_weights && total_weight > 0.0:
					var r := prng.randf() * total_weight
					var accumulated := 0.0
					for i in range(num_choices):
						accumulated += weights[i]
						if r <= accumulated:
							attr_idx = i
							break
					if attr_idx == -1:
						attr_idx = prng.randi_range( 0, num_choices - 1 )
				else:
					attr_idx = prng.randi_range( 0, num_choices - 1 )
				# print( "Copy all attr of in_attr[%d] into out_data[%d]" % [attr_idx, idx])
				for j in range(num_new_streams):
					out_containers[ j ][ idx ] = in_containers[ j ][ attr_idx ]
			
	set_output( 0, out_data )
