@tool
extends FlowNodeBase

# UE PCG parity: Get Spline Data. Collects Path3D nodes and outputs spline
# spatial data (FlowSplineShape on Data.shape, zero points) instead of the
# `node` reference stream scan_splines emits. Shape-aware consumers
# (sample_spline, difference/intersection/union, to_point, filter_data_by_type,
# get_bounds) read the shape; scan_splines keeps working for legacy graphs.
# Each Data also carries @data attributes: spline_length, spline_closed, source.

const GetSplineDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_spline_data_settings.gd")

func _init():
	meta_node = {
		"title" : "Get Spline Data",
		"settings" : GetSplineDataSettings,
		"aliases" : ["Get Spline Data", "Spline Data"],
		"category" : "Input",
		"scans_scene" : true,
		"ins" : [],
		"outs" : [{ "label" : "Out", "data_type" : FlowData.DataType.NodePath }],	# pin colour of the legacy Path3D stream
		"tooltip" : "Collects Path3D nodes as spline data (a copied curve + transform per Data).\nFeeds Sample Spline, To Point and the spatial set operations (a spline acts as a tube of 'tube_half_width').",
	}

func _paths( ctx : FlowData.EvaluationContext ) -> Array:
	var owner_node = ctx.owner if ctx != null else null
	return FlowSpatialSources.collect( owner_node, str( getSettingValue( ctx, "group_name", "" ) ), bool( getSettingValue( ctx, "recursive", true ) ), settings.required_meta_bool,
		func( n ): return n is Path3D and n.curve != null )

func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	if ctx == null or ctx.owner == null:
		return null
	return FlowSpatialSources.fingerprint( ctx.owner, _paths( ctx ) )

static func spline_data( shape : FlowSplineShape, source : String ) -> FlowData.Data:
	var d := FlowData.Data.from_shape( shape )
	d.set_data_attr( "spline_length", shape.get_length(), FlowData.DataType.Float )
	d.set_data_attr( "spline_closed", shape.closed, FlowData.DataType.Bool )
	d.set_data_attr( "source", source, FlowData.DataType.String )
	return d

func execute( ctx : FlowData.EvaluationContext ):
	if reportMissingOwner( ctx ) or ctx == null or ctx.owner == null:
		var empty := FlowData.Data.new()
		empty.kind = FlowData.Kind.Spline
		set_output( 0, empty )
		return
	var half_width : float = getSettingValue( ctx, "tube_half_width", 1.0 )
	var steep : float = getSettingValue( ctx, "tube_steepness", 1.0 )
	var shapes : Array = []
	var names : Array = []
	for path in _paths( ctx ):
		var s := FlowSplineShape.from_path( path, half_width, steep )
		if s == null:
			continue
		shapes.append( s )
		names.append( String( path.name ) )
	if shapes.is_empty():
		var none := FlowData.Data.new()
		none.kind = FlowData.Kind.Spline
		set_output( 0, none )
		return
	if settings.output_mode == GetSplineDataSettings.eOutputMode.Merged:
		# Union by maximum (UE union density): a Binary union would be 1 wherever any
		# operand is > 0 and erase the steepness falloff of soft sources.
		var merged := FlowData.Data.from_shape( FlowCompositeShape.union_of( shapes, FlowSpatial.DENSITY_MINIMUM ) )
		merged.set_data_attr( "spline_count", shapes.size(), FlowData.DataType.Int )
		set_output( 0, merged )
		return
	for i in range( shapes.size() ):
		set_output( 0, spline_data( shapes[i], names[i] ) )
