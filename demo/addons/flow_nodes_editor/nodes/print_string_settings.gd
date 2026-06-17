@tool
class_name PrintStringNodeSettings
extends NodeSettings

@export_group("Print String")

## Text message prepended to print statements.
@export var prefix_message: String = "Log:"
## Name of the point attribute stream to print.
@export var attribute_to_print: String = ""

func _init():
	super._init()
	resource_name = "Print String Settings"
