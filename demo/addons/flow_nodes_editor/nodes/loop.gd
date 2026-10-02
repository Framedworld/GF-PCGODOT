@tool
extends FlowNodeBase

## Loop: runs a graph once per iteration and collects the results.
##
## Iterations (settings.iteration_mode, docs/_round2/WP8.md):
##   Points      one iteration per point of each input entry (historical).
##               iteration_key = point index.
##   Entries     one iteration per data entry (bulk) on the Stream pin, all
##               entries of the pin together. iteration_key = entry index, or
##               the entry's key_attribute value when that is set and found.
##   Partitions  the points of each input entry grouped by partition_attribute,
##               one iteration per distinct value, in ascending key order
##               (key_less). iteration_key = the value.
##   Chunks      chunk_size consecutive points of each input entry per
##               iteration, the last chunk possibly shorter.
##               iteration_key = chunk index.
## Points, Partitions and Chunks run once per input entry (the node's usual
## per-bulk execution), so their iteration_index restarts for every entry.
##
## Each iteration's graph evaluation receives runtime_params iteration_index,
## iteration_count and iteration_key (and, in Entries and Partitions mode, the
## per-data attributes of the iteration's data), readable through $param
## bindings and ctx.runtime_params, and the graph seed
## iteration_seed(ctx.seed, iteration_key).
##
## Output (settings.output_mode): Merge concatenates the iteration results
## into one Data (historical); Collection emits one bulk per iteration.

const IterationMode = LoopNodeSettings.IterationMode
const OutputMode = LoopNodeSettings.OutputMode

## Runtime parameter names every iteration receives.
const PARAM_INDEX := "iteration_index"
const PARAM_COUNT := "iteration_count"
const PARAM_KEY := "iteration_key"

var _connected_graph: FlowGraphResource = null
# Entries mode: every entry of the Stream pin, gathered by run().
var _entries_override = null

func _init():
	meta_node = {
		"title" : "Loop",
		"category" : "ControlFlow",
		"settings" : LoopNodeSettings,
		"ins" : [{ "label" : "Stream", "data_type" : FlowData.DataType.Invalid }],
		"outs" : [{ "label" : "Out", "data_type" : FlowData.DataType.Invalid }],
		"tooltip" : "Runs a graph once per iteration of Stream: per point, per data entry, per attribute partition or per chunk of points",
	}

# --- Widget hooks (see node.gd) -----------------------------------------------
# The nested graph's in_params_changed signal is only watched while the node is
# shown in the editor; runtime elements never connect to shared resources.

func widget_exit_tree(_widget):
	_disconnect_graph()

func widget_refresh(_widget):
	if settings:
		_connect_graph(settings.graph)
	initFromScript()

func _disconnect_graph():
	if is_instance_valid(_connected_graph):
		if _connected_graph.in_params_changed.is_connected(_on_graph_params_changed):
			_connected_graph.in_params_changed.disconnect(_on_graph_params_changed)
	_connected_graph = null

func _connect_graph(graph: FlowGraphResource):
	_disconnect_graph()
	if is_instance_valid(graph):
		_connected_graph = graph
		if not _connected_graph.in_params_changed.is_connected(_on_graph_params_changed):
			_connected_graph.in_params_changed.connect(_on_graph_params_changed)

func _on_graph_params_changed():
	initFromScript()

