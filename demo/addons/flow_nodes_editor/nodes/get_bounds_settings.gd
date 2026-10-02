@tool
extends NodeSettings

@export_group("Get Bounds")

enum eOutputMode {
	## One bounds point per input Data.
	Points,
	## The bounds as a box volume shape (zero points).
	Shape,
}

## Output a bounds point (default) or a box volume shape.
@export var output_mode : eOutputMode = eOutputMode.Points
## Steepness of the box volume in Shape mode.
@export_range( 0.0, 1.0 ) var steepness : float = 1.0

func _init():
	super._init()
	resource_name = "Get Bounds Settings"

func exposeParam( name : String ) -> bool:
	if name == "steepness":
		return output_mode == eOutputMode.Shape
	return true
