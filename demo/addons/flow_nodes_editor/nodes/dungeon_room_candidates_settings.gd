@tool
class_name DungeonRoomCandidatesSettings
extends NodeSettings

@export_group("Dungeon Room Candidates")

## Grid width (cells) used when generating candidate room slots.
@export var grid_width : int = 24:
	set(value):
		grid_width = value
		emit_changed()

## Grid height (cells) used when generating candidate room slots.
@export var grid_height : int = 24:
	set(value):
		grid_height = value
		emit_changed()

## Size of each grid cell used by this node.
@export var cell_size : float = 2.0:
	set(value):
		cell_size = value
		emit_changed()

## Maximum number of candidate rooms/positions considered per pass.
@export var candidate_count : int = 40:
	set(value):
		candidate_count = value
		emit_changed()

## Lower bound used by this node for room size.
@export var min_room_size : int = 3:
	set(value):
		min_room_size = value
		emit_changed()

## Upper bound used by this node for room size.
@export var max_room_size : int = 6:
	set(value):
		max_room_size = value
		emit_changed()

func _init():
	super._init()
	resource_name = "DungeonRoomCandidates"

