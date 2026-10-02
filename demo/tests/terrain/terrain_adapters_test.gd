# terrain_adapters_test.gd
# WP6: FlowTerrainAdapter and its adapters (HeightMapShape3D, heightmap Image,
# MeshInstance3D, Terrain3D and HTerrain by duck typing), FlowSurfaceLayers,
# edge clamping, detection. The plugin adapters run against the fakes in
# support/fake_terrain_plugins.gd only; nothing here touches the real plugins.
class_name TerrainAdaptersTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const Fakes = preload("res://tests/terrain/support/fake_terrain_plugins.gd")
const SampleTerrainLayersNode = preload("res://addons/flow_nodes_editor/nodes/sample_terrain_layers.gd")
const SampleTerrainLayersSettings = preload("res://addons/flow_nodes_editor/nodes/sample_terrain_layers_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	add_child(_owner)

func _add(n : Node) -> Node:
	_owner.add_child(n)
	return n

# --- HeightMapShape3D --------------------------------------------------------------------

## 3 x 3 map, h = i + j, placed at (5, 0, 5): local x = i - 1, z = j - 1.
func _heightmap_cs() -> CollisionShape3D:
	var hm := HeightMapShape3D.new()
	hm.map_width = 3
	hm.map_depth = 3
	hm.map_data = PackedFloat32Array([0, 1, 2, 1, 2, 3, 2, 3, 4])
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.position = Vector3(5, 0, 5)
	return cs

func test_heightmap_shape_adapter_heights_and_edge_clamp() -> void:
	var cs : CollisionShape3D = auto_free(_heightmap_cs())
	var a := FlowTerrainAdapter.for_node(cs)
	assert_object(a).is_instanceof(FlowHeightMapShapeTerrainAdapter)
	assert_bool(a.is_valid()).is_true()
	assert_float(a.get_height(5, 5)).is_equal_approx(2.0, 1e-5)
	assert_float(a.get_height(5.5, 5)).is_equal_approx(2.5, 1e-5)
	# Beyond the grid: clamped onto the nearest edge.
	assert_float(a.get_height(100, 5)).is_equal_approx(3.0, 1e-5)
	assert_float(a.get_height(-100, -100)).is_equal_approx(0.0, 1e-5)
	assert_float(a.get_height(100, 100)).is_equal_approx(4.0, 1e-5)
	# Normals at and beyond the edges are finite and equal to the edge cell's.
	var inner := Vector3(-1, 1, -1).normalized()
	for p in [Vector2(5, 5), Vector2(6, 6), Vector2(100, 100), Vector2(-100, 3), Vector2(4, -50)]:
		var n := a.get_normal(p.x, p.y)
		assert_bool(n.is_finite()).is_true()
		assert_float(n.distance_to(inner)).is_less(1e-4)
	assert_aabb_eq(a.get_bounds(), AABB(Vector3(4, 0, 4), Vector3(2, 4, 2)))

func assert_aabb_eq(a : AABB, b : AABB) -> void:
	assert_float(a.position.distance_to(b.position)).is_less(1e-4)
	assert_float(a.size.distance_to(b.size)).is_less(1e-4)

func test_heightmap_shape_to_surface_is_the_grid() -> void:
	var cs : CollisionShape3D = auto_free(_heightmap_cs())
	var a := FlowTerrainAdapter.for_node(cs)
	var surf := a.to_surface()
	assert_object(surf).is_instanceof(FlowHeightfieldSurface)
	assert_int(surf.content_hash()).is_equal(FlowHeightfieldSurface.from_heightmap_shape(cs.shape, cs.transform).content_hash())
	assert_object(surf.get_layers()).is_null()
	assert_object(a.to_surface()).is_same(surf)
	assert_int(a.get_layer_names().size()).is_equal(0)
	assert_float(a.get_layer_weight("grass", 5, 5)).is_equal(0.0)
	# vertical_tolerance option reaches the surface.
	var t := FlowTerrainAdapter.for_node(cs, {"vertical_tolerance": 0.5})
	assert_float(t.to_surface().vertical_tolerance).is_equal(0.5)

# --- heightmap Image + splat layers -------------------------------------------------------

func _random_image(w : int, h : int, seed_value : int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	return img

func test_image_adapter_splat_layers_match_sample_terrain_layers() -> void:
	# 64 x 64 heightmap, cell 2, centred: footprint [-63, 63]^2. Splat 37 x 23.
	var height := _random_image(64, 64, 1)
	var splat := _random_image(37, 23, 2)
	var layer := FlowTerrainSplatLayer.make("grass", splat, FlowTerrainSplatLayer.eChannel.G)
	var a := FlowImageTerrainAdapter.new(height, 2.0, 10.0, Transform3D.IDENTITY, true, {"splat_layers": [layer]})
	assert_bool(a.is_valid()).is_true()
	assert_array(Array(a.get_layer_names())).is_equal(["grass"])
	var positions := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 200:
		positions.append(Vector3(rng.randf_range(-80, 80), 0, rng.randf_range(-80, 80)))
	positions.append(Vector3(-63, 0, -63))
	positions.append(Vector3(63, 0, 63))
	# The same lookup through Sample Terrain Layers (textures, world XZ, Clamp).
	var entry := TerrainLayerEntry.new()
	entry.layer_name = "grass"
	entry.texture = ImageTexture.create_from_image(splat)
	var s := SampleTerrainLayersSettings.new()
	s.layers.append(entry)
	s.world_min = Vector2(-63, -63)
	s.world_max = Vector2(63, 63)
	s.value_channel = SampleTerrainLayersNodeSettings.eValueChannel.G
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, positions, FlowData.DataType.Vector)
	var node = SampleTerrainLayersNode.new()
	node.settings = s
	node.inputs = [d]
	var ctx := FlowDataScript.EvaluationContext.new()
	ctx.owner = _owner
	node.preExecute(ctx)
	node.execute(ctx)
	assert_str(node.err).is_empty()
	var expected : PackedFloat32Array = node.generated_bulks[0][0].getContainerChecked("layer_grass", FlowData.DataType.Float)
	var layers := a.to_surface().get_layers()
	assert_object(layers).is_not_null()
	for i in positions.size():
		assert_float(a.get_layer_weight("grass", positions[i].x, positions[i].z)).is_equal(expected[i])
		assert_float(layers.get_weight("grass", positions[i].x, positions[i].z)).is_equal(expected[i])

func test_image_adapter_heights_match_from_image() -> void:
	var height := _random_image(9, 7, 3)
	var xform := Transform3D(Basis(Vector3.UP, 0.3), Vector3(3, 1, -2))
	var a := FlowImageTerrainAdapter.new(height, 1.5, 4.0, xform, false)
	var ref := FlowHeightfieldSurface.from_image(height, 1.5, 4.0, xform, false)
	assert_int(a.to_surface().content_hash()).is_equal(ref.content_hash())
	var inside : Vector3 = xform * Vector3(4.2, 0, 3.1)
	assert_float(a.get_height(inside.x, inside.z)).is_equal_approx(ref.project_vertical(inside.x, inside.z).position.y, 1e-5)
	# Beyond the grid (rotated frame): finite edge values.
	var far : Vector3 = xform * Vector3(100, 0, -100)
	assert_bool(is_finite(a.get_height(far.x, far.z))).is_true()
	assert_bool(a.get_normal(far.x, far.z).is_finite()).is_true()
	assert_bool(FlowImageTerrainAdapter.new(null).is_valid()).is_false()

# --- MeshInstance3D -------------------------------------------------------------------------

func test_mesh_adapter() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	plane.subdivide_width = 3
	plane.subdivide_depth = 3
	var mi : MeshInstance3D = auto_free(MeshInstance3D.new())
	mi.mesh = plane
	mi.position = Vector3(0, 3, 0)
	var splat := _random_image(8, 8, 4)
	var a := FlowTerrainAdapter.for_node(mi, {"splat_layers": [FlowTerrainSplatLayer.make("dirt", splat)]})
	assert_object(a).is_instanceof(FlowMeshTerrainAdapter)
	assert_float(a.get_height(1, 2)).is_equal_approx(3.0, 1e-5)
	assert_float(a.get_height(50, -50)).is_equal_approx(3.0, 1e-5)
	assert_float(a.get_normal(50, -50).distance_to(Vector3.UP)).is_less(1e-5)
	var surf := a.to_surface()
	assert_object(surf).is_instanceof(FlowMeshSurface)
	assert_object(surf.get_layers()).is_not_null()
	assert_float(surf.get_layers().get_weight("dirt", -5, -5)).is_equal(splat.get_pixel(0, 0).r)
	assert_float(a.get_layer_weight("dirt", 5, 5)).is_equal(splat.get_pixel(7, 7).r)

# --- Terrain3D (fake) ------------------------------------------------------------------------

func _t3d(regions = null, with_assets : bool = true) -> Node:
	var t = Fakes.terrain3d(regions if regions != null else [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)], with_assets)
	return auto_free(t)

