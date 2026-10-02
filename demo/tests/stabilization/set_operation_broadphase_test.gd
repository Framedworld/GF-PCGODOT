# WP11 item 4: the native RTree broadphase of difference / intersection / union
# (and self_pruning) must use the same boxes as a brute-force AABB overlap,
# for points with bounds_min/bounds_max streams and for points with plain size.
class_name SetOperationBroadphaseTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const Difference = preload("res://addons/flow_nodes_editor/nodes/difference.gd")
const Intersection = preload("res://addons/flow_nodes_editor/nodes/intersection.gd")
const Union = preload("res://addons/flow_nodes_editor/nodes/union.gd")
const DifferenceSettings = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")
const SelfPruning = preload("res://addons/flow_nodes_editor/nodes/self_pruning.gd")
const SelfPruningSettings = preload("res://addons/flow_nodes_editor/nodes/self_pruning_settings.gd")

const N := 60
const EXTENT := 12.0

## Random points with a unique `pid`. With `with_bounds`, every point carries
## asymmetric bounds_min / bounds_max (as surface_sampler output does) and a
## size stream that the bounds must win over; otherwise only a random size.
func _random_points(rng : RandomNumberGenerator, n : int, id_base : int, with_bounds : bool):
	var positions := []
	for i in range(n):
		positions.append(Vector3(rng.randf_range(-EXTENT, EXTENT), rng.randf_range(-1.0, 1.0), rng.randf_range(-EXTENT, EXTENT)))
	var d = H.points(positions)
	var sizes : PackedVector3Array = d.getVector3Container("size")
	var ids := PackedInt32Array()
	var bmin := PackedVector3Array()
	var bmax := PackedVector3Array()
	for i in range(n):
		ids.append(id_base + i)
		if with_bounds:
			# A size that disagrees with the bounds, so using it would be visible.
			sizes[i] = Vector3(0.2, 0.2, 0.2)
			var lo := Vector3(rng.randf_range(0.2, 2.5), rng.randf_range(0.2, 2.5), rng.randf_range(0.2, 2.5))
			var hi := Vector3(rng.randf_range(0.2, 2.5), rng.randf_range(0.2, 2.5), rng.randf_range(0.2, 2.5))
			bmin.append(-lo)
			bmax.append(hi)
		else:
			sizes[i] = Vector3(rng.randf_range(0.4, 4.0), rng.randf_range(0.4, 4.0), rng.randf_range(0.4, 4.0))
	d.registerStream("pid", ids, FlowDataScript.DataType.Int)
	if with_bounds:
		d.registerStream("bounds_min", bmin, FlowDataScript.DataType.Vector)
		d.registerStream("bounds_max", bmax, FlowDataScript.DataType.Vector)
	return d

## World boxes computed independently of the node code.
func _boxes(d) -> Array:
	var pos : PackedVector3Array = d.getVector3Container("position")
	var out := []
	var bounds : bool = d.hasStream("bounds_min") and d.hasStream("bounds_max")
	for i in range(pos.size()):
		if bounds:
			out.append([pos[i] + d.value_at("bounds_min", i), pos[i] + d.value_at("bounds_max", i)])
		else:
			var h : Vector3 = d.value_at("size", i).abs() * 0.5
			out.append([pos[i] - h, pos[i] + h])
	return out

static func _overlap(a : Array, b : Array) -> bool:
	for axis in range(3):
		if a[0][axis] > b[1][axis] or b[0][axis] > a[1][axis]:
			return false
	return true

## Indices of `a` that overlap at least one box of `b`.
func _overlapping(a_boxes : Array, b_boxes : Array) -> Array:
	var out := []
	for i in range(a_boxes.size()):
		for j in range(b_boxes.size()):
			if _overlap(a_boxes[i], b_boxes[j]):
				out.append(i)
				break
	return out

func _ids(d) -> Array:
	var out := []
	if d == null:
		return out
	for i in range(d.size()):
		out.append(int(d.value_at("pid", i)))
	out.sort()
	return out

func _ids_of(d, indices : Array) -> Array:
	var out := []
	for i in indices:
		out.append(int(d.value_at("pid", i)))
	return out

func _complement(n : int, indices : Array) -> Array:
	var out := []
	for i in range(n):
		if not indices.has(i):
			out.append(i)
	return out

