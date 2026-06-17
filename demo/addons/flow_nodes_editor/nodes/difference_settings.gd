@tool
extends NodeSettings

@export_group("Difference")

enum eOperation {
	## Removes points in A that overlap with points in B.
	A_Minus_B,
	## Removes points in B that overlap with points in A.
	B_Minus_A,
	## Keeps only points that overlap between A and B.
	Intersection,
	## Combines points from both A and B.
	Union,
	## Keeps points in A or B but not in both.
	SymmetricDifference,
}

enum eOverlapSource {
	## Uses the legacy boolean flag to resolve overlap selection.
	LegacyKeepAFlag,
	## Selects overlapping points from A.
	FromA,
	## Selects overlapping points from B.
	FromB,
	## Merges properties of both overlapping points.
	MergeAAndB,
}

enum eDensityFunction {
	## Applies a hard binary overlap culling.
	Binary,
	## Applies a minimum-based density attenuation.
	Minimum,
	## Multiplies overlapping densities.
	Multiply,
	## Subtracts overlapping densities.
	Subtract,
}


## Chooses the set difference or boolean operation to perform between Input A and Input B.
@export var operation : eOperation = eOperation.A_Minus_B:
	set(value):
		value = clampi(value, 0, eOperation.size() - 1)
		if operation != value:
			operation = value
			notify_property_list_changed()

## When performing a Union operation, if enabled, preserves points from Input A when they overlap with Input B.
@export var keep_a_on_union_overlap : bool = true:
	set(value):
		keep_a_on_union_overlap = value
		emit_changed()

## Determines which source points to preserve on Union overlap.
@export var union_overlap_source : eOverlapSource = eOverlapSource.LegacyKeepAFlag:
	set(value):
		value = clampi(value, 0, eOverlapSource.size() - 1)
		union_overlap_source = value
		notify_property_list_changed()

## Determines which source point data to use for overlapping points during an Intersection operation.
@export var intersection_overlap_source : eOverlapSource = eOverlapSource.FromA:
	set(value):
		value = clampi(value, 0, eOverlapSource.size() - 1)
		intersection_overlap_source = value
		notify_property_list_changed()

## How overlapped points are resolved. Binary (default) hard-removes them (legacy behavior). Minimum/Multiply/Subtract instead keep them with reduced density computed from box interpenetration (shaped by steepness when present), leaving culling to a downstream density_filter.
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
