@tool
class_name DungeonConnectRoomsSettings
extends NodeSettings

@export_group("Dungeon Connect Rooms")

## The grid cell size in units used to align and connect rooms in the dungeon layout.
@export var cell_size : float = 2.0:
	set(value):
		cell_size = value
		emit_changed()

func _init():
	super._init()
	resource_name = "DungeonConnectRooms"
