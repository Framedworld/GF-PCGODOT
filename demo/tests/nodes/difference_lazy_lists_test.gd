# difference_lazy_lists_test.gd
# Pins difference after the WP13-P1 performance change (only the overlap
# index lists an operation reads are queried; already ordered native results
# skip the sanitizing pass) to the original implementation kept verbatim in
# support/difference_reference.gd: every operation, density function,
# overlap source and union flag, with and without bounds streams, must give
# byte-identical outputs and the same logged messages.
class_name DifferenceLazyListsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/difference.gd")
const ReferenceScript = preload("res://tests/nodes/support/difference_reference.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/difference_settings.gd")

const T := FlowDataScript.DataType

static func _cloud(n : int, seed_value : int, with_bounds : bool, extra : String) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var positions := []
	for i in range(n):
		positions.append(Vector3(rng.randf_range(0, 20), rng.randf_range(0, 1), rng.randf_range(0, 20)))
	var d = H.points(positions)
	var siz : PackedVector3Array = d.getVector3Container("size")
	var dens := PackedFloat32Array()
	var marks := PackedInt32Array()
	for i in range(n):
		siz[i] = Vector3.ONE * rng.randf_range(0.2, 2.5)
		dens.append(rng.randf())
		marks.append(i)
	d.registerStream("density", dens, T.Float)
	d.registerStream(extra, marks, T.Int)
	if with_bounds:
		var bmin := PackedVector3Array()
		var bmax := PackedVector3Array()
		for i in range(n):
			bmin.append(Vector3(-rng.randf_range(0.1, 1), -0.5, -rng.randf_range(0.1, 1)))
			bmax.append(Vector3(rng.randf_range(0.1, 1), 0.5, rng.randf_range(0.1, 1)))
		d.registerStream("bounds_min", bmin, T.Vector)
		d.registerStream("bounds_max", bmax, T.Vector)
		var steep := PackedFloat32Array()
		for i in range(n):
			steep.append(rng.randf())
		d.registerStream("steepness", steep, T.Float)
	return d

static func _settings(op : int, density_function : int, inter_src : int, union_src : int, keep_a : bool):
	var s = SettingsScript.new()
	s.operation = op
	s.density_function = density_function
	s.intersection_overlap_source = inter_src
	s.union_overlap_source = union_src
	s.keep_a_on_union_overlap = keep_a
	return s

func test_every_operation_and_source_matches_the_reference() -> void:
	var checked := 0
	for with_bounds in [false, true]:
		var a := _cloud(60, 1, with_bounds, "a_id")
		var b := _cloud(25, 2, with_bounds, "b_id")
		for op in range(5):
			for density_function in range(4):
				for src in range(4):
					for keep_a in [true, false]:
						var expected := R.exec_logged(ReferenceScript, _settings(op, density_function, src, src, keep_a), [a, b])
						var actual := R.exec_logged(NodeScript, _settings(op, density_function, src, src, keep_a), [a, b])
						assert_array(actual).override_failure_message("bounds=%s op=%d df=%d src=%d keep_a=%s differs" % [with_bounds, op, density_function, src, keep_a]).is_equal(expected)
						checked += 1
	assert_int(checked).is_equal(2 * 5 * 4 * 4 * 2)

func test_empty_and_degenerate_inputs_match_the_reference() -> void:
	var a := _cloud(10, 3, false, "a_id")
	var empty := FlowDataScript.Data.new()
	var no_size := FlowDataScript.Data.new()
	no_size.registerStream("position", PackedVector3Array([Vector3.ZERO, Vector3.ONE]), T.Vector)
	var bad_size := _cloud(4, 4, false, "x")
	bad_size.streams["size"] = { "container": PackedVector3Array([Vector3.ONE, Vector3.ONE]), "name": "size", "data_type": T.Vector }
	for op in range(5):
		for pair in [[a, empty], [empty, a], [empty, empty], [a, no_size], [no_size, a], [a, bad_size], [a, a]]:
			var expected := R.exec_logged(ReferenceScript, _settings(op, 0, 1, 0, true), pair)
			var actual := R.exec_logged(NodeScript, _settings(op, 0, 1, 0, true), pair)
			assert_array(actual).is_equal(expected)
