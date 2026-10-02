# golden_tolerance.gd
# Cross-platform tolerance layer for the golden harness (tests/golden/README.md,
# "Cross-platform noise").
#
# The golden hashes quantize floats to 1/1000 and hash the whole stream, so a
# single element sitting within one float32 ulp of a rounding boundary flips the
# hash when another platform's libm (sin, cos, atan2) or compiler rounds the
# last bit differently. For Euler angles of 100..180 degrees one ulp is about
# 1.5% of the 1/1000 quantum, so a stream of a few hundred rotations almost
# always has such an element: a plain quantized hash is not portable.
#
# The exact hash stays the strict check. Next to baseline.json,
# baseline_tolerance.json stores, for every float stream the baseline hashes,
# a fingerprint that a re-run on another platform can verify element by element
# without the original values:
#
#   - every value is mapped to a bucket of QUANTUM (boundaries shifted by OFFSET
#     so values on round decimal or power-of-two grids never sit on one);
#   - "masked" values are those that sat within the noise budget of a bucket
#     boundary when the fingerprint was made; their index and that boundary
#     are stored (`m`). The budget `d` is NOISE_ULPS float32 ulps of the
#     stream's largest magnitude (at least ulp(1));
#   - `r` hashes the bucket of every other value (masked ones as a fixed token).
#
# A run whose values differ from the fingerprinted run by at most the budget
# reproduces `r` exactly (an unmasked value was further than the budget from a
# boundary) and keeps every masked value within twice the budget of its
# boundary. A change of QUANTUM or more in any component of any element always
# fails: unmasked, its bucket changes; masked, it leaves the window.
#
# Rotation streams (ANGLE_STREAMS, three components: Euler degrees in Godot's
# default YXZ order, pitch = x) are compared as rotations, not as three
# independent numbers:
#
#   - wraparound: buckets and boundaries are taken modulo 360 / QUANTUM, so
#     +179.9999 and -179.9999 are 0.0002 apart, not 359.9998;
#   - |cos(pitch)| >= GIMBAL_COS: per-component buckets, budget scaled by
#     1 / |cos(pitch)| (yaw and roll extracted from a basis get noisier towards
#     gimbal lock);
#   - |cos(pitch)| < GIMBAL_EXACT_COS (pitch at +-90 up to float noise): the
#     rotation only depends on pitch and phi = yaw - sign(pitch) * roll, so
#     those two are bucketed; the yaw/roll split is arbitrary there;
#   - in between (near gimbal lock): yaw and roll are ill-conditioned, so the
#     element is stored whole (`g`) and compared by rotation distance
#     (rotation_distance_deg), tolerance min(2 * d + float32 term, 0.005 deg).
#
# Only hash differences of float streams can be platform noise. Any other
# difference (point count, stream set, stream type, element count, tags,
# kind, spawn count, errors, integer or string streams) is a failure.
class_name GoldenTolerance extends RefCounted

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

const SIDECAR_PATH := "res://tests/golden/baseline_tolerance.json"
const FORMAT := 1
## Bucket width of the tolerant comparison. A change of this much or more in
## any component of any element is always reported.
const QUANTUM := 0.005
## Bucket boundaries sit at (k - OFFSET) * QUANTUM, off the grid of round
## decimal and power-of-two values (0.125, 2.5, ...) that graphs produce
## exactly, so exact values are never masked.
const OFFSET := 0.381966
## Per-stream noise budget in float32 ulps of the stream's largest magnitude.
const NOISE_ULPS := 8.0
## Vector3 streams holding Euler angles in degrees: compared as rotations.
const ANGLE_STREAMS : Array[String] = ["rotation"]
const ANGLE_PERIOD_BUCKETS := 72000 # 360 / QUANTUM
## Below this |cos(pitch)| (pitch within ~5.7 degrees of +-90) an element is
## near gimbal lock; above it the per-component budget is scaled by
## 1 / |cos(pitch)| (at most 10x).
const GIMBAL_COS := 0.1
## Below this |cos(pitch)| (pitch within ~0.001 degrees of +-90) an element is
## at gimbal lock: compared through (pitch, yaw - sign(pitch) * roll).
const GIMBAL_EXACT_COS := 0.00002
## Float32 representability term of the near-gimbal tolerance, in ulps of 1,
## and its cap (half the smallest change that must always be reported).
const GIMBAL_ULPS := 2.0
const GIMBAL_MAX_TOL_DEG := 0.005
const GIMBAL_TOKEN := -9223372036854775804
const GIMBAL_LOCK_TOKEN := -9223372036854775803

