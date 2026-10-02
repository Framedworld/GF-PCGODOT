# filter_data_by_tag_test.gd
class_name FilterDataByTagTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const FilterDataByTagNode = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_tag.gd")
const FilterDataByTagSettings = preload("res://addons/flow_nodes_editor/nodes/filter_data_by_tag_settings.gd")

func _make_data(tags: PackedStringArray = PackedStringArray()) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.tags = tags
	d.registerStream("position", PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)]), FlowDataScript.DataType.Vector)
	return d

func _make_settings(tags_csv: String) -> FilterDataByTagNodeSettings:
	var s := FilterDataByTagSettings.new()
	s.tags = tags_csv
	return s

func _run(input, settings: FilterDataByTagNodeSettings) -> FilterDataByTagNode:
	var node := FilterDataByTagNode.new()
	node.name = "filter_data_by_tag_test_node"
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

func _inside(node: FilterDataByTagNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.size() < 1:
		return null
	return bulk[0]

func _outside(node: FilterDataByTagNode) -> FlowData.Data:
	if node.generated_bulks.is_empty():
		return null
	var bulk = node.generated_bulks[0]
	if bulk.size() < 2:
		return null
	return bulk[1]

func test_matching_tag_routes_to_inside() -> void:
	var input := _make_data(PackedStringArray(["grass", "forest"]))
	var node := _run(input, _make_settings("grass"))
	assert_str(node.err).is_empty()
	var inside := _inside(node)
	var outside := _outside(node)
	assert_object(inside).is_equal(input)
	assert_int(outside.size()).is_equal(0)

func test_non_matching_tag_routes_to_outside() -> void:
	var input := _make_data(PackedStringArray(["rock", "snow"]))
	var node := _run(input, _make_settings("grass"))
	assert_str(node.err).is_empty()
	var inside := _inside(node)
	var outside := _outside(node)
	assert_int(inside.size()).is_equal(0)
	assert_object(outside).is_equal(input)

func test_or_semantics_any_matching_tag_routes_inside() -> void:
	var input := _make_data(PackedStringArray(["rock"]))
	var node := _run(input, _make_settings("grass, rock, snow"))
	assert_str(node.err).is_empty()
	var inside := _inside(node)
	var outside := _outside(node)
	assert_object(inside).is_equal(input)
	assert_int(outside.size()).is_equal(0)

func test_data_with_no_tags_routes_to_outside() -> void:
	var input := _make_data(PackedStringArray())
	var node := _run(input, _make_settings("grass, forest"))
	assert_str(node.err).is_empty()
	var inside := _inside(node)
	var outside := _outside(node)
	assert_int(inside.size()).is_equal(0)
	assert_object(outside).is_equal(input)

func test_whitespace_around_tags_in_filter_is_trimmed() -> void:
	var input := _make_data(PackedStringArray(["forest"]))
	var node := _run(input, _make_settings("  grass  ,  forest  ,  rock  "))
	assert_str(node.err).is_empty()
	var inside := _inside(node)
	assert_object(inside).is_equal(input)

func test_empty_tags_setting_sets_error() -> void:
	var input := _make_data(PackedStringArray(["grass"]))
	var node := _run(input, _make_settings(""))
	assert_str(node.err).is_not_empty()

func test_whitespace_only_tags_setting_sets_error() -> void:
	var input := _make_data(PackedStringArray(["grass"]))
	var node := _run(input, _make_settings("  ,  ,  "))
	assert_str(node.err).is_not_empty()

func test_input_not_connected_sets_error() -> void:
	var node := FilterDataByTagNode.new()
	node.name = "filter_data_by_tag_test_node"
	node.settings = _make_settings("grass")
	node.inputs = []
	var ctx := FlowDataScript.EvaluationContext.new()
	var dummy := FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	assert_str(node.err).is_not_empty()

func test_multiple_data_tags_all_match_filter_still_routes_inside() -> void:
	var input := _make_data(PackedStringArray(["grass", "forest", "rock"]))
	var node := _run(input, _make_settings("rock"))
	assert_str(node.err).is_empty()
	var inside := _inside(node)
	var outside := _outside(node)
	assert_object(inside).is_equal(input)
	assert_int(outside.size()).is_equal(0)

func test_exact_tag_match_required_no_partial_matching() -> void:
	var input := _make_data(PackedStringArray(["grassland"]))
	var node := _run(input, _make_settings("grass"))
	assert_str(node.err).is_empty()
	var inside := _inside(node)
	var outside := _outside(node)
	assert_int(inside.size()).is_equal(0)
	assert_object(outside).is_equal(input)
