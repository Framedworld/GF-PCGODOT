@tool
class_name NoiseNodeSettings
extends NodeSettings

@export_group("Noise")

## Name of the output attribute this node writes.
@export var out_name : String = "density"
## Input value/attribute key used for scale.
@export var in_scale : float = 1.0
## Constant value added to sampled noise before amplitude/remap.
@export var noise_bias : float = 0.0
## Multiplier applied to sampled noise values.
@export var noise_amplitude : float = 1.0
## Attribute name used to read/write sample on point data.
@export var sample_attribute : String = "position"

enum eOutputType {
	Float = 0,
	Vector3 = 1,
}

enum eMode {
	Override = 0,
	Add = 1,
}

enum eSampleSpace {
	World3D = 0,
	XZ2D = 1,
}

enum eNoiseType {
	Value = 0,
	ValueCubic = 1,
	Perlin = 2,
	Cellular = 3,
	Simplex = 4,
	SimplexSmooth = 5,
}

enum eFractalType {
	None = 0,
	FBM = 1,
	Ridged = 2,
	PingPong = 3,
}

## Selects this node behavior mode (Float, Vector3).
@export var output_type : eOutputType = eOutputType.Float
## Selects which processing mode this node uses (similar to UE PCG node modes).
@export var mode : eMode = eMode.Override
## Selects this node behavior mode (World3D, XZ2D).
@export var sample_space : eSampleSpace = eSampleSpace.World3D
## Selects this node behavior mode (Value, ValueCubic, Perlin, Cellular, Simplex, SimplexSmooth).
@export var noise_type : eNoiseType = eNoiseType.Value
## Selects this node behavior mode (None, FBM, Ridged, PingPong).
@export var fractal_type : eFractalType = eFractalType.None:
	set(value):
		value = clampi(value, 0, eFractalType.size() - 1)
		if fractal_type != value:
			fractal_type = value
			notify_property_list_changed()
## Number of fractal octaves layered in the noise function.
@export var fractal_octaves : int = 4
## Frequency multiplier between consecutive fractal octaves.
@export var fractal_lacunarity : float = 2.0
## Amplitude multiplier between consecutive fractal octaves.
@export var fractal_gain : float = 0.5
## Ping-pong shaping strength for fractal noise variants.
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
