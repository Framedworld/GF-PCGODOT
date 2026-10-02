# flow_node_traits_test.gd
# FlowNodeTraits: every stock template is classified by the central table,
# meta_node overrides, meta-flag fallbacks and the safe default for unknown
# (third-party) templates.
class_name FlowNodeTraitsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")


func _stock_templates() -> Array:
	var templates := []
	var dir := DirAccess.open(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY)
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd") or file_name.ends_with("_settings.gd"):
			continue
		var script : Script = load(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY + "/" + file_name)
		if script == null or not script.can_instantiate():
			continue
		var instance = script.new()
		if instance is FlowNodeBase:
			templates.append(file_name.get_basename())
		elif instance is Object and not (instance is RefCounted):
			instance.free()
	return templates


func test_every_stock_template_is_in_the_table() -> void:
	var missing := []
	for template in _stock_templates():
		if not FlowNodeTraits.TABLE.has(template):
			missing.append(template)
	assert_array(missing).override_failure_message("templates without traits: %s" % [missing]).is_empty()


func test_table_rows_name_existing_templates() -> void:
	var templates := _stock_templates()
	var stale := []
	for template in FlowNodeTraits.TABLE:
		if not templates.has(template):
			stale.append(template)
	assert_array(stale).is_empty()


func test_scene_and_context_nodes_are_main_thread_and_not_cacheable() -> void:
	for template in ["spawn_meshes", "spawn_scenes", "spawn_nodes", "scan_splines", "ray_cast", "subgraph", "loop", "set_variable", "get_variable", "input", "sample_spline", "debug"]:
		var traits := FlowNodeTraits.resolve(template)
		assert_bool(traits.main_thread).override_failure_message(template).is_true()
		assert_bool(traits.cacheable).override_failure_message(template).is_false()


func test_pure_nodes_are_threadable_and_cacheable() -> void:
	for template in ["grid", "add_attribute", "math_op", "expression", "filter", "merge", "transform_points", "sample_points"]:
		var traits := FlowNodeTraits.resolve(template)
		assert_bool(traits.main_thread).override_failure_message(template).is_false()
		assert_bool(traits.cacheable).override_failure_message(template).is_true()


func test_dynamic_input_and_output_templates_resolve_like_their_base() -> void:
	assert_dict(FlowNodeTraits.resolve("input_density")).is_equal(FlowNodeTraits.resolve("input"))
	assert_dict(FlowNodeTraits.resolve("output_points")).is_equal(FlowNodeTraits.resolve("output"))


func test_unknown_templates_default_to_main_thread_and_not_cacheable() -> void:
	var traits := FlowNodeTraits.resolve("my_game_room_dresser")
	assert_bool(traits.main_thread).is_true()
	assert_bool(traits.cacheable).is_false()


func test_meta_flags_mark_scene_nodes() -> void:
	for flag in ["scans_scene", "queries_physics", "is_final"]:
		var traits := FlowNodeTraits.resolve("my_game_node", { flag: true })
		assert_bool(traits.main_thread).is_true()
		assert_bool(traits.cacheable).is_false()


func test_meta_node_overrides_win() -> void:
	var pure := FlowNodeTraits.resolve("my_game_node", { "pure": true })
	assert_bool(pure.main_thread).is_false()
	assert_bool(pure.cacheable).is_true()
	var pure_main := FlowNodeTraits.resolve("my_game_node", { "pure": true, "main_thread": true })
	assert_bool(pure_main.main_thread).is_true()
	assert_bool(pure_main.cacheable).is_true()
	# A stock node can be pinned to the main thread by its script.
	var pinned := FlowNodeTraits.resolve("grid", { "main_thread": true })
	assert_bool(pinned.main_thread).is_true()
	assert_bool(pinned.cacheable).is_true()
	var impure := FlowNodeTraits.resolve("grid", { "pure": false })
	assert_bool(impure.main_thread).is_true()
	assert_bool(impure.cacheable).is_false()


func test_for_element_reads_the_script_meta() -> void:
	var element : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path("grid")).new()
	element.node_template = "grid"
	assert_bool(FlowNodeTraits.main_thread(element)).is_false()
	assert_bool(FlowNodeTraits.cacheable(element)).is_true()
	var spawner : FlowNodeBase = load(FlowNodeRegistry.get_node_script_path("spawn_meshes")).new()
	spawner.node_template = "spawn_meshes"
	assert_bool(FlowNodeTraits.main_thread(spawner)).is_true()