func test_terrain3d_detection_and_bounds() -> void:
	var t := _t3d()
	assert_bool(FlowTerrainAdapter.is_terrain3d(t)).is_true()
	assert_bool(FlowTerrainAdapter.is_hterrain(t)).is_false()
	assert_bool(FlowTerrainAdapter.is_terrain_plugin_node(t)).is_true()
	var a := FlowTerrainAdapter.for_node(t)
	assert_object(a).is_instanceof(FlowTerrain3DAdapter)
	assert_str(a.error).is_empty()
	# region_size 32 * vertex_spacing 2 = 64 per region; height range from data.
	assert_aabb_eq(a.get_bounds(), AABB(Vector3(-64, -7.6, -64), Vector3(128, 19.2, 128)))
	assert_float(a.get_sample_spacing()).is_equal(2.0)

func test_terrain3d_heights_normals_and_clamp() -> void:
	var a := FlowTerrainAdapter.for_node(_t3d())
	assert_float(a.get_height(0, 0)).is_equal_approx(2.0, 1e-5)
	assert_float(a.get_height(30, -20)).is_equal_approx(4.0, 1e-5)
	# Beyond the terrain: clamped onto the edge (x = 64).
	assert_float(a.get_height(1000, 0)).is_equal_approx(8.4, 1e-4)
	assert_float(a.get_height(-1000, -1000)).is_equal_approx(2.0 - 6.4 - 3.2, 1e-4)
	var expected := Vector3(-0.1, 1.0, -0.05).normalized()
	assert_float(a.get_normal(30, -20).distance_to(expected)).is_less(1e-5)
	assert_float(a.get_normal(1000, 1000).distance_to(expected)).is_less(1e-5)
	# Over a hole the plugin answers NaN: the height is NaN, the normal stays finite.
	assert_bool(is_nan(a.get_height(12, 12))).is_true()
	var hole_normal := a.get_normal(12, 12)
	assert_bool(hole_normal.is_finite()).is_true()
	assert_float(hole_normal.length()).is_equal_approx(1.0, 1e-5)

