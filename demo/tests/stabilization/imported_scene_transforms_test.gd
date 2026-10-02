# WP11 item 2: points_from_imported_scene (and load_alembic_file) must apply
# the scene's own node transforms. The instance never enters the tree, so the
# node accumulates local transforms while walking.
class_name ImportedSceneTransformsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const ImportedScene = preload("res://addons/flow_nodes_editor/nodes/points_from_imported_scene.gd")
const Alembic = preload("res://addons/flow_nodes_editor/nodes/load_alembic_file.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/points_from_imported_scene_settings.gd")

const SCENE_PATH := "user://wp11_imported_scene_transforms.tscn"

var _scene_root_xform := Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(10, 0, 0))
var _pivot_xform := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(30.0)).scaled(Vector3(2, 2, 2)), Vector3(0, 3, 0))
var _mesh_xform := Transform3D(Basis(Vector3.FORWARD, deg_to_rad(45.0)), Vector3(4, 0, -1))

func before() -> void:
	# root (Node3D, rotated and offset)
	#   Pivot (Node3D, rotated, scaled, offset)
	#     Rock (MeshInstance3D, offset and rotated, BoxMesh 1x2x3)
	#   Plain (Node)                      <- breaks the Node3D chain, as in the tree
	#     Loose (MeshInstance3D, offset)
	#   Top (MeshInstance3D, top_level)   <- ignores its parents, as in the tree
	var root := Node3D.new()
	root.name = "Root"
	root.transform = _scene_root_xform
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.transform = _pivot_xform
	root.add_child(pivot)
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	var box := BoxMesh.new()
	box.size = Vector3(1, 2, 3)
	rock.mesh = box
	rock.transform = _mesh_xform
	pivot.add_child(rock)
	var plain := Node.new()
	plain.name = "Plain"
	root.add_child(plain)
	var loose := MeshInstance3D.new()
	loose.name = "Loose"
	loose.mesh = BoxMesh.new()
	loose.position = Vector3(0, 0, 7)
	plain.add_child(loose)
	var top := MeshInstance3D.new()
	top.name = "Top"
	top.mesh = BoxMesh.new()
	top.top_level = true
	top.position = Vector3(-5, 1, 0)
	pivot.add_child(top)
	for n in [pivot, rock, plain, loose, top]:
		n.owner = root
	var packed := PackedScene.new()
	assert_int(packed.pack(root)).is_equal(OK)
	assert_int(ResourceSaver.save(packed, SCENE_PATH)).is_equal(OK)
	root.free()

func after() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCENE_PATH))

func _settings():
	var s = SettingsScript.new()
	s.asset_path = SCENE_PATH
	s.include_source_name = true
	return s

## The reference: the same scene inside the running tree, read through
## global_transform, the way the node meant to read it.
func _tree_reference() -> Dictionary:
	var inst : Node = (load(SCENE_PATH) as PackedScene).instantiate()
	var holder := Node3D.new()
	add_child(holder)
	holder.add_child(inst)
	var ref := {}
	for name in ["Rock", "Loose", "Top"]:
		var mi : MeshInstance3D = inst.find_child(name, true, false)
		var tr := mi.global_transform
		var aabb := mi.mesh.get_aabb()
		ref[name] = {
			"position": tr * (aabb.position + aabb.size * 0.5),
			"rotation": FlowDataScript.basisToEuler(tr.basis),
			"size": aabb.size * tr.basis.get_scale().abs(),
		}
	holder.free()
	return ref

func _by_name(out) -> Dictionary:
	var rows := {}
	for i in range(out.size()):
		rows[String(out.value_at("source_node_name", i))] = {
			"position": out.value_at("position", i),
			"rotation": out.value_at("rotation", i),
			"size": out.value_at("size", i),
		}
	return rows

func _check(node_script) -> void:
	var r := H.exec(node_script, _settings(), [])
	assert_str(r.err).is_empty()
	var rows := _by_name(H.port(r, 0))
	var ref := _tree_reference()
	assert_int(rows.size()).is_equal(3)
	for name in ref:
		assert_bool(rows.has(name)).is_true()
		assert_vector(rows[name].position).is_equal_approx(ref[name].position, Vector3.ONE * 1e-4)
		assert_vector(rows[name].rotation).is_equal_approx(ref[name].rotation, Vector3.ONE * 1e-3)
		assert_vector(rows[name].size).is_equal_approx(ref[name].size, Vector3.ONE * 1e-4)

func test_nested_mesh_uses_accumulated_transform() -> void:
	var r := H.exec(ImportedScene, _settings(), [])
	assert_str(r.err).is_empty()
	var rows := _by_name(H.port(r, 0))
	# Known value, independent of the tree: root * pivot * mesh applied to the
	# box centre (the BoxMesh AABB is centred on the origin).
	var expected : Vector3 = (_scene_root_xform * _pivot_xform * _mesh_xform) * Vector3.ZERO
	assert_vector(rows["Rock"].position).is_equal_approx(expected, Vector3.ONE * 1e-4)
	assert_vector(rows["Rock"].size).is_equal_approx(Vector3(2, 4, 6), Vector3.ONE * 1e-4)
	# A plain Node parent breaks the chain; a top_level mesh ignores its parents.
	assert_vector(rows["Loose"].position).is_equal_approx(Vector3(0, 0, 7), Vector3.ONE * 1e-4)
	assert_vector(rows["Top"].position).is_equal_approx(Vector3(-5, 1, 0), Vector3.ONE * 1e-4)

func test_points_from_imported_scene_matches_tree_transforms() -> void:
	_check(ImportedScene)

func test_load_alembic_file_matches_tree_transforms() -> void:
	_check(Alembic)
