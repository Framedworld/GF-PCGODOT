# runtime_quality_test.gd
# Runtime Quality Branch and Runtime Quality Select.
class_name RuntimeQualityTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const BranchScript = preload("res://addons/flow_nodes_editor/nodes/runtime_quality_branch.gd")
const BranchSettings = preload("res://addons/flow_nodes_editor/nodes/runtime_quality_branch_settings.gd")
const SelectScript = preload("res://addons/flow_nodes_editor/nodes/runtime_quality_select.gd")
const SelectSettings = preload("res://addons/flow_nodes_editor/nodes/runtime_quality_select_settings.gd")

const SETTING := "flow_nodes/quality_level"

var _saved_setting = null

func before_test() -> void:
	BranchScript.ensure_project_setting()
	_saved_setting = ProjectSettings.get_setting(SETTING)

func after_test() -> void:
	ProjectSettings.set_setting(SETTING, _saved_setting)

func _branch_settings(pins : Array = [true, true, true, true, true]):
	var s = BranchSettings.new()
	s.use_low_pin = pins[0]
	s.use_medium_pin = pins[1]
	s.use_high_pin = pins[2]
	s.use_epic_pin = pins[3]
	s.use_cinematic_pin = pins[4]
	return s

func _select_settings(pins : Array = [true, true, true, true, true]):
	var s = SelectSettings.new()
	s.use_low_pin = pins[0]
	s.use_medium_pin = pins[1]
	s.use_high_pin = pins[2]
	s.use_epic_pin = pins[3]
	s.use_cinematic_pin = pins[4]
	return s

## Index of the branch output pin holding the input's points.
func _branch_pin(settings, params : Dictionary) -> int:
	var data = H.points([Vector3.ZERO, Vector3.ONE])
	var r := H.exec(BranchScript, settings, [data], H.make_ctx(null, 0, params))
	assert_str(r.err).is_empty()
	var hit := -1
	for p in range(6):
		var d = H.port(r, p)
		assert_object(d).is_not_null()
		if d.size() == 2:
			assert_int(hit).is_equal(-1)
			hit = p
		else:
			# Unselected pins carry the schema with zero rows.
			assert_bool(d.hasStream("position")).is_true()
	return hit

func _tagged(label : String) -> FlowData.Data:
	var d = H.points([Vector3.ZERO])
	d.tags = PackedStringArray([label])
	return d

func _select_tag(settings, params : Dictionary, inputs : Array = []) -> String:
	if inputs.is_empty():
		inputs = [_tagged("default"), _tagged("low"), _tagged("medium"), _tagged("high"), _tagged("epic"), _tagged("cinematic")]
	var r := H.exec(SelectScript, settings, inputs, H.make_ctx(null, 0, params))
	var out = H.port(r, 0)
	return out.tags[0] if out != null and out.tags.size() > 0 else ""

func test_meta() -> void:
	var b = BranchScript.new()
	assert_array(b.meta_node.aliases).contains(["Runtime Quality Branch"])
	assert_int(b.meta_node.outs.size()).is_equal(6)
	H.dispose(b)
	var s = SelectScript.new()
	assert_array(s.meta_node.aliases).contains(["Runtime Quality Select"])
	assert_int(s.meta_node.ins.size()).is_equal(6)
	H.dispose(s)

func test_project_setting_is_registered_with_enum_hint() -> void:
	assert_bool(ProjectSettings.has_setting(SETTING)).is_true()
	var info := {}
	for prop in ProjectSettings.get_property_list():
		if prop.name == SETTING:
			info = prop
	assert_int(info.get("hint", -1)).is_equal(PROPERTY_HINT_ENUM)
	assert_str(info.get("hint_string", "")).is_equal("Low,Medium,High,Epic,Cinematic")
	assert_int(ProjectSettings.property_get_revert(SETTING)).is_equal(0)

