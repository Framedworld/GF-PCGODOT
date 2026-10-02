@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Merge",
		"settings" : MergeNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Merge", "Merge Points"],
		"category" : "Utility",
		"tooltip" : "Merges and combines all streams of all input connections in a single output\nIf input A provides streams s1 and s2, and input B streams s1 and s3\nthe output will have streams s1,s2 and s3 and the default values will be used where the input does not define a value.",
	}

func run( ctx : FlowData.EvaluationContext ):

	var out_data := FlowData.Data.new()
	var offset = 0
	
	# Each output connected to our input can bring several bulk datas
	for bulk_index in range( num_connected_bulks ):
		readAllInputsForBulk( ctx, bulk_index )
		var in_data = get_input(0)
		if in_data == null:
			continue
			
		if settings.trace:
			print( "Processing input data with size %d: (Offset:%d)" % [ in_data.size(), offset ] )

		# First register every stream this bulk introduces, sized to the current
		# offset (just before us adding our content). Doing this before any
		# append keeps every out stream at the same length while registering,
		# so registerStream's point-count invariant does not warn.
		for stream_name in in_data.streams:
			if not out_data.hasStream( stream_name ):
				var stream = in_data.streams[ stream_name ]
				var container = in_data.newContainerOfType( stream.data_type )
				container.resize( offset )
				var err = out_data.registerStream( stream_name, container, stream.data_type )
				if err:
					setError( err )
					return

		# Then append this bulk's values to each stream
		for stream_name in in_data.streams:
			var stream = in_data.streams[ stream_name ]
			var out_stream = out_data.findStream( stream_name )

			if out_stream == null:
				setError( "Failed to find or register stream %s" % stream_name )
				return
			elif stream.data_type != out_stream.data_type:
				# Tolerated mismatch: skip this bulk's values for the stream (the
				# resize below zero-pads) so the merge still completes — aborting
				# here would kill whole graphs over one inconsistent stream.
				push_warning( "Merge '%s': stream %s is already defined with type %s, but input bulk %d provides it with type %s — skipping its values" % [ name, stream_name, out_stream.data_type, bulk_index, stream.data_type ] )
			else:
				# copy elements of stream in target stream at the end
				out_stream.container.append_array( stream.container )

		offset += in_data.size()
		
		# Ensure we have all the containers with the same size (in case in_data does not provide a stream for example
		for stream_name in out_data.streams:
			var stream = out_data.streams[ stream_name ]
			if stream.container.size() < offset:
				# print( " Appending %d elems from input container -> %d" % [ stream.container.size(), offset ] )
				stream.container.resize( offset )

	set_output( 0, out_data )
