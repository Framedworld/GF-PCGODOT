# assets_test.gd
class_name AssetsTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const AssetsNode = preload("res://addons/flow_nodes_editor/nodes/assets.gd")
const AssetsSettings = preload("res://addons/flow_nodes_editor/nodes/assets_settings.gd")

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# Build a FlowUserResourceData subclass at runtime with a single float export.
# Returns the Script object; call .new() on it to get an instance.
func _make_float_asset_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends FlowUserResourceData
@export var weight: float = 0.0
"""
	s.reload()
	return s

# Build a script with one int, one bool, one String and one Vector3 export.
func _make_multi_asset_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends FlowUserResourceData
@export var count: int = 0
@export var enabled: bool = false
@export var label: String = ""
@export var offset: Vector3 = Vector3.ZERO
"""
	s.reload()
	return s

# Build a script with a Color export (maps to DataType.Vector as rgb).
func _make_color_asset_script() -> GDScript:
	var s = GDScript.new()
	s.source_code = """
extends FlowUserResourceData
@export var tint: Color = Color.WHITE
"""
	s.reload()
	return s

func _run(settings) -> AssetsNode:
	var node = AssetsNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	var dummy = FlowGraphNode3D.new()
	ctx.owner = dummy
	node.preExecute(ctx)
	node.execute(ctx)
	dummy.free()
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_empty_assets_no_error() -> void:
	var s = AssetsSettings.new()
	s.assets.clear()
	var node = _run(s)
	assert_str(node.err).is_empty()
	# Output data exists even when there are no assets (no streams, but no crash).
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_all_null_entries_no_error() -> void:
	# Null entries must be skipped without a crash or error.
	var s = AssetsSettings.new()
	s.assets.clear()
	s.assets.append(null)
	s.assets.append(null)
	s.assets.append(null)
	var node = _run(s)
	assert_str(node.err).is_empty()
	node.free()

func test_mixed_null_and_real_entries_no_error() -> void:
	var scr = _make_float_asset_script()
	var a = scr.new()
	a.weight = 1.5
	var s = AssetsSettings.new()
	# index 0 = null (skipped), index 1 = real asset
	s.assets.clear()
	s.assets.append(null)
	s.assets.append(a)
	var node = _run(s)
	assert_str(node.err).is_empty()
	node.free()

# ---------------------------------------------------------------------------
# Float property: two assets, verify stream length and values
# ---------------------------------------------------------------------------

