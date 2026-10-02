# create_points_test.gd
class_name CreatePointsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const H = preload("res://tests/nodes/support/point_node_harness.gd")
const NodeScript = preload("res://addons/flow_nodes_editor/nodes/create_points.gd")
const SettingsScript = preload("res://addons/flow_nodes_editor/nodes/create_points_settings.gd")
const EntryScript = preload("res://addons/flow_nodes_editor/nodes/create_points_point_settings.gd")

func _entry(pos : Vector3, attrs : Dictionary = {}):
	var e = EntryScript.new()
	e.position = pos
	e.attributes = attrs
	return e

func _settings(entries : Array):
	var s = SettingsScript.new()
	var typed : Array[FlowPointEntry] = []
	for e in entries:
		typed.append(e)
	s.points = typed
	return s

func _exec(settings, ctx = null) -> Dictionary:
	return H.exec(NodeScript, settings, [], ctx)

func _out(settings, ctx = null):
	var r := _exec(settings, ctx)
	assert_str(r.err).is_empty()
	return H.port(r)

func test_meta() -> void:
	var node = NodeScript.new()
	assert_array(node.meta_node.aliases).contains(["Create Points"])
	assert_int(node.meta_node.ins.size()).is_equal(0)
	H.dispose(node)

func test_writes_every_point_property() -> void:
	var e = _entry(Vector3(1, 2, 3))
	e.rotation = Vector3(0, 90, 0)
	e.scale = Vector3(2, 2, 2)
	e.bounds_min = Vector3(-1, 0, -1)
	e.bounds_max = Vector3(1, 3, 1)
	e.density = 0.4
	e.steepness = 0.7
	e.seed = 1234
	var out = _out(_settings([e, _entry(Vector3(5, 0, 0))]))
	assert_int(out.size()).is_equal(2)
	assert_vector(out.value_at("position", 0)).is_equal(Vector3(1, 2, 3))
	assert_vector(out.value_at("rotation", 0)).is_equal(Vector3(0, 90, 0))
	assert_vector(out.value_at("size", 0)).is_equal(Vector3(2, 2, 2))
	assert_vector(out.value_at("bounds_max", 0)).is_equal(Vector3(1, 3, 1))
	assert_float(out.value_at("density", 0)).is_equal_approx(0.4, 1e-6)
	assert_float(out.value_at("steepness", 0)).is_equal_approx(0.7, 1e-6)
	assert_int(out.value_at("seed", 0)).is_equal(1234)
	assert_float(out.value_at("density", 1)).is_equal(1.0)
	assert_vector(out.value_at("bounds_min", 1)).is_equal(Vector3(-0.5, -0.5, -0.5))

func test_derived_seed_is_position_based_and_order_independent() -> void:
	var a = _out(_settings([_entry(Vector3(1, 0, 0)), _entry(Vector3(2, 0, 0))]))
	var b = _out(_settings([_entry(Vector3(2, 0, 0)), _entry(Vector3(1, 0, 0))]))
	assert_int(a.value_at("seed", 0)).is_equal(b.value_at("seed", 1))
	assert_int(a.value_at("seed", 1)).is_equal(b.value_at("seed", 0))
	assert_int(a.value_at("seed", 0)).is_not_equal(a.value_at("seed", 1))
	assert_int(a.value_at("seed", 0)).is_equal(FlowDataScript.point_seed(Vector3(1, 0, 0), 12345))

func test_graph_seed_changes_derived_seeds_only() -> void:
	var explicit = _entry(Vector3(1, 0, 0))
	explicit.seed = 77
	var s = _settings([explicit, _entry(Vector3(2, 0, 0))])
	var a = _out(s, H.make_ctx(null, 0))
	var b = _out(s, H.make_ctx(null, 991))
	assert_int(a.value_at("seed", 0)).is_equal(77)
	assert_int(b.value_at("seed", 0)).is_equal(77)
	assert_int(a.value_at("seed", 1)).is_not_equal(b.value_at("seed", 1))

func test_attributes_union_defaults_and_numeric_promotion() -> void:
	var out = _out(_settings([
		_entry(Vector3.ZERO, {"kind": "tree", "weight": 2}),
		_entry(Vector3.ONE, {"weight": 0.5, "tint": Color.RED}),
	]))
	assert_str(out.value_at("kind", 0)).is_equal("tree")
	assert_str(out.value_at("kind", 1)).is_equal("")
	assert_int(out.streams["weight"].data_type).is_equal(FlowDataScript.DataType.Float)
	assert_float(out.value_at("weight", 0)).is_equal(2.0)
	assert_float(out.value_at("weight", 1)).is_equal(0.5)
	assert_object(out.value_at("tint", 1)).is_equal(Color.RED)

func test_attribute_type_conflict_is_an_error() -> void:
	var r := _exec(_settings([_entry(Vector3.ZERO, {"a": 1}), _entry(Vector3.ONE, {"a": "x"})]))
	assert_str(r.err).contains("mixed types")

func test_canonical_attribute_name_is_refused() -> void:
	var r := _exec(_settings([_entry(Vector3.ZERO, {"density": 0.5})]))
	assert_str(r.err).contains("point property")

func test_write_bounds_off() -> void:
	var s = _settings([_entry(Vector3.ZERO)])
	s.write_bounds = false
	var out = _out(s)
	assert_bool(out.hasStream("bounds_min")).is_false()
	assert_bool(out.hasStream("steepness")).is_false()

func test_empty_list_and_null_entries() -> void:
	var out = _out(_settings([]))
	assert_int(out.size()).is_equal(0)
	assert_bool(out.hasStream("position")).is_true()
	var s = SettingsScript.new()
	var typed : Array[FlowPointEntry] = [null, _entry(Vector3.ONE)]
	s.points = typed
	assert_int(_out(s).size()).is_equal(1)

func test_local_space_follows_owner() -> void:
	var owner := Node3D.new()
	owner.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(10, 0, 0))
	var e = _entry(Vector3(1, 0, 0))
	var s = _settings([e])
	s.coordinate_space = SettingsScript.eCoordinateSpace.Local
	var out = _out(s, H.make_ctx(owner))
	var p : Vector3 = out.value_at("position", 0)
	assert_float(p.x).is_equal_approx(10.0, 1e-4)
	assert_float(p.z).is_equal_approx(-1.0, 1e-4)
	assert_float(out.value_at("rotation", 0).y).is_equal_approx(90.0, 1e-3)
	# Owner-less Local evaluation falls back to world space.
	assert_vector(_out(s).value_at("position", 0)).is_equal(Vector3(1, 0, 0))
	owner.free()
