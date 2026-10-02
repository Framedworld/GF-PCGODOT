@tool
extends FlowNodeBase

## Test double for conformance_harness_test.gd: a pure node (meta "pure") that
## breaks one executor contract on purpose, picked by `behavior`, so the
## harness self-test can prove every check catches its violation. Lives in a
## .gdignore'd folder and is loaded lazily, after the addon scripts compiled.

static var behavior : String = "good"
static var counter : int = 0

func _init():
	meta_node = {
		"title" : "Conformance Fake",
		"ins" : [{ "label" : "In" }],
		"outs" : [{ "label" : "Out" }],
		"pure" : true,
	}

func execute( ctx : FlowData.EvaluationContext ):
	var in_data = inputs[0] if inputs.size() > 0 else null
	if not ( in_data is FlowData.Data ):
		setError( "Input 'In' not connected" )
		return
	var out : FlowData.Data = in_data.duplicate()
	match behavior:
		"mutate_tags":
			# Writes into the input instead of the copy.
			in_data.tags.append( "conformance_mutated" )
		"mutate_stream":
			var densities := PackedFloat32Array()
			densities.resize( in_data.size() )
			in_data.registerStream( "conformance_injected", densities, FlowData.DataType.Float )
		"nondeterministic":
			counter += 1
			out.set_data_attr( "run", counter, FlowData.DataType.Int )
		"nondeterministic_error":
			counter += 1
			setError( "run %d" % counter )
		"thread_sensitive":
			var on_main := OS.get_thread_caller_id() == OS.get_main_thread_id()
			out.set_data_attr( "on_main", on_main, FlowData.DataType.Bool )
		"cache_sensitive":
			var cached : bool = ctx.has_meta( FlowExecutor.OUTPUT_CACHE_META )
			out.set_data_attr( "cached", cached, FlowData.DataType.Bool )
	set_output( 0, out )
