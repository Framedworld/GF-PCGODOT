@tool
extends NodeSettings

@export_group("Attribute Remove Duplicates")

## Attributes whose combined value identifies an entry; entries repeating an earlier
## combination are removed. Any type; values compare exactly (no tolerance).
@export var attribute_names : PackedStringArray = PackedStringArray(["@last"])

func _init():
	super._init()
	resource_name = "Attribute Remove Duplicates"
