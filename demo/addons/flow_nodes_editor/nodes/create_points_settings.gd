@tool
class_name CreatePointsNodeSettings
extends NodeSettings

enum eCoordinateSpace {
	## Entry transforms are world-space transforms.
	World,
	## Entry transforms are relative to the owner node (the FlowGraphNode3D);
	## without an owner they are used as world transforms.
	Local,
}

@export_group("Create Points")

## The points to create, in output order.
@export var points : Array[FlowPointEntry] = []:
	set(value):
		points = value
		emit_changed()
## Space the entry transforms are expressed in.
@export var coordinate_space : eCoordinateSpace = eCoordinateSpace.World
## Write the entries' bounds_min/bounds_max and steepness. Off leaves the
## points in the size-as-extent model (no bounds streams).
@export var write_bounds : bool = true

func _init():
	super._init()
	resource_name = "Create Points Settings"
