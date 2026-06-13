@tool
extends NodeSettings

@export_group("Get Loop Index")

## Name of the output attribute this node writes.
@export var out_name : String = "loop_index":
	set(value):
		out_name = value.strip_edges()
		emit_changed()

## Base index value used for generated loop/index attributes.
@export var start_index : int = 0:
	set(value):
		start_index = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Get Loop Index Settings"
