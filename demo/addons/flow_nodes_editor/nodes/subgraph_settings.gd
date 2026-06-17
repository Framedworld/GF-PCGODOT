@tool
class_name SubgraphNodeSettings
extends NodeSettings

@export_group("Subgraph")

## The subgraph resource to run.
@export var graph : FlowGraphResource:
	set(value):
		graph = value
		emit_changed()

## Optional parameters to override on the subgraph.
@export var param_overrides : Dictionary = {}

func _init():
	super._init()
	resource_name = "Subgraph"

## Returns the effective value for a parameter: override if set, else graph default.
func get_param_value(param: GraphInputParameter) -> Variant:
	if param_overrides.has(param.name):
		return param_overrides[param.name]
	return param.get_default_value()

## Sets a per-instance override for a parameter.
func set_param_override(param_name: String, value: Variant):
	param_overrides[param_name] = value
	emit_changed()

## Clears a per-instance override, reverting to graph default.
func clear_param_override(param_name: String):
	param_overrides.erase(param_name)
	emit_changed()

## Returns true if a parameter has a per-instance override.
func has_param_override(param_name: String) -> bool:
	return param_overrides.has(param_name)
