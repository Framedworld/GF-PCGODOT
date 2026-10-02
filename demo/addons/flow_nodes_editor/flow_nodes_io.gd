extends Node
class_name FlowNodeIO

# Here are all functions related to read/write the resources, including
# serialization to/from json for the clipboard

const LOAD_PROGRESS_CHUNK_SIZE := 8
const FAST_GRAPH_LOAD_NODE_THRESHOLD := 24

# Settings keys that are only written when non-empty, so graphs that never use the
# feature serialise exactly as before (no new key on every node).
const OMIT_WHEN_EMPTY_PROPS := { "bindings": true }

static func resource_to_dict(resource: Resource) -> Dictionary:
	var dict := {}
	for prop in resource.get_property_list():
		if prop.name in FlowNodeAssets.discarded_props:
			continue
		if prop.usage & PROPERTY_USAGE_STORAGE != 0:
			var name = prop.name
			var value = resource.get(name)
			if OMIT_WHEN_EMPTY_PROPS.has(name) and value is Dictionary and value.is_empty():
				continue
			dict[name] = value
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
		if name in FlowNodeAssets.discarded_props:
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
			"position" : ( node.position_offset / editor.ui_scale ) - min_pos,
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
			"position" : ( node.position_offset / editor.ui_scale ) - min_pos,
			"size" : node.size,
			"name" : node.name,
			"tint_color" : node.tint_color,
			"title" : node.title,
			"attached" : attached,
		}
	)

	var data := {
		"type" : "flow_graph_nodes",
		"version" : FlowGraphMigrations.CURRENT_VERSION,
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
	# Clipboard JSON (and resources loaded outside loadFromResource) may predate the
	# current graph format. No-op when already current.
	dict = FlowGraphMigrations.migrate(dict)
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

	var attached_names := {}
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
			if _attach_graph_node_to_frame_if_available(editor, new_name, frame.name, attached_names):
				continue

	if editor.has_method("refreshVariableNodes"):
		editor.refreshVariableNodes()
	if editor.has_method("repair_graph_integrity"):
		editor.repair_graph_integrity()
	return new_nodes

static func create_nodes_from_dict_with_progress(dict, editor: Control, paste_offset = null, progress_callback: Callable = Callable(), start_progress := 45.0, end_progress := 92.0) -> Array:
	if dict.get("type", null) != "flow_graph_nodes":
		push_error("Invalid dict to paste nodes from")
		return []
	dict = FlowGraphMigrations.migrate(dict)

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

	var attached_names := {}
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
			if _attach_graph_node_to_frame_if_available(editor, new_name, frame.name, attached_names):
				continue
		completed_steps += 1
		if _should_report_load_progress(completed_steps, total_steps):
			await _report_load_progress(progress_callback, "Restoring Frames...", completed_steps, total_steps, start_progress, end_progress)

	if editor.has_method("refreshVariableNodes"):
		editor.refreshVariableNodes()
	if editor.has_method("repair_graph_integrity"):
		editor.repair_graph_integrity()
	return new_nodes

static func _can_attach_graph_node(editor: Control, node_name: StringName) -> bool:
	if String(node_name).is_empty():
		return false
	if editor.has_method("_has_graph_node"):
		return editor._has_graph_node(node_name)
	var gedit: GraphEdit = editor.gedit
	if gedit == null:
		return false
	var node: GraphNode = gedit.get_node_or_null(NodePath(node_name)) as GraphNode
	return node != null and is_instance_valid(node) and node.get_parent() == gedit

static func _attach_graph_node_to_frame_if_available(
	editor: Control,
	node_name,
	frame_name: StringName,
	attached_names: Dictionary
) -> bool:
	if node_name == null:
		return false
	var attach_name := StringName(node_name)
	if attached_names.has(attach_name):
		return false
	if editor.has_method("_attach_graph_node_to_frame_if_available"):
		return editor._attach_graph_node_to_frame_if_available(attach_name, frame_name, attached_names)
	if not _can_attach_graph_node(editor, attach_name):
		return false
	var frame: GraphFrame = editor.gedit.get_node_or_null(NodePath(frame_name)) as GraphFrame
	if frame == null or frame.get_parent() != editor.gedit:
		return false
	if editor.gedit.get_element_frame(attach_name) != null:
		return false
	editor.gedit.attach_graph_element_to_frame(attach_name, frame_name)
	attached_names[attach_name] = true
	return true

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
		return n is GraphFrame and not n.has_meta("flow_retired")
	)
	current_resource.data = nodes_as_dict( all_nodes, all_frames, editor )
	current_resource.view_zoom = gedit.zoom
	current_resource.view_offset = gedit.scroll_offset
	current_resource.new_name_counter = editor.new_name_counter

## Editor load: upgrades an old graph resource in memory to the current format and
## marks it dirty, so the next save writes the current version. Returns true when the
## resource data changed.
static func migrate_resource_for_editor(editor: Control, resource: FlowGraphResource) -> bool:
	if resource == null or resource.data.is_empty():
		return false
	var migrated: Dictionary = FlowGraphMigrations.migrate(resource.data)
	if is_same(migrated, resource.data):
		return false
	resource.data = migrated
	if editor != null and editor.has_method("queueSave"):
		editor.queueSave()
	return true

static func loadFromResource( editor : Control ):
	var current_resource = editor.current_resource
	if current_resource == null:
		return
	migrate_resource_for_editor(editor, current_resource)

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
	if editor.has_method("repair_graph_integrity"):
		editor.repair_graph_integrity()

static func loadFromResourceWithProgress(editor: Control, progress_callback: Callable = Callable()) -> void:
	var current_resource = editor.current_resource
	if current_resource == null:
		return

	if editor.has_method("_should_use_fast_graph_load") and editor._should_use_fast_graph_load(current_resource):
		loadFromResource(editor)
		return
	migrate_resource_for_editor(editor, current_resource)

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
	if editor.has_method("repair_graph_integrity"):
		editor.repair_graph_integrity()

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


static func _publish_runtime_params(child_ctx: FlowData.EvaluationContext, parent_ctx: FlowData.EvaluationContext, local_params: Dictionary) -> void:
	if parent_ctx == null:
		return
	for key in child_ctx.runtime_params.keys():
		var runtime_key := str(key)
		if _is_local_runtime_param(runtime_key) or local_params.has(runtime_key):
			continue
		parent_ctx.runtime_params[runtime_key] = child_ctx.runtime_params[key]