const MASKED_TOKEN := -9223372036854775805
const NAN_TOKEN := -9223372036854775807
const POS_INF_TOKEN := 9223372036854775807
const NEG_INF_TOKEN := -9223372036854775806

## FLOW_GOLDEN_TOLERANCE=strict | noise overrides the platform rule below.
const ENV_POLICY := "FLOW_GOLDEN_TOLERANCE"


# --- policy ----------------------------------------------------------------------

static func platform_id() -> String:
	return "%s.%s" % [OS.get_name(), Engine.get_architecture_name()]

## PLATFORM_NOISE is accepted only off the platform that generated the
## baseline (the exact hash stays the check there), unless overridden with
## FLOW_GOLDEN_TOLERANCE=strict (never accept) or =noise (always accept).
static func noise_allowed(sidecar) -> bool:
	var env := OS.get_environment(ENV_POLICY).strip_edges().to_lower()
	if env == "strict":
		return false
	if env == "noise":
		return true
	if not (sidecar is Dictionary):
		return false
	return platform_id() != str(sidecar.get("platform", ""))

static func load_sidecar(path: String = SIDECAR_PATH) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else null

## The sidecar next to a baseline file: foo.json -> foo_tolerance.json.
static func sidecar_path_for(baseline_path: String) -> String:
	if baseline_path == "res://tests/golden/baseline.json":
		return SIDECAR_PATH
	return baseline_path.get_basename() + "_tolerance.json"


# --- float extraction ----------------------------------------------------------------

## { "comps": int, "values": PackedFloat64Array } for containers the golden hash
## quantizes, or {} for exact-valued containers (int, bool, string, objects).
static func float_components(container) -> Dictionary:
	var values := PackedFloat64Array()
	var comps := 0
	if container is PackedFloat32Array or container is PackedFloat64Array:
		comps = 1
		values.resize(container.size())
		for i in range(container.size()):
			values[i] = container[i]
	elif container is PackedVector2Array or container is PackedVector3Array or container is PackedVector4Array or container is PackedColorArray:
		comps = 2
		if container is PackedVector3Array:
			comps = 3
		elif container is PackedVector4Array or container is PackedColorArray:
			comps = 4
		values.resize(container.size() * comps)
		var k := 0
		for i in range(container.size()):
			var v = container[i]
			for c in range(comps):
				values[k] = v[c]
				k += 1
	elif container is Array and not container.is_empty():
		var t := typeof(container[0])
		match t:
			TYPE_FLOAT: comps = 1
			TYPE_VECTOR2: comps = 2
			TYPE_VECTOR3: comps = 3
			TYPE_VECTOR4, TYPE_COLOR, TYPE_QUATERNION: comps = 4
			_: return {}
		values.resize(container.size() * comps)
		var k := 0
		for item in container:
			if typeof(item) != t:
				return {}
			if comps == 1:
				values[k] = item
				k += 1
			else:
				for c in range(comps):
					values[k] = item[c]
					k += 1
	else:
		return {}
	return { "comps": comps, "values": values }

static func is_angle_address(address: String) -> bool:
	return address.get_slice("|", address.get_slice_count("|") - 1) in ANGLE_STREAMS

static func _ulp32(magnitude: float) -> float:
	var m : float = maxf(absf(magnitude), 1.0)
	return pow(2.0, floorf(log(m) / log(2.0)) - 23.0)

static func noise_budget(values: PackedFloat64Array) -> float:
	var absmax := 0.0
	for v in values:
		if not is_nan(v) and not is_inf(v):
			absmax = maxf(absmax, absf(v))
	return NOISE_ULPS * _ulp32(absmax)

static func _special_token(v: float) -> int:
	if is_nan(v):
		return NAN_TOKEN
	return POS_INF_TOKEN if v > 0.0 else NEG_INF_TOKEN

static func _wrap_bucket(b: int, angle: bool) -> int:
	return posmod(b, ANGLE_PERIOD_BUCKETS) if angle else b

static func _hash_tokens(tokens: PackedInt64Array) -> String:
	var hctx := HashingContext.new()
	hctx.start(HashingContext.HASH_SHA256)
	if tokens.size() > 0:
		hctx.update(tokens.to_byte_array())
	return hctx.finish().hex_encode().substr(0, 16)

static func _ranges(values: PackedFloat64Array, comps: int) -> Array:
	var lo := []
	var hi := []
	for c in range(comps):
		lo.append(INF)
		hi.append(-INF)
	for i in range(values.size()):
		var v := values[i]
		if is_nan(v) or is_inf(v):
			continue
		var c := i % comps
		lo[c] = min(lo[c], v)
		hi[c] = max(hi[c], v)
	for c in range(comps):
		lo[c] = snappedf(lo[c], 0.0001) if not is_inf(lo[c]) else null
		hi[c] = snappedf(hi[c], 0.0001) if not is_inf(hi[c]) else null
	return [lo, hi]


