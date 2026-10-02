@tool
extends FlowNodeBase

# UE PCG parity: Reset Point Center. Moves each point's pivot to a normalized
# location inside its bounds and shifts bounds_min/bounds_max the other way,
# so the box stays where it was. Bounds come from Data.getEffectiveBounds();
# the offset is applied in the point's rotated frame (scale is not applied,
# matching how explicit bounds are read everywhere else in the addon).

const SplitPoints = preload("res://addons/flow_nodes_editor/nodes/split_points.gd")

func _init():
	meta_node = {
		"title" : "Reset Point Center",
		"settings" : ResetPointCenterNodeSettings,
		"aliases" : ["Reset Point Center", "Recenter Points", "Set Pivot", "Center Pivot"],
		"category" : "Spatial",
		"pure" : true,
		"main_thread" : false,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Moves each point's position to a normalized location inside its bounds (0 = min corner, 1 = max corner, 0.5 = center)\nand offsets bounds_min/bounds_max so the bounds box stays in place. Always writes explicit bounds; size is unchanged.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input( 0, ctx, "Input 'In'" )
	if in_data == null:
		return

	var n := in_data.size()
	var out_data : FlowData.Data = in_data.duplicate()
	var positions : PackedVector3Array = in_data.getVector3Container( FlowData.AttrPosition )
	if n > 0 and positions.size() == 0:
		setError( "Input must provide a position stream" )
		return

	var loc : Vector3 = getSettingValue( ctx, "point_center_location", settings.point_center_location )
	var eff := in_data.getEffectiveBounds()
	var lo_arr : PackedVector3Array = eff.min
	var hi_arr : PackedVector3Array = eff.max
	var new_pos := PackedVector3Array()
	var new_min := PackedVector3Array()
	var new_max := PackedVector3Array()
	new_pos.resize( n )
	new_min.resize( n )
	new_max.resize( n )
	for i in range( n ):
		var lo : Vector3 = lo_arr[i]
		var hi : Vector3 = hi_arr[i]
		var pivot : Vector3 = lo + ( hi - lo ) * loc
		var p : Vector3 = positions[ FlowData.bcast_idx( positions.size(), i ) ]
		new_pos[i] = p + SplitPoints.rotation_basis_at( in_data, i ) * pivot
		new_min[i] = lo - pivot
		new_max[i] = hi - pivot

	var err = null
	if n > 0:
		err = out_data.registerStream( FlowData.AttrPosition, new_pos, FlowData.DataType.Vector )
	if err == null:
		err = out_data.registerStream( FlowData.AttrBoundsMin, new_min, FlowData.DataType.Vector )
	if err == null:
		err = out_data.registerStream( FlowData.AttrBoundsMax, new_max, FlowData.DataType.Vector )
	if err:
		setError( err )
		return
	set_output( 0, out_data )
