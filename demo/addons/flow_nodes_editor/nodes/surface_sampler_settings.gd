@tool
class_name SurfaceSamplerNodeSettings
extends NodeSettings

@export_group("Surface Sampler")
## The number of points to sample across the surface area.
@export var num_points: int = 40
## Default scale size assigned to generated sample points.
@export var point_size: Vector3 = Vector3.ONE

func _init():
	super._init()
	resource_name = "Surface Sampler Settings"
