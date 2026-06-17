@tool
class_name SetVariableNodeSettings
extends NodeSettings

@export_group("Set Variable")

## Name of the variable to write to.
@export var variable_name : String = "variable"
## Color icon indicator assigned in editor graph.
@export var node_color : Color = Color("22d3ee")

func _init():
	super._init()
	resource_name = "Set Variable"
