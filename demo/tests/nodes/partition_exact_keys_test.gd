# partition_exact_keys_test.gd
# Pins partition after the WP13-P1 performance change (Int, Int64, Bool and
# String attributes grouped by their value instead of a formatted string per
# point) to the original implementation kept verbatim in
# support/partition_reference.gd: groups, their order, the per-data attribute
# and the partition id stream must be byte-identical for every attribute type,
# including floats (still grouped by their string form) and tracing.
class_name PartitionExactKeysTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const R = preload("res://tests/nodes/support/reference_compare.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/partition.gd")
const ReferenceScript = preload("res://tests/nodes/support/partition_reference.gd")

const T := FlowDataScript.DataType

static func _make_input(n : int) -> FlowData.Data:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var positions := []
	for i in range(n):
		positions.append(Vector3(i, 0, -i))
	var d = H.points(positions)
	var ints := PackedInt32Array(); var big := PackedInt64Array(); var flags := PackedByteArray()
	var names := PackedStringArray(); var floats := PackedFloat32Array(); var vecs := PackedVector3Array()
	for i in range(n):
		ints.append(rng.randi_range(-3, 3))
		big.append((1 << 40) + rng.randi_range(0, 4))
		flags.append(rng.randi_range(0, 1))
		names.append(["a", "b", "", "a ", "A"][rng.randi_range(0, 4)])
		floats.append([0.1, 0.10000001, 1.0, -0.0, 0.0][rng.randi_range(0, 4)])
		vecs.append(Vector3(rng.randi_range(0, 1), 0, 0))
	d.registerStream("i", ints, T.Int)
	d.registerStream("l", big, T.Int64)
	d.registerStream("b", flags, T.Bool)
	d.registerStream("s", names, T.String)
	d.registerStream("f", floats, T.Float)
	d.registerStream("v", vecs, T.Vector)
	return d

static func _settings(attribute : String, out_attribute : String, trace := false):
	var s = PartitionNodeSettings.new()
	s.attribute_name = attribute
	s.out_partition_attribute = out_attribute
	s.trace = trace
	return s

func test_every_attribute_type_matches_the_reference() -> void:
	var input := _make_input(80)
	for attribute in ["i", "l", "b", "s", "f", "v", "position.x", "missing"]:
		for out_attribute in ["", "pid"]:
			var expected := R.exec_logged(ReferenceScript, _settings(attribute, out_attribute), [input])
			var actual := R.exec_logged(NodeScript, _settings(attribute, out_attribute), [input])
			assert_array(actual).override_failure_message("%s/%s differs" % [attribute, out_attribute]).is_equal(expected)

func test_tracing_and_tiny_inputs_match_the_reference() -> void:
	for n in [0, 1, 2]:
		var input := _make_input(n)
		assert_array(R.exec_logged(NodeScript, _settings("i", "pid"), [input])).is_equal(R.exec_logged(ReferenceScript, _settings("i", "pid"), [input]))
	var traced := _make_input(5)
	assert_array(R.exec_logged(NodeScript, _settings("s", "", true), [traced])).is_equal(R.exec_logged(ReferenceScript, _settings("s", "", true), [traced]))
