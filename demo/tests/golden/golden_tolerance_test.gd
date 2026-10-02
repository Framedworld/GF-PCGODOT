# golden_tolerance_test.gd
# The cross-platform tolerance layer of the golden harness
# (golden_tolerance.gd, baseline_tolerance.json): simulated last-bit float noise
# like another platform's libm produces must pass as PLATFORM_NOISE, and real
# changes (0.01 in any component, point count, stream set) must still fail.
#
# The noise tests fingerprint the values this machine produces and perturb
# those, so they hold on any platform (on Windows the captured values already
# carry Windows' own noise relative to the Linux sidecar).
class_name GoldenToleranceTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const COLONNADE := "res://demos/demo_flashy_colonnade.tscn"
const COLONNADE_KEY := "res://demos/demo_flashy_colonnade.tscn::FlowGraphNode3D"
const SAMPLE_POINTS := "res://demos/demo_sample_points.tscn"
const SAMPLE_ROTATION := "nodes|id_0002_sample|0|0|rotation"
## A sidecar that claims another platform generated the baseline, so the
## comparison accepts PLATFORM_NOISE as it would on a Windows run.
const FOREIGN_PLATFORM := "SimulatedOtherOS.x86_64"

static var _capture_cache : Dictionary = {}


func _sidecar() -> Dictionary:
	var sidecar = GoldenTolerance.load_sidecar()
	assert_object(sidecar).override_failure_message("baseline_tolerance.json missing").is_not_null()
	return sidecar if sidecar is Dictionary else {}

func _baseline_graphs() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden/baseline.json"))
	return parsed.get("graphs", {}) if parsed is Dictionary else {}

## Raw float containers of a golden source, evaluated once per run.
func _captured(path: String) -> Dictionary:
	if not _capture_cache.has(path):
		_capture_cache[path] = GoldenTolerance.capture(self, path)
		_clear_gdunit_script_errors()
	return _capture_cache[path]

func _clear_gdunit_script_errors() -> void:
	var tctx = GdUnitThreadManager.get_current_context()
	if tctx == null:
		return
	var exec_ctx = tctx.get_execution_context()
	if exec_ctx != null and exec_ctx.error_monitor != null:
		exec_ctx.error_monitor.clear_logs()

## Copy of a float container with every component multiplied by
## (1 + u * relative), u uniform in [-1, 1], rounded back to the container's
## storage (float32 for packed vector arrays).
static func _jitter_relative(container, relative: float, rng: RandomNumberGenerator):
	var out = container.duplicate()
	var comps := 1
	if out is PackedVector2Array:
		comps = 2
	elif out is PackedVector3Array:
		comps = 3
	elif out is PackedVector4Array or out is PackedColorArray:
		comps = 4
	for i in range(out.size()):
		if comps == 1:
			out[i] = out[i] * (1.0 + rng.randf_range(-relative, relative))
		else:
			var v = out[i]
			for c in range(comps):
				v[c] = v[c] * (1.0 + rng.randf_range(-relative, relative))
			out[i] = v
	return out

## Copy with every component moved by a whole number of float32 ulps in
## [-max_ulps, max_ulps] (the magnitude of a libm last-bit difference).
static func _jitter_ulps(container, max_ulps: int, rng: RandomNumberGenerator):
	var out = container.duplicate()
	var comps := 1
	if out is PackedVector2Array:
		comps = 2
	elif out is PackedVector3Array:
		comps = 3
	elif out is PackedVector4Array or out is PackedColorArray:
		comps = 4
	for i in range(out.size()):
		var v = out[i]
		for c in range(comps):
			var x : float = v if comps == 1 else v[c]
			if x == 0.0:
				continue
			var ulp := pow(2.0, floorf(log(absf(x)) / log(2.0)) - 23.0)
			x += ulp * rng.randi_range(-max_ulps, max_ulps)
			if comps == 1:
				v = x
			else:
				v[c] = x
		out[i] = v
	return out

## Copy with one component of one element changed by `delta`.
static func _bump(container, element: int, component: int, delta: float):
	var out = container.duplicate()
	var v = out[element]
	if v is float:
		v += delta
	else:
		v[component] += delta
	out[element] = v
	return out


## Fingerprint of this machine's own values for `address` (the same function
## and constants the sidecar is built with).
static func _local_fp(container, address: String) -> Dictionary:
	return GoldenTolerance.fingerprint(container, GoldenTolerance.is_angle_address(address))


