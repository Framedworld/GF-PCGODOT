@tool
class_name PartitionNodeSettings
extends NodeSettings

@export_group("Partition")

## Name of the attribute this node reads from or writes to.
@export var attribute_name : String = "@last"
## Output attribute name that stores partition produced by this node.
@export var out_partition_attribute : String

func _init():
	super._init()
	resource_name = "Partition"
