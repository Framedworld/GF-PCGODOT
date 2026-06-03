extends Node
class_name FlowNodeIO

# Here are all functions related to read/write the resources, including 
# serialization to/from json for the clipboard

const LOAD_PROGRESS_CHUNK_SIZE := 8
const FAST_GRAPH_LOAD_NODE_THRESHOLD := 24

static func resource_to_dict(resource: Resource) -> Dictionary:
	var dict := {}
	for prop in resource.get_property_list():
		if prop.name in FlowNodeAssets.discardted_props:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE != 0:
			var name = prop.name
			dict[name] = resource.get(name)
	return dict
	
static func split_floats(in_str : String) -> Array:
	var parts = in_str.lstrip("(").rstrip(")").split(",")
	var vfloats = []
	for part in parts:
		vfloats.append( part.to_float() )
	return vfloats

static func _parse_color(value) -> Color:
	if typeof(value) == TYPE_STRING:
		var parts = split_floats(value)
		return Color(parts[0], parts[1], parts[2], parts[3])
	return value

static func _parse_vector2(value) -> Vector2:
	if typeof(value) == TYPE_STRING:
		var parts = split_floats(value)
		return Vector2(parts[0], parts[1])
	if value == null:
		return Vector2(0,0)
	#print( "returning...", value)
	return value

static  func _parse_vector3(value) -> Vector3:
	if typeof(value) == TYPE_STRING:
		var parts = split_floats(value)
		return Vector3(parts[0], parts[1], parts[2])
	return value

static func dict_to_resource(data: Dictionary, resource: Resource) -> void:
	for prop in resource.get_property_list():
		var name = prop.name
		if name in FlowNodeAssets.discardted_props:
			continue
		if not data.has(name):
			continue
		var value = data[name]
		var type = prop.type
		match type:
			TYPE_COLOR:
				resource.set(name, _parse_color(value))
			TYPE_VECTOR2:
				resource.set(name, _parse_vector2(value))
			TYPE_VECTOR3:
				resource.set(name, _parse_vector3(value))
			_:
				if type == TYPE_ARRAY and typeof(value) == TYPE_ARRAY:
					var target_arr = resource.get(name)
					if target_arr != null and target_arr.is_typed():
						target_arr.clear()
						for item in value:
							target_arr.append(item)
					else:
						resource.set(name, value)
				else:
					resource.set(name, value)

static func _stabilize_missing_seed(settings_res: Resource, node_name: String, template: String, serialized_settings: Dictionary) -> void:
	if settings_res == null:
		return
	if not ("random_seed" in settings_res):
		return
	if serialized_settings.has("random_seed"):
		return
	# Legacy graph entries may miss random_seed. Use a deterministic fallback per node
	# so repeated evaluate_graph calls (analyze/debug) remain stable.
	var seed_hash := hash("%s::%s" % [template, node_name])
	var stable_seed := int(seed_hash & 0x7fffffff)
	if stable_seed == 0:
		stable_seed = 1
	settings_res.set("random_seed", stable_seed)

static func _serialize_args_ports(node, editor: Control) -> Dictionary:
	var args_ports: Dictionary = node.args_ports_by_name.duplicate(true)
	for arg_name in args_ports:
		args_ports[arg_name].connected = editor.is_node_port_connected(node.name, args_ports[arg_name].port)
	return args_ports

static func _settings_name(settings) -> String:
	if settings == null:
		return ""
	if settings is Dictionary:
		return str(settings.get("name", ""))
	if settings is Object and "name" in settings:
		return str(settings.name)
	return ""

static func _canonical_dynamic_node_template(node_template: String, settings) -> String:
	var param_name := _settings_name(settings)
	if param_name.is_empty():
		return node_template
	if node_template.begins_with("input_"):
		return "input_%s" % param_name
	if node_template.begins_with("output_"):
		return "output_%s" % param_name
	return node_template

static func _serialized_node_template(node) -> String:
	return _canonical_dynamic_node_template(str(node.node_template), node.settings)

