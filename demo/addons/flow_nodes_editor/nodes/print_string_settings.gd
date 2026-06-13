@tool
class_name PrintStringNodeSettings
extends NodeSettings

@export_group("Print String")

## Text prefix prepended to each printed debug line.
@export var prefix_message: String = "Log:"
## Attribute name whose value is printed for each element.
@export var attribute_to_print: String = ""

func _init():
	super._init()
	resource_name = "Print String Settings"
