# conformance_harness_test.gd
# Self-test of the WP9 conformance harness: the fixture library is
# deterministic and complete, every check catches a node that breaks its
# contract on purpose (fakes/conformance_fake_node.gd), a well-behaved node
# passes, and the static scan finds and classifies hazards.
class_name ConformanceHarnessTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const Fixtures = preload("res://tests/executor/conformance/conformance_fixtures.gd")
const Harness = preload("res://tests/executor/conformance/conformance_harness.gd")
const StaticScan = preload("res://tests/executor/conformance/conformance_static_scan.gd")

const FAKE_PATH := "res://tests/executor/conformance/fakes/conformance_fake_node.gd"
const FAKE_OVERRIDE := { "primary": [ "points", "single", "empty", "volume_box" ] }

var _fake : Script = null


func before() -> void:
	_fake = load(FAKE_PATH)


func after_test() -> void:
	if _fake != null:
		_fake.behavior = "good"
		_fake.counter = 0
	FlowOutputCache.clear()


func _check_fake(behavior : String) -> Dictionary:
	_fake.behavior = behavior
	_fake.counter = 0
	return Harness.check_template("conformance_fake", _fake, FAKE_OVERRIDE)


# --- Fixtures ---------------------------------------------------------------------

func test_fixtures_are_deterministic_and_fresh() -> void:
	for id in Fixtures.all_ids():
		var a := Fixtures.build(id)
		var b := Fixtures.build(id)
		assert_object(a).override_failure_message("fixture %s" % id).is_not_null()
		assert_bool(a == b).override_failure_message("fixture %s must be a fresh object per build" % id).is_false()
		assert_int(a.content_hash()).override_failure_message("fixture %s content hash" % id).is_equal(b.content_hash())
		assert_int(Harness.data_digest(a)).override_failure_message("fixture %s digest" % id).is_equal(Harness.data_digest(b))


func test_point_fixture_carries_canonical_streams_and_every_type() -> void:
	var d := Fixtures.build("points")
	assert_int(d.size()).is_equal(Fixtures.POINT_COUNT)
	for canonical in FlowData.CANONICAL_ATTRIBUTE_TYPES:
		if canonical == FlowData.AttrRotationQuat:
			continue
		assert_bool(d.hasStreamOfType(canonical, FlowData.CANONICAL_ATTRIBUTE_TYPES[canonical])).override_failure_message(String(canonical)).is_true()
	var types := {}
	for stream in d.streams.values():
		types[int(stream.data_type)] = true
	for data_type in [ FlowData.DataType.Bool, FlowData.DataType.Int, FlowData.DataType.Float, FlowData.DataType.Vector,
			FlowData.DataType.String, FlowData.DataType.Resource, FlowData.DataType.Color, FlowData.DataType.Quaternion,
			FlowData.DataType.Vector2, FlowData.DataType.Vector4, FlowData.DataType.Transform, FlowData.DataType.Int64,
			FlowData.DataType.Double ]:
		assert_bool(types.has(data_type)).override_failure_message("missing DataType %d" % data_type).is_true()
	assert_int(Fixtures.build("single").size()).is_equal(1)
	assert_int(Fixtures.build("empty_schema").size()).is_equal(0)
	assert_int(Fixtures.build("empty_schema").streams.size()).is_equal(d.streams.size())


func test_shape_fixtures_cover_every_spatial_kind() -> void:
	var kinds := {}
	for id in [ "spline", "surface_polygon", "surface_heightfield", "surface_mesh", "volume_box", "volume_sphere", "composite" ]:
		var d := Fixtures.build(id)
		assert_bool(d.has_shape()).override_failure_message(id).is_true()
		assert_int(d.size()).override_failure_message(id).is_equal(0)
		kinds[int(d.kind)] = true
	for kind in [ FlowData.Kind.Spline, FlowData.Kind.Surface, FlowData.Kind.Volume ]:
		assert_bool(kinds.has(int(kind))).override_failure_message("kind %d" % kind).is_true()


func test_meta_fixtures() -> void:
	assert_int(Fixtures.build("tagged").tags.size()).is_equal(2)
	assert_bool(Fixtures.build("data_attrs").data_attrs.has("df_attr")).is_true()
	assert_int(int(Fixtures.build("attr_set").kind)).is_equal(FlowData.Kind.AttrSet)
	assert_bool(Fixtures.build("attr_set").hasStream("position")).is_false()


func test_cases_pair_secondary_inputs() -> void:
	assert_array(Harness.cases_for(0, {})).is_equal([ [ Fixtures.NO_INPUT, "" ] ])
	assert_int(Harness.cases_for(1, {}).size()).is_equal(Fixtures.PRIMARY.size())
	var two := Harness.cases_for(2, {})
	assert_int(two.size()).is_equal(Fixtures.PRIMARY.size() + Fixtures.SECONDARY.size() - 1)
	assert_array(two[0]).is_equal([ "points", Fixtures.SECONDARY[0] ])
	assert_array(two[two.size() - 1]).is_equal([ "points", Fixtures.SECONDARY[Fixtures.SECONDARY.size() - 1] ])


