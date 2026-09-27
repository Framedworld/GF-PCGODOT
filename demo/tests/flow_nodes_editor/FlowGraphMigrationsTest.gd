# FlowGraphMigrationsTest.gd
# Graph format versioning and per-template settings migrations.
class_name FlowGraphMigrationsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FlowEditorScene = preload("res://addons/flow_nodes_editor/flow_editor.tscn")

var _saved_migrations : Dictionary = {}

func before_test() -> void:
	_saved_migrations = FlowGraphMigrations.MIGRATIONS.duplicate()

func after_test() -> void:
	FlowGraphMigrations.MIGRATIONS = _saved_migrations

# Installs a temporary migration for the current version.
func _install(template: String, rules: Dictionary) -> void:
	var table : Dictionary = FlowGraphMigrations.MIGRATIONS.get(FlowGraphMigrations.CURRENT_VERSION, {}).duplicate()
	table[template] = rules
	FlowGraphMigrations.MIGRATIONS[FlowGraphMigrations.CURRENT_VERSION] = table

func _grid_graph_data(version, grid_settings: Dictionary) -> Dictionary:
	var data := {
		"type": "flow_graph_nodes",
		"min_pos": Vector2.ZERO,
		"nodes": [
			{ "name": "pts", "template": "grid", "position": Vector2.ZERO, "settings": grid_settings },
			{ "name": "out", "template": "output", "position": Vector2(200, 0), "settings": { "name": "result" } },
		],
		"links": [ { "from_node": "pts", "from_port": 0, "to_node": "out", "to_port": 0 } ],
		"frames": [],
	}
	if version != null:
		data["version"] = version
	return data

func _evaluate(graph: FlowGraphResource) -> Dictionary:
	var ctx := FlowDataScript.EvaluationContext.new()
	var owner := FlowGraphNode3D.new()
	ctx.owner = owner
	var outputs := FlowNodeIO.evaluate_graph(graph, {}, ctx)
	owner.free()
	return outputs

# ---------------------------------------------------------------------------

func test_current_version_is_two() -> void:
	assert_int(FlowGraphMigrations.CURRENT_VERSION).is_equal(2)
	assert_bool(FlowGraphMigrations.MIGRATIONS.has(2)).is_true()

func test_unversioned_data_counts_as_version_one() -> void:
	var data := _grid_graph_data(null, { "x": 1 })
	assert_int(FlowGraphMigrations.get_version(data)).is_equal(1)
	assert_bool(FlowGraphMigrations.needs_migration(data)).is_true()
	assert_int(FlowGraphMigrations.migrate(data).version).is_equal(2)

func test_version_one_is_bumped_by_noop_migration() -> void:
	var data := _grid_graph_data(1, { "x": 2, "y": 1, "z": 2 })
	var migrated := FlowGraphMigrations.migrate(data)
	assert_bool(is_same(migrated, data)).is_false()
	assert_int(migrated.version).is_equal(FlowGraphMigrations.CURRENT_VERSION)
	assert_dict(migrated.nodes[0].settings).is_equal(data.nodes[0].settings)
	# The input is never modified.
	assert_int(data.version).is_equal(1)

func test_version_one_old_key_is_renamed_and_evaluates() -> void:
	_install("grid", { "legacy_count_x": "x" })
	var data := _grid_graph_data(1, { "legacy_count_x": 5, "y": 1, "z": 1, "random_seed": 3 })
	var migrated := FlowGraphMigrations.migrate(data)
	assert_bool(migrated.nodes[0].settings.has("legacy_count_x")).is_false()
	assert_int(migrated.nodes[0].settings.x).is_equal(5)

	var graph := FlowGraphResource.new()
	graph.data = data
	var outputs := _evaluate(graph)
	assert_bool(outputs.has("result")).is_true()
	assert_int(outputs["result"].size()).is_equal(5)
	# Runtime migration never writes back to the resource.
	assert_int(graph.data.version).is_equal(1)
	assert_bool(graph.data.nodes[0].settings.has("legacy_count_x")).is_true()

func test_rename_keeps_existing_new_key() -> void:
	_install("grid", { "legacy_count_x": "x" })
	var migrated := FlowGraphMigrations.migrate(_grid_graph_data(1, { "legacy_count_x": 5, "x": 2 }))
	assert_int(migrated.nodes[0].settings.x).is_equal(2)
	assert_bool(migrated.nodes[0].settings.has("legacy_count_x")).is_false()

static func _split_legacy_count(settings: Dictionary) -> Dictionary:
	var out := settings.duplicate()
	out["x"] = settings["legacy_count"]
	out["z"] = settings["legacy_count"]
	out.erase("legacy_count")
	return out

