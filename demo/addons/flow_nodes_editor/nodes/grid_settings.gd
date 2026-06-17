@tool
class_name GridNodeSettings
extends NodeSettings

@export_group("Grid")

## The number of points along the X axis of the grid.
@export_range( 0, 50 ) var x : int = 3
## The number of points along the Y axis of the grid.
@export_range( 0, 50 ) var y : int = 1
## The number of points along the Z axis of the grid.
@export_range( 0, 50 ) var z : int = 3
## The distance spacing between adjacent grid points.
@export var step : Vector3 = Vector3( 1.0, 1.0, 1.0 )
## The local origin/offset of the generated grid.
@export var origin : Vector3 = Vector3.ZERO
## The local rotation applied to the grid layout.
@export var rotation : Vector3 = Vector3.ZERO
## The scale/size multiplier applied to the grid layout.
@export var size : float = 1.0

func _init():
	super._init()
	resource_name = "Grid Settings"