func _sorted(a : Array) -> Array:
	var c := a.duplicate()
	c.sort()
	return c

## The four input pairings: bounds/bounds, bounds/size, size/bounds, size/size.
func _pairs(seed_value : int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	for flags in [[true, true], [true, false], [false, true], [false, false]]:
		out.append([_random_points(rng, N, 0, flags[0]), _random_points(rng, N, 1000, flags[1]), "%s/%s" % [ "bounds" if flags[0] else "size", "bounds" if flags[1] else "size" ]])
	return out

func _run(script, a, b, op := -1):
	var s = DifferenceSettings.new()
	if op >= 0:
		s.operation = op
	var r := H.exec(script, s, [a, b])
	assert_str(r.err).is_empty()
	return H.port(r, 0)

func test_difference_matches_brute_force() -> void:
	for seed_value in [1, 7, 1234]:
		for pair in _pairs(seed_value):
			var a = pair[0]
			var b = pair[1]
			var a_hit := _overlapping(_boxes(a), _boxes(b))
			var b_hit := _overlapping(_boxes(b), _boxes(a))
			# Make sure the random set exercises both outcomes.
			assert_int(a_hit.size()).override_failure_message("%s: no overlap" % pair[2]).is_greater(0)
			assert_int(a_hit.size()).override_failure_message("%s: all overlap" % pair[2]).is_less(N)
			var a_minus_b = _run(Difference, a, b, DifferenceSettings.eOperation.A_Minus_B)
			assert_array(_ids(a_minus_b)).override_failure_message("A-B %s seed %d" % [pair[2], seed_value]) \
				.is_equal(_sorted(_ids_of(a, _complement(N, a_hit))))
			var b_minus_a = _run(Difference, a, b, DifferenceSettings.eOperation.B_Minus_A)
			assert_array(_ids(b_minus_a)).override_failure_message("B-A %s seed %d" % [pair[2], seed_value]) \
				.is_equal(_sorted(_ids_of(b, _complement(N, b_hit))))

func test_intersection_matches_brute_force() -> void:
	for seed_value in [2, 99]:
		for pair in _pairs(seed_value):
			var a = pair[0]
			var b = pair[1]
			var a_hit := _overlapping(_boxes(a), _boxes(b))
			assert_array(_ids(_run(Intersection, a, b))).override_failure_message("intersection %s" % pair[2]) \
				.is_equal(_sorted(_ids_of(a, a_hit)))
			# The Intersection operation of difference itself goes through the same path.
			assert_array(_ids(_run(Difference, a, b, DifferenceSettings.eOperation.Intersection))).is_equal(_sorted(_ids_of(a, a_hit)))

func test_union_matches_brute_force() -> void:
	for seed_value in [3, 42]:
		for pair in _pairs(seed_value):
			var a = pair[0]
			var b = pair[1]
			var b_hit := _overlapping(_boxes(b), _boxes(a))
			# Defaults keep A on overlap: all of A plus the B points touching no A box.
			var expected := _ids_of(a, range(N)) + _ids_of(b, _complement(N, b_hit))
			assert_array(_ids(_run(Union, a, b))).override_failure_message("union %s" % pair[2]) \
				.is_equal(_sorted(expected))

## Greedy self-pruning reference (input order, keep the first of an
## overlapping pair), the native self_prune contract.
func _self_prune_reference(d) -> Array:
	var boxes := _boxes(d)
	var kept := []
	for i in range(boxes.size()):
		var free := true
		for k in kept:
			if _overlap(boxes[i], boxes[k]):
				free = false
				break
		if free:
			kept.append(i)
	return kept

func test_self_pruning_matches_brute_force() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for with_bounds in [true, false]:
		var d = _random_points(rng, N, 0, with_bounds)
		var s = SelfPruningSettings.new()
		var r := H.exec(SelfPruning, s, [d])
		assert_str(r.err).is_empty()
		var kept := _self_prune_reference(d)
		assert_int(kept.size()).is_less(N)
		assert_array(_ids(H.port(r, 0))).override_failure_message("self_pruning bounds=%s" % with_bounds) \
			.is_equal(_sorted(_ids_of(d, kept)))
