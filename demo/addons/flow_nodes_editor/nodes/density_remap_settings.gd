@tool
class_name DensityRemapNodeSettings
extends NodeSettings

@export_group("Density Remap")

## Input value/attribute key used for min.
@export var in_min: float = 0.0
## Input value/attribute key used for max.
@export var in_max: float = 1.0
## Output value/attribute key used for min.
@export var out_min: float = 0.0
## Output value/attribute key used for max.
@export var out_max: float = 1.0
## Parameter used for clamp to output range.
@export var clamp_to_output_range: bool = true

func _init():
	super._init()
	resource_name = "Density Remap Settings"
