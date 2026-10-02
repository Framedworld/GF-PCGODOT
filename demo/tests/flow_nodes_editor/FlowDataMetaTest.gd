# FlowDataMetaTest.gd
# Data.copy_meta_from / content_hash: the single place every Data rebuild goes through.
class_name FlowDataMetaTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

class FakeShape:
	extends RefCounted
	var tag : int = 1
	func content_hash() -> int:
		return tag

func _rich() -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.addCommonStreams(3)
	d.getVector3Container(FlowDataScript.AttrPosition)[1] = Vector3(1, 2, 3)
	d.tags = PackedStringArray(["a", "b"])
	d.kind = FlowDataScript.Kind.Surface
	d.set_data_attr("room", 7)
	d.shape = FakeShape.new()
	return d

func test_copy_meta_from_copies_tags_attrs_kind_and_shape() -> void:
	var src := _rich()
	var dst := FlowDataScript.Data.new().copy_meta_from(src)
	assert_array(Array(dst.tags)).is_equal(["a", "b"])
	assert_int(dst.kind).is_equal(FlowDataScript.Kind.Surface)
	assert_int(dst.get_data_attr("room")).is_equal(7)
	assert_object(dst.shape).is_same(src.shape)
	# tags and attributes are copies, not aliases
	dst.tags.append("c")
	assert_int(src.tags.size()).is_equal(2)

func test_duplicate_filter_and_empty_like_carry_shape() -> void:
	var src := _rich()
	assert_object(src.duplicate().shape).is_same(src.shape)
	assert_object(src.filter(PackedInt32Array([0, 2])).shape).is_same(src.shape)
	assert_object(src.emptyLike().shape).is_same(src.shape)

func test_content_hash_equal_for_equal_content() -> void:
	var a := _rich()
	var b := a.duplicate()
	assert_int(a.content_hash()).is_equal(b.content_hash())

func test_content_hash_changes_with_streams_tags_attrs_kind_and_shape() -> void:
	var base := _rich().content_hash()
	var m := _rich()
	m.getVector3Container(FlowDataScript.AttrPosition)[0] = Vector3(9, 9, 9)
	assert_bool(m.content_hash() != base).is_true()
	m = _rich(); m.tags = PackedStringArray(["a"])
	assert_bool(m.content_hash() != base).is_true()
	m = _rich(); m.set_data_attr("room", 8)
	assert_bool(m.content_hash() != base).is_true()
	m = _rich(); m.kind = FlowDataScript.Kind.Volume
	assert_bool(m.content_hash() != base).is_true()
	m = _rich(); m.shape.tag = 2
	assert_bool(m.content_hash() != base).is_true()

func test_content_hash_is_stable_across_instances() -> void:
	assert_int(_rich().content_hash()).is_equal(_rich().content_hash())
