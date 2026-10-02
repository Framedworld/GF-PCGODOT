@tool
extends "res://addons/flow_nodes_editor/nodes/scan_nodes.gd"

# UE PCG parity: Get Property From Object Path. Reads properties of explicitly
# named objects (scene nodes or resources) into an attribute set, one row per
# object. Property paths and value typing follow Scan Nodes' import_properties
# (get_property_path is inherited from scan_nodes.gd): ":"-separated sub
# paths, StringName read as String, Bool/Int/Float/String/Vector/Color/Resource
# values kept, other types skipped.

func _init():
	meta_node = {
		"title" : "Get Property From Object Path",
		"settings" : GetPropertyFromObjectPathNodeSettings,
		"aliases" : ["Get Property From Object Path", "Get Property from Object Path", "Get Actor Property", "Read Property", "Get Resource Property"],
		"category" : "Input",
		"scans_scene" : true,
		"main_thread" : true,
		"pure" : false,
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Reads properties from the objects listed in 'object_paths' into an attribute set, one row per object.\nNode paths are resolved from the owner node (then its scene root); res://, uid:// and user:// paths load resources and need no owner.\nProperty paths use Scan Nodes' syntax (e.g. mesh:size) and name the attribute after their last segment.\nAn unresolved object is an error and its row is skipped; a property no object has is an error.",
	}

static func is_resource_path( path : String ) -> bool:
	return path.begins_with( "res://" ) or path.begins_with( "uid://" ) or path.begins_with( "user://" )

## The object at `path`, or null. Node paths need a valid owner.
func resolve_object( ctx : FlowData.EvaluationContext, path : String ) -> Object:
	if is_resource_path( path ):
		if not ResourceLoader.exists( path ):
			return null
		return load( path )
	if ctx == null or ctx.owner == null or not is_instance_valid( ctx.owner ):
		return null
	var owner_node : Node = ctx.owner
	if path.begins_with( "/" ) and not owner_node.is_inside_tree():
		return null
	var found : Node = owner_node.get_node_or_null( NodePath( path ) )
	if found == null and owner_node.owner != null and not path.begins_with( "/" ):
		found = owner_node.owner.get_node_or_null( NodePath( path ) )
	return found

func _paths() -> Array:
	var out : Array = []
	for raw in settings.object_paths:
		var p := String( raw ).strip_edges()
		if p != "":
			out.append( p )
	return out

func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	var nodes : Array = []
	var extra : Array = []
	for path in _paths():
		var obj := resolve_object( ctx, path )
		extra.append( path )
		if obj is Node:
			nodes.append( obj )
		for prop_path in settings.property_paths:
			if prop_path:
				extra.append( get_property_path( obj, String( prop_path ).split( ":" ) ) if obj != null else null )
	return hashSceneNodesForFingerprint( ctx, nodes, extra )

static func _import_value( value ) -> Array:
	# [value, data_type] with scan_nodes' conversions; data_type Invalid = skip.
	var data_type := getFlowDataTypeFromObject( value )
	if data_type == FlowData.DataType.Invalid and typeof( value ) == TYPE_STRING_NAME:
		return [ String( value ), FlowData.DataType.String ]
	return [ value, data_type ]

func execute( ctx : FlowData.EvaluationContext ):
	var paths := _paths()
	var objects : Array = []
	var row_paths := PackedStringArray()
	var needs_owner := false
	var errors : Array = []
	for path in paths:
		if not is_resource_path( path ) and ( ctx == null or ctx.owner == null or not is_instance_valid( ctx.owner ) ):
			needs_owner = true
			continue
		var obj := resolve_object( ctx, path )
		if obj == null:
			errors.append( "Object '%s' not found" % path )
			continue
		objects.append( obj )
		row_paths.append( path )
	if needs_owner and reportMissingOwner( ctx ):
		errors.push_front( err )

	var rows := objects.size()
	var output := FlowData.Data.new()
	output.kind = FlowData.Kind.AttrSet
	var path_attr : String = String( settings.path_attribute ).strip_edges()
	if path_attr != "":
		var err = output.registerStream( path_attr, row_paths, FlowData.DataType.String )
		if err:
			setError( err )
			return

	for prop_path in settings.property_paths:
		if not prop_path:
			continue
		var parts := String( prop_path ).split( ":" )
		var stream_name : String = parts[ parts.size() - 1 ]
		var container = null
		var stream_type : int = FlowData.DataType.Invalid
		for row in range( rows ):
			var raw = get_property_path( objects[row], parts )
			if raw == null:
				continue
			var typed := _import_value( raw )
			if typed[1] == FlowData.DataType.Invalid:
				continue
			if container == null:
				stream_type = typed[1]
				container = FlowData.Data.newContainerOfType( stream_type )
				container.resize( rows )
			elif typed[1] != stream_type:
				push_warning( "Get Property From Object Path: '%s' on '%s' has type %d but earlier rows have type %d; row left at its default" % [ prop_path, row_paths[row], typed[1], stream_type ] )
				continue
			FlowData.Data.writeValue( container, row, typed[0], stream_type )
		if container == null:
			if rows > 0:
				errors.append( "Property '%s' not found (or of an unsupported type) on any object" % prop_path )
			continue
		var err = output.registerStream( stream_name, container, stream_type )
		if err:
			errors.append( err )

	if not errors.is_empty():
		setError( "; ".join( errors ) )
	set_output( 0, output )