func test_terrain3d_layers_from_control_map() -> void:
	var a := FlowTerrainAdapter.for_node(_t3d())
	assert_array(Array(a.get_layer_names())).is_equal(["grass", "rock", "sand"])
	assert_float(a.get_layer_weight("grass", -5, -5)).is_equal(1.0)
	assert_float(a.get_layer_weight("rock", -5, -5)).is_equal(0.0)
	assert_float(a.get_layer_weight("rock", 5, 5)).is_equal_approx(0.75, 1e-6)
	assert_float(a.get_layer_weight("sand", 5, 5)).is_equal_approx(0.25, 1e-6)
	assert_float(a.get_layer_weight("sand", 12, 12)).is_equal(0.0)	# hole
	assert_float(a.get_layer_weight("unknown", 5, 5)).is_equal(0.0)
	# Renaming.
	var r := FlowTerrainAdapter.for_node(_t3d(), {"layer_names": PackedStringArray(["meadow", "", "beach"])})
	assert_array(Array(r.get_layer_names())).is_equal(["meadow", "rock", "beach"])
	assert_float(r.get_layer_weight("beach", 5, 5)).is_equal_approx(0.25, 1e-6)
	# Without an asset list the ids found on a probe lattice name the layers.
	var probed := FlowTerrainAdapter.for_node(_t3d(null, false))
	assert_array(Array(probed.get_layer_names())).is_equal(["texture_0", "texture_1", "texture_2"])

