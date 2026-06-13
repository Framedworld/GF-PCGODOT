@tool
class_name SanityCheckNodeSettings
extends NodeSettings

@export_group("Sanity Check")

## Name of the attribute this node reads from or writes to.
@export var attribute_name: String = "density"
## Lower bound used by this node for value.
@export var min_value: float = 0.0
## Upper bound used by this node for value.
@export var max_value: float = 1.0

func _init():
	super._init()
	resource_name = "Sanity Check Settings"
