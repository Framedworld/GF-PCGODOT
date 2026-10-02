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
## Legacy bridge: write the sampling extent into `size` (old size-as-scale) and
## write NO `bounds_min`/`bounds_max` streams, so the output is byte-identical to
## the node before the size->bounds change. Off = UE-correct unit scale + bounds.
@export var legacy_scale_from_extent : bool = false

enum eOutputMode {
	## Bounds-style surface points (today's output).
	Points,
	## Surface spatial data: a FlowPolygonSurface per outline (zero points, with
	## @data area / perimeter attributes). Sample it with Surface Sampler or To
	## Point, intersect a landscape with it, or use it as a Difference cutter.
	Shape,
}

## Points (default, unchanged output) or surface spatial data.
@export var output_mode : eOutputMode = eOutputMode.Points
## Shape mode: one Data holding the union of every surface instead of one Data per surface.
@export var merge_shapes : bool = false

func _init():
	super._init()
	resource_name = "Create Surface From Spline Settings"

func exposeParam(name : String) -> bool:
	if name == "merge_shapes":
		return output_mode == eOutputMode.Shape
	if name == "out_spline_attribute":
		return include_spline_ref
	return true