static func _template_for_load(in_node: Dictionary, editor: Control) -> String:
	var node_template := str(in_node.get("template", ""))
	var canonical_template := _canonical_dynamic_node_template(
		node_template,
		in_node.get("settings", {})
	)
	if editor.has_method("ensureNodeTypeRegistered"):
		editor.ensureNodeTypeRegistered(canonical_template)
	return canonical_template

static func _normalize_loaded_node_template(node, editor: Control) -> void:
	if node == null:
		return
	if editor.has_method("normalizeDynamicNodeTemplate"):
		editor.normalizeDynamicNodeTemplate(node)

static func nodes_as_dict( nodes, frames, editor : Control ):
	var exported_node_names = {}
	
	# Find the top-left coord of all nodes
	var min_pos = null
	for node in nodes:
		var pos = node.position_offset / editor.ui_scale
		if min_pos == null:
			min_pos = pos
		else:
			min_pos.x = minf( min_pos.x, pos.x )
			min_pos.y = minf( min_pos.y, pos.y )
	
	var nodes_clean = nodes.map( func( node ):
		exported_node_names[ node.name ] = 1
		
		return {
			"position" : ( node.position_offset - min_pos ) / editor.ui_scale,
			"name" : node.name,
			"template" : _serialized_node_template(node),
			"show_disconnected_inputs" : node.show_disconnected_inputs,
			"args_port" : _serialize_args_ports(node, editor),
			"settings" : resource_to_dict( node.settings ),
		}
	)
	
	var links = []
	for connection in editor.gedit.connections:
		if connection.from_node in exported_node_names and connection.to_node in exported_node_names:
			links.append( connection )
			
	var frames_clean = frames.map( func( node ):
		var attached : Array[StringName] = editor.gedit.get_attached_nodes_of_frame(node.name)
		return {
			"position" : ( node.position_offset - min_pos ) / editor.ui_scale,
			"size" : node.size,
			"name" : node.name,
			"tint_color" : node.tint_color,
			"title" : node.title,
			"attached" : attached,
		}
	)		
			
	var data := {
		"type" : "flow_graph_nodes",
		"version" : 1,
		"min_pos" : min_pos,
		"nodes" : nodes_clean,
		"links" : links,
		"frames" : frames_clean,
	}
	return data

static func _paste_nodes_from_dict( dict, editor : Control, at_graph_coords = null):
	if typeof(dict) != TYPE_DICTIONARY:
		return []
	# Read paste coords from mouse
	var mouse_pos = editor.get_local_mouse_position()
	var graph_coords : Vector2 = editor.localToGraphCoords( mouse_pos )
	if at_graph_coords:
		graph_coords = at_graph_coords
		
	var new_nodes = create_nodes_from_dict( dict, editor, graph_coords )
	
	# Update selection
	for node in editor.getSelectedNodes():
		node.selected = false
	for node in new_nodes:
		node.selected = true

static func _ensure_unique_set_variable_name(node, editor: Control, variable_name_remaps: Dictionary) -> void:
	if node == null or node.node_template != "set_variable" or node.settings == null or not ("variable_name" in node.settings):
		return
	var original_name := String(node.settings.variable_name).strip_edges()
	if not editor.has_method("ensureSetVariableNameUnique"):
		return
	var unique_name := String(editor.ensureSetVariableNameUnique(node, false))
	if not original_name.is_empty() and unique_name != original_name:
		variable_name_remaps[original_name] = unique_name

static func _remap_get_variable_names(nodes: Array, variable_name_remaps: Dictionary) -> void:
	if variable_name_remaps.is_empty():
		return
	for node in nodes:
		if node == null or node.node_template != "get_variable" or node.settings == null or not ("variable_name" in node.settings):
			continue
		var variable_name := String(node.settings.variable_name).strip_edges()
		if not variable_name_remaps.has(variable_name):
			continue
		node.settings.variable_name = variable_name_remaps[variable_name]
		node.refreshFromSettings()

