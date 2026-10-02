@tool
extends FlowNodeBase

# UE PCG parity: Filter Data By Index. In DataEntries mode every data entry
# (bulk) arriving on the input is routed whole to "In Filter" or "Outside
# Filter" by its index on the pin; the other pin gets an empty Data, like
# filter_data_by_tag. In Points mode the points of each entry are split by
# their index instead.

func _init():
	meta_node = {
		"title" : "Filter Data By Index",
		"settings" : FilterDataByIndexNodeSettings,
		"aliases" : ["Filter Data By Index", "Filter Data by Index", "Filter By Index", "Select Data By Index", "Filter Points By Index"],
		"category" : "Filter",
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "In Filter" }, { "label" : "Outside Filter" }],
		"tooltip" : "Keeps the data entries (or, in Points mode, the points) whose index is listed in 'selected_indices'.\nSyntax: comma-separated indices and ranges, e.g. \"0, 2:5, -1\" (ranges exclude their end; negative values count from the end).\nSelected entries go to 'In Filter', the rest to 'Outside Filter'; 'invert' swaps them.",
	}

## Parses `spec` against `count` entries. Returns { "indices": PackedInt32Array
## (sorted, unique, inside 0..count-1), "error": String }.
static func parse_indices( spec : String, count : int ) -> Dictionary:
	var picked := {}
	var error := ""
	for raw_token in spec.split( "," ):
		var token := raw_token.strip_edges()
		if token == "":
			continue
		var parts := token.split( ":" )
		if parts.size() > 2:
			error = "Invalid index range '%s'" % token
			break
		var bad := false
		var values : Array = []
		for part in parts:
			var p := String( part ).strip_edges()
			if p == "":
				values.append( null )
			elif p.is_valid_int():
				var v := int( p )
				values.append( v + count if v < 0 else v )
			else:
				bad = true
		if bad or ( parts.size() == 1 and values[0] == null ):
			error = "Invalid index '%s'" % token
			break
		if parts.size() == 1:
			var idx : int = values[0]
			if idx >= 0 and idx < count:
				picked[idx] = true
			continue
		var start : int = 0 if values[0] == null else clampi( values[0], 0, count )
		var stop : int = count if values[1] == null else clampi( values[1], 0, count )
		for idx in range( start, stop ):
			picked[idx] = true
	var keys : Array = picked.keys()
	keys.sort()
	return { "indices": PackedInt32Array( keys ), "error": error }

func execute( ctx : FlowData.EvaluationContext ):
	var data_mode : bool = settings.mode == FilterDataByIndexNodeSettings.eMode.DataEntries
	# Index of this data entry on the input pin: one bulk is emitted per execute.
	var entry_index : int = num_generated_bulks
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		if num_generated_bulks > entry_index:
			set_output( 1, FlowData.Data.new() )
		elif data_mode:
			# Keep the entry indices of the following bulks aligned.
			set_output( 0, FlowData.Data.new() )
			set_output( 1, FlowData.Data.new() )
		return

	var spec : String = String( getSettingValue( ctx, "selected_indices", settings.selected_indices ) )
	var invert : bool = settings.invert

	if data_mode:
		var total : int = maxi( num_connected_bulks, entry_index + 1 )
		var parsed := parse_indices( spec, total )
		if parsed.error != "":
			setError( parsed.error )
			return
		var selected : bool = parsed.indices.has( entry_index )
		if selected != invert:
			set_output( 0, in_data )
			set_output( 1, FlowData.Data.new() )
		else:
			set_output( 0, FlowData.Data.new() )
			set_output( 1, in_data )
		return

	var n := in_data.size()
	var parsed_points := parse_indices( spec, n )
	if parsed_points.error != "":
		setError( parsed_points.error )
		return
	var inside : PackedInt32Array = parsed_points.indices
	var lookup := {}
	for idx in inside:
		lookup[idx] = true
	var outside := PackedInt32Array()
	for i in range( n ):
		if not lookup.has( i ):
			outside.append( i )
	if invert:
		var tmp := inside
		inside = outside
		outside = tmp
	set_output( 0, in_data.filter( inside ) )
	set_output( 1, in_data.filter( outside ) )