func getMeta() -> Dictionary:
	var ins = [{ "label" : "Stream", "data_type" : FlowData.DataType.Invalid }]
	var outs = [{ "label" : "Out", "data_type" : FlowData.DataType.Invalid }]
	if settings and settings.graph:
		for param in settings.graph.in_params:
			if param and param.name != settings.item_input_name:
				ins.append({
					"label": param.name,
					"data_type": param.data_type
				})
		if settings.graph.data and settings.graph.data.has("nodes"):
			for n_data in settings.graph.data["nodes"]:
				if n_data.get("template") == "output":
					var node_settings = n_data.get("settings", {})
					var out_name = node_settings.get("name", "out_val")
					if out_name == settings.output_attribute_name:
						var out_type = node_settings.get("data_type", FlowData.DataType.Float)
						outs[0].data_type = out_type
						outs[0].label = out_name
						break
		if settings.feedback_param_name != "":
			var fb_type = FlowData.DataType.Invalid
			if settings.graph.data and settings.graph.data.has("nodes"):
				for n_data in settings.graph.data["nodes"]:
					if n_data.get("template") == "output":
						var node_settings = n_data.get("settings", {})
						if node_settings.get("name", "out_val") == settings.feedback_param_name:
							fb_type = node_settings.get("data_type", FlowData.DataType.Float)
							break
			outs.append({
				"label": settings.feedback_param_name,
				"data_type": fb_type
			})
	meta_node.ins = ins
	meta_node.outs = outs
	return meta_node

func getTitle() -> String:
	var title := "Loop"
	if settings and settings.graph:
		var path = settings.graph.resource_path
		if path != "":
			title = "Loop (%s)" % path.get_file().get_basename()
		else:
			title = "Loop (New Graph)"
	elif settings and settings.graph_attribute != "":
		title = "Loop (@%s)" % settings.graph_attribute
	if settings:
		var tags := PackedStringArray()
		if settings.iteration_mode != IterationMode.Points:
			tags.append(IterationMode.find_key(settings.iteration_mode))
		if settings.output_mode != OutputMode.Merge:
			tags.append(OutputMode.find_key(settings.output_mode))
		if not tags.is_empty():
			title += " [%s]" % ", ".join(tags)
	return title


func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name in ["graph", "item_input_name", "output_attribute_name", "feedback_param_name", "iteration_mode", "output_mode", "graph_attribute"]:
		if settings and get_widget() != null:
			_connect_graph(settings.graph)
		initFromScript()

func computeSceneFingerprint( _ctx : FlowData.EvaluationContext ) -> Variant:
	# A dynamic graph is only known per iteration: treat it as scene-dependent.
	if settings and settings.graph_attribute != "":
		return null
	return nestedGraphSceneFingerprint( settings.graph if settings else null )

# --- Iteration keys and seeds -------------------------------------------------------

## Graph seed for the loop iteration with key `key` (an int index, or any
## partition value) given the loop's graph seed (the ctx.seed the loop runs
## with): 0 (legacy, every body node keeps its own random_seed) when the graph
## seed is 0, else FlowNodeBase.derive_seed(loop_graph_seed, key_seed(key)).
## For an int key this is the historical hash([seed, index]) & 0x7fffffff, so
## Points mode keeps its seeds; a partition keeps its seed whatever other
## partitions exist.
static func iteration_seed( loop_graph_seed : int, key ) -> int:
	if loop_graph_seed == 0:
		return 0
	return FlowNodeBase.derive_seed( loop_graph_seed, key_seed( key ) )

## Integer form of an iteration key used for seeding: an int as is, a bool as
## 0/1, anything else hash(key_string(key)) & 0x7fffffff (stable across runs
## and processes for plain values).
static func key_seed( key ) -> int:
	match typeof( key ):
		TYPE_INT:
			return key
		TYPE_BOOL:
			return 1 if key else 0
	return int( hash( key_string( key ) ) & 0x7fffffff )

## Text form of an iteration key: Strings as is, everything else var_to_str
## ("2", "2.5", "Vector3(1, 0, 0)"). Used for seeding, ordering mixed types and
## error messages.
static func key_string( key ) -> String:
	if key is String or key is StringName:
		return String( key )
	if key is Object:
		if is_instance_valid( key ) and key is Resource and key.resource_path != "":
			return key.resource_path
		return "<%s>" % ( key.get_class() if is_instance_valid( key ) else "null" )
	return var_to_str( key )

const _ORDERED_VECTOR_TYPES := [ TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I ]

