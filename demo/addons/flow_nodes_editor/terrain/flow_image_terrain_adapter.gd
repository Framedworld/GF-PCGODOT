@tool
class_name FlowImageTerrainAdapter
extends FlowHeightfieldTerrainAdapter

## A heightmap Image (red channel; 8-bit formats read 0..1, float formats raw)
## scaled by height_scale, one sample per pixel at `cell` spacing, placed by a
## transform, optionally with splat images (options.splat_layers) covering the
## same footprint. Same grid as FlowHeightfieldSurface.from_image.

func _init( image : Image = null, cell : float = 1.0, height_scale : float = 1.0, xform : Transform3D = Transform3D.IDENTITY, centered : bool = true, adapter_options : Dictionary = {} ) -> void:
	var has_image := image != null and not image.is_empty()
	super._init( FlowHeightfieldSurface.from_image( image, cell, height_scale, xform, centered ) if has_image else null, adapter_options )
	if not has_image:
		error = "no heightmap image"

func get_type_name() -> String:
	return "Heightmap Image"
