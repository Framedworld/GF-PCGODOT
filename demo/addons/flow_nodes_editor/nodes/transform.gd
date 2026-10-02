@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Transform",
		"category" : "Spatial",
		"settings" : TransformNodeSettings,
		"ins" : [{ "label": "In" }], 
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Applies the random translation/rotation/scale to each point",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = get_input(0)
	if in_data == null:
		if is_ownerless_preview(ctx):
			set_output(0, FlowData.Data.new())
			return
		setError("Input 'In' is not connected")
		return null
	var out_data : FlowData.Data = in_data.duplicate()
	if not out_data.hasStream(FlowData.AttrPosition) or not out_data.hasStream(FlowData.AttrRotation) or not out_data.hasStream(FlowData.AttrSize):
		if is_ownerless_preview(ctx):
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide position, rotation, and size streams")
		return
	var spos = out_data.cloneStream( FlowData.AttrPosition )
	var srot = out_data.cloneStream( FlowData.AttrRotation )
	var ssizes = out_data.cloneStream( FlowData.AttrSize )
	if spos == null or srot == null or ssizes == null:
		if is_ownerless_preview(ctx):
			set_output(0, FlowData.Data.new())
			return
		setError("Input must provide position, rotation, and size streams")
		return
	var offset_min : Vector3 = getSettingValue( ctx, "offset_min" )
	var offset_max : Vector3 = getSettingValue( ctx, "offset_max" )
	var rotation_min : Vector3 = getSettingValue( ctx, "rotation_min" )
	var rotation_max : Vector3 = getSettingValue( ctx, "rotation_max" )
	var scale_min : Vector3 = getSettingValue( ctx, "scale_min" )
	var scale_max : Vector3 = getSettingValue( ctx, "scale_max" )
	var uniform_scale : bool = getSettingValue( ctx, "uniform_scale" )
	var rotation_local_space : bool = getSettingValue( ctx, "rotation_local_space" )
	# Per-point seeded randomness (UE parity): each point's random TRS is derived
	# from its own seed/position, so the result is stable under reordering and
	# upstream count changes instead of depending on the node-global RNG draw order.
	var point_seeds = out_data.getContainerChecked( FlowData.AttrSeed, FlowData.DataType.Int )
	if point_seeds != null and point_seeds.size() != spos.size() and point_seeds.size() != 1:
		point_seeds = null
	var node_seed : int = effective_seed()
	var prng := RandomNumberGenerator.new()
	# Loop invariants, and the bodies of FlowData.resolve_seed, point_seed,
	# eulerToBasis and basisToEuler inlined: the same expressions on the same
	# values (bit-identical), without four static calls per point.
	var seeds : PackedInt32Array = point_seeds if point_seeds != null else PackedInt32Array()
	var seeds_size : int = seeds.size()
	var offset_range : Vector3 = offset_max - offset_min
	var rotation_range : Vector3 = rotation_max - rotation_min
	var scale_range : Vector3 = scale_max - scale_min
	var scale_range_x : float = scale_max.x - scale_min.x
	var count : int = spos.size()
	for i in count:
		# Seed from the point's input position (before we move it) so the draw is deterministic.
		if seeds_size > 0:
			prng.seed = int( seeds[i if seeds_size > 1 else 0] ) ^ node_seed
		else:
			var pos : Vector3 = spos[i if count > 1 else 0]
			prng.seed = hash( [ int( round( pos.x * 1000.0 ) ), int( round( pos.y * 1000.0 ) ), int( round( pos.z * 1000.0 ) ), node_seed ] ) & 0x7fffffff
		var amount_pos = Vector3( prng.randf(), prng.randf(), prng.randf() )
		var euler : Vector3 = srot[i]
		var basis := Basis.from_euler( Vector3( deg_to_rad( euler.x ), deg_to_rad( euler.y ), deg_to_rad( euler.z ) ) )
		spos[i] += basis * (offset_min + offset_range * amount_pos)
		var amount_rot = Vector3( prng.randf(), prng.randf(), prng.randf() )
		if rotation_local_space:
			var delta_rot : Vector3 = rotation_min + rotation_range * amount_rot
			var delta_basis := Basis.from_euler( Vector3( deg_to_rad( delta_rot.x ), deg_to_rad( delta_rot.y ), deg_to_rad( delta_rot.z ) ) )
			var e : Vector3 = ( basis * delta_basis ).get_euler()
			srot[i] = Vector3( rad_to_deg( e.x ), rad_to_deg( e.y ), rad_to_deg( e.z ) )
		else:
			srot[i] += rotation_min + rotation_range * amount_rot
		if uniform_scale:
			var amount_scale = prng.randf()
			ssizes[i] *= scale_min.x + scale_range_x * amount_scale
		else:
			var amount_scale = Vector3( prng.randf(), prng.randf(), prng.randf() )
			ssizes[i] *= scale_min + scale_range * amount_scale
	set_output( 0, out_data )