func test_terrain3d_to_surface() -> void:
	var a := FlowTerrainAdapter.for_node(_t3d())
	var surf : FlowHeightfieldSurface = a.to_surface()
	assert_object(surf).is_instanceof(FlowHeightfieldSurface)
	assert_int(surf.width).is_equal(65)
	assert_float(surf.cell_size).is_equal_approx(2.0, 1e-6)
	assert_float(surf.project_vertical(30, -20).position.y).is_equal_approx(4.0, 1e-4)
	# Holes stay holes.
	assert_bool(surf.project_vertical(12, 12).is_empty()).is_true()
	assert_float(surf.sample_density(Vector3(12, 0, 12))).is_equal(0.0)
	var layers := surf.get_layers()
	assert_array(Array(layers.names)).is_equal(["grass", "rock", "sand"])
	assert_float(layers.get_weight("rock", 5.5, 5.5)).is_equal_approx(0.75, 1e-6)
	assert_float(layers.get_weight("grass", -5.5, -5.5)).is_equal(1.0)
	# max_resolution caps the snapshot grid.
	var coarse : FlowHeightfieldSurface = FlowTerrainAdapter.for_node(_t3d(), {"max_resolution": 9}).to_surface()
	assert_int(coarse.width).is_equal(9)
	assert_float(coarse.cell_size).is_equal_approx(16.0, 1e-5)

func test_terrain3d_legacy_storage_and_explicit_bounds() -> void:
	var t : Node = auto_free(Fakes.FakeTerrain3DLegacy.new())
	var d = Fakes.FakeTerrain3DData.new()
	d.region_locations = [Vector2i(0, 0)]
	t.storage = d
	assert_bool(FlowTerrainAdapter.is_terrain3d(t)).is_true()
	var a := FlowTerrainAdapter.for_node(t)
	assert_bool(a.is_valid()).is_false()
	assert_str(a.error).contains("bounds")
	var b := FlowTerrainAdapter.for_node(t, {"bounds": AABB(Vector3(0, -10, 0), Vector3(20, 20, 30))})
	assert_bool(b.is_valid()).is_true()
	assert_float(b.get_height(5, 5)).is_equal_approx(2.75, 1e-5)
	assert_float(b.get_height(100, 5)).is_equal_approx(2.0 + 2.0 + 0.25, 1e-5)

# --- HTerrain (fake) ----------------------------------------------------------------------------

func _ht_xform() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3(2, 1, 2)), Vector3(10, 1, -5))

func test_hterrain_detection_heights_and_clamp() -> void:
	var t : Node = auto_free(Fakes.hterrain(17, _ht_xform()))
	assert_bool(FlowTerrainAdapter.is_hterrain(t)).is_true()
	assert_bool(FlowTerrainAdapter.is_terrain3d(t)).is_false()
	var a := FlowTerrainAdapter.for_node(t)
	assert_object(a).is_instanceof(FlowHTerrainAdapter)
	assert_str(a.error).is_empty()
	# World (14, -1) is cell (2, 2): raw 1.5, world 2.5.
	assert_float(a.get_height(14, -1)).is_equal_approx(2.5, 1e-5)
	assert_float(a.get_height(1000, -1)).is_equal_approx(1.0 + 8.0 + 0.5, 1e-5)
	assert_float(a.get_height(-1000, -1000)).is_equal_approx(1.0, 1e-5)
	var expected := Vector3(-0.25, 1.0, -0.125).normalized()
	for p in [Vector2(14, -1), Vector2(42, 27), Vector2(1000, 1000), Vector2(-50, 3)]:
		assert_float(a.get_normal(p.x, p.y).distance_to(expected)).is_less(1e-5)
	assert_aabb_eq(a.get_bounds(), AABB(Vector3(10, 1, -5), Vector3(32, 12, 32)))
	assert_int(int(t._data.calls.get("get_interpolated_height_at", 0))).is_greater(0)

