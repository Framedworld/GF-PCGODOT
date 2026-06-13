@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Partition",
		"settings" : PartitionNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Attribute Partition"],
		"category" : "Metadata",
		"tooltip" : "Partition data based on the different values an attribute."
	}
	
func getTitle() -> String:
	return "Partition %s" % [ settings.attribute_name ]

func execute( ctx : FlowData.EvaluationContext ):
	var in_data = require_input( 0, ctx )
	if in_data == null:
		return

	var stream = in_data.findStream( settings.attribute_name )
	if stream == null:
		setError( "Attribute %s not found in input" % settings.attribute_name )
		return
	var container = stream.container

	if settings.trace:
		print( "Partitioning by attribute %s (%d values)" % [ settings.attribute_name, container.size() ] )
	
	# Do a quick and dirty partition by string representation of the value
	# Preserves the indices
	var parts : Dictionary = {} 
	for idx in range( container.size() ):
		var val = "%s" % container[ idx ]
		if not parts.has( val ):
			parts[ val ] = PackedInt32Array()
		parts[ val ].append( idx )
		
	if settings.trace:
		print( parts )
		
	# data_type of the partitioned attribute, used to stamp the per-data attr.
	var attr_data_type : int = stream.data_type

	var partition_id := 0
	for key in parts.keys():
		var indices : PackedInt32Array = parts[key]
		var out_data : FlowData.Data = in_data.filter( indices )
		if settings.out_partition_attribute:
			var p = newStream( out_data.size(), settings.out_partition_attribute, partition_id, FlowData.DataType.Int )
			out_data.registerStream( p.name, p.container )

		# Stamp the partition's representative key as a per-data attribute (UE
		# @Data parity). Every point in this output shares the same value for
		# the partitioned attribute, so it belongs in the data domain rather
		# than as a redundant per-point stream. Addressable as
		# "@data.<attribute_name>" downstream.
		if indices.size() > 0:
			var rep_value = container[ indices[0] ]
			var attr_container = FlowData.Data.newContainerOfType( attr_data_type )
			if attr_container != null:
				attr_container.resize( 1 )
				FlowData.Data.writeValue( attr_container, 0, rep_value, attr_data_type )
				out_data.registerStream( FlowData.DataAttrPrefix + settings.attribute_name, attr_container, attr_data_type )

		set_output( 0, out_data )
		partition_id += 1
	
