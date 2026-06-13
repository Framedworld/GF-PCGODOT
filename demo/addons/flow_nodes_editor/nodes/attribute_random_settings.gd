@tool
class_name AttributeRandomNodeSettings
extends NodeSettings

@export_group("Attribute Random")
## Name of the attribute this node reads from or writes to.
@export var attribute_name: String = "random_attr"

enum eType { Float, Int }
## Selects this node behavior mode (resource_name).
@export var data_type: eType = eType.Float

## Lower bound used by this node for value.
@export var min_value: float = 0.0
## Upper bound used by this node for value.
@export var max_value: float = 1.0

## Toggles whether this node uses index as value instead of default behavior.
@export var use_index_as_value: bool = false

func _init():
	super._init()
	resource_name = "Attribute Random Settings"
