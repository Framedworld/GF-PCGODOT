@tool
extends FlowNodeBase

const TransformOpSettings = preload("res://addons/flow_nodes_editor/nodes/transform_op_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Transform Op",
		"settings" : TransformOpSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Transform attribute operations: Compose (apply A then B, UE order), Invert, Lerp (slerped rotation),\n" +
			"TransformPosition / InverseTransformPosition / TransformDirection of a Vector attribute B,\n" +
			"and ApplyToPoints, which moves every point by A (writes position, rotation, size).",
		"aliases" : ["Transform Op", "Attribute Transform Op"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Transform %s" % TransformOpSettings.eOperation.keys()[ clampi( settings.operation, 0, TransformOpSettings.eOperation.size() - 1 ) ]

func execute( ctx : FlowData.EvaluationContext ):
	var D := FlowData.DataType
	var E := TransformOpSettings.eOperation
	var in_a : FlowData.Data = require_input( 0, ctx, "Input A" )
	if in_a == null:
		return
	var n : int = in_a.size()
	var out_data : FlowData.Data = in_a.duplicate()
	if n == 0:
		set_output( 0, out_data )
		return
	var read_a := Ops.read_values( in_a, settings.in_nameA, n, "Input A" )
	if not read_a.ok:
		setError( read_a.error )
		return
	if read_a.data_type != D.Transform:
		setError( "Input A '%s' is %s; Transform Op needs a Transform attribute (see Make Transform Attribute)" % [ settings.in_nameA, Ops.type_label( read_a.data_type ) ] )
		return
	var op : int = settings.operation
	var vector_b : bool = op == E.TransformPosition or op == E.InverseTransformPosition or op == E.TransformDirection

	var b_values : Array = []
	if settings.usesB():
		if settings.use_constant_b:
			var cb : Transform3D = settings.constant_b
			b_values = Ops.constant_values( cb.origin if vector_b else cb, n )
		else:
			var read_b := Ops.read_operand( in_a, get_optional_input( 1 ), settings.in_nameB, n, "Input B" )
			if not read_b.ok:
				setError( read_b.error )
				return
			var want : int = D.Vector if vector_b else D.Transform
			if read_b.data_type != want:
				setError( "Input B '%s' is %s; this operation needs a %s" % [ settings.in_nameB, Ops.type_label( read_b.data_type ), Ops.type_label( want ) ] )
				return
			b_values = read_b.values
	var c_values : Array = []
	if op == E.Lerp:
		if settings.in_nameC.strip_edges() == "":
			c_values = Ops.constant_values( settings.constant_c, n )
		else:
			var read_c := Ops.read_operand( in_a, get_optional_input( 1 ), settings.in_nameC, n, "Input C" )
			if not read_c.ok:
				setError( read_c.error )
				return
			if not Ops.is_numeric_type( read_c.data_type ):
				setError( "Input C '%s' must be numeric" % settings.in_nameC )
				return
			c_values = read_c.values

	if op == E.ApplyToPoints:
		_apply_to_points( out_data, read_a.values, n )
		return

	var results : Array = []
	results.resize( n )
	for i in range( n ):
		var a : Transform3D = read_a.values[i]
		match op:
			E.Compose:
				var b : Transform3D = b_values[i]
				results[i] = b * a
			E.Invert:
				results[i] = a.affine_inverse()
			E.Lerp:
				results[i] = Ops.lerp_transform( a, b_values[i], float( c_values[i] ) )
			E.TransformPosition:
				results[i] = a * ( b_values[i] as Vector3 )
			E.InverseTransformPosition:
				results[i] = a.affine_inverse() * ( b_values[i] as Vector3 )
			E.TransformDirection:
				results[i] = a.basis * ( b_values[i] as Vector3 )
	var out_type : int = D.Vector if vector_b else D.Transform
	var out_name := Ops.resolve_output_name( settings.out_name, read_a.name )
	var err := Ops.write_stream( out_data, out_name, results, out_type, out_name == read_a.name )
	if err != "":
		setError( err )
		return
	set_output( 0, out_data )

func _apply_to_points( out_data : FlowData.Data, transforms : Array, n : int ) -> void:
	var D := FlowData.DataType
	if not out_data.hasStreamOfType( FlowData.AttrPosition, D.Vector ):
		setError( "ApplyToPoints needs point data with a Vector 'position' stream" )
		return
	var positions = out_data.getContainerChecked( FlowData.AttrPosition, D.Vector )
	var rotations = out_data.getContainerChecked( FlowData.AttrRotation, D.Vector )
	var quats = out_data.getContainerChecked( FlowData.AttrRotationQuat, D.Quaternion )
	var sizes = out_data.getContainerChecked( FlowData.AttrSize, D.Vector )
	var new_pos := PackedVector3Array()
	var new_rot := PackedVector3Array()
	var new_quat := PackedVector4Array()
	var new_size := PackedVector3Array()
	new_pos.resize( n )
	new_rot.resize( n )
	new_quat.resize( n )
	new_size.resize( n )
	for i in range( n ):
		var p := Ops.point_transform( positions, rotations, quats, sizes, i )
		var moved : Transform3D = ( transforms[i] as Transform3D ) * p
		var parts := Ops.break_transform( moved )
		new_pos[i] = parts.translation
		new_rot[i] = parts.rotation
		new_quat[i] = FlowData.quatToVec4( parts.quaternion )
		new_size[i] = parts.scale
	var err = out_data.registerStream( FlowData.AttrPosition, new_pos, D.Vector )
	if err == null and ( rotations != null or quats == null ):
		err = out_data.registerStream( FlowData.AttrRotation, new_rot, D.Vector )
	if err == null and quats != null:
		err = out_data.registerStream( FlowData.AttrRotationQuat, new_quat, D.Quaternion )
	if err == null:
		err = out_data.registerStream( FlowData.AttrSize, new_size, D.Vector )
	if err != null:
		setError( str( err ) )
		return
	set_output( 0, out_data )