static func _is_local_runtime_param(runtime_key: String) -> bool:
	return runtime_key in [
		"__eval_depth",
		"debug_enabled",
		"flow_analyze_node",
		"flow_suppress_preview_side_effects",
		"flow_suppress_seed_advance",
		# Mirrored from ctx.seed per evaluation; a loop iteration's derived seed
		# must never leak into the parent context.
		"seed",
	]


static func _is_topo_final_root(node: FlowNodeBase) -> bool:
	if node.node_template == "output" or node.node_template.begins_with("output_"):
		return true
	if node.settings.inspect_enabled or node.settings.debug_enabled:
		return true
	if not node.getMeta().get("is_final", false):
		return false
	# Subgraph nodes with downstream consumers are reached through those consumers.
	# A terminal subgraph is itself the execution root for graphs that intentionally
	# end at subgraph side effects instead of output nodes.
	if node.node_template == "subgraph":
		for conn in node.deps:
			if not conn.get("virtual_variable", false):
				return node.dependants.is_empty()
	return true


static func _needs_input_order_stabilization(node: FlowNodeBase) -> bool:
	if node.node_template == "subgraph":
		return true
	# Final nodes that also consume other nodes' outputs can be scheduled too early
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


## Shared execution order for evaluate_graph() and the editor's evalGraph().
## node_list entries must already have physical deps; call _add_virtual_variable_dependencies first when needed.
static func build_execution_order(node_list: Array, instances_by_name: Dictionary) -> Array:
	var ordered_nodes: Array = []
	var visited: Dictionary = {}
	var visit_node = func(node, on_stack: Dictionary, this_func) -> void:
		if visited.has(node.name):
			return
		if on_stack.has(node.name):
			push_warning("Circular dependency detected involving node: " + node.name)
			return
		on_stack[node.name] = true
		for conn in node.deps:
			var dep_node = instances_by_name.get(conn.from_node)
			if dep_node:
				this_func.call(dep_node, on_stack, this_func)
		on_stack.erase(node.name)
		visited[node.name] = true
		ordered_nodes.append(node)

	var finals = node_list.filter(func(node):
		if node.settings != null and node.settings.disabled:
			return false
		return _is_topo_final_root(node)
	)
	for node in finals:
		visit_node.call(node, {}, visit_node)
	_stabilize_variable_execution_order(ordered_nodes)
	_stabilize_consumer_input_order(ordered_nodes)
	return ordered_nodes


# FlowNodeBase extends GraphNode (a Control, not RefCounted). evaluate_graph
# instantiates the whole graph without ever adding the nodes to the tree, so
# they must be freed explicitly — otherwise every runtime evaluation leaks the
# full node graph (and loop.gd evaluates once per element).
static func _free_node_instances(node_list: Array) -> void:
	for node in node_list:
		if is_instance_valid(node):
			node.free()

# Runtime args (e.g. FlowGraphNode3D.args) may hold raw primitives instead of
# FlowData.Data. Wrap supported primitives into a single-entry Data whose
# stream is named after the input param, so graph-input constants work at
# runtime. Falsy primitives (0, 0.0, "") are valid values — hence the explicit
# null/type checks instead of truthiness.
static func _coerce_input_data(val, input_name: String):
	if val == null:
		return null
	if val is FlowData.Data:
		return val
	var data_type = FlowNodeBase.getFlowDataTypeFromObject(val)
	if data_type == FlowData.DataType.Invalid:
		push_warning("evaluate_graph: input '%s' got unsupported runtime value of type %s — expected FlowData.Data or float/int/bool/String/Vector3/Color" % [input_name, type_string(typeof(val))])
		return null
	# An input named like a canonical attribute (density, seed, ...) takes that
	# attribute's numeric type, so `{"density": 1}` still registers as Float.
	data_type = FlowData.canonical_numeric_type(input_name, data_type)
	var data = load("res://addons/flow_nodes_editor/flow_data.gd").Data.new()
	var container = data.addStream(input_name, data_type)
	if container == null:
		push_warning("evaluate_graph: could not wrap runtime input '%s' (data_type %d)" % [input_name, data_type])
		return null
	container.resize(1)
	# Use the typed writer rather than `container[0] = val`: primitive streams are
	# backed by Packed*Array (PackedByteArray for Bool, PackedInt32Array for Int,
	# PackedStringArray for String, ...). Direct subscript assignment of a raw
	# bool/int/String into the wrong packed type crashes or silently coerces the
	# runtime feed — the original primitive-graph-input bug. writeValue() casts to
	# the container's element type, matching the generic-input default-value path.
	FlowData.Data.writeValue(container, 0, val, data_type)
	return data

# ---------------------------------------------------------------------------
# Per-instance overrides and $param bindings (RUNTIME_API_P0 §4).
#
# Precedence for a node setting at evaluation time, highest first:
#   1. a wired parameter port (getSettingValue reads the connected input at
#      execute time, so it wins over whatever is written here)
#   2. a per-instance override  (ctx.overrides, from FlowGraphNode3D.overrides)
#   3. a $param binding         (NodeSettings.bindings)
#   4. the value saved in the graph resource
# ---------------------------------------------------------------------------

## Meta key on an EvaluationContext holding the Dictionary of override keys that
## matched at least one node anywhere in the current evaluation tree.
const OVERRIDE_HITS_META := &"flow_override_hits"

## True when `settings` could be changed by apply_setting_bindings under `ctx`:
## the context carries overrides or the settings declare bindings. Cheap; lets the
## evaluators skip all binding work for graphs that use neither.
static func has_setting_bindings(settings: Resource, ctx: FlowData.EvaluationContext) -> bool:
	if settings == null:
		return false
	if ctx != null and ctx.overrides != null and not ctx.overrides.is_empty():
		return true
	if not ("bindings" in settings):
		return false
	var bindings = settings.get("bindings")
	return bindings is Dictionary and not bindings.is_empty()

