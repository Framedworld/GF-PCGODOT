@tool
extends NodeSettings

@export_group("Attribute Rename")
## The name of the existing attribute stream to be renamed.
@export var from_name : String = "":
	set(value):
		from_name = value.strip_edges()
		emit_changed()

## The new name to assign to the renamed attribute stream.
@export var to_name : String = "":
	set(value):
		to_name = value.strip_edges()
		emit_changed()

## If enabled, overrides and replaces any existing attribute stream with the new name.
@export var overwrite_existing : bool = false:
	set(value):
		overwrite_existing = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Attribute Rename Settings"
