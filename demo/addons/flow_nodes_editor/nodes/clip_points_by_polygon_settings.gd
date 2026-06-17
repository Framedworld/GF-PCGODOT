@tool
extends NodeSettings

@export_group("Clip Points By Polygon")

enum ePlane {
	## Clip on the XZ projection plane.
	XZ,
	## Clip on the XY projection plane.
	XY,
	## Clip on the YZ projection plane.
	YZ,
}

## The reference 2D projection plane (XZ, XY, or YZ) used for clipping.
@export var plane : ePlane = ePlane.XZ
## If enabled, points inside the polygon boundary are kept and points outside are clipped. If disabled, points outside are kept and points inside are clipped.
@export var keep_inside : bool = true
## The NodePath in the scene tree to the polygon node used for clipping.
@export var polygon_node_path : NodePath
## The attribute stream containing the reference spline or polygon node references.
@export var spline_stream_attribute : String = "node"

func _init():
	super._init()
	resource_name = "Clip Points By Polygon Settings"
