@tool
class_name SampleTerrainLayersNodeSettings
extends NodeSettings

@export_group("Terrain Layers")

## An array of terrain layers to sample. Each entry associates a layer name with a mask texture.
## The node outputs a float stream (0.0 to 1.0) for each layer indicating its sample weight.
@export var layers : Array[TerrainLayerEntry] = []:
	set(value):
		layers = value
		emit_changed()

## The prefix prepended to the generated output stream names for each layer.
## For example, a prefix of 'layer_' with a layer named 'grass' creates the stream 'layer_grass'.
@export var stream_prefix : String = "layer_":
	set(value):
		stream_prefix = value
		emit_changed()

@export_group("World-to-UV Mapping")

## If enabled, projects the points' world-space XZ coordinates into [0, 1] UVs using 'world_min' and 'world_max'.
## If disabled, reads UV coordinates directly from the point attribute named in 'uv_attribute_name'.
@export var use_world_xz : bool = true:
	set(value):
		if use_world_xz != value:
			use_world_xz = value
			notify_property_list_changed()

## The minimum boundary in world coordinates (X and Z) corresponding to UV coordinate (0.0, 0.0) on the textures.
## Only used when 'use_world_xz' is enabled.
@export var world_min : Vector2 = Vector2(-100.0, -100.0):
	set(value):
		world_min = value
		emit_changed()

## The maximum boundary in world coordinates (X and Z) corresponding to UV coordinate (1.0, 1.0) on the textures.
## Only used when 'use_world_xz' is enabled.
@export var world_max : Vector2 = Vector2(100.0, 100.0):
	set(value):
		world_max = value
		emit_changed()

## The name of the input Vector or Color attribute to read UV coordinates from.
## Only used when 'use_world_xz' is disabled.
@export var uv_attribute_name : String = "uv":
	set(value):
		uv_attribute_name = value.strip_edges()
		emit_changed()

@export_group("Sampling")

## Which channel of each mask texture is interpreted as the layer weight.
enum eValueChannel {
	## Sample the Red channel.
	R,
	## Sample the Green channel.
	G,
	## Sample the Blue channel.
	B,
	## Sample the Alpha channel.
	A,
	## Sample the calculated Luminance value.
	Luminance,
}

## The texture color channel (Red, Green, Blue, Alpha, or Luminance) to interpret as the layer weight.
@export var value_channel : eValueChannel = eValueChannel.R:
	set(value):
		value = clampi(value, 0, eValueChannel.size() - 1)
		value_channel = value
		emit_changed()

## How UV coordinates outside [0, 1] are handled.
enum eWrapMode {
	## Clamps coordinates to terrain boundaries.
	Clamp,
	## Wraps coordinates around terrain boundaries.
	Wrap,
}

## Determines how UV coordinates outside the [0, 1] range are handled.
@export var wrap_mode : eWrapMode = eWrapMode.Clamp:
	set(value):
		value = clampi(value, 0, eWrapMode.size() - 1)
		wrap_mode = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Sample Terrain Layers Settings"

func exposeParam(name : String) -> bool:
	if name == "world_min" or name == "world_max":
		return use_world_xz
	if name == "uv_attribute_name":
		return not use_world_xz
	return true
