@tool
class_name CurveRemapDensityNodeSettings
extends NodeSettings

@export_group("Curve Remap Density")

## A Curve resource defining the remapping transfer function. Evaluates input density values along the X-axis (0.0 to 1.0) and assigns the resulting Y-axis values back as the output density.
@export var remap_curve: Curve

func _init():
	super._init()
	resource_name = "Curve Remap Density Settings"
