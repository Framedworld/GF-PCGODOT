# attribute_string_op_test.gd
class_name AttributeStringOpNodeTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const StringNode = preload("res://addons/flow_nodes_editor/nodes/attribute_string_op.gd")
const StringSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_string_op_settings.gd")

var D = FlowDataScript.DataType
var E = StringSettings.eOperation

func _data() -> FlowData.Data:
	return H.data({
		"name": [PackedStringArray(["Oak_Tree", "pine tree", "Rock"]), D.String],
		"suffix": [PackedStringArray(["_a", "_b", "_c"]), D.String],
		"n": [PackedInt64Array([1, 2, 1 << 40]), D.Int64],
	})

func _run(op: int, configure: Callable = Callable()) -> Dictionary:
	var s = StringSettings.new()
	s.operation = op
	s.in_nameA = "name"
	s.out_name = "r"
	if configure.is_valid():
		configure.call(s)
	return H.exec(StringNode, s, [_data()])

func test_append_prepend_with_attribute_and_constant() -> void:
	assert_array(H.values(_run(E.Append, func(s): s.in_nameB = "suffix").out, "r")).is_equal(["Oak_Tree_a", "pine tree_b", "Rock_c"])
	assert_array(H.values(_run(E.Prepend, func(s): s.constant_b = "x:").out, "r")).is_equal(["x:Oak_Tree", "x:pine tree", "x:Rock"])

func test_replace_case_modes() -> void:
	var cs = _run(E.Replace, func(s): s.constant_b = "tree"; s.constant_c = "T")
	assert_array(H.values(cs.out, "r")).is_equal(["Oak_Tree", "pine T", "Rock"])
	var ci = _run(E.Replace, func(s): s.constant_b = "tree"; s.constant_c = "T"; s.case_sensitive = false)
	assert_array(H.values(ci.out, "r")).is_equal(["Oak_T", "pine T", "Rock"])

func test_upper_lower_trim_length() -> void:
	assert_array(H.values(_run(E.ToUpper).out, "r")).is_equal(["OAK_TREE", "PINE TREE", "ROCK"])
	assert_array(H.values(_run(E.ToLower).out, "r")).is_equal(["oak_tree", "pine tree", "rock"])
	var l = _run(E.Length)
	assert_int(H.dtype(l.out, "r")).is_equal(D.Int)
	assert_array(H.values(l.out, "r")).is_equal([8, 9, 4])

func test_predicates_write_bools() -> void:
	var c = _run(E.Contains, func(s): s.constant_b = "tree")
	assert_int(H.dtype(c.out, "r")).is_equal(D.Bool)
	assert_array(H.values(c.out, "r")).is_equal([0, 1, 0])
	assert_array(H.values(_run(E.Contains, func(s): s.constant_b = "TREE"; s.case_sensitive = false).out, "r")).is_equal([1, 1, 0])
	assert_array(H.values(_run(E.StartsWith, func(s): s.constant_b = "Oak").out, "r")).is_equal([1, 0, 0])
	assert_array(H.values(_run(E.EndsWith, func(s): s.constant_b = "ck").out, "r")).is_equal([0, 0, 1])

func test_format_with_operands_index_and_attributes() -> void:
	var f = _run(E.Format, func(s): s.in_nameB = "suffix"; s.constant_c = "!"; s.format_pattern = "{index}:{0}{1}{2}#{n}")
	assert_str(f.err).is_empty()
	assert_array(H.values(f.out, "r")).is_equal(["0:Oak_Tree_a!#1", "1:pine tree_b!#2", "2:Rock_c!#%d" % (1 << 40)])
	var bad = _run(E.Format, func(s): s.format_pattern = "{missing}")
	assert_str(bad.err).contains("missing")

func test_substring_and_non_string_input() -> void:
	assert_array(H.values(_run(E.Substring, func(s): s.constant_b = "1"; s.constant_c = "3").out, "r")).is_equal(["ak_", "ine", "ock"])
	assert_array(H.values(_run(E.Substring, func(s): s.constant_b = "4").out, "r")).is_equal(["Tree", " tree", ""])
	assert_str(_run(E.Substring, func(s): s.constant_b = "x").err).contains("integer")
	var nums = _run(E.Append, func(s): s.in_nameA = "n"; s.constant_b = "px")
	assert_array(H.values(nums.out, "r")).is_equal(["1px", "2px", "%dpx" % (1 << 40)])

func test_source_output_overwrites_input() -> void:
	var r = _run(E.ToUpper, func(s): s.out_name = "@Source")
	assert_array(H.values(r.out, "name")).is_equal(["OAK_TREE", "PINE TREE", "ROCK"])
