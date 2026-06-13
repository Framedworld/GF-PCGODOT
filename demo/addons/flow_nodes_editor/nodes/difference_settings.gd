@tool
extends NodeSettings

@export_group("Difference")

enum eOperation {
	A_Minus_B,
	B_Minus_A,
	Intersection,
	Union,
	SymmetricDifference,
}

enum eOverlapSource {
	LegacyKeepAFlag,
	FromA,
	FromB,
	MergeAAndB,
}

# How overlapped points are resolved.
#  Binary   - legacy default: overlapped points are hard-removed (today's
#             behavior, byte-for-byte). No density is touched.
#  Minimum  - density := min(density, 1 - overlap_factor). Survives, attenuated.
#  Multiply - density := density * (1 - overlap_factor).
#  Subtract - density := density - overlap_factor (clamped to 0).
# For the non-Binary modes overlapped points are KEPT with reduced density;
# culling is left to a downstream density_filter. Steepness (when present)
# shapes the overlap_factor falloff ramp.
enum eDensityFunction {
	Binary,
	Minimum,
	Multiply,
	Subtract,
}

## Chooses the operation this node applies to incoming data.
@export var operation : eOperation = eOperation.A_Minus_B:
	set(value):
		value = clampi(value, 0, eOperation.size() - 1)
		if operation != value:
			operation = value
			notify_property_list_changed()

@export var keep_a_on_union_overlap : bool = true:
	set(value):
		keep_a_on_union_overlap = value
		emit_changed()

@export var union_overlap_source : eOverlapSource = eOverlapSource.LegacyKeepAFlag:
	set(value):
		value = clampi(value, 0, eOverlapSource.size() - 1)
		union_overlap_source = value
		notify_property_list_changed()

@export var intersection_overlap_source : eOverlapSource = eOverlapSource.FromA:
	set(value):
		value = clampi(value, 0, eOverlapSource.size() - 1)
		intersection_overlap_source = value
		notify_property_list_changed()

## How overlapped points are resolved. Binary (default) hard-removes them
## (legacy behavior). Minimum/Multiply/Subtract instead keep them with reduced
## density computed from box interpenetration (shaped by steepness when present),
## leaving culling to a downstream density_filter.
@export var density_function : eDensityFunction = eDensityFunction.Binary:
	set(value):
		value = clampi(value, 0, eDensityFunction.size() - 1)
		density_function = value
		emit_changed()

func _init():
	super._init()
	resource_name = "Difference Settings"

func exposeParam(name : String) -> bool:
	if name == "keep_a_on_union_overlap":
		return operation == eOperation.Union and union_overlap_source == eOverlapSource.LegacyKeepAFlag
	if name == "union_overlap_source":
		return operation == eOperation.Union
	if name == "intersection_overlap_source":
		return operation == eOperation.Intersection
	# Density-function attenuation only applies to the subtractive operations.
	if name == "density_function":
		return operation == eOperation.A_Minus_B or operation == eOperation.B_Minus_A
	return true