static func create_nodes_from_dict( dict, editor : Control, paste_offset = null):		
	if dict.get( "type", null) != "flow_graph_nodes":
		push_error( "Invalid dict to paste nodes from" )
		return []
	var new_nodes = []
	var old_to_new_names = {}
	var variable_name_remaps := {}
	for in_node in dict.nodes:
		var in_name = in_node.name
		var node_template = _template_for_load(in_node, editor)
		var new_name = in_name
		if editor.gedit_nodes_by_name.has( in_name ):
			new_name = editor.getNewName(node_template)
		var node = editor.addNodeFromTemplate( node_template, new_name )
		if not node:
			return null
		var in_pos = _parse_vector2( in_node.position )
		node.position_offset = ( in_pos + paste_offset ) * editor.ui_scale
		node.show_disconnected_inputs = in_node.get("show_disconnected_inputs", false)
		node.args_ports_by_name = in_node.get("args_port", {})
		
		# Apply saved settings...
		dict_to_resource( in_node.settings, node.settings )
		_normalize_loaded_node_template(node, editor)
		_ensure_unique_set_variable_name(node, editor, variable_name_remaps)
		
		# Never inport the inspect_enabled
		node.settings.inspect_enabled = false
		
		node.initFromScript();
		
		node.refreshFromSettings()
		
		# Update relation old -> new for the links
		old_to_new_names[ in_name ] = new_name
		new_nodes.append( node )
		
	_remap_get_variable_names(new_nodes, variable_name_remaps)

	# Recreate the links
	for link in dict.links:
		var new_from = old_to_new_names.get( link.from_node, null )
		var new_to = old_to_new_names.get( link.to_node, null )
		if new_from == null or new_to == null:
			push_error( "Failed to identify params links", link)
			continue
		editor.connect_nodes(new_from, link.from_port, new_to, link.to_port )

	for frame_data in dict.get( "frames", [] ):
		var frame := GraphFrame.new()
		frame.name = frame_data.name
		frame.title = frame_data.title
		var in_pos = _parse_vector2( frame_data.position )
		frame.position_offset = (in_pos + paste_offset ) * editor.ui_scale
		frame.size = _parse_vector2( frame_data.size )
		frame.tint_color = _parse_color( frame_data.tint_color )
		frame.tint_color_enabled = true
		editor.gedit.add_child(frame)
		for old_name in frame_data.attached:
			var new_name = old_to_new_names.get( old_name, null )
			if new_name:
				editor.gedit.attach_graph_element_to_frame( new_name, frame.name )

	if editor.has_method("refreshVariableNodes"):
		editor.refreshVariableNodes()
	return new_nodes

