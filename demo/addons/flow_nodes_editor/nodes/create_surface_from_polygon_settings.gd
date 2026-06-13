@tool
extends NodeSettings

@export_group("Create Surface From Polygon")

enum ePlane {
	XZ,
	XY,
	YZ,
}

## Selects this node behavior mode (XZ, XY, YZ).
@export var plane : ePlane = ePlane.XZ
## Attribute name used to read/write group on point data.
@export var group_attribute : String = ""
## Lower bound used by this node for thickness.
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
