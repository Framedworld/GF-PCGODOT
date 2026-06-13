@tool
class_name RemapNodeSettings
extends NodeSettings

@export_group("Remap")

## Name of the input attribute to read from.
@export var in_name : String = "density"
## Name of the output attribute this node writes.
@export var out_name : String = "@in_name"
## Curve asset that remaps input values into the output range.
@export var remap_curve : Curve

func _init():
	super._init()
	remap_curve = Curve.new()
	remap_curve.add_point( Vector2(0,0) )
	remap_curve.add_point( Vector2(1,1) )
	resource_name = "Remap Settings"
