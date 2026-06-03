@tool
extends Node3D
class_name FlowGraphNode3D

# This is the Node3d the user will instantiate in his final 3D scenes to trigger
# the generation of pcg
# It technically should not need to be a Node3D, as the transform is not really used
# but I'm currently generating the spawned nodes as child of this nodes

const FlowNodeIOClass = preload("res://addons/flow_nodes_editor/flow_nodes_io.gd")

@export var graph : FlowGraphResource :
	set(new_value):
		_graph = new_value
		graph_node_changed.emit( self, "graph_resource" )

	get:
		return _graph

var _graph : FlowGraphResource = FlowGraphResource.new()
signal graph_node_changed( graph_node : FlowGraphNode3D, prop_name : String )

# custom inputs values for this instantiation
@export var args : Dictionary = {}

# You can also use get_property_list() for more control
func _get_property_list():
	return [
		{
			"name": "refresh_inputs",
			"type": TYPE_CALLABLE,
			"hint": PROPERTY_HINT_TOOL_BUTTON | PROPERTY_USAGE_EDITOR,
			"hint_string": "Refresh Inputs"
		}
	]

func _get(property: StringName):
	match property:
		"refresh_inputs":
			return refreshInputs
	return null

func refreshInputs():
	print( "RefreshInputs %s" % graph )
	if args == null:
		args = {}
	var changed := false
	if graph:
		print( "Checking in_params:", graph.in_params )
		for in_param in graph.in_params:
			if in_param == null:
				continue
			var param_name = in_param.name
			print( "  in_param. Name:'%s' Type:%s" % [ param_name, in_param.data_type ] )
			if not args.has( param_name ):
				args[ param_name ] = in_param.get_default_value()
				print( "  not found. Assigning default value" )
				changed = true
				
			else:
				var curr_val = args[ param_name ]
				if in_param.data_type != FlowNodeBase.getFlowDataTypeFromObject( curr_val ):
					print( "  found but wrong type. Assigning default value %s" % [ curr_val ] )
					changed = true
					args[ param_name ] = in_param.get_default_value()
				else:
					print( "  found and type matches. Do nothing" )
					pass

		var keys_to_delete = []
		print( "Args:", args)
		for arg_name in args.keys():
			var input = graph.findInParamByName( arg_name )
			if input == null:
				keys_to_delete.append( arg_name )
				changed = true
		for arg_name in keys_to_delete:
			args.erase( arg_name )

	else:
		#print( "Clearing current args. graph is null" )
		if args:
			args.clear()
			changed = true
		
	if changed:
		notify_property_list_changed()

func _ready():
	if not Engine.is_editor_hint():
		execute()

func execute() -> void:
	if not graph:
		push_warning("FlowGraphNode3D: no graph resource assigned")
		return
	var ctx = load("res://addons/flow_nodes_editor/flow_data.gd").EvaluationContext.new()
	ctx.owner = self
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	FlowNodeIOClass.evaluate_graph(graph, args if args != null else {}, ctx, {})
