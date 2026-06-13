@tool
extends FlowNodeBase

const RotatorOpNodeSettings = preload("res://addons/flow_nodes_editor/nodes/rotator_op_settings.gd")

func _init():
	meta_node = {
		"title" : "Rotator Op",
		"settings" : RotatorOpNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Operates on point rotation: Combine, Invert, Lerp, or RotateAroundAxis.\nReads either the Euler 'rotation' stream or the 'rotation_quat' stream, converts through Quaternion internally, and writes back in the representation you select.",
		"aliases" : ["Rotator Op", "Quaternion Op", "Rotation Op"],
		"category" : "Spatial",
	}

func getTitle() -> String:
	return RotatorOpNodeSettings.eOperation.keys()[settings.operation]

# Reads the current rotation of every point as a Quaternion, preferring the
# quaternion stream when present, otherwise the Euler stream. Returns an Array
# of Quaternion of length num_elems, or null on error (error already set).
func _read_quats( in_data : FlowData.Data, num_elems : int ) -> Array:
	var quats : Array = []
	quats.resize( num_elems )
	if in_data.hasStream( FlowData.AttrRotationQuat ):
		var s = in_data.findStream( FlowData.AttrRotationQuat )
		if s == null or s.data_type != FlowData.DataType.Quaternion:
			setError( "'%s' stream is present but is not a Quaternion stream" % FlowData.AttrRotationQuat )
			return []
		var container : PackedVector4Array = s.container
		var sz : int = container.size()
		if sz != num_elems and sz != 1:
			setError( "'%s' has %d values but input has %d points" % [ FlowData.AttrRotationQuat, sz, num_elems ] )
			return []
		for i in range( num_elems ):
			quats[i] = FlowData.vec4ToQuat( container[ FlowData.bcast_idx( sz, i ) ] )
		return quats
	elif in_data.hasStream( FlowData.AttrRotation ):
		var s = in_data.findStream( FlowData.AttrRotation )
		if s == null or s.data_type != FlowData.DataType.Vector:
			setError( "'%s' stream is present but is not a Vector (Euler) stream" % FlowData.AttrRotation )
			return []
		var container : PackedVector3Array = s.container
		var sz : int = container.size()
		if sz != num_elems and sz != 1:
			setError( "'%s' has %d values but input has %d points" % [ FlowData.AttrRotation, sz, num_elems ] )
			return []
		for i in range( num_elems ):
			quats[i] = FlowData.eulerToQuat( container[ FlowData.bcast_idx( sz, i ) ] )
		return quats
	else:
		setError( "Input has no '%s' or '%s' rotation stream" % [ FlowData.AttrRotation, FlowData.AttrRotationQuat ] )
		return []

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return

	var num_elems : int = in_data.size()
	if num_elems == 0:
		set_output( 0, FlowData.Data.new() )
		return

	var quats := _read_quats( in_data, num_elems )
	if quats.is_empty():
		# _read_quats only returns empty after calling setError (num_elems == 0 is
		# handled above). Stay graceful in the editor preview, surface otherwise.
		if ctx.owner == null and Engine.is_editor_hint():
			set_output( 0, FlowData.Data.new() )
		return

	var op : int = settings.operation
	var operand_quat := FlowData.eulerToQuat( settings.operand_euler )
	var alpha : float = settings.alpha
	var axis : Vector3 = settings.axis
	var angle_rad : float = deg_to_rad( settings.angle_degrees )
	var axis_quat := Quaternion.IDENTITY
	if op == RotatorOpNodeSettings.eOperation.RotateAroundAxis:
		if axis.length() < 1e-8:
			setError( "RotateAroundAxis: axis can't be a zero vector" )
			return
		axis_quat = Quaternion( axis.normalized(), angle_rad )

	for i in range( num_elems ):
		var q : Quaternion = quats[i]
		match op:
			RotatorOpNodeSettings.eOperation.Combine:
				quats[i] = ( q * operand_quat ).normalized()
			RotatorOpNodeSettings.eOperation.Invert:
				quats[i] = q.inverse()
			RotatorOpNodeSettings.eOperation.Lerp:
				quats[i] = q.slerp( operand_quat, alpha ).normalized()
			RotatorOpNodeSettings.eOperation.RotateAroundAxis:
				quats[i] = ( axis_quat * q ).normalized()

	var out_data : FlowData.Data = in_data.duplicate()

	if settings.representation == RotatorOpNodeSettings.eRepresentation.Quaternion:
		# Write the quaternion stream; remove the Euler stream so the canonical
		# quaternion representation is unambiguous downstream.
		var out_quat := PackedVector4Array()
		out_quat.resize( num_elems )
		for i in range( num_elems ):
			out_quat[i] = FlowData.quatToVec4( quats[i] )
		out_data.delStream( FlowData.AttrRotation )
		var err = out_data.registerStream( FlowData.AttrRotationQuat, out_quat, FlowData.DataType.Quaternion )
		if err:
			setError( err )
			return
	else:
		# Euler representation (default). Write back the Euler stream and drop any
		# quaternion stream so the two don't disagree.
		var out_euler := PackedVector3Array()
		out_euler.resize( num_elems )
		for i in range( num_elems ):
			out_euler[i] = FlowData.quatToEuler( quats[i] )
		out_data.delStream( FlowData.AttrRotationQuat )
		var err = out_data.registerStream( FlowData.AttrRotation, out_euler, FlowData.DataType.Vector )
		if err:
			setError( err )
			return

	set_output( 0, out_data )
