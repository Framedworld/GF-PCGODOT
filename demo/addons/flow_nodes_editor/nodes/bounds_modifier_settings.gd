@tool
class_name BoundsModifierNodeSettings
extends NodeSettings

@export_group("Bounds Modifier")

enum eMode {
	## Directly sets the bounds to the specified minimum and maximum.
	Set,
	## Adds the specified values to the existing bounds.
	Add,
	## Multiplies the existing bounds by the specified values.
	Multiply,
}

# Where the node writes its result.
#  SymmetricSize  - legacy default: collapse |max-min| into the `size` stream
#                   (symmetric extent, bounds center ignored). Byte-for-byte
#                   identical to the original node behavior.
#  PerPointBounds - write asymmetric per-point `bounds_min`/`bounds_max` streams
#                   (UE BoundsMin/BoundsMax parity), leaving `size` untouched so
#                   mesh scale and collision bounds can diverge.
enum eOutput {
	## Writes symmetric size output (legacy behavior).
	SymmetricSize,
	## Writes asymmetric bounds using position offsets.
	PerPointBounds,
}

## The modification mode to apply to point bounds.
@export var mode: eMode = eMode.Set
## Determines whether the result is written back to the legacy 'size' stream or to the per-point bounds streams.
@export var output_mode: eOutput = eOutput.SymmetricSize:
	set(value):
		output_mode = value
		notify_property_list_changed()
		emit_changed()
## The minimum corner of the bounding box.
@export var bounds_min: Vector3 = -Vector3.ONE * 0.5
## The maximum corner of the bounding box.
@export var bounds_max: Vector3 = Vector3.ONE * 0.5

func _init():
	super._init()
	resource_name = "Bounds Modifier Settings"