func test_hterrain_to_surface_and_splat_layers() -> void:
	var t : Node = auto_free(Fakes.hterrain(17, _ht_xform()))
	var a := FlowTerrainAdapter.for_node(t)
	var surf : FlowHeightfieldSurface = a.to_surface()
	assert_object(surf).is_instanceof(FlowHeightfieldSurface)
	assert_int(surf.width).is_equal(17)
	assert_float(surf.project_vertical(14, -1).position.y).is_equal_approx(2.5, 1e-5)
	assert_int(int(t._data.calls.get("get_height_at", 0))).is_equal(17 * 17)
	var names := a.get_layer_names()
	assert_int(names.size()).is_equal(8)
	assert_str(names[0]).is_equal("texture_0")
	var map0 : Image = t._data.splat_maps[0]
	var map1 : Image = t._data.splat_maps[1]
	# World (14, -1) is cell (2, 2).
	assert_float(a.get_layer_weight("texture_0", 14, -1)).is_equal(map0.get_pixel(2, 2).r)
	assert_float(a.get_layer_weight("texture_1", 14, -1)).is_equal(map0.get_pixel(2, 2).g)
	assert_float(a.get_layer_weight("texture_2", 14, -1)).is_equal(map0.get_pixel(2, 2).b)
	assert_float(a.get_layer_weight("texture_7", 14, -1)).is_equal(map1.get_pixel(2, 2).a)
	# Beyond the terrain: clamped texel.
	assert_float(a.get_layer_weight("texture_0", 1000, -1)).is_equal(map0.get_pixel(16, 2).r)
	assert_float(surf.get_layers().get_weight("texture_1", 14, -1)).is_equal(map0.get_pixel(2, 2).g)
	# max_resolution coarsens the snapshot.
	var coarse : FlowHeightfieldSurface = FlowTerrainAdapter.for_node(t, {"max_resolution": 5}).to_surface()
	assert_int(coarse.width).is_equal(5)
	assert_float(coarse.cell_size).is_equal(4.0)

func test_hterrain_fallback_transform() -> void:
	var t : Node = auto_free(Fakes.FakeHTerrainNoInternal.new())
	var d = Fakes.FakeHTerrainData.new()
	t._data = d
	t.map_scale = Vector3(2, 1, 2)
	t.centered = true
	t.position = Vector3(10, 1, -5)
	var a := FlowTerrainAdapter.for_node(t)
	assert_bool(a.is_valid()).is_true()
	# Centred: cell (8, 8) sits at the node origin. Raw 0.5*8 + 0.25*8 = 6.
	assert_float(a.get_height(10, -5)).is_equal_approx(7.0, 1e-5)
	# No splat maps: no layers.
	assert_int(a.get_layer_names().size()).is_equal(0)

# --- FlowSurfaceLayers ---------------------------------------------------------------------------

func test_surface_layers_function_snapshot_and_merge() -> void:
	var fn := func(n : String, x : float, _z : float) -> float: return (x + 10.0) / 20.0 if n == "a" else 0.25
	var l := FlowSurfaceLayers.from_function(PackedStringArray(["a", "b"]), fn, Vector2(-10, -10), Vector2(10, 10), 5, 5)
	assert_float(l.get_weight("a", -10, 0)).is_equal(0.0)
	assert_float(l.get_weight("a", 10, 0)).is_equal(1.0)
	assert_float(l.get_weight("a", 2, 0)).is_equal(0.5)	# nearest-lower lattice point x = 0
	assert_float(l.get_weight("b", 100, 100)).is_equal(0.25)
	assert_array(Array(l.get_weights(10, 0))).is_equal([1.0, 0.25])
	var other := FlowSurfaceLayers.from_function(PackedStringArray(["b", "c"]), func(_n, _x, _z): return 1.0, Vector2(-10, -10), Vector2(10, 10), 2, 2)
	var m := FlowSurfaceLayers.merged(l, other)
	assert_array(Array(m.names)).is_equal(["a", "b", "c"])
	assert_float(m.get_weight("b", 0, 0)).is_equal(0.25)
	assert_float(m.get_weight("c", 0, 0)).is_equal(1.0)
	assert_int(l.content_hash()).is_not_equal(m.content_hash())
	assert_array(Array(l.renamed(PackedStringArray(["", "z"])).names)).is_equal(["a", "z"])

