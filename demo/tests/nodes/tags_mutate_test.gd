# tags_mutate_test.gd
class_name TagsMutateTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const TagsMutateNode = preload("res://addons/flow_nodes_editor/nodes/tags_mutate.gd")
const TagsMutateSettings = preload("res://addons/flow_nodes_editor/nodes/tags_mutate_settings.gd")

func _make_settings(tags_csv: String, operation: int = TagsMutateSettings.eOperation.Add, case_sensitive: bool = false) -> TagsMutateSettings:
	var s := TagsMutateSettings.new()
	s.tags_csv = tags_csv
	s.operation = operation
	s.case_sensitive = case_sensitive
	return s

func _make_data(existing_tags: PackedStringArray = PackedStringArray()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.tags = existing_tags
	return d

func _run(input: FlowData.Data, settings: TagsMutateSettings) -> TagsMutateNode:
	var node := TagsMutateNode.new()
	node.name = "tags_mutate_test_node"
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

func _output(node: TagsMutateNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_add_tags_to_empty() -> void:
	var s := _make_settings("grass, rock", TagsMutateSettings.eOperation.Add)
	var node := _run(_make_data(), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "rock"]))
	node.free()

func test_add_tags_no_duplicates() -> void:
	var s := _make_settings("grass, snow", TagsMutateSettings.eOperation.Add)
	var existing := PackedStringArray(["grass", "forest"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest", "snow"]))
	node.free()

func test_add_case_insensitive_deduplication() -> void:
	var s := _make_settings("GRASS, Rock", TagsMutateSettings.eOperation.Add, false)
	var existing := PackedStringArray(["grass", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "rock"]))
	node.free()

func test_add_case_sensitive_allows_different_case() -> void:
	var s := _make_settings("GRASS, Rock", TagsMutateSettings.eOperation.Add, true)
	var existing := PackedStringArray(["grass", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "rock", "GRASS", "Rock"]))
	node.free()

func test_remove_tags_from_existing() -> void:
	var s := _make_settings("grass, rock", TagsMutateSettings.eOperation.Remove)
	var existing := PackedStringArray(["grass", "forest", "rock", "snow"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest", "snow"]))
	node.free()

func test_remove_tag_not_present_leaves_unchanged() -> void:
	var s := _make_settings("desert", TagsMutateSettings.eOperation.Remove)
	var existing := PackedStringArray(["grass", "forest"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest"]))
	node.free()

func test_remove_all_tags_produces_empty() -> void:
	var s := _make_settings("grass, forest, rock", TagsMutateSettings.eOperation.Remove)
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray())
	node.free()

func test_remove_case_insensitive_matches_different_case() -> void:
	var s := _make_settings("GRASS, ROCK", TagsMutateSettings.eOperation.Remove, false)
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest"]))
	node.free()

func test_remove_case_sensitive_does_not_remove_different_case() -> void:
	var s := _make_settings("GRASS, ROCK", TagsMutateSettings.eOperation.Remove, true)
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest", "rock"]))
	node.free()

func test_replace_existing_tags() -> void:
	var s := _make_settings("rock, ice", TagsMutateSettings.eOperation.Replace)
	var existing := PackedStringArray(["grass", "forest", "snow"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["rock", "ice"]))
	node.free()

func test_replace_with_empty_csv_clears_all_tags() -> void:
	var s := _make_settings("", TagsMutateSettings.eOperation.Replace)
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray())
	node.free()

func test_replace_deduplicates_csv_tags() -> void:
	var s := _make_settings("rock, rock, ice, rock", TagsMutateSettings.eOperation.Replace)
	var existing := PackedStringArray(["grass"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["rock", "ice"]))
	node.free()

func test_empty_csv_add_leaves_tags_unchanged() -> void:
	var s := _make_settings("", TagsMutateSettings.eOperation.Add)
	var existing := PackedStringArray(["forest", "snow"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest", "snow"]))
	node.free()

func test_whitespace_trimmed_from_csv_tags() -> void:
	var s := _make_settings("  grass  ,  forest  ,  rock  ", TagsMutateSettings.eOperation.Add)
	var node := _run(_make_data(), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest", "rock"]))
	node.free()

func test_does_not_mutate_original_input() -> void:
	var s := _make_settings("rock", TagsMutateSettings.eOperation.Add)
	var original_tags := PackedStringArray(["grass"])
	var input := _make_data(original_tags)
	var node := _run(input, s)
	assert_str(node.err).is_empty()
	assert_array(input.tags).is_equal(PackedStringArray(["grass"]))
	node.free()

func test_input_not_connected_sets_error() -> void:
	var node := TagsMutateNode.new()
	node.name = "tags_mutate_test_node"
	node.settings = _make_settings("grass")
	node.inputs = []
	node.inputs.resize(1)
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()
	node.free()
