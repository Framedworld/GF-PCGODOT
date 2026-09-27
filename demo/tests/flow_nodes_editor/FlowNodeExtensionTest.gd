# FlowNodeExtensionTest.gd
# Project node directories (flow_nodes/node_directories), template aliases and
# metadata-driven node categories.
class_name FlowNodeExtensionTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FlowNodeBaseScript = preload("res://addons/flow_nodes_editor/node.gd")

const EXT_DIR := "res://tests/fixtures/ext_nodes"
const EXT_TEMPLATE := "ext_fixture_value"
const SETTING := FlowNodeRegistry.SETTING_NODE_DIRECTORIES

var _had_setting := false
var _saved_setting = null
var _saved_aliases : Dictionary = {}

func before_test() -> void:
	_had_setting = ProjectSettings.has_setting(SETTING)
	_saved_setting = ProjectSettings.get_setting(SETTING) if _had_setting else null
	_saved_aliases = FlowNodeRegistry.template_aliases.duplicate()

func after_test() -> void:
	if _had_setting:
		ProjectSettings.set_setting(SETTING, _saved_setting)
	else:
		ProjectSettings.set_setting(SETTING, null)
	FlowNodeRegistry.unregister_node_directory(EXT_DIR)
	FlowNodeRegistry.template_aliases = _saved_aliases
	FlowNodeRegistry.reset_alias_warnings()

# ---------------------------------------------------------------------------
# Helpers

func _node_entry(node_name: String, template: String, settings: Dictionary = {}) -> Dictionary:
	return { "name": node_name, "template": template, "position": Vector2.ZERO, "settings": settings }

func _link(from_node: String, to_node: String) -> Dictionary:
	return { "from_node": from_node, "from_port": 0, "to_node": to_node, "to_port": 0 }

func _graph(nodes: Array, links: Array, version: int = FlowGraphMigrations.CURRENT_VERSION) -> FlowGraphResource:
	var graph := FlowGraphResource.new()
	graph.data = {
		"type": "flow_graph_nodes",
		"version": version,
		"min_pos": Vector2.ZERO,
		"nodes": nodes,
		"links": links,
		"frames": [],
	}
	return graph

func _evaluate(graph: FlowGraphResource) -> Dictionary:
	var ctx := FlowDataScript.EvaluationContext.new()
	var owner := FlowGraphNode3D.new()
	ctx.owner = owner
	var outputs := FlowNodeIO.evaluate_graph(graph, {}, ctx)
	owner.free()
	return outputs

func _ext_graph() -> FlowGraphResource:
	return _graph(
		[_node_entry("ext", EXT_TEMPLATE), _node_entry("out", "output", { "name": "result" })],
		[_link("ext", "out")])

# ---------------------------------------------------------------------------
# Node directories from project settings

func test_project_setting_directory_resolves_and_evaluates() -> void:
	assert_str(FlowNodeRegistry.get_node_script_path(EXT_TEMPLATE)).is_empty()
	var version_before := FlowNodeRegistry.get_version()

	ProjectSettings.set_setting(SETTING, PackedStringArray([EXT_DIR + "/"]))

	assert_int(FlowNodeRegistry.get_version()).is_greater(version_before)
	assert_bool(EXT_DIR in FlowNodeRegistry.get_node_directories()).is_true()
	assert_str(FlowNodeRegistry.get_node_script_path(EXT_TEMPLATE)).is_equal(EXT_DIR + "/" + EXT_TEMPLATE + ".gd")

	var outputs := _evaluate(_ext_graph())
	assert_bool(outputs.has("result")).is_true()
	var stream = outputs["result"].findStream("ext_value")
	assert_object(stream).is_not_null()
	assert_float(stream.container[0]).is_equal(42.0)

func test_removing_project_setting_directory_unregisters_it() -> void:
	ProjectSettings.set_setting(SETTING, PackedStringArray([EXT_DIR]))
	assert_str(FlowNodeRegistry.get_node_script_path(EXT_TEMPLATE)).is_not_empty()
	ProjectSettings.set_setting(SETTING, PackedStringArray())
	assert_str(FlowNodeRegistry.get_node_script_path(EXT_TEMPLATE)).is_empty()
	assert_bool(EXT_DIR in FlowNodeRegistry.get_node_directories()).is_false()

func test_project_setting_merges_with_registered_directories() -> void:
	FlowNodeRegistry.register_node_directory(EXT_DIR)
	ProjectSettings.set_setting(SETTING, PackedStringArray([EXT_DIR, FlowNodeRegistry.DEFAULT_NODE_DIRECTORY]))
	var directories := FlowNodeRegistry.get_node_directories()
	assert_str(directories[0]).is_equal(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY)
	assert_int(directories.count(EXT_DIR)).is_equal(1)
	assert_int(directories.count(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY)).is_equal(1)

