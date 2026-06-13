@tool
class_name CopyNodeSettings
extends NodeSettings

@export_group("Copy")

enum eMode {
	LinearCopies,
	SourceToTargets,
}

enum eSourceSelection {
	Cycle,
	RandomDeterministic,
}

## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode : eMode = eMode.LinearCopies:
	set(value):
		value = clampi(value, 0, eMode.size() - 1)
		if mode != value:
			mode = value
			notify_property_list_changed()

## How many duplicate copies to generate per input point.
@export var num_copies := 1:
	set(value):
		num_copies = maxi(0, value)
		emit_changed()
## Per-copy translation offset applied before output.
@export var translation : Vector3 = Vector3.ZERO
## Rotation applied to generated or transformed points/instances.
@export var rotation : Vector3 = Vector3.ZERO

## Selects this node behavior mode (Cycle, RandomDeterministic).
@export var source_selection : eSourceSelection = eSourceSelection.Cycle:
	set(value):
		value = clampi(value, 0, eSourceSelection.size() - 1)
		source_selection = value
		emit_changed()
## If enabled, composes source and target transforms instead of replacing target transforms.
@export var combine_source_with_target_transform : bool = true
## Scale factor used to adjust inherit target scale.
@export var inherit_target_scale : bool = true
## Attribute name used to read/write write target index on point data.
@export var write_target_index_attribute : String = ""

## If enabled, adds an attribute identifying which copy instance produced each output point.
@export var generate_copy_id : String

func _init():
	super._init()
	resource_name = "Copy Settings"

func exposeParam(name : String) -> bool:
	if mode == eMode.LinearCopies:
		if name == "source_selection" or name == "combine_source_with_target_transform" or name == "inherit_target_scale" or name == "write_target_index_attribute":
			return false
		return true

	if name == "num_copies" or name == "translation" or name == "rotation":
		return false
	return true