func test_callable_migration() -> void:
	_install("grid", { "legacy_count": _split_legacy_count })
	var data := _grid_graph_data(1, { "legacy_count": 3, "y": 1, "random_seed": 3 })
	var graph := FlowGraphResource.new()
	graph.data = data
	var outputs := _evaluate(graph)
	assert_int(outputs["result"].size()).is_equal(9)

func test_wildcard_template_rules_apply_to_every_node() -> void:
	_install("*", { "legacy_debug": "debug_enabled" })
	var migrated := FlowGraphMigrations.migrate(_grid_graph_data(1, { "legacy_debug": true }))
	assert_bool(migrated.nodes[0].settings.debug_enabled).is_true()
	assert_bool(migrated.nodes[0].settings.has("legacy_debug")).is_false()

func test_version_two_data_is_untouched() -> void:
	_install("grid", { "legacy_count_x": "x" })
	var data := _grid_graph_data(2, { "legacy_count_x": 5, "y": 1, "z": 1 })
	var migrated := FlowGraphMigrations.migrate(data)
	assert_bool(is_same(migrated, data)).is_true()
	assert_bool(migrated.nodes[0].settings.has("legacy_count_x")).is_true()
	assert_bool(FlowGraphMigrations.needs_migration(data)).is_false()

func test_future_version_is_left_alone() -> void:
	var data := _grid_graph_data(FlowGraphMigrations.CURRENT_VERSION + 1, { "x": 1 })
	assert_bool(is_same(FlowGraphMigrations.migrate(data), data)).is_true()

func test_empty_data_is_left_alone() -> void:
	var data := {}
	assert_bool(is_same(FlowGraphMigrations.migrate(data), data)).is_true()

# ---------------------------------------------------------------------------
# Editor path: load an old resource, save it, the stored version is bumped.

func _make_editor() -> Control:
	var editor : Control = FlowEditorScene.instantiate()
	add_child(editor)
	return editor

func _free_editor(editor: Control) -> void:
	editor.current_resource = null
	for child in editor.gedit.get_children():
		if child is GraphNode or child is GraphFrame:
			editor.gedit.remove_child(child)
			child.free()
	editor.gedit_nodes_by_name.clear()
	remove_child(editor)
	editor.free()

func test_editor_load_and_save_bumps_version() -> void:
	_install("grid", { "legacy_count_x": "x" })
	var resource := FlowGraphResource.new()
	resource.data = _grid_graph_data(1, { "legacy_count_x": 4, "y": 1, "z": 1 })

	var editor := _make_editor()
	editor.current_resource = resource
	FlowNodeIO.loadFromResource(editor)

	# Loading upgrades in memory and marks the graph for saving.
	assert_int(resource.data.version).is_equal(FlowGraphMigrations.CURRENT_VERSION)
	assert_bool(editor.save_pending).is_true()
	var grid_node = editor.gedit_nodes_by_name.get("pts")
	assert_object(grid_node).is_not_null()
	assert_int(grid_node.settings.x).is_equal(4)

	FlowNodeIO.saveToResource(editor)
	assert_int(resource.data.version).is_equal(FlowGraphMigrations.CURRENT_VERSION)
	var saved_grid : Dictionary = {}
	for node_data in resource.data.nodes:
		if node_data.name == "pts":
			saved_grid = node_data
	assert_int(saved_grid.settings.x).is_equal(4)
	assert_bool(saved_grid.settings.has("legacy_count_x")).is_false()
	_free_editor(editor)

func test_editor_load_of_current_graph_is_not_marked_dirty() -> void:
	var resource := FlowGraphResource.new()
	resource.data = _grid_graph_data(FlowGraphMigrations.CURRENT_VERSION, { "x": 2, "y": 1, "z": 1 })
	var original : Dictionary = resource.data
	var editor := _make_editor()
	editor.current_resource = resource
	FlowNodeIO.loadFromResource(editor)
	assert_bool(is_same(resource.data, original)).is_true()
	assert_bool(editor.save_pending).is_false()
	_free_editor(editor)

func test_paste_of_old_clipboard_json_is_migrated() -> void:
	_install("grid", { "legacy_count_x": "x" })
	var editor := _make_editor()
	editor.current_resource = FlowGraphResource.new()
	var json := JSON.stringify(_grid_graph_data(1, { "legacy_count_x": 6, "y": 1, "z": 1 }))
	var dict = JSON.parse_string(json)
	var new_nodes = FlowNodeIO.create_nodes_from_dict(dict, editor, Vector2.ZERO)
	var grid_node = null
	for node in new_nodes:
		if node.node_template == "grid":
			grid_node = node
	assert_object(grid_node).is_not_null()
	assert_int(grid_node.settings.x).is_equal(6)
	_free_editor(editor)
