@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Expression",
		"settings" : ExpressionNodeSettings,
		"ins" : [{ "label": "In" }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Attribute Expression"],
		"category" : "Metadata",
		"tooltip" :
			"Evaluates an expression and stores the result in the output stream\n" + 
			" * When expose_arrays is set, the values of the point set are exposed as arrays\n" +
			"   and position[Index] (Index with capital I) must be used to reference the current point\n" + 
			"   and position[Index-1] references the previous position\n" + 
			" * Size for the total number of points\n" +  
			" * Customize the Node Label if the expression is too long\n" +
			" * Writing a numeric result (bool/int/float) into an existing Bool/Int/Float\n" +
			"   stream converts it to that stream's type instead of retyping the stream\n"
			,
	}
	
var _container
var _data_type : FlowData.DataType = FlowData.DataType.Invalid
var _expression : Expression
var _in_size : int
var _out_data : FlowData.Data
	
func shorten(text: String) -> String:
	return text.substr(0, 32) + "..." if text.length() > 32 else text
	
# Expose the local parameters of the expressions as parameters of the flow node 
func getExposedParams():
	var params = []
	for arg_name in settings.args:
		var prop_gd_type = typeof( settings.args[ arg_name ] )
		var data = {
			"name" : arg_name,
			"label" : editorDisplayName( arg_name ),
			"type" : prop_gd_type,
			"data_type" : getFlowDataTypeFromGdScriptType( prop_gd_type ),
			"is_parameter" : true,
			"port" : -1,
		}	
		params.append( data )	
		#print( arg_name, settings.args[ arg_name ], data )
	return params
	
func getTitle() -> String:
	if settings.title and settings.title != "Expression":
		return settings.title
	if !settings.expression:
		return "Expression"
	return shorten( settings.expression )

# The title follows the expression text; shrink the widget to fit it.
func widget_refresh(widget):
	widget.size = widget.get_combined_minimum_size()

# Translate UE-style `$Attribute` references into the matching Expression
# variable name. UE PCG addresses built-ins with a `$` prefix ($Position, $Index,
# $Density, $Seed, ...), but Godot's Expression tokenizer treats `$` as a
# node-path sigil and fails to parse it ("Expected number after '$'"). Resolution
# prefers an exact name match — so capitalized virtuals like $Index / $Size win —
# then falls back to a case-insensitive match, mapping $Position -> position,
# $Density -> density, etc. Unknown names are left bare (the `$` stripped) so the
# parser reports them as undefined rather than choking on the sigil. Expressions
# that already use the bare variable names are unaffected (no `$` to translate).
func _translate_ue_attribute_names( expr : String, names : Array ) -> String:
	if expr.find("$") == -1:
		return expr
	var lower_lookup := {}
	for n in names:
		lower_lookup[ str(n).to_lower() ] = str(n)
	var re := RegEx.new()
	if re.compile("\\$([A-Za-z_][A-Za-z0-9_]*)") != OK:
		return expr
	var out := ""
	var last := 0
	for m in re.search_all( expr ):
		out += expr.substr( last, m.get_start() - last )
		var raw_name := m.get_string(1)
		var resolved := raw_name
		if names.has( raw_name ):
			resolved = raw_name
		elif lower_lookup.has( raw_name.to_lower() ):
			resolved = lower_lookup[ raw_name.to_lower() ]
		else:
			# UE selector aliases ($Scale -> size, $BoundsMin -> bounds_min, ...)
			# when the canonical stream is bound.
			var alias := FlowData.resolveSelectorAlias( "$" + raw_name )
			if alias != "" and names.has( alias ):
				resolved = alias
		out += resolved
		last = m.get_end()
	out += expr.substr( last )
	return out

const _NUMERIC_TYPES := [ FlowData.DataType.Bool, FlowData.DataType.Int, FlowData.DataType.Float, FlowData.DataType.Int64, FlowData.DataType.Double ]

## Result types the base mapping (getFlowDataTypeFromGdScriptType) does not
## know: they register with their explicit type (a Vector4 result would
## otherwise infer as Quaternion).
const _EXTRA_RESULT_TYPES := {
	TYPE_VECTOR2: FlowData.DataType.Vector2,
	TYPE_VECTOR4: FlowData.DataType.Vector4,
	TYPE_QUATERNION: FlowData.DataType.Quaternion,
	TYPE_TRANSFORM3D: FlowData.DataType.Transform,
}

func _result_data_type( result ) -> FlowData.DataType:
	var flow_data_type = getFlowDataTypeFromGdScriptType( typeof( result ) )
	if flow_data_type == FlowData.DataType.Invalid:
		flow_data_type = _EXTRA_RESULT_TYPES.get( typeof( result ), FlowData.DataType.Invalid )
	return flow_data_type