## Applies the context's per-instance overrides, then the node's $param bindings,
## to `target_settings` (default: node_instance.settings). Overrides are keyed
## "<node_name>/<property>", optionally prefixed "<graph basename>:" to target one
## subgraph; a property set by an override is not rebound. A setting name may also
## address one entry of a Dictionary-typed setting as "<dict_property>/<key>"
## (e.g. binding "args/theme", override "node/args/theme"); on an Expression node a
## bare name that is an existing key of its `args` resolves to "args/<name>". Bindings resolve
## "property" -> "param" against input_data_map, then ctx.runtime_params, then
## ctx.variables (a FlowData.Data value yields its first element), then the default
## of `graph`'s declared input of that name (graph.in_params). A missing
## parameter keeps the saved value silently; a value that cannot be assigned to the
## property keeps it with a warning. Does not call refreshFromSettings.
## Returns true when at least one setting was written.
static func apply_setting_bindings(node_instance: FlowNodeBase, graph: FlowGraphResource, ctx: FlowData.EvaluationContext, input_data_map: Dictionary = {}, target_settings: Resource = null) -> bool:
	if node_instance == null or ctx == null:
		return false
	var settings: Resource = target_settings if target_settings != null else node_instance.settings
	if settings == null:
		return false
	var node_name := String(node_instance.name)
	var changed := false
	var overridden := {}

	if ctx.overrides != null and not ctx.overrides.is_empty():
		var graph_name := graph_basename(graph)
		var hits = ctx.get_meta(OVERRIDE_HITS_META, null)
		for key in ctx.overrides:
			var target := _parse_override_key(str(key))
			if target.is_empty() or target.node != node_name:
				continue
			if not target.scope.is_empty() and target.scope != graph_name:
				continue
			var override_target := _resolve_setting_target(settings, target.prop)
			if override_target.is_empty():
				continue
			if hits is Dictionary:
				hits[key] = true
			if _assign_setting_target(settings, override_target, ctx.overrides[key], node_name, "override '%s'" % key):
				changed = true
				overridden[override_target.id] = true

	if "bindings" in settings:
		var bindings = settings.get("bindings")
		if bindings is Dictionary and not bindings.is_empty():
			for prop in bindings:
				var prop_name := str(prop)
				var param_name := str(bindings[prop]).strip_edges().trim_prefix("$")
				if prop_name.is_empty() or param_name.is_empty():
					continue
				var binding_target := _resolve_setting_target(settings, prop_name)
				if binding_target.is_empty():
					push_warning("Flow: node '%s' binds unknown setting '%s' to '$%s'; ignored." % [node_name, prop_name, param_name])
					continue
				if overridden.has(binding_target.id):
					continue
				var resolved := _resolve_binding_param(param_name, ctx, input_data_map, graph)
				if resolved.is_empty():
					continue
				if _assign_setting_target(settings, binding_target, resolved[0], node_name, "binding '$%s'" % param_name):
					changed = true
	return changed

## Editor evaluation path: when overrides/bindings apply to `node`, swaps a scratch
## duplicate of its settings in (the authored resource is never written, so it is
## never dirtied, saved or re-emitted as changed) and returns the authored settings
## to hand back to end_scratch_setting_bindings() after the node ran. Returns null,
## leaving the node untouched, when nothing applies.
static func begin_scratch_setting_bindings(node: FlowNodeBase, graph: FlowGraphResource, ctx: FlowData.EvaluationContext, input_data_map: Dictionary = {}) -> Resource:
	if node == null or node.settings == null or not has_setting_bindings(node.settings, ctx):
		return null
	var authored: Resource = node.settings
	var scratch: Resource = authored.duplicate()
	if not apply_setting_bindings(node, graph, ctx, input_data_map, scratch):
		return null
	node.settings = scratch
	return authored

## Restores the settings returned by begin_scratch_setting_bindings(). No-op on null.
static func end_scratch_setting_bindings(node: FlowNodeBase, authored: Resource) -> void:
	if node == null or authored == null or not is_instance_valid(node):
		return
	node.settings = authored

## Name used for "<graph>:" override prefixes: the graph file's basename
## ("res://graphs/style_room_default.tres" -> "style_room_default"). Graphs without
## a file of their own (in-memory or embedded) fall back to their resource_name.
static func graph_basename(graph: Resource) -> String:
	if graph == null:
		return ""
	var path := graph.resource_path
	if path.is_empty() or path.contains("::"):
		return String(graph.resource_name)
	return path.get_file().get_basename()

static func _is_bindable_setting(settings: Resource, prop: String) -> bool:
	if prop == "bindings" or FlowNodeAssets.discarded_props.has(prop):
		return false
	return prop in settings

## Resolves a binding/override setting name to what it writes:
##   "<property>"              -> { prop, id }            a plain setting property
##   "<dict_property>/<key>"   -> { prop, key, id }       one entry of a Dictionary setting
##   "<name>" on an Expression -> { prop: "args", key, id } when <name> is an existing args key
## `id` is the canonical "<prop>" / "<prop>/<key>" form (an override on an id stops a
## binding on the same id). Returns {} when the name matches none of these.
static func _resolve_setting_target(settings: Resource, name: String) -> Dictionary:
	if name.is_empty():
		return {}
	if _is_bindable_setting(settings, name):
		return { "prop": name, "id": name }
	var slash := name.find("/")
	if slash > 0 and slash < name.length() - 1:
		var dict_prop := name.substr(0, slash)
		var key := name.substr(slash + 1)
		if _is_bindable_setting(settings, dict_prop) and settings.get(dict_prop) is Dictionary:
			return { "prop": dict_prop, "key": key, "id": name }
		return {}
	if settings is ExpressionNodeSettings:
		var args = settings.get("args")
		if args is Dictionary and _dict_key_matching(args, name) != null:
			return { "prop": "args", "key": name, "id": "args/" + name }
	return {}

# The key of `dict` whose string form is `key` (String or StringName keys), or null.
static func _dict_key_matching(dict: Dictionary, key: String):
	if dict.has(key):
		return key
	for k in dict:
		if str(k) == key:
			return k
	return null

# Writes `value` into the setting described by a _resolve_setting_target() result.
# A Dictionary entry is coerced to the type of the entry it replaces (any value when
# the key is new) and written into a fresh copy of the Dictionary, never in place:
# the editor's scratch settings duplicate shares its containers with the authored one.
static func _assign_setting_target(settings: Resource, target: Dictionary, value, node_name: String, source_label: String) -> bool:
	if not target.has("key"):
		return _assign_setting(settings, target.prop, value, node_name, source_label)
	var dict = settings.get(target.prop)
	if not (dict is Dictionary):
		return false
	var existing_key = _dict_key_matching(dict, target.key)
	var current = dict[existing_key] if existing_key != null else null
	var coerced := _coerce_setting_value(value, { "type": typeof(current) }, current)
	if coerced.is_empty():
		push_warning("Flow: %s cannot assign %s value %s to setting '%s' (%s) of node '%s'; keeping the saved value." % [
			source_label, type_string(typeof(value)), str(value), target.id, type_string(typeof(current)), node_name])
		return false
	var updated: Dictionary = dict.duplicate()
	updated[existing_key if existing_key != null else target.key] = coerced[0]
	settings.set(target.prop, updated)
	return true

