@tool
class_name SnapToGridNodeSettings
extends NodeSettings

@export_group("Snap to Grid")
## Size parameter controlling grid size during generation/transforms.
@export var grid_size: Vector3 = Vector3.ONE * 2.0
## Snaps generated positions to the translation grid.
@export var snap_position: bool = true
## Rotation value/attribute used when orienting generated instances or points.
@export var snap_rotation: bool = false:
	set(value):
		snap_rotation = value
		notify_property_list_changed()
## Scale factor used to adjust snap scale.
@export var snap_scale: bool = false:
	set(value):
		snap_scale = value
		notify_property_list_changed()
## Step used when snapping rotation (Euler degrees); ZERO falls back to grid_size
@export var rotation_grid_size: Vector3 = Vector3.ZERO
## Step used when snapping scale; ZERO falls back to grid_size
@export var scale_grid_size: Vector3 = Vector3.ZERO

func exposeParam(name : String) -> bool:
	if name == "rotation_grid_size":
		return snap_rotation
	if name == "scale_grid_size":
		return snap_scale
	return true

func _init():
	super._init()
	resource_name = "Snap to Grid Settings"