static func create_nodes_from_dict_with_progress(dict, editor: Control, paste_offset = null, progress_callback: Callable = Callable(), start_progress := 45.0, end_progress := 92.0) -> Array:
	if dict.get("type", null) != "flow_graph_nodes":
		push_error("Invalid dict to paste nodes from")
		return []

	var source_nodes: Array = dict.get("nodes", [])
	if source_nodes.size() <= FAST_GRAPH_LOAD_NODE_THRESHOLD:
		return create_nodes_from_dict(dict, editor, paste_offset)
	var source_links: Array = dict.get("links", [])
	var source_frames: Array = dict.get("frames", [])
	var total_steps = maxi(source_nodes.size() * 4 + source_links.size() + source_frames.size(), 1)
	var completed_steps := 0
	var new_nodes := []
	var old_to_new_names := {}
	var variable_name_remaps := {}

	for in_node in source_nodes:
		completed_steps += 1
		if _should_report_load_progress(completed_steps, total_steps):
			await _report_load_progress(progress_callback, "Building Graph...", completed_steps, total_steps, start_progress, end_progress)

		var in_name = in_node.name
		var node_template = _template_for_load(in_node, editor)
		var new_name = in_name
		if editor.gedit_nodes_by_name.has(in_name):
			new_name = editor.getNewName(node_template)
		var node = editor.addNodeFromTemplate(node_template, new_name, null, false)
		if not node:
			return []
		var in_pos = _parse_vector2(in_node.position)
		node.position_offset = (in_pos + paste_offset) * editor.ui_scale
		node.show_disconnected_inputs = in_node.get("show_disconnected_inputs", false)
		node.args_ports_by_name = in_node.get("args_port", {})

		completed_steps += 1
		if _should_report_load_progress(completed_steps, total_steps):
			await _report_load_progress(progress_callback, "Building Graph...", completed_steps, total_steps, start_progress, end_progress)

		dict_to_resource(in_node.settings, node.settings)
		_normalize_loaded_node_template(node, editor)
		_ensure_unique_set_variable_name(node, editor, variable_name_remaps)
		node.settings.inspect_enabled = false

		completed_steps += 1
		if _should_report_load_progress(completed_steps, total_steps):
			await _report_load_progress(progress_callback, "Building Graph...", completed_steps, total_steps, start_progress, end_progress)

		node.initFromScript()
		node.refreshFromSettings()
		editor.refreshSignalsInputArgs(node)

		old_to_new_names[in_name] = new_name
		new_nodes.append(node)
		completed_steps += 1
		if _should_report_load_progress(completed_steps, total_steps):
			await _report_load_progress(progress_callback, "Building Graph...", completed_steps, total_steps, start_progress, end_progress)

	_remap_get_variable_names(new_nodes, variable_name_remaps)

	for link in source_links:
		var new_from = old_to_new_names.get(link.from_node, null)
		var new_to = old_to_new_names.get(link.to_node, null)
		if new_from == null or new_to == null:
			push_error("Failed to identify params links", link)
		else:
			editor.connect_nodes(new_from, link.from_port, new_to, link.to_port)
		completed_steps += 1
		if _should_report_load_progress(completed_steps, total_steps):
			await _report_load_progress(progress_callback, "Connecting Nodes...", completed_steps, total_steps, start_progress, end_progress)

	for frame_data in source_frames:
		var frame := GraphFrame.new()
		frame.name = frame_data.name
		frame.title = frame_data.title
		var in_pos = _parse_vector2(frame_data.position)
		frame.position_offset = (in_pos + paste_offset) * editor.ui_scale
		frame.size = _parse_vector2(frame_data.size)
		frame.tint_color = _parse_color(frame_data.tint_color)
		frame.tint_color_enabled = true
		editor.gedit.add_child(frame)
		for old_name in frame_data.attached:
			var new_name = old_to_new_names.get(old_name, null)
			if new_name:
				editor.gedit.attach_graph_element_to_frame(new_name, frame.name)
		completed_steps += 1
		if _should_report_load_progress(completed_steps, total_steps):
			await _report_load_progress(progress_callback, "Restoring Frames...", completed_steps, total_steps, start_progress, end_progress)

	if editor.has_method("refreshVariableNodes"):
		editor.refreshVariableNodes()
	return new_nodes

static func copySelectionToClipboard( editor : Control ):
	var nodes = editor.getSelectedNodes()
	var frames = editor.getSelectedFrames()
	var json_str = JSON.stringify( nodes_as_dict( nodes, frames, editor ), "\t")
	DisplayServer.clipboard_set( json_str )

static func pasteNodeFromClipboard( editor : Control ):
	var json_str = DisplayServer.clipboard_get( )
	var dict = JSON.parse_string(json_str)
	_paste_nodes_from_dict( dict, editor )

static func duplicateSelecteddNodes( editor : Control ):
	var nodes = editor.getSelectedNodes()
	var frames = editor.getSelectedFrames()
	var dict = nodes_as_dict(nodes, frames, editor )
	_paste_nodes_from_dict( dict, editor )

static func saveToResource( editor : Control ):
	var current_resource = editor.current_resource
	if current_resource == null:
		return
	var gedit = editor.gedit
	var all_nodes = gedit.get_children().filter( func( n ):
		return n is GraphNode
	)
	var all_frames = gedit.get_children().filter( func( n ):
		return n is GraphFrame
	)
	current_resource.data = nodes_as_dict( all_nodes, all_frames, editor )
	current_resource.view_zoom = gedit.zoom
	current_resource.view_offset = gedit.scroll_offset
	current_resource.new_name_counter = editor.new_name_counter

