@tool
class_name SurfaceSamplerNodeSettings
extends NodeSettings

@export_group("Surface Sampler")
## Number of points to sample/generate on the surface.
@export var num_points: int = 40
## Size assigned to generated points (point extents/scale hint).
@export var point_size: Vector3 = Vector3.ONE

func _init():
	super._init()
	resource_name = "Surface Sampler Settings"
