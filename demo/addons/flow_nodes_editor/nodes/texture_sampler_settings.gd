@tool
extends NodeSettings

@export_group("Texture Sampler")

enum eWrapMode {
	## Wraps coordinates around texture boundaries.
	Wrap,
	## Clamps coordinates to texture boundaries.
	Clamp,
}

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

## The Texture2D asset to sample color values from. The texture is decompressed at runtime if VRAM-compressed.
@export var texture : Texture2D:
	set(value):
		texture = value
		emit_changed()

## The name of the input Vector or Color stream containing the point UV coordinates.
@export var uv_attribute_name : String = "uv":
	set(value):
		uv_attribute_name = value.strip_edges()
		emit_changed()

## The name of the input Vector stream containing point positions to use as a fallback.
## Only used when 'use_position_if_uv_missing' is enabled.
@export var position_attribute_name : String = "position":
	set(value):
		position_attribute_name = value.strip_edges()
		emit_changed()

## If enabled, uses position coordinates to calculate UV mapping when the primary UV attribute is missing.
@export var use_position_if_uv_missing : bool = true:
	set(value):
		if use_position_if_uv_missing != value:
			use_position_if_uv_missing = value
			notify_property_list_changed()

## If enabled, uses X and Z coordinates of the position vector for UV mapping.
## If disabled, uses X and Y coordinates. Only used for position-derived fallback UV mapping.
@export var use_xz_for_position : bool = true:
	set(value):
		use_xz_for_position = value
		emit_changed()

## Scale multiplier applied to the position coordinates when generating fallback UVs.
@export var uv_scale : Vector2 = Vector2(0.1, 0.1):
	set(value):
		uv_scale = value
		emit_changed()

## Translation offset added to the scaled position coordinates when generating fallback UVs.
@export var uv_offset : Vector2 = Vector2.ZERO:
	set(value):
		uv_offset = value
		emit_changed()

## Determines how coordinates outside the [0, 1] range are handled.
@export var wrap_mode : eWrapMode = eWrapMode.Wrap:
	set(value):
		value = clampi(value, 0, eWrapMode.size() - 1)
		wrap_mode = value
		emit_changed()

@export_group("Outputs")
## If enabled, writes the sampled pixel's full Color to the stream named in 'out_color_attribute_name'.
@export var write_color_attribute : bool = true:
	set(value):
		if write_color_attribute != value:
			write_color_attribute = value
			notify_property_list_changed()

## The name of the output Color stream to write the sampled texture color into.
## Only used when 'write_color_attribute' is enabled.
@export var out_color_attribute_name : String = "sampled_color":
	set(value):
		out_color_attribute_name = value.strip_edges()
		emit_changed()

## If enabled, writes a single channel value (float) to the stream named in 'out_value_attribute_name'.
@export var write_value_attribute : bool = true:
	set(value):
		if write_value_attribute != value:
			write_value_attribute = value
			notify_property_list_changed()

## The name of the output Float stream to write the sampled channel value into.
## Only used when 'write_value_attribute' is enabled.
@export var out_value_attribute_name : String = "sampled_value":
	set(value):
		out_value_attribute_name = value.strip_edges()
		emit_changed()

## The color channel from the texture to read and write as the float value.
## Only used when 'write_value_attribute' is enabled.
@export var value_channel : eValueChannel = eValueChannel.Luminance:
	set(value):
		value = clampi(value, 0, eValueChannel.size() - 1)
		value_channel = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Texture Sampler Settings"

func exposeParam(name : String) -> bool:
	if name == "position_attribute_name" or name == "use_xz_for_position" or name == "uv_scale" or name == "uv_offset":
		return use_position_if_uv_missing
	if name == "out_color_attribute_name":
		return write_color_attribute
	if name == "out_value_attribute_name" or name == "value_channel":
		return write_value_attribute
	return true