# --- fingerprint and check -------------------------------------------------------------

## |cos(pitch)| of element `e` of an Euler stream (pitch = X, the middle
## rotation of Godot's default YXZ order): 1 far from gimbal lock, 0 at it.
static func _pitch_cos(values: PackedFloat64Array, e: int) -> float:
	return absf(cos(deg_to_rad(values[e * 3])))

## Rotation (Godot's default YXZ Euler order, degrees) as a unit quaternion
## [w, x, y, z] in double precision: q = qy * qx * qz.
static func _quat_yxz(x_deg: float, y_deg: float, z_deg: float) -> PackedFloat64Array:
	var hx := deg_to_rad(x_deg) * 0.5
	var hy := deg_to_rad(y_deg) * 0.5
	var hz := deg_to_rad(z_deg) * 0.5
	var qy := PackedFloat64Array([cos(hy), 0.0, sin(hy), 0.0])
	var qx := PackedFloat64Array([cos(hx), sin(hx), 0.0, 0.0])
	var qz := PackedFloat64Array([cos(hz), 0.0, 0.0, sin(hz)])
	return _qmul(_qmul(qy, qx), qz)

static func _qmul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		a[0] * b[0] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
		a[0] * b[1] + a[1] * b[0] + a[2] * b[3] - a[3] * b[2],
		a[0] * b[2] - a[1] * b[3] + a[2] * b[0] + a[3] * b[1],
		a[0] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[0],
	])

## Angle in degrees of the rotation between two YXZ Euler triples (sign of
## the quaternion ignored, so equivalent triples are 0 apart).
static func rotation_distance_deg(a: Array, b: Array) -> float:
	var qa := _quat_yxz(a[0], a[1], a[2])
	var qb := _quat_yxz(b[0], b[1], b[2])
	var dot := absf(qa[0] * qb[0] + qa[1] * qb[1] + qa[2] * qb[2] + qa[3] * qb[3])
	return rad_to_deg(2.0 * acos(minf(dot, 1.0)))

## Rotation-distance tolerance of a near-gimbal element: twice the stream's
## noise budget plus what a float32 Euler triple can represent there (yaw and
## roll are each extracted from basis entries of size ~|cos(pitch)|, so their
## float32 rounding is amplified by 1/|cos(pitch)|), capped so that a 0.01
## degree change is always reported.
static func gimbal_tolerance_deg(delta: float, pitch_cos: float) -> float:
	return minf(2.0 * delta + rad_to_deg(GIMBAL_ULPS * pow(2.0, -23.0) / maxf(pitch_cos, 1e-9)), GIMBAL_MAX_TOL_DEG)

## Canonical values of an angle element at gimbal lock: pitch and
## phi = yaw - sign(pitch) * roll (Ry(y) Rx(-+90) Rz(z) = Ry(y -+ z) Rx(-+90)).
static func _gimbal_lock_pair(values: PackedFloat64Array, e: int) -> Array:
	var pitch := values[e * 3]
	return [pitch, values[e * 3 + 1] - signf(pitch) * values[e * 3 + 2]]

## Token of value `v` at flat index `i`, or MASKED_TOKEN after recording
## [i, boundary] in `masks` when it lies within `window` buckets of one.
static func _tokenize(v: float, i: int, window: float, angle: bool, masks: Array) -> int:
	if is_nan(v) or is_inf(v):
		return _special_token(v)
	var x := v / QUANTUM + OFFSET
	var b := floorf(x)
	var frac := x - b
	if frac < window:
		masks.append(i)
		masks.append(_wrap_bucket(int(b), angle))
		return MASKED_TOKEN
	if 1.0 - frac < window:
		masks.append(i)
		masks.append(_wrap_bucket(int(b) + 1, angle))
		return MASKED_TOKEN
	return _wrap_bucket(int(b), angle)

## Token of value `v` at flat index `i` against the recorded masks, or a
## failure description (String) when a masked value left its window.
static func _verify(v: float, i: int, window: float, angle: bool, masked: Dictionary) -> Variant:
	if is_nan(v) or is_inf(v):
		return _special_token(v)
	var x := v / QUANTUM + OFFSET
	if not masked.has(i):
		return _wrap_bucket(int(floorf(x)), angle)
	var dist : float = x - float(masked[i])
	if angle:
		dist = fposmod(dist + ANGLE_PERIOD_BUCKETS * 0.5, ANGLE_PERIOD_BUCKETS) - ANGLE_PERIOD_BUCKETS * 0.5
	if absf(dist) > window:
		return "value %s is %s from the value it had at baseline time (noise budget %s)" % [str(v), str(absf(dist) * QUANTUM), str(window * QUANTUM)]
	return MASKED_TOKEN

