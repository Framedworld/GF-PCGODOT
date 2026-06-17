@tool
class_name DungeonRoomCandidatesSettings
extends NodeSettings

@export_group("Dungeon Room Candidates")

## The width of the generation grid in cells.
@export var grid_width : int = 24:
	set(value):
		grid_width = value
		emit_changed()

## The height of the generation grid in cells.
@export var grid_height : int = 24:
	set(value):
		grid_height = value
		emit_changed()

## The size of each grid cell in units.
@export var cell_size : float = 2.0:
	set(value):
		cell_size = value
		emit_changed()

## The number of random candidate room slots to evaluate during generation.
@export var candidate_count : int = 40:
	set(value):
		candidate_count = value
		emit_changed()

## The minimum width/height of candidate rooms in cells.
@export var min_room_size : int = 3:
	set(value):
		min_room_size = value
		emit_changed()

## The maximum width/height of candidate rooms in cells.
@export var max_room_size : int = 6:
	set(value):
		max_room_size = value
		emit_changed()

func _init():
	super._init()
	resource_name = "DungeonRoomCandidates"

