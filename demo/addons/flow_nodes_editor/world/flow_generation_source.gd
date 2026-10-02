@tool
class_name FlowGenerationSource
extends Node3D

## A generation source for FlowWorld3D runtime generation (Unreal's
## UPCGGenerationSource): cells within each level's generation radius of a
## source are generated, cells beyond radius * cleanup_radius_multiplier of
## every source are cleaned up. Put it on the player, the camera rig or
## anything that should pull content in around it.
##
## Any Node3D in the group "flow_generation_source" (FlowWorld3D.SOURCE_GROUP)
## is a source; this helper joins the group by itself and adds a per-source
## radius scale and an on/off switch.

## Disabled sources are ignored.
@export var enabled : bool = true
## Multiplies every level's generation (and cleanup) radius for this source.
@export_range(0.0, 16.0, 0.01, "or_greater") var radius_scale : float = 1.0

func _enter_tree() -> void:
	add_to_group(FlowWorld3D.SOURCE_GROUP)

func _exit_tree() -> void:
	remove_from_group(FlowWorld3D.SOURCE_GROUP)
