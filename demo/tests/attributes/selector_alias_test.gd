# selector_alias_test.gd
# UE-style $Name selector aliases in FlowData.Data.findStream / registerStream.
# Aliases only add names: every pre-existing selector must resolve exactly as
# before (checked at the end against a fixed set of selectors).
class_name SelectorAliasTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")

func _points() -> FlowData.Data:
	var D = FlowDataScript.DataType
	var d := FlowDataScript.Data.new()
	d.registerStream("position", PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]), D.Vector)
	d.registerStream("rotation", PackedVector3Array([Vector3(0, 90, 0), Vector3(10, 20, 30)]), D.Vector)
	d.registerStream("size", PackedVector3Array([Vector3(2, 2, 2), Vector3(1, 3, 1)]), D.Vector)
	d.registerStream("density", PackedFloat32Array([0.5, 1.0]), D.Float)
	d.registerStream("seed", PackedInt32Array([7, 9]), D.Int)
	d.registerStream("bounds_min", PackedVector3Array([-Vector3.ONE, -Vector3.ONE]), D.Vector)
	d.registerStream("bounds_max", PackedVector3Array([Vector3.ONE, Vector3(2, 2, 2)]), D.Vector)
	d.registerStream("steepness", PackedFloat32Array([0.25, 0.75]), D.Float)
	d.registerStream("color", PackedColorArray([Color.RED, Color.BLUE]), D.Color)
	d.registerStream("custom", PackedFloat32Array([3.0, 4.0]), D.Float)
	return d

func _same(d: FlowData.Data, alias: String, canonical: String) -> void:
	var a = d.findStream(alias)
	var c = d.findStream(canonical)
	assert_object(a).override_failure_message("%s did not resolve" % alias).is_not_null()
	assert_int(a.data_type).is_equal(c.data_type)
	assert_bool(a.container == c.container).override_failure_message("%s != %s" % [alias, canonical]).is_true()

func test_canonical_aliases() -> void:
	var d := _points()
	_same(d, "$Position", "position")
	_same(d, "$Rotation", "rotation")
	_same(d, "$Scale", "size")
	_same(d, "$Density", "density")
	_same(d, "$Seed", "seed")
	_same(d, "$BoundsMin", "bounds_min")
	_same(d, "$BoundsMax", "bounds_max")
	_same(d, "$Steepness", "steepness")
	_same(d, "$Color", "color")
	_same(d, "$Index", "index")

func test_aliases_are_case_insensitive_and_take_components() -> void:
	var d := _points()
	_same(d, "$position", "position")
	_same(d, "$DENSITY", "density")
	_same(d, "$Position.X", "position.X")
	_same(d, "$Scale.y", "size.y")
	_same(d, "$Color.a", "color.a")

func test_alias_helpers_used_by_value_readers() -> void:
	var d := _points()
	assert_float(d.first("$Density")).is_equal(0.5)
	assert_int(d.value_at("$Seed", 1)).is_equal(9)
	assert_object(d.container("$Scale")).is_not_null()

func test_writing_through_an_alias_writes_the_canonical_stream() -> void:
	var d := _points()
	assert_that(d.registerStream("$Density", PackedFloat32Array([0.1, 0.2]), FlowDataScript.DataType.Float)).is_null()
	assert_float(d.findStream("density").container[1]).is_equal_approx(0.2, 1e-6)
	assert_bool(d.hasStream("$Density")).is_false()
	# Canonical typing still applies through the alias.
	assert_that(d.registerStream("$Density", PackedVector3Array([Vector3.ONE, Vector3.ONE]), FlowDataScript.DataType.Vector)).is_not_null()

func test_a_literal_dollar_stream_wins_over_the_alias() -> void:
	var d := _points()
	d.registerStream("$Density", PackedFloat32Array([42.0, 43.0]), FlowDataScript.DataType.Float)
	# registerStream translated it to density (no literal stream existed yet)...
	assert_float(d.findStream("density").container[0]).is_equal(42.0)
	# ...but a stream that literally carries the name keeps resolving to itself.
	d.streams["$Seed"] = { "name": "$Seed", "data_type": FlowDataScript.DataType.Float, "container": PackedFloat32Array([1.0, 2.0]) }
	assert_int(d.findStream("$Seed").data_type).is_equal(FlowDataScript.DataType.Float)

func test_unknown_alias_resolves_to_nothing() -> void:
	var d := _points()
	assert_object(d.findStream("$NotAnAlias")).is_null()
	assert_object(d.container("$Steep")).is_null()
	assert_str(FlowDataScript.resolveSelectorAlias("Density")).is_empty()
	assert_str(FlowDataScript.resolveSelectorAlias("$Scale.z")).is_equal("size.z")

func test_existing_selectors_are_unchanged() -> void:
	var d := _points()
	d.set_data_attr("tag_value", 5)
	var expectations := {
		"position": PackedVector3Array([Vector3(1, 2, 3), Vector3(4, 5, 6)]),
		"position.x": PackedFloat32Array([1, 4]),
		"position.Z": PackedFloat32Array([3, 6]),
		"Yaw": PackedFloat32Array([90, 20]),
		"Pitch": PackedFloat32Array([0, 10]),
		"Roll": PackedFloat32Array([0, 30]),
		"index": PackedInt32Array([0, 1]),
		"@data.tag_value": PackedInt32Array([5]),
		"color.r": PackedFloat32Array([1, 0]),
		"custom": PackedFloat32Array([3, 4]),
	}
	for sel in expectations:
		var s = d.findStream(sel)
		assert_object(s).override_failure_message("selector %s" % sel).is_not_null()
		assert_bool(s.container == expectations[sel]).override_failure_message("selector %s gave %s" % [sel, str(s.container)]).is_true()
	# @last is the last registered stream
	assert_str(d.findStream("@last").name).is_equal("custom")
	assert_object(d.findStream("up")).is_not_null()
	assert_object(d.findStream("missing")).is_null()