func test_register_node_directory_still_works_without_setting() -> void:
	FlowNodeRegistry.register_node_directory(EXT_DIR)
	assert_str(FlowNodeRegistry.get_node_script_path(EXT_TEMPLATE)).is_equal(EXT_DIR + "/" + EXT_TEMPLATE + ".gd")
	var outputs := _evaluate(_ext_graph())
	assert_bool(outputs.has("result")).is_true()

func test_stock_template_cannot_be_shadowed_by_project_directory() -> void:
	ProjectSettings.set_setting(SETTING, PackedStringArray([EXT_DIR]))
	assert_str(FlowNodeRegistry.get_node_script_path("grid")).is_equal(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY + "/grid.gd")

func test_ensure_project_setting_registers_default() -> void:
	ProjectSettings.set_setting(SETTING, null)
	FlowNodeRegistry.ensure_project_setting()
	assert_bool(ProjectSettings.has_setting(SETTING)).is_true()
	var value = ProjectSettings.get_setting(SETTING)
	assert_bool(value is PackedStringArray).is_true()
	assert_int(value.size()).is_equal(0)
	# The default is registered as the initial value, so project.godot only stores
	# the setting once a project changes it.
	assert_that(ProjectSettings.property_get_revert(SETTING)).is_equal(PackedStringArray())

# ---------------------------------------------------------------------------
# Template aliases

func test_template_alias_resolves_to_new_template() -> void:
	FlowNodeRegistry.template_aliases["legacy_grid_points"] = "grid"
	assert_str(FlowNodeRegistry.get_node_script_path("legacy_grid_points")).is_equal(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY + "/grid.gd")
	assert_str(FlowNodeRegistry.resolve_template_alias("legacy_grid_points")).is_equal("grid")
	assert_str(FlowNodeRegistry.resolve_template_alias("grid")).is_equal("grid")

func test_template_alias_chain_and_cycle() -> void:
	FlowNodeRegistry.template_aliases["legacy_a"] = "legacy_b"
	FlowNodeRegistry.template_aliases["legacy_b"] = "grid"
	assert_str(FlowNodeRegistry.get_node_script_path("legacy_a")).is_equal(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY + "/grid.gd")
	FlowNodeRegistry.template_aliases["loop_x"] = "loop_y"
	FlowNodeRegistry.template_aliases["loop_y"] = "loop_x"
	assert_str(FlowNodeRegistry.get_node_script_path("loop_x")).is_empty()

func test_alias_does_not_replace_existing_template() -> void:
	FlowNodeRegistry.template_aliases["merge"] = "grid"
	assert_str(FlowNodeRegistry.get_node_script_path("merge")).is_equal(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY + "/merge.gd")
	assert_str(FlowNodeRegistry.alias_for_missing_template("merge")).is_empty()

func test_aliased_graph_evaluates_and_migrates_template_name() -> void:
	FlowNodeRegistry.template_aliases["legacy_grid_points"] = "grid"
	var graph := _graph(
		[_node_entry("pts", "legacy_grid_points", { "x": 2, "y": 1, "z": 2, "random_seed": 7 }),
		 _node_entry("out", "output", { "name": "result" })],
		[_link("pts", "out")])
	var outputs := _evaluate(graph)
	assert_bool(outputs.has("result")).is_true()
	assert_int(outputs["result"].size()).is_equal(4)
	# Runtime never writes back to the resource.
	assert_str(graph.data.nodes[0].template).is_equal("legacy_grid_points")
	var migrated := FlowGraphMigrations.migrate(graph.data)
	assert_str(migrated.nodes[0].template).is_equal("grid")

# ---------------------------------------------------------------------------
# Categories come from node metadata

func test_every_stock_node_declares_a_known_category() -> void:
	var missing : Array[String] = []
	var dir := DirAccess.open(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY)
	assert_object(dir).is_not_null()
	for file_name in dir.get_files():
		if not file_name.ends_with(".gd") or file_name.ends_with("_settings.gd"):
			continue
		var script : Script = load(FlowNodeRegistry.DEFAULT_NODE_DIRECTORY + "/" + file_name)
		if script == null or not script.can_instantiate():
			continue
		var instance = script.new()
		if not (instance is FlowNodeBase):
			if instance is Node:
				instance.free()
			continue
		var category := String(instance.getMeta().get("category", ""))
		var key := FlowNodeBaseScript.normalize_category(category)
		if not FlowNodeBaseScript.CATEGORY_HUES.has(key):
			missing.append("%s (%s)" % [file_name, category])
		instance.free()
	assert_array(missing).is_empty()