static func _parse_override_key(key: String) -> Dictionary:
	var scope := ""
	var rest := key
	var colon := key.find(":")
	if colon >= 0:
		scope = key.substr(0, colon)
		rest = key.substr(colon + 1)
	# "<node>/<property>" or "<node>/<dict_property>/<key>": the node name is up to
	# the first "/", the rest is the setting name (see _resolve_setting_target).
	var slash := rest.find("/")
	if slash <= 0 or slash >= rest.length() - 1:
		return {}
	return { "scope": scope, "node": rest.substr(0, slash), "prop": rest.substr(slash + 1) }

# Context the bindings of one graph level resolve against: what the child ctx
# built later in _build_evaluation_state will hold (parent overrides, parent +
# local runtime params, inherited variables), without copying anything deeply.
static func _binding_scope_context(graph: FlowGraphResource, parent_ctx: FlowData.EvaluationContext, runtime_params: Dictionary, override_hits: Dictionary) -> FlowData.EvaluationContext:
	var scope = load("res://addons/flow_nodes_editor/flow_data.gd").EvaluationContext.new()
	scope.graph = graph
	scope.owner = parent_ctx.owner
	scope.overrides = parent_ctx.overrides
	var parent_params: Dictionary = parent_ctx.runtime_params if parent_ctx.runtime_params else {}
	scope.runtime_params = parent_params.merged(runtime_params, true)
	scope.variables = parent_ctx.variables
	scope.set_meta(OVERRIDE_HITS_META, override_hits)
	return scope

# Returns [value] when `param_name` resolves, [] when it is absent everywhere.
# Sources, first hit wins: input_data_map, ctx.runtime_params, ctx.variables, then
# the default of the graph's own declared input (`graph.in_params`) of that name,
# so one declared graph input can single-source a knob in dock previews (which
# feed no inputs) as well as at runtime.
static func _resolve_binding_param(param_name: String, ctx: FlowData.EvaluationContext, input_data_map: Dictionary, graph: FlowGraphResource = null) -> Array:
	for source in [input_data_map, ctx.runtime_params, ctx.variables]:
		if source == null or not source.has(param_name):
			continue
		var value = source[param_name]
		if value is FlowData.Data:
			value = _first_value_of(value, param_name)
		if value != null:
			return [value]
	if graph != null:
		for param in graph.in_params:
			if param != null and param.name == param_name:
				var default_value = param.get_default_value()
				if default_value != null:
					return [default_value]
				break
	return []

# Element 0 of stream `name` (or of the per-data attribute `name` / "@data.<name>").
# A Data holding exactly one stream yields that stream's first element whatever its
# name, mirroring how the graph-input feed treats a Data's main stream. Bool streams
# are stored as bytes and come back as bool. Returns null when nothing matches.
static func _first_value_of(data: FlowData.Data, name: String):
	if data == null:
		return null
	var attr_name := name.trim_prefix(FlowData.DataAttrPrefix)
	if not data.streams.has(name) and data.data_attrs.has(attr_name):
		return data.data_attrs[attr_name].get("value", null)
	var stream = data.streams.get(name, null)
	if stream == null and data.streams.size() == 1:
		stream = data.streams.values()[0]
	if stream == null or stream.container == null or stream.container.size() == 0:
		return null
	var value = stream.container[0]
	if stream.data_type == FlowData.DataType.Bool:
		return bool(value)
	return value

# Writes `value` into settings[prop] when the types are compatible (with int<->float
# and String<->StringName coercion); otherwise warns and keeps the current value.
static func _assign_setting(settings: Resource, prop: String, value, node_name: String, source_label: String) -> bool:
	var info := {}
	for p in settings.get_property_list():
		if p.name == prop:
			info = p
			break
	if info.is_empty():
		return false
	var coerced := _coerce_setting_value(value, info, settings.get(prop))
	if coerced.is_empty():
		push_warning("Flow: %s cannot assign %s value %s to setting '%s' (%s) of node '%s'; keeping the saved value." % [
			source_label, type_string(typeof(value)), str(value), prop, type_string(int(info.type)), node_name])
		return false
	settings.set(prop, coerced[0])
	return true

# Returns [coerced_value] or [] when `value` cannot be assigned to the property.
static func _coerce_setting_value(value, info: Dictionary, current) -> Array:
	var target_type := int(info.type)
	var value_type := typeof(value)
	if target_type == TYPE_NIL:
		return [value]
	match target_type:
		TYPE_FLOAT:
			if value_type == TYPE_FLOAT or value_type == TYPE_INT:
				return [float(value)]
		TYPE_INT:
			if value_type == TYPE_INT:
				return [value]
			if value_type == TYPE_FLOAT:
				return [int(value)]
		TYPE_STRING:
			if value_type == TYPE_STRING or value_type == TYPE_STRING_NAME:
				return [String(value)]
		TYPE_STRING_NAME:
			if value_type == TYPE_STRING or value_type == TYPE_STRING_NAME:
				return [StringName(value)]
		TYPE_VECTOR2:
			if value_type == TYPE_VECTOR2 or value_type == TYPE_VECTOR2I:
				return [Vector2(value)]
		TYPE_VECTOR3:
			if value_type == TYPE_VECTOR3 or value_type == TYPE_VECTOR3I:
				return [Vector3(value)]
		TYPE_ARRAY:
			if value_type == TYPE_ARRAY:
				if current is Array and current.is_typed():
					# Build a fresh array of the property's element type; never
					# mutate `current` (the editor's scratch duplicate may share it).
					var element_type: int = current.get_typed_builtin()
					var typed: Array = current.duplicate()
					typed.clear()
					for item in value:
						if element_type == TYPE_OBJECT:
							if item != null and not (item is Object):
								return []
						elif typeof(item) != element_type:
							return []
						typed.append(item)
					return [typed]
				return [value]
		TYPE_OBJECT:
			if value == null:
				return [null]
			if value_type != TYPE_OBJECT:
				return []
			var class_hint := str(info.get("hint_string", ""))
			if int(info.get("hint", 0)) == PROPERTY_HINT_RESOURCE_TYPE and not class_hint.is_empty():
				if not _object_is_class(value, class_hint):
					return []
			return [value]
		_:
			if value_type == target_type:
				return [value]
	return []

static func _object_is_class(value: Object, class_hint: String) -> bool:
	for class_name_hint in class_hint.split(","):
		var wanted := class_name_hint.strip_edges()
		if wanted.is_empty() or value.is_class(wanted):
			return true
		var script: Script = value.get_script()
		while script != null:
			if String(script.get_global_name()) == wanted:
				return true
			script = script.get_base_script()
	return false

