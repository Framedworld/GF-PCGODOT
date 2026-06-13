@tool
class_name SequenceSampleNodeSettings
extends NodeSettings

@export_group("Sequence Sample")

## Start index used by sequence sampling.
@export var start : int = 0
## Number of items taken from the sequence starting at start.
@export var count : int = 0
## Step amount used when iterating or sampling values.
@export var step : int = 1

func _init():
	super._init()
	resource_name = "Sequence Sample Settings"
