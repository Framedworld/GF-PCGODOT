@tool
class_name SanityCheckNodeSettings
extends NodeSettings

@export_group("Sanity Check")

## Attribute stream name to validate.
@export var attribute_name: String = "density"
## Lower limit for validation range check.
@export var min_value: float = 0.0
## Upper limit for validation range check.
@export var max_value: float = 1.0

func _init():
	super._init()
	resource_name = "Sanity Check Settings"