## Strict ordering of partition keys. Numbers (int, float, bool) compare
## numerically (equal values by Variant type id: bool, int, float); Strings
## lexically; vectors of one type component-wise; any other pair, including
## mixed types, by
## key_string and then by Variant type id. Deterministic for any input.
static func key_less( a, b ) -> bool:
	var ta := typeof( a )
	var tb := typeof( b )
	var a_num := ta == TYPE_INT or ta == TYPE_FLOAT or ta == TYPE_BOOL
	var b_num := tb == TYPE_INT or tb == TYPE_FLOAT or tb == TYPE_BOOL
	if a_num and b_num:
		var fa := float( a )
		var fb := float( b )
		# NaN sorts after every number (NaN compares false both ways, which
		# would make the order depend on the input order).
		if is_nan( fa ) or is_nan( fb ):
			if is_nan( fa ) and is_nan( fb ):
				return ta < tb
			return is_nan( fb )
		if fa != fb:
			return fa < fb
		return ta < tb
	if ta == tb and ( ta == TYPE_STRING or ta == TYPE_STRING_NAME ):
		return String( a ) < String( b )
	if ta == tb and ta in _ORDERED_VECTOR_TYPES and a != b:
		return a < b
	var sa := key_string( a )
	var sb := key_string( b )
	if sa != sb:
		return sa < sb
	return ta < tb

# --- Iterations ---------------------------------------------------------------------

# One iteration: { "item": Data, "key": Variant, "attrs": Dictionary }.
static func _iteration( item : FlowData.Data, key, attrs : Dictionary = {} ) -> Dictionary:
	return { "item": item, "key": key, "attrs": attrs }

## The iterations of `in_data` in Points, Partitions or Chunks mode, or of
## `entries` in Entries mode. Returns { "iterations": Array, "error": String }.
func build_iterations( in_data : FlowData.Data, entries : Array ) -> Dictionary:
	var iterations : Array = []
	match int( settings.iteration_mode ):
		IterationMode.Entries:
			for i in range( entries.size() ):
				var entry : FlowData.Data = entries[i]
				var key = i
				if settings.key_attribute != "":
					var found = entry.first( settings.key_attribute, null )
					if found != null:
						key = found
				iterations.append( _iteration( entry, key, _data_attr_values( entry ) ) )
		IterationMode.Partitions:
			return _partition_iterations( in_data )
		IterationMode.Chunks:
			var size := in_data.size()
			var chunk := maxi( 1, settings.chunk_size )
			var chunk_index := 0
			for start in range( 0, size, chunk ):
				var indices := PackedInt32Array()
				for i in range( start, mini( start + chunk, size ) ):
					indices.append( i )
				iterations.append( _iteration( in_data.filter( indices ), chunk_index ) )
				chunk_index += 1
		_:
			for idx in range( in_data.size() ):
				iterations.append( _iteration( in_data.filter( PackedInt32Array( [ idx ] ) ), idx ) )
	return { "iterations": iterations, "error": "" }

func _partition_iterations( in_data : FlowData.Data ) -> Dictionary:
	var attribute : String = settings.partition_attribute.strip_edges()
	if attribute == "":
		return { "iterations": [], "error": "Loop Partitions mode needs a partition_attribute" }
	var missing := RefCounted.new()
	if is_same( in_data.value_at( attribute, 0, missing ), missing ):
		return { "iterations": [], "error": "Loop partition attribute not found in input: %s" % attribute }
	# Distinct values in first-seen order, each with its point indices (input
	# order kept inside a partition).
	var groups : Dictionary = {}
	var keys : Array = []
	for i in range( in_data.size() ):
		var value = in_data.value_at( attribute, i )
		if not groups.has( value ):
			groups[ value ] = PackedInt32Array()
			keys.append( value )
		groups[ value ].append( i )
	keys.sort_custom( key_less )
	var attr_name := attribute.trim_prefix( FlowData.DataAttrPrefix )
	# Stamp the value with the attribute's own type: inferring it from the
	# Variant would store an Int64 key as Int (low 32 bits) and a Double as Float.
	var key_type : int = FlowData.DataType.Invalid
	var key_stream = in_data._findStreamQuiet( attribute )
	if key_stream != null:
		key_type = key_stream.data_type
	elif in_data.data_attrs.has( attribute ):
		key_type = in_data.data_attrs[ attribute ].data_type
	var iterations : Array = []
	for key in keys:
		var item := in_data.filter( groups[ key ] )
		# The partition value as a per-data attribute (like the Partition node),
		# so the body can read it with "@data.<attribute>" or a binding.
		if not item.data_attrs.has( attr_name ):
			item.set_data_attr( attr_name, key, key_type )
		iterations.append( _iteration( item, key, _data_attr_values( item ) ) )
	return { "iterations": iterations, "error": "" }

