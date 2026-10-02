@tool
extends NodeSettings

@export_group("Get Surface Data")

enum eSource {
	## MeshInstance3D and HeightMapShape3D collision shapes found in the scene.
	Scene,
	## A heightmap image (heightmap_image, else heightmap_texture), no scene needed.
	HeightmapImage,
}

enum eOutputMode {
	## One Data per mesh instance / heightmap shape.
	PerSource,
	## A single Data: all meshes in one mesh surface (union with heightmaps).
	Merged,
}

## Where the surface comes from.
@export var source : eSource = eSource.Scene:
	set( value ):
		source = value
		notify_property_list_changed()
## Group name to collect from. Empty scans the whole scene.
@export var group_name : String
## Metadata key that must be true on a node for it to be collected.
@export var required_meta_bool : StringName
## Also collect descendants of the group members (or of the scene root).
@export var recursive : bool = true
## Collect MeshInstance3D nodes as mesh surfaces.
@export var include_meshes : bool = true
## Collect CollisionShape3D nodes holding a HeightMapShape3D as heightfield surfaces.
@export var include_heightmap_shapes : bool = true
## One Data per source, or one merged Data.
@export var output_mode : eOutputMode = eOutputMode.Merged
## Heightmap image (red channel; 8-bit formats read 0..1, float formats raw).
@export var heightmap_image : Image
## Used when heightmap_image is empty (needs a texture whose image is readable).
@export var heightmap_texture : Texture2D
## Distance between heightmap samples.
@export var image_cell_size : float = 1.0
## Multiplier from pixel value to height.
@export var image_height_scale : float = 1.0
## Placement of the heightmap (local grid space to world space).
@export var image_transform : Transform3D = Transform3D.IDENTITY
## Centre the heightmap grid on image_transform's origin.
@export var image_centered : bool = true
## Vertical band of the surface when used as a density (Difference /
## Intersection): <= 0 means the whole column above and below the surface.
@export var vertical_tolerance : float = -1.0

func _init():
	super._init()
	resource_name = "Get Surface Data Settings"

func exposeParam( name : String ) -> bool:
	if name.begins_with( "image_" ) or name.begins_with( "heightmap_" ):
		return source == eSource.HeightmapImage
	if name in [ "group_name", "required_meta_bool", "recursive", "include_meshes", "include_heightmap_shapes", "output_mode" ]:
		return source == eSource.Scene
	return true
