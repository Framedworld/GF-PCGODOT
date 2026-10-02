@tool
extends FlowNodeBase

# UE PCG parity: Split Points.
#
# Every input point becomes two: the part of its local bounds box before the
# cut ("Before Split") and the part after it ("After Split"). The cut is a
# plane across `split_axis` at `split_position` (0 = bounds min, 1 = bounds max).
# Bounds come from Data.getEffectiveBounds(): explicit bounds_min/bounds_max
# when present, otherwise the symmetric box derived from `size`.

## Point properties kept when inherit_attributes is off.
const POINT_PROPERTY_STREAMS := [
	&"position", &"rotation", &"rotation_quat", &"size", &"bounds_min", &"bounds_max",
	&"density", &"seed", &"steepness", &"normal",
]

func _init():
	meta_node = {
		"title" : "Split Points",
		"settings" : SplitPointsNodeSettings,
		"aliases" : ["Split Points", "Slice Points", "Cut Points", "Split Bounds"],
		"category" : "Spatial",
		"pure" : true,
		"main_thread" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Before Split" }, { "label" : "After Split" }],
		"tooltip" : "Splits every point in two along a local axis of its bounds at a 0..1 ratio.\nKeepTransform (Unreal): both halves keep the point's transform and get the matching bounds_min/bounds_max.\nRecenter: each half moves to the center of its box; points without bounds streams get their size scaled on the split axis instead.\nOptional per-point ratio attribute, side (0/1) and fraction attributes, and attribute inheritance toggle.",
	}

## Orthonormal rotation of point `i` (rotation_quat wins over Euler rotation,
## both broadcast-aware); identity when the Data has no rotation.
static func rotation_basis_at( data : FlowData.Data, i : int ) -> Basis:
	var quats = data.getContainerChecked( FlowData.AttrRotationQuat, FlowData.DataType.Quaternion )
	if quats != null and quats.size() > 0:
		var q : Vector4 = quats[ FlowData.bcast_idx( quats.size(), i ) ]
		return Basis( FlowData.vec4ToQuat( q ).normalized() )
	var eulers = data.getContainerChecked( FlowData.AttrRotation, FlowData.DataType.Vector )
	if eulers != null and eulers.size() > 0:
		return FlowData.eulerToBasis( eulers[ FlowData.bcast_idx( eulers.size(), i ) ] ).orthonormalized()
	return Basis.IDENTITY

## True when the Data carries non-empty Vector bounds_min AND bounds_max.
static func has_explicit_bounds( data : FlowData.Data ) -> bool:
	return data.getVector3Container( FlowData.AttrBoundsMin ).size() > 0 \
		and data.getVector3Container( FlowData.AttrBoundsMax ).size() > 0

## Numeric read of `stream` at point `i` (broadcast-aware), or `fallback`.
static func numeric_at( stream, i : int, fallback : float ) -> float:
	if stream == null or stream.container.size() == 0:
		return fallback
	var v = stream.container[ FlowData.bcast_idx( stream.container.size(), i ) ]
	if v is float or v is int or v is bool:
		return float( v )
	return fallback

