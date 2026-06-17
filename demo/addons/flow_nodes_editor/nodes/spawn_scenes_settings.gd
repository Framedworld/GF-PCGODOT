@tool
class_name SpawnScenesNodeSettings
extends NodeSettings

@export_group("Spawn Scenes")

## PackedScene resource to instantiate at point positions.
@export var scene : PackedScene
## Input attribute name specifying custom scenes per point.
@export var scene_attribute : String
## Array of variant PackedScene resources.
@export var scene_variants : Array[PackedScene] = []
## Selection weights assigned to variant scenes.
@export var scene_variant_weights : Array[float] = []
## Custom scene variant index selector attribute name.
@export var scene_selector_attribute : String = ""
## If enabled, picks variants randomly per point.
@export var randomize_scene_variants : bool = false
## Scene tree parent path under which spawned scenes are grouped.
@export var spawn_parent_path : String = ""
## If enabled, deletes previously spawned scene instances.
@export var clear_previous_instances : bool = true
## If enabled, outputs path reference to spawned scenes in streams.
@export var assign_target_path : String = ""
## Map of point attributes to set as properties on spawned scene root nodes.
@export var assign_attributes: Dictionary

func _init():
	super._init()
	resource_name = "Spawn Scenes Settings"

func exposeParam(name : String) -> bool:
	if name == "scene_variant_weights":
		return scene_variants.size() > 0
	if name == "scene_selector_attribute":
		return scene_variants.size() > 0 and not randomize_scene_variants
	return true