# --- the budget is pinned ------------------------------------------------------------

## The budget must not grow silently: a larger budget weakens what PLATFORM_NOISE
## can hide, a smaller one breaks Windows again (measured noise reached 39 ulps).
## Change these only with new cross-platform measurements, and regenerate the
## sidecar with FLOW_GOLDEN_UPDATE_TOLERANCE=1.
func test_noise_budget_is_pinned() -> void:
	assert_float(GoldenTolerance.NOISE_ULPS).is_equal(64.0)
	assert_float(GoldenTolerance.BUDGET_CAP).is_equal(0.0015)
	assert_float(GoldenTolerance.QUANTUM).is_equal(0.005)
	assert_float(GoldenTolerance.GIMBAL_COS).is_equal(0.7)
	assert_float(GoldenTolerance.GIMBAL_MAX_TOL_DEG).is_equal(0.005)
	# A masked value is within 1 budget of its boundary and may move 2 budgets:
	# with budget <= QUANTUM / 3 any change of QUANTUM fails.
	assert_bool(GoldenTolerance.BUDGET_CAP * 3.0 <= GoldenTolerance.QUANTUM).is_true()
	assert_float(GoldenTolerance.value_budget(1.0, 1.0)).is_equal(GoldenTolerance.BUDGET_CAP)
	var sidecar := _sidecar()
	assert_float(float(sidecar.get("noise_ulps", 0.0))).is_equal(GoldenTolerance.NOISE_ULPS)
	assert_float(float(sidecar.get("budget_cap", 0.0))).is_equal(GoldenTolerance.BUDGET_CAP)
	assert_float(float(sidecar.get("gimbal_cos", 0.0))).is_equal(GoldenTolerance.GIMBAL_COS)


# --- the problem is real ----------------------------------------------------------

## One-ulp-scale relative noise (1e-7) on the colonnade's sampled rotations
## changes the exact quantized hash in most trials: this is why a plain
## quantized hash is not portable across platforms.
func test_ulp_noise_flips_the_exact_hash_but_not_the_tolerance_check() -> void:
	var original = _captured(COLONNADE)[COLONNADE_KEY][SAMPLE_ROTATION].container
	var exact := FlowNodeIO.snapshot_hash_container(original)
	var fp := _local_fp(original, SAMPLE_ROTATION)
	assert_str(GoldenTolerance.check(original, true, fp)).is_empty()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var flipped := 0
	var trials := 200
	var failures := []
	for t in range(trials):
		var noisy = _jitter_relative(original, 1e-7, rng)
		if FlowNodeIO.snapshot_hash_container(noisy) != exact:
			flipped += 1
		var verdict := GoldenTolerance.check(noisy, true, fp)
		if not verdict.is_empty():
			failures.append("trial %d: %s" % [t, verdict])
	assert_int(flipped).override_failure_message("1e-7 jitter flipped the exact hash in only %d/%d trials" % [flipped, trials]).is_greater(trials / 2)
	assert_array(failures).is_empty()


## Up to 30 float32 ulps on every component of every float stream of the two
## graphs the Windows run reported (colonnade, sample_points) stays within the
## noise budget.
func test_30_ulp_jitter_on_every_reported_stream_is_tolerated() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var failures := []
	var checked := 0
	for path in [COLONNADE, SAMPLE_POINTS]:
		var cap : Dictionary = _captured(path)
		for key in cap:
			for address in cap[key]:
				var container = cap[key][address].container
				var fp := _local_fp(container, address)
				if fp.is_empty():
					continue
				for trial in range(3):
					var noisy = _jitter_ulps(container, 30, rng)
					var verdict := GoldenTolerance.check(noisy, GoldenTolerance.is_angle_address(address), fp)
					checked += 1
					if not verdict.is_empty():
						failures.append("%s: %s" % [GoldenTolerance.describe_address(key, address), verdict])
	assert_int(checked).is_greater(50)
	assert_array(failures).is_empty()


