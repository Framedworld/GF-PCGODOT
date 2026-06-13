@tool
class_name GridNodeSettings
extends NodeSettings

@export_group("Grid")

## X component used when composing or overriding vector values.
@export_range( 0, 50 ) var x : int = 3
## Y component used when composing or overriding vector values.
@export_range( 0, 50 ) var y : int = 1
## Z component used when composing or overriding vector values.
@export_range( 0, 50 ) var z : int = 3
## Step amount used when iterating or sampling values.
@export var step : Vector3 = Vector3( 1.0, 1.0, 1.0 )
## Grid origin position from which cell coordinates are generated.
@export var origin : Vector3 = Vector3.ZERO
## Rotation applied to generated or transformed points/instances.
@export var rotation : Vector3 = Vector3.ZERO
## Overall size value used by this node for generated data.
@export var size : float = 1.0

func _init():
	super._init()
	resource_name = "Grid Settings"
