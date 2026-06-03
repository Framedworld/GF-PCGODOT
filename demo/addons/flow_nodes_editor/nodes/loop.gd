@tool
extends FlowNodeBase

var _connected_graph: FlowGraphResource = null

func _init():
	meta_node = {
		"title" : "Loop",
		"settings" : LoopNodeSettings,
		"ins" : [{ "label" : "Stream", "data_type" : FlowData.DataType.Invalid }],
		"outs" : [{ "label" : "Out", "data_type" : FlowData.DataType.Invalid }],
		"tooltip" : "Loops over each element in Stream and runs a graph for each",
	}

func _exit_tree():
	super._exit_tree()
	_disconnect_graph()

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

func refreshFromSettings():
	super.refreshFromSettings()
	if settings:
		_connect_graph(settings.graph)
	initFromScript()

func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "graph" or prop_name == "item_input_name" or prop_name == "output_attribute_name" or prop_name == "feedback_param_name":
		if settings:
			_connect_graph(settings.graph)
		initFromScript()

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
				
		var FlowNodeIOClass = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
		var outputs = FlowNodeIOClass.evaluate_graph(settings.graph, input_data_map, ctx)
		
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


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		var editor = getEditor()
		if editor and settings and settings.graph:
			editor.setResourceToEdit(settings.graph, null)
			accept_event()