## The worst deviations the Windows retest measured against the previous
## 8-ulp budget, at their upper bounds, applied to the same elements: sampled
## rotation element 439 roll (up to 5.9e-4 degrees), rubble rotation element
## 434 pitch (up to 1.09e-3 degrees at |cos(pitch)| 0.34), duplicated rubble
## position element 1319 z (up to 2.7e-5). All pass now, both signs.
func test_measured_windows_deviations_are_tolerated() -> void:
	var cap : Dictionary = _captured(COLONNADE)[COLONNADE_KEY]
	var cases := [
		["nodes|id_0002_sample|0|0|rotation", 439, 2, 5.92e-4],
		["nodes|id_0005_trans_lintels|0|0|rotation", 439, 2, 5.92e-4],
		["nodes|id_0008_trans_rubble|0|0|rotation", 434, 0, 1.09e-3],
		["nodes|id_0007_dup_rubble|0|0|position", 1319, 2, 2.66e-5],
	]
	var failures := []
	for case in cases:
		var container = cap[case[0]].container
		var fp := _local_fp(container, case[0])
		for sign in [1.0, -1.0]:
			var moved = _bump(container, case[1], case[2], sign * case[3])
			var verdict := GoldenTolerance.check(moved, GoldenTolerance.is_angle_address(case[0]), fp)
			if not verdict.is_empty():
				failures.append("%s element %d comp %d %+f: %s" % [case[0], case[1], case[2], sign * case[3], verdict])
	assert_array(failures).is_empty()


## The propagated position error the retest saw on the rubble positions
## (bucket flips of values that were not masked under the old budget): 30 ulps
## on every position of the transformed rubble passes.
func test_propagated_position_noise_is_tolerated() -> void:
	var cap : Dictionary = _captured(COLONNADE)[COLONNADE_KEY]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for address in ["nodes|id_0008_trans_rubble|0|0|position", "nodes|id_0024_random_color|0|0|position"]:
		var container = cap[address].container
		var fp := _local_fp(container, address)
		for trial in range(20):
			var noisy = _jitter_ulps(container, 30, rng)
			assert_str(GoldenTolerance.check(noisy, false, fp)).override_failure_message("%s trial %d" % [address, trial]).is_empty()


# --- real changes still fail ---------------------------------------------------------

## A 0.01 change in any single component of ANY element of every float stream
## of the colonnade and sample_points graphs fails, both signs: every masked
## value, every near-gimbal rotation, every gimbal-lock element and all the
## others. Checked element by element with the same per-element function
## check() uses (a changed element token changes the stream hash).
func test_a_0_01_change_in_any_component_fails() -> void:
	var missed := []
	var tried := 0
	var masked_tried := 0
	var gimbal_tried := 0
	for path in [COLONNADE, SAMPLE_POINTS]:
		var cap : Dictionary = _captured(path)
		for key in cap:
			for address in cap[key]:
				var stats := verify_0_01_detected(cap[key][address].container, GoldenTolerance.is_angle_address(address), missed, "%s %s" % [key, address])
				tried += stats.tried
				masked_tried += stats.masked
				gimbal_tried += stats.gimbal
	assert_int(tried).is_greater(100000)
	assert_int(masked_tried).override_failure_message("no masked value exercised").is_greater(100)
	assert_int(gimbal_tried).override_failure_message("no near-gimbal rotation exercised").is_greater(100)
	assert_array(missed.slice(0, 20)).is_empty()


## Bumps every component of every element of `container` by +-0.01 against its
## own fingerprint and appends to `missed` any bump check() would not catch.
static func verify_0_01_detected(container, angle: bool, missed: Array, label: String) -> Dictionary:
	var stats := { "tried": 0, "masked": 0, "gimbal": 0 }
	var fp := GoldenTolerance.fingerprint(container, angle)
	if fp.is_empty():
		return stats
	var comps := int(fp.c)
	angle = angle and comps == 3
	var values : PackedFloat64Array = GoldenTolerance.float_components(container).values
	var tables := GoldenTolerance.fp_tables(fp)
	var delta := float(fp.d)
	for e in range(values.size() / comps):
		var original = GoldenTolerance.element_tokens(values, comps, e, angle, delta, tables.masked, tables.gimbal)
		if original is String:
			missed.append("%s element %d does not match its own fingerprint: %s" % [label, e, original])
			continue
		if tables.gimbal.has(e):
			stats.gimbal += 1
		for k in range(comps):
			var i := e * comps + k
			if tables.masked.has(i):
				stats.masked += 1
			var v := values[i]
			if is_nan(v) or is_inf(v):
				continue
			for step in [0.01, -0.01]:
				stats.tried += 1
				values[i] = v + step
				var bumped = GoldenTolerance.element_tokens(values, comps, e, angle, delta, tables.masked, tables.gimbal)
				values[i] = v
				if not (bumped is String) and bumped == original:
					missed.append("%s element %d comp %d %+f" % [label, e, k, step])
	return stats


