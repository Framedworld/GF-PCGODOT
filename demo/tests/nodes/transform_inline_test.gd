# transform_inline_test.gd
# Pins transform / transform_points after the WP13-P1 performance rewrite
# (loop invariants hoisted, seed and rotation helpers inlined) to the original
# implementation kept verbatim in support/transform_reference.gd: per-point
# seeds, broadcast seeds, position-hash seeds, local and world rotation,
# uniform and per-axis scale must give byte-identical outputs.
class_name TransformInlineTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/transform.gd")
const PointsNodeScript = preload("res://addons/flow_nodes_editor/nodes/transform_points.gd")
const ReferenceScript = preload("res://tests/nodes/support/transform_reference.gd")

const T := FlowDataScript.DataType

static func _make_input(n : int, seeds : String) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var positions := []
	for i in range(n):
		positions.append(Vector3(rng.randf_range(-50, 50), rng.randf_range(-1, 1), rng.randf_range(-50, 50)))
	var d = H.points(positions)
	var rot : PackedVector3Array = d.getVector3Container("rotation")
	var siz : PackedVector3Array = d.getVector3Container("size")
	for i in range(n):
		rot[i] = Vector3(rng.randf_range(-45, 45), rng.randf_range(-180, 180), rng.randf_range(-45, 45))
		siz[i] = Vector3.ONE * rng.randf_range(0.5, 2.0)
	match seeds:
		"per_point":
			var s := PackedInt32Array()
			for i in range(n):
				s.append(rng.randi() & 0x7fffffff)
			d.registerStream("seed", s, T.Int)
		"broadcast":
			d.registerStream("seed", PackedInt32Array([12345]), T.Int)
		"wrong_length":
			d.streams["seed"] = { "container": PackedInt32Array([1, 2]), "name": "seed", "data_type": T.Int }
	return d

static func _settings(local_rot : bool, uniform : bool, random_seed : int):
	var s = TransformNodeSettings.new()
	s.offset_min = Vector3(-1.5, -0.25, -1.5)
	s.offset_max = Vector3(1.5, 0.75, 1.5)
	s.rotation_min = Vector3(-10, -90, -5)
	s.rotation_max = Vector3(10, 90, 5)
	s.rotation_local_space = local_rot
	s.scale_min = Vector3(0.5, 0.75, 0.9)
	s.scale_max = Vector3(1.5, 1.25, 3.0)
	s.uniform_scale = uniform
	s.random_seed = random_seed
	return s

func test_every_mode_matches_the_reference() -> void:
	var checked := 0
	for seeds in ["none", "per_point", "broadcast", "wrong_length"]:
		for n in [1, 2, 37]:
			var input := _make_input(n, seeds)
			for local_rot in [false, true]:
				for uniform in [false, true]:
					for script in [NodeScript, PointsNodeScript]:
						var expected := R.exec_logged(ReferenceScript, _settings(local_rot, uniform, 4242), [input])
						var actual := R.exec_logged(script, _settings(local_rot, uniform, 4242), [input])
						assert_array(actual).override_failure_message("%s n=%d local=%s uniform=%s differs" % [seeds, n, local_rot, uniform]).is_equal(expected)
						checked += 1
	assert_int(checked).is_equal(4 * 3 * 2 * 2 * 2)

func test_graph_seed_and_missing_streams_match_the_reference() -> void:
	var input := _make_input(20, "none")
	var ctx = H.make_ctx(null, 987)
	var expected := H.exec(ReferenceScript, _settings(true, false, 3), [input], ctx)
	var actual := H.exec(NodeScript, _settings(true, false, 3), [input], H.make_ctx(null, 987))
	assert_bool(R.data_bytes(H.port(actual)) == R.data_bytes(H.port(expected))).is_true()
	var no_rotation := FlowDataScript.Data.new()
	no_rotation.registerStream("position", PackedVector3Array([Vector3.ONE]), T.Vector)
	assert_array(R.exec_logged(NodeScript, _settings(false, true, 1), [no_rotation])).is_equal(R.exec_logged(ReferenceScript, _settings(false, true, 1), [no_rotation]))
