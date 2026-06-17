@tool
extends NodeSettings

@export_group("Create Surface From Spline")

enum ePlane {
	## Project surface onto the XZ plane.
	XZ,
	## Project surface onto the XY plane.
	XY,
	## Project surface onto the YZ plane.
	YZ,
}

## The attribute stream containing Path3D spline references.
@export var spline_stream_attribute : String = "node"
## The reference 2D projection plane (XZ, XY, or YZ) used for creating the surface geometry.
@export var plane : ePlane = ePlane.XZ
## The minimum thickness allowed for the generated surface geometry.
@export var minimum_thickness : float = 0.1
## Output attribute name that stores area produced by this node.
@export var out_area_attribute : String = "surface_area"
## Output attribute name that stores perimeter produced by this node.
@export var out_perimeter_attribute : String = "surface_perimeter"
## When enabled, also outputs spline ref alongside generated points/data.
@export var include_spline_ref : bool = true
## Output attribute name that stores spline produced by this node.
@export var out_spline_attribute : String = "node"

func _init():
	super._init()
	resource_name = "Create Surface From Spline Settings"

func exposeParam(name : String) -> bool:
	if name == "out_spline_attribute":
		return include_spline_ref
	return true
