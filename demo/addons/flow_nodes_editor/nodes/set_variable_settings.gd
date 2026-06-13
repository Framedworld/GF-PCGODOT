@tool
class_name SetVariableNodeSettings
extends NodeSettings

@export_group("Set Variable")

## Name of the graph variable to get or set.
@export var variable_name : String = "variable"
## Editor color assigned to the variable node representation.
@export var node_color : Color = Color("22d3ee")

func _init():
	super._init()
	resource_name = "Set Variable"