static func loadFromResource( editor : Control ):
	var current_resource = editor.current_resource
	if current_resource == null:
		return

	# Register the input_* and output_* nodes before trying to load the nodes
	for input in current_resource.in_params:
		editor.registerInputNodeType( input )
	if "out_params" in current_resource:
		for output in current_resource.out_params:
			editor.registerOutputNodeType( output )
		
	if current_resource.data and not current_resource.data.is_empty():
		var paste_offset = _parse_vector2( current_resource.data.min_pos )
		create_nodes_from_dict( current_resource.data, editor, paste_offset )
		
	editor.gedit.zoom = current_resource.view_zoom
	editor.gedit.scroll_offset = current_resource.view_offset
	editor.new_name_counter = current_resource.new_name_counter
	editor.data_inspector.setNode( null )

static func loadFromResourceWithProgress(editor: Control, progress_callback: Callable = Callable()) -> void:
	var current_resource = editor.current_resource
	if current_resource == null:
		return

	if editor.has_method("_should_use_fast_graph_load") and editor._should_use_fast_graph_load(current_resource):
		loadFromResource(editor)
		return

	await _call_load_progress(progress_callback, "Registering Parameters...", 45.0)
	for input in current_resource.in_params:
		editor.registerInputNodeType(input)
	if "out_params" in current_resource:
		for output in current_resource.out_params:
			editor.registerOutputNodeType(output)

	if current_resource.data and not current_resource.data.is_empty():
		var paste_offset = _parse_vector2(current_resource.data.min_pos)
		await create_nodes_from_dict_with_progress(current_resource.data, editor, paste_offset, progress_callback, 48.0, 90.0)

	await _call_load_progress(progress_callback, "Restoring View...", 92.0)
	editor.gedit.zoom = current_resource.view_zoom
	editor.gedit.scroll_offset = current_resource.view_offset
	editor.new_name_counter = current_resource.new_name_counter
	editor.data_inspector.setNode(null)

static func _should_report_load_progress(completed_steps: int, total_steps: int) -> bool:
	if completed_steps == total_steps:
		return true
	if total_steps <= FAST_GRAPH_LOAD_NODE_THRESHOLD * 4:
		return false
	var chunk := maxi(total_steps / 20, LOAD_PROGRESS_CHUNK_SIZE)
	return completed_steps % chunk == 0

static func _report_load_progress(progress_callback: Callable, message: String, completed_steps: int, total_steps: int, start_progress: float, end_progress: float) -> void:
	var ratio := float(completed_steps) / float(maxi(total_steps, 1))
	await _call_load_progress(progress_callback, message, lerpf(start_progress, end_progress, ratio))

static func _call_load_progress(progress_callback: Callable, message: String, value: float) -> void:
	if progress_callback.is_valid():
		await progress_callback.call(message, value)

static func _node_variable_name(node) -> String:
	return FlowVariableEval.variable_name_from_node(node)

static func _inherit_flow_variables(target_ctx: FlowData.EvaluationContext, parent_ctx: FlowData.EvaluationContext) -> void:
	target_ctx.variables.clear()
	if parent_ctx == null:
		return
	for var_name in parent_ctx.variables.keys():
		target_ctx.variables[var_name] = parent_ctx.variables[var_name]


static func _publish_flow_variables(child_ctx: FlowData.EvaluationContext, parent_ctx: FlowData.EvaluationContext) -> void:
	if parent_ctx == null:
		return
	for var_name in child_ctx.variables.keys():
		parent_ctx.variables[var_name] = child_ctx.variables[var_name]
	FlowVariableEval._mirror_variables_to_runtime(parent_ctx)


static func _is_topo_final_root(node: FlowNodeBase) -> bool:
	if node.node_template == "output" or node.node_template.begins_with("output_"):
		return true
	if node.settings.inspect_enabled or node.settings.debug_enabled:
		return true
	if not node.getMeta().get("is_final", false):
		return false
	# Subgraph nodes fed by in-graph wires are already reached via upstream finals.
	if node.node_template == "subgraph":
		for conn in node.deps:
			if not conn.get("virtual_variable", false):
				return false
	return true


static func _needs_input_order_stabilization(node: FlowNodeBase) -> bool:
	if node.node_template == "subgraph":
		return true
	# MapGen finals (scene_3d_plan, layer subgraph feeds, etc.) can be scheduled too early
	# when multiple finals are merged; only adjust nodes that still have in-graph wires.
	if node.getMeta().get("is_final", false):
		for conn in node.deps:
			if not conn.get("virtual_variable", false):
				return true
	return false


