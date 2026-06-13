@tool
class_name FilterDataByTypeNodeSettings
extends NodeSettings

@export_group("Filter Data By Type")

enum eTargetType { PointData, SplineData, AttributeSet }
## Selects this node behavior mode (resource_name).
@export var target_type: eTargetType = eTargetType.PointData

func _init():
	super._init()
	resource_name = "Filter Data By Type Settings"
