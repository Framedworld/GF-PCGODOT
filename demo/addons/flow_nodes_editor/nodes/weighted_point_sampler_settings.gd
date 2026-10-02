@tool
class_name WeightedPointSamplerNodeSettings
extends NodeSettings

@export_group("Weighted Point Sampler")

## Number of points to pick. Without replacement it is capped at the number
## of points with a positive weight.
@export_range(0, 1000000, 1, "or_greater") var count : int = 10
## Numeric attribute giving each point's weight (negative counts as 0; points
## with weight 0 are never picked). Empty, or every weight 0, picks uniformly.
@export var weight_attribute : String = ""
## Allow a point to be picked more than once (independent draws). Off picks
## distinct points.
@export var with_replacement : bool = false
## Optional Int attribute receiving the pick order (0 = first pick). Empty
## disables it.
@export var sample_index_attribute : String = ""
## With replacement, give repeated copies of a point a new seed (the source
## seed hashed with the copy number) so their randomness downstream differs.
## Only applies when the input has a per-point seed stream.
@export var mutate_duplicate_seeds : bool = true

func _init():
	super._init()
	resource_name = "Weighted Point Sampler Settings"

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "weight_attribute", "port": 0 },
	]
