@tool
class_name SampleTerrainLayersNodeSettings
extends NodeSettings

@export_group("Terrain Layers")

## List of paint layers to sample.  Each TerrainLayerEntry pairs a name
## with a mask texture.  Each entry produces one Float stream named
## "<stream_prefix><layer_name>" on the output points.
@export var layers : Array[TerrainLayerEntry] = []:
	set(value):
		layers = value
		emit_changed()

## Prefix prepended to each layer name when naming the output stream.
## Default "layer_" makes a layer named "grass" produce stream "layer_grass".
@export var stream_prefix : String = "layer_":
	set(value):
		stream_prefix = value
		emit_changed()

@export_group("World-to-UV Mapping")

## When true the node derives UV from each point's world XZ position
## (X -> U, Z -> V) using world_min/world_max bounds.
## When false the node reads a pre-existing UV attribute from the point data.
@export var use_world_xz : bool = true:
	set(value):
		if use_world_xz != value:
			use_world_xz = value
			notify_property_list_changed()

## World-space minimum corner of the terrain rectangle (X, Z plane).
## Maps to UV (0, 0).  The Vector2 stores (world_X, world_Z).
## Only used when use_world_xz is true.
@export var world_min : Vector2 = Vector2(-100.0, -100.0):
	set(value):
		world_min = value
		emit_changed()

## World-space maximum corner of the terrain rectangle (X, Z plane).
## Maps to UV (1, 1).  The Vector2 stores (world_X, world_Z).
## Only used when use_world_xz is true.
@export var world_max : Vector2 = Vector2(100.0, 100.0):
	set(value):
		world_max = value
		emit_changed()

## Name of the UV attribute to read when use_world_xz is false.
## The attribute must be of type Vector (XY used) or Color (RG used).
@export var uv_attribute_name : String = "uv":
	set(value):
		uv_attribute_name = value.strip_edges()
		emit_changed()

@export_group("Sampling")

## Which channel of each mask texture is interpreted as the layer weight.
enum eValueChannel {
	R,
	G,
	B,
	A,
	Luminance,
}

## Texture channel used as the layer weight value (0..1).
@export var value_channel : eValueChannel = eValueChannel.R:
	set(value):
		value = clampi(value, 0, eValueChannel.size() - 1)
		value_channel = value
		emit_changed()

## How UV coordinates outside [0, 1] are handled.
enum eWrapMode {
	Clamp,
	Wrap,
}

## Clamp keeps the border pixel value; Wrap tiles the texture.
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