# --- Checks catch violations ---------------------------------------------------------

func test_well_behaved_node_passes_every_check() -> void:
	var result := _check_fake("good")
	assert_bool(result.main_thread).is_false()
	assert_bool(result.cacheable).is_true()
	for check in Harness.CHECKS:
		assert_str(result.checks[check].status).override_failure_message("%s: %s" % [ check, result.checks[check].detail ]).is_equal("pass")
	assert_int(result.cache_hits).is_equal(result.cases.size())
	assert_int(result.worked).is_greater(0)


func test_input_mutation_is_caught() -> void:
	for behavior in [ "mutate_tags", "mutate_stream" ]:
		var result := _check_fake(behavior)
		assert_str(result.checks.mutation.status).override_failure_message(behavior).is_equal("fail")
		assert_str(result.checks.mutation.detail).contains("input 0")


func test_nondeterministic_output_is_caught() -> void:
	var result := _check_fake("nondeterministic")
	assert_str(result.checks.determinism.status).is_equal("fail")


func test_nondeterministic_errors_are_caught() -> void:
	var result := _check_fake("nondeterministic_error")
	assert_str(result.checks.determinism.status).is_equal("fail")
	assert_str(result.checks.determinism.detail).contains("errors=")


func test_thread_dependent_output_is_caught() -> void:
	var result := _check_fake("thread_sensitive")
	assert_str(result.checks.determinism.status).is_equal("pass")
	assert_str(result.checks.thread.status).is_equal("fail")


func test_cache_dependent_output_is_caught() -> void:
	var result := _check_fake("cache_sensitive")
	assert_str(result.checks.thread.status).is_equal("pass")
	assert_str(result.checks.cache.status).is_equal("fail")


func test_main_thread_and_uncacheable_templates_skip_those_checks() -> void:
	var result := Harness.check_template("get_points_count", null, { "primary": [ "points" ] })
	assert_str(result.checks.thread.status).is_equal("pass")
	var main_result := Harness.check_template("print_string", null, { "primary": [ "single" ] })
	assert_str(main_result.checks.thread.status).is_equal("skip")
	assert_str(main_result.checks.cache.status).is_equal("skip")
	assert_str(main_result.checks.determinism.status).is_equal("pass")


func test_skip_rows_are_reported_with_their_reason() -> void:
	var result := Harness.check_template("grid", null, { "skip": "needs an asset" })
	assert_array(result.cases).is_empty()
	for check in Harness.CHECKS:
		assert_str(result.checks[check].status).is_equal("skip")
		assert_str(result.checks[check].detail).is_equal("needs an asset")


func test_digest_ignores_identity_of_equal_unsaved_resources() -> void:
	var a := FlowDataScript.Data.new()
	var b := FlowDataScript.Data.new()
	var curve_a := Curve.new()
	curve_a.add_point(Vector2(0, 1))
	var curve_b := Curve.new()
	curve_b.add_point(Vector2(0, 1))
	a.registerStream("curve", [ curve_a ], FlowData.DataType.Resource)
	b.registerStream("curve", [ curve_b ], FlowData.DataType.Resource)
	assert_int(Harness.data_digest(a)).is_equal(Harness.data_digest(b))
	curve_b.add_point(Vector2(1, 0))
	assert_int(Harness.data_digest(a)).is_not_equal(Harness.data_digest(b))


# --- Static scan ------------------------------------------------------------------------

func test_static_scan_finds_and_classifies_hazards() -> void:
	var source := "\n".join(PackedStringArray([
		"func execute(ctx):",
		"\tvar root = ctx.owner.get_tree().current_scene  # unguarded",
		"\tif Engine.is_editor_hint():",
		"\t\tvar ei = EditorInterface",
		"\t# RenderingServer in a comment is ignored",
		"\tvar s = \"get_tree() in a string\"",
		"\tvar n = randi()",
	]))
	var findings := StaticScan.scan_source("fake", "res://fake.gd", source)
	var by_label := {}
	for finding in findings:
		by_label[finding.label] = finding
	assert_bool(by_label.has("get_tree")).is_true()
	assert_bool(by_label.has("ctx.owner")).is_true()
	assert_str(by_label["get_tree"].guard).is_empty()
	assert_int(by_label["get_tree"].line).is_equal(2)
	assert_bool(by_label.has("EditorInterface")).is_true()
	assert_str(by_label["EditorInterface"].guard).contains("is_editor_hint")
	assert_bool(by_label.has("RenderingServer")).is_false()
	assert_bool(by_label.has("global RNG")).is_true()
	assert_bool(by_label["global RNG"].required).is_false()


func test_static_scan_skips_main_thread_templates_and_follows_extends() -> void:
	var findings := StaticScan.scan([ "scan_splines", "density_filter" ])
	for finding in findings:
		assert_str(finding.template).is_equal("density_filter")
	var chain := StaticScan.script_chain(load("res://addons/flow_nodes_editor/nodes/density_filter.gd"))
	assert_array(chain).contains([ "res://addons/flow_nodes_editor/nodes/attribute_filter_range.gd" ])