# Reports, once per evaluation tree, every override key that matched no node.
static func _warn_unmatched_overrides(overrides: Dictionary, hits: Dictionary) -> void:
	if overrides == null or overrides.is_empty():
		return
	for key in overrides:
		if not hits.has(key):
			push_warning("Flow: override '%s' matched no node setting in this evaluation (expected \"[graph:]node_name/property\" or \"[graph:]node_name/dict_property/key\")." % str(key))

# Runtime counterpart of the editor's args_port bookkeeping: remember which
# parameter ports are actually wired so getSettingValue can read them. Only
# connected ports past the flow inputs are restored (stale unconnected entries are
# ignored, matching what the editor rebuilds in initFromScript).
static func _restore_wired_param_ports(instance: FlowNodeBase, n_data: Dictionary) -> void:
	var saved_ports = n_data.get("args_port", {})
	if not (saved_ports is Dictionary) or saved_ports.is_empty():
		return
	var num_flow_ins: int = instance.getMeta().get("ins", []).size()
	for arg_name in saved_ports:
		var entry = saved_ports[arg_name]
		if not (entry is Dictionary) or not entry.get("connected", false):
			continue
		var port := int(entry.get("port", -1))
		if port < num_flow_ins:
			continue
		instance.args_ports_by_name[arg_name] = { "port": port, "connected": true }

# ---------------------------------------------------------------------------
# Resumable evaluator foundation (PARITY_ROADMAP "Async / proximity runtime
# generation", stage 2 only — time-slicing).
#
# The evaluation has three phases:
#   1. _build_evaluation_state(): instance nodes, build deps, topo-sort, build
#      the EvaluationContext, feed graph inputs. (Cheap; done up front.)
#   2. execution of the ordered node list — the only resumable part. Each node
#      is run by _execute_single_node().
#   3. _finalize_evaluation(): collect outputs, publish flow variables, free the
#      instanced node Controls.
#
# evaluate_graph() runs all three phases synchronously in one call and is
# byte-for-byte identical to the historical behavior (it just drives the same
# helpers to completion). GraphEvaluation exposes the same work as a resumable
# state object with a step(budget_ms) method, so a host (FlowGraphNode3D with
# async_generation = true) can spread phase 2 across frames. Topo sort, cycle
# detection, variable/runtime-param publishing and node-instance freeing are
# shared by both paths — there is a single execution implementation.
# ---------------------------------------------------------------------------

# Phase 1: instance + order + context + feed inputs. Returns a state Dictionary,
# or {} on the recursion-guard trip (mirroring evaluate_graph's early return).
static func _build_evaluation_state(graph: FlowGraphResource, input_data_map: Dictionary, parent_ctx: FlowData.EvaluationContext, runtime_params: Dictionary, depth: int) -> Dictionary:
	var instances = {}
	var node_list = []
	# Overrides / $param bindings (RUNTIME_API_P0 §4). The scope context is built
	# lazily, only when a node actually has something to apply.
	var owns_override_hits := not parent_ctx.has_meta(OVERRIDE_HITS_META)
	var override_hits: Dictionary = parent_ctx.get_meta(OVERRIDE_HITS_META, {})
	var binding_scope: FlowData.EvaluationContext = null
	# Upgrade old graph data to the current format before instantiating nodes. Returns
	# the resource's own dictionary when already current; never writes back.
	var graph_data: Dictionary = FlowGraphMigrations.migrate(graph.data)
	for n_data in graph_data.get("nodes", []):
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
		var raw_instance = node_script.new()
		var instance := raw_instance as FlowNodeBase
		if instance == null:
			push_error("Node script is not a FlowNodeBase: %s" % script_path)
			if raw_instance is Node:
				raw_instance.free()
			continue
		instance.name = name
		instance.node_template = template

		# Initialize settings resource if defined. Nodes without a settings
		# class (e.g. merge_points) fall back to the base NodeSettings,
		# mirroring the editor — the evaluator reads settings.disabled and
		# settings.debug_enabled on every node.
		var meta = instance.getMeta()
		if meta.has("settings") and meta.settings:
			instance.settings = meta.settings.new()
		else:
			instance.settings = NodeSettings.new()

		# Apply saved settings
		var saved_settings = n_data.get("settings", {})
		dict_to_resource(saved_settings, instance.settings)
		_stabilize_missing_seed(instance.settings, name, template, saved_settings)
		if has_setting_bindings(instance.settings, parent_ctx):
			if binding_scope == null:
				binding_scope = _binding_scope_context(graph, parent_ctx, runtime_params, override_hits)
			apply_setting_bindings(instance, graph, binding_scope, input_data_map)

		instance.refreshFromSettings()
		_restore_wired_param_ports(instance, n_data)

		instances[name] = instance
		node_list.append(instance)

	# Build connections (deps and dependants)
	for conn in graph_data.get("links", []):
		var src_node = instances.get(conn.from_node)
		var dst_node = instances.get(conn.to_node)
		if src_node and dst_node:
			src_node.dependants.append(conn)
			dst_node.deps.append(conn)
	_add_virtual_variable_dependencies(node_list)
	var ordered_nodes: Array = build_execution_order(node_list, instances)

	# Construct EvaluationContext for subgraph
	var ctx = load("res://addons/flow_nodes_editor/flow_data.gd").EvaluationContext.new()
	ctx.graph = graph
	# parent_ctx.owner may be null (owner-less evaluation); owner-dependent
	# nodes report it themselves.
	ctx.owner = parent_ctx.owner
	# Copied verbatim: only make_context()/the editor assign the counter, so
	# legacy callers that hand-build a context (some store a seed in eval_id)
	# stay byte-identical.
	ctx.eval_id = parent_ctx.eval_id
	# Seed, component identity and per-instance overrides flow into nested
	# subgraph/loop evaluations unchanged (loop derives per-iteration seeds by
	# setting parent_ctx.seed around its call).
	ctx.seed = parent_ctx.seed
	ctx.component_id = parent_ctx.component_id
	ctx.overrides = parent_ctx.overrides
	ctx.preview = parent_ctx.preview
	ctx.gedit_nodes_by_name = instances
	ctx.runtime_params = parent_ctx.runtime_params.duplicate(true) if parent_ctx.runtime_params else {}
	for key in runtime_params.keys():
		ctx.runtime_params[key] = runtime_params[key]
	ctx.runtime_params["seed"] = ctx.seed
	ctx.runtime_params["__eval_depth"] = depth
	ctx.set_meta("flow_eval_depth", depth)
	ctx.set_meta(OVERRIDE_HITS_META, override_hits)
	# Nested evaluations share the root's error log. A custom node that builds its
	# own context still reports into the synchronous evaluation around it.
	var error_log = parent_ctx.get_meta(FlowNodeBase.ERROR_LOG_META) if parent_ctx.has_meta(FlowNodeBase.ERROR_LOG_META) else _sync_error_log
	if error_log is Array:
		ctx.set_meta(FlowNodeBase.ERROR_LOG_META, error_log)
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
			var val = _coerce_input_data(input_data_map.get(specific_input_name, null), specific_input_name)
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
					# A canonical attribute name (density, seed, ...) only aliases a
					# main stream of that attribute's type.
					if FlowData.canonical_type_error(specific_input_name, main_stream.data_type) == "":
						target_data.registerStream(specific_input_name, main_stream.container, main_stream.data_type)
				# Carry per-data domain attributes, tags, kind and shape across the subgraph boundary.
				target_data.copy_meta_from(val)
				node.set_output(0, target_data)
		elif node.node_template == "input":
			# Generic multi-port inputs node
			for i in range(graph.in_params.size()):
				var param = graph.in_params[i]
				if param:
					var val = _coerce_input_data(input_data_map.get(param.name, null), param.name)
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
							if FlowData.canonical_type_error(param.name, main_stream.data_type) == "":
								target_data.registerStream(param.name, main_stream.container, main_stream.data_type)
						target_data.copy_meta_from(val)
					else:
						var new_value = param.get_default_value()
						var container = target_data.addStream(param.name, param.data_type)
						if container != null:
							container.resize(1)
							FlowData.Data.writeValue(container, 0, new_value, param.data_type)
					node.set_output(i, target_data)

	return {
		"graph": graph,
		"parent_ctx": parent_ctx,
		"instances": instances,
		"node_list": node_list,
		"ordered_nodes": ordered_nodes,
		"ctx": ctx,
		# Local overrides passed into THIS subgraph invocation. Carried so
		# _finalize_evaluation can tell _publish_runtime_params which keys are
		# local (must not leak to the parent) vs. genuinely produced downstream.
		"local_params": runtime_params,
		# The outermost evaluation owns the override hit set and reports unmatched
		# override keys once, after every nested subgraph/loop evaluation has run.
		"owns_override_hits": owns_override_hits,
	}


