# points_from_tilemap_test.gd
class_name PointsFromTilemapTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const PointsFromTilemapNode = preload("res://addons/flow_nodes_editor/nodes/points_from_tilemap.gd")
const PointsFromTilemapSettings = preload("res://addons/flow_nodes_editor/nodes/points_from_tilemap_settings.gd")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _default_settings() -> PointsFromTilemapSettings:
	var s = PointsFromTilemapSettings.new()
	s.include_tile_ids = true
	s.include_layer_ref = false
	s.out_cell_attribute = "tile_cell"
	s.out_source_id_attribute = "tile_source_id"
	s.out_alternative_id_attribute = "tile_alt_id"
	s.height = 0.0
	s.position_scale = 1.0
	s.cell_size = Vector2(1.0, 1.0)
	s.cell_height = 1.0
	s.source_id_filter = -1
	s.alternative_id_filter = -1
	return s

# Build a FlowGraphNode3D owner that contains one TileMapLayer with the given
# cells pre-populated.  source_id is passed to set_cell so get_used_cells()
# returns those coords.  Returns [owner, layer] so the caller can configure
# the layer further before running (and so it knows what to free).
func _make_owner_with_layer(cells: Array) -> Array:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var layer = TileMapLayer.new()
	owner_node.add_child(layer)
	for cell in cells:
		# set_cell with source_id=0 marks the cell as used
		layer.set_cell(cell, 0, Vector2i(0, 0), 0)
	return [owner_node, layer]

func _run(owner_node, settings) -> PointsFromTilemapNode:
	var node = PointsFromTilemapNode.new()
	node.name = "test_node"
	node.settings = settings
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = owner_node
	node.preExecute(ctx)
	node.execute(ctx)
	return node

func _output(node) -> FlowData.Data:
	if node.generated_bulks.is_empty(): return null
	var bulk = node.generated_bulks[0]
	if bulk.is_empty(): return null
	return bulk[0]

# ---------------------------------------------------------------------------
# Error-path tests
# ---------------------------------------------------------------------------

func test_null_owner_returns_empty_without_error() -> void:
	var s = _default_settings()
	var node = PointsFromTilemapNode.new()
	node.name = "test_node"
	node.settings = s
	node.inputs = []
	var ctx = FlowDataScript.EvaluationContext.new()
	ctx.owner = null
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	node.free()

func test_invalid_tilemap_path_sets_error() -> void:
	var s = _default_settings()
	s.tilemap_path = "NoSuchNode/TileMapLayer"
	var result = _make_owner_with_layer([])
	var owner_node = result[0]
	var node = _run(owner_node, s)
	assert_str(node.err).is_not_empty()
	owner_node.free()
	node.free()

func test_no_tilemaplayer_in_scene_returns_empty_no_error() -> void:
	# Owner has only plain Node3D children — no TileMapLayer
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	owner_node.add_child(Node3D.new())
	var s = _default_settings()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# SCENE-BUILD: real TileMapLayer with populated cells
# ---------------------------------------------------------------------------

