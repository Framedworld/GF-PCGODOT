@tool
class_name RandomColorNodeSettings
extends NodeSettings

@export_group("Random Color")

## Name of the output attribute this node writes.
@export var out_name : String = "color"
## Toggles whether this node uses palette instead of default behavior.
@export var use_palette : bool = true:
	set(value):
		if use_palette != value:
			use_palette = value
			notify_property_list_changed()
## Color palette used for random color assignment.
@export var palette : Array[Color] = [
	Color(1.0, 0.078, 0.576, 1.0), # Pink
	Color(0.0, 0.749, 1.0, 1.0),   # Cyan
	Color(1.0, 0.843, 0.0, 1.0)    # Yellow
]

## Minimum hue value for HSV random color generation.
@export_range(0.0, 1.0) var hue_min : float = 0.0
## Maximum hue value for HSV random color generation.
@export_range(0.0, 1.0) var hue_max : float = 1.0
## Minimum saturation value for HSV random color generation.
@export_range(0.0, 1.0) var sat_min : float = 0.6
## Maximum saturation value for HSV random color generation.
@export_range(0.0, 1.0) var sat_max : float = 1.0
## Minimum value/brightness for HSV random color generation.
@export_range(0.0, 1.0) var val_min : float = 0.6
## Maximum value/brightness for HSV random color generation.
@export_range(0.0, 1.0) var val_max : float = 1.0

func _init():
	super._init()
	resource_name = "Random Color Settings"

func exposeParam(name : String) -> bool:
	if name == "palette":
		return use_palette
	if name in ["hue_min", "hue_max", "sat_min", "sat_max", "val_min", "val_max"]:
		return not use_palette
	return true
