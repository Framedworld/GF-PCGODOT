@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Filter",
		"settings" : FilterNodeSettings,
		"ins" : [{ "label": "In A" }, { "label": "In B" }], 
		"outs" : [{ "label" : "True" }, { "label" : "False" }],
		"hide_inputs" : true,
		"tooltip" : "Filter inputs based on some condition.\nThis node returns splits the input stream in two substreams.",
	}

func execute( ctx : FlowData.EvaluationContext ):
	#print( "filter.input: ", inputs )
	var in_dataA : FlowData.Data = get_input(0)
	if in_dataA == null:
		setError( "Input A %s not found" % [settings.in_nameA])
		return
	if in_dataA.size() == 0:
		set_output( 0, in_dataA )
		set_output( 1, in_dataA )
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
	# in which case we will expand it. Wwe might need in the future A to be just one 
	# element and B having lots of elements, or the type not to be float...
	if requires_two_operands and num_elemsA != num_elemsB:
		if num_elemsB == 1 and num_elemsA > 0 and sB.data_type == FlowData.DataType.Float:
			sB = newFloatStream( num_elemsA, sA.name + " as float", sB.container[0])
		else:
			if ctx.owner == null and Engine.is_editor_hint():
				var empty_out = FlowData.Data.new()
				set_output( 0, empty_out )
				set_output( 1, empty_out )
				return
			setError( "Num elements from A nd B do not match (%d vs %d)" % [num_elemsA, num_elemsB])
			return
	var num_elems := num_elemsA
	
	# When comparing int vs floats, promote the ints to float to reduce the casuistics
	if requires_two_operands and sA.data_type == FlowData.DataType.Int and sB.data_type == FlowData.DataType.Float:
		sA = newFloatStream( num_elemsA, sA.name + " as float", func( idx : int ) -> float: return sA.container[idx] )
		
	# Also, when comparing bools vs floats, promote the bool to float to reduce the casuistics
	if requires_two_operands and sA.data_type == FlowData.DataType.Bool and sB.data_type == FlowData.DataType.Float:
		sA = newFloatStream( num_elemsA, sA.name + " as float", func( idx : int ) -> float: return sA.container[idx] )

	# This will store the indices that pass the test
	var indices_true = PackedInt32Array( )
	var indices_false = PackedInt32Array( )
		
	if requires_two_operands and sA.data_type == FlowData.DataType.Float and sB.data_type == FlowData.DataType.Float:
		var inA : PackedFloat32Array = sA.container
		var inB : PackedFloat32Array = sB.container
		match settings.condition:

			FilterNodeSettings.eCondition.Equal:
				for i in range(num_elems):
					if inA[i] == inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.NotEqual:
				for i in num_elems:
					if inA[i] != inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.Greater:
				for i in num_elems:
					if inA[i] > inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.GreaterOrEqual:
				for i in num_elems:
					if inA[i] >= inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.Less:
				for i in num_elems:
					if inA[i] < inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.LessOrEqual:
				for i in num_elems:
					if inA[i] <= inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.AlmostEqual:
				var threshold : float = getSettingValue( ctx, "threshold" )
				for i in num_elems:
					if abs(inA[i] - inB[i]) < threshold:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.LogicalAND:
				for i in num_elems:
					if inA[i] && inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.LogicalOR:
				for i in num_elems:
					if inA[i] || inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.LogicalXOR:
				for i in num_elems:
					if inA[i] != inB[i]:
						indices_true.append(i)
					else:
						indices_false.append(i)

			FilterNodeSettings.eCondition.IsNull:
				for i in num_elems:
					if !inA[i]:
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
