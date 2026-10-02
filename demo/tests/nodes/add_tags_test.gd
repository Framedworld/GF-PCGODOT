# add_tags_test.gd
class_name AddTagsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const AddTagsNode = preload("res://addons/flow_nodes_editor/nodes/add_tags.gd")
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

func _run(input: FlowData.Data, settings: TagsMutateSettings) -> AddTagsNode:
	var node := AddTagsNode.new()
	node.name = "add_tags_test_node"
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

func _output(node: AddTagsNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty():
		return null
	return bulk[0]

func test_add_single_tag_to_empty() -> void:
	var s := _make_settings("grass")
	var node := _run(_make_data(), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass"]))

func test_add_multiple_tags_to_empty() -> void:
	var s := _make_settings("forest, rock, water")
	var node := _run(_make_data(), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest", "rock", "water"]))

func test_add_tags_to_existing_tags() -> void:
	var s := _make_settings("rock, ice")
	var existing := PackedStringArray(["grass", "forest"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "forest", "rock", "ice"]))

func test_no_duplicate_tags_added() -> void:
	var s := _make_settings("grass, rock")
	var existing := PackedStringArray(["grass"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "rock"]))

func test_case_insensitive_deduplication() -> void:
	var s := _make_settings("GRASS, Rock", false)
	var existing := PackedStringArray(["grass", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "rock"]))

func test_case_sensitive_allows_different_case() -> void:
	var s := _make_settings("GRASS, Rock", true)
	var existing := PackedStringArray(["grass", "rock"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["grass", "rock", "GRASS", "Rock"]))

func test_empty_tags_csv_leaves_tags_unchanged() -> void:
	var s := _make_settings("")
	var existing := PackedStringArray(["forest", "snow"])
	var node := _run(_make_data(existing), s)
	assert_str(node.err).is_empty()
	var out := _output(node)
	assert_object(out).is_not_null()
	assert_array(out.tags).is_equal(PackedStringArray(["forest", "snow"]))

func test_input_not_connected_sets_error() -> void:
	var node := AddTagsNode.new()
	node.name = "add_tags_test_node"
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
	var original_tags := PackedStringArray(["grass"])
	var input := _make_data(original_tags)
	var node := _run(input, s)
	assert_str(node.err).is_empty()
	assert_array(input.tags).is_equal(PackedStringArray(["grass"]))