static func _data_attr_values( data : FlowData.Data ) -> Dictionary:
	var values := {}
	for attr_name in data.data_attrs:
		values[ String( attr_name ) ] = data.get_data_attr( attr_name )
	return values

# --- Graphs -------------------------------------------------------------------------

## The problem that keeps `graph` from running as this loop's body, or "".
## The messages are the historical ones.
func graph_problem( graph : FlowGraphResource ) -> String:
	if not graph.findInParamByName(settings.item_input_name):
		return "Loop graph does not have input parameter: %s" % settings.item_input_name
	if graph.data and graph.data.has("nodes"):
		for n_data in graph.data["nodes"]:
			if n_data.get("template") == "output":
				var node_settings = n_data.get("settings", {})
				if node_settings.get("name", "out_val") == settings.output_attribute_name:
					return ""
	return "Loop graph does not have output node: %s" % settings.output_attribute_name

# Graph of one iteration with graph_attribute set: { "graph", "error" }.
# `memo` caches each resolved path and each validated graph for this run.
func _resolve_iteration_graph( item : FlowData.Data, memo : Dictionary ) -> Dictionary:
	var missing := RefCounted.new()
	var value = item.first( settings.graph_attribute, missing )
	if is_same( value, missing ):
		return { "graph": null, "error": "attribute '%s' not found" % settings.graph_attribute }
	var resolved : Dictionary = FlowNodeIO.resolve_graph_reference( value, settings.graph, memo )
	var graph : FlowGraphResource = resolved.graph
	if graph == null:
		return resolved
	var problem_key := "__problem_%d" % graph.get_instance_id()
	if not memo.has( problem_key ):
		# Keep the graph referenced for the whole run, so a path loaded once is
		# not freed and reloaded (and recompiled) between iterations.
		memo[ problem_key ] = [ graph_problem( graph ), graph ]
	var problem : String = memo[ problem_key ][0]
	if problem != "":
		return { "graph": null, "error": "%s (%s)" % [ problem, _graph_label( graph ) ] }
	return resolved

static func _graph_label( graph : FlowGraphResource ) -> String:
	if graph.resource_path != "":
		return graph.resource_path
	return "unsaved graph"

# Extra inputs of the interface graph (settings.graph): param name -> the Data
# wired to its port, or null. Ports follow settings.graph.in_params minus the
# item parameter, as getMeta builds them.
func _interface_inputs() -> Dictionary:
	var extras := {}
	if settings.graph == null:
		return extras
	var input_idx = 1
	for param in settings.graph.in_params:
		if param and param.name != settings.item_input_name:
			extras[ param.name ] = get_optional_input( input_idx )
			input_idx += 1
	return extras

# --- Execution ----------------------------------------------------------------------

## Entries mode needs every entry of the Stream pin at once; the other modes
## run once per entry (the base per-bulk execution).
func run( ctx : FlowData.EvaluationContext ):
	if settings == null or int( settings.iteration_mode ) != IterationMode.Entries:
		super.run( ctx )
		return
	var entries : Array = []
	var first_inputs = null
	for bulk_index in range( num_connected_bulks ):
		readAllInputsForBulk( ctx, bulk_index )
		if first_inputs == null:
			first_inputs = inputs
		var entry = inputs[0] if inputs.size() > 0 else null
		if entry is FlowData.Data:
			entries.append( entry )
	# The other pins (extra graph inputs, feedback) are read from the first entry.
	if first_inputs != null:
		inputs = first_inputs
	if settings.trace:
		print( "%s Entries mode: %d entries" % [ name, entries.size() ] )
	_entries_override = entries
	execute( ctx )
	_entries_override = null