## Near gimbal lock an Euler triple's yaw and roll swing a lot for a tiny
## rotation change (the colonnade's rubble element at pitch -89.81 moves 0.0013
## degrees in yaw and roll for a 0.0004 degree rotation): compared as a
## rotation it is noise, and a real 0.01 degree rotation is still caught.
func test_near_gimbal_rotation_is_compared_as_a_rotation() -> void:
	var base := PackedVector3Array([Vector3(-89.8144226074219, -172.649963378906, 171.273147583008), Vector3(10.0, 20.0, 30.0)])
	var fp := GoldenTolerance.fingerprint(base, true)
	assert_array(fp.get("g", [])).has_size(4)
	# Same rotation within 0.0004 degrees, Euler components 0.0013 apart.
	var noisy := PackedVector3Array([Vector3(-89.8144226074219, -172.65087890625, 171.274444580078), Vector3(10.0, 20.0, 30.0)])
	assert_float(GoldenTolerance.rotation_distance_deg([base[0].x, base[0].y, base[0].z], [noisy[0].x, noisy[0].y, noisy[0].z])).is_less(0.001)
	assert_str(GoldenTolerance.check(noisy, true, fp)).is_empty()
	# At gimbal lock only yaw -+ roll matters: trading 5 degrees between them
	# is the same rotation, moving either one alone by 0.01 is not.
	var locked := PackedVector3Array([Vector3(-90.0, 30.0, 10.0), Vector3(90.0, -60.0, 20.0)])
	var lock_fp := GoldenTolerance.fingerprint(locked, true)
	assert_array(lock_fp.get("g", [])).is_empty()
	var traded := PackedVector3Array([Vector3(-90.0, 35.0, 5.0), Vector3(90.0, -55.0, 25.0)])
	assert_float(GoldenTolerance.rotation_distance_deg([-90.0, 30.0, 10.0], [-90.0, 35.0, 5.0])).is_less(0.0001)
	assert_float(GoldenTolerance.rotation_distance_deg([90.0, -60.0, 20.0], [90.0, -55.0, 25.0])).is_less(0.0001)
	assert_str(GoldenTolerance.check(traded, true, lock_fp)).is_empty()
	for k in range(3):
		var moved := locked.duplicate()
		var w := moved[1]
		w[k] += 0.01
		moved[1] = w
		assert_str(GoldenTolerance.check(moved, true, lock_fp)).override_failure_message("0.01 on component %d at gimbal lock passed" % k).is_not_empty()
	for k in range(3):
		var bumped := base.duplicate()
		var v := bumped[0]
		v[k] += 0.01
		bumped[0] = v
		assert_str(GoldenTolerance.check(bumped, true, fp)).override_failure_message("0.01 on component %d of a near-gimbal rotation passed" % k).is_not_empty()


func test_changed_point_count_fails() -> void:
	var fp : Dictionary = _sidecar().graphs[COLONNADE_KEY][SAMPLE_ROTATION]
	var container : PackedVector3Array = _captured(COLONNADE)[COLONNADE_KEY][SAMPLE_ROTATION].container
	var shorter := container.duplicate()
	shorter.resize(container.size() - 1)
	assert_str(GoldenTolerance.check(shorter, true, fp)).contains("element count")
	var longer := container.duplicate()
	longer.append(Vector3.ZERO)
	assert_str(GoldenTolerance.check(longer, true, fp)).contains("element count")
	# And at the summary level a count change is structural, never noise.
	var expected : Dictionary = _baseline_graphs()[COLONNADE_KEY]
	var actual : Dictionary = expected.duplicate(true)
	actual.nodes["id_0002_sample"][0][0]["size"] = 474.0
	var result := GoldenTolerance.compare_entry(COLONNADE_KEY, expected, actual, _foreign(_sidecar()), _no_raw)
	assert_array(result.failures).is_not_empty()
	assert_array(result.noise).is_empty()