func test_layers_change_the_shape_hash_only_when_present() -> void:
	var cs : CollisionShape3D = auto_free(_heightmap_cs())
	var base := FlowHeightfieldSurface.from_heightmap_shape(cs.shape, cs.transform)
	var h := base.content_hash()
	base.attach_layers(null)
	assert_int(base.content_hash()).is_equal(h)
	var with := FlowHeightfieldSurface.from_heightmap_shape(cs.shape, cs.transform)
	with.attach_layers(FlowSurfaceLayers.from_function(PackedStringArray(["a"]), func(_n, _x, _z): return 1.0, Vector2.ZERO, Vector2.ONE, 2, 2))
	assert_int(with.content_hash()).is_not_equal(h)
	# Composites expose the surface operand's layers.
	var comp := FlowCompositeShape.new(FlowSpatial.Op.Intersection, FlowBoxVolume.from_aabb(AABB(Vector3(-50, -50, -50), Vector3(100, 100, 100))), with)
	assert_object(comp.get_layers()).is_same(with.get_layers())
	assert_object(FlowCompositeShape.new(FlowSpatial.Op.Difference, with, FlowSphereVolume.at(Vector3.ZERO, 1.0)).get_layers()).is_same(with.get_layers())

# --- detection ------------------------------------------------------------------------------------

func test_detect_single_terrain_explicit_path_and_errors() -> void:
	var none := FlowTerrainAdapter.detect(_owner)
	assert_object(none.adapter).is_null()
	assert_str(none.error).contains("no terrain node found")
	var t3d := _add(Fakes.terrain3d())
	var one := FlowTerrainAdapter.detect(_owner)
	assert_object(one.adapter).is_instanceof(FlowTerrain3DAdapter)
	assert_object(one.node).is_same(t3d)
	var ht := _add(Fakes.hterrain(9))
	var two := FlowTerrainAdapter.detect(_owner)
	assert_object(two.adapter).is_null()
	assert_str(two.error).contains("ambiguous")
	assert_str(two.error).contains(String(t3d.get_path()))
	assert_str(two.error).contains(String(ht.get_path()))
	# The explicit path wins over ambiguity.
	var explicit := FlowTerrainAdapter.detect(_owner, NodePath("HTerrain"))
	assert_object(explicit.adapter).is_instanceof(FlowHTerrainAdapter)
	# A group narrows auto-detection.
	ht.add_to_group("wp6_terrain")
	var grouped := FlowTerrainAdapter.detect(_owner, NodePath(), "wp6_terrain")
	assert_object(grouped.adapter).is_instanceof(FlowHTerrainAdapter)
	# Explicit path errors.
	assert_str(FlowTerrainAdapter.detect(_owner, NodePath("Missing")).error).contains("does not resolve")
	var plain := Node3D.new()
	plain.name = "Plain"
	_add(plain)
	assert_str(FlowTerrainAdapter.detect(_owner, NodePath("Plain")).error).contains("is not a terrain")
	# Built-in sources are accepted by path, not auto-detected.
	var cs := _heightmap_cs()
	cs.name = "Ground"
	_add(cs)
	assert_object(FlowTerrainAdapter.detect(_owner, NodePath("Ground")).adapter).is_instanceof(FlowHeightMapShapeTerrainAdapter)
	assert_str(FlowTerrainAdapter.detect(_owner, NodePath(), "missing_group").error).contains("no terrain node found in group")

func test_generated_nodes_are_not_detected() -> void:
	var t := Fakes.terrain3d()
	t.set_meta("flow_owner", {"component": 1, "node": "x"})
	_add(t)
	assert_str(FlowTerrainAdapter.detect(_owner).error).contains("no terrain node found")
