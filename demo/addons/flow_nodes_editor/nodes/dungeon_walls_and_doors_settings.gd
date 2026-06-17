@tool
class_name DungeonWallsAndDoorsSettings
extends NodeSettings

@export_group("Dungeon Walls and Doors")

## The grid cell size in units used for matching walls and doors.
@export var cell_size : float = 2.0:
	set(value):
		cell_size = value
		emit_changed()

## The probability (between 0.0 and 1.0) of placing a torch along wall segments.
@export var torch_probability : float = 0.15:
	set(value):
		torch_probability = value
		emit_changed()

## The offset distance wall geometry is inset from the grid boundary line.
@export var wall_inset : float = 0.0:
	set(value):
		wall_inset = value
		emit_changed()

## If enabled, includes pillar points at concave/interior corners of the layout.
@export var include_concave_pillars : bool = true:
	set(value):
		include_concave_pillars = value
		emit_changed()

## The constant Vector3 size/scale assigned to the generated wall/door points.
@export var output_scale : Vector3 = Vector3.ONE:
	set(value):
		output_scale = value
		emit_changed()

func _init():
	super._init()
	resource_name = "DungeonWallsAndDoors"