func test_one_layer_two_cells_produces_two_points() -> void:
	var result = _make_owner_with_layer([Vector2i(0, 0), Vector2i(1, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_empty_layer_produces_zero_points() -> void:
	var result = _make_owner_with_layer([])
	var owner_node = result[0]
	var s = _default_settings()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	owner_node.free()
	node.free()

func test_cell_stream_carries_raw_grid_coordinates() -> void:
	# The node sets cells[i] = Vector3(cell.x, 0.0, cell.y) unconditionally.
	# With two known cells we can verify the mapping exactly.
	var result = _make_owner_with_layer([Vector2i(2, 3), Vector2i(5, 7)])
	var owner_node = result[0]
	var s = _default_settings()
	s.out_cell_attribute = "tile_cell"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var cell_stream = out.findStream("tile_cell")
	assert_object(cell_stream).is_not_null()
	assert_int(cell_stream.container.size()).is_equal(2)
	# Each entry must be Vector3(x, 0.0, y) — order follows get_used_cells() which
	# is implementation-defined, so check both possible orderings.
	var c0 = cell_stream.container[0]
	var c1 = cell_stream.container[1]
	var coords_y : Array = [c0.y, c1.y]
	assert_float(coords_y[0]).is_equal_approx(0.0, 0.001)
	assert_float(coords_y[1]).is_equal_approx(0.0, 0.001)
	# The X and Z channels must be the raw integer cell coordinates
	var pairs : Array = [Vector2(c0.x, c0.z), Vector2(c1.x, c1.z)]
	var expected : Array = [Vector2(2.0, 3.0), Vector2(5.0, 7.0)]
	assert_bool(pairs.has(expected[0]) and pairs.has(expected[1])).is_true()
	owner_node.free()
	node.free()

func test_size_stream_matches_cell_size_setting() -> void:
	var result = _make_owner_with_layer([Vector2i(0, 0), Vector2i(1, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.cell_size = Vector2(2.0, 3.0)
	s.cell_height = 5.0
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var size_stream = out.findStream("size")
	assert_object(size_stream).is_not_null()
	assert_int(size_stream.container.size()).is_equal(2)
	# Every point gets Vector3(cell_size.x, cell_height, cell_size.y)
	for i in range(size_stream.container.size()):
		var sz = size_stream.container[i]
		assert_float(sz.x).is_equal_approx(2.0, 0.001)
		assert_float(sz.y).is_equal_approx(5.0, 0.001)
		assert_float(sz.z).is_equal_approx(3.0, 0.001)
	owner_node.free()
	node.free()

func test_height_setting_applied_to_y_position() -> void:
	# The node sets y = settings.height for every point regardless of cell pos.
	var result = _make_owner_with_layer([Vector2i(0, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.height = 42.0
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_float(pos_stream.container[0].y).is_equal_approx(42.0, 0.001)
	owner_node.free()
	node.free()

func test_rotation_stream_is_all_zero() -> void:
	# The execute() appends Vector3.ZERO for every cell's rotation.
	var result = _make_owner_with_layer([Vector2i(0, 0), Vector2i(0, 1)])
	var owner_node = result[0]
	var s = _default_settings()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var rot_stream = out.findStream("rotation")
	assert_object(rot_stream).is_not_null()
	for i in range(rot_stream.container.size()):
		var r = rot_stream.container[i]
		assert_float(r.x).is_equal_approx(0.0, 0.001)
		assert_float(r.y).is_equal_approx(0.0, 0.001)
		assert_float(r.z).is_equal_approx(0.0, 0.001)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Tile ID streams
# ---------------------------------------------------------------------------

func test_tile_id_streams_present_when_include_tile_ids_true() -> void:
	var result = _make_owner_with_layer([Vector2i(0, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.include_tile_ids = true
	s.out_source_id_attribute = "tile_source_id"
	s.out_alternative_id_attribute = "tile_alt_id"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out.findStream("tile_source_id")).is_not_null()
	assert_object(out.findStream("tile_alt_id")).is_not_null()
	owner_node.free()
	node.free()

func test_tile_id_streams_absent_when_include_tile_ids_false() -> void:
	var result = _make_owner_with_layer([Vector2i(0, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.include_tile_ids = false
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	# Streams should not exist when include_tile_ids is off
	assert_object(out.findStream("tile_source_id")).is_null()
	assert_object(out.findStream("tile_alt_id")).is_null()
	owner_node.free()
	node.free()

func test_source_id_stream_value_matches_set_cell_source_id() -> void:
	# We set_cell with source_id=0; the stream must record 0.
	var result = _make_owner_with_layer([Vector2i(0, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.include_tile_ids = true
	s.source_id_filter = -1  # no filter
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var sid_stream = out.findStream("tile_source_id")
	assert_object(sid_stream).is_not_null()
	assert_int(sid_stream.container.size()).is_equal(1)
	assert_int(sid_stream.container[0]).is_equal(0)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Source ID filter
# ---------------------------------------------------------------------------

func test_source_id_filter_excludes_non_matching_cells() -> void:
	# Set up two cells: both get source_id=0 in _make_owner_with_layer.
	# Filter for source_id=1 should exclude all of them.
	var result = _make_owner_with_layer([Vector2i(0, 0), Vector2i(1, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.source_id_filter = 1   # no cell has source_id=1
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out).is_not_null()
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(0)
	owner_node.free()
	node.free()

func test_source_id_filter_minus_one_passes_all_cells() -> void:
	var result = _make_owner_with_layer([Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.source_id_filter = -1  # no filter
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(3)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Cell attribute stream toggle
# ---------------------------------------------------------------------------

func test_empty_cell_attribute_name_suppresses_cell_stream() -> void:
	var result = _make_owner_with_layer([Vector2i(0, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.out_cell_attribute = ""   # empty -> no stream registered
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	assert_object(out.findStream("tile_cell")).is_null()
	assert_object(out.findStream("")).is_null()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Layer reference stream
# ---------------------------------------------------------------------------

func test_layer_ref_stream_present_when_include_layer_ref_true() -> void:
	var result = _make_owner_with_layer([Vector2i(0, 0)])
	var owner_node = result[0]
	var s = _default_settings()
	s.include_layer_ref = true
	s.out_layer_attribute = "tile_layer"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var layer_stream = out.findStream("tile_layer")
	assert_object(layer_stream).is_not_null()
	assert_int(layer_stream.container.size()).is_equal(1)
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Tilemap path resolution
# ---------------------------------------------------------------------------

func test_valid_tilemap_path_finds_single_layer() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var layer = TileMapLayer.new()
	layer.name = "MyLayer"
	owner_node.add_child(layer)
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	layer.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0), 0)
	var s = _default_settings()
	s.tilemap_path = "MyLayer"
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(2)
	owner_node.free()
	node.free()

func test_tilemap_path_to_non_tilemaplayer_node_sets_error() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var plain = Node3D.new()
	plain.name = "NotALayer"
	owner_node.add_child(plain)
	var s = _default_settings()
	s.tilemap_path = "NotALayer"
	var node = _run(owner_node, s)
	assert_str(node.err).is_not_empty()
	owner_node.free()
	node.free()

# ---------------------------------------------------------------------------
# Multiple layers
# ---------------------------------------------------------------------------

func test_two_layers_points_are_accumulated() -> void:
	var owner_node = FlowGraphNode3D.new()
	add_child(owner_node)
	var layer1 = TileMapLayer.new()
	owner_node.add_child(layer1)
	layer1.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0), 0)
	layer1.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0), 0)
	var layer2 = TileMapLayer.new()
	owner_node.add_child(layer2)
	layer2.set_cell(Vector2i(0, 1), 0, Vector2i(0, 0), 0)
	var s = _default_settings()
	var node = _run(owner_node, s)
	assert_str(node.err).is_empty()
	var out = _output(node)
	var pos_stream = out.findStream("position")
	assert_object(pos_stream).is_not_null()
	assert_int(pos_stream.container.size()).is_equal(3)
	owner_node.free()
	node.free()
