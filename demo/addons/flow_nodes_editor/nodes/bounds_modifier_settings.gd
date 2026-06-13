@tool
class_name BoundsModifierNodeSettings
extends NodeSettings

@export_group("Bounds Modifier")

enum eMode { Set, Add, Multiply }

# Where the node writes its result.
#  SymmetricSize  - legacy default: collapse |max-min| into the `size` stream
#                   (symmetric extent, bounds center ignored). Byte-for-byte
#                   identical to the original node behavior.
#  PerPointBounds - write asymmetric per-point `bounds_min`/`bounds_max` streams
#                   (UE BoundsMin/BoundsMax parity), leaving `size` untouched so
#                   mesh scale and collision bounds can diverge.
enum eOutput { SymmetricSize, PerPointBounds }

## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode: eMode = eMode.Set
## Selects whether the result is written into `size` (legacy) or per-point bounds.
@export var output_mode: eOutput = eOutput.SymmetricSize:
	set(value):
		output_mode = value
		notify_property_list_changed()
		emit_changed()
## Minimum corner of the bounds box.
@export var bounds_min: Vector3 = -Vector3.ONE * 0.5
@export var bounds_max: Vector3 = Vector3.ONE * 0.5

func _init():
	super._init()
	resource_name = "Bounds Modifier Settings"
