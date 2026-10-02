## Verbatim copy of nodes/expression.gd before the WP13-P1 performance rewrite
## (base d5bd9b6). Reference implementation for expression_fast_path_test.gd;
## not a registered node. Do not edit.
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
				values[ k0 + k ] = containers[k][ FlowData.bcast_idx( containers[k].size(), idx ) ]
			#if settings.trace:
				#print( "  For %d : %s" % [ idx, values ])
			if not evaluateAndSaveResult( idx, values ):
				break

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
