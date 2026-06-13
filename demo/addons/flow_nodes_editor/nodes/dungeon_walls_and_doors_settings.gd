@tool
class_name DungeonWallsAndDoorsSettings
extends NodeSettings

@export_group("Dungeon Walls and Doors")

## Size of each grid cell used by this node.
@export var cell_size : float = 2.0:
	set(value):
		cell_size = value
		emit_changed()

## Chance (0..1) of applying torch per evaluation/sample.
@export var torch_probability : float = 0.15:
	set(value):
		torch_probability = value
		emit_changed()

## Inset distance applied to wall geometry from room boundaries.
@export var wall_inset : float = 0.0:
	set(value):
		wall_inset = value
		emit_changed()

## When enabled, also outputs concave pillars alongside generated points/data.
@export var include_concave_pillars : bool = true:
	set(value):
		include_concave_pillars = value
		emit_changed()

## Scale factor used to adjust output scale.
@export var output_scale : Vector3 = Vector3.ONE:
	set(value):
		output_scale = value
		emit_changed()

func _init():
	super._init()
	resource_name = "DungeonWallsAndDoors"
