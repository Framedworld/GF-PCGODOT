@tool
class_name SpawnScenesNodeSettings
extends NodeSettings

@export_group("Spawn Scenes")

## Default scene to spawn when scene attributes/variants are not used.
@export var scene : PackedScene
## Attribute name used to read/write scene on point data.
@export var scene_attribute : String
## List of scene candidates this node can choose from while spawning/assigning.
@export var scene_variants : Array[PackedScene] = []
## Relative selection weights used when randomly picking from scene_variants.
@export var scene_variant_weights : Array[float] = []
## Attribute name used to read/write scene selector on point data.
@export var scene_selector_attribute : String = ""
## If enabled, randomly chooses from scene_variants instead of using scene_selector_attribute values.
@export var randomize_scene_variants : bool = false
## Scene/resource path used to resolve spawn parent.
@export var spawn_parent_path : String = ""
## When enabled, clears previous instances before writing new results.
@export var clear_previous_instances : bool = true
## Scene/resource path used to resolve assign target.
@export var assign_target_path : String = ""
## When enabled, assigns attributes during node execution.
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
