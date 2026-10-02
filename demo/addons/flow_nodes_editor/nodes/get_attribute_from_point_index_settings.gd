@tool
class_name GetAttributeFromPointIndexNodeSettings
extends NodeSettings

@export_group("Get Attribute From Point Index")

## Index of the point to read. Negative values count from the end (-1 is the
## last point). Out of range is an error.
@export var index : int = 0
## Attribute to read. Accepts every selector: "@last", "density",
## "position.y", "Yaw", "@data.name".
@export var input_attribute : String = "@last"
## Name of the attribute written on the outputs. Empty derives it from the
## input attribute ("position.y" becomes "position_y", "@data.n" becomes "n").
@export var output_attribute : String = ""

func _init():
	super._init()
	resource_name = "Get Attribute From Point Index Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "input_attribute", "port": 0 },
	]
