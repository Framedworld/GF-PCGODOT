@tool
class_name MatchAndSetNodeSettings
extends NodeSettings

@export_group("Match And Set")

## The attribute stream name used to compare and match entries.
@export var match_attr : String
## Optional attribute stream name specifying selection weights for random distribution.
@export var weight_attr : String
## Points without a `seed` stream normally get a per-point seed from their
## position (FlowData.resolve_seed), like transform and attribute_noise.
## Enable to draw them from the node-global RNG in point order instead, which
## reproduces the output of graphs built before that change.
@export var legacy_global_rng : bool = false

func _init():
	super._init()
	resource_name = "Match And Set"
