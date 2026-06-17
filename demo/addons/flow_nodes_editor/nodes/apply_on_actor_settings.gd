@tool
extends NodeSettings

@export_group("Apply On Actor")

enum eTargetMode {
	## Finds target actors by reading from a point attribute stream containing node references.
	FromNodeStream,
	## Resolves a single target actor using a specific node path in the scene tree.
	NodePath,
	## Resolves target actors by retrieving all nodes belonging to the specified group.
	Group,
}

## Determines how the target actor nodes are located in the scene.
@export var target_mode : eTargetMode = eTargetMode.FromNodeStream:
	set(value):
		value = clampi(value, 0, eTargetMode.size() - 1)
		target_mode = value
		notify_property_list_changed()

## Attribute name used to read/write target stream on point data.
@export var target_stream_attribute : String = "node"
## The scene tree NodePath to the target Node.
@export_node_path("Node") var target_node_path : NodePath
## Group name used to find or filter scene nodes.
@export var group_name : String = ""
## Optional relative NodePath from each resolved target actor to a specific child node.
@export_node_path("Node") var target_child_path : NodePath
## If enabled, writes the position, rotation, and size/scale from the point data back to the target Node3D actor.
@export var apply_transform_to_node3d : bool = false
## A mapping of point attribute names to target Node properties to be assigned during execution.
@export var assign_attributes : Dictionary = {}

func _init():
	super._init()
	resource_name = "Apply On Actor Settings"

func exposeParam(name : String) -> bool:
	if name == "target_stream_attribute":
		return target_mode == eTargetMode.FromNodeStream
	if name == "target_node_path":
		return target_mode == eTargetMode.NodePath
	if name == "group_name":
		return target_mode == eTargetMode.Group
	return true
