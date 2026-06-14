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
			" * Customize the Node Label if the expression is too long\n"
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
	size = get_combined_minimum_size()
	if settings.title and settings.title != "Expression":
		return settings.title
	if !settings.expression:
		return "Expression"
	return shorten( settings.expression )

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
		out += resolved
		last = m.get_end()
	out += expr.substr( last )
	return out

func evaluateAndSaveResult( idx : int, values : Array ):

	var result = _expression.execute(values)
	if not _expression.has_execute_failed():
		if _container == null:
			var flow_data_type = getFlowDataTypeFromGdScriptType( typeof( result ))
			if flow_data_type != FlowData.DataType.Invalid:
				var stream = newStream( _in_size, settings.out_name, result, flow_data_type )
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

	var names = ["Index", "Size"]
	names.append_array( settings.args.keys() )
	names.append_array( in_data.streams.keys() )
	var parsed_expression := _translate_ue_attribute_names( settings.expression, names )
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
	
	if settings.expose_arrays:
		var containers = in_data.streams.values().map( func( s ): return s.container )
		values.append_array( containers )

		for idx in range( _in_size ):
			values[0] = idx
			if not evaluateAndSaveResult( idx, values ):
				break
	else:
		var k0 = values.size()
		var containers := in_data.streams.values().map( func(s): return s.container )
		var num_containers = containers.size()
		values.append_array( containers.map( func( c ): return c[0] ) )
		for idx in range( _in_size ):
			values[0] = idx
			for k in range( containers.size() ):
				values[ k0 + k ] = containers[k][ idx ]
			#if settings.trace:
				#print( "  For %d : %s" % [ idx, values ])
			if not evaluateAndSaveResult( idx, values ):
				break

	# Register the result stream in both modes (expose_arrays previously
	# skipped this and silently dropped the computed stream).
	if _container != null:
		if settings.trace:
			print( "Registering stream %s with %s" % [ settings.out_name, _container ])
		var err_msg = _out_data.registerStream( settings.out_name, _container )
		if err_msg:
			setError( err_msg )

	set_output( 0, _out_data )
