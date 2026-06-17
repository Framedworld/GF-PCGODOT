@tool
class_name AttributeRandomNodeSettings
extends NodeSettings

@export_group("Attribute Random")
## The name of the attribute stream to create or write the random values to.
@export var attribute_name: String = "random_attr"

enum eType {
	## Generates random float values.
	Float,
	## Generates random integer values.
	Int,
}
## The data type of the random values to generate (Int or Float).
@export var data_type: eType = eType.Float

## The minimum bound of the generated random values.
@export var min_value: float = 0.0
## The maximum bound of the generated random values.
@export var max_value: float = 1.0

## If enabled, uses the point index directly as the generated value instead of a random number.
@export var use_index_as_value: bool = false

func _init():
	super._init()
	resource_name = "Attribute Random Settings"