func test_parse_level() -> void:
	assert_int(BranchScript.parse_level(2)).is_equal(2)
	assert_int(BranchScript.parse_level(9)).is_equal(4)
	assert_int(BranchScript.parse_level(-3)).is_equal(0)
	assert_int(BranchScript.parse_level(2.6)).is_equal(3)
	assert_int(BranchScript.parse_level("epic")).is_equal(3)
	assert_int(BranchScript.parse_level(" 1 ")).is_equal(1)
	assert_int(BranchScript.parse_level("ultra")).is_equal(-1)
	assert_int(BranchScript.parse_level(FlowDataScript.Data.scalar("quality", 4))).is_equal(4)

func test_branch_routes_by_runtime_param() -> void:
	ProjectSettings.set_setting(SETTING, 0)
	for level in range(5):
		assert_int(_branch_pin(_branch_settings(), {"quality": level})).is_equal(level + 1)
	assert_int(_branch_pin(_branch_settings(), {"quality": "High"})).is_equal(3)

func test_branch_disabled_pin_goes_to_default() -> void:
	assert_int(_branch_pin(_branch_settings([true, true, false, true, true]), {"quality": 2})).is_equal(0)
	assert_int(_branch_pin(BranchSettings.new(), {"quality": 4})).is_equal(0)

func test_project_setting_fallback_and_default() -> void:
	ProjectSettings.set_setting(SETTING, 3)
	assert_int(_branch_pin(_branch_settings(), {})).is_equal(4)
	# The runtime parameter wins over the project setting.
	assert_int(_branch_pin(_branch_settings(), {"quality": 1})).is_equal(2)
	ProjectSettings.set_setting(SETTING, 0)
	assert_int(_branch_pin(_branch_settings(), {})).is_equal(1)

func test_override_wins() -> void:
	var s = _branch_settings()
	s.quality_override = 2
	assert_int(_branch_pin(s, {"quality": 4})).is_equal(3)

func test_branch_empty_and_missing_input() -> void:
	var r := H.exec(BranchScript, _branch_settings(), [H.points([])], H.make_ctx(null, 0, {"quality": 1}))
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 2).size()).is_equal(0)
	var missing := H.exec(BranchScript, _branch_settings(), [null])
	assert_str(missing.err).contains("not connected")

func test_select_picks_level_input() -> void:
	assert_str(_select_tag(_select_settings(), {"quality": 0})).is_equal("low")
	assert_str(_select_tag(_select_settings(), {"quality": "Cinematic"})).is_equal("cinematic")
	assert_str(_select_tag(_select_settings([true, false, true, true, true]), {"quality": 1})).is_equal("default")
	assert_str(_select_tag(SelectSettings.new(), {"quality": 3})).is_equal("default")

func test_select_enabled_but_unconnected_pin_is_empty() -> void:
	var r := H.exec(SelectScript, _select_settings(), [_tagged("default"), null], H.make_ctx(null, 0, {"quality": 0}))
	assert_str(r.err).is_empty()
	assert_int(H.port(r, 0).size()).is_equal(0)

func test_graph_evaluation_uses_quality_param() -> void:
	var graph = TestGraph.new() \
		.node("grid", "grid", {"x": 2, "y": 1, "z": 1}) \
		.node("q", "runtime_quality_branch", {"use_high_pin": true}) \
		.node("out_default", "output", {"name": "default"}) \
		.node("out_high", "output", {"name": "high"}) \
		.link("grid", 0, "q", 0) \
		.link("q", 0, "out_default", 0) \
		.link("q", 3, "out_high", 0) \
		.build()
	ProjectSettings.set_setting(SETTING, 0)
	var high = FlowNodeIO.evaluate(graph, {}, 0, {"quality": 2})
	assert_int(high["high"].size()).is_equal(2)
	assert_int(high["default"].size()).is_equal(0)
	var low = FlowNodeIO.evaluate(graph, {}, 0, {})
	assert_int(low["high"].size()).is_equal(0)
	assert_int(low["default"].size()).is_equal(2)
