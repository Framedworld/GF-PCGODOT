@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Filter",
		"settings" : FilterNodeSettings,
		"ins" : [{ "label": "In A" }, { "label": "In B" }], 
		"outs" : [{ "label" : "True" }, { "label" : "False" }],
		"hide_inputs" : true,
		"aliases" : ["Filter Attribute Elements"],
		"category" : "Filter",
		"tooltip" : "Filter inputs based on some condition.\nThis node splits the input stream in two substreams.",
	}


func _is_numeric_stream_type(data_type : FlowData.DataType) -> bool:
	return data_type == FlowData.DataType.Float \
		or data_type == FlowData.DataType.Int \
		or data_type == FlowData.DataType.Bool


func _numeric_as_float(value) -> float:
	if value is bool:
		return 1.0 if value else 0.0
	return float(value)


func _passes_numeric_condition(value_a, value_b, condition : int, threshold : float) -> bool:
	match condition:
		FilterNodeSettings.eCondition.Equal:
			return value_a == value_b
		FilterNodeSettings.eCondition.NotEqual:
			return value_a != value_b
		FilterNodeSettings.eCondition.Greater:
			return _numeric_as_float(value_a) > _numeric_as_float(value_b)
		FilterNodeSettings.eCondition.GreaterOrEqual:
			return _numeric_as_float(value_a) >= _numeric_as_float(value_b)
		FilterNodeSettings.eCondition.Less:
			return _numeric_as_float(value_a) < _numeric_as_float(value_b)
		FilterNodeSettings.eCondition.LessOrEqual:
			return _numeric_as_float(value_a) <= _numeric_as_float(value_b)
		FilterNodeSettings.eCondition.AlmostEqual:
			return absf(_numeric_as_float(value_a) - _numeric_as_float(value_b)) < threshold
		FilterNodeSettings.eCondition.LogicalAND:
			return bool(value_a) and bool(value_b)
		FilterNodeSettings.eCondition.LogicalOR:
			return bool(value_a) or bool(value_b)
		FilterNodeSettings.eCondition.LogicalXOR:
			return bool(value_a) != bool(value_b)
	return false


func execute( ctx : FlowData.EvaluationContext ):
	var in_dataA : FlowData.Data = require_input(0, ctx, "Input A")
	if in_dataA == null:
		return
	if in_dataA.size() == 0:
		set_output( 0, in_dataA )
		set_output( 1, in_dataA.duplicate() )
		return
	var sA = in_dataA.findStream( settings.in_nameA )
	if sA == null:
		if ctx.owner == null and Engine.is_editor_hint():
			var empty_out = FlowData.Data.new()
			set_output( 0, empty_out )
			set_output( 1, empty_out )
			return
		setError( "Input A stream %s not found" % [settings.in_nameA])
		return
	var num_elemsA := in_dataA.size()

	# B is optional, can be replaced by a cte
	var in_dataB = get_optional_input(1)
	var num_elemsB := num_elemsA
	var sB = null
	if in_dataB:
		num_elemsB = in_dataB.size()
		sB = in_dataB.findStream( settings.in_nameB )
		
	var requires_two_operands = settings.condition != FilterNodeSettings.eCondition.IsNull

	# if B is not connected, we might have a constant
	if sB == null:
		# Check if the name looks like a float
		if settings.in_nameB.is_valid_float():
			var v = settings.in_nameB.to_float()
			sB = newFloatStream( in_dataA.size(), "Constant %s" % settings.in_nameB, v )
		elif settings.in_nameB.to_lower() == "true":
			sB = newFloatStream( in_dataA.size(), "Constant %s" % settings.in_nameB, 1.0 )
		elif settings.in_nameB.to_lower() == "false":
			sB = newFloatStream( in_dataA.size(), "Constant %s" % settings.in_nameB, 0.0 )
		else:
			if requires_two_operands:
				if ctx.owner == null and Engine.is_editor_hint():
					var empty_out = FlowData.Data.new()
					set_output( 0, empty_out )
					set_output( 1, empty_out )
					return
				setError( "Input B %s not found, and can't be interpreted as a constant number (Op:%d)" % [settings.in_nameB, settings.condition])
				return

	# The number of elements should match, unless the B channel has just 1 element
	# in which case we will expand it.
	if requires_two_operands and num_elemsA != num_elemsB:
		if num_elemsB == 1 and num_elemsA > 0:
			sB = newStream( num_elemsA, sB.name, sB.container[0], sB.data_type )
			num_elemsB = num_elemsA
		else:
			if ctx.owner == null and Engine.is_editor_hint():
				var empty_out = FlowData.Data.new()
				set_output( 0, empty_out )
				set_output( 1, empty_out )
				return
			setError( "Num elements from A and B do not match (%d vs %d)" % [num_elemsA, num_elemsB])
			return
	var num_elems := num_elemsA

	# This will store the indices that pass the test
	var indices_true = PackedInt32Array( )
	var indices_false = PackedInt32Array( )
		
	if (
		requires_two_operands
		and _is_numeric_stream_type(sA.data_type)
		and _is_numeric_stream_type(sB.data_type)
	):
		var inA = sA.container
		var inB = sB.container
		var threshold : float = getSettingValue( ctx, "threshold" )
		for i in num_elems:
			if _passes_numeric_condition(inA[i], inB[i], settings.condition, threshold):
				indices_true.append(i)
			else:
				indices_false.append(i)

	elif not requires_two_operands:
		var inA = sA.container
		match settings.condition:
			FilterNodeSettings.eCondition.IsNull:
				for i in num_elems:
					if !inA[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)
	else:
		if ctx.owner == null and Engine.is_editor_hint():
			var empty_out = FlowData.Data.new()
			set_output( 0, empty_out )
			set_output( 1, empty_out )
			return
		setError( "Input A and B must have int/float type" )
		return

	var out_data_true = in_dataA.filter( indices_true )
	var out_data_false = in_dataA.filter( indices_false )
	set_output( 0, out_data_true )
	set_output( 1, out_data_false )
