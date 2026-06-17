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

func _init():
	super._init()
	resource_name = "Make Bounds Settings"
