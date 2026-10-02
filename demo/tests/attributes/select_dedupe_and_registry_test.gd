# select_dedupe_and_registry_test.gd
# attribute_select, attribute_remove_duplicates, and a registry check that every
# WP4a node template resolves, instantiates and declares valid metadata.
class_name SelectDedupeRegistryTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/attributes/support/node_harness.gd")
const SelectNode = preload("res://addons/flow_nodes_editor/nodes/attribute_select.gd")
const SelectSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_select_settings.gd")
const DedupeNode = preload("res://addons/flow_nodes_editor/nodes/attribute_remove_duplicates.gd")
const DedupeSettings = preload("res://addons/flow_nodes_editor/nodes/attribute_remove_duplicates_settings.gd")

const NEW_TEMPLATES := [
	"attribute_cast", "make_transform_attribute", "break_transform_attribute", "copy_attribute",
	"attribute_string_op", "bitwise_op", "compare_op", "merge_attributes", "gather",
	"vector_op", "transform_op", "trig_op", "attribute_select", "attribute_remove_duplicates",
]

var D = FlowDataScript.DataType

func _pts() -> FlowData.Data:
	return H.data({
		"position": [PackedVector3Array([Vector3(0, 5, 0), Vector3(1, 9, 0), Vector3(2, 1, 0), Vector3(3, 9, 0)]), D.Vector],
		"h": [PackedFloat64Array([5, 9, 1, 9]), D.Double],
		"name": [PackedStringArray(["c", "a", "d", "b"]), D.String],
	})

func _select(op: int, attr: String, configure: Callable = Callable()) -> Dictionary:
	var s = SelectSettings.new()
	s.operation = op
	s.input_attribute = attr
	if configure.is_valid():
		configure.call(s)
	return H.exec(SelectNode, s, [_pts()])

func test_select_min_max_median() -> void:
	var E = SelectSettings.eOperation
	var mx = _select(E.Max, "h")
	assert_str(mx.err).is_empty()
	assert_array(H.values(mx.out, "h")).is_equal([9.0])
	assert_array(H.values(mx.out, "selected_index")).is_equal([1])	# first of the tie
	assert_int(H.dtype(mx.out, "h")).is_equal(D.Double)
	assert_int(mx.out1.size()).is_equal(1)
	assert_array(H.values(mx.out1, "name")).is_equal(["a"])
	assert_array(H.values(_select(E.Min, "h").out, "selected_index")).is_equal([2])
	# sorted keys 1,5,9,9 -> lower middle is 5 (index 0)
	assert_array(H.values(_select(E.Median, "h").out, "selected_index")).is_equal([0])
	assert_array(H.values(_select(E.Min, "name").out, "name")).is_equal(["a"])

func test_select_vectors_by_axis() -> void:
	var E = SelectSettings.eOperation
	var A = SelectSettings.eAxis
	var y = _select(E.Max, "position", func(s): s.axis = A.Y)
	assert_array(H.values(y.out, "position")).is_equal([Vector3(1, 9, 0)])
	var x = _select(E.Max, "position", func(s): s.axis = A.X)
	assert_array(H.values(x.out, "selected_index")).is_equal([3])
	var w = _select(E.Max, "position", func(s): s.axis = A.W)
	assert_str(w.err).contains("can't be selected")

func test_remove_duplicates_keeps_first() -> void:
	var s = DedupeSettings.new()
	s.attribute_names = PackedStringArray(["h"])
	var r = H.exec(DedupeNode, s, [_pts()])
	assert_str(r.err).is_empty()
	assert_array(H.values(r.out, "name")).is_equal(["c", "a", "d"])
	s.attribute_names = PackedStringArray(["h", "name"])
	assert_int(H.exec(DedupeNode, s, [_pts()]).out.size()).is_equal(4)

func test_remove_duplicates_on_transforms() -> void:
	var xf = FlowDataScript.Data.newContainerOfType(D.Transform)
	xf.append(Transform3D.IDENTITY)
	xf.append(Transform3D(Basis.IDENTITY, Vector3.ONE))
	xf.append(Transform3D.IDENTITY)
	var d = H.data({"t": [xf, D.Transform]})
	var s = DedupeSettings.new()
	s.attribute_names = PackedStringArray(["t"])
	assert_int(H.exec(DedupeNode, s, [d]).out.size()).is_equal(2)

func test_every_new_template_resolves_and_has_valid_meta() -> void:
	for template in NEW_TEMPLATES:
		var path := FlowNodeRegistry.get_node_script_path(template)
		assert_str(path).override_failure_message("template %s" % template).is_not_empty()
		var script = load(path)
		assert_object(script).is_not_null()
		var node = script.new()
		var meta : Dictionary = node.meta_node
		assert_str(meta.get("title", "")).is_not_empty()
		assert_bool(meta.has("settings") and meta.settings != null).override_failure_message(template).is_true()
		assert_bool(meta.get("ins", []).size() >= 1).is_true()
		assert_bool(meta.get("outs", []).size() >= 1).is_true()
		assert_str(meta.get("category", "")).is_not_empty()
		assert_bool(meta.get("aliases", []).size() >= 1).is_true()
		var settings = meta.settings.new()
		assert_bool(settings is NodeSettings).is_true()
		node.settings = settings
		assert_that(node.getTitle()).is_not_null()	# must not crash
		H.dispose(node)
