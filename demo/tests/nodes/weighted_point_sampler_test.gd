# weighted_point_sampler_test.gd
class_name WeightedPointSamplerTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/weighted_point_sampler.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/weighted_point_sampler_settings.gd")

func _settings(count : int, weight : String = "", replace : bool = false):
	var s = SettingsScript.new()
	s.count = count
	s.weight_attribute = weight
	s.with_replacement = replace
	return s

func _line(count : int, weights = null) -> FlowData.Data:
	var pts := []
	var ids := PackedInt32Array()
	for i in range(count):
		pts.append(Vector3(i, 0, i * 0.5))
		ids.append(i)
	var extra := {"id": ids}
	if weights != null:
		extra["w"] = PackedFloat32Array(weights)
	return H.points(pts, extra)

func _exec(data, settings, seed : int = 0) -> Dictionary:
	return H.exec(NodeScript, settings, [data], H.make_ctx(null, seed))

func _picked(data, settings, seed : int = 0) -> Array:
	var r := _exec(data, settings, seed)
	assert_str(r.err).is_empty()
	return Array(H.port(r, 0).container("id"))

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Weighted Point Sampler"])
	H.dispose(node)

func test_without_replacement_picks_distinct_points() -> void:
	var ids := _picked(_line(10), _settings(4))
	assert_int(ids.size()).is_equal(4)
	var unique := {}
	for i in ids:
		unique[i] = true
	assert_int(unique.size()).is_equal(4)

func test_count_is_capped_and_zero_weights_never_picked() -> void:
	assert_int(_picked(_line(5), _settings(50)).size()).is_equal(5)
	var ids := _picked(_line(5, [0, 0, 2, 1, 0]), _settings(5, "w"))
	ids.sort()
	assert_array(ids).is_equal([2, 3])
	var rep := _picked(_line(5, [0, 0, 2, 1, -4]), _settings(40, "w", true))
	assert_int(rep.size()).is_equal(40)
	for i in rep:
		assert_bool(i == 2 or i == 3).is_true()

func test_all_zero_or_broadcast_weights_are_uniform() -> void:
	assert_int(_picked(_line(6, [0, 0, 0, 0, 0, 0]), _settings(3, "w")).size()).is_equal(3)
	var d = _line(6)
	d.registerStream("bw", PackedFloat32Array([2.0]))
	assert_int(_picked(d, _settings(3, "bw")).size()).is_equal(3)

func test_with_replacement_follows_weights() -> void:
	var ids := _picked(_line(2, [1, 9]), _settings(2000, "w", true))
	var heavy := ids.count(1)
	assert_int(heavy).is_between(1700, 1900)

func test_without_replacement_follows_weights_across_seeds() -> void:
	var heavy_first := 0
	for seed in range(1, 201):
		var ids := _picked(_line(2, [1, 9]), _settings(1, "w"), seed)
		if ids[0] == 1:
			heavy_first += 1
	assert_int(heavy_first).is_between(160, 196)

func test_deterministic_and_reorder_stable() -> void:
	var d = _line(20, range(1, 21))
	for replace in [false, true]:
		var s = _settings(6, "w", replace)
		var a := _picked(d, s, 7)
		assert_array(_picked(d, s, 7)).is_equal(a)
		assert_array(_picked(H.reversed(d), s, 7)).is_equal(a)

func test_graph_seed_changes_the_pick() -> void:
	var d = _line(30)
	var s = _settings(5)
	var differs := false
	for seed in range(1, 6):
		if _picked(d, s, seed) != _picked(d, s, 0):
			differs = true
	assert_bool(differs).is_true()

func test_per_point_seed_stream_is_used() -> void:
	var d = _line(12)
	var seeds := PackedInt32Array()
	for i in range(12):
		seeds.append(1000 + i * 37)
	d.registerStream("seed", seeds)
	var a := _picked(d, _settings(4))
	# Moving points does not change the pick when they carry their own seed.
	var moved = d.duplicate()
	var pos = moved.getVector3Container("position")
	for i in range(pos.size()):
		pos[i] += Vector3(100, 0, 0)
	assert_array(_picked(moved, _settings(4))).is_equal(a)

func test_duplicate_seeds_mutated_and_sample_index() -> void:
	var d = _line(1)
	d.registerStream("seed", PackedInt32Array([42]))
	var s = _settings(3, "", true)
	s.sample_index_attribute = "pick"
	var out = H.port(_exec(d, s), 0)
	assert_int(out.size()).is_equal(3)
	var seeds = out.container("seed")
	assert_int(seeds[0]).is_equal(42)
	assert_int(seeds[1]).is_not_equal(42)
	assert_int(seeds[2]).is_not_equal(seeds[1])
	assert_array(Array(out.container("pick"))).is_equal([0, 1, 2])
	s.mutate_duplicate_seeds = false
	assert_array(Array(H.port(_exec(d, s), 0).container("seed"))).is_equal([42, 42, 42])

func test_not_selected_is_the_complement() -> void:
	var r := _exec(_line(8), _settings(3))
	var picked := Array(H.port(r, 0).container("id"))
	var rest := Array(H.port(r, 1).container("id"))
	assert_int(rest.size()).is_equal(5)
	for i in range(8):
		assert_bool((i in picked) != (i in rest)).is_true()
	# Input order on Not Selected.
	var sorted_rest := rest.duplicate()
	sorted_rest.sort()
	assert_array(rest).is_equal(sorted_rest)

func test_errors_and_empty_input() -> void:
	assert_str(_exec(_line(3), _settings(1, "nope")).err).contains("not found")
	var d = _line(3)
	d.registerStream("name", PackedStringArray(["a", "b", "c"]))
	assert_str(_exec(d, _settings(1, "name")).err).contains("numeric")
	var r := _exec(_line(0), _settings(3, "w"))
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 0).size()).is_equal(0)
	assert_str(_exec(null, _settings(1)).err).contains("not connected")
