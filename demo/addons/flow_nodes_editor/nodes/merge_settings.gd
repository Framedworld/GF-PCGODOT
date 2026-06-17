@tool
class_name MergeNodeSettings
extends NodeSettings

@export_group("Merge")

## If enabled, merges all attributes from all input sets. If disabled, only merges common attributes.
#@export var merge_all_attributes := true

func _init():
	super._init()
	resource_name = "Merge Settings"