func execute( ctx : FlowData.EvaluationContext ):
	var dynamic : bool = settings.graph_attribute != ""
	if not dynamic:
		if not settings.graph:
			setError("No graph assigned to Loop")
			return
		var problem := graph_problem( settings.graph )
		if problem != "":
			setError( problem )
			return

	var extras := _interface_inputs()
	var feedback_enabled : bool = settings.feedback_param_name != ""
	var feedback_data : FlowData.Data = null
	if feedback_enabled:
		feedback_data = extras.get( settings.feedback_param_name, null )
		if not feedback_data:
			feedback_data = FlowData.Data.new()

	var mode := int( settings.iteration_mode )
	var in_data = get_optional_input(0)
	var entries : Array = []
	if mode == IterationMode.Entries:
		if _entries_override is Array:
			entries = _entries_override
		elif in_data is FlowData.Data:
			entries = [ in_data ]
	var is_empty : bool = entries.is_empty() if mode == IterationMode.Entries else ( not in_data or in_data.size() == 0 )
	if is_empty:
		set_output(0, FlowData.Data.new())
		if feedback_enabled:
			set_output(1, feedback_data)
		return

	var built := build_iterations( in_data, entries )
	if built.error != "":
		setError( built.error )
		return
	var iterations : Array = built.iterations
	var count := iterations.size()

	var FlowNodeIOClass = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	# Recursion guard: evaluate_graph stamps its depth on the ctx it builds;
	# editor-built contexts have no meta, so default to 0 there.
	var depth : int = ctx.get_meta("flow_eval_depth", 0)
	var child_depth := depth + 1
	var results : Array = []
	var feedbacks : Array = []
	var memo := {}
	for idx in range( count ):
		var iteration : Dictionary = iterations[idx]
		var graph : FlowGraphResource = settings.graph
		if dynamic:
			var resolved := _resolve_iteration_graph( iteration.item, memo )
			if resolved.graph == null:
				setError( "Loop iteration %d (key %s): %s" % [ idx, key_string( iteration.key ), resolved.error ] )
				if int( settings.on_graph_error ) == LoopNodeSettings.GraphErrorPolicy.Stop:
					break
				continue
			graph = resolved.graph

		var input_data_map = {}
		input_data_map[settings.item_input_name] = iteration.item
		# Extra graph inputs, matched by name (a dynamic graph may declare a
		# subset of the interface graph's inputs, in any order).
		for param in graph.in_params:
			if param and param.name != settings.item_input_name:
				if param.name == settings.feedback_param_name:
					input_data_map[param.name] = feedback_data.duplicate() if feedback_data != null else FlowData.Data.new()
				else:
					var extra_in = extras.get( param.name, null )
					if extra_in:
						input_data_map[param.name] = extra_in

		var params := {}
		for attr_name in iteration.attrs:
			params[ attr_name ] = iteration.attrs[ attr_name ]
		params[ PARAM_INDEX ] = idx
		params[ PARAM_COUNT ] = count
		params[ PARAM_KEY ] = iteration.key

		# Per-iteration seed (docs/_round2/WP8.md): derived from the loop's graph
		# seed and the iteration key; seed 0 stays 0 (legacy). The child context
		# copies ctx.seed, so set it around the call.
		if child_depth > FlowExecutor.MAX_EVAL_DEPTH:
			# The executor refuses the evaluation with only a console error;
			# report it on the loop so it reaches the runtime error log.
			setError( "Loop iteration %d: graph %s exceeds the maximum nesting depth (%d); a graph probably runs itself" % [ idx, _graph_label( graph ), FlowExecutor.MAX_EVAL_DEPTH ] )
			break
		var parent_seed : int = ctx.seed
		ctx.seed = iteration_seed( parent_seed, iteration.key )
		var outputs = FlowNodeIOClass.evaluate_graph(graph, input_data_map, ctx, params, child_depth)
		ctx.seed = parent_seed

		var result_data = outputs.get(settings.output_attribute_name, null)
		if result_data == null:
			push_warning("Loop iteration produced no output for stream: " + settings.output_attribute_name)
		results.append(result_data)

		if feedback_enabled:
			feedback_data = outputs.get(settings.feedback_param_name, null)
			if not feedback_data:
				feedback_data = FlowData.Data.new()
		feedbacks.append( feedback_data )

	if int( settings.output_mode ) == OutputMode.Collection:
		_emit_collection( results, feedbacks, feedback_data )
		return

	set_output(0, merge_results( results ))
	if feedback_enabled:
		set_output(1, feedback_data)

