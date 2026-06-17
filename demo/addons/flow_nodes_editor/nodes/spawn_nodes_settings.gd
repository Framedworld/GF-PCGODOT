@tool
class_name SpawnNodesNodeSettings
extends NodeSettings

@export_group("Spawn Nodes")

## Name of Godot Node class to spawn.
@export var node_class : String = "OmniLight3D"
## List of alternative Node class names to select from.
@export var node_class_variants : Array[String] = []
## Custom index selector attribute name.
@export var node_selector_attribute : String = ""
## If enabled, picks class variants randomly per point.
@export var randomize_node_variants : bool = false
## Scene tree parent path under which spawned nodes are grouped.
@export var spawn_parent_path : String = ""
## If enabled, deletes previously spawned node instances.
@export var clear_previous_instances : bool = true
## If enabled, outputs path reference to spawned nodes in streams.
@export var assign_target_path : String = ""
## Map of point attributes to set as properties on spawned nodes.
@export var assign_attributes: Dictionary

func _init():
	super._init()
	resource_name = "Spawn Nodes Settings"

func exposeParam(name : String) -> bool:
	if name == "node_selector_attribute":
		return node_class_variants.size() > 0 and not randomize_node_variants
	return true
