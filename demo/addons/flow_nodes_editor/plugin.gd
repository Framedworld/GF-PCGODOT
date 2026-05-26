@tool
extends EditorPlugin

# This is the entry point for the plugin
# Where we register all editors, inspectors and hocks

var graph_dock: Control
var data_inspector_dock: Control
var inspector_plugin
var watched_nodes : Array[Node] = []
var undo_redo: EditorUndoRedoManager
var graph_input_inspector_plugin : EditorInspectorPlugin
var node_settings_inspector_plugin : EditorInspectorPlugin

# To detect scene changes
var current_scene_root = null
var current_watched_node = null

@onready var selection = EditorInterface.get_selection()

func spawnDock( res_template : String, title : String, bottom : bool ) -> Control:
	var packed : PackedScene = load( res_template )
	var new_control = packed.instantiate() as Control
	new_control.name = title
	if bottom:
		add_control_to_bottom_panel(new_control, title)	
	else:
		add_control_to_dock( DOCK_SLOT_RIGHT_UL, new_control )
	return new_control

func _enter_tree():
	print("Data Flow plugin enabled")
	graph_dock = spawnDock("res://addons/flow_nodes_editor/flow_editor.tscn", "Data Flow", false ) as Control
	
	graph_input_inspector_plugin = load("res://addons/flow_nodes_editor/graph_input_parameter_inspector.gd").new()
	add_inspector_plugin(graph_input_inspector_plugin)
	node_settings_inspector_plugin = load("res://addons/flow_nodes_editor/node_settings_inspector_plugin.gd").new()
	add_inspector_plugin(node_settings_inspector_plugin)
	
	# Will refresh everytime the undo/redo subsystem saves a point
	undo_redo = get_undo_redo()
	undo_redo.history_changed.connect(_on_history_changed)
	graph_dock.undo_redo = undo_redo
	
	set_process(true)
	
func _save_external_data():
	graph_dock.saveResource()
	
func _exit_tree():
	if undo_redo:
		undo_redo.history_changed.disconnect(_on_history_changed)
	remove_inspector_plugin(node_settings_inspector_plugin)
	remove_inspector_plugin(graph_input_inspector_plugin)
	#remove_inspector_plugin(inspector_plugin)
	remove_control_from_docks(graph_dock)
	graph_dock.free()
	if data_inspector_dock and is_instance_valid(data_inspector_dock):
		remove_control_from_bottom_panel(data_inspector_dock)
		data_inspector_dock.free()
	selection.selection_changed.disconnect(_selection_changed)

func _ready():
	selection.selection_changed.connect(_selection_changed)
	_selection_changed()

# This is called after the a new scene is loaded, but the 'selection' event of the new
# scene is called first.
func on_scene_changed(scene_root: Node) -> void:
	print( "Scene Changed detected %s : %s -> %s" % [graph_dock.current_resource, is_instance_valid(graph_dock.resource_owner), scene_root.name ] )
	if is_instance_valid(graph_dock.resource_owner):
		var node = graph_dock.resource_owner
		if scene_root and (node.get_owner() != scene_root and not scene_root.is_ancestor_of(node)):
			graph_dock.setResourceToEdit( null, null )
			
	# Auto activate the first flow node graph found in the scene
	for node in scene_root.get_children():
		var flow_node = node as FlowGraphNode3D
		if flow_node:
			graph_dock.setResourceToEdit( flow_node.graph, flow_node )
			break
		

func _selection_changed():
	
	var scene_nodes = selection.get_selected_nodes()
	if not scene_nodes.is_empty():
		var scene_node = scene_nodes[0]
		if scene_node is FlowGraphNode3D:
			setWatchedNode( scene_node )
			graph_dock.setResourceToEdit( scene_node.graph, scene_node )
			return
	setWatchedNode( null )

func setWatchedNode( new_node ):
	#print( "setWatchedNode %s" % new_node )
	if current_watched_node:
		current_watched_node.graph_node_changed.disconnect( onSelectedGraphNodeChanged )
		current_watched_node = null
	if new_node:
		current_watched_node = new_node
		new_node.graph_node_changed.connect( onSelectedGraphNodeChanged )

func onSelectedGraphNodeChanged( node : FlowGraphNode3D, prop_name: String ):
	print( "onSelectedGraphNodeChanged %s.%s" % [node.name, prop_name] )
	if prop_name == "graph_resource":
		print( "  -> %s" % [node.graph] )
		graph_dock.setResourceToEdit( node.graph, node )
		

func _on_history_changed( ):
	#print("Something changed in the editor (undo/redo history updated)")	
	graph_dock.onEditorSceneChanged()

func _process( elapsed : float ):
	var scene_root = get_editor_interface().get_edited_scene_root()
	if scene_root != current_scene_root:
		current_scene_root = scene_root
		on_scene_changed(scene_root)
