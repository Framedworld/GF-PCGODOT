@tool
class_name BoundsModifierNodeSettings
extends NodeSettings

@export_group("Bounds Modifier")

enum eMode { Set, Add, Multiply }
## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode: eMode = eMode.Set
## Minimum corner of the bounds box.
@export var bounds_min: Vector3 = -Vector3.ONE * 0.5
## Maximum corner of the bounds box.
@export var bounds_max: Vector3 = Vector3.ONE * 0.5

func _init():
	super._init()
	resource_name = "Bounds Modifier Settings"