## Merge output: the iteration results concatenated in iteration order. A
## stream missing from some results is padded with default values.
static func merge_results( results : Array ) -> FlowData.Data:
	var out_data := FlowData.Data.new()
	var offset = 0
	for res in results:
		if res == null:
			continue
		var res_size = res.size()
		if res_size == 0:
			continue

		for stream_name in res.streams:
			var stream = res.streams[stream_name]
			if not out_data.hasStream(stream_name):
				var container = res.newContainerOfType(stream.data_type)
				container.resize(offset)
				out_data.registerStream(stream_name, container, stream.data_type)

			var out_stream = out_data.streams[stream_name]
			if stream.data_type != out_stream.data_type:
				# Another iteration (e.g. another dynamic graph) wrote this
				# attribute with another type: append_array would fail. Numbers
				# convert to the first type; anything else is left at defaults.
				if FlowAttributeOps.is_numeric_type(stream.data_type) and FlowAttributeOps.is_numeric_type(out_stream.data_type):
					var start : int = out_stream.container.size()
					out_stream.container.resize(start + res_size)
					var count : int = stream.container.size()
					for i in range(res_size):
						if count > 0:
							FlowData.Data.writeValue(out_stream.container, start + i, stream.container[FlowData.bcast_idx(count, i)], out_stream.data_type)
				else:
					push_warning("Loop merge: '%s' is %s in one iteration and %s in another; those values are left at their defaults" % [stream_name, FlowData.DataType.find_key(out_stream.data_type), FlowData.DataType.find_key(stream.data_type)])
			elif stream.container.size() == 1 and res_size > 1:
				# A broadcast (length-1) stream holds one value for every point.
				for _i in range(res_size):
					out_stream.container.append_array(stream.container)
			else:
				out_stream.container.append_array(stream.container)

		offset += res_size

		for stream_name in out_data.streams:
			var stream = out_data.streams[stream_name]
			if stream.container.size() < offset:
				stream.container.resize(offset)
	return out_data

# Collection output: one bulk per iteration that ran, holding its result (an
# empty Data when the iteration produced none) and, with feedback, the
# feedback value after that iteration on port 1. No iteration ran: one empty
# bulk (plus the current feedback), like an empty input.
func _emit_collection( results : Array, feedbacks : Array, feedback_data : FlowData.Data ) -> void:
	var feedback_enabled : bool = settings.feedback_param_name != ""
	if results.is_empty():
		set_output(0, FlowData.Data.new())
		if feedback_enabled:
			set_output(1, feedback_data if feedback_data != null else FlowData.Data.new())
		return
	for i in range( results.size() ):
		var res = results[i]
		set_output(0, res if res is FlowData.Data else FlowData.Data.new())
		if feedback_enabled:
			set_output(1, feedbacks[i])


func widget_gui_input(widget, event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		var editor = getEditor()
		if editor and settings and settings.graph:
			editor.setResourceToEdit(settings.graph, null)
			widget.accept_event()
			return true
	return false