# Phase 2 (one node): identical body to the historical inline execution loop.
# Shared verbatim by the synchronous path and the resumable step() so the two
# can never diverge.
static func _execute_single_node(node, instances: Dictionary, graph: FlowGraphResource, ctx: FlowData.EvaluationContext) -> void:
	if (node.node_template.begins_with("input_") or node.node_template == "input") and node.generated_bulks.size() > 0:
		return

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
				# Links into exposed setting ports (to_port >= meta ins) are legal;
				# grow the input array instead of failing the whole evaluation.
				if conn.to_port >= node.inputs.size():
					node.inputs.resize(conn.to_port + 1)
				node.inputs[conn.to_port] = src_bulk[conn.from_port]

	node.preExecute(ctx)
	if node.settings != null and node.settings.disabled:
		node.executedDisabled(ctx)
	elif not FlowVariableEval.try_fast_execute(node, ctx, instances):
		node.run(ctx)
	if FlowVariableEval.should_refresh_debug_draw(node):
		node.setupDrawDebug()


# Phase 3: collect outputs, publish variables, free instances. Identical to the
# historical tail of evaluate_graph.
static func _finalize_evaluation(state: Dictionary) -> Dictionary:
	var graph: FlowGraphResource = state["graph"]
	var node_list: Array = state["node_list"]
	var ctx: FlowData.EvaluationContext = state["ctx"]
	var parent_ctx: FlowData.EvaluationContext = state["parent_ctx"]
	var local_params: Dictionary = state.get("local_params", {})

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
	_publish_runtime_params(ctx, parent_ctx, local_params)
	if state.get("owns_override_hits", false):
		_warn_unmatched_overrides(ctx.overrides, ctx.get_meta(OVERRIDE_HITS_META, {}))

	# Outputs are collected (FlowData.Data is RefCounted, so the references in
	# `outputs` keep the data alive) — free the instanced node Controls now.
	_free_node_instances(node_list)
	return outputs


## Build a root EvaluationContext (docs/RUNTIME_API_P0.md §3).
## `owner` may be null for owner-less evaluation. Any Node3D can host the
## evaluation (spawned content is parented under it and tagged with its
## instance id); a FlowGraphNode3D additionally contributes its `overrides`.
## `params` become ctx.runtime_params, with "seed" mirrored from `seed`.
## `overrides` ("node_name/property" -> value) are merged over the owner's.
## eval_id starts at 0 here; nested evaluations copy the parent's verbatim.
static func make_context(owner : Node3D = null, seed : int = 0, params : Dictionary = {},
		overrides : Dictionary = {}) -> FlowData.EvaluationContext:
	var ctx = load("res://addons/flow_nodes_editor/flow_data.gd").EvaluationContext.new()
	ctx.owner = owner
	ctx.component_id = owner.get_instance_id() if owner != null else 0
	var merged_overrides := {}
	if owner != null:
		var owner_overrides = owner.get("overrides")
		if owner_overrides is Dictionary:
			merged_overrides = owner_overrides.duplicate()
	if overrides:
		merged_overrides.merge(overrides, true)
	ctx.overrides = merged_overrides
	ctx.seed = seed
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = params.duplicate(true) if params else {}
	ctx.runtime_params["seed"] = seed
	return ctx


## Errors raised (FlowNodeBase.setError) during the most recent top-level
## FlowNodeIO.evaluate() or FlowGraphNode3D.generate()/generate_async(), in the
## order they were raised, nested subgraph and loop evaluations included:
## [{ "node": <node name>, "template": <template>, "message": <text> }, ...].
## Reset at the start of every top-level evaluation; empty when nothing failed.
static var last_errors : Array = []

# Error log of the synchronous top-level evaluation in progress (null otherwise).
static var _sync_error_log = null

## Runs `graph` from the root context `ctx` (depth 0) and collects every node
## error into `ctx`'s error log. Sets last_errors and returns
## { "outputs": Dictionary, "errors": Array }. Used by evaluate() and
## FlowGraphNode3D.generate(). A nested call (a node that calls evaluate())
## also reports its errors to the evaluation around it.
static func evaluate_collecting_errors(graph : FlowGraphResource, input_data_map : Dictionary, ctx : FlowData.EvaluationContext) -> Dictionary:
	var error_log := start_error_log(ctx)
	var outer = _sync_error_log
	_sync_error_log = error_log
	var outputs := evaluate_graph(graph, input_data_map, ctx, {}, 0)
	_sync_error_log = outer
	if outer is Array:
		outer.append_array(error_log)
	last_errors = error_log
	return { "outputs": outputs, "errors": error_log }

