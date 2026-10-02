@tool
class_name MakeBoundsNodeSettings
extends NodeSettings

@export_group("Make Bounds")
## The Vector3 size dimensions of the bounding box.
@export var size: Vector3 = Vector3(48.0, 1.0, 48.0):
	set(value):
		size = value
		emit_changed()
## The Vector3 center position of the bounding box.
@export var center: Vector3 = Vector3.ZERO:
	set(value):
		center = value
		emit_changed()


enum eOutputMode {
	## One bounds point (today's output).
	Points,
	## A box volume shape (FlowBoxVolume, zero points): spatial data for the
	## set operations, Volume Sampler or To Point.
	Shape,
}

## Points (default, unchanged output) or a box volume shape.
@export var output_mode : eOutputMode = eOutputMode.Points:
	set(value):
		output_mode = value
		emit_changed()
## Steepness of the box volume in Shape mode (1 = hard edge).
@export_range(0.0, 1.0) var steepness : float = 1.0:
	set(value):
		steepness = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Make Bounds Settings"

func exposeParam(name : String) -> bool:
	if name == "steepness":
		return output_mode == eOutputMode.Shape
	return true