## Fingerprint of a float container: { n, c, d, r, m, g, lo, hi } (see the
## header), or {} for exact-valued containers.
static func fingerprint(container, angle: bool) -> Dictionary:
	var fc := float_components(container)
	if fc.is_empty():
		return {}
	var values : PackedFloat64Array = fc.values
	var comps : int = fc.comps
	angle = angle and comps == 3
	var delta := noise_budget(values)
	var tokens := PackedInt64Array()
	tokens.resize(values.size())
	var masks := []
	var gimbal := []
	for e in range(values.size() / comps):
		var window := delta / QUANTUM
		if angle:
			var c := _pitch_cos(values, e)
			if c < GIMBAL_EXACT_COS:
				var pair := _gimbal_lock_pair(values, e)
				tokens[e * 3] = _tokenize(pair[0], e * 3, window, true, masks)
				tokens[e * 3 + 1] = _tokenize(pair[1], e * 3 + 1, 2.0 * window, true, masks)
				tokens[e * 3 + 2] = GIMBAL_LOCK_TOKEN
				continue
			if c < GIMBAL_COS:
				gimbal.append_array([e, snappedf(values[e * 3], 0.000001), snappedf(values[e * 3 + 1], 0.000001), snappedf(values[e * 3 + 2], 0.000001)])
				for k in range(3):
					tokens[e * 3 + k] = GIMBAL_TOKEN
				continue
			window /= c
		for k in range(comps):
			tokens[e * comps + k] = _tokenize(values[e * comps + k], e * comps + k, window, angle, masks)
	var ranges := _ranges(values, comps)
	var fp := {
		"n": values.size() / comps,
		"c": comps,
		"d": delta,
		"r": _hash_tokens(tokens),
		"m": masks,
		"lo": ranges[0],
		"hi": ranges[1],
	}
	if not gimbal.is_empty():
		fp["g"] = gimbal
	return fp

## "" when `container` matches fingerprint `fp` within its noise budget,
## otherwise a description of the first problem found.
static func check(container, angle: bool, fp: Dictionary) -> String:
	var fc := float_components(container)
	if fc.is_empty():
		return "not a float stream (exact-valued streams cannot be platform noise)"
	var values : PackedFloat64Array = fc.values
	var comps : int = fc.comps
	angle = angle and comps == 3
	if comps != int(fp.get("c", -1)):
		return "component count %d -> %d" % [int(fp.get("c", -1)), comps]
	if values.size() / comps != int(fp.get("n", -1)):
		return "element count %d -> %d" % [int(fp.get("n", -1)), values.size() / comps]
	var delta := float(fp.get("d", 0.0))
	var masked := {}
	var m : Array = fp.get("m", [])
	for j in range(0, m.size() - 1, 2):
		masked[int(m[j])] = int(m[j + 1])
	var gimbal := {}
	var g : Array = fp.get("g", [])
	for j in range(0, g.size() - 3, 4):
		gimbal[int(g[j])] = [float(g[j + 1]), float(g[j + 2]), float(g[j + 3])]
	if not gimbal.is_empty() and not angle:
		return "near-gimbal rotations recorded but the stream is not a 3-component angle stream"
	var tokens := PackedInt64Array()
	tokens.resize(values.size())
	for e in range(values.size() / comps):
		var window := 2.0 * delta / QUANTUM
		if angle:
			if gimbal.has(e):
				var was : Array = gimbal[e]
				var now := [values[e * 3], values[e * 3 + 1], values[e * 3 + 2]]
				var tol := gimbal_tolerance_deg(delta, absf(cos(deg_to_rad(was[0]))))
				var dist := rotation_distance_deg(was, now)
				if is_nan(dist) or dist > tol:
					return "element %d rotation %s is %s degrees from %s at baseline time (near gimbal lock; tolerance %s)" % [
						e, str(now), str(dist), str(was), str(tol)]
				for k in range(3):
					tokens[e * 3 + k] = GIMBAL_TOKEN
				continue
			var c := _pitch_cos(values, e)
			if c < GIMBAL_EXACT_COS:
				var pair := _gimbal_lock_pair(values, e)
				for k in range(2):
					var t = _verify(pair[k], e * 3 + k, window * (1.0 + k), true, masked)
					if t is String:
						return "element %d (at gimbal lock) %s %s" % [e, "pitch" if k == 0 else "yaw -+ roll", t]
					tokens[e * 3 + k] = t
				tokens[e * 3 + 2] = GIMBAL_LOCK_TOKEN
				continue
			window /= maxf(c, GIMBAL_COS)
		for k in range(comps):
			var t = _verify(values[e * comps + k], e * comps + k, window, angle, masked)
			if t is String:
				return "element %d component %d %s" % [e, k, t]
			tokens[e * comps + k] = t
	if _hash_tokens(tokens) != str(fp.get("r", "")):
		var ranges := _ranges(values, comps)
		return "values moved by %s or more somewhere in the stream (noise budget %s); per-component min %s -> %s, max %s -> %s" % [
			str(QUANTUM), str(delta), str(fp.get("lo")), str(ranges[0]), str(fp.get("hi")), str(ranges[1])]
	return ""


