@tool
class_name MatchAndSetNodeSettings
extends NodeSettings

@export_group("Match And Set")

## The attribute stream name used to compare and match entries.
@export var match_attr : String
## Optional attribute stream name specifying selection weights for random distribution.
@export var weight_attr : String

func _init():
	super._init()
	resource_name = "Match And Set"
