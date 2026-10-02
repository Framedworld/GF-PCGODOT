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
		or data_type == FlowData.DataType.Bool \
		or data_type == FlowData.DataType.Int64 \
		or data_type == FlowData.DataType.Double


func _numeric_as_float(value) -> float:
	if value is bool:
		return 1.0 if value else 0.0
	return float(value)


func _is_numeric(value) -> bool:
	return value is int or value is float or value is bool


func _passes_numeric_condition(value_a, value_b, condition : int, threshold : float) -> bool:
	# Two integers (Int / Int64) compare exactly: going through float would
	# lose Int64 bits above 2^53. Identical results for 32-bit values.
	if value_a is int and value_b is int and condition >= FilterNodeSettings.eCondition.Equal and condition <= FilterNodeSettings.eCondition.LessOrEqual:
		match condition:
			FilterNodeSettings.eCondition.Equal:
				return value_a == value_b
			FilterNodeSettings.eCondition.NotEqual:
				return value_a != value_b
			FilterNodeSettings.eCondition.Greater:
				return value_a > value_b
			FilterNodeSettings.eCondition.GreaterOrEqual:
				return value_a >= value_b
			FilterNodeSettings.eCondition.Less:
				return value_a < value_b
			FilterNodeSettings.eCondition.LessOrEqual:
				return value_a <= value_b
	match condition:
		FilterNodeSettings.eCondition.Equal:
			# Coerce across numeric types so 1 (int) == 1.0 (float) and true == 1.0.
			if _is_numeric(value_a) and _is_numeric(value_b):
				return _numeric_as_float(value_a) == _numeric_as_float(value_b)
			return value_a == value_b
		FilterNodeSettings.eCondition.NotEqual:
			if _is_numeric(value_a) and _is_numeric(value_b):
				return _numeric_as_float(value_a) != _numeric_as_float(value_b)
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


## The first `count` values of a Float, Int, Bool or Double container as
## doubles, or an empty array when the container has another type, does not
## match its declared type or is shorter than `count`. Every value converts
## exactly (Int is 32-bit), so _passes_numeric_condition on the doubles gives
## the same answer as on the original values; Int64 is left out because it
## can exceed 2^53.
static func _as_float64(container, data_type : int, count : int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if count <= 0 or container == null or container.size() < count:
		return out
	match data_type:
		FlowData.DataType.Float:
			if not (container is PackedFloat32Array):
				return out
			var c : PackedFloat32Array = container
			out.resize(count)
			for i in count:
				out[i] = c[i]
		FlowData.DataType.Int:
			if not (container is PackedInt32Array):
				return out
			var c : PackedInt32Array = container
			out.resize(count)
			for i in count:
				out[i] = c[i]
		FlowData.DataType.Bool:
			if not (container is PackedByteArray):
				return out
			var c : PackedByteArray = container
			out.resize(count)
			for i in count:
				out[i] = c[i]
		FlowData.DataType.Double:
			if not (container is PackedFloat64Array):
				return out
			out = container.slice(0, count)
	return out


## _passes_numeric_condition for every point, on doubles, one typed loop per
## condition (a call per point cost about 1.5 us).
static func _split_float64(a : PackedFloat64Array, b : PackedFloat64Array, count : int, condition : int, threshold : float, inside : PackedInt32Array, outside : PackedInt32Array) -> void:
	match condition:
		FilterNodeSettings.eCondition.Equal:
			for i in count:
				if a[i] == b[i]: inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.NotEqual:
			for i in count:
				if a[i] != b[i]: inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.Greater:
			for i in count:
				if a[i] > b[i]: inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.GreaterOrEqual:
			for i in count:
				if a[i] >= b[i]: inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.Less:
			for i in count:
				if a[i] < b[i]: inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.LessOrEqual:
			for i in count:
				if a[i] <= b[i]: inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.AlmostEqual:
			for i in count:
				if absf(a[i] - b[i]) < threshold: inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.LogicalAND:
			for i in count:
				if bool(a[i]) and bool(b[i]): inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.LogicalOR:
			for i in count:
				if bool(a[i]) or bool(b[i]): inside.append(i)
				else: outside.append(i)
		FilterNodeSettings.eCondition.LogicalXOR:
			for i in count:
				if bool(a[i]) != bool(b[i]): inside.append(i)
				else: outside.append(i)
		_:
			for i in count:
				outside.append(i)


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
		if is_ownerless_preview(ctx):
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
				if is_ownerless_preview(ctx):
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
			if is_ownerless_preview(ctx):
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
		var condition : int = settings.condition
		var fA := _as_float64(inA, sA.data_type, num_elems)
		var fB := _as_float64(inB, sB.data_type, num_elems)
		if not fA.is_empty() and not fB.is_empty():
			_split_float64(fA, fB, num_elems, condition, threshold, indices_true, indices_false)
		else:
			# Broadcast (length-1) streams apply their one value to every point.
			for i in num_elems:
				if _passes_numeric_condition(inA[FlowData.bcast_idx(inA.size(), i)], inB[FlowData.bcast_idx(inB.size(), i)], condition, threshold):
					indices_true.append(i)
				else:
					indices_false.append(i)

	elif not requires_two_operands:
		var inA = sA.container
		match settings.condition:
			FilterNodeSettings.eCondition.IsNull:
				for i in num_elems:
					if !inA[FlowData.bcast_idx(inA.size(), i)]:
						indices_true.append(i)
					else:
						indices_false.append(i)
	else:
		if is_ownerless_preview(ctx):
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
