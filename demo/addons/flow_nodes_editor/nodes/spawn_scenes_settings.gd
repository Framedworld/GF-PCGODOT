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

@export_subgroup("Attribute Overrides")
## Point attribute name -> property path on each spawned instance, applied after
## instancing (and after assign_attributes), with type coercion. Paths:
## "light_energy", "position:x" (nested), "Child/Light:light_energy",
## "%Mesh:material_override:albedo_color" (unique name, nested). A leading ':'
## forces the instance root. Unreal's Spawn Actor property overrides.
@export var property_overrides : Dictionary = {}

@export_subgroup("Placement")
## Attribute holding the spawn parent per point (or per data, e.g. "@data.target"
## from Create Target Node): a Node3D reference, or a NodePath/String relative to
## the owner. Empty: spawn_parent_path is used.
@export var spawn_parent_attribute : String = ""
## Reuse this node's spawned scene roots from the previous generation (same
## component, same PackedScene) instead of freeing and re-instancing them: the
## transform, name, assigned attributes and property overrides are re-applied,
## other runtime state of a reused instance is kept. Needs
## clear_previous_instances. Off by default.
@export var reuse_instances : bool = false

func _init():
	super._init()
	resource_name = "Spawn Scenes Settings"

func exposeParam(name : String) -> bool:
	if name == "scene_variant_weights":
		return scene_variants.size() > 0
	if name == "scene_selector_attribute":
		return scene_variants.size() > 0 and not randomize_scene_variants
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "spawn_parent_attribute", "port": 0 },
	]