# --- addresses ---------------------------------------------------------------------------

## nodes|<node>|<bulk>|<port>|<stream> (or @attr:<name> for a data attribute),
## outputs|<name>|<stream>.
static func node_address(node_name: String, bulk: int, port: int, stream: String) -> String:
	return "nodes|%s|%d|%d|%s" % [node_name, bulk, port, stream]

static func output_address(output_name: String, stream: String) -> String:
	return "outputs|%s|%s" % [output_name, stream]

## Readable form of an address for failure messages.
static func describe_address(key: String, address: String) -> String:
	var parts := address.split("|")
	if parts[0] == "outputs":
		return "graph=%s output=%s stream=%s" % [key, parts[1], parts[2]]
	return "graph=%s node=%s bulk=%s port=%s stream=%s" % [key, parts[1], parts[2], parts[3], parts[4]]

## The exact hash an entry summary records at `address`, or "" if none.
static func summary_hash(entry: Dictionary, address: String) -> String:
	var parts := address.split("|")
	var summary = null
	if parts[0] == "outputs":
		summary = entry.get("outputs", {}).get(parts[1], null)
		return _summary_stream_hash(summary, parts[2])
	var bulks = entry.get("nodes", {}).get(parts[1], null)
	if not (bulks is Array) or int(parts[2]) >= bulks.size():
		return ""
	var ports = bulks[int(parts[2])]
	if not (ports is Array) or int(parts[3]) >= ports.size():
		return ""
	return _summary_stream_hash(ports[int(parts[3])], parts[4])

static func _summary_stream_hash(summary, stream: String) -> String:
	if not (summary is Dictionary):
		return ""
	if stream.begins_with("@attr:"):
		var attr = summary.get("data_attrs", {}).get(stream.substr(6), null)
		return str(attr.get("hash", "")) if attr is Dictionary else ""
	for s in summary.get("streams", []):
		if str(s.get("name", "")) == stream:
			return str(s.get("hash", ""))
	return ""


# --- classification of differences ---------------------------------------------------

## Splits the differences between two golden entries into `structural`
## (anything but a stream or data-attribute hash: always a failure) and
## `streams` (addresses whose name, type and count agree and only the hash
## differs: candidates for platform noise).
static func classify(expected: Dictionary, actual: Dictionary) -> Dictionary:
	var structural := []
	var streams := []
	if expected.get("status") != actual.get("status"):
		structural.append("status")
		return { "structural": structural, "streams": streams }
	for field in ["spawned", "script_errors", "node_errors"]:
		if expected.get(field) != actual.get(field):
			structural.append(field)
	var exp_out : Dictionary = expected.get("outputs", {})
	var act_out : Dictionary = actual.get("outputs", {})
	if exp_out.keys().size() != act_out.keys().size():
		structural.append("output set")
	for name in exp_out:
		if not act_out.has(name):
			structural.append("output '%s' removed" % name)
			continue
		_classify_summary("outputs|%s" % name, exp_out[name], act_out[name], structural, streams)
	for name in act_out:
		if not exp_out.has(name):
			structural.append("output '%s' added" % name)
	var exp_nodes : Dictionary = expected.get("nodes", {})
	var act_nodes : Dictionary = actual.get("nodes", {})
	for name in exp_nodes:
		if not act_nodes.has(name):
			structural.append("node '%s' disappeared" % name)
			continue
		var eb = exp_nodes[name]
		var ab = act_nodes[name]
		if not (eb is Array and ab is Array) or eb.size() != ab.size():
			structural.append("node '%s' bulk count" % name)
			continue
		for b in range(eb.size()):
			if not (eb[b] is Array and ab[b] is Array) or eb[b].size() != ab[b].size():
				structural.append("node '%s' bulk %d port count" % [name, b])
				continue
			for p in range(eb[b].size()):
				_classify_summary("nodes|%s|%d|%d" % [name, b, p], eb[b][p], ab[b][p], structural, streams)
	for name in act_nodes:
		if not exp_nodes.has(name):
			structural.append("node '%s' is new" % name)
	return { "structural": structural, "streams": streams }

