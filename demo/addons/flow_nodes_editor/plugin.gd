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

var selection: EditorSelection

func spawnDock( res_template : String, title : String, bottom : bool ) -> Control:
	var packed : PackedScene = load( res_template )
	var new_control = packed.instantiate() as Control
	new_control.name = title
	if bottom:
		add_control_to_bottom_panel(new_control, title)	
	else:
		add_control_to_dock( DOCK_SLOT_RIGHT_UL, new_control )
	return new_control

func _has_valid_graph_dock() -> bool:
	return graph_dock != null and is_instance_valid(graph_dock)

func _ensure_graph_dock() -> void:
	if _has_valid_graph_dock() and not FlowEditorChrome.is_valid_layout(graph_dock):
		remove_control_from_docks(graph_dock)
		graph_dock.queue_free()
		graph_dock = null
	if not _has_valid_graph_dock():
		graph_dock = spawnDock(
			"res://addons/flow_nodes_editor/flow_editor.tscn",
			FlowI18n.t("Data Flow"),
			false
		) as Control

func _enter_tree():
	print("Data Flow plugin enabled")
	_ensure_graph_dock()

	graph_input_inspector_plugin = load("res://addons/flow_nodes_editor/graph_input_parameter_inspector.gd").new()
	add_inspector_plugin(graph_input_inspector_plugin)
	node_settings_inspector_plugin = load("res://addons/flow_nodes_editor/node_settings_inspector_plugin.gd").new()
	add_inspector_plugin(node_settings_inspector_plugin)

	# Will refresh everytime the undo/redo subsystem saves a point
	undo_redo = get_undo_redo()
	undo_redo.history_changed.connect(_on_history_changed)
	graph_dock.undo_redo = undo_redo

	# Auto-detect file changes on disk (from git, agents, external editors)
	var efs = EditorInterface.get_resource_filesystem()
	if efs:
		efs.filesystem_changed.connect(_on_filesystem_changed)
		efs.resources_reimported.connect(_on_resources_reimported)

	selection = EditorInterface.get_selection()
	if selection:
		selection.selection_changed.connect(_selection_changed)
	else:
		push_warning("Data Flow: EditorSelection unavailable in _enter_tree; selection sync disabled until editor is ready.")

	set_process(true)
	
func _save_external_data():
	if _has_valid_graph_dock() and graph_dock.has_method("saveResource"):
		graph_dock.saveResource()
	
func _exit_tree():
	setWatchedNode(null)
	if undo_redo and undo_redo.history_changed.is_connected(_on_history_changed):
		undo_redo.history_changed.disconnect(_on_history_changed)
	var efs = EditorInterface.get_resource_filesystem()
	if efs:
		if efs.filesystem_changed.is_connected(_on_filesystem_changed):
			efs.filesystem_changed.disconnect(_on_filesystem_changed)
		if efs.resources_reimported.is_connected(_on_resources_reimported):
			efs.resources_reimported.disconnect(_on_resources_reimported)
	if node_settings_inspector_plugin:
		remove_inspector_plugin(node_settings_inspector_plugin)
	if graph_input_inspector_plugin:
		remove_inspector_plugin(graph_input_inspector_plugin)
	#remove_inspector_plugin(inspector_plugin)
	if _has_valid_graph_dock():
		remove_control_from_docks(graph_dock)
		graph_dock.queue_free()
		graph_dock = null
	if data_inspector_dock and is_instance_valid(data_inspector_dock):
		remove_control_from_bottom_panel(data_inspector_dock)
		data_inspector_dock.queue_free()
		data_inspector_dock = null
	if selection and selection.selection_changed.is_connected(_selection_changed):
		selection.selection_changed.disconnect(_selection_changed)

func _ready():
	if selection == null:
		selection = EditorInterface.get_selection()
		if selection and not selection.selection_changed.is_connected(_selection_changed):
			selection.selection_changed.connect(_selection_changed)
	if selection:
		_selection_changed()

# This is called after the a new scene is loaded, but the 'selection' event of the new
# scene is called first.
func on_scene_changed(scene_root: Node) -> void:
	if not _has_valid_graph_dock() or scene_root == null:
		return
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
	if not _has_valid_graph_dock():
		return
	if selection == null:
		selection = EditorInterface.get_selection()
	if selection == null:
		return

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
	if not _has_valid_graph_dock():
		return
	print( "onSelectedGraphNodeChanged %s.%s" % [node.name, prop_name] )
	if prop_name == "graph_resource":
		print( "  -> %s" % [node.graph] )
		graph_dock.setResourceToEdit( node.graph, node )
		

func _on_history_changed( ):
	#print("Something changed in the editor (undo/redo history updated)")	
	if _has_valid_graph_dock():
		graph_dock.onEditorSceneChanged()

func _process( elapsed : float ):
	var scene_root = get_editor_interface().get_edited_scene_root()
	if scene_root != current_scene_root:
		current_scene_root = scene_root
		on_scene_changed(scene_root)

func _on_filesystem_changed():
	# Auto-reload current graph when files change on disk
	if _has_valid_graph_dock() and graph_dock.current_resource:
		graph_dock._on_filesystem_changed()

func _on_resources_reimported(resources: PackedStringArray):
	# Check if any reimported resource is the current graph or a subgraph
	if _has_valid_graph_dock() and graph_dock.current_resource:
		var current_path = graph_dock.current_resource.resource_path
		for res_path in resources:
			if res_path == current_path or res_path.ends_with(".tres"):
				graph_dock._on_filesystem_changed()
				return
