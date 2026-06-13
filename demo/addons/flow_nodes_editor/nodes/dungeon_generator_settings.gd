@tool
class_name DungeonGeneratorNodeSettings
extends NodeSettings

@export_group("Dungeon Size")
## Horizontal extent (often room/map width) used by the generator.
@export var width : int = 20
## Height value used when generating points/rooms in 3D space.
@export var height : int = 20
## Size of each grid cell used by this node.
@export var cell_size : float = 2.0

@export_group("Rooms Configuration")
## Upper bound used by this node for rooms.
@export var max_rooms : int = 8
## Size parameter controlling room min size during generation/transforms.
@export var room_min_size : int = 4
## Size parameter controlling room max size during generation/transforms.
@export var room_max_size : int = 8

@export_group("Decoration")
## Chance (0..1) of applying torch per evaluation/sample.
@export var torch_probability : float = 0.15

func _init():
	super._init()
	resource_name = "Dungeon Generator Settings"
