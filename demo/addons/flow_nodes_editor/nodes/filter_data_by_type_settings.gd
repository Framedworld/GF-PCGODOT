@tool
class_name FilterDataByTypeNodeSettings
extends NodeSettings

@export_group("Filter Data By Type")

enum eTargetType {
	## Retains only point data containers.
	PointData,
	## Retains only spline/path data containers.
	SplineData,
	## Retains only raw attribute set containers.
	AttributeSet,
}
## Selects the data container type to preserve.
@export var target_type: eTargetType = eTargetType.PointData

func _init():
	super._init()
	resource_name = "Filter Data By Type Settings"
