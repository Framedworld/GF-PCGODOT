@tool
extends FlowNodeBase

# UE PCG parity: Create Points. Emits an explicit, hand-authored list of points
# (FlowPointEntry resources in settings.points): transform, bounds, density,
# steepness, seed and optional extra attributes.

func _init():
	meta_node = {
		"title" : "Create Points",
		"settings" : CreatePointsNodeSettings,
		"aliases" : ["Create Points", "Point List", "Manual Points", "Hand Placed Points"],
		"category" : "Sampler",
		"ins" : [],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Creates the points listed in the settings, in order: position, rotation (Euler degrees), scale (size),\nbounds_min/bounds_max, density, steepness, seed and extra attributes per point.\nSeed 0 derives the seed from the world position and the node seed. Local space places the points relative to the owner node.\nExtra attributes missing on some points get the type's default; Int and Float values of one name merge into Float.",
	}

static func _value_type( value ) -> FlowData.DataType:
	match typeof( value ):
		TYPE_BOOL:
			return FlowData.DataType.Bool
		TYPE_INT:
			return FlowData.DataType.Int
		TYPE_FLOAT:
			return FlowData.DataType.Float
		TYPE_STRING, TYPE_STRING_NAME:
			return FlowData.DataType.String
		TYPE_VECTOR3:
			return FlowData.DataType.Vector
		TYPE_COLOR:
			return FlowData.DataType.Color
		TYPE_QUATERNION, TYPE_VECTOR4:
			return FlowData.DataType.Quaternion
	if value is Resource:
		return FlowData.DataType.Resource
	return FlowData.DataType.Invalid

func _owner_transform( ctx : FlowData.EvaluationContext ) -> Transform3D:
	if settings.coordinate_space != CreatePointsNodeSettings.eCoordinateSpace.Local:
		return Transform3D.IDENTITY
	if ctx == null or ctx.owner == null or not is_instance_valid( ctx.owner ):
		return Transform3D.IDENTITY
	return ctx.owner.global_transform if ctx.owner.is_inside_tree() else ctx.owner.transform

func computeSceneFingerprint( ctx : FlowData.EvaluationContext ) -> Variant:
	if settings == null or settings.coordinate_space != CreatePointsNodeSettings.eCoordinateSpace.Local:
		return SCENE_INDEPENDENT
	return hash( _owner_transform( ctx ) )

func execute( ctx : FlowData.EvaluationContext ):
	var entries : Array = []
	for entry in settings.points:
		if entry != null:
			entries.append( entry )
	var n := entries.size()

	# Extra attribute schema: first appearance order, Int+Float merge to Float.
	var attr_order : Array = []
	var attr_types := {}
	for entry in entries:
		for key in entry.attributes:
			var attr_name := String( key ).strip_edges()
			if attr_name == "":
				continue
			if FlowData.CANONICAL_ATTRIBUTE_TYPES.has( StringName( attr_name ) ):
				setError( "Attribute '%s' is a point property; set it with the entry's own field" % attr_name )
				return
			var t := _value_type( entry.attributes[key] )
			if t == FlowData.DataType.Invalid:
				setError( "Attribute '%s' has an unsupported value type (%s)" % [ attr_name, type_string( typeof( entry.attributes[key] ) ) ] )
				return
			if not attr_types.has( attr_name ):
				attr_types[attr_name] = t
				attr_order.append( attr_name )
				continue
			var prev : int = attr_types[attr_name]
			if prev == t:
				continue
			var numeric := [ FlowData.DataType.Int, FlowData.DataType.Float ]
			if prev in numeric and t in numeric:
				attr_types[attr_name] = FlowData.DataType.Float
				continue
			setError( "Attribute '%s' has mixed types across points (%s and %s)" % [ attr_name, FlowData.DataType.find_key( prev ), FlowData.DataType.find_key( t ) ] )
			return

	var xform := _owner_transform( ctx )
	var owner_basis := xform.basis.orthonormalized()
	var owner_scale := xform.basis.get_scale()
	var node_seed := effective_seed()

	var output := FlowData.Data.new()
	output.addCommonStreams( n )
	var spos := output.getVector3Container( FlowData.AttrPosition )
	var srot := output.getVector3Container( FlowData.AttrRotation )
	var ssize := output.getVector3Container( FlowData.AttrSize )
	var sdensity := PackedFloat32Array()
	var sseed := PackedInt32Array()
	var sbmin := PackedVector3Array()
	var sbmax := PackedVector3Array()
	var ssteep := PackedFloat32Array()
	sdensity.resize( n )
	sseed.resize( n )
	sbmin.resize( n )
	sbmax.resize( n )
	ssteep.resize( n )
	for i in range( n ):
		var e : FlowPointEntry = entries[i]
		var world_pos : Vector3 = xform * e.position
		spos[i] = world_pos
		if xform == Transform3D.IDENTITY:
			srot[i] = e.rotation
			ssize[i] = e.scale
		else:
			srot[i] = FlowData.basisToEuler( owner_basis * FlowData.eulerToBasis( e.rotation ) )
			ssize[i] = e.scale * owner_scale
		sdensity[i] = clampf( e.density, 0.0, 1.0 )
		sseed[i] = e.seed if e.seed != 0 else FlowData.point_seed( world_pos, node_seed )
		sbmin[i] = e.bounds_min
		sbmax[i] = e.bounds_max
		ssteep[i] = clampf( e.steepness, 0.0, 1.0 )

	output.registerStream( FlowData.AttrDensity, sdensity, FlowData.DataType.Float )
	output.registerStream( FlowData.AttrSeed, sseed, FlowData.DataType.Int )
	if settings.write_bounds:
		output.registerStream( FlowData.AttrBoundsMin, sbmin, FlowData.DataType.Vector )
		output.registerStream( FlowData.AttrBoundsMax, sbmax, FlowData.DataType.Vector )
		output.registerStream( FlowData.AttrSteepness, ssteep, FlowData.DataType.Float )

	for attr_name in attr_order:
		var t : int = attr_types[attr_name]
		var container = FlowData.Data.newContainerOfType( t )
		container.resize( n )
		for i in range( n ):
			var attrs : Dictionary = entries[i].attributes
			var value = null
			for key in attrs:
				if String( key ).strip_edges() == attr_name:
					value = attrs[key]
					break
			if value == null:
				continue
			FlowData.Data.writeValue( container, i, value, t )
		var err = output.registerStream( attr_name, container, t )
		if err:
			setError( err )
			return

	set_output( 0, output )