## Attaches a fresh error log to the root context `ctx`, resets last_errors to
## it and returns it. The async path (FlowGraphNode3D.generate_async) calls this
## before begin_evaluation().
static func start_error_log(ctx : FlowData.EvaluationContext) -> Array:
	var error_log : Array = []
	ctx.set_meta(FlowNodeBase.ERROR_LOG_META, error_log)
	last_errors = error_log
	return error_log

## One-call evaluation: builds a context with make_context() and runs
## evaluate_graph(). `inputs` maps graph input names to FlowData.Data or plain
## values (float/int/bool/String/Vector3/Color). Returns the graph outputs,
## name -> FlowData.Data. With `owner == null`, owner-dependent nodes
## (spawners, scene scanners, apply_on_actor) report an error and pass their
## input through. The run's node errors are in FlowNodeIO.last_errors.
static func evaluate(graph : FlowGraphResource, inputs : Dictionary = {}, seed : int = 0,
		params : Dictionary = {}, owner : Node3D = null, overrides : Dictionary = {}) -> Dictionary:
	if graph == null:
		last_errors = []
		push_warning("FlowNodeIO.evaluate: graph is null")
		return {}
	var ctx := make_context(owner, seed, params, overrides)
	return evaluate_collecting_errors(graph, inputs.duplicate() if inputs else {}, ctx).outputs


## Synchronous graph evaluation — the default, unchanged runtime path.
## Builds the state, runs every ordered node in one pass, finalizes. This is
## the historical evaluate_graph: same phases, same order, same side effects,
## same return value. Nested subgraph/loop nodes keep calling this.
static func evaluate_graph(graph: FlowGraphResource, input_data_map: Dictionary, parent_ctx: FlowData.EvaluationContext, runtime_params: Dictionary = {}, depth: int = 0) -> Dictionary:
	if depth > 20:
		push_error("PCG graph evaluation exceeded maximum recursion depth (20). Check for circular subgraph references.")
		return {}
	var state := _build_evaluation_state(graph, input_data_map, parent_ctx, runtime_params, depth)
	if state.is_empty():
		return {}
	var graph_res: FlowGraphResource = state["graph"]
	var instances: Dictionary = state["instances"]
	var ctx: FlowData.EvaluationContext = state["ctx"]
	for node in state["ordered_nodes"]:
		_execute_single_node(node, instances, graph_res, ctx)
	return _finalize_evaluation(state)


## OPT-IN resumable evaluation (PARITY_ROADMAP async stage 2).
## Returns a GraphEvaluation the caller drives across frames via step(budget_ms).
## The work, ordering and side effects are identical to evaluate_graph(); only
## phase 2 (node execution) is spread over multiple calls. Returns null on the
## recursion-guard trip, matching evaluate_graph's {} early-out.
static func begin_evaluation(graph: FlowGraphResource, input_data_map: Dictionary, parent_ctx: FlowData.EvaluationContext, runtime_params: Dictionary = {}, depth: int = 0):
	if depth > 20:
		push_error("PCG graph evaluation exceeded maximum recursion depth (20). Check for circular subgraph references.")
		return null
	var state := _build_evaluation_state(graph, input_data_map, parent_ctx, runtime_params, depth)
	if state.is_empty():
		return null
	return GraphEvaluation.new(state)


## Resumable, time-sliced driver over an already-built evaluation state.
##
## Lifecycle:
##   var ev = FlowNodeIO.begin_evaluation(graph, args, ctx)
##   while ev != null and not ev.is_done():
##       ev.step(frame_budget_ms)   # run nodes until the ms budget is spent
##   var outputs = ev.outputs       # populated once is_done() is true
##
## Granularity is one node: a step never interrupts a node mid-run (a single
## heavy node can still overrun the budget — the heavy nodes are native-
## accelerated, so this is acceptable for stage 2). Phase 1 (build) already ran
## in begin_evaluation; finalize (output collection, variable publishing,
## instance freeing) runs automatically when the last node completes, so the
## same teardown guarantees as the synchronous path hold.
class GraphEvaluation:
	extends RefCounted

	var _state: Dictionary
	var _ordered: Array
	var _instances: Dictionary
	var _graph: FlowGraphResource
	var _ctx: FlowData.EvaluationContext
	var _index: int = 0
	var _finalized: bool = false
	var outputs: Dictionary = {}

	func _init(state: Dictionary) -> void:
		_state = state
		_ordered = state["ordered_nodes"]
		_instances = state["instances"]
		_graph = state["graph"]
		_ctx = state["ctx"]

	## Total nodes in the ordered execution list.
	func node_count() -> int:
		return _ordered.size()

	## Nodes executed so far (for progress reporting / proximity scheduling later).
	func progress() -> int:
		return _index

	## True once every node has run and finalize has published outputs.
	func is_done() -> bool:
		return _finalized

	## Execute ordered nodes until `budget_ms` of wall-clock time is spent this
	## call, then return so the host can yield the frame. Resumes from where it
	## left off next call. Always makes forward progress (at least one node per
	## call) so a tiny/zero budget cannot deadlock. Returns true when the whole
	## graph is finished (outputs are then populated).
	func step(budget_ms: float = 4.0) -> bool:
		if _finalized:
			return true
		var start_us := Time.get_ticks_usec()
		var budget_us := int(maxf(budget_ms, 0.0) * 1000.0)
		while _index < _ordered.size():
			FlowNodeIO._execute_single_node(_ordered[_index], _instances, _graph, _ctx)
			_index += 1
			# Node-level granularity: check the budget only between nodes. Guarantee
			# one node of progress per call regardless of budget.
			if Time.get_ticks_usec() - start_us >= budget_us:
				break
		if _index >= _ordered.size():
			outputs = FlowNodeIO._finalize_evaluation(_state)
			_finalized = true
			return true
		return false

	## Run the remainder synchronously (e.g. on teardown / forced completion),
	## still finalizing exactly once.
	func run_to_completion() -> Dictionary:
		while not _finalized:
			step(1.0e12)
		return outputs


# ---------------------------------------------------------------------------
# Golden-output snapshot (used by tests/golden; see tests/golden/README.md).
#
# Self-contained on purpose: it only drives the evaluator phases above and
# never changes their behaviour. evaluate_graph_snapshot() runs exactly what
# evaluate_graph() runs (same build, same ordered execution, same finalize and
# instance freeing) but, before the node instances are freed, records a
# summary of every node's generated bulks. A regression can then be pinned to
# the first node whose output drifted instead of only to the graph outputs.
# ---------------------------------------------------------------------------

