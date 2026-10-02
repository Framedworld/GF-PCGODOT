@tool
extends FlowNodeBase

const StringOpSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_string_op_settings.gd")
const Ops = preload("res://addons/flow_nodes_editor/attributes/flow_attribute_ops.gd")

func _init():
	meta_node = {
		"title" : "Attribute String Op",
		"settings" : StringOpSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"tooltip" : "String operations per point: Append, Prepend, Replace, ToUpper, ToLower, Contains, StartsWith, EndsWith,\n" +
			"Format ({0} = A, {1} = B, {2} = C, {index}, {attribute}), Length, Trim, Substring.\n" +
			"Non-String operands are converted to text first. Contains/StartsWith/EndsWith write a Bool, Length an Int, the rest a String.",
		"aliases" : ["Attribute String Op", "String Op", "Format String"],
		"category" : "Metadata",
	}

func getTitle() -> String:
	return "String %s" % StringOpSettings.eOperation.keys()[ clampi( settings.operation, 0, StringOpSettings.eOperation.size() - 1 ) ]

## Text values for an operand: attribute `attr` (In B first, then In A) or `constant`.
func _texts( in_a : FlowData.Data, attr : String, constant : String, n : int, label : String ) -> Dictionary:
	if attr.strip_edges() == "":
		return { "ok": true, "values": Ops.constant_values( constant, n ) }
	var read := Ops.read_operand( in_a, get_optional_input( 1 ), attr, n, label )
	if not read.ok:
		return read
	return _to_texts( read )

static func _to_texts( read : Dictionary ) -> Dictionary:
	var out : Array = []
	for v in read.values:
		var c := Ops.cast_value( v, read.data_type, FlowData.DataType.String, {} )
		if not c.ok:
			return c
		out.append( c.value )
	return { "ok": true, "values": out }

func execute( ctx : FlowData.EvaluationContext ):
	var D := FlowData.DataType
	var E := StringOpSettings.eOperation
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
	var ta := _to_texts( read_a )
	if not ta.ok:
		setError( ta.error )
		return
	var op : int = settings.operation
	var tb := { "ok": true, "values": [] }
	var tc := { "ok": true, "values": [] }
	if settings.usesB():
		tb = _texts( in_a, settings.in_nameB, settings.constant_b, n, "Input B" )
		if not tb.ok:
			setError( tb.error )
			return
	if settings.usesC():
		tc = _texts( in_a, settings.in_nameC, settings.constant_c, n, "Input C" )
		if not tc.ok:
			setError( tc.error )
			return

	var tokens := {}
	if op == E.Format:
		var err := _collect_format_tokens( in_a, n, tokens )
		if err != "":
			setError( err )
			return

	var out_type : int = D.String
	if op == E.Contains or op == E.StartsWith or op == E.EndsWith:
		out_type = D.Bool
	elif op == E.Length:
		out_type = D.Int
	var cs : bool = settings.case_sensitive
	var results : Array = []
	results.resize( n )
	for i in range( n ):
		var a : String = ta.values[i]
		var b : String = tb.values[i] if not tb.values.is_empty() else ""
		var c : String = tc.values[i] if not tc.values.is_empty() else ""
		match op:
			E.Append:
				results[i] = a + b
			E.Prepend:
				results[i] = b + a
			E.Replace:
				results[i] = a.replace( b, c ) if cs else a.replacen( b, c )
			E.ToUpper:
				results[i] = a.to_upper()
			E.ToLower:
				results[i] = a.to_lower()
			E.Contains:
				results[i] = a.contains( b ) if cs else a.to_lower().contains( b.to_lower() )
			E.StartsWith:
				results[i] = a.begins_with( b ) if cs else a.to_lower().begins_with( b.to_lower() )
			E.EndsWith:
				results[i] = a.ends_with( b ) if cs else a.to_lower().ends_with( b.to_lower() )
			E.Format:
				results[i] = _format( settings.format_pattern, a, b, c, i, tokens )
			E.Length:
				results[i] = a.length()
			E.Trim:
				results[i] = a.strip_edges()
			E.Substring:
				if not b.strip_edges().is_valid_int() or ( c.strip_edges() != "" and not c.strip_edges().is_valid_int() ):
					setError( "Substring needs integer B (start) and C (length, empty or negative for the rest); got '%s', '%s'" % [ b, c ] )
					return
				var length : int = c.strip_edges().to_int() if c.strip_edges() != "" else -1
				results[i] = a.substr( maxi( b.strip_edges().to_int(), 0 ), length )
	var out_name := Ops.resolve_output_name( settings.out_name, read_a.name )
	var write_err := Ops.write_stream( out_data, out_name, results, out_type, out_name == read_a.name )
	if write_err != "":
		setError( write_err )
		return
	set_output( 0, out_data )

const _RESERVED_TOKENS := [ "0", "1", "2", "index" ]

## Reads the attribute named by every {name} token of the pattern (except {0},
## {1}, {2} and {index}) as text, per point.
func _collect_format_tokens( in_a : FlowData.Data, n : int, tokens : Dictionary ) -> String:
	var re := RegEx.new()
	re.compile( "\\{([^{}]+)\\}" )
	for m in re.search_all( settings.format_pattern ):
		var token := m.get_string( 1 )
		if _RESERVED_TOKENS.has( token ) or tokens.has( token ):
			continue
		var read := Ops.read_values( in_a, token, n, "Format attribute" )
		if not read.ok:
			return read.error
		var texts := _to_texts( read )
		if not texts.ok:
			return texts.error
		tokens[token] = texts.values
	return ""

static func _format( pattern : String, a : String, b : String, c : String, i : int, tokens : Dictionary ) -> String:
	var values := { "0": a, "1": b, "2": c, "index": str( i ) }
	for token in tokens:
		values[token] = tokens[token][i]
	# One pass over the pattern: String.format replaces key by key, so a value
	# that itself contains "{1}" or "{index}" would be expanded again.
	var re := RegEx.new()
	re.compile( "\\{([^{}]+)\\}" )
	var out := ""
	var last := 0
	for m in re.search_all( pattern ):
		out += pattern.substr( last, m.get_start() - last )
		var key := m.get_string( 1 )
		out += String( values[key] ) if values.has( key ) else m.get_string()
		last = m.get_end()
	return out + pattern.substr( last )
