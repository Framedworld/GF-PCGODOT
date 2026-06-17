@tool
class_name SnapToGridNodeSettings
extends NodeSettings

@export_group("Snap to Grid")
## Grid spacing size vector for snap positions.
@export var grid_size: Vector3 = Vector3.ONE * 2.0
## If enabled, snaps positions to grid.
@export var snap_position: bool = true
## If enabled, snaps rotations to angular grid.
@export var snap_rotation: bool = false:
	set(value):
		snap_rotation = value
		notify_property_list_changed()
## If enabled, snaps scales/sizes to grid sizes.
@export var snap_scale: bool = false:
	set(value):
		snap_scale = value
		notify_property_list_changed()
## Angular grid step size (in degrees) for snapping rotations.
@export var rotation_grid_size: Vector3 = Vector3.ZERO
## Scale grid step size for snapping scale/size vectors.
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
