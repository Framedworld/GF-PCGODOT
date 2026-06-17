@tool
extends NodeSettings

@export_group("Point From Player")

## Scene tree path to target player pawn Node.
@export_node_path("Node3D") var player_node_path : NodePath
## Group name to locate player pawn when path is empty.
@export var group_name : String = "player"
## Class name filter to identify player pawn.
@export var class_name_filter : String = "CharacterBody3D"
## Name pattern to filter player pawn.
@export var name_pattern : String = "*Player*"
## If enabled, falls back to active Camera3D position if player is not found.
@export var fallback_to_current_camera : bool = false
## If enabled, outputs node reference in point streams.
@export var include_node_ref : bool = true
## Output attribute stream name storing node reference.
@export var node_attribute : String = "node"

func _init():
	super._init()
	resource_name = "Point From Player Settings"

func exposeParam(name : String) -> bool:
	if name == "node_attribute":
		return include_node_ref
	return true
