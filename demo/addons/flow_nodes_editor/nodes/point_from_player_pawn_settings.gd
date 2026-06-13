@tool
extends NodeSettings

@export_group("Point From Player")

## Direct node path override for the player source; if empty, discovery uses the filters below.
@export_node_path("Node3D") var player_node_path : NodePath
## Group name used to find or filter scene nodes.
@export var group_name : String = "player"
## Only considers nodes whose script/class name contains this value when searching for a player node.
@export var class_name_filter : String = "CharacterBody3D"
## Wildcard name pattern used to match candidate scene nodes (for example *Player*).
@export var name_pattern : String = "*Player*"
## If no player-like node is found, uses the current camera transform as the emitted point source.
@export var fallback_to_current_camera : bool = false
## When enabled, also outputs node ref alongside generated points/data.
@export var include_node_ref : bool = true
## Output attribute name used to store a reference to the matched source node.
@export var node_attribute : String = "node"

func _init():
	super._init()
	resource_name = "Point From Player Settings"

func exposeParam(name : String) -> bool:
	if name == "node_attribute":
		return include_node_ref
	return true