static func _stabilize_consumer_input_order(ordered_nodes: Array) -> void:
	var index_by_name: Dictionary = {}
	for index in range(ordered_nodes.size()):
		index_by_name[ordered_nodes[index].name] = index
	var changed := true
	while changed:
		changed = false
		for node in ordered_nodes:
			if not _needs_input_order_stabilization(node):
				continue
			var node_index: int = int(index_by_name.get(node.name, -1))
			if node_index < 0:
				continue
			for conn in node.deps:
				if conn.get("virtual_variable", false):
					continue
				var src_index: int = int(index_by_name.get(conn.from_node, -1))
				if src_index < 0 or src_index < node_index:
					continue
				ordered_nodes.remove_at(node_index)
				ordered_nodes.insert(src_index + 1, node)
				for reorder_index in range(ordered_nodes.size()):
					index_by_name[ordered_nodes[reorder_index].name] = reorder_index
				changed = true
				break
			if changed:
				break


static func _stabilize_variable_execution_order(ordered_nodes: Array) -> void:
	var index_by_name: Dictionary = {}
	for index in range(ordered_nodes.size()):
		index_by_name[ordered_nodes[index].name] = index
	var changed := true
	while changed:
		changed = false
		for node in ordered_nodes:
			if node.node_template != "get_variable":
				continue
			for conn in node.deps:
				if not conn.get("virtual_variable", false):
					continue
				var set_index: int = int(index_by_name.get(conn.from_node, -1))
				var get_index: int = int(index_by_name.get(node.name, -1))
				if set_index < 0 or get_index < 0 or set_index < get_index:
					continue
				ordered_nodes.remove_at(get_index)
				ordered_nodes.insert(set_index, node)
				for reorder_index in range(ordered_nodes.size()):
					index_by_name[ordered_nodes[reorder_index].name] = reorder_index
				changed = true
				break
			if changed:
				break


static func _add_virtual_variable_dependencies(node_list: Array) -> void:
	var set_nodes_by_name := {}
	for node in node_list:
		if node.node_template != "set_variable":
			continue
		var variable_name := _node_variable_name(node)
		if variable_name.is_empty():
			continue
		if not set_nodes_by_name.has(variable_name):
			set_nodes_by_name[variable_name] = []
		set_nodes_by_name[variable_name].append(node)

	for node in node_list:
		if node.node_template != "get_variable":
			continue
		var variable_name := _node_variable_name(node)
		if variable_name.is_empty() or not set_nodes_by_name.has(variable_name):
			continue
		var set_nodes : Array = set_nodes_by_name[variable_name].duplicate()
		set_nodes.reverse()
		for set_node in set_nodes:
			var conn = {
				"from_node": set_node.name,
				"from_port": 0,
				"to_node": node.name,
				"to_port": -1,
				"virtual_variable": true,
			}
			set_node.dependants.append(conn)
			node.deps.append(conn)

