@tool
class_name SubstractSettings
extends NodeSettings

@export_group("Substract")

enum eOperation {
	## Removes points in A overlapping points in B.
	A_Minus_B,
	## Keeps only points in A overlapping points in B.
	A_Intersection_B,
	#A_Union_B,
}

## Culling behavior mode.
@export var operation : eOperation = eOperation.A_Minus_B

func _init():
	super._init()
	resource_name = "Substract"
