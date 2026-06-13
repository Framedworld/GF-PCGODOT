@tool
extends NodeSettings

@export_group("Clip Points By Polygon")

enum ePlane {
	XZ,
	XY,
	YZ,
}

## Selects this node behavior mode (XZ, XY, YZ).
@export var plane : ePlane = ePlane.XZ
## When enabled, preserves inside instead of discarding/replacing it.
@export var keep_inside : bool = true
## Scene/resource path used to resolve polygon node.
@export var polygon_node_path : NodePath
## Attribute name used to read/write spline stream on point data.
@export var spline_stream_attribute : String = "node"

func _init():
	super._init()
	resource_name = "Clip Points By Polygon Settings"
