@tool
extends FlowNodeBase

## Label of the extra input pin a dynamic subgraph (graph_attribute) reads.
const GRAPH_PIN_LABEL := "Graph"

var _connected_graph: FlowGraphResource = null
var _last_input_data_map: Dictionary = {}
# Dynamic subgraph: graphs resolved during the current evaluation (path ->
# result, instance id -> graph), reset at its first entry.
var _graph_memo: Dictionary = {}

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
	if settings and settings.graph_attribute != "":
		# Dynamic subgraph: the data whose graph_attribute names the graph.
		ins.append({ "label": GRAPH_PIN_LABEL, "data_type": FlowData.DataType.Invalid })
	meta_node.ins = ins
	meta_node.outs = outs
	return meta_node

func getTitle() -> String:
	var title := "Subgraph"
	if settings and settings.graph:
		var path = settings.graph.resource_path
		if path != "":
			title = "Subgraph (%s)" % path.get_file().get_basename()
		else:
			title = "Subgraph (New Graph)"
	if settings and settings.graph_attribute != "":
		title += " [@%s]" % settings.graph_attribute
	return title


func onPropChanged( prop_name : String ):
	super.onPropChanged( prop_name )
	if prop_name == "graph" or prop_name == "graph_attribute":
		if settings and get_widget() != null:
			_connect_graph(settings.graph)
		initFromScript()

func computeSceneFingerprint( _ctx : FlowData.EvaluationContext ) -> Variant:
	# A dynamic graph is only known per iteration: treat it as scene-dependent.
	if settings and settings.graph_attribute != "":
		return null
	return nestedGraphSceneFingerprint( settings.graph if settings else null )

## Dynamic subgraph: the graph for the entry being executed, as
## { "graph": FlowGraphResource or null, "error": String }. The Graph pin's
## data of this entry is used (or of the first entry when this one has none);
## an unconnected Graph pin runs the default graph.
func resolve_entry_graph() -> Dictionary:
	if input_bulks.size() <= 1:
		_graph_memo = {}
	var pin : int = getMeta().ins.size() - 1
	var graph_data = get_optional_input(pin)
	if not (graph_data is FlowData.Data) and input_bulks.size() > 1:
		var first_entry : Array = input_bulks[0]
		if pin < first_entry.size():
			graph_data = first_entry[pin]
	if not (graph_data is FlowData.Data):
		if settings.graph != null:
			return { "graph": settings.graph, "error": "" }
		return { "graph": null, "error": "%s input not connected and no default graph assigned" % GRAPH_PIN_LABEL }
	var missing := RefCounted.new()
	var value = graph_data.first(settings.graph_attribute, missing)
	if is_same(value, missing):
		return { "graph": null, "error": "attribute '%s' not found on the %s input" % [settings.graph_attribute, GRAPH_PIN_LABEL] }
	var resolved : Dictionary = FlowNodeIO.resolve_graph_reference(value, settings.graph, _graph_memo)
	if resolved.graph != null:
		# Keeps a graph loaded from a path alive for this evaluation's entries.
		_graph_memo[resolved.graph.get_instance_id()] = resolved.graph
	return resolved

func execute( ctx : FlowData.EvaluationContext ):
	var graph : FlowGraphResource = settings.graph
	if settings.graph_attribute != "":
		var resolved := resolve_entry_graph()
		if resolved.graph == null:
			setError("Subgraph entry %d: %s" % [maxi(input_bulks.size() - 1, 0), resolved.error])
			for i in range(getMeta().outs.size()):
				set_output(i, FlowData.Data.new())
			return
		graph = resolved.graph
	elif not settings.graph:
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
	# The nested evaluation inherits ctx.seed, component_id and overrides
	# unchanged (docs/RUNTIME_API_P0.md §2): a subgraph is part of the same
	# generation, so it shares the graph seed.
	# A dynamic graph receives the inputs above by name; its own inputs that the
	# default graph does not declare take their graph defaults.
	var outputs = FlowNodeIOClass.evaluate_graph(graph, input_data_map, ctx, {}, child_depth)
	
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

func widget_gui_input(widget, event: InputEvent) -> bool:
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
			widget.accept_event()
			return true
	return false

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
