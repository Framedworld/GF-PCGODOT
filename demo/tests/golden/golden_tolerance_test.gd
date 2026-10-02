# golden_tolerance_test.gd
# The cross-platform tolerance layer of the golden harness
# (golden_tolerance.gd, baseline_tolerance.json): simulated last-bit float noise
# like another platform's libm produces must pass as PLATFORM_NOISE, and real
# changes (0.01 in any component, point count, stream set) must still fail.
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


# --- the problem is real ----------------------------------------------------------

## One-ulp-scale relative noise (1e-7) on the colonnade's sampled rotations
## changes the exact quantized hash in most trials: this is why a plain
## quantized hash is not portable across platforms.
func test_ulp_noise_flips_the_exact_hash_but_not_the_tolerance_check() -> void:
	var fp : Dictionary = _sidecar().graphs[COLONNADE_KEY][SAMPLE_ROTATION]
	var original = _captured(COLONNADE)[COLONNADE_KEY][SAMPLE_ROTATION].container
	assert_str(FlowNodeIO.snapshot_hash_container(original)).is_equal(fp.e)
	assert_str(GoldenTolerance.check(original, true, fp)).is_empty()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var flipped := 0
	var trials := 200
	var failures := []
	for t in range(trials):
		var noisy = _jitter_relative(original, 1e-7, rng)
		if FlowNodeIO.snapshot_hash_container(noisy) != fp.e:
			flipped += 1
		var verdict := GoldenTolerance.check(noisy, true, fp)
		if not verdict.is_empty():
			failures.append("trial %d: %s" % [t, verdict])
	assert_int(flipped).override_failure_message("1e-7 jitter flipped the exact hash in only %d/%d trials" % [flipped, trials]).is_greater(trials / 2)
	assert_array(failures).is_empty()


## Up to 4 float32 ulps on every component of every float stream of the two
## graphs a Windows run reported (colonnade, sample_points) stays within the
## noise budget.
func test_ulp_jitter_on_every_reported_stream_is_tolerated() -> void:
	var sidecar := _sidecar()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var failures := []
	var checked := 0
	for path in [COLONNADE, SAMPLE_POINTS]:
		var cap : Dictionary = _captured(path)
		for key in cap:
			for address in cap[key]:
				var fp = sidecar.graphs.get(key, {}).get(address, null)
				if not (fp is Dictionary):
					continue
				for trial in range(3):
					var noisy = _jitter_ulps(cap[key][address].container, 4, rng)
					var verdict := GoldenTolerance.check(noisy, GoldenTolerance.is_angle_address(address), fp)
					checked += 1
					if not verdict.is_empty():
						failures.append("%s: %s" % [GoldenTolerance.describe_address(key, address), verdict])
	assert_int(checked).is_greater(50)
	assert_array(failures).is_empty()


# --- real changes still fail ---------------------------------------------------------

## A 0.01 change in any component of any element fails: every masked element
## (the ones near a bucket boundary), every near-gimbal rotation and a spread
## of the others, both signs. The rubble rotations are random, so they include
## near-gimbal elements (pitch close to +-90).
func test_a_0_01_change_in_any_component_fails() -> void:
	var sidecar := _sidecar()
	var cap : Dictionary = _captured(COLONNADE)[COLONNADE_KEY]
	var missed := []
	var tried := 0
	var gimbal_tried := 0
	var unrepresentable := []
	for address in [SAMPLE_ROTATION, "nodes|id_0008_trans_rubble|0|0|rotation", "nodes|id_0008_trans_rubble|0|0|position", "nodes|id_0008_trans_rubble|0|0|size", "nodes|id_0024_random_color|0|0|color"]:
		var fp : Dictionary = sidecar.graphs[COLONNADE_KEY][address]
		var container = cap[address].container
		var comps := int(fp.c)
		var angle := GoldenTolerance.is_angle_address(address)
		var flat := []
		var m : Array = fp.m
		for j in range(0, m.size() - 1, 2):
			flat.append(int(m[j]))
		var g : Array = fp.get("g", [])
		for j in range(0, g.size() - 3, 4):
			# Below |cos(pitch)| ~0.0014 (pitch within 0.08 degrees of +-90) a
			# float32 Euler triple cannot represent a rotation to 0.01 degrees;
			# such elements are listed, not silently skipped.
			var c := absf(cos(deg_to_rad(float(g[j + 1]))))
			if GoldenTolerance.gimbal_tolerance_deg(float(fp.d), c) >= 0.0095:
				unrepresentable.append("%s element %d pitch %s" % [address, int(g[j]), g[j + 1]])
				continue
			gimbal_tried += 1
			for k in range(3):
				flat.append(int(g[j]) * 3 + k)
		for i in range(0, container.size() * comps, 37):
			flat.append(i)
		for i in flat:
			for delta in [0.01, -0.01]:
				tried += 1
				var changed = _bump(container, i / comps, i % comps, delta)
				if GoldenTolerance.check(changed, angle, fp).is_empty():
					missed.append("%s element %d comp %d delta %s" % [address, i / comps, i % comps, delta])
	assert_int(tried).is_greater(200)
	assert_int(gimbal_tried).override_failure_message("no near-gimbal rotation exercised").is_greater(10)
	assert_array(unrepresentable).is_empty()
	assert_array(missed).is_empty()


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

## A simulated other-platform run of the colonnade (every rotation stream with
## 1e-7 relative jitter, its hash recomputed) passes as PLATFORM_NOISE when the
## baseline came from another platform, fails on the baseline's own platform,
## and a 0.01 change fails everywhere.
func test_simulated_platform_noise_end_to_end() -> void:
	var expected : Dictionary = _baseline_graphs()[COLONNADE_KEY]
	var cap : Dictionary = _captured(COLONNADE)[COLONNADE_KEY]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var noisy_raw := {}
	var actual : Dictionary = expected.duplicate(true)
	var changed := 0
	for address in cap:
		if not address.ends_with("|rotation") or not address.begins_with("nodes|"):
			continue
		var noisy = _jitter_relative(cap[address].container, 1e-7, rng)
		var h := FlowNodeIO.snapshot_hash_container(noisy)
		noisy_raw[address] = { "container": noisy, "hash": h }
		var parts : PackedStringArray = address.split("|")
		for s in actual.nodes[parts[1]][int(parts[2])][int(parts[3])].streams:
			if s.name == "rotation" and s.hash != h:
				s.hash = h
				changed += 1
	assert_int(changed).override_failure_message("the jitter changed no exact hash").is_greater(0)
	var provider := func(_key: String, _addresses: Array) -> Dictionary: return noisy_raw
	var sidecar := _sidecar()
	# Off the baseline platform: PLATFORM_NOISE (unless forced strict).
	var result := GoldenTolerance.compare_entry(COLONNADE_KEY, expected, actual, _foreign(sidecar), provider)
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
	for s in bumped_actual.nodes["id_0002_sample"][0][0].streams:
		if s.name == "rotation":
			s.hash = bumped_raw[SAMPLE_ROTATION].hash
	var bumped_provider := func(_key: String, _addresses: Array) -> Dictionary: return bumped_raw
	result = GoldenTolerance.compare_entry(COLONNADE_KEY, expected, bumped_actual, _foreign(sidecar), bumped_provider)
	assert_array(result.failures).is_not_empty()
	assert_str(str(result.failures[0])).contains("graph=%s node=id_0002_sample" % COLONNADE_KEY)
	assert_str(str(result.failures[0])).contains("stream=rotation")


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
