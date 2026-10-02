# WP11 item 6: stale tooltips, and the flow_nodes/quality_level project setting
# registered by the editor plugin at startup (not only by the quality nodes).
class_name TooltipsAndSettingsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const SETTING := "flow_nodes/quality_level"
const PLUGIN_PATH := "res://addons/flow_nodes_editor/plugin.gd"

var _saved_value = null
var _had_setting := false

func before() -> void:
	_had_setting = ProjectSettings.has_setting(SETTING)
	if _had_setting:
		_saved_value = ProjectSettings.get_setting(SETTING)

func after() -> void:
	if _had_setting:
		ProjectSettings.set_setting(SETTING, _saved_value)

func _tooltip(template : String) -> String:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path(template)).new()
	return String(element.meta_node.get("tooltip", ""))

func test_bounds_modifier_tooltip_describes_per_point_bounds() -> void:
	var text := _tooltip("bounds_modifier")
	assert_str(text).contains("Per Point Bounds")
	assert_str(text).contains("bounds_min/bounds_max")
	assert_str(text).not_contains("the bounds center is ignored")

func test_decompose_vector_tooltip_lists_every_vector_type() -> void:
	var text := _tooltip("decompose_vector")
	for type_name in ["Vector2", "Vector3", "Vector4", "Quaternion", "Color"]:
		assert_str(text).contains(type_name)
	assert_str(text).not_contains("into three float attributes")

func test_get_property_from_object_path_tooltip_mentions_user_paths() -> void:
	assert_str(_tooltip("get_property_from_object_path")).contains("user://")

func _property_info(name : String) -> Dictionary:
	for info in ProjectSettings.get_property_list():
		if info.name == name:
			return info
	return {}

func test_plugin_registers_the_quality_level_setting() -> void:
	ProjectSettings.clear(SETTING)
	assert_bool(ProjectSettings.has_setting(SETTING)).is_false()
	load(PLUGIN_PATH).register_project_settings()
	assert_bool(ProjectSettings.has_setting(SETTING)).is_true()
	assert_int(int(ProjectSettings.get_setting(SETTING))).is_equal(0)
	var info := _property_info(SETTING)
	assert_int(int(info.get("hint", -1))).is_equal(PROPERTY_HINT_ENUM)
	assert_str(String(info.get("hint_string", ""))).is_equal("Low,Medium,High,Epic,Cinematic")

func test_plugin_startup_calls_the_registration() -> void:
	# _enter_tree and _enable_plugin need a running editor; check that both go
	# through register_project_settings().
	var source := FileAccess.get_file_as_string(PLUGIN_PATH)
	for hook in ["func _enter_tree", "func _enable_plugin"]:
		var start := source.find(hook)
		assert_int(start).is_greater_equal(0)
		var next := source.find("\nfunc ", start + 1)
		var body := source.substr(start, (next - start) if next > 0 else -1)
		assert_str(body).override_failure_message(hook).contains("register_project_settings()")
