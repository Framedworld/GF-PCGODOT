@tool
class_name SampleTerrainLayersNodeSettings
extends NodeSettings

@export_group("Terrain Layers")

## Where layer weights come from.
enum eLayerSource {
	## Mask textures listed in 'layers' (default, the original behaviour).
	Textures,
	## A terrain adapter (WP6): the terrain at 'terrain_node_path', or the single
	## Terrain3D / HTerrain node found in the scene (or in 'terrain_group_name').
	## Writes one stream per terrain layer (prefix + layer name).
	TerrainAdapter,
}

## Read weights from mask textures (default) or from a terrain through its adapter.
@export var layer_source : eLayerSource = eLayerSource.Textures:
	set(value):
		value = clampi(value, 0, eLayerSource.size() - 1)
		if layer_source != value:
			layer_source = value
			notify_property_list_changed()
		emit_changed()

## TerrainAdapter source: terrain node (relative to the graph's owner). Empty
## auto-detects the one Terrain3D / HTerrain node. Also accepts a
## CollisionShape3D with a HeightMapShape3D or a MeshInstance3D (whose layers
## then come from 'terrain_splat_layers').
@export var terrain_node_path : NodePath:
	set(value):
		terrain_node_path = value
		emit_changed()

## TerrainAdapter source: limit auto-detection to this group and its descendants.
@export var terrain_group_name : String = "":
	set(value):
		terrain_group_name = value
		emit_changed()

## TerrainAdapter source: layers to write, by name (after renaming). Empty
## writes every layer of the terrain.
@export var terrain_layers : PackedStringArray:
	set(value):
		terrain_layers = value
		emit_changed()

## TerrainAdapter source: new names for the terrain's own layers, in order
## (empty entries keep the adapter's name, e.g. texture_0).
@export var terrain_layer_names : PackedStringArray:
	set(value):
		terrain_layer_names = value
		emit_changed()

## TerrainAdapter source: extra layers from splat image channels covering the
## terrain footprint.
@export var terrain_splat_layers : Array[FlowTerrainSplatLayer] = []:
	set(value):
		terrain_splat_layers = value
		emit_changed()


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
	if name.begins_with("terrain_"):
		return layer_source == eLayerSource.TerrainAdapter
	if layer_source == eLayerSource.TerrainAdapter and name in ["layers", "use_world_xz", "world_min", "world_max", "uv_attribute_name", "value_channel", "wrap_mode"]:
		return false
	if name == "world_min" or name == "world_max":
		return use_world_xz
	if name == "uv_attribute_name":
		return not use_world_xz
	return true
