@tool
class_name DungeonGeneratorNodeSettings
extends NodeSettings

@export_group("Dungeon Size")
## The width of the dungeon grid in cells.
@export var width : int = 20
## The height of the dungeon grid in cells.
@export var height : int = 20
## The size of each dungeon grid cell in units.
@export var cell_size : float = 2.0

@export_group("Rooms Configuration")
## The maximum number of rooms to attempt to place during generation.
@export var max_rooms : int = 8
## The minimum width/height of generated rooms in cells.
@export var room_min_size : int = 4
## The maximum width/height of generated rooms in cells.
@export var room_max_size : int = 8

@export_group("Decoration")
## The probability (between 0.0 and 1.0) of placing a torch item/point along room walls.
@export var torch_probability : float = 0.15

func _init():
	super._init()
	resource_name = "Dungeon Generator Settings"