func test_float_stream_values() -> void:
	var scr = _make_float_asset_script()
	var a0 = scr.new()
	a0.weight = 0.25
	var a1 = scr.new()
	a1.weight = 0.75

	var s = AssetsSettings.new()
	s.assets.clear()
	s.assets.append(a0)
	s.assets.append(a1)

	var node = _run(s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var stream = out.findStream("weight")
	assert_object(stream).is_not_null()

	# Container must be a PackedFloat32Array of length 2.
	var container = stream.container
	assert_int(container.size()).is_equal(2)
	assert_float(float(container[0])).is_equal_approx(0.25, 0.001)
	assert_float(float(container[1])).is_equal_approx(0.75, 0.001)

	node.free()

# ---------------------------------------------------------------------------
# Multi-type properties: int, bool, String, Vector3 all in one pass
# ---------------------------------------------------------------------------

func test_multi_type_streams_produced() -> void:
	var scr = _make_multi_asset_script()
	var a0 = scr.new()
	a0.count   = 3
	a0.enabled = true
	a0.label   = "hello"
	a0.offset  = Vector3(1.0, 2.0, 3.0)

	var a1 = scr.new()
	a1.count   = 7
	a1.enabled = false
	a1.label   = "world"
	a1.offset  = Vector3(4.0, 5.0, 6.0)

	var s = AssetsSettings.new()
	s.assets.clear()
	s.assets.append(a0)
	s.assets.append(a1)

	var node = _run(s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	# ----- int stream -----
	var count_stream = out.findStream("count")
	assert_object(count_stream).is_not_null()
	var count_c = count_stream.container
	assert_int(count_c.size()).is_equal(2)
	assert_int(int(count_c[0])).is_equal(3)
	assert_int(int(count_c[1])).is_equal(7)

	# ----- bool stream (stored as PackedByteArray: 0/1) -----
	var enabled_stream = out.findStream("enabled")
	assert_object(enabled_stream).is_not_null()
	var enabled_c = enabled_stream.container
	assert_int(enabled_c.size()).is_equal(2)
	assert_int(int(enabled_c[0])).is_equal(1)   # true -> 1
	assert_int(int(enabled_c[1])).is_equal(0)   # false -> 0

	# ----- String stream -----
	var label_stream = out.findStream("label")
	assert_object(label_stream).is_not_null()
	var label_c = label_stream.container
	assert_int(label_c.size()).is_equal(2)
	assert_str(str(label_c[0])).is_equal("hello")
	assert_str(str(label_c[1])).is_equal("world")

	# ----- Vector3 stream -----
	var offset_stream = out.findStream("offset")
	assert_object(offset_stream).is_not_null()
	var offset_c = offset_stream.container
	assert_int(offset_c.size()).is_equal(2)
	assert_vector(offset_c[0]).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3.ONE * 0.001)
	assert_vector(offset_c[1]).is_equal_approx(Vector3(4.0, 5.0, 6.0), Vector3.ONE * 0.001)

	node.free()

# ---------------------------------------------------------------------------
# Color property: must be converted to Vector3(r, g, b)
# ---------------------------------------------------------------------------

func test_color_mapped_to_vector3_stream() -> void:
	var scr = _make_color_asset_script()
	var a0 = scr.new()
	a0.tint = Color(1.0, 0.0, 0.5, 1.0)
	var a1 = scr.new()
	a1.tint = Color(0.0, 1.0, 0.0, 1.0)

	var s = AssetsSettings.new()
	s.assets.clear()
	s.assets.append(a0)
	s.assets.append(a1)

	var node = _run(s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	# Color -> DataType.Vector -> PackedVector3Array, r/g/b components only.
	var tint_stream = out.findStream("tint")
	assert_object(tint_stream).is_not_null()
	var tint_c = tint_stream.container
	assert_int(tint_c.size()).is_equal(2)
	assert_vector(tint_c[0]).is_equal_approx(Vector3(1.0, 0.0, 0.5), Vector3.ONE * 0.001)
	assert_vector(tint_c[1]).is_equal_approx(Vector3(0.0, 1.0, 0.0), Vector3.ONE * 0.001)

	node.free()

# ---------------------------------------------------------------------------
# Stream count: each distinct exported property becomes exactly one stream
# ---------------------------------------------------------------------------

func test_stream_count_matches_property_count() -> void:
	var scr = _make_multi_asset_script()
	var a0 = scr.new()
	var a1 = scr.new()

	var s = AssetsSettings.new()
	s.assets.clear()
	s.assets.append(a0)
	s.assets.append(a1)

	var node = _run(s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()
	# multi script has: count, enabled, label, offset -> 4 streams
	assert_bool(out.hasStream("count")).is_true()
	assert_bool(out.hasStream("enabled")).is_true()
	assert_bool(out.hasStream("label")).is_true()
	assert_bool(out.hasStream("offset")).is_true()

	node.free()

# ---------------------------------------------------------------------------
# Null fallback: a null entry at position i must write the default value for
# every stream at that index (not crash or leave the slot uninitialised).
# The code calls _asset_value which returns default_value for null assets.
# ---------------------------------------------------------------------------

func test_null_entry_writes_default_float() -> void:
	var scr = _make_float_asset_script()
	var a1 = scr.new()
	a1.weight = 9.0

	var s = AssetsSettings.new()
	# index 0 = null, index 1 = real asset
	s.assets.clear()
	s.assets.append(null)
	s.assets.append(a1)

	var node = _run(s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var stream = out.findStream("weight")
	assert_object(stream).is_not_null()
	var container = stream.container
	assert_int(container.size()).is_equal(2)
	# Null entry uses default 0.0 (per _asset_value fallback).
	assert_float(float(container[0])).is_equal_approx(0.0, 0.001)
	assert_float(float(container[1])).is_equal_approx(9.0, 0.001)

	node.free()

# ---------------------------------------------------------------------------
# Trace flag must not error
# ---------------------------------------------------------------------------

func test_trace_flag_does_not_error() -> void:
	var scr = _make_float_asset_script()
	var a = scr.new()
	a.weight = 1.0

	var s = AssetsSettings.new()
	s.assets.clear()
	s.assets.append(a)
	s.trace = true

	var node = _run(s)
	assert_str(node.err).is_empty()
	node.free()

# ---------------------------------------------------------------------------
# Single asset produces streams of length 1
# ---------------------------------------------------------------------------

func test_single_asset_stream_length_one() -> void:
	var scr = _make_float_asset_script()
	var a = scr.new()
	a.weight = 42.0

	var s = AssetsSettings.new()
	s.assets.clear()
	s.assets.append(a)

	var node = _run(s)
	assert_str(node.err).is_empty()

	var out = _output(node)
	assert_object(out).is_not_null()

	var stream = out.findStream("weight")
	assert_object(stream).is_not_null()
	assert_int(stream.container.size()).is_equal(1)
	assert_float(float(stream.container[0])).is_equal_approx(42.0, 0.001)

	node.free()
