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
	## Combines two rotations.
	Combine,
	## Inverts the rotation.
	Invert,
	## Interpolates between two rotations.
	Lerp,
	## Rotates around an axis vector.
	RotateAroundAxis,
}

## How the rotation is read from / written back to the point data.
## - Euler: read/write the canonical `rotation` stream (Vector3 Euler degrees)
## - Quaternion: read/write the canonical `rotation_quat` stream (Quaternion)
## Euler stays the default authoring representation.
enum eRepresentation {
	## Uses Euler angles representation.
	Euler,
	## Uses Quaternion representation.
	Quaternion,
}

## Rotation math operation.
@export var operation : eOperation = eOperation.Combine:
	set(value):
		if operation != value:
			operation = value
			notify_property_list_changed()

## Internal representation format: Euler angles or Quaternion.
@export var representation : eRepresentation = eRepresentation.Euler

## Constant Euler angles rotation offset.
@export var operand_euler : Vector3 = Vector3.ZERO

## Blend factor used for interpolation/Lerp.
@export var alpha : float = 0.5

## Rotation axis vector used for RotateAroundAxis.
@export var axis : Vector3 = Vector3.UP

## Rotation angle in degrees.
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
