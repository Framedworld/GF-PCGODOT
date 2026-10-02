# terrain_nodes_test.gd
# WP6 node integration: get_surface_data (source = Terrain, auto-detection,
# explicit path, ambiguity, splat layers on HeightmapImage), surface_sampler
# writing terrain layer weights, sample_terrain_layers reading an adapter, and
# the scene fingerprints. Plugin terrains are the fakes of
# support/fake_terrain_plugins.gd.
class_name TerrainNodesTest extends GdUnitTestSuite

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const S = preload("res://tests/spatial/support/spatial_test_support.gd")
const Fakes = preload("res://tests/terrain/support/fake_terrain_plugins.gd")
const GetSurfaceData = preload("res://addons/flow_nodes_editor/nodes/get_surface_data.gd")
const GetSurfaceDataSettings = preload("res://addons/flow_nodes_editor/nodes/get_surface_data_settings.gd")
const SurfaceSamplerNode = preload("res://addons/flow_nodes_editor/nodes/surface_sampler.gd")
const SurfaceSamplerSettings = preload("res://addons/flow_nodes_editor/nodes/surface_sampler_settings.gd")
const SampleTerrainLayersNode = preload("res://addons/flow_nodes_editor/nodes/sample_terrain_layers.gd")
const SampleTerrainLayersSettings = preload("res://addons/flow_nodes_editor/nodes/sample_terrain_layers_settings.gd")

var _owner : FlowGraphNode3D

func before_test() -> void:
	_owner = auto_free(FlowGraphNode3D.new())
	add_child(_owner)

func _terrain_settings(path : String = "") -> GetSurfaceDataSettings:
	var s := GetSurfaceDataSettings.new()
	s.source = GetSurfaceDataSettings.eSource.Terrain
	s.terrain_node_path = NodePath(path)
	return s

func _ctx() -> FlowData.EvaluationContext:
	var ctx := FlowDataScript.EvaluationContext.new()
	ctx.owner = _owner
	return ctx

# --- get_surface_data ----------------------------------------------------------------

func test_defaults_unchanged() -> void:
	var s := GetSurfaceDataSettings.new()
	assert_int(s.source).is_equal(GetSurfaceDataSettings.eSource.Scene)
	assert_int(s.terrain_splat_layers.size()).is_equal(0)
	var st := SampleTerrainLayersSettings.new()
	assert_int(st.layer_source).is_equal(SampleTerrainLayersSettings.eLayerSource.Textures)
	var ss := SurfaceSamplerSettings.new()
	assert_bool(ss.write_terrain_layers).is_true()
	assert_str(ss.terrain_layer_prefix).is_equal("layer_")

func test_get_surface_data_auto_detects_terrain3d() -> void:
	_owner.add_child(Fakes.terrain3d())
	var node = S.run(GetSurfaceData, _terrain_settings(), [], _owner)
	assert_str(node.err).is_empty()
	var d := S.output(node)
	assert_object(d.shape).is_instanceof(FlowHeightfieldSurface)
	assert_int(d.size()).is_equal(0)
	assert_int(d.kind).is_equal(FlowData.Kind.Surface)
	assert_str(str(d.get_data_attr("terrain_type"))).is_equal("Terrain3D")
	assert_str(str(d.get_data_attr("terrain_layers"))).is_equal("grass,rock,sand")
	assert_str(str(d.get_data_attr("source"))).contains("Terrain3D")
	assert_float(d.shape.project_vertical(30, -20).position.y).is_equal_approx(4.0, 1e-4)

func test_get_surface_data_hterrain_by_path_and_ambiguity() -> void:
	_owner.add_child(Fakes.terrain3d())
	_owner.add_child(Fakes.hterrain(17, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0))))
	var amb = S.run(GetSurfaceData, _terrain_settings(), [], _owner)
	assert_str(amb.err).contains("ambiguous terrain: 2 terrain nodes")
	assert_object(S.output(amb).shape).is_null()
	assert_int(S.output(amb).kind).is_equal(FlowData.Kind.Surface)
	var explicit = S.run(GetSurfaceData, _terrain_settings("HTerrain"), [], _owner)
	assert_str(explicit.err).is_empty()
	var d := S.output(explicit)
	assert_str(str(d.get_data_attr("terrain_type"))).is_equal("HTerrain")
	assert_float(d.shape.project_vertical(2, 2).position.y).is_equal_approx(1.5, 1e-5)
	assert_int(d.shape.get_layers().names.size()).is_equal(8)
	# Renamed layers.
	var s := _terrain_settings("HTerrain")
	s.terrain_layer_names = PackedStringArray(["grass", "rock"])
	var renamed := S.output(S.run(GetSurfaceData, s, [], _owner))
	assert_str(str(renamed.get_data_attr("terrain_layers"))).starts_with("grass,rock,texture_2")

