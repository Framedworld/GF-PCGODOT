@tool
class_name CreateTargetNodeSettings
extends NodeSettings

enum eOwnerPolicy {
	## Saved with the scene like other spawned content, unless the component has
	## transient_output (then never saved).
	FollowComponent,
	## Never saved into the scene (owner stays null).
	Transient,
}

@export_group("Create Target Node")

## Name of the Node3D container. An existing container with this name created
## by this node for the same component is reused, so content parented under it
## survives regeneration (and instance pooling keeps working).
@export var node_name : String = "FlowTarget"
## Path (relative to the owner) of the node the container is created under.
## Empty: the owner itself.
@export var parent_path : String = ""
## Groups the container is added to (persistent groups, saved with the scene).
@export var groups : PackedStringArray = PackedStringArray()
## Whether the container is saved into the scene.
@export var owner_policy : eOwnerPolicy = eOwnerPolicy.FollowComponent
## Name of the reference written to the output: a per-data attribute
## ("@data.<name>") on the passed-through input, and a one-element NodePath
## stream when the input is not connected. Spawners read it through their
## spawn_parent_attribute setting.
@export var attribute_name : String = "target"

func _init():
	super._init()
	resource_name = "Create Target Node Settings"
