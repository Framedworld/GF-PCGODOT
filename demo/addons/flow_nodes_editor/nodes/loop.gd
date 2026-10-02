@tool
extends FlowNodeBase

var _connected_graph: FlowGraphResource = null

func _init():
	meta_node = {
		"title" : "Loop",
		"category" : "ControlFlow",
		"settings" : LoopNodeSettings,
		"ins" : [{ "label" : "Stream", "data_type" : FlowData.DataType.Invalid }],
		"outs" : [{ "label" : "Out", "data_type" : FlowData.DataType.Invalid }],
		"tooltip" : "Loops over each element in Stream and runs a graph for each",
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
	if settings and settings.graph:
		var path = settings.graph.resource_path
		if path != "":
			return "Loop (%s)" % path.get_file().get_basename()
		return "Loop (New Graph)"
	return "Loop"


func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "graph" or prop_name == "item_input_name" or prop_name == "output_attribute_name" or prop_name == "feedback_param_name":
		if settings and get_widget() != null:
			_connect_graph(settings.graph)
		initFromScript()

func computeSceneFingerprint( _ctx : FlowData.EvaluationContext ) -> Variant:
	return nestedGraphSceneFingerprint( settings.graph if settings else null )

## Graph seed for loop iteration `index` given the loop's graph seed:
## FlowNodeBase.derive_seed(seed, index), and 0 (legacy) when the seed is 0.
static func iteration_seed( loop_graph_seed : int, index : int ) -> int:
	if loop_graph_seed == 0:
		return 0
	return FlowNodeBase.derive_seed( loop_graph_seed, index )

func execute( ctx : FlowData.EvaluationContext ):
	if not settings.graph:
		setError("No graph assigned to Loop")
		return
		
	if not settings.graph.findInParamByName(settings.item_input_name):
		setError("Loop graph does not have input parameter: %s" % settings.item_input_name)
		return
		
	var has_output = false
	if settings.graph.data and settings.graph.data.has("nodes"):
		for n_data in settings.graph.data["nodes"]:
			if n_data.get("template") == "output":
				var node_settings = n_data.get("settings", {})
				if node_settings.get("name", "out_val") == settings.output_attribute_name:
					has_output = true
					break
	if not has_output:
		setError("Loop graph does not have output node: %s" % settings.output_attribute_name)
		return

	var in_data = get_optional_input(0)
	if not in_data or in_data.size() == 0:
		set_output(0, FlowData.Data.new())
		if settings.feedback_param_name != "":
			var feedback_data : FlowData.Data = null
			var input_idx = 1
			for param in settings.graph.in_params:
				if param and param.name != settings.item_input_name:
					if param.name == settings.feedback_param_name:
						feedback_data = get_optional_input(input_idx)
						break
					input_idx += 1
			if not feedback_data:
				feedback_data = FlowData.Data.new()
			set_output(1, feedback_data)
		return
		
	var results = []
	var size = in_data.size()
	
	var feedback_data : FlowData.Data = null
	if settings.feedback_param_name != "":
		var input_idx = 1
		for param in settings.graph.in_params:
			if param and param.name != settings.item_input_name:
				if param.name == settings.feedback_param_name:
					feedback_data = get_optional_input(input_idx)
					break
				input_idx += 1
		if not feedback_data:
			feedback_data = FlowData.Data.new()
	
	var FlowNodeIOClass = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	# Recursion guard: evaluate_graph stamps its depth on the ctx it builds;
	# editor-built contexts have no meta, so default to 0 there.
	var depth : int = ctx.get_meta("flow_eval_depth", 0)
	# PERF: evaluate_graph re-instantiates (and now frees) the whole sub-graph's
	# node Controls once per element. Reusing one parsed graph across iterations
	# would require splitting evaluate_graph into parse/execute phases with
	# per-pass state resets (generated_bulks, inputs, fed input nodes) — too
	# invasive for this fix; correctness first.
	for idx in range(size):
		var item_data = in_data.filter(PackedInt32Array([idx]))
		var input_data_map = {}
		input_data_map[settings.item_input_name] = item_data

		# Map extra input parameters
		var input_idx = 1
		for param in settings.graph.in_params:
			if param and param.name != settings.item_input_name:
				if param.name == settings.feedback_param_name:
					input_data_map[param.name] = feedback_data.duplicate() if feedback_data != null else FlowData.Data.new()
				else:
					var extra_in = get_optional_input(input_idx)
					if extra_in:
						input_data_map[param.name] = extra_in
				input_idx += 1

		var child_depth := depth + 1
		# Per-iteration seed (docs/RUNTIME_API_P0.md §2): iteration i runs with
		# hash([seed, i]) so iterations are decorrelated; seed 0 stays 0 (legacy).
		# The child context copies ctx.seed, so set it around the call.
		var parent_seed : int = ctx.seed
		ctx.seed = iteration_seed(parent_seed, idx)
		var outputs = FlowNodeIOClass.evaluate_graph(settings.graph, input_data_map, ctx, {}, child_depth)
		ctx.seed = parent_seed

		var result_data = outputs.get(settings.output_attribute_name, null)
		if result_data == null:
			push_warning("Loop iteration produced no output for stream: " + settings.output_attribute_name)
		results.append(result_data)
		
		if settings.feedback_param_name != "":
			feedback_data = outputs.get(settings.feedback_param_name, null)
			if not feedback_data:
				feedback_data = FlowData.Data.new()
		
	# Merge results
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
			out_stream.container.append_array(stream.container)
			
		offset += res_size
		
		for stream_name in out_data.streams:
			var stream = out_data.streams[stream_name]
			if stream.container.size() < offset:
				stream.container.resize(offset)
				
	set_output(0, out_data)
	if settings.feedback_param_name != "":
		set_output(1, feedback_data)


func widget_gui_input(widget, event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		var editor = getEditor()
		if editor and settings and settings.graph:
			editor.setResourceToEdit(settings.graph, null)
			widget.accept_event()
			return true
	return false
