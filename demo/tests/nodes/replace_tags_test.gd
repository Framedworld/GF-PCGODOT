# replace_tags_test.gd
class_name ReplaceTagsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const ReplaceTagsNode = preload("res://addons/flow_nodes_editor/nodes/replace_tags.gd")
const TagsMutateSettings = preload("res://addons/flow_nodes_editor/nodes/tags_mutate_settings.gd")

func _make_settings(tags_csv: String, case_sensitive: bool = false) -> TagsMutateSettings:
	var s := TagsMutateSettings.new()
	s.tags_csv = tags_csv
	s.case_sensitive = case_sensitive
	return s

func _make_data(existing_tags: PackedStringArray = PackedStringArray()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.tags = existing_tags
	return d

func _run(input: FlowData.Data, settings: TagsMutateSettings) -> ReplaceTagsNode:
	var node := ReplaceTagsNode.new()
	node.name = "replace_tags_test_node"
	node.settings = settings
	node.inputs = []
	node.inputs.resize(1)
	node.inputs[0] = input
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node: ReplaceTagsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_replace_existing_tags_with_new_set() -> void:
	var s := _make_settings("rock, ice")
	var existing := PackedStringArray(["grass", "forest", "snow"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["rock", "ice"]))

func test_replace_empty_tags_with_new_set() -> void:
	var s := _make_settings("grass, forest")
	var node := _run(_make_data(), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest"]))

func test_replace_tags_with_empty_csv_clears_all_tags() -> void:
	var s := _make_settings("")
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray())

func test_replace_single_tag() -> void:
	var s := _make_settings("desert")
	var existing := PackedStringArray(["grass", "forest", "water"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["desert"]))

func test_duplicate_tags_in_csv_deduplicated() -> void:
	var s := _make_settings("rock, rock, ice, rock")
	var existing := PackedStringArray(["grass"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["rock", "ice"]))

func test_case_insensitive_deduplication_in_csv() -> void:
	var s := _make_settings("Rock, rock, ROCK", false)
	var existing := PackedStringArray(["grass"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["Rock"]))

func test_case_sensitive_allows_different_case_variants() -> void:
	var s := _make_settings("Rock, rock, ROCK", true)
	var existing := PackedStringArray(["grass"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["Rock", "rock", "ROCK"]))

func test_operation_setting_is_ignored_always_replaces() -> void:
	var s := _make_settings("snow")
	s.operation = TagsMutateSettings.eOperation.Add
	var existing := PackedStringArray(["grass", "forest"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["snow"]))

func test_input_not_connected_sets_error() -> void:
	var node := ReplaceTagsNode.new()
	node.name = "replace_tags_test_node"
	node.settings = _make_settings("grass")
	node.inputs = []
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()

func test_does_not_mutate_original_input() -> void:
	var s := _make_settings("rock")
	var original_tags := PackedStringArray(["grass", "forest"])
	var input := _make_data(original_tags)
	var node := _run(input, s)
	assert_str(node.err).is_empty()
	assert_array(input.tags).is_equal(PackedStringArray(["grass", "forest"]))

func test_whitespace_trimmed_from_csv_tags() -> void:
	var s := _make_settings("  grass  ,  forest  ,  rock  ")
	var node := _run(_make_data(), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest", "rock"]))
