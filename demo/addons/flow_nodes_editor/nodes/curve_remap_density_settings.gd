@tool
class_name CurveRemapDensityNodeSettings
extends NodeSettings

@export_group("Curve Remap Density")

## Curve asset that remaps input values into the output range.
@export var remap_curve: Curve

func _init():
	super._init()
	resource_name = "Curve Remap Density Settings"
