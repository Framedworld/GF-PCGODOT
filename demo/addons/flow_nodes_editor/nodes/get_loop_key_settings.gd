@tool
extends NodeSettings

@export_group("Get Loop Key")

## The name of the output attribute that receives the iteration key.
@export var out_name : String = "loop_key":
	set(value):
		out_name = value.strip_edges()
		emit_changed()

func _init():
	super._init()
	resource_name = "Get Loop Key Settings"
