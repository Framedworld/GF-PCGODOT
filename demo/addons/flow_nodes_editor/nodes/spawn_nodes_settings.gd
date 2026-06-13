@tool
class_name SpawnNodesNodeSettings
extends NodeSettings

@export_group("Spawn Nodes")

## Default node class to spawn when selectors/variants are not used.
@export var node_class : String = "OmniLight3D"
## List of node class candidates this node can choose from while spawning/assigning.
@export var node_class_variants : Array[String] = []
## Attribute name used to read/write node selector on point data.
@export var node_selector_attribute : String = ""
## If enabled, randomly chooses from node_class_variants instead of using node_selector_attribute order.
@export var randomize_node_variants : bool = false
## Scene/resource path used to resolve spawn parent.
@export var spawn_parent_path : String = ""
## When enabled, clears previous instances before writing new results.
@export var clear_previous_instances : bool = true
## Scene/resource path used to resolve assign target.
@export var assign_target_path : String = ""
## When enabled, assigns attributes during node execution.
@export var assign_attributes: Dictionary

func _init():
	super._init()
	resource_name = "Spawn Nodes Settings"

func exposeParam(name : String) -> bool:
	if name == "node_selector_attribute":
		return node_class_variants.size() > 0 and not randomize_node_variants
	return true