func test_changed_stream_set_fails() -> void:
	var expected : Dictionary = _baseline_graphs()[COLONNADE_KEY]
	var sidecar := _foreign(_sidecar())
	# Removed stream.
	var removed : Dictionary = expected.duplicate(true)
	var streams : Array = removed.nodes["id_0002_sample"][0][0].streams
	streams.remove_at(0)
	var result := GoldenTolerance.compare_entry(COLONNADE_KEY, expected, removed, sidecar, _no_raw)
	assert_array(result.failures).is_not_empty()
	assert_array(result.noise).is_empty()
	# Added stream.
	var added : Dictionary = expected.duplicate(true)
	added.nodes["id_0002_sample"][0][0].streams.append({ "name": "extra", "data_type": 2.0, "count": 475.0, "hash": "0000000000000000" })
	result = GoldenTolerance.compare_entry(COLONNADE_KEY, expected, added, sidecar, _no_raw)
	assert_array(result.failures).is_not_empty()
	assert_array(result.noise).is_empty()
	# Retyped stream (same hash change pattern, different data_type).
	var retyped : Dictionary = expected.duplicate(true)
	retyped.nodes["id_0002_sample"][0][0].streams[0]["data_type"] = 1.0
	result = GoldenTolerance.compare_entry(COLONNADE_KEY, expected, retyped, sidecar, _no_raw)
	assert_array(result.failures).is_not_empty()


# --- Euler wraparound -----------------------------------------------------------------

func test_rotation_wraparound_is_compared_modulo_360() -> void:
	var base := PackedVector3Array([Vector3(179.9999, -179.9999, 180.0), Vector3(-180.0, 90.0, 0.0), Vector3(179.995, 12.5, -45.0)])
	var fp := GoldenTolerance.fingerprint(base, true)
	# The same rotations written on the other side of the +-180 seam match.
	var wrapped := PackedVector3Array([Vector3(-179.9999, 179.9999, -180.0), Vector3(180.0, 90.0, 0.0), Vector3(179.995, 12.5, -45.0)])
	assert_str(GoldenTolerance.check(wrapped, true, fp)).is_empty()
	# Across the seam by 0.01 (179.995 -> -179.995) is a real change.
	var crossed := PackedVector3Array([Vector3(179.9999, -179.9999, 180.0), Vector3(-180.0, 90.0, 0.0), Vector3(-179.995, 12.5, -45.0)])
	assert_str(GoldenTolerance.check(crossed, true, fp)).is_not_empty()
	# 0.01 next to the seam on the same side is a real change.
	var moved := PackedVector3Array([Vector3(179.9899, -179.9999, 180.0), Vector3(-180.0, 90.0, 0.0), Vector3(179.995, 12.5, -45.0)])
	assert_str(GoldenTolerance.check(moved, true, fp)).is_not_empty()
	# A non-angle stream gets no wraparound: +179.9999 vs -179.9999 differs.
	var linear := GoldenTolerance.fingerprint(base, false)
	assert_str(GoldenTolerance.check(wrapped, false, linear)).is_not_empty()
	# Only the configured angle streams get it.
	assert_bool(GoldenTolerance.is_angle_address("nodes|n|0|0|rotation")).is_true()
	assert_bool(GoldenTolerance.is_angle_address("nodes|n|0|0|position")).is_false()


## Values on round decimal / power-of-two grids are exact on every platform
## and must not be masked (the bucket boundaries are offset from that grid).
func test_exact_grid_values_are_not_masked() -> void:
	var values := PackedVector3Array()
	for i in range(400):
		values.append(Vector3(i * 0.125, i * 0.5, i * 0.6))
	assert_array(GoldenTolerance.fingerprint(values, false).m).is_empty()


# --- the comparison end to end ------------------------------------------------------

