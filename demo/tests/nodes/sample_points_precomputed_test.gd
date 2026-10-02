# sample_points_precomputed_test.gd
# Pins sample_points after the WP13-P1 performance change (the quasi-random
# 2D sequence computed once per run instead of through a Callable per sample,
# the node seed and point_seed hoisted out of the seed loop) to the original
# implementation kept verbatim in support/sample_points_reference.gd: every
# distribution, phase, groups with an output group id, inherited attributes,
# graph seeds and bounds-carrying inputs must give byte-identical outputs.
class_name SamplePointsPrecomputedTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/sample_points.gd")
const ReferenceScript = preload("res://tests/nodes/support/sample_points_reference.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/sample_points_settings.gd")

const T := FlowDataScript.DataType

static func _anchors(n : int, with_bounds : bool) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var positions := []
	for i in range(n):
		positions.append(Vector3(rng.randf_range(-20, 20), rng.randf_range(0, 3), rng.randf_range(-20, 20)))
	var d = H.points(positions)
	var rot : PackedVector3Array = d.getVector3Container("rotation")
	var siz : PackedVector3Array = d.getVector3Container("size")
	var tag := PackedInt32Array()
	for i in range(n):
		rot[i] = Vector3(rng.randf_range(-20, 20), rng.randf_range(-180, 180), 0)
		siz[i] = Vector3(rng.randf_range(0.5, 4), rng.randf_range(0.5, 2), rng.randf_range(0.5, 4))
		tag.append(i * 7)
	d.registerStream("tag", tag, T.Int)
	if with_bounds:
		var bmin := PackedVector3Array()
		var bmax := PackedVector3Array()
		for i in range(n):
			bmin.append(Vector3(-1.5, -0.25, -0.5))
			bmax.append(Vector3(0.5, 0.75, 2.0))
		d.registerStream("bounds_min", bmin, T.Vector)
		d.registerStream("bounds_max", bmax, T.Vector)
	return d

static func _settings(distribution : int, phase : float, groups : Array, group_id : String, inherit : bool, random_seed : int):
	var s = SettingsScript.new()
	s.distribution = distribution
	s.phase = phase
	s.groups.clear()
	for g in groups:
		s.groups.append(g)
	s.out_group_id = group_id
	s.inherit_attributes = inherit
	s.num_samples = 24
	s.sampling_distance = 0.7
	s.random_seed = random_seed
	return s

func _assert_same(input, settings_args : Array, graph_seed := 0) -> void:
	var expected := H.exec(ReferenceScript, callv("_settings", settings_args), [input], H.make_ctx(null, graph_seed))
	var actual := H.exec(NodeScript, callv("_settings", settings_args), [input], H.make_ctx(null, graph_seed))
	assert_str(actual.err).is_equal(expected.err)
	assert_int(actual.bulks.size()).is_equal(expected.bulks.size())
	for b in range(expected.bulks.size()):
		for p in range(expected.bulks[b].size()):
			assert_bool(R.data_bytes(actual.bulks[b][p]) == R.data_bytes(expected.bulks[b][p])).override_failure_message("%s seed %d differs" % [str(settings_args), graph_seed]).is_true()

func test_every_distribution_matches_the_reference() -> void:
	for with_bounds in [false, true]:
		var input := _anchors(9, with_bounds)
		for distribution in range(4):
			for phase in [0.0, 0.37]:
				_assert_same(input, [distribution, phase, [32], "", false, 5])
				_assert_same(input, [distribution, phase, [5, 0, 11], "grp", true, 77], 1234)

func test_degenerate_groups_and_empty_input_match_the_reference() -> void:
	var input := _anchors(3, false)
	for distribution in [1, 2]:
		_assert_same(input, [distribution, 0.5, [0], "grp", false, 1])
		_assert_same(input, [distribution, 0.5, [-4, 3], "grp", false, 1])
		_assert_same(input, [distribution, 0.5, [], "grp", false, 1])
		_assert_same(FlowDataScript.Data.new(), [distribution, 0.5, [8], "", true, 1])
