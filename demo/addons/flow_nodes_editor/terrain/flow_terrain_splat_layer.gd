@tool
class_name FlowTerrainSplatLayer
extends Resource

## One paint layer read from a splat image channel, for the terrain adapters
## (get_surface_data `terrain_splat_layers`). The image covers the terrain's
## footprint; lookups follow the Sample Terrain Layers convention (see
## FlowSurfaceLayers): nearest-lower texel, clamped.

enum eChannel {
	## Red channel.
	R,
	## Green channel.
	G,
	## Blue channel.
	B,
	## Alpha channel.
	A,
	## Luminance of the colour.
	Luminance,
}

## Layer name; the weight attribute is the sampler's prefix + this name.
@export var layer_name : String = "":
	set( value ):
		layer_name = value.strip_edges()
		emit_changed()
## Splat image (one layer per channel is the usual layout).
@export var image : Image:
	set( value ):
		image = value
		emit_changed()
## Used when `image` is empty (needs a texture whose image is readable).
@export var texture : Texture2D:
	set( value ):
		texture = value
		emit_changed()
## Channel holding this layer's weight.
@export var channel : eChannel = eChannel.R:
	set( value ):
		channel = clampi( value, 0, eChannel.size() - 1 )
		emit_changed()

func _init() -> void:
	resource_name = "Terrain Splat Layer"

## The image to read: `image`, else the texture's image, else null.
func get_layer_image() -> Image:
	if image != null and not image.is_empty():
		return image
	if texture != null:
		return texture.get_image()
	return null

static func make( name : String, layer_image : Image, layer_channel : int = 0 ) -> FlowTerrainSplatLayer:
	var l := FlowTerrainSplatLayer.new()
	l.layer_name = name
	l.image = layer_image
	l.channel = layer_channel
	return l