static func _classify_summary(prefix: String, e, a, structural: Array, streams: Array) -> void:
	if e == a:
		return
	if not (e is Dictionary and a is Dictionary):
		structural.append("%s: %s -> %s" % [prefix, "data" if e is Dictionary else "null", "data" if a is Dictionary else "null"])
		return
	for field in ["size", "kind", "tags"]:
		if e.get(field) != a.get(field):
			structural.append("%s: %s %s -> %s" % [prefix, field, e.get(field), a.get(field)])
	var ea : Dictionary = e.get("data_attrs", {})
	var aa : Dictionary = a.get("data_attrs", {})
	if ea.keys().size() != aa.keys().size():
		structural.append("%s: data attribute set" % prefix)
	for name in ea:
		if not aa.has(name) or ea[name].get("data_type") != aa[name].get("data_type"):
			structural.append("%s: data attribute '%s' removed or retyped" % [prefix, name])
		elif ea[name].get("hash") != aa[name].get("hash"):
			streams.append({ "address": "%s|@attr:%s" % [prefix, name], "expected": ea[name].get("hash"), "actual": aa[name].get("hash") })
	var es := {}
	for s in e.get("streams", []):
		es[s.name] = s
	var as_ := {}
	for s in a.get("streams", []):
		as_[s.name] = s
	for name in es:
		if not as_.has(name):
			structural.append("%s: stream '%s' removed" % [prefix, name])
			continue
		var x : Dictionary = es[name]
		var y : Dictionary = as_[name]
		if x.get("data_type") != y.get("data_type") or x.get("count") != y.get("count"):
			structural.append("%s: stream '%s' type %s->%s count %s->%s" % [prefix, name, x.get("data_type"), y.get("data_type"), x.get("count"), y.get("count")])
		elif x.get("hash") != y.get("hash"):
			streams.append({ "address": "%s|%s" % [prefix, name], "expected": x.get("hash"), "actual": y.get("hash") })
	for name in as_:
		if not es.has(name):
			structural.append("%s: stream '%s' added" % [prefix, name])


# --- comparison ----------------------------------------------------------------------------

## Compares one golden entry against the baseline.
##
## Returns { "failures": [String], "noise": [String] }:
## - both empty: exact match;
## - only `noise`: PLATFORM_NOISE (every difference is a float stream whose
##   hash differs but whose values match the fingerprint within the noise
##   budget, on a platform where that is accepted);
## - `failures`: a real difference, printed per stream (graph, node, bulk,
##   port, stream, exact hashes, tolerance verdict).
##
## `raw_provider` is Callable(key: String, addresses: Array) -> Dictionary
## { address: { "container": ..., "hash": String } }: it re-evaluates the graph
## and returns the raw containers so their values can be checked. Its hashes
## must equal the run under test, so the checked values are that run's.
static func compare_entry(key: String, expected: Dictionary, actual: Dictionary, sidecar, raw_provider: Callable, exact_diffs: Array = []) -> Dictionary:
	var failures := []
	var noise := []
	if exact_diffs.is_empty():
		exact_diffs = GoldenGraphsTest.diff_entries(key, expected, actual)
	if exact_diffs.is_empty():
		return { "failures": failures, "noise": noise }
	var cls := classify(expected, actual)
	if not cls.structural.is_empty() or cls.streams.is_empty():
		failures.append_array(exact_diffs)
		return { "failures": failures, "noise": noise }
	var fps = sidecar.get("graphs", {}).get(key, null) if sidecar is Dictionary else null
	var addresses := []
	for cand in cls.streams:
		addresses.append(cand.address)
	var raw : Dictionary = {}
	if fps is Dictionary:
		raw = raw_provider.call(key, addresses)
	for cand in cls.streams:
		var where := describe_address(key, cand.address)
		var head := "%s: exact hash %s -> %s" % [where, cand.expected, cand.actual]
		if not (fps is Dictionary):
			failures.append("%s; no tolerance fingerprint for this graph (regenerate %s)" % [head, SIDECAR_PATH])
			continue
		var fp = fps.get(cand.address, null)
		if not (fp is Dictionary):
			failures.append("%s; not a float stream or no fingerprint: exact change" % head)
			continue
		if str(fp.get("e", "")) != str(cand.expected):
			failures.append("%s; fingerprint is stale (made for hash %s; regenerate %s)" % [head, fp.get("e", ""), SIDECAR_PATH])
			continue
		var got = raw.get(cand.address, null)
		if not (got is Dictionary):
			failures.append("%s; re-evaluation did not produce this stream" % head)
			continue
		if str(got.hash) != str(cand.actual):
			failures.append("%s; re-evaluation gave hash %s, not reproducible" % [head, got.hash])
			continue
		var verdict := check(got.container, is_angle_address(cand.address), fp)
		if verdict.is_empty():
			noise.append("%s; within noise budget %s" % [head, str(fp.get("d"))])
		else:
			failures.append("%s; tolerance: %s" % [head, verdict])
	if failures.is_empty() and not noise.is_empty() and not noise_allowed(sidecar):
		for n in noise:
			failures.append("%s (PLATFORM_NOISE is not accepted on the platform that generated the baseline, %s; set %s=noise to accept it)" % [n, platform_id(), ENV_POLICY])
		noise = []
	return { "failures": failures, "noise": noise }

