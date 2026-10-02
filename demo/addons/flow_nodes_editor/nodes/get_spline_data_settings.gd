@tool
extends NodeSettings

@export_group("Get Spline Data")

enum eOutputMode {
	## One Data per Path3D (UE: one spline data per spline component).
	PerSpline,
	## A single Data whose shape is the union of every spline.
	Merged,
}

## Group name to collect Path3D nodes from. Empty scans the whole scene.
@export var group_name : String
## Metadata key that must be true on a Path3D for it to be collected.
@export var required_meta_bool : StringName
## Also collect Path3D descendants of the group members (or of the scene root).
@export var recursive : bool = true
## One Data per spline, or one merged Data.
@export var output_mode : eOutputMode = eOutputMode.PerSpline
## Radius of the spline's tube when it is used as a volume (Difference,
## Intersection, sample_density): distance from the curve where density reaches 0.
@export var tube_half_width : float = 1.0
## Hardness of the tube edge (UE Steepness): 1 = hard tube, lower = density ramps
## down from the curve to the tube edge.
@export_range( 0.0, 1.0 ) var tube_steepness : float = 1.0

func _init():
	super._init()
	resource_name = "Get Spline Data Settings"