static func evaluate_graph(graph: FlowGraphResource, input_data_map: Dictionary, parent_ctx: FlowData.EvaluationContext, runtime_params: Dictionary = {}, depth: int = 0) -> Dictionary:
	if depth > 20:
		push_error("PCG graph evaluation exceeded maximum recursion depth (20). Check for circular subgraph references.")
		return {}
	var instances = {}
	var node_list = []
	for n_data in graph.data.get("nodes", []):
		var template = n_data.template
		var name = n_data.name
		var script_path = FlowNodeRegistry.get_node_script_path(template)
		if script_path.is_empty():
			push_error("Failed to resolve node script for template: %s. Make sure its provider addon registered its node directory before evaluation." % template)
			continue
		var node_script = load(script_path)
		if not node_script:
			push_error("Failed to load node script for template: %s" % template)
			continue
		var instance = node_script.new() as FlowNodeBase
		instance.name = name
		instance.node_template = template
		
		# Initialize settings resource if defined
		var meta = instance.getMeta()
		if meta.has("settings") and meta.settings:
			instance.settings = meta.settings.new()
		
		# Apply saved settings
		dict_to_resource(n_data.settings, instance.settings)
		_stabilize_missing_seed(instance.settings, name, template, n_data.settings)
		
		instance.refreshFromSettings()
		
		instances[name] = instance
		node_list.append(instance)

	# Build connections (deps and dependants)
	for conn in graph.data.get("links", []):
		var src_node = instances.get(conn.from_node)
		var dst_node = instances.get(conn.to_node)
		if src_node and dst_node:
			src_node.dependants.append(conn)
			dst_node.deps.append(conn)
	_add_virtual_variable_dependencies(node_list)

	# Topological sort (on_stack = DFS path for cycles; closed = finished nodes in DAG joins)
	var get_deps_recursive = func(node, on_stack: Dictionary, closed: Dictionary, this_func) -> Array:
		if on_stack.has(node.name):
			push_warning("Circular dependency detected involving node: " + node.name)
			return []
		if closed.has(node.name):
			return []
		on_stack[node.name] = true
		var deps = [node]
		for conn in node.deps:
			var dep_node = instances.get(conn.from_node)
			if dep_node:
				deps.append_array(this_func.call(dep_node, on_stack, closed, this_func))
		on_stack.erase(node.name)
		closed[node.name] = true
		return deps

	var finals = node_list.filter(func(node): return _is_topo_final_root(node))

	var all_deps = []
	for node in finals:
		all_deps.append_array(get_deps_recursive.call(node, {}, {}, get_deps_recursive))
	all_deps.reverse()
	
	var ordered_nodes = []
	var visited = {}
	for node in all_deps:
		if not visited.has(node.name):
			visited[node.name] = true
			ordered_nodes.append(node)
	_stabilize_variable_execution_order(ordered_nodes)
	_stabilize_consumer_input_order(ordered_nodes)
	if OS.get_environment("MAPGEN_DEBUG_ORDER") == "1":
		for ordered_node in ordered_nodes:
			if (
				"assemble_map_plan" in ordered_node.node_template
				or ordered_node.node_template == "set_variable"
				or ordered_node.node_template == "get_variable"
				or "pcg_map_plan" in ordered_node.name
			):
				print("eval_order: %s (%s)" % [ordered_node.name, ordered_node.node_template])
			
	# Construct EvaluationContext for subgraph
	var ctx = load("res://addons/flow_nodes_editor/flow_data.gd").EvaluationContext.new()
	ctx.graph = graph
	ctx.owner = parent_ctx.owner
	ctx.eval_id = parent_ctx.eval_id
	ctx.gedit_nodes_by_name = instances
	ctx.runtime_params = parent_ctx.runtime_params.duplicate(true) if parent_ctx.runtime_params else {}
	for key in runtime_params.keys():
		ctx.runtime_params[key] = runtime_params[key]
	ctx.runtime_params["__eval_depth"] = depth
	_inherit_flow_variables(ctx, parent_ctx)
	FlowVariableEval._mirror_variables_to_runtime(ctx)
	
	# Feed subgraph inputs from input_data_map
	for node in ordered_nodes:
		var is_specific_input = false
		var specific_input_name = ""
		if node.node_template == "input":
			if node.settings and node.settings.name != "" and node.settings.name != "in_val":
				for param in graph.in_params:
					if param and param.name == node.settings.name:
						is_specific_input = true
						specific_input_name = param.name
						break
		elif node.node_template.begins_with("input_"):
			is_specific_input = true
			specific_input_name = node.settings.name

		if is_specific_input:
			var val = input_data_map.get(specific_input_name, null)
			if val:
				# Create a new Data object to rename/register the stream under the input's name
				var target_data = load("res://addons/flow_nodes_editor/flow_data.gd").Data.new()
				for stream_name in val.streams:
					var stream = val.streams[stream_name]
					target_data.registerStream(stream_name, stream.container, stream.data_type)

				# Ensure that the main stream is registered under input_name
				if val.streams.size() > 0 and not target_data.hasStream(specific_input_name):
					var main_stream_name = val.last_added_stream_name
					if main_stream_name == "" or not val.hasStream(main_stream_name):
						main_stream_name = val.streams.keys()[val.streams.size() - 1]
					var main_stream = val.streams[main_stream_name]
					target_data.registerStream(specific_input_name, main_stream.container, main_stream.data_type)
				node.set_output(0, target_data)
		elif node.node_template == "input":
			# Generic multi-port inputs node
			for i in range(graph.in_params.size()):
				var param = graph.in_params[i]
				if param:
					var val = input_data_map.get(param.name, null)
					var target_data = load("res://addons/flow_nodes_editor/flow_data.gd").Data.new()
					if val:
						for stream_name in val.streams:
							var stream = val.streams[stream_name]
							target_data.registerStream(stream_name, stream.container, stream.data_type)
						if val.streams.size() > 0 and not target_data.hasStream(param.name):
							var main_stream_name = val.last_added_stream_name
							if main_stream_name == "" or not val.hasStream(main_stream_name):
								main_stream_name = val.streams.keys()[val.streams.size() - 1]
							var main_stream = val.streams[main_stream_name]
							target_data.registerStream(param.name, main_stream.container, main_stream.data_type)
					else:
						var new_value = param.get_default_value()
						var container = target_data.addStream(param.name, param.data_type)
						if container != null:
							container.resize(1)
							FlowData.Data.writeValue(container, 0, new_value, param.data_type)
					node.set_output(i, target_data)

	# Execute nodes in topological order
	for node in ordered_nodes:
		if (node.node_template.begins_with("input_") or node.node_template == "input") and node.generated_bulks.size() > 0:
			continue
			
		node.inputs.clear()
		var num_ins = node.getMeta().get("ins", []).size()
		if node.node_template == "output":
			if "out_params" in graph and graph.out_params.size() > 0:
				num_ins = graph.out_params.size()
			else:
				num_ins = max(num_ins, 1)
		node.inputs.resize(num_ins)
		for conn in node.deps:
			if conn.get("virtual_variable", false):
				continue
			var src = instances.get(conn.from_node)
			if src and src.generated_bulks.size() > 0:
				var src_bulk = src.generated_bulks[src.generated_bulks.size() - 1]
				if conn.from_port < src_bulk.size():
					node.inputs[conn.to_port] = src_bulk[conn.from_port]
					
		node.preExecute(ctx)
		if node.settings.disabled:
			node.executedDisabled(ctx)
		elif not FlowVariableEval.try_fast_execute(node, ctx, instances):
			node.run(ctx)
		if FlowVariableEval.should_refresh_debug_draw(node):
			node.setupDrawDebug()
		
	# Collect output data
	var outputs = {}
	for node in node_list:
		var is_specific_output = false
		var specific_output_name = ""
		if node.node_template == "output":
			if node.settings and node.settings.name != "" and node.settings.name != "out_val":
				if "out_params" in graph:
					for param in graph.out_params:
						if param and param.name == node.settings.name:
							is_specific_output = true
							specific_output_name = param.name
							break
		elif node.node_template.begins_with("output_"):
			is_specific_output = true
			specific_output_name = node.settings.name

		if is_specific_output:
			if node.generated_bulks.size() > 0:
				var bulk = node.generated_bulks[node.generated_bulks.size() - 1]
				if bulk.size() > 0:
					outputs[specific_output_name] = bulk[0]
			elif node.inputs.size() > 0 and node.inputs[0] != null:
				outputs[specific_output_name] = node.inputs[0]
		elif node.node_template == "output":
			# Generic multi-port outputs node
			if "out_params" in graph and graph.out_params.size() > 0:
				for i in range(graph.out_params.size()):
					var param = graph.out_params[i]
					if not param:
						continue
					if node.inputs.size() > i and node.inputs[i] != null:
						outputs[param.name] = node.inputs[i]
			else:
				var out_name = node.settings.name
				if node.generated_bulks.size() > 0:
					var bulk = node.generated_bulks[node.generated_bulks.size() - 1]
					if bulk.size() > 0:
						outputs[out_name] = bulk[0]
				elif node.inputs.size() > 0 and node.inputs[0] != null:
					outputs[out_name] = node.inputs[0]
	_publish_flow_variables(ctx, parent_ctx)
	return outputs
