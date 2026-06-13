@tool
class_name MatchAndSetNodeSettings
extends NodeSettings

@export_group("Match And Set")

## Attribute used as the lookup key when matching source and target rows/points.
@export var match_attr : String
## Optional weight attribute used for weighted match selection.
@export var weight_attr : String

func _init():
	super._init()
	resource_name = "Match And Set"