## A simulated other-platform run of the colonnade passes as PLATFORM_NOISE
## when the baseline came from another platform, fails on the baseline's own
## platform, and a 0.01 change fails everywhere. The "baseline" here is this
## machine's own run (summary hashes and fingerprints made from the captured
## values), and the "other platform" adds 30-ulp jitter to every rotation and
## position stream, so the test does not depend on where it runs.
func test_simulated_platform_noise_end_to_end() -> void:
	var cap : Dictionary = _captured(COLONNADE)[COLONNADE_KEY]
	var expected : Dictionary = _baseline_graphs()[COLONNADE_KEY].duplicate(true)
	var fps := {}
	for address in cap:
		_set_summary_hash(expected, address, cap[address].hash)
		var fp := _local_fp(cap[address].container, address)
		if not fp.is_empty():
			fp["e"] = cap[address].hash
			fps[address] = fp
	var sidecar := { "platform": FOREIGN_PLATFORM, "graphs": { COLONNADE_KEY: fps } }
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noisy_raw := {}
	var actual : Dictionary = expected.duplicate(true)
	var changed := 0
	for address in cap:
		if not address.begins_with("nodes|") or not (address.ends_with("|rotation") or address.ends_with("|position")):
			continue
		var noisy = _jitter_ulps(cap[address].container, 30, rng)
		var h := FlowNodeIO.snapshot_hash_container(noisy)
		noisy_raw[address] = { "container": noisy, "hash": h }
		if h != cap[address].hash:
			_set_summary_hash(actual, address, h)
			changed += 1
	assert_int(changed).override_failure_message("the jitter changed no exact hash").is_greater(10)
	var provider := func(_key: String, _addresses: Array) -> Dictionary: return noisy_raw
	# Off the baseline platform: PLATFORM_NOISE (unless forced strict).
	var result := GoldenTolerance.compare_entry(COLONNADE_KEY, expected, actual, sidecar, provider)
	if OS.get_environment(GoldenTolerance.ENV_POLICY).to_lower() != "strict":
		assert_array(result.failures).is_empty()
		assert_int(result.noise.size()).is_equal(changed)
	# On the baseline platform: the exact hash is the check.
	if OS.get_environment(GoldenTolerance.ENV_POLICY).is_empty():
		var local := sidecar.duplicate()
		local["platform"] = GoldenTolerance.platform_id()
		result = GoldenTolerance.compare_entry(COLONNADE_KEY, expected, actual, local, provider)
		assert_array(result.failures).is_not_empty()
		assert_array(result.noise).is_empty()
	# A real 0.01 change on top of the noise still fails off-platform, and the
	# message names graph, node and stream.
	var bumped_raw := noisy_raw.duplicate()
	var bumped = _bump(noisy_raw[SAMPLE_ROTATION].container, 10, 1, 0.01)
	bumped_raw[SAMPLE_ROTATION] = { "container": bumped, "hash": FlowNodeIO.snapshot_hash_container(bumped) }
	var bumped_actual : Dictionary = actual.duplicate(true)
	_set_summary_hash(bumped_actual, SAMPLE_ROTATION, bumped_raw[SAMPLE_ROTATION].hash)
	var bumped_provider := func(_key: String, _addresses: Array) -> Dictionary: return bumped_raw
	result = GoldenTolerance.compare_entry(COLONNADE_KEY, expected, bumped_actual, sidecar, bumped_provider)
	assert_array(result.failures).is_not_empty()
	assert_str("\n".join(PackedStringArray(result.failures))).contains("graph=%s node=id_0002_sample bulk=0 port=0 stream=rotation" % COLONNADE_KEY)


## Sets the summary hash an entry records at a node-stream `address`.
static func _set_summary_hash(entry: Dictionary, address: String, h: String) -> void:
	var parts : PackedStringArray = address.split("|")
	if parts[0] != "nodes" or parts[4].begins_with("@attr:"):
		return
	var summary = entry.nodes[parts[1]][int(parts[2])][int(parts[3])]
	for st in summary.streams:
		if st.name == parts[4]:
			st.hash = h


## A difference in an exact-valued stream (integers) is never platform noise.
func test_integer_stream_change_is_not_noise() -> void:
	var expected : Dictionary = _baseline_graphs()[COLONNADE_KEY]
	var actual : Dictionary = expected.duplicate(true)
	for s in actual.nodes["id_0002_sample"][0][0].streams:
		if s.name == "seed":
			s.hash = "0123456789abcdef"
	var cap : Dictionary = _captured(COLONNADE)[COLONNADE_KEY]
	var provider := func(_key: String, _addresses: Array) -> Dictionary: return cap
	var result := GoldenTolerance.compare_entry(COLONNADE_KEY, expected, actual, _foreign(_sidecar()), provider)
	assert_array(result.failures).is_not_empty()
	assert_array(result.noise).is_empty()


static func _foreign(sidecar: Dictionary) -> Dictionary:
	var copy := sidecar.duplicate()
	copy["platform"] = FOREIGN_PLATFORM
	return copy

static func _no_raw(_key: String, _addresses: Array) -> Dictionary:
	return {}
