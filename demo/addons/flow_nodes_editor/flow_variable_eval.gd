extends Object
class_name FlowVariableEval

## Fast evaluation for Set/Get Variable relay nodes.
## These nodes only read/write ctx.variables; they do not need full bulk iteration or debug summaries.


static func is_relay_template(node_template: String) -> bool:
	return node_template == "set_variable" or node_template == "get_variable"


static func should_refresh_debug_draw(node: FlowNodeBase) -> bool:
	if not is_relay_template(node.node_template):
		return true
	if node.settings == null:
		return false
	return bool(node.settings.inspect_enabled) or bool(node.settings.debug_enabled)


static func variable_name_from_node(node: FlowNodeBase) -> String:
	if node.settings == null or not ("variable_name" in node.settings):
		return ""
	return String(node.settings.variable_name).strip_edges()


static func try_fast_execute(
	node: FlowNodeBase,
	ctx: FlowData.EvaluationContext,
	instances: Dictionary = {}
) -> bool:
	match node.node_template:
		"set_variable":
			return _fast_execute_set(node, ctx, instances)
		"get_variable":
			return _fast_execute_get(node, ctx)
	return false


static func _fast_execute_set(
	node: FlowNodeBase,
	ctx: FlowData.EvaluationContext,
	instances: Dictionary
) -> bool:
	_wire_inputs_from_deps(node, ctx, instances)
	var in_data: FlowData.Data = node.get_optional_input(0)
	if in_data == null:
		in_data = FlowData.Data.new()
	var variable_name := variable_name_from_node(node)
	if variable_name.is_empty():
		node.setError("Variable name can't be empty")
		node.set_output(0, in_data)
		return true
	ctx.variables[variable_name] = in_data
	node.set_output(0, in_data)
	return true


static func _fast_execute_get(node: FlowNodeBase, ctx: FlowData.EvaluationContext) -> bool:
	var variable_name := variable_name_from_node(node)
	if variable_name.is_empty():
		node.setError("No variable selected")
		node.set_output(0, FlowData.Data.new())
		return true
	var data: Variant = ctx.variables.get(variable_name, null)
	if data == null:
		node.setError("Variable '%s' is not set" % variable_name)
		node.set_output(0, FlowData.Data.new())
		return true
	node.set_output(0, data)
	return true


static func _wire_inputs_from_deps(
	node: FlowNodeBase,
	ctx: FlowData.EvaluationContext,
	instances: Dictionary
) -> void:
	var nodes_by_name: Dictionary = instances if not instances.is_empty() else ctx.gedit_nodes_by_name
	node.inputs.clear()
	var num_ins: int = node.getMeta().get("ins", []).size()
	if num_ins <= 0:
		num_ins = 1
	node.inputs.resize(num_ins)
	for conn in node.deps:
		if conn.get("virtual_variable", false):
			continue
		var src: FlowNodeBase = nodes_by_name.get(conn.from_node)
		if src == null or src.generated_bulks.is_empty():
			continue
		var src_bulk: Array = src.generated_bulks[src.generated_bulks.size() - 1]
		var to_port: int = int(conn.to_port)
		if to_port < 0 or to_port >= node.inputs.size():
			continue
		var from_port: int = int(conn.from_port)
		if from_port < src_bulk.size():
			node.inputs[to_port] = src_bulk[from_port]
