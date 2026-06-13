@tool
class_name TerrainLayerEntry
extends Resource

## A single paint-layer entry used by the Sample Terrain Layers node.
## Pairs a short name with a mask texture that encodes the layer weight.

## Short identifier used to name the output stream: e.g. "grass" becomes
## the stream "layer_grass" (prefix configured on the parent settings).
## Must be non-empty and unique within the layers array.
@export var layer_name : String = "":
	set(value):
		layer_name = value.strip_edges()
		emit_changed()

## Mask texture whose pixel value (in the chosen channel) encodes the
## layer weight in 0..1.  Greyscale or RGBA textures both work.
@export var texture : Texture2D:
	set(value):
		texture = value
		emit_changed()

func _init():
	resource_name = "Terrain Layer Entry"
