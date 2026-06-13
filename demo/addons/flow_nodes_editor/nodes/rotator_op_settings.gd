@tool
class_name RotatorOpNodeSettings
extends NodeSettings

@export_group("Rotator Op")

## Operation applied to the rotation of each point.
## - Combine: result = current_rotation * operand (operand applied in local space)
## - Invert: result = current_rotation inverted (operand ignored)
## - Lerp: spherically interpolates current_rotation towards operand by `alpha`
## - RotateAroundAxis: rotates current_rotation by `angle_degrees` around `axis`
enum eOperation {
	Combine,
	Invert,
	Lerp,
	RotateAroundAxis,
}

## How the rotation is read from / written back to the point data.
## - Euler: read/write the canonical `rotation` stream (Vector3 Euler degrees)
## - Quaternion: read/write the canonical `rotation_quat` stream (Quaternion)
## Euler stays the default authoring representation.
enum eRepresentation {
	Euler,
	Quaternion,
}

## Chooses the operation this node applies to the rotation.
@export var operation : eOperation = eOperation.Combine:
	set(value):
		if operation != value:
			operation = value
			notify_property_list_changed()

## Representation read from the input and written to the output.
@export var representation : eRepresentation = eRepresentation.Euler

## Operand rotation as Euler degrees (used by Combine / Lerp / and the basis the
## quaternion operand is derived from). Ignored by Invert.
@export var operand_euler : Vector3 = Vector3.ZERO

## Interpolation factor for Lerp (0 = current rotation, 1 = operand).
@export var alpha : float = 0.5

## Axis used by RotateAroundAxis (normalized internally).
@export var axis : Vector3 = Vector3.UP

## Angle in degrees used by RotateAroundAxis.
@export var angle_degrees : float = 0.0

func _init():
	super._init()
	resource_name = "Rotator Op"

func exposeParam( name : String ) -> bool:
	match name:
		"operand_euler":
			return operation == eOperation.Combine or operation == eOperation.Lerp
		"alpha":
			return operation == eOperation.Lerp
		"axis", "angle_degrees":
			return operation == eOperation.RotateAroundAxis
	return true
