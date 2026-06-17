@tool
class_name SequenceSampleNodeSettings
extends NodeSettings

@export_group("Sequence Sample")

## Starting value of sequence.
@export var start : int = 0
## Number of sequence items to generate.
@export var count : int = 0
## Difference spacing step between adjacent items.
@export var step : int = 1

func _init():
	super._init()
	resource_name = "Sequence Sample Settings"
