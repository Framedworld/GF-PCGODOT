@tool
class_name DensityRemapNodeSettings
extends NodeSettings

@export_group("Density Remap")

## The lower limit of the expected input density range.
@export var in_min: float = 0.0
## The upper limit of the expected input density range.
@export var in_max: float = 1.0
## The lower limit of the output density range mapped from in_min.
@export var out_min: float = 0.0
## The upper limit of the output density range mapped from in_max.
@export var out_max: float = 1.0
## If enabled, clamps the remapped density output values to the configured output range limits.
@export var clamp_to_output_range: bool = true

func _init():
	super._init()
	resource_name = "Density Remap Settings"
