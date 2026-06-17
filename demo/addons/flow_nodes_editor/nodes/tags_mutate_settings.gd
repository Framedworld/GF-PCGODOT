@tool
extends NodeSettings

@export_group("Tags")

enum eOperation {
	## Adds the specified tags to the point data.
	Add,
	## Removes the specified tags from the point data.
	Remove,
	## Replaces the existing tags with the specified tags.
	Replace,
}

## Tag operation to perform.
@export var operation : eOperation = eOperation.Add
## Comma-separated list of tags to mutate.
@export var tags_csv : String = ""
## If enabled, tags matching will be case-sensitive.
@export var case_sensitive : bool = false

func _init():
	super._init()
	resource_name = "Tags Mutate Settings"
