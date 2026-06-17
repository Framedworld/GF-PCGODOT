@tool
class_name MakeVectorNodeSettings
extends NodeSettings

@export_group("Make Vector")

## X component used when composing or overriding vector values.
@export var x : float
## Y component used when composing or overriding vector values.
@export var y : float
## Z component used when composing or overriding vector values.
@export var z : float

# This is a signal to stop presenting the rest of the output as inputs of the box
var HiddenFromThisPoint := true
## The output attribute stream name in which to write the composed vector.
@export var out_name : String = "Vector"

func _init():
	super._init()
	resource_name = "Make Vector Settings"
