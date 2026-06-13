@tool
class_name DungeonExpandRoomsSettings
extends NodeSettings

@export_group("Dungeon Expand Rooms")

## Size of each grid cell used by this node.
@export var cell_size : float = 2.0:
	set(value):
		cell_size = value
		emit_changed()

func _init():
	super._init()
	resource_name = "DungeonExpandRooms"
