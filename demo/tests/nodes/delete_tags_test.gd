# delete_tags_test.gd
class_name DeleteTagsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const DeleteTagsNode = preload("res://addons/flow_nodes_editor/nodes/delete_tags.gd")
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

func _run(input: FlowData.Data, settings: TagsMutateSettings) -> DeleteTagsNode:
	var node := DeleteTagsNode.new()
	node.name = "delete_tags_test_node"
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

func _output(node: DeleteTagsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_delete_single_tag() -> void:
	var s := _make_settings("grass")
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest", "rock"]))

func test_delete_multiple_tags() -> void:
	var s := _make_settings("grass, rock")
	var existing := PackedStringArray(["grass", "forest", "rock", "snow"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest", "snow"]))

func test_delete_all_tags() -> void:
	var s := _make_settings("grass, forest, rock")
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray())

func test_delete_tag_not_present_leaves_tags_unchanged() -> void:
	var s := _make_settings("snow")
	var existing := PackedStringArray(["grass", "forest"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest"]))

func test_empty_tags_csv_leaves_all_tags() -> void:
	var s := _make_settings("")
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest", "rock"]))

func test_delete_from_empty_tags_produces_empty() -> void:
	var s := _make_settings("grass")
	var node := _run(_make_data(), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray())

func test_case_insensitive_delete_matches_different_case() -> void:
	var s := _make_settings("GRASS, ROCK", false)
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest"]))

func test_case_sensitive_does_not_delete_different_case() -> void:
	var s := _make_settings("GRASS, ROCK", true)
	var existing := PackedStringArray(["grass", "forest", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest", "rock"]))

func test_input_not_connected_sets_error() -> void:
	var node := DeleteTagsNode.new()
	node.name = "delete_tags_test_node"
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
	var s := _make_settings("grass")
	var original_tags := PackedStringArray(["grass", "forest"])
	var input := _make_data(original_tags)
	var node := _run(input, s)
	assert_str(node.err).is_empty()
	assert_array(input.tags).is_equal(PackedStringArray(["grass", "forest"]))