## When the output stream already exists as Bool/Int/Float and the result is
## numeric too, keep the existing stream's type (the result is converted into
## it by writeValue) instead of retyping the stream with a conflict warning.
## Any other combination keeps the result's own type.
func _output_type_for_result( result_type : FlowData.DataType ) -> FlowData.DataType:
	if not _NUMERIC_TYPES.has( result_type ):
		return result_type
	var existing = _out_data.streams.get( settings.out_name, null )
	if existing != null and _NUMERIC_TYPES.has( existing.data_type ):
		return existing.data_type
	return result_type

func evaluateAndSaveResult( idx : int, values : Array ):

	var result = _expression.execute(values)
	if not _expression.has_execute_failed():
		if _container == null:
			var flow_data_type = _result_data_type( result )
			if flow_data_type != FlowData.DataType.Invalid:
				var result_type = flow_data_type
				flow_data_type = _output_type_for_result( flow_data_type )
				var init_value = result
				if flow_data_type != result_type:
					# Coerced numeric: pre-convert the fill value for the typed container.
					match flow_data_type:
						FlowData.DataType.Bool: init_value = 1 if bool( result ) else 0
						FlowData.DataType.Int, FlowData.DataType.Int64: init_value = int( result )
						FlowData.DataType.Float, FlowData.DataType.Double: init_value = float( result )
				if init_value is Quaternion:
					init_value = FlowData.quatToVec4( init_value )
				var stream = newStream( _in_size, settings.out_name, init_value, flow_data_type )
				if settings.trace:
					print( "Created container of type %d %s" % [ flow_data_type, stream ])
				_container = stream.container
				_data_type = flow_data_type
			else:
				setError( "Failed to identify type of expression result at index %d" % idx )
				return false
		if settings.trace:
			print( "Added[%d] = %s" % [ idx, result ])
		# Route through writeValue so each DataType is coerced into its packed
		# container correctly (e.g. Bool -> 0/1 byte). Godot 4.4+ rejects a direct
		# `byte_array[i] = <bool>` assignment, which a raw `_container[idx] = result`
		# would attempt for bool-valued expressions.
		FlowData.Data.writeValue( _container, idx, result, _data_type )
		return true
	setError( _expression.get_error_text() )	
	return false

## typeof() a result must have to be stored with a plain indexed write into
## the output container of `data_type`; for these pairs the write gives exactly
## what FlowData.Data.writeValue stores. -1: always go through writeValue.
static func _direct_store_type( data_type : FlowData.DataType ) -> int:
	match data_type:
		FlowData.DataType.Float, FlowData.DataType.Double:
			return TYPE_FLOAT
		FlowData.DataType.Int, FlowData.DataType.Int64:
			return TYPE_INT
		FlowData.DataType.Bool:
			return TYPE_BOOL
		FlowData.DataType.Vector:
			return TYPE_VECTOR3
		FlowData.DataType.Color:
			return TYPE_COLOR
		FlowData.DataType.String:
			return TYPE_STRING
		FlowData.DataType.Vector2:
			return TYPE_VECTOR2
		FlowData.DataType.Vector4:
			return TYPE_VECTOR4
	return -1