func test_get_surface_data_terrain_errors_and_ownerless() -> void:
	var none = S.run(GetSurfaceData, _terrain_settings(), [], _owner)
	assert_str(none.err).contains("no terrain node found")
	var ownerless = S.run(GetSurfaceData, _terrain_settings(), [], null)
	assert_str(ownerless.err).is_not_empty()
	assert_object(S.output(ownerless).shape).is_null()

func test_get_surface_data_terrain_heightmap_shape_by_path_with_splat() -> void:
	var hm := HeightMapShape3D.new()
	hm.map_width = 5
	hm.map_depth = 5
	var cs := CollisionShape3D.new()
	cs.name = "Ground"
	cs.shape = hm
	_owner.add_child(cs)
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.8, 0, 1))
	var s := _terrain_settings("Ground")
	s.terrain_splat_layers = [FlowTerrainSplatLayer.make("moss", img, FlowTerrainSplatLayer.eChannel.G)]
	s.vertical_tolerance = 0.5
	var node = S.run(GetSurfaceData, s, [], _owner)
	assert_str(node.err).is_empty()
	var d := S.output(node)
	assert_str(str(d.get_data_attr("terrain_type"))).is_equal("HeightMapShape3D")
	assert_float(d.shape.vertical_tolerance).is_equal(0.5)
	assert_float(d.shape.get_layers().get_weight("moss", 0, 0)).is_equal_approx(img.get_pixel(0, 0).g, 1e-6)

func test_heightmap_image_source_unchanged_without_splat_and_layers_with_it() -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RF)
	for y in 8:
		for x in 8:
			img.set_pixel(x, y, Color(x * 0.5, 0, 0))
	var s := GetSurfaceDataSettings.new()
	s.source = GetSurfaceDataSettings.eSource.HeightmapImage
	s.heightmap_image = img
	var plain := S.output(S.run(GetSurfaceData, s, [], null))
	assert_int(plain.shape.content_hash()).is_equal(FlowHeightfieldSurface.from_image(img, 1.0, 1.0, Transform3D.IDENTITY, true).content_hash())
	assert_object(plain.shape.get_layers()).is_null()
	var splat := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	splat.fill(Color(1, 0, 0, 1))
	s.terrain_splat_layers = [FlowTerrainSplatLayer.make("snow", splat)]
	var layered := S.output(S.run(GetSurfaceData, s, [], null))
	assert_object(layered.shape.get_layers()).is_not_null()
	assert_float(layered.shape.project_vertical(0.5, 0).position.y).is_equal_approx(plain.shape.project_vertical(0.5, 0).position.y, 1e-6)

func test_get_surface_data_terrain_fingerprint() -> void:
	var t := Fakes.terrain3d()
	_owner.add_child(t)
	var node = GetSurfaceData.new()
	node.settings = _terrain_settings()
	var a = node.computeSceneFingerprint(_ctx())
	var b = node.computeSceneFingerprint(_ctx())
	assert_bool(a is int).is_true()
	assert_int(a).is_equal(b)
	t.data.height_offset = 3.0
	assert_int(node.computeSceneFingerprint(_ctx())).is_not_equal(a)
	# HeightmapImage stays scene independent.
	var img_node = GetSurfaceData.new()
	var s := GetSurfaceDataSettings.new()
	s.source = GetSurfaceDataSettings.eSource.HeightmapImage
	img_node.settings = s
	assert_that(img_node.computeSceneFingerprint(_ctx())).is_equal(FlowNodeBase.SCENE_INDEPENDENT)

# --- surface_sampler on terrain -------------------------------------------------------

func test_surface_sampler_writes_terrain_layer_weights() -> void:
	_owner.add_child(Fakes.terrain3d())
	var terrain := S.output(S.run(GetSurfaceData, _terrain_settings(), [], _owner))
	var s := SurfaceSamplerSettings.new()
	s.points_per_square_meter = 0.05
	var node = S.run(SurfaceSamplerNode, s, [terrain])
	assert_str(node.err).is_empty()
	var pts := S.output(node)
	assert_int(pts.size()).is_greater(100)
	var layers := terrain.shape.get_layers()
	var positions := pts.getVector3Container(FlowData.AttrPosition)
	for lname in ["grass", "rock", "sand"]:
		assert_bool(pts.hasStream("layer_" + lname)).is_true()
		var w : PackedFloat32Array = pts.getContainerChecked("layer_" + lname, FlowData.DataType.Float)
		for i in positions.size():
			assert_float(w[i]).is_equal(layers.get_weight(lname, positions[i].x, positions[i].z))
	# Weights are partitions of unity on this terrain.
	var g : PackedFloat32Array = pts.getContainerChecked("layer_grass", FlowData.DataType.Float)
	var r : PackedFloat32Array = pts.getContainerChecked("layer_rock", FlowData.DataType.Float)
	var sa : PackedFloat32Array = pts.getContainerChecked("layer_sand", FlowData.DataType.Float)
	for i in g.size():
		assert_float(g[i] + r[i] + sa[i]).is_equal_approx(1.0, 1e-5)
	# Prefix and opt-out.
	s.terrain_layer_prefix = "w_"
	assert_bool(S.output(S.run(SurfaceSamplerNode, s, [terrain])).hasStream("w_rock")).is_true()
	s.write_terrain_layers = false
	var off := S.output(S.run(SurfaceSamplerNode, s, [terrain]))
	assert_bool(off.hasStream("w_rock") or off.hasStream("layer_rock")).is_false()
	# Holes produce no samples.
	for p in positions:
		assert_bool(p.x >= 10.0 and p.x <= 14.0 and p.z >= 10.0 and p.z <= 14.0).is_false()

