@tool
extends NodeSettings

@export_group("Vector Op")

enum eOperation {
	## A . B (Float).
	Dot,
	## A x B. Vector: a Vector; Vector2: the Float z of the 3D cross product.
	Cross,
	## A / |A| (zero stays zero).
	Normalize,
	## |A| (Float).
	Length,
	## |A|^2 (Float).
	LengthSquared,
	## |A - B| (Float).
	Distance,
	## |A - B|^2 (Float).
	DistanceSquared,
	## A reflected off the surface with normal B: A - 2 (A.N) N, N = B normalized (UE GetReflectionVector).
	Reflect,
	## A projected onto B: (A.B / B.B) B.
	Project,
	## A + (B - A) * C.
	Lerp,
	## A rotated around axis B by C degrees (Vector only).
	RotateAroundAxis,
	## Unsigned angle between A and B in degrees (Float).
	Angle,
	## Per-component minimum of A and B.
	ComponentMin,
	## Per-component maximum of A and B.
	ComponentMax,
}

@export var operation : eOperation = eOperation.Dot:
	set(value):
		if operation != value:
			operation = value
			notify_property_list_changed()
## Operand A: a Vector2, Vector or Vector4 attribute.
@export var in_nameA : String = "@last"
## Operand B: an attribute read from In B when connected (and holding it), else from In A.
@export var in_nameB : String = "normal"
## Use constant_b instead of the In B attribute.
@export var use_constant_b : bool = false:
	set(value):
		if use_constant_b != value:
			use_constant_b = value
			notify_property_list_changed()
## Constant operand B. Vector2 uses x,y; Vector uses x,y,z.
@export var constant_b : Vector4 = Vector4(0, 1, 0, 0)
## Operand C (Lerp alpha, RotateAroundAxis degrees): a numeric attribute, or empty to use constant_c.
@export var in_nameC : String = ""
## Constant operand C.
@export var constant_c : float = 0.5
## Attribute written with the result ("@Source" writes back to A).
@export var out_name : String = "vector_op"

func _init():
	super._init()
	resource_name = "Vector Op"

func usesB() -> bool:
	return operation != eOperation.Normalize and operation != eOperation.Length and operation != eOperation.LengthSquared

func usesC() -> bool:
	return operation == eOperation.Lerp or operation == eOperation.RotateAroundAxis

func exposeParam( name : String ) -> bool:
	match name:
		"in_nameB":
			return usesB() and not use_constant_b
		"use_constant_b":
			return usesB()
		"constant_b":
			return usesB() and use_constant_b
		"in_nameC", "constant_c":
			return usesC()
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [ { "prop": "in_nameA", "port": 0 }, { "prop": "in_nameB", "port": 0 } ]
