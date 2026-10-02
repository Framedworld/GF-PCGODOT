@tool
class_name FlowHeightMapShapeTerrainAdapter
extends FlowHeightfieldTerrainAdapter

## A HeightMapShape3D (Godot's built-in height collision) placed by a transform,
## typically a CollisionShape3D's global transform. The grid is centred on the
## shape origin with one unit per cell, as Godot physics uses it.

func _init( shape : HeightMapShape3D = null, xform : Transform3D = Transform3D.IDENTITY, adapter_options : Dictionary = {} ) -> void:
	super._init( FlowHeightfieldSurface.from_heightmap_shape( shape, xform ) if shape != null else null, adapter_options )
	if shape == null:
		error = "no HeightMapShape3D"

static func from_collision_shape( cs : CollisionShape3D, adapter_options : Dictionary = {} ) -> FlowHeightMapShapeTerrainAdapter:
	if cs == null or not ( cs.shape is HeightMapShape3D ):
		return FlowHeightMapShapeTerrainAdapter.new( null, Transform3D.IDENTITY, adapter_options )
	return FlowHeightMapShapeTerrainAdapter.new( cs.shape, FlowSpatialSources.world_transform( cs ), adapter_options )

func get_type_name() -> String:
	return "HeightMapShape3D"
