@tool
class_name PartitionNodeSettings
extends NodeSettings

@export_group("Partition")

## The name of the attribute stream to partition the data by.
@export var attribute_name : String = "@last"
## The output attribute name storing partition assignment IDs.
@export var out_partition_attribute : String

func _init():
	super._init()
	resource_name = "Partition"
