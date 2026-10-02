# get_property_from_object_path_test.gd
class_name GetPropertyFromObjectPathTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/get_property_from_object_path.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/get_property_from_object_path_settings.gd")

const RES_PATH := "user://wp4b_get_property_box.tres"

var _level : Node3D
var _gen : FlowGraphNode3D

func before_test() -> void:
	_level = Node3D.new()
	_level.name = "Level"
	add_child(_level)
	_gen = FlowGraphNode3D.new()
	_gen.name = "Gen"
	_level.add_child(_gen)
	_gen.owner = _level
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	var box := BoxMesh.new()
	box.size = Vector3(2, 3, 4)
	rock.mesh = box
	rock.visible = false
	_level.add_child(rock)
	rock.owner = _level
	rock.unique_name_in_owner = true
	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.light_color = Color(1, 0.5, 0.25)
	_gen.add_child(lamp)
	var saved := BoxMesh.new()
	saved.size = Vector3(7, 8, 9)
	ResourceSaver.save(saved, RES_PATH)

func after_test() -> void:
	_level.free()
	if FileAccess.file_exists(RES_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RES_PATH))

func _settings(paths : Array, props : Array):
	var s = SettingsScript.new()
	s.object_paths = PackedStringArray(paths)
	var typed : Array[StringName] = []
	for p in props:
		typed.append(StringName(p))
	s.property_paths = typed
	return s

func _exec(settings, owner = _gen) -> Dictionary:
	return H.exec(NodeScript, settings, [], H.make_ctx(owner))

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Get Property From Object Path"])
	assert_bool(node.meta_node.scans_scene).is_true()
	H.dispose(node)

func test_reads_node_properties_by_relative_and_unique_paths() -> void:
	var r := _exec(_settings(["%Rock", "Lamp", "../Rock"], ["visible", "mesh:size", "light_color", "name"]))
	var out = H.port(r, 0)
	assert_int(out.size()).is_equal(3)
	assert_array(Array(out.container("object_path"))).is_equal(["%Rock", "Lamp", "../Rock"])
	assert_bool(out.value_at("visible", 0)).is_false()
	assert_bool(out.value_at("visible", 1)).is_true()
	assert_vector(out.value_at("size", 0)).is_equal(Vector3(2, 3, 4))
	assert_vector(out.value_at("size", 1)).is_equal(Vector3.ZERO)
	assert_object(out.value_at("light_color", 1)).is_equal(Color(1, 0.5, 0.25))
	# StringName is read as String, like Scan Nodes.
	assert_int(out.streams["name"].data_type).is_equal(FlowDataScript.DataType.String)
	assert_str(out.value_at("name", 2)).is_equal("Rock")
	assert_int(out.kind).is_equal(FlowDataScript.Kind.AttrSet)
	assert_str(r.err).is_empty()

func test_reads_resource_without_owner() -> void:
	var r := _exec(_settings([RES_PATH], ["size"]), null)
	assert_str(r.err).is_empty()
	assert_vector(H.port(r, 0).value_at("size", 0)).is_equal(Vector3(7, 8, 9))

func test_node_path_without_owner_reports_owner_error() -> void:
	var r := _exec(_settings(["%Rock", RES_PATH], ["size"]), null)
	assert_str(r.err).contains("needs an owner node")
	assert_int(H.port(r, 0).size()).is_equal(1)

func test_unresolved_object_and_missing_property_are_errors() -> void:
	var r := _exec(_settings(["Nope", "%Rock"], ["visible", "not_a_property"]))
	assert_str(r.err).contains("Object 'Nope' not found")
	assert_str(r.err).contains("not_a_property")
	var out = H.port(r, 0)
	assert_int(out.size()).is_equal(1)
	assert_bool(out.hasStream("visible")).is_true()

func test_path_attribute_can_be_disabled_and_empty_list() -> void:
	var s = _settings(["%Rock"], ["visible"])
	s.path_attribute = ""
	var out = H.port(_exec(s), 0)
	assert_bool(out.hasStream("object_path")).is_false()
	assert_int(out.size()).is_equal(1)
	var empty := _exec(_settings([], ["visible"]))
	assert_str(empty.err).is_empty()
	assert_int(H.port(empty, 0).size()).is_equal(0)

func test_fingerprint_tracks_property_values() -> void:
	var node = NodeScript.new()
	node.settings = _settings(["%Rock"], ["visible"])
	var ctx = H.make_ctx(_gen)
	var a = node.computeSceneFingerprint(ctx)
	(_level.get_node("Rock") as Node3D).visible = true
	var b = node.computeSceneFingerprint(ctx)
	assert_bool(a == b).is_false()
	H.dispose(node)
