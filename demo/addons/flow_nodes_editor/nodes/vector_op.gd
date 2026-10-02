@tool
extends FlowNodeBase

const VectorOpSettings = preload("res://addons/flow_nodes_editor/nodes/vector_op_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Vector Op",
		"settings" : VectorOpSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "Vector operations on Vector2, Vector and Vector4 attributes: Dot, Cross, Normalize, Length, LengthSquared,\n" +
			"Distance, DistanceSquared, Reflect, Project, Lerp, RotateAroundAxis (degrees), Angle (degrees), ComponentMin/Max.\n" +
			"B is an attribute (In B, else In A) or a constant; a scalar B broadcasts to every component. C is the Lerp alpha or the rotation angle.\n" +
			"Scalar results are Float; vector results keep A's type. For + - * / use Math Op.",
		"aliases" : ["Vector Op", "Attribute Vector Op"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "Vector %s" % VectorOpSettings.eOperation.keys()[ clampi( settings.operation, 0, VectorOpSettings.eOperation.size() - 1 ) ]

func execute( ctx : FlowData.EvaluationContext ):
	var D := FlowData.DataType
	var E := VectorOpSettings.eOperation
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
	var ta : int = read_a.data_type
	if ta != D.Vector2 and ta != D.Vector and ta != D.Vector4:
		setError( "Input A '%s' is %s; Vector Op needs a Vector2, Vector or Vector4 attribute" % [ settings.in_nameA, Ops.type_label( ta ) ] )
		return
	var width := Ops.vector_width( ta )
	var op : int = settings.operation

	var b_values : Array = []
	if settings.usesB():
		if settings.use_constant_b:
			var cb : Vector4 = settings.constant_b
			b_values = Ops.constant_values( [ cb.x, cb.y, cb.z, cb.w ].slice( 0, width ), n )
		else:
			var read_b := Ops.read_operand( in_a, get_optional_input( 1 ), settings.in_nameB, n, "Input B" )
			if not read_b.ok:
				setError( read_b.error )
				return
			var tb : int = read_b.data_type
			b_values.resize( n )
			for i in range( n ):
				if Ops.is_numeric_type( tb ):
					b_values[i] = Ops.constant_values( float( read_b.values[i] ), width )
				elif Ops.vector_width( tb ) == width and tb != D.Quaternion:
					b_values[i] = Ops._components( read_b.values[i], tb )
				else:
					setError( "Input B '%s' is %s; it must be a number or have %d components like A" % [ settings.in_nameB, Ops.type_label( tb ), width ] )
					return
	var c_values : Array = []
	if settings.usesC():
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

	if op == E.Cross and ta == D.Vector4:
		setError( "Cross needs Vector or Vector2 operands" )
		return
	if op == E.RotateAroundAxis and ta != D.Vector:
		setError( "RotateAroundAxis needs a Vector (3D) operand" )
		return

	var scalar_result : bool = op in [ E.Dot, E.Length, E.LengthSquared, E.Distance, E.DistanceSquared, E.Angle ] \
		or ( op == E.Cross and ta == D.Vector2 )
	var out_type : int = D.Float if scalar_result else ta
	var results : Array = []
	results.resize( n )
	for i in range( n ):
		var a : Array = Ops._components( read_a.values[i], ta )
		var b : Array = b_values[i] if not b_values.is_empty() else []
		var c : float = float( c_values[i] ) if not c_values.is_empty() else 0.0
		var r = _apply( op, a, b, c )
		results[i] = r if scalar_result else Ops._components_to_value( r, ta )
	var out_name := Ops.resolve_output_name( settings.out_name, read_a.name )
	var err := Ops.write_stream( out_data, out_name, results, out_type, out_name == read_a.name )
	if err != "":
		setError( err )
		return
	set_output( 0, out_data )

static func _dot( a : Array, b : Array ) -> float:
	var s := 0.0
	for k in range( a.size() ):
		s += a[k] * b[k]
	return s

static func _scale( a : Array, f : float ) -> Array:
	var out : Array = []
	for x in a:
		out.append( x * f )
	return out

static func _sub( a : Array, b : Array ) -> Array:
	var out : Array = []
	for k in range( a.size() ):
		out.append( a[k] - b[k] )
	return out

static func _apply( op : int, a : Array, b : Array, c : float ):
	var E := VectorOpSettings.eOperation
	match op:
		E.Dot:
			return _dot( a, b )
		E.Cross:
			if a.size() == 2:
				return a[0] * b[1] - a[1] * b[0]
			var v := Vector3( a[0], a[1], a[2] ).cross( Vector3( b[0], b[1], b[2] ) )
			return [ v.x, v.y, v.z ]
		E.Normalize:
			var l := sqrt( _dot( a, a ) )
			return _scale( a, 1.0 / l ) if l > 0.0 else _scale( a, 0.0 )
		E.Length:
			return sqrt( _dot( a, a ) )
		E.LengthSquared:
			return _dot( a, a )
		E.Distance:
			var d := _sub( a, b )
			return sqrt( _dot( d, d ) )
		E.DistanceSquared:
			var d := _sub( a, b )
			return _dot( d, d )
		E.Reflect:
			var bl := sqrt( _dot( b, b ) )
			if bl <= 0.0:
				return a.duplicate()
			var nrm := _scale( b, 1.0 / bl )
			return _sub( a, _scale( nrm, 2.0 * _dot( a, nrm ) ) )
		E.Project:
			var bb := _dot( b, b )
			if bb <= 0.0:
				return _scale( a, 0.0 )
			return _scale( b, _dot( a, b ) / bb )
		E.Lerp:
			var out : Array = []
			for k in range( a.size() ):
				out.append( a[k] + ( b[k] - a[k] ) * c )
			return out
		E.RotateAroundAxis:
			var axis := Vector3( b[0], b[1], b[2] )
			if axis.length_squared() <= 0.0:
				return a.duplicate()
			var v := Vector3( a[0], a[1], a[2] ).rotated( axis.normalized(), deg_to_rad( c ) )
			return [ v.x, v.y, v.z ]
		E.Angle:
			var la := sqrt( _dot( a, a ) )
			var lb := sqrt( _dot( b, b ) )
			if la <= 0.0 or lb <= 0.0:
				return 0.0
			return rad_to_deg( acos( clampf( _dot( a, b ) / ( la * lb ), -1.0, 1.0 ) ) )
		E.ComponentMin:
			var out : Array = []
			for k in range( a.size() ):
				out.append( minf( a[k], b[k] ) )
			return out
		E.ComponentMax:
			var out : Array = []
			for k in range( a.size() ):
				out.append( maxf( a[k], b[k] ) )
			return out
	return 0.0
