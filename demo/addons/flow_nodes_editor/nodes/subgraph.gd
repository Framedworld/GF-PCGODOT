@tool
extends FlowNodeBase

var _connected_graph: FlowGraphResource = null
var _last_input_data_map: Dictionary = {}

func _init():
	meta_node = {
		"title" : "Subgraph",
		"category" : "ControlFlow",
		"settings" : SubgraphNodeSettings,
		"ins" : [],
		"outs" : [],
		"is_final" : true,
		"tooltip" : "Evaluates a nested graph inside this node",
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
	var ins = []
	var outs = []
	if settings and settings.graph:
		for param in settings.graph.in_params:
			if param:
				ins.append({
					"label": param.name,
					"data_type": param.data_type
				})
		if "out_params" in settings.graph and settings.graph.out_params.size() > 0:
			for param in settings.graph.out_params:
				if param:
					outs.append({
						"label": param.name,
						"data_type": param.data_type
					})
		elif settings.graph.data and settings.graph.data.has("nodes"):
			for n_data in settings.graph.data["nodes"]:
				if n_data.get("template") == "output":
					var node_settings = n_data.get("settings", {})
					var out_name = node_settings.get("name", "out_val")
					var out_type = node_settings.get("data_type", FlowData.DataType.Float)
					outs.append({
						"label": out_name,
						"data_type": out_type
					})
	meta_node.ins = ins
	meta_node.outs = outs
	return meta_node

func getTitle() -> String:
	if settings and settings.graph:
		var path = settings.graph.resource_path
		if path != "":
			return "Subgraph (%s)" % path.get_file().get_basename()
		return "Subgraph (New Graph)"
	return "Subgraph"

func refreshFromSettings():
	super.refreshFromSettings()
	if settings:
		_connect_graph(settings.graph)
	initFromScript()

func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "graph":
		if settings:
			_connect_graph(settings.graph)
		initFromScript()

func computeSceneFingerprint( _ctx : FlowData.EvaluationContext ) -> Variant:
	return nestedGraphSceneFingerprint( settings.graph if settings else null )

func execute( ctx : FlowData.EvaluationContext ):
	if not settings.graph:
		setError("No graph assigned to Subgraph node '%s'" % getTitle())
		return
		
	var input_data_map = {}
	_last_input_data_map = {}
	if settings.graph:
		for i in range(settings.graph.in_params.size()):
			var param = settings.graph.in_params[i]
			if param:
				var in_data = get_optional_input(i)
				if in_data:
					# Priority 1: Connected wire
					input_data_map[param.name] = in_data
					_last_input_data_map[param.name] = in_data
				elif settings.has_param_override(param.name):
					# Priority 2: Per-instance override
					var override_val = settings.get_param_value(param)
					var override_data = FlowData.Data.new()
					var container = override_data.addStream(param.name, param.data_type)
					if container != null:
						container.resize(1)
						FlowData.Data.writeValue(container, 0, override_val, param.data_type)
					input_data_map[param.name] = override_data
					_last_input_data_map[param.name] = override_data
				# Priority 3: Graph default (handled by the evaluator's input node)
	
	var FlowNodeIOClass = load("res://addons/flow_nodes_editor/flow_nodes_io.gd")
	var child_depth := int(ctx.get_meta("flow_eval_depth", ctx.runtime_params.get("__eval_depth", 0))) + 1
	var outputs = FlowNodeIOClass.evaluate_graph(settings.graph, input_data_map, ctx, {}, child_depth)
	
	var meta = getMeta()
	var missing_outputs := PackedStringArray()
	for i in range(meta.outs.size()):
		var out_info = meta.outs[i]
		var out_name = out_info.label
		var out_data = outputs.get(out_name, null)
		if out_data:
			set_output(i, out_data)
		else:
			set_output(i, FlowData.Data.new())
			missing_outputs.append(out_name)
	if missing_outputs.size() > 0:
		setError("Missing outputs: %s" % ", ".join(missing_outputs))

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		var editor = getEditor()
		if editor and settings and settings.graph:
			var owner = editor.resource_owner
			if owner:
				var debug_inputs := _debug_input_data_map()
				owner.set_meta("flow_debug_graph", settings.graph)
				owner.set_meta("flow_debug_graph_path", settings.graph.resource_path)
				owner.set_meta("flow_debug_input_data_map", debug_inputs)
			editor.setResourceToEdit(settings.graph, owner)
			accept_event()

func _debug_input_data_map() -> Dictionary:
	var data_map: Dictionary = {}
	if not settings or not settings.graph:
		return data_map
	for i in range(settings.graph.in_params.size()):
		var param = settings.graph.in_params[i]
		if param == null:
			continue
		var data = null
		if inputs.size() > i and inputs[i] != null:
			data = inputs[i]
		elif _last_input_data_map.has(param.name):
			data = _last_input_data_map[param.name]
		if data is FlowData.Data:
			data_map[param.name] = data
	return data_map
