@tool
extends FlowNodeBase

# UE PCG parity: Apply Scale To Bounds.
#
# Bounds model of this addon (see FlowData.Data.getEffectiveBounds):
#  - with explicit `bounds_min`/`bounds_max` streams, those are the point's
#    local bounds and `size` is a pure scale;
#  - without them, `size` is both the scale and the extent, i.e. the implicit
#    unscaled local bounds are (-0.5, 0.5) on every axis.
# This node multiplies the (explicit or implicit) local bounds by the scale,
# writes them to `bounds_min`/`bounds_max` and resets `size` to (1, 1, 1).
# For points without explicit bounds the world-space box is unchanged; for
# points with explicit bounds the box grows by the scale, as in Unreal.

func _init():
	meta_node = {
		"title" : "Apply Scale To Bounds",
		"settings" : ApplyScaleToBoundsNodeSettings,
		"aliases" : ["Apply Scale To Bounds", "Apply Scale to Bounds", "Bake Scale Into Bounds", "Reset Scale"],
		"category" : "Spatial",
		"pure" : true,
		"main_thread" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Moves each point's scale into its bounds: bounds_min/bounds_max are multiplied by the scale (the `size` stream)\nand the scale is reset to (1, 1, 1). Asymmetric bounds are preserved; a negative scale axis swaps min and max.\nPoints without bounds streams use the implicit (-0.5, 0.5) bounds, so their world box is unchanged.\nA missing `size` stream counts as scale 1.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return

	var out_data : FlowData.Data = in_data.duplicate()
	var n := in_data.size()

	var has_explicit : bool = in_data.hasStreamOfType( FlowData.AttrBoundsMin, FlowData.DataType.Vector ) \
		and in_data.hasStreamOfType( FlowData.AttrBoundsMax, FlowData.DataType.Vector ) \
		and in_data.getVector3Container( FlowData.AttrBoundsMin ).size() > 0 \
		and in_data.getVector3Container( FlowData.AttrBoundsMax ).size() > 0
	var explicit_min : PackedVector3Array = in_data.getVector3Container( FlowData.AttrBoundsMin ) if has_explicit else PackedVector3Array()
	var explicit_max : PackedVector3Array = in_data.getVector3Container( FlowData.AttrBoundsMax ) if has_explicit else PackedVector3Array()
	var sizes : PackedVector3Array = in_data.getVector3Container( FlowData.AttrSize )

	var new_min := PackedVector3Array()
	var new_max := PackedVector3Array()
	new_min.resize( n )
	new_max.resize( n )
	var half := Vector3( 0.5, 0.5, 0.5 )
	for i in range( n ):
		var base_min : Vector3 = explicit_min[ FlowData.bcast_idx( explicit_min.size(), i ) ] if has_explicit else -half
		var base_max : Vector3 = explicit_max[ FlowData.bcast_idx( explicit_max.size(), i ) ] if has_explicit else half
		var s : Vector3 = sizes[ FlowData.bcast_idx( sizes.size(), i ) ] if sizes.size() > 0 else Vector3.ONE
		var a : Vector3 = base_min * s
		var b : Vector3 = base_max * s
		new_min[i] = a.min( b )
		new_max[i] = a.max( b )

	var err = out_data.registerStream( FlowData.AttrBoundsMin, new_min, FlowData.DataType.Vector )
	if err:
		setError( err )
		return
	err = out_data.registerStream( FlowData.AttrBoundsMax, new_max, FlowData.DataType.Vector )
	if err:
		setError( err )
		return

	if settings.reset_scale and sizes.size() > 0:
		var ones := PackedVector3Array()
		ones.resize( sizes.size() )
		ones.fill( Vector3.ONE )
		err = out_data.registerStream( FlowData.AttrSize, ones, FlowData.DataType.Vector )
		if err:
			setError( err )
			return

	set_output( 0, out_data )
