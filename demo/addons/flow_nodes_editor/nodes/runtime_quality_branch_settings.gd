@tool
class_name RuntimeQualityBranchNodeSettings
extends NodeSettings

@export_group("Runtime Quality Branch")

## Route data to the "Low" pin when the quality level is Low (0). Off sends it
## to "Default" instead.
@export var use_low_pin : bool = false
## Route data to the "Medium" pin when the quality level is Medium (1).
@export var use_medium_pin : bool = false
## Route data to the "High" pin when the quality level is High (2).
@export var use_high_pin : bool = false
## Route data to the "Epic" pin when the quality level is Epic (3).
@export var use_epic_pin : bool = false
## Route data to the "Cinematic" pin when the quality level is Cinematic (4).
@export var use_cinematic_pin : bool = false
## Force a quality level for this node (0 Low .. 4 Cinematic), e.g. to preview
## a level in the editor. -1 uses the runtime parameter "quality", then the
## project setting flow_nodes/quality_level.
@export_range(-1, 4) var quality_override : int = -1

func _init():
	super._init()
	resource_name = "Runtime Quality Branch Settings"

## The use_*_pin flags in level order (Low first).
func level_pins() -> Array:
	return [ use_low_pin, use_medium_pin, use_high_pin, use_epic_pin, use_cinematic_pin ]
