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
					"\nIf none are set, a random point from the Attributes entry is picked and assigned to each In point" 
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	var attrs_data : FlowData.Data = require_input(1, ctx, "Input 'Attributes'")
	if attrs_data == null:
		return

	# Per-point seed consumption (UE $Seed parity): when the input carries an
	# AttrSeed stream, each point's random pick derives from point_seed ^ node
	# seed; when absent, the node-level rng behavior is kept unchanged.
	var seed_stream = in_data.streams.get(FlowData.AttrSeed, null)
	var seed_container = seed_stream.container if seed_stream != null else null
	var node_seed : int = effective_seed()
	var point_rng := RandomNumberGenerator.new()

	var using_lut := false
	var lut := {}
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
			var prng : RandomNumberGenerator = rng
			if seed_container != null and idx < seed_container.size():
				point_rng.seed = (int(seed_container[idx]) ^ node_seed) & 0x7fffffff
				prng = point_rng
			var in_lut_value : String = str(input_lut_container[ idx ])
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
				var prng : RandomNumberGenerator = rng
				if seed_container != null and idx < seed_container.size():
					point_rng.seed = (int(seed_container[idx]) ^ node_seed) & 0x7fffffff
					prng = point_rng
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
