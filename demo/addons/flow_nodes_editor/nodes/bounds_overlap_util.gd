@tool
class_name BoundsOverlapUtil
extends Object

# Shared per-point overlap-resolution math for the density-aware set operations
# (difference / self_pruning). The native RTree stays the broadphase; these
# helpers only run the narrowphase + density fold on the broadphase-flagged
# subset, so the common (Binary) path is unaffected.

## Build per-point WORLD-space AABB min/max corners for a Data set, honoring
## per-point bounds_min/bounds_max when present and falling back to symmetric
## `size`-derived bounds otherwise (via Data.getEffectiveBounds). `positions`
## is supplied by the caller (already validated to be one-per-point).
## Returns { "min": PackedVector3Array, "max": PackedVector3Array }.
static func world_aabbs(data : FlowData.Data, positions : PackedVector3Array) -> Dictionary:
	var local := data.getEffectiveBounds()
	var lmin : PackedVector3Array = local.min
	var lmax : PackedVector3Array = local.max
	var n := positions.size()
	var wmin := PackedVector3Array()
	var wmax := PackedVector3Array()
	wmin.resize(n)
	wmax.resize(n)
	for i in range(n):
		# getEffectiveBounds returns one entry per point (length == data.size()).
		# Guard the index in case positions and bounds disagree.
		var li : int = i if i < lmin.size() else 0
		var p : Vector3 = positions[i]
		wmin[i] = p + lmin[li]
		wmax[i] = p + lmax[li]
	return { "min": wmin, "max": wmax }

## Interpenetration ratio of box A against box B in [0..1]: the fraction of A's
## extent (per axis, multiplied) that lies inside B. 0 = no overlap, 1 = A fully
## inside B on every axis. Robust to zero-extent axes.
static func penetration_ratio(a_min : Vector3, a_max : Vector3, b_min : Vector3, b_max : Vector3) -> float:
	var ox : float = minf(a_max.x, b_max.x) - maxf(a_min.x, b_min.x)
	var oy : float = minf(a_max.y, b_max.y) - maxf(a_min.y, b_min.y)
	var oz : float = minf(a_max.z, b_max.z) - maxf(a_min.z, b_min.z)
	if ox <= 0.0 or oy <= 0.0 or oz <= 0.0:
		return 0.0
	var ax : float = a_max.x - a_min.x
	var ay : float = a_max.y - a_min.y
	var az : float = a_max.z - a_min.z
	var rx : float = 1.0 if ax <= 0.0 else clampf(ox / ax, 0.0, 1.0)
	var ry : float = 1.0 if ay <= 0.0 else clampf(oy / ay, 0.0, 1.0)
	var rz : float = 1.0 if az <= 0.0 else clampf(oz / az, 0.0, 1.0)
	return clampf(rx * ry * rz, 0.0, 1.0)

## Shape a raw penetration ratio by a per-point steepness in [0..1].
##  steepness == 1 -> binary box: any penetration yields full factor 1.0.
##  steepness  < 1 -> falloff ramp: the factor eases in. At steepness 0 the
##                    factor equals the linear penetration ratio (softest).
## This mirrors UE's notion that steepness is the hardness of the volume edge.
static func shape_factor(ratio : float, steepness : float) -> float:
	if ratio <= 0.0:
		return 0.0
	steepness = clampf(steepness, 0.0, 1.0)
	if steepness >= 1.0:
		return 1.0
	# Power ramp: low steepness => exponent ~1 (linear), high => sharp toe.
	# exponent in [~0.08 .. 1]; smaller exponent pushes ratio toward 1 faster.
	var exponent : float = 1.0 - steepness * 0.92
	return clampf(pow(ratio, exponent), 0.0, 1.0)

## Apply a density function fold. `density` and `factor` are scalars; returns the
## attenuated density clamped to [0..1].
static func fold_density(density : float, factor : float, density_function : int, fn_minimum : int, fn_multiply : int, fn_subtract : int) -> float:
	if density_function == fn_minimum:
		return clampf(minf(density, 1.0 - factor), 0.0, 1.0)
	elif density_function == fn_multiply:
		return clampf(density * (1.0 - factor), 0.0, 1.0)
	elif density_function == fn_subtract:
		return clampf(density - factor, 0.0, 1.0)
	return clampf(density, 0.0, 1.0)