## Float quantization for snapshot hashes: values are rounded to 1/1000 before
## hashing so last-bit float noise (different CPUs, compilers, engine minor
## versions) does not register as a regression.
const SNAPSHOT_FLOAT_QUANTUM := 1000.0

## Evaluates `graph` like evaluate_graph() and returns
##   { node_name: [ bulk_0 [ port_0 summary, port_1 summary, ... ], bulk_1 [...] ] }
## for EVERY node instanced from the graph (a node that did not execute maps to
## []; an unset port maps to null). Summaries come from snapshot_summarize_data().
## When `outputs_out` is a Dictionary it receives the graph outputs that
## evaluate_graph() would have returned.
static func evaluate_graph_snapshot(graph: FlowGraphResource, input_data_map: Dictionary, parent_ctx: FlowData.EvaluationContext, runtime_params: Dictionary = {}, depth: int = 0, outputs_out = null) -> Dictionary:
	if depth > 20:
		push_error("PCG graph evaluation exceeded maximum recursion depth (20). Check for circular subgraph references.")
		return {}
	var state := _build_evaluation_state(graph, input_data_map, parent_ctx, runtime_params, depth)
	if state.is_empty():
		return {}
	var graph_res: FlowGraphResource = state["graph"]
	var instances: Dictionary = state["instances"]
	var ctx: FlowData.EvaluationContext = state["ctx"]
	for node in state["ordered_nodes"]:
		_execute_single_node(node, instances, graph_res, ctx)
	var snapshot := {}
	for node in state["node_list"]:
		var bulks := []
		for bulk in node.generated_bulks:
			var ports := []
			for port_data in bulk:
				if port_data is FlowData.Data:
					ports.append(snapshot_summarize_data(port_data))
				else:
					ports.append(null)
			bulks.append(ports)
		snapshot[str(node.name)] = bulks
	var outputs := _finalize_evaluation(state)
	if outputs_out is Dictionary:
		outputs_out.clear()
		for key in outputs:
			outputs_out[key] = outputs[key]
	return snapshot

## Stable, JSON-friendly summary of a Data: point count, kind, sorted tags,
## per-data attributes and, per stream (sorted by name): name, data_type,
## element count and a content hash.
static func snapshot_summarize_data(data: FlowData.Data) -> Dictionary:
	var names := []
	for stream_name in data.streams.keys():
		names.append(str(stream_name))
	names.sort()
	var streams := []
	for stream_name in names:
		var stream = data.streams[stream_name]
		streams.append({
			"name": stream_name,
			"data_type": int(stream.data_type),
			"count": stream.container.size(),
			"hash": snapshot_hash_container(stream.container),
		})
	var tags := []
	for tag in data.tags:
		tags.append(str(tag))
	tags.sort()
	var attr_names := []
	for attr_name in data.data_attrs.keys():
		attr_names.append(str(attr_name))
	attr_names.sort()
	var attrs := {}
	for attr_name in attr_names:
		var record = data.data_attrs[attr_name]
		var value = record.get("value", null) if record is Dictionary else record
		var data_type = int(record.get("data_type", -1)) if record is Dictionary else -1
		attrs[attr_name] = { "data_type": data_type, "hash": snapshot_hash_container([value]) }
	return {
		"size": data.size(),
		"kind": int(data.kind),
		"tags": tags,
		"data_attrs": attrs,
		"streams": streams,
	}

## Content hash (16 hex chars of SHA-256) of a stream container. Integer, bool
## and string containers hash their exact contents; float-based containers are
## quantized with SNAPSHOT_FLOAT_QUANTUM first; Resource/Node arrays hash only
## resource_path (or class) per element, never object identity.
static func snapshot_hash_container(container) -> String:
	var hctx := HashingContext.new()
	hctx.start(HashingContext.HASH_SHA256)
	var bytes := PackedByteArray()
	if container is PackedByteArray:
		bytes = container
	elif container is PackedInt32Array or container is PackedInt64Array:
		bytes = container.to_byte_array()
	elif container is PackedStringArray:
		bytes = ("\u001f".join(container)).to_utf8_buffer()
	elif container is PackedFloat32Array or container is PackedFloat64Array:
		var q := PackedInt64Array()
		q.resize(container.size())
		for i in range(container.size()):
			q[i] = _snapshot_quantize(container[i])
		bytes = q.to_byte_array()
	elif container is PackedVector2Array or container is PackedVector3Array or container is PackedVector4Array or container is PackedColorArray:
		var comps := 2
		if container is PackedVector3Array:
			comps = 3
		elif container is PackedVector4Array or container is PackedColorArray:
			comps = 4
		var q := PackedInt64Array()
		q.resize(container.size() * comps)
		var k := 0
		for i in range(container.size()):
			var v = container[i]
			for c in range(comps):
				q[k] = _snapshot_quantize(v[c])
				k += 1
		bytes = q.to_byte_array()
	elif container is Array:
		var tokens := PackedStringArray()
		for value in container:
			tokens.append(_snapshot_value_token(value))
		bytes = ("\u001f".join(tokens)).to_utf8_buffer()
	else:
		bytes = _snapshot_value_token(container).to_utf8_buffer()
	if bytes.size() > 0:
		hctx.update(bytes)
	return hctx.finish().hex_encode().substr(0, 16)

static func _snapshot_quantize(v: float) -> int:
	if is_nan(v):
		return -9223372036854775807
	if is_inf(v):
		return 9223372036854775807 if v > 0.0 else -9223372036854775806
	return int(round(v * SNAPSHOT_FLOAT_QUANTUM))

static func _snapshot_value_token(value) -> String:
	if typeof(value) == TYPE_NIL:
		return "null"
	if typeof(value) == TYPE_OBJECT:
		if not is_instance_valid(value):
			return "null"
		if value is Resource and not value.resource_path.is_empty():
			return value.resource_path
		return "<%s>" % value.get_class()
	match typeof(value):
		TYPE_FLOAT:
			return str(_snapshot_quantize(value))
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION:
			var parts := PackedStringArray()
			var n := 4
			if typeof(value) == TYPE_VECTOR2:
				n = 2
			elif typeof(value) == TYPE_VECTOR3:
				n = 3
			for c in range(n):
				parts.append(str(_snapshot_quantize(value[c])))
			return ",".join(parts)
	return var_to_str(value)