func test_surface_sampler_bounding_shape_keeps_layers() -> void:
	_owner.add_child(Fakes.terrain3d())
	var terrain := S.output(S.run(GetSurfaceData, _terrain_settings(), [], _owner))
	var s := SurfaceSamplerSettings.new()
	s.points_per_square_meter = 0.25
	s.use_bounding_shape = true
	var box := FlowDataScript.Data.from_shape(FlowBoxVolume.from_aabb(AABB(Vector3(2, -50, 2), Vector3(6, 100, 6))))
	var pts := S.output(S.run(SurfaceSamplerNode, s, [terrain, box]))
	assert_int(pts.size()).is_greater(0)
	for w in pts.getContainerChecked("layer_rock", FlowData.DataType.Float):
		assert_float(w).is_equal_approx(0.75, 1e-6)

# --- sample_terrain_layers from an adapter ----------------------------------------------------

func _points(positions : Array) -> FlowData.Data:
	var d := FlowDataScript.Data.new()
	d.registerStream(FlowData.AttrPosition, PackedVector3Array(positions), FlowData.DataType.Vector)
	return d

func _stl(s : SampleTerrainLayersSettings, input : FlowData.Data, owner : Node3D = null):
	return S.run(SampleTerrainLayersNode, s, [input], owner if owner != null else _owner)

func test_sample_terrain_layers_reads_adapter_weights() -> void:
	_owner.add_child(Fakes.terrain3d())
	var s := SampleTerrainLayersSettings.new()
	s.layer_source = SampleTerrainLayersSettings.eLayerSource.TerrainAdapter
	var node = _stl(s, _points([Vector3(-5, 0, -5), Vector3(5, 0, 5), Vector3(500, 0, 500)]))
	assert_str(node.err).is_empty()
	var d := S.output(node)
	assert_array(Array(d.getContainerChecked("layer_grass", FlowData.DataType.Float))).is_equal([1.0, 0.0, 0.0])
	var rock : PackedFloat32Array = d.getContainerChecked("layer_rock", FlowData.DataType.Float)
	assert_float(rock[1]).is_equal_approx(0.75, 1e-6)
	assert_float(rock[2]).is_equal_approx(0.75, 1e-6)	# clamped onto the edge
	# Subset and rename.
	s.terrain_layers = PackedStringArray(["sand"])
	var only := S.output(_stl(s, _points([Vector3(5, 0, 5)])))
	assert_bool(only.hasStream("layer_grass")).is_false()
	assert_float(only.getContainerChecked("layer_sand", FlowData.DataType.Float)[0]).is_equal_approx(0.25, 1e-6)
	s.terrain_layers = PackedStringArray(["lava"])
	assert_str(_stl(s, _points([Vector3.ZERO])).err).contains("no layer 'lava'")

func test_sample_terrain_layers_adapter_errors_and_fingerprint() -> void:
	var s := SampleTerrainLayersSettings.new()
	s.layer_source = SampleTerrainLayersSettings.eLayerSource.TerrainAdapter
	assert_str(_stl(s, _points([Vector3.ZERO])).err).contains("no terrain node found")
	var node = SampleTerrainLayersNode.new()
	node.settings = SampleTerrainLayersSettings.new()
	assert_that(node.computeSceneFingerprint(_ctx())).is_equal(FlowNodeBase.SCENE_INDEPENDENT)
	var t := Fakes.hterrain(9)
	_owner.add_child(t)
	node.settings = s
	var a = node.computeSceneFingerprint(_ctx())
	assert_bool(a is int).is_true()
	(t._data.splat_maps[0] as Image).set_pixel(0, 0, Color(0.1, 0.1, 0.1, 0.1))
	assert_int(node.computeSceneFingerprint(_ctx())).is_not_equal(a)
	# HTerrain splat weights through the node.
	var d := S.output(_stl(s, _points([Vector3(8, 0, 8)])))
	assert_int(d.streams.size()).is_equal(1 + 8)
	assert_float(d.getContainerChecked("layer_texture_0", FlowData.DataType.Float)[0]).is_equal((t._data.splat_maps[0] as Image).get_pixel(8, 8).r)

func test_sample_terrain_layers_in_scene_dependent_templates() -> void:
	assert_bool(FlowNodeBase.SCENE_DEPENDENT_TEMPLATES.has("sample_terrain_layers")).is_true()
	assert_bool(FlowNodeBase.SCENE_DEPENDENT_TEMPLATES.has("get_surface_data")).is_true()
