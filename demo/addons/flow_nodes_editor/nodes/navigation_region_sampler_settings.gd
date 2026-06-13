@tool
extends NodeSettings

@export_group("Navigation Region Sampler")

enum eSampleMode {
	Polygons,
	Vertices,
}

## Scene/resource path used to resolve navigation region.
@export_node_path("NavigationRegion3D") var navigation_region_path : NodePath
## Group name used to find or filter scene nodes.
@export var group_name : String = ""
## Selects this node behavior mode (Polygons, Vertices).
@export var sample_mode : eSampleMode = eSampleMode.Polygons
## Size assigned to generated points (point extents/scale hint).
@export var point_size : Vector3 = Vector3.ONE
## Output attribute name that stores region produced by this node.
@export var out_region_attribute : String = "navigation_region"
## Output attribute name that stores polygon index produced by this node.
@export var out_polygon_index_attribute : String = "navigation_polygon_index"
## Output attribute name that stores area produced by this node.
@export var out_area_attribute : String = "navigation_polygon_area"

func _init():
	super._init()
	resource_name = "Navigation Region Sampler Settings"