## Prints a PLATFORM_NOISE pass: a WARNING header, one line per stream, and a
## push_warning so editor runs show it too. `header` replaces the default
## first-line text.
static func print_noise(context: String, noise: Array, header: String = "") -> void:
	if noise.is_empty() and header.is_empty():
		return
	if header.is_empty():
		header = "%d stream(s) differ from the baseline's exact hash but match its tolerance fingerprint within the float noise budget" % noise.size()
	print("WARNING: %s: PLATFORM_NOISE pass on %s: %s" % [context, platform_id(), header])
	for n in noise:
		print("  PLATFORM_NOISE ", n)
	push_warning("%s: PLATFORM_NOISE pass on %s (%d stream(s)); see the printed list" % [context, platform_id(), noise.size()])


# --- raw re-evaluation -------------------------------------------------------------------

## The golden source file of a key ("res://x.tscn::Path" -> "res://x.tscn").
static func source_of(key: String) -> String:
	return key.get_slice("::", 0)

## Re-evaluates golden source `path` exactly like GoldenGraphsTest (same owners,
## inputs, order and skip rules) and returns { key: { address: { container,
## hash } } } for every float-like container, or only the addresses listed in
## `wanted` ({ key: [address, ...] }) when it is a Dictionary.
static func capture(parent: Node, path: String, wanted = null) -> Dictionary:
	var result := {}
	var ext := path.get_extension()
	if ext == "tscn" or ext == "scn":
		var packed = ResourceLoader.load(path)
		if not (packed is PackedScene):
			return result
		var root : Node = packed.instantiate()
		var flow_nodes := []
		if root is FlowGraphNode3D:
			flow_nodes.append(root)
		for n in root.find_children("*", "", true, false):
			if n is FlowGraphNode3D:
				flow_nodes.append(n)
		if flow_nodes.is_empty():
			root.free()
			return result
		var graphs := {}
		for fn in flow_nodes:
			graphs[fn] = fn.graph
			fn.graph = null
		parent.add_child(root)
		for fn in flow_nodes:
			var key := "%s::%s" % [path, str(root.get_path_to(fn))]
			var graph : FlowGraphResource = graphs[fn]
			fn.graph = graph
			if graph == null or not GoldenGraphsTest.skip_reason(graph).is_empty():
				continue
			result[key] = _capture_run(graph, fn, fn.args if fn.args != null else {}, _wanted_for(wanted, key))
		parent.remove_child(root)
		root.free()
	else:
		var graph = ResourceLoader.load(path)
		if not (graph is FlowGraphResource) or not GoldenGraphsTest.skip_reason(graph).is_empty():
			return result
		var owner := FlowGraphNode3D.new()
		owner.name = "GoldenOwner"
		parent.add_child(owner)
		result[path] = _capture_run(graph, owner, {}, _wanted_for(wanted, path))
		parent.remove_child(owner)
		owner.free()
	return result

static func _wanted_for(wanted, key: String):
	if not (wanted is Dictionary):
		return null
	var set := {}
	for a in wanted.get(key, []):
		set[a] = true
	return set

