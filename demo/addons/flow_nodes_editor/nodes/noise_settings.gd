@tool
class_name NoiseNodeSettings
extends NodeSettings

@export_group("Noise")

## Output attribute name storing generated noise values.
@export var out_name : String = "density"
## Scaling factor applied to point position coordinates before sampling noise.
@export var in_scale : float = 1.0
## Constant bias value added to generated noise output.
@export var noise_bias : float = 0.0
## Amplitude multiplier applied to generated noise output.
@export var noise_amplitude : float = 1.0
## Optional attribute stream name used as coordinate source for noise sampling instead of position.
@export var sample_attribute : String = "position"

enum eOutputType {
	## Generates a single float noise value.
	Float = 0,
	## Generates 3D vector noise values.
	Vector3 = 1,
}

enum eMode {
	## Overwrites the output attribute stream with noise values.
	Override = 0,
	## Adds noise values to the existing attribute stream values.
	Add = 1,
}

enum eSampleSpace {
	## Samples noise using 3D point positions.
	World3D = 0,
	## Samples noise using 2D (XZ plane) point positions.
	XZ2D = 1,
}

enum eNoiseType {
	## Cellular-like value noise.
	Value = 0,
	## Cubic value noise.
	ValueCubic = 1,
	## Classical Perlin noise.
	Perlin = 2,
	## Worley/Cellular noise.
	Cellular = 3,
	## Simplex noise.
	Simplex = 4,
	## Smoothed simplex noise.
	SimplexSmooth = 5,
}

enum eFractalType {
	## No fractal layering.
	None = 0,
	## Fractional Brownian Motion fractal.
	FBM = 1,
	## Ridged multi-fractal.
	Ridged = 2,
	## Ping-Pong fractal layering.
	PingPong = 3,
}

## Output value format: Float or Vector3.
@export var output_type : eOutputType = eOutputType.Float
## Blend mode: Override or Add.
@export var mode : eMode = eMode.Override
## The noise sample space (World3D or XZ2D).
@export var sample_space : eSampleSpace = eSampleSpace.World3D
## The base noise generator algorithm type.
@export var noise_type : eNoiseType = eNoiseType.Value
## The fractal accumulation algorithm type.
@export var fractal_type : eFractalType = eFractalType.None:
	set(value):
		value = clampi(value, 0, eFractalType.size() - 1)
		if fractal_type != value:
			fractal_type = value
			notify_property_list_changed()
## The number of noise octaves for fractal detail.
@export var fractal_octaves : int = 4
## Lacunarity spacing multiplier for fractal octaves.
@export var fractal_lacunarity : float = 2.0
## Gain amplitude multiplier for fractal octaves.
@export var fractal_gain : float = 0.5
## Strength factor for Ping-Pong fractal type.
@export var fractal_ping_pong_strength : float = 2.0

func _init():
	super._init()
	resource_name = "Noise Settings"

func exposeParam(name : String) -> bool:
	if name == "fractal_octaves" or name == "fractal_lacunarity" or name == "fractal_gain" or name == "fractal_ping_pong_strength":
		return fractal_type != eFractalType.None
	return true

func _get_attribute_selector_props() -> Array[Dictionary]:
	return [
		{ "prop": "sample_attribute", "port": 0 },
	]