func _strip_attributes( data : FlowData.Data ) -> void:
	for stream_name in data.streams.keys():
		if not ( StringName( stream_name ) in POINT_PROPERTY_STREAMS ):
			data.delStream( stream_name )

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		if num_generated_bulks > 0 and generated_bulks[num_generated_bulks - 1].size() == 1:
			set_output( 1, FlowData.Data.new() )
		return

	var n := in_data.size()
	var axis : int = int( settings.split_axis )
	var mode : int = int( settings.mode )
	var default_ratio : float = clampf( float( getSettingValue( ctx, "split_position", settings.split_position ) ), 0.0, 1.0 )

	var ratio_stream = null
	var ratio_attr : String = String( settings.split_position_attribute ).strip_edges()
	if ratio_attr != "" and n > 0:
		ratio_stream = in_data.findStream( ratio_attr )
		if ratio_stream == null:
			setError( "Split position attribute '%s' not found" % ratio_attr )
			return
		if not ( ratio_stream.data_type in [ FlowData.DataType.Float, FlowData.DataType.Int, FlowData.DataType.Bool ] ):
			setError( "Split position attribute '%s' must be numeric (Float, Int or Bool)" % ratio_attr )
			return

	var positions : PackedVector3Array = in_data.getVector3Container( FlowData.AttrPosition )
	if mode == SplitPointsNodeSettings.eMode.Recenter and n > 0 and positions.size() == 0:
		setError( "Recenter mode needs a position stream" )
		return

	var before : FlowData.Data = in_data.duplicate()
	var after : FlowData.Data = in_data.duplicate()
	if not settings.inherit_attributes:
		_strip_attributes( before )
		_strip_attributes( after )

	var explicit := has_explicit_bounds( in_data )
	var eff := in_data.getEffectiveBounds()
	var bmin : PackedVector3Array = eff.min
	var bmax : PackedVector3Array = eff.max

	var halves := [ before, after ]
	var fractions := [ PackedFloat32Array(), PackedFloat32Array() ]
	var new_mins := [ PackedVector3Array(), PackedVector3Array() ]
	var new_maxs := [ PackedVector3Array(), PackedVector3Array() ]
	var new_pos := [ PackedVector3Array(), PackedVector3Array() ]
	var new_size := [ PackedVector3Array(), PackedVector3Array() ]
	for side in range( 2 ):
		fractions[side].resize( n )
		new_mins[side].resize( n )
		new_maxs[side].resize( n )
		new_pos[side].resize( n )
		new_size[side].resize( n )

	var sizes : PackedVector3Array = in_data.getVector3Container( FlowData.AttrSize )
	for i in range( n ):
		var r : float = clampf( numeric_at( ratio_stream, i, default_ratio ), 0.0, 1.0 )
		var lo : Vector3 = bmin[i]
		var hi : Vector3 = bmax[i]
		var cut : float = lo[axis] + ( hi[axis] - lo[axis] ) * r
		var before_max := hi
		before_max[axis] = cut
		var after_min := lo
		after_min[axis] = cut
		var boxes := [ [ lo, before_max ], [ after_min, hi ] ]
		fractions[0][i] = r
		fractions[1][i] = 1.0 - r
		var p : Vector3 = positions[ FlowData.bcast_idx( positions.size(), i ) ] if positions.size() > 0 else Vector3.ZERO
		var s : Vector3 = sizes[ FlowData.bcast_idx( sizes.size(), i ) ] if sizes.size() > 0 else Vector3.ONE
		for side in range( 2 ):
			var box_lo : Vector3 = boxes[side][0]
			var box_hi : Vector3 = boxes[side][1]
			if mode == SplitPointsNodeSettings.eMode.KeepTransform:
				new_mins[side][i] = box_lo
				new_maxs[side][i] = box_hi
			else:
				var center : Vector3 = ( box_lo + box_hi ) * 0.5
				new_pos[side][i] = p + rotation_basis_at( in_data, i ) * center
				var half_ext : Vector3 = ( box_hi - box_lo ) * 0.5
				new_mins[side][i] = -half_ext
				new_maxs[side][i] = half_ext
				var scaled := s
				scaled[axis] = s[axis] * fractions[side][i]
				new_size[side][i] = scaled

	for side in range( 2 ):
		var data : FlowData.Data = halves[side]
		var err = null
		if mode == SplitPointsNodeSettings.eMode.KeepTransform or explicit:
			err = data.registerStream( FlowData.AttrBoundsMin, new_mins[side], FlowData.DataType.Vector )
			if err == null:
				err = data.registerStream( FlowData.AttrBoundsMax, new_maxs[side], FlowData.DataType.Vector )
		if err == null and mode == SplitPointsNodeSettings.eMode.Recenter:
			if n > 0 or data.hasStream( FlowData.AttrPosition ):
				err = data.registerStream( FlowData.AttrPosition, new_pos[side], FlowData.DataType.Vector )
			if err == null and not explicit and ( n > 0 or data.hasStream( FlowData.AttrSize ) ):
				err = data.registerStream( FlowData.AttrSize, new_size[side], FlowData.DataType.Vector )
		var side_attr : String = String( settings.side_attribute ).strip_edges()
		if err == null and side_attr != "":
			var side_values := PackedInt32Array()
			side_values.resize( n )
			side_values.fill( side )
			err = data.registerStream( side_attr, side_values, FlowData.DataType.Int )
		var fraction_attr : String = String( settings.fraction_attribute ).strip_edges()
		if err == null and fraction_attr != "":
			err = data.registerStream( fraction_attr, fractions[side], FlowData.DataType.Float )
		if err:
			setError( err )
			return

	set_output( 0, before )
	set_output( 1, after )
