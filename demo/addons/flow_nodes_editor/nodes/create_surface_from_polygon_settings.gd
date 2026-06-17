@tool
extends NodeSettings

@export_group("Create Surface From Polygon")

enum ePlane {
	## Project surface onto the XZ plane.
	XZ,
	## Project surface onto the XY plane.
	XY,
	## Project surface onto the YZ plane.
	YZ,
}

## The reference 2D projection plane (XZ, XY, or YZ) used for creating the surface geometry.
@export var plane : ePlane = ePlane.XZ
## Optional attribute name used to group boundary points into separate polygon surfaces.
@export var group_attribute : String = ""
## The minimum thickness allowed for the generated surface geometry.
@export var minimum_thickness : float = 0.1
## Output attribute name that stores area produced by this node.
@export var out_area_attribute : String = "surface_area"
## Output attribute name that stores perimeter produced by this node.
@export var out_perimeter_attribute : String = "surface_perimeter"
## Output attribute name that stores point count produced by this node.
@export var out_point_count_attribute : String = "surface_point_count"

func _init():
	super._init()
	resource_name = "Create Surface From Polygon Settings"