func execute( ctx : FlowData.EvaluationContext ):
	var in_data : FlowData.Data = require_input(0, ctx, "Input 'In'")
	if in_data == null:
		return
	_out_data = in_data.duplicate()
	
	_in_size = in_data.size()
	if _in_size == 0:
		set_output( 0, _out_data )
		return
	
	_expression = Expression.new()
	_container = null
	_data_type = FlowData.DataType.Invalid

	var stream_names : Array = in_data.streams.keys()
	var containers : Array = in_data.streams.values().map( func( s ): return s.container )
	var names = ["Index", "Size"]
	names.append_array( settings.args.keys() )
	names.append_array( stream_names )
	var parsed_expression := _translate_ue_attribute_names( settings.expression, names )

	# Performance: only streams whose name occurs in the expression text can be
	# referenced by it, so only those are bound as inputs and copied per point
	# (the order of the bound names is kept, so duplicates resolve as before).
	# The full binding stays when tracing, and in per-point mode when a stream
	# is shorter than the point count: reading it fails exactly as it always did.
	var bind_all : bool = settings.trace
	if not settings.expose_arrays:
		for c in containers:
			if c.size() < _in_size:
				bind_all = true
				break
	if not bind_all:
		var kept_names := []
		var kept_containers := []
		for k in range( stream_names.size() ):
			if parsed_expression.contains( str( stream_names[k] ) ):
				kept_names.append( stream_names[k] )
				kept_containers.append( containers[k] )
		names.resize( names.size() - stream_names.size() )
		names.append_array( kept_names )
		containers = kept_containers

	var error := _expression.parse(parsed_expression, names)
	if error != OK:
		setError("Failed parsing expression: %s" % _expression.get_error_text())
		return
	var values = [0, _in_size]
	for arg_name in settings.args:
		var def_value = settings.args[ arg_name ]
		var arg_value = getSettingValue( ctx, arg_name, def_value )
		#print( "%s is %s vs %s" % [ arg_name, def_value, arg_value ] )
		if arg_value != null:
			values.append( arg_value )
		else:
			values.append( def_value )
	
	if bind_all:
		# Reference path (tracing, or a short stream): the original loop, one
		# evaluateAndSaveResult per point, inline here so a failing read
		# aborts this function exactly as it always did.
		if settings.expose_arrays:
			values.append_array( containers )
			for idx in range( _in_size ):
				values[0] = idx
				if not evaluateAndSaveResult( idx, values ):
					break
		else:
			var k0 = values.size()
			values.append_array( containers.map( func( c ): return c[0] ) )
			for idx in range( _in_size ):
				values[0] = idx
				for k in range( containers.size() ):
					# Broadcast (length-1) streams apply their one value to every point.
					values[ k0 + k ] = containers[k][ FlowData.bcast_idx( containers[k].size(), idx ) ]
				if not evaluateAndSaveResult( idx, values ):
					break
	else:
		_evaluate_points( values, containers )

	# Register the result stream in both modes (expose_arrays previously
	# skipped this and silently dropped the computed stream).
	if _container != null:
		if settings.trace:
			print( "Registering stream %s with %s" % [ settings.out_name, _container ])
		var err_msg
		if FlowData.Data.isExtendedType( _data_type ) or _data_type == FlowData.DataType.Quaternion:
			err_msg = _out_data.registerStream( settings.out_name, _container, _data_type )
		else:
			err_msg = _out_data.registerStream( settings.out_name, _container )
		if err_msg:
			setError( err_msg )

	set_output( 0, _out_data )

## The per-point loop without tracing. Same results as calling
## evaluateAndSaveResult for every point: the first point goes through it (it
## creates the typed output container); later points store results of the
## container's own type with a plain indexed write and hand anything else to
## FlowData.Data.writeValue, as evaluateAndSaveResult does. In per-point mode
## the bound stream values are copied with unrolled locals for up to four
## streams (a nested loop over an untyped Array costs about 150 ns per stream
## and point).
func _evaluate_points( values : Array, containers : Array ) -> void:
	var k0 : int = values.size()
	var per_point : bool = not settings.expose_arrays
	var count : int = containers.size()
	if per_point:
		for c in containers:
			if c.size() != _in_size:
				# Broadcast (length-1) streams apply their one value to every
				# point: take the general loop below, which indexes with
				# bcast_idx, instead of the unrolled direct reads.
				count = -1
				break
		values.append_array( containers.map( func( c ): return c[0] ) )
	else:
		values.append_array( containers )
		count = 0
	var c0 = containers[0] if count > 0 else null
	var c1 = containers[1] if count > 1 else null
	var c2 = containers[2] if count > 2 else null
	var c3 = containers[3] if count > 3 else null
	var expression : Expression = _expression
	var direct_type : int = -2   # -2: output container not created yet
	var as_byte : bool = false
	var out = null
	for idx in range( _in_size ):
		values[0] = idx
		match count:
			0:
				pass
			1:
				values[k0] = c0[idx]
			2:
				values[k0] = c0[idx]
				values[k0 + 1] = c1[idx]
			3:
				values[k0] = c0[idx]
				values[k0 + 1] = c1[idx]
				values[k0 + 2] = c2[idx]
			4:
				values[k0] = c0[idx]
				values[k0 + 1] = c1[idx]
				values[k0 + 2] = c2[idx]
				values[k0 + 3] = c3[idx]
			_:
				var k := k0
				for c in containers:
					values[k] = c[ FlowData.bcast_idx( c.size(), idx ) ]
					k += 1
		if direct_type == -2:
			if not evaluateAndSaveResult( idx, values ):
				break
			direct_type = _direct_store_type( _data_type )
			as_byte = _data_type == FlowData.DataType.Bool
			out = _container
			continue
		var result = expression.execute( values )
		if expression.has_execute_failed():
			setError( expression.get_error_text() )
			break
		if typeof( result ) == direct_type:
			if as_byte:
				out[idx] = 1 if result else 0
			else:
				out[idx] = result
		else:
			FlowData.Data.writeValue( out, idx, result, _data_type )
