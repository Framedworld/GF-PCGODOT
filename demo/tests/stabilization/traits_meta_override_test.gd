# WP11 item 3: bounds_from_mesh runs on the main thread, and FlowNodeTraits
# warns (once per template) when a meta_node flag contradicts a table row.
class_name TraitsMetaOverrideTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

func before_test() -> void:
	FlowNodeTraits.clear_cache()
	FlowNodeTraits.clear_override_warnings()

func after() -> void:
	FlowNodeTraits.clear_cache()
	FlowNodeTraits.clear_override_warnings()

func _element(template : String) -> FlowNodeBase:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path(template)).new()
	element.node_template = template
	return element

func test_bounds_from_mesh_is_main_thread_and_not_cacheable() -> void:
	var element := _element("bounds_from_mesh")
	assert_bool(FlowNodeTraits.main_thread(element)).is_true()
	assert_bool(FlowNodeTraits.cacheable(element)).is_false()
	assert_bool(element.meta_node.get("main_thread")).is_true()
	assert_bool(element.meta_node.get("pure")).is_false()

func test_no_stock_template_contradicts_its_table_row() -> void:
	for template in FlowNodeTraits.TABLE.keys():
		var path := FlowNodeRegistry.get_node_script_path(template)
		if path == "" or not ResourceLoader.exists(path):
			continue
		FlowNodeTraits.for_element(_element(template))
	assert_dict(FlowNodeTraits.override_warnings()).is_empty()

func test_contradicting_meta_warns_once_per_template() -> void:
	# grid's table row is [main_thread = false, cacheable = true].
	var pinned := FlowNodeTraits.resolve("grid", { "main_thread": true })
	assert_bool(pinned.main_thread).is_true()
	FlowNodeTraits.resolve("grid", { "pure": false })
	var warnings := FlowNodeTraits.override_warnings()
	assert_int(warnings.size()).is_equal(1)
	assert_str(String(warnings["grid"])).contains("grid")
	assert_str(String(warnings["grid"])).contains("main_thread")

func test_agreeing_meta_and_unknown_templates_do_not_warn() -> void:
	FlowNodeTraits.resolve("grid", { "pure": true, "main_thread": false })
	FlowNodeTraits.resolve("my_game_node", { "pure": true })
	FlowNodeTraits.resolve("spawn_meshes", {})
	assert_dict(FlowNodeTraits.override_warnings()).is_empty()
