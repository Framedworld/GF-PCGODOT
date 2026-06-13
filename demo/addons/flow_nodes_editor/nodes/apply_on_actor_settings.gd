@tool
extends NodeSettings

@export_group("Apply On Actor")

enum eTargetMode {
	FromNodeStream,
	NodePath,
	Group,
}

## Selects this node behavior mode (FromNodeStream, NodePath, Group).
@export var target_mode : eTargetMode = eTargetMode.FromNodeStream:
	set(value):
		value = clampi(value, 0, eTargetMode.size() - 1)
		target_mode = value
		notify_property_list_changed()

## Attribute name used to read/write target stream on point data.
@export var target_stream_attribute : String = "node"
## Scene/resource path used to resolve target node.
@export_node_path("Node") var target_node_path : NodePath
## Group name used to find or filter scene nodes.
@export var group_name : String = ""
## Scene/resource path used to resolve target child.
@export_node_path("Node") var target_child_path : NodePath
## If enabled, writes point transform (position/rotation/scale) back to the target Node3D.
@export var apply_transform_to_node3d : bool = false
## When enabled, assigns attributes during node execution.
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