## evaluate_graph_snapshot()'s run (build, ordered execution, read every
## node's bulks, finalize) keeping copies of the raw float containers.
static func _capture_run(graph: FlowGraphResource, owner: FlowGraphNode3D, inputs: Dictionary, want) -> Dictionary:
	var out := {}
	var ctx := FlowData.EvaluationContext.new()
	ctx.owner = owner
	ctx.eval_id = 0
	ctx.gedit_nodes_by_name = {}
	ctx.runtime_params = {}
	var executor := FlowExecutor.new()
	if not executor.begin(graph, inputs, ctx, {}, 0):
		return out
	var node_list : Array = executor.state["node_list"].duplicate()
	for node in executor.state["ordered_nodes"]:
		executor._run_element(node)
	for node in node_list:
		for b in range(node.generated_bulks.size()):
			var bulk = node.generated_bulks[b]
			for p in range(bulk.size()):
				if bulk[p] is FlowData.Data:
					_capture_data("nodes|%s|%d|%d" % [str(node.name), b, p], bulk[p], want, out)
	var outputs := executor.finalize()
	for out_name in outputs:
		if outputs[out_name] is FlowData.Data:
			_capture_data("outputs|%s" % str(out_name), outputs[out_name], want, out)
	return out

static func _capture_data(prefix: String, data: FlowData.Data, want, out: Dictionary) -> void:
	for stream_name in data.streams:
		var address := "%s|%s" % [prefix, str(stream_name)]
		if want is Dictionary and not want.has(address):
			continue
		var container = data.streams[stream_name].container
		if want == null and float_components(container).is_empty():
			continue
		out[address] = { "container": container.duplicate(), "hash": FlowNodeIO.snapshot_hash_container(container) }
	for attr_name in data.data_attrs:
		var address := "%s|@attr:%s" % [prefix, str(attr_name)]
		if want is Dictionary and not want.has(address):
			continue
		var record = data.data_attrs[attr_name]
		var value = record.get("value", null) if record is Dictionary else record
		if want == null and float_components([value]).is_empty():
			continue
		out[address] = { "container": [value], "hash": FlowNodeIO.snapshot_hash_container([value]) }


# --- sidecar generation --------------------------------------------------------------------

## Builds the sidecar for `entries` (normalized golden entries, { key: entry }).
## Every fingerprint is bound to the exact hash `entries` records for that
## stream; `errors` receives every stream whose re-evaluated hash differs from
## it (then the sidecar must not be written).
static func build_sidecar(parent: Node, entries: Dictionary, errors: Array) -> Dictionary:
	var by_file := {}
	for key in entries:
		if entries[key].get("status") == "ok":
			by_file[source_of(key)] = true
	var files := by_file.keys()
	files.sort()
	var graphs := {}
	for path in files:
		var cap := capture(parent, path)
		for key in cap:
			if not entries.has(key) or entries[key].get("status") != "ok":
				continue
			var fps := {}
			var addresses : Array = cap[key].keys()
			addresses.sort()
			for address in addresses:
				var got : Dictionary = cap[key][address]
				var expected_hash := summary_hash(entries[key], address)
				if expected_hash != str(got.hash):
					errors.append("%s: re-evaluated hash %s != recorded %s" % [describe_address(key, address), got.hash, expected_hash])
					continue
				var fp := fingerprint(got.container, is_angle_address(address))
				if fp.is_empty():
					continue
				fp["e"] = expected_hash
				fps[address] = fp
			graphs[key] = fps
	return {
		"format": FORMAT,
		"platform": platform_id(),
		"quantum": QUANTUM,
		"offset": OFFSET,
		"noise_ulps": NOISE_ULPS,
		"angle_streams": ANGLE_STREAMS,
		"graphs": graphs,
	}

## Writes the sidecar one fingerprint per line (valid JSON, diffable).
static func write_sidecar(path: String, data: Dictionary) -> bool:
	var lines := PackedStringArray()
	lines.append("{")
	for field in ["angle_streams", "format", "noise_ulps", "offset", "platform", "quantum"]:
		lines.append("\t%s: %s," % [JSON.stringify(field), JSON.stringify(data[field])])
	lines.append("\t\"graphs\": {")
	var keys : Array = data.graphs.keys()
	keys.sort()
	for ki in range(keys.size()):
		var fps : Dictionary = data.graphs[keys[ki]]
		lines.append("\t\t%s: {" % JSON.stringify(keys[ki]))
		var addresses : Array = fps.keys()
		addresses.sort()
		for ai in range(addresses.size()):
			var sep := "," if ai < addresses.size() - 1 else ""
			lines.append("\t\t\t%s: %s%s" % [JSON.stringify(addresses[ai]), JSON.stringify(fps[addresses[ai]], "", true), sep])
		lines.append("\t\t}%s" % ("," if ki < keys.size() - 1 else ""))
	lines.append("\t}")
	lines.append("}")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("\n".join(lines) + "\n")
	f.close()
	return true
