@tool
extends FlowNodeBase

const MergeAttributesSettings = preload("res://addons/flow_nodes_editor/nodes/merge_attributes_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Merge Attributes",
		"settings" : MergeAttributesSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Merges every data on In into one attribute set.\n" +
			"Append: entries are concatenated in input order with the union of attributes; missing values get the type default;\n" +
			"numeric type clashes promote (Int + Float = Float, Int + Int64 = Int64, Int64 + Float = Double); other clashes fail.\n" +
			"ByIndex: attributes are joined side by side, entry by entry (later inputs win name clashes).\n" +
			"Tags and @data attributes are merged too (later inputs win). Unlike Merge, type clashes never drop values silently.",
		"aliases" : ["Merge Attributes", "Merge Attribute Sets"],
		"category" : "Metadata",
	}

func run( ctx : FlowData.EvaluationContext ):
	var entries : Array = []
	for bulk_index in range( num_connected_bulks ):
		readAllInputsForBulk( ctx, bulk_index )
		var in_data = get_input( 0 )
		if in_data is FlowData.Data:
			entries.append( in_data )
	if entries.is_empty():
		if not is_ownerless_preview( ctx ):
			setError( "Input 'In' not connected" )
		set_output( 0, FlowData.Data.new() )
		return
	var result := merge_entries( entries, settings.mode, settings.promote_numeric_types )
	if not result.ok:
		setError( result.error )
		return
	set_output( 0, result.data )

## Merges `entries` (FlowData.Data, in order). Returns { ok, data } or { ok = false, error }.
static func merge_entries( entries : Array, mode : int, promote : bool ) -> Dictionary:
	var out := FlowData.Data.new()
	out.copy_meta_from( entries[0] )
	for k in range( 1, entries.size() ):
		var e : FlowData.Data = entries[k]
		for tag in e.tags:
			if not out.tags.has( tag ):
				out.tags.append( tag )
		for attr_name in e.data_attrs:
			out.data_attrs[attr_name] = e.data_attrs[attr_name].duplicate( true ) if e.data_attrs[attr_name] is Dictionary else e.data_attrs[attr_name]
	if mode == MergeAttributesSettings.eMode.ByIndex:
		return _merge_by_index( entries, out )
	return _merge_append( entries, out, promote )

static func _merge_append( entries : Array, out : FlowData.Data, promote : bool ) -> Dictionary:
	var names : Array = []
	var types := {}
	for k in range( entries.size() ):
		var e : FlowData.Data = entries[k]
		for stream_name in e.streams:
			var t : int = e.streams[stream_name].data_type
			if not types.has( stream_name ):
				names.append( stream_name )
				types[stream_name] = t
			elif types[stream_name] != t:
				var prev : int = types[stream_name]
				if promote and Ops.is_numeric_type( prev ) and Ops.is_numeric_type( t ):
					types[stream_name] = Ops.promote_numeric( prev, t )
				elif ( prev == FlowData.DataType.Vector4 and t == FlowData.DataType.Quaternion ) or ( prev == FlowData.DataType.Quaternion and t == FlowData.DataType.Vector4 ):
					types[stream_name] = FlowData.DataType.Vector4
				else:
					return { "ok": false, "error": "Attribute '%s' is %s in one input and %s in input %d" % [ stream_name, Ops.type_label( prev ), Ops.type_label( t ), k ] }
	for stream_name in names:
		var t : int = types[stream_name]
		var values : Array = []
		var default_value = _default_value( t )
		for e in entries:
			var n : int = e.size()
			var stream = e.streams.get( stream_name, null )
			if stream == null:
				for i in range( n ):
					values.append( default_value )
				continue
			var count : int = stream.container.size()
			for i in range( n ):
				if count == 0:
					values.append( default_value )
					continue
				var v = Ops.to_variant( stream.container[ FlowData.bcast_idx( count, i ) ], stream.data_type )
				if stream.data_type != t:
					var cast := Ops.cast_value( v, stream.data_type, t, {} )
					if not cast.ok:
						return cast
					v = cast.value
				values.append( v )
		var container = Ops.make_container( values, t )
		var err = out.registerStream( stream_name, container, t )
		if err != null:
			return { "ok": false, "error": str( err ) }
	return { "ok": true, "data": out }

static func _merge_by_index( entries : Array, out : FlowData.Data ) -> Dictionary:
	var n := 0
	for e in entries:
		n = maxi( n, e.size() )
	for k in range( entries.size() ):
		var e : FlowData.Data = entries[k]
		var size : int = e.size()
		if e.streams.size() > 0 and size != n and size != 1:
			return { "ok": false, "error": "ByIndex: input %d has %d entries; every input needs %d or 1" % [ k, size, n ] }
	for k in range( entries.size() ):
		var e : FlowData.Data = entries[k]
		for stream_name in e.streams:
			var stream = e.streams[stream_name]
			var count : int = stream.container.size()
			var container = FlowData.Data.newContainerOfType( stream.data_type )
			container.resize( n )
			if count > 0:
				for i in range( n ):
					container[i] = stream.container[ FlowData.bcast_idx( count, i ) ]
			if out.streams.has( stream_name ):
				push_warning( "Merge Attributes: input %d overrides attribute '%s'" % [ k, stream_name ] )
				out.delStream( stream_name )
			var err = out.registerStream( stream_name, container, stream.data_type )
			if err != null:
				return { "ok": false, "error": str( err ) }
	return { "ok": true, "data": out }

static func _default_value( t : int ):
	# Quaternion storage is zero filled; the type default is the identity.
	if t == FlowData.DataType.Quaternion:
		return Quaternion.IDENTITY
	var c = FlowData.Data.newContainerOfType( t )
	if c == null:
		return null
	c.resize( 1 )
	return Ops.to_variant( c[0], t )
