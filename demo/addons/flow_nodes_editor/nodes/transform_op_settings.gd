@tool
extends NodeSettings

@export_group("Transform Op")

enum eOperation {
	## Apply A, then B (UE FTransform A * B). Transform result.
	Compose,
	## Inverse of A. Transform result.
	Invert,
	## Interpolate A towards B by C: translation and scale linearly, rotation by slerp.
	Lerp,
	## B (a Vector position) transformed by A. Vector result.
	TransformPosition,
	## B (a Vector position) transformed by the inverse of A. Vector result.
	InverseTransformPosition,
	## B (a Vector direction) transformed by A's rotation and scale, without translation. Vector result.
	TransformDirection,
	## Each point's transform (position, rotation, size) is followed by A: the point moves with A.
	## Writes position, rotation (or rotation_quat when the point carries one) and size.
	ApplyToPoints,
}

@export var operation : eOperation = eOperation.Compose:
	set(value):
		if operation != value:
			operation = value
			notify_property_list_changed()
## Operand A: a Transform attribute.
@export var in_nameA : String = "transform"
## Operand B: a Transform (Compose, Lerp) or Vector (Transform*) attribute, read from In B when
## connected (and holding it), else from In A.
@export var in_nameB : String = "transform"
## Use constant_b instead of the In B attribute (for Transform* operations the constant's origin is the vector).
@export var use_constant_b : bool = false:
	set(value):
		if use_constant_b != value:
			use_constant_b = value
			notify_property_list_changed()
@export var constant_b : Transform3D = Transform3D.IDENTITY
## Lerp factor attribute; empty uses constant_c.
@export var in_nameC : String = ""
@export var constant_c : float = 0.5
## Attribute written with the result ("@Source" writes back to A). Unused by ApplyToPoints.
@export var out_name : String = "transform"

func _init():
	super._init()
	resource_name = "Transform Op"

func usesB() -> bool:
	return operation != eOperation.Invert and operation != eOperation.ApplyToPoints

func exposeParam( name : String ) -> bool:
	match name:
		"in_nameB":
			return usesB() and not use_constant_b
		"use_constant_b":
			return usesB()
		"constant_b":
			return usesB() and use_constant_b
		"in_nameC", "constant_c":
			return operation == eOperation.Lerp
		"out_name":
			return operation != eOperation.ApplyToPoints
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "in_nameA", "port": 0 }, { "prop": "in_nameB", "port": 0 } ]
