@tool
extends NodeSettings

@export_group("Navigation Region Sampler")

enum eSampleMode {
	## Sample points inside the navigation polygon area.
	Polygons,
	## Sample points directly on the navigation polygon vertices.
	Vertices,
}

## Scene tree path to the NavigationRegion3D to sample.
@export_node_path("NavigationRegion3D") var navigation_region_path : NodePath
## The group name to search for navigation regions when path is empty.
@export var group_name : String = ""
## The sampling target mode (Polygons or Vertices).
@export var sample_mode : eSampleMode = eSampleMode.Polygons
## The point scale size assigned to generated sample points.
@export var point_size : Vector3 = Vector3.ONE
## Output attribute name storing navigation region references.
@export var out_region_attribute : String = "navigation_region"
## Output attribute name storing sampled polygon index.
@export var out_polygon_index_attribute : String = "navigation_polygon_index"
## Output attribute name storing sampled area size.
@export var out_area_attribute : String = "navigation_polygon_area"

func _init():
	super._init()
	resource_name = "Navigation Region Sampler Settings"