func test_category_hue_comes_from_metadata() -> void:
	var node = FlowNodeBaseScript.new()
	node.node_template = "bl_something"
	node.meta_node = { "category": "Filter" }
	assert_float(node._get_category_hue()).is_equal(FlowNodeBaseScript.CATEGORY_HUES["filter"])
	node.meta_node = { "category": "Control Flow" }
	assert_float(node._get_category_hue()).is_equal(FlowNodeBaseScript.CATEGORY_HUES["controlflow"])
	node.meta_node = { "category": "Generators" }
	assert_float(node._get_category_hue()).is_equal(FlowNodeBaseScript.CATEGORY_HUES["generator"])
	# Unknown or missing category -> stable hash of the template name.
	node.meta_node = {}
	var expected := float(node.node_template.hash() % 360) / 360.0
	assert_float(node._get_category_hue()).is_equal(expected)
	node.free()

func test_search_popup_prefers_meta_category() -> void:
	var popup := SearchAddNodePopup.new()
	assert_str(popup._get_category_for_template("grid", { "category": "Sampler" })).is_equal("Sampler")
	assert_str(popup._get_category_for_template("my_project_node", { "category": "My Game" })).is_equal("My Game")
	assert_str(popup._get_category_for_template("my_project_node", {})).is_equal("Utility")
	popup.free()

# ---------------------------------------------------------------------------
# Project category colour: meta_node.hue / meta_node.color

func _ext_instance(template: String) -> FlowNodeBase:
	FlowNodeRegistry.register_node_directory(EXT_DIR)
	var path := FlowNodeRegistry.get_node_script_path(template)
	assert_str(path).is_equal(EXT_DIR + "/" + template + ".gd")
	var node: FlowNodeBase = load(path).new()
	node.node_template = template
	return node

func test_fixture_node_with_meta_hue_gets_that_hue() -> void:
	var node := _ext_instance("ext_fixture_hued")
	assert_float(node._get_category_hue()).is_equal_approx(0.62, 0.00001)
	assert_object(node._get_meta_node_color()).is_null()
	node.free()

func test_meta_hue_is_shared_across_project_category_and_clamped() -> void:
	var a = FlowNodeBaseScript.new()
	a.node_template = "mygame_a"
	a.meta_node = { "category": "My Game", "hue": 0.4 }
	var b = FlowNodeBaseScript.new()
	b.node_template = "mygame_b"
	b.meta_node = { "category": "My Game", "hue": 0.4 }
	# Without the hue the two templates hash to different colours.
	assert_float(a._get_category_hue()).is_equal(b._get_category_hue())
	a.meta_node = { "category": "Filter", "hue": 1.7 }
	assert_float(a._get_category_hue()).is_equal(1.0)
	a.meta_node = { "category": "Filter", "hue": 1 }
	assert_float(a._get_category_hue()).is_equal(1.0)
	# A non-numeric hue is ignored: the category table applies.
	a.meta_node = { "category": "Filter", "hue": "red" }
	assert_float(a._get_category_hue()).is_equal(FlowNodeBaseScript.CATEGORY_HUES["filter"])
	a.free()
	b.free()

func test_fixture_node_with_meta_color_uses_its_hue_and_colour() -> void:
	var node := _ext_instance("ext_fixture_colored")
	var expected := Color(0.9, 0.3, 0.1)
	assert_object(node._get_meta_node_color()).is_equal(expected)
	assert_float(node._get_category_hue()).is_equal_approx(expected.h, 0.00001)
	node.free()

func _color_nodes_editor() -> Control:
	var script := GDScript.new()
	script.source_code = "extends Control\nvar color_nodes := true\nvar resource_owner = null\n"
	script.reload()
	var editor: Control = script.new()
	return editor

# update_node_style tints the title bar from meta_node.color (or the hue) when
# the editor colours nodes. getEditor() is GraphEdit -> 3 Control ancestors up.
func _styled_titlebar(node: FlowNodeBase) -> StyleBox:
	var editor := _color_nodes_editor()
	var c1 := Control.new()
	var c2 := Control.new()
	var gedit := GraphEdit.new()
	editor.add_child(c1)
	c1.add_child(c2)
	c2.add_child(gedit)
	gedit.add_child(node)
	add_child(editor)
	node.update_node_style()
	var sb := node.get_theme_stylebox("titlebar")
	editor.queue_free()
	return sb

func test_update_node_style_uses_meta_color() -> void:
	var node := _ext_instance("ext_fixture_colored")
	var sb := _styled_titlebar(node)
	assert_bool(sb is StyleBoxFlat).is_true()
	assert_object((sb as StyleBoxFlat).bg_color).is_equal(Color(0.9, 0.3, 0.1).darkened(0.62))

func test_update_node_style_uses_meta_hue() -> void:
	var node := _ext_instance("ext_fixture_hued")
	var sb := _styled_titlebar(node)
	assert_bool(sb is StyleBoxFlat).is_true()
	assert_object((sb as StyleBoxFlat).bg_color).is_equal(Color.from_hsv(0.62, 0.35, 0.24, 1.0))
