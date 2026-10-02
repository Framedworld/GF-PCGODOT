@tool
extends FlowNodeBase

const CopyAttributeSettings = preload("res://addons/flow_nodes_editor/nodes/copy_attribute_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

const POINT_PROPERTIES := [ "position", "rotation", "rotation_quat", "size", "bounds_min", "bounds_max", "steepness" ]

func _init():
	meta_node = {
		"title" : "Copy Attribute",
		"settings" : CopyAttributeSettings,
		"ins" : [{ "label": "Target", "multiple_connections" : false }, { "label": "Source", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Copies attributes from Source onto Target, keeping their types (UE Copy Attribute / Transfer Attribute).\n" +
			"ByIndex: point i gets source entry i (or the single source entry). ByMatchAttribute: the first source entry with an equal key.\n" +
			"NearestPoint: the nearest source point by position (optional max distance).\n" +
			"Unmatched points keep the target's existing value of that attribute, or the type's default (0, empty, identity).",
		"aliases" : ["Copy Attribute", "Copy Attributes", "Transfer Attribute"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Copy Attribute (%s)" % CopyAttributeSettings.eMode.keys()[ clampi( settings.mode, 0, CopyAttributeSettings.eMode.size() - 1 ) ]

func execute( ctx : FlowData.EvaluationContext ):
	var target : FlowData.Data = require_input( 0, ctx, "Input 'Target'" )
	if target == null:
		return
	var source = get_optional_input( 1 )
	if not ( source is FlowData.Data ):
		if is_ownerless_preview( ctx ):
			set_output( 0, target.duplicate() )
			return
		setError( "Input 'Source' not connected" )
		return
	var nt : int = target.size()
	var out_data : FlowData.Data = target.duplicate()
	if nt == 0:
		set_output( 0, out_data )
		return
	var ns : int = source.size()

	var mapping := _build_mapping( target, source, nt, ns )
	if mapping.is_empty():
		return	# error already set

	var names : Array = []
	if settings.copy_all_attributes:
		for stream_name in source.streams:
			if not settings.include_point_properties and POINT_PROPERTIES.has( String( stream_name ) ):
				continue
			names.append( [ String( stream_name ), String( stream_name ) ] )
	else:
		var src_stream = Ops.find_stream( source, settings.source_attribute )
		if src_stream == null:
			setError( "Source attribute '%s' not found" % settings.source_attribute )
			return
		names.append( [ settings.source_attribute, Ops.resolve_output_name( settings.target_attribute, String( src_stream.name ) ) ] )

	for pair in names:
		var err := _copy_one( out_data, source, pair[0], pair[1], mapping, nt )
		if err != "":
			setError( err )
			return

	if settings.out_matched_attribute.strip_edges() != "":
		var matched : Array = []
		for j in mapping:
			matched.append( j >= 0 )
		var err := Ops.write_stream( out_data, settings.out_matched_attribute.strip_edges(), matched, FlowData.DataType.Bool )
		if err != "":
			setError( err )
			return
	set_output( 0, out_data )

## Source entry index per target point, -1 when unmatched. Empty on error.
func _build_mapping( target : FlowData.Data, source : FlowData.Data, nt : int, ns : int ) -> PackedInt32Array:
	var mapping := PackedInt32Array()
	mapping.resize( nt )
	mapping.fill( -1 )
	match settings.mode:
		CopyAttributeSettings.eMode.ByIndex:
			if ns != nt and ns != 1:
				setError( "ByIndex needs as many source entries as target points, or one (got %d source, %d target)" % [ ns, nt ] )
				return PackedInt32Array()
			for i in range( nt ):
				mapping[i] = i if ns == nt else 0
		CopyAttributeSettings.eMode.ByMatchAttribute:
			var src_keys := Ops.read_values( source, settings.match_attribute, ns, "Source match attribute" )
			if not src_keys.ok:
				setError( src_keys.error )
				return PackedInt32Array()
			var target_key_name := Ops.resolve_output_name( settings.target_match_attribute, settings.match_attribute )
			var dst_keys := Ops.read_values( target, target_key_name, nt, "Target match attribute" )
			if not dst_keys.ok:
				setError( dst_keys.error )
				return PackedInt32Array()
			var both_int : bool = not Ops.is_real_type( src_keys.data_type ) and not Ops.is_real_type( dst_keys.data_type )
			var lut := {}
			for j in range( ns ):
				var k = _key( src_keys.values[j], src_keys.data_type, both_int )
				if not lut.has( k ):
					lut[k] = j
			for i in range( nt ):
				mapping[i] = lut.get( _key( dst_keys.values[i], dst_keys.data_type, both_int ), -1 )
		CopyAttributeSettings.eMode.NearestPoint:
			var src_pos = source.getContainerChecked( FlowData.AttrPosition, FlowData.DataType.Vector )
			var dst_pos = target.getContainerChecked( FlowData.AttrPosition, FlowData.DataType.Vector )
			if src_pos == null or dst_pos == null:
				setError( "NearestPoint needs a Vector 'position' stream on both Target and Source" )
				return PackedInt32Array()
			if ns == 0 or src_pos.size() == 0:
				return mapping
			if dst_pos.size() == 1 and nt > 1:
				# Broadcast (length-1) target position: one query per point.
				var expanded := PackedVector3Array()
				expanded.resize( nt )
				expanded.fill( dst_pos[0] )
				dst_pos = expanded
			var nearest := _nearest_indices( src_pos, dst_pos )
			var max_d : float = settings.max_distance
			for i in range( nt ):
				var j : int = nearest[i]
				if max_d > 0.0 and ( dst_pos[i] as Vector3 ).distance_to( src_pos[j] ) > max_d:
					continue
				mapping[i] = j
	return mapping

static func _key( value, data_type : int, both_int : bool ):
	if Ops.is_numeric_type( data_type ):
		return int( value ) if both_int else float( value )
	return value

## Nearest source index per target position. Uses the native KD-tree when the
## extension is loaded, else a brute-force scan (first nearest wins on ties).
static func _nearest_indices( src : PackedVector3Array, dst : PackedVector3Array ) -> PackedInt32Array:
	if ClassDB.class_exists( "GDKdTree" ):
		var tree = ClassDB.instantiate( "GDKdTree" )
		tree.set_points( src )
		return tree.find_nearest_indices( dst )
	var out := PackedInt32Array()
	out.resize( dst.size() )
	for i in range( dst.size() ):
		var best := -1
		var best_d := INF
		for j in range( src.size() ):
			var d := dst[i].distance_squared_to( src[j] )
			if d < best_d:
				best_d = d
				best = j
		out[i] = best
	return out

func _copy_one( out_data : FlowData.Data, source : FlowData.Data, src_name : String, dst_name : String, mapping : PackedInt32Array, nt : int ) -> String:
	var src_stream = Ops.find_stream( source, src_name )
	if src_stream == null:
		return "Source attribute '%s' not found" % src_name
	var data_type : int = src_stream.data_type
	var src_container = src_stream.container
	var src_count : int = src_container.size()
	var container
	var existing = out_data.streams.get( dst_name, null )
	if existing != null and existing.data_type == data_type and existing.container.size() == nt:
		container = existing.container.duplicate()
	else:
		container = FlowData.Data.newContainerOfType( data_type )
		if container == null:
			return "Can't copy attribute '%s' of type %s" % [ src_name, Ops.type_label( data_type ) ]
		container.resize( nt )
		# The Quaternion default is the identity rotation, not a zero Vector4.
		if data_type == FlowData.DataType.Quaternion:
			container.fill( Vector4( 0, 0, 0, 1 ) )
		# A broadcast (length-1) target stream: unmatched points keep its value.
		if existing != null and existing.data_type == data_type and existing.container.size() == 1:
			for i in range( nt ):
				container[i] = existing.container[0]
	for i in range( nt ):
		var j : int = mapping[i]
		if j < 0 or src_count == 0:
			continue
		var src_idx := FlowData.bcast_idx( src_count, j )
		if src_idx >= src_count:
			continue
		container[i] = src_container[ src_idx ]
	if existing != null and existing.data_type != data_type:
		var canonical := FlowData.canonical_type_error( dst_name, data_type )
		if canonical != "":
			return canonical
		out_data.delStream( dst_name )
	var err = out_data.registerStream( dst_name, container, data_type )
	return "" if err == null else str( err )
