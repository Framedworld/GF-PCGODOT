@tool
extends NodeSettings

@export_group("Tags")

enum eOperation {
	Add,
	Remove,
	Replace,
}

## Chooses the operation this node applies to incoming data.
@export var operation : eOperation = eOperation.Add
## Comma-separated tags used for add/remove/replace tag operations.
@export var tags_csv : String = ""
## If enabled, text matching treats uppercase/lowercase as different values.
@export var case_sensitive : bool = false

func _init():
	super._init()
	resource_name = "Tags Mutate Settings"
