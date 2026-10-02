@tool
class_name DiscardPointsOnIrregularSurfaceNodeSettings
extends NodeSettings

enum eHeightMetric {
	## Standard deviation of the neighbourhood heights (Y). Flags slopes too.
	StdDev,
	## RMS distance to the least-squares plane through the neighbourhood: a
	## smooth slope scores 0, bumps and steps score high. Falls back to StdDev
	## when the neighbours are collinear in X/Z.
	PlaneResidual,
	## Largest absolute height difference between the point and a neighbour.
	MaxDeviation,
}

enum eNeighborSearch {
	## Native GDRTree when the library is loaded and the input has at least 64
	## points, otherwise the GDScript grid. Both give identical results.
	Auto,
	## Always the native GDRTree (GDScript grid when the library is missing).
	Native,
	## Always the pure-GDScript uniform grid.
	GDScript,
}

@export_group("Discard Points On Irregular Surface")

## Multiplier on each point's bounds footprint (its X/Z extent around the
## position) that defines its neighbourhood. 1 = exactly the point's bounds.
@export_range(0.0, 100.0, 0.01, "or_greater") var footprint_scale : float = 1.0
## Minimum width of the footprint on X and Z (world units), so points with
## tiny bounds still look at their surroundings. 0 = no minimum.
@export_range(0.0, 1000.0, 0.01, "or_greater") var min_footprint_extent : float = 0.0
## How the height irregularity of the neighbourhood is measured.
@export var height_metric : eHeightMetric = eHeightMetric.StdDev
## Points whose height metric is above this are discarded. Negative disables
## the height test.
@export var max_height_deviation : float = 0.25
## Points whose normal differs from a neighbour's by more than this many
## degrees are discarded. Negative disables the normal test.
@export_range(-1.0, 180.0, 0.1) var max_normal_angle : float = 20.0
## Vector attribute holding the surface normal. When it is missing the point's
## up vector (from rotation_quat or rotation) is used; without rotation, +Y.
@export var normal_attribute : String = "normal"
## Neighbours (other than the point itself) needed for the tests to apply.
@export_range(0, 1000) var min_neighbors : int = 2
## Keep points with fewer than min_neighbors neighbours. Off discards them.
@export var keep_isolated : bool = true
## Optional Float attribute receiving the height metric. Empty disables it.
@export var height_metric_attribute : String = ""
## Optional Float attribute receiving the largest normal angle (degrees).
## Empty disables it.
@export var normal_metric_attribute : String = ""
## Optional Int attribute receiving the neighbour count (excluding the point).
## Empty disables it.
@export var neighbor_count_attribute : String = ""
## Neighbour query backend; results do not depend on it.
@export var neighbor_search : eNeighborSearch = eNeighborSearch.Auto

func _init():
	super._init()
	resource_name = "Discard Points On Irregular Surface Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "normal_attribute", "port": 0 },
	]
