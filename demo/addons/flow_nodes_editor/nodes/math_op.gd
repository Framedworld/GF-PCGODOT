@tool
extends FlowNodeBase

func _init():
	meta_node = {
		"title" : "Math",
		"settings" : MathOpNodeSettings,
		"ins" : [{ "label": "In A", "multiple_connections" : false }, { "label": "In B", "multiple_connections" : false }],
		"outs" : [{ "label" : "Out" }],
		"aliases" : ["Attribute Maths Op", "Attribute Math"],
		"category" : "Metadata",
		"tooltip" : "Applies a math operation between two streams, storing the result in a new stream or overriding another.\nYou can read and write substreams like position.X",
	}
	
func getTitle() -> String:
	return MathOpNodeSettings.eOperation.keys()[settings.operation]	

func execute( ctx : FlowData.EvaluationContext ):
	var time_start_init = Time.get_ticks_usec()	
	
	var is_single_arg = settings.isSingleArgument()
		
	if not settings.out_name:
		setError( "Output name can't be empty")
		return
	
	# Check A
	var in_dataA: FlowData.Data = require_input(0, ctx, "Input A")
	if in_dataA == null:
		return
	var sA = in_dataA.findStream( settings.in_nameA )
	if sA == null:
		if is_ownerless_preview(ctx):
			var empty_data = FlowData.Data.new()
			set_output(0, empty_data)
			return
		setError( "Input A %s not found" % [settings.in_nameA])
		return
	var num_elemsA := in_dataA.size()
	
	# B is optional, can be replaced by a cte
	var in_dataB = get_optional_input(1)
	var num_elemsB := num_elemsA
	var sB = null
	if in_dataB:
		num_elemsB = in_dataB.size()
		sB = in_dataB.findStream( settings.in_nameB )
		
	# if B is not connected, we might have a constant
	if sB == null:
		# Check if the name looks like a float
		if settings.in_nameB.is_valid_float():
			var v = settings.in_nameB.to_float()
			sB = newFloatStream( in_dataA.size(), "Constant %s" % settings.in_nameB, v )
		else:
			if not is_single_arg:
				if is_ownerless_preview(ctx):
					var empty_data = FlowData.Data.new()
					set_output(0, empty_data)
					return
				setError( "Input B %s not found, and can't be interpreted as a constant number" % [settings.in_nameB])
				return

	# The number of elements should match, unless the B channel has just 1 element
	# in which case we will expand it. We might need in the future A to be just one
	# element and B having lots of elements, or the type not to be float...
	# (sB can only be null here for single-argument ops, which ignore B.)
	if sB != null and not is_single_arg and num_elemsA != num_elemsB:
		if num_elemsB == 1 and num_elemsA > 0:
			if sB.data_type == FlowData.DataType.Float:
				sB = newFloatStream( num_elemsA, sA.name + " as float", sB.container[0])
			elif sB.data_type == FlowData.DataType.Vector:
				sB = newStream( num_elemsA, sA.name + " as vector3", sB.container[0], FlowData.DataType.Vector )
			elif sB.data_type == FlowData.DataType.Color:
				sB = newStream( num_elemsA, sA.name + " as color", sB.container[0], FlowData.DataType.Color )
			else:
				if is_ownerless_preview(ctx):
					var empty_data = FlowData.Data.new()
					set_output(0, empty_data)
					return
				setError( "Num elements from A and B do not match (%d vs %d). But In B data type must be a float, Vector3, or Color" % [num_elemsA, num_elemsB])
				return
		else:
			if is_ownerless_preview(ctx):
				var empty_data = FlowData.Data.new()
				set_output(0, empty_data)
				return
			setError( "Num elements from A and B do not match (%d vs %d)" % [num_elemsA, num_elemsB])
			return
	var num_elems := num_elemsA
	
	var out_container
	var out_data : FlowData.Data = in_dataA.duplicate()
	
	if settings.trace: print( "Math.init: %f (%d)" % [ Time.get_ticks_usec() - time_start_init, num_elems ] )
	
	if sA.data_type == FlowData.DataType.Int and (is_single_arg or sB.data_type == FlowData.DataType.Float):
		sA = newFloatStream( num_elemsA, sA.name + " as float", func( idx : int ) -> float: return sA.container[idx] )
		
	if is_single_arg:

		if sA.data_type == FlowData.DataType.Float:
			var inA : PackedFloat32Array = sA.container
			
			if settings.operation == MathOpNodeSettings.eOperation.FloorAsInt:
				var outI := PackedInt32Array()
				outI.resize( num_elems )
				for i in num_elems:
					outI[i] = floori(inA[i])
				out_container = outI
				
			else:
				var outC := PackedFloat32Array()
				outC.resize( num_elems )
				match settings.operation:
					MathOpNodeSettings.eOperation.Negate:
						for i in num_elems:
							outC[i] = -inA[i]
					MathOpNodeSettings.eOperation.Absolute:
						for i in num_elems:
							outC[i] = absf(inA[i])
					MathOpNodeSettings.eOperation.Saturate:
						for i in num_elems:
							outC[i] = clampf(inA[i], 0.0, 1.0)
					MathOpNodeSettings.eOperation.Floor:
						for i in num_elems:
							outC[i] = floorf(inA[i])
					MathOpNodeSettings.eOperation.Round:
						for i in num_elems:
							outC[i] = roundf(inA[i])
					MathOpNodeSettings.eOperation.Frac:
						for i in num_elems:
							outC[i] = inA[i] - floorf(inA[i])
					MathOpNodeSettings.eOperation.OneMinus:
						for i in num_elems:
							outC[i] = 1.0 - inA[i]
					MathOpNodeSettings.eOperation.Sign:
						for i in num_elems:
							outC[i] = -1 if inA[i] < 0 else ( 1.0 if inA[i] > 0 else 0)
					MathOpNodeSettings.eOperation.Sqrt:
						for i in num_elems:
							outC[i] = sqrt( max( 0.0, inA[i] ) )
				out_container = outC
		
		elif sA.data_type == FlowData.DataType.Vector:
			var inA : PackedVector3Array = sA.container
			var outC := PackedVector3Array()
			outC.resize( num_elems )
			
			match settings.operation:
				MathOpNodeSettings.eOperation.Negate:
					for i in num_elems:
						outC[i] = -inA[i]
				MathOpNodeSettings.eOperation.Absolute:
					for i in num_elems:
						outC[i].x = absf(inA[i].x)
						outC[i].y = absf(inA[i].y)
						outC[i].z = absf(inA[i].z)
				MathOpNodeSettings.eOperation.Saturate:
					for i in num_elems:
						outC[i].x = clampf(inA[i].x, 0.0, 1.0)
						outC[i].y = clampf(inA[i].y, 0.0, 1.0)
						outC[i].z = clampf(inA[i].z, 0.0, 1.0)
				_:
					setError( "Vector operation %s not supported as single-argument yet" % MathOpNodeSettings.eOperation.keys()[ settings.operation ] )
					return
			out_container = outC

		else:
			setError( "Input A has unsupported data type for single-argument operation (%s)" % [sA.data_type])
			return
			
	else:
		if sA.data_type == FlowData.DataType.Float and sB.data_type == FlowData.DataType.Float:
			var time_start = Time.get_ticks_usec()

			var inA : PackedFloat32Array = sA.container
			
			var inB : PackedFloat32Array = sB.container
			var outC := PackedFloat32Array()
			outC.resize( num_elems )
			out_container = outC
			
			match settings.operation:
				MathOpNodeSettings.eOperation.Multiply:
					for i in num_elems:
						outC[i] = inA[i] * inB[i]
				MathOpNodeSettings.eOperation.Add:
					for i in num_elems:
						outC[i] = inA[i] + inB[i]
				MathOpNodeSettings.eOperation.Substract:
					for i in num_elems:
						outC[i] = inA[i] - inB[i]
				MathOpNodeSettings.eOperation.Divide:
					for i in num_elems:
						if inB[i] == 0.0:
							setError( "Division by zero" )
							return
						outC[i] = inA[i] / inB[i]
				MathOpNodeSettings.eOperation.Modulo:
					for i in num_elems:
						if inB[i] == 0.0:
							setError( "Modulo by zero" )
							return
						outC[i] = fmod(inA[i], inB[i])
				MathOpNodeSettings.eOperation.Min:
					for i in num_elems:
						outC[i] = minf(inA[i], inB[i])
				MathOpNodeSettings.eOperation.Max:
					for i in num_elems:
						outC[i] = maxf(inA[i], inB[i])
				MathOpNodeSettings.eOperation.ModuloInt:
					var outI := PackedInt32Array()
					outI.resize( num_elems )
					out_container = outI
					for i in num_elems:
						var iA := int( inA[i] + 1e-6 )
						var iB := int( inB[i] + 1e-6 )
						if iB == 0:
							setError( "Modulo by zero" )
							return
						outI[i] = iA % iB
				MathOpNodeSettings.eOperation.Pow:
					for i in num_elems:
						outC[i] = pow( inA[i], inB[i] )
				_:
					setError( "Float vs Float operation %s not supported yet" % MathOpNodeSettings.eOperation.keys()[ settings.operation ]  )
			if settings.trace: print( "Math.Loop: %f (%d)" % [ Time.get_ticks_usec() - time_start, num_elems ] )
			
		elif sA.data_type == FlowData.DataType.Vector && sB.data_type == FlowData.DataType.Vector:
			var inA : PackedVector3Array = sA.container
			var inB : PackedVector3Array = sB.container
			var outC := PackedVector3Array()
			outC.resize( num_elems )
			
			match settings.operation:
				MathOpNodeSettings.eOperation.Multiply:
					for i in num_elems:
						outC[i] = inA[i] * inB[i]
				MathOpNodeSettings.eOperation.Add:
					for i in num_elems:
						outC[i] = inA[i] + inB[i]
				MathOpNodeSettings.eOperation.Substract:
					for i in num_elems:
						outC[i] = inA[i] - inB[i]
				MathOpNodeSettings.eOperation.Divide:
					for i in num_elems:
						if inB[i].x == 0.0 or inB[i].y == 0.0 or inB[i].z == 0.0:
							setError( "Division by zero" )
							return
						outC[i] = inA[i] / inB[i]
				_:
					setError( "Vector3 vs Vector3 operation not supported yet")
			out_container = outC

		elif sA.data_type == FlowData.DataType.Vector && sB.data_type == FlowData.DataType.Float:
			var inA : PackedVector3Array = sA.container
			var inB : PackedFloat32Array = sB.container
			var outC := PackedVector3Array()
			outC.resize( num_elems )
			match settings.operation:
				MathOpNodeSettings.eOperation.Multiply:
					for i in num_elems:
						outC[i] = inA[i] * inB[i]
				MathOpNodeSettings.eOperation.Divide:
					for i in num_elems:
						if inB[i] == 0.0:
							setError( "Division by zero" )
							return
						outC[i] = inA[i] / inB[i]
				_:
					setError( "Vector3 vs Float operation not supported yet")
			out_container = outC

		elif sA.data_type == FlowData.DataType.Color && sB.data_type == FlowData.DataType.Color:
			var inA : PackedColorArray = sA.container
			var inB : PackedColorArray = sB.container
			var outC := PackedColorArray()
			outC.resize( num_elems )
			
			match settings.operation:
				MathOpNodeSettings.eOperation.Multiply:
					for i in num_elems:
						outC[i] = Color(inA[i].r * inB[i].r, inA[i].g * inB[i].g, inA[i].b * inB[i].b, inA[i].a * inB[i].a)
				MathOpNodeSettings.eOperation.Add:
					for i in num_elems:
						outC[i] = Color(inA[i].r + inB[i].r, inA[i].g + inB[i].g, inA[i].b + inB[i].b, inA[i].a + inB[i].a)
				MathOpNodeSettings.eOperation.Substract:
					for i in num_elems:
						outC[i] = Color(inA[i].r - inB[i].r, inA[i].g - inB[i].g, inA[i].b - inB[i].b, inA[i].a - inB[i].a)
				MathOpNodeSettings.eOperation.Divide:
					for i in num_elems:
						if inB[i].r == 0.0 or inB[i].g == 0.0 or inB[i].b == 0.0 or inB[i].a == 0.0:
							setError( "Division by zero" )
							return
						outC[i] = Color(inA[i].r / inB[i].r, inA[i].g / inB[i].g, inA[i].b / inB[i].b, inA[i].a / inB[i].a)
				_:
					setError( "Color vs Color operation not supported yet")
			out_container = outC

		elif sA.data_type == FlowData.DataType.Color && sB.data_type == FlowData.DataType.Float:
			var inA : PackedColorArray = sA.container
			var inB : PackedFloat32Array = sB.container
			var outC := PackedColorArray()
			outC.resize( num_elems )
			match settings.operation:
				MathOpNodeSettings.eOperation.Multiply:
					for i in num_elems:
						outC[i] = Color(inA[i].r * inB[i], inA[i].g * inB[i], inA[i].b * inB[i], inA[i].a * inB[i])
				MathOpNodeSettings.eOperation.Divide:
					for i in num_elems:
						if inB[i] == 0.0:
							setError( "Division by zero" )
							return
						outC[i] = Color(inA[i].r / inB[i], inA[i].g / inB[i], inA[i].b / inB[i], inA[i].a / inB[i])
				MathOpNodeSettings.eOperation.Add:
					for i in num_elems:
						outC[i] = Color(inA[i].r + inB[i], inA[i].g + inB[i], inA[i].b + inB[i], inA[i].a + inB[i])
				MathOpNodeSettings.eOperation.Substract:
					for i in num_elems:
						outC[i] = Color(inA[i].r - inB[i], inA[i].g - inB[i], inA[i].b - inB[i], inA[i].a - inB[i])
				_:
					setError( "Color vs Float operation not supported yet")
			out_container = outC

		elif sA.data_type == FlowData.DataType.Int && sB.data_type == FlowData.DataType.Int:
			var inA : PackedInt32Array = sA.container
			var inB : PackedInt32Array = sB.container
			var outC := PackedInt32Array()
			outC.resize( num_elems )
			match settings.operation:
				MathOpNodeSettings.eOperation.Multiply:
					for i in num_elems:
						outC[i] = inA[i] * inB[i]
				MathOpNodeSettings.eOperation.Add:
					for i in num_elems:
						outC[i] = inA[i] + inB[i]
				MathOpNodeSettings.eOperation.Substract:
					for i in num_elems:
						outC[i] = inA[i] - inB[i]
				MathOpNodeSettings.eOperation.Divide:
					for i in num_elems:
						if inB[i] == 0:
							setError( "Division by zero" )
							return
						outC[i] = inA[i] / inB[i]
				MathOpNodeSettings.eOperation.ModuloInt:
					for i in num_elems:
						if inB[i] == 0:
							setError( "Modulo by zero" )
							return
						outC[i] = inA[i] % inB[i]
				MathOpNodeSettings.eOperation.Min:
					for i in num_elems:
						outC[i] = mini( inA[i], inB[i] )
				MathOpNodeSettings.eOperation.Max:
					for i in num_elems:
						outC[i] = maxi( inA[i], inB[i] )
				_:
					setError( "Int vs Int operation not supported yet")
			out_container = outC
	
		else:
			if is_ownerless_preview(ctx):
				var empty_data = FlowData.Data.new()
				set_output(0, empty_data)
				return
			setError( "Input A and B have incompatible/unsupported data types (%s vs %s)" % [sA.data_type, sB.data_type])
			return

	var time_start_end = Time.get_ticks_usec()
	# This will override the existing stream if exists or update a substream
	var err = out_data.registerStream( settings.out_name, out_container )
	if err:
		setError( err )
		return
		
	set_output( 0, out_data )
	if settings.trace: print( "Math.end:  %f (%d)" % [ Time.get_ticks_usec() - time_start_end, num_elems ] )
