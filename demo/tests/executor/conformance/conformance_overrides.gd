extends RefCounted

## Per-template adjustments for the node conformance harness (WP9).
##
## The harness runs every template with default settings on the generic
## fixtures. A row here gives a template better inputs where the generic ones
## only reach an error path, or records why it cannot be driven generically.
## Keys (all optional):
##   settings        { property: value, or Callable() -> value } applied to fresh settings
##   primary         fixture ids for input port 0 (default Fixtures.PRIMARY)
##   secondary       fixture ids for ports 1+ (default Fixtures.SECONDARY)
##   extra_cases     extra [primary, secondary] pairs
##   variants        { label: { property: value } }: the cases run again once per
##                   variant with these settings on top (labels "<case>@<label>")
##   owner           "scene" (default: a Node3D in the tree with a Path3D, a
##                   MeshInstance3D and a box collision body) or "none" (owner-less)
##   runtime_params  EvaluationContext.runtime_params entries
##   variables       Callable() -> Dictionary of EvaluationContext.variables
##   known_bugs      { case label: "file:line description" }: cases that hit a
##                   genuine node bug (listed in docs/_round2/WP9.md). They are
##                   left out of the suite so it stays green and quiet; the
##                   report tool runs them with --include-known-bugs.
##   skip            reason: the template is not run at all
##   note            free text for the report
## Rows must name existing templates (the conformance test checks this).
##
## Fixture ids are those of conformance_fixtures.gd; "scene_meshes" and
## "scene_paths" reference the owner scene's MeshInstance3D and Path3D.

const FlowDataScript = preload("res://addons/flow_nodes_editor/flow_data.gd")
const Fixtures = preload("res://tests/executor/conformance/conformance_fixtures.gd")
const TestGraph = preload("res://tests/evaluator/support/test_graph.gd")
const GrammarModuleResource = preload("res://addons/flow_nodes_editor/grammar_module_resource.gd")

const DATA_DIR := "res://tests/executor/conformance/data"
const STOCK_ASSET := "res://addons/kaykit_dungeon_remastered/Assets/gltf/torch.gltf.glb"

static var _rows = null

static func for_template(template : String) -> Dictionary:
	return rows().get(template, {})

static func rows() -> Dictionary:
	if _rows == null:
		_rows = _build_rows()
	return _rows

static func _build_rows() -> Dictionary:
	return {
		# --- Pure nodes whose defaults only reach an error path ----------------------
		"attribute_rename": { "settings": { "from_name": "f_attr", "to_name": "renamed_attr" } },
		"bounds_from_mesh": {
			"settings": { "mesh_attribute": "r_attr", "mesh": func(): return Fixtures.shared_mesh() },
			"note": "reads the per-point Mesh attribute (ArrayMesh.get_aabb) on the worker thread",
		},
		"dungeon_connect_rooms": {
			"known_bugs": { "attr_set": "dungeon_connect_rooms.gd:51 indexes the position stream of an input with 2+ rows and no position stream (SCRIPT ERROR)" },
		},
		"dungeon_expand_rooms": { "primary": [ "dungeon_rooms", "empty", "points", "single" ] },
		"dungeon_walls_and_doors": { "primary": [ "dungeon_cells", "empty", "points", "single" ] },
		"filter_data_by_attribute": { "settings": { "attribute_name": "df_attr" } },
		"filter_data_by_tag": { "settings": { "tags": "conformance_tag_a" } },
		"grammar_expand": {
			"settings": {
				"grammar": "A B*",
				"modules": func(): return _grammar_modules(),
				"length_attribute": "f_attr",
			},
		},
		"boolean": {
			"settings": { "in_nameA": "b_attr", "in_nameB": "b_attr" },
			"secondary": [ "points", "points_b", "empty", "attr_set", "volume_box" ],
		},
		"filter": { "settings": { "in_nameA": "f_attr", "in_nameB": "f_attr" } },

		# --- Settings variants: modes the defaults do not reach -----------------------
		# Enum values are written as ints; the comment names them.
		"sample_points": {
			# eDistribution: UniformGrid 0, QuasiRandom3D 2, BlueNoise2D 3 (lazy static table with a Mutex)
			"variants": { "grid": { "distribution": 0 }, "halton3d": { "distribution": 2 }, "blue_noise": { "distribution": 3 } },
		},
		"self_pruning": { "variants": { "grid_cell": { "mode": 1 } } },   # ePruneMode.GridCell
		"difference": {
			# eOperation: B_Minus_A 1, Intersection 2, Union 3, SymmetricDifference 4; eDensityFunction: Minimum 1
			"variants": { "b_minus_a": { "operation": 1 }, "union": { "operation": 3 }, "symmetric": { "operation": 4 }, "density_min": { "density_function": 1 } },
		},
		"surface_sampler": { "variants": { "count": { "shape_sampling": 1, "align_to_normal": true } } },   # eShapeSampling.Count
		"noise": { "variants": { "add": { "mode": 1 } } },   # eMode.Add
		"attribute_noise": { "variants": { "minimum": { "mode": 1 }, "multiply": { "mode": 4 } } },   # eMode
		"math_op": {
			"settings": { "in_nameA": "f_attr", "in_nameB": "f_attr", "out_name": "math_out" },
			"secondary": [ "points", "points_b", "empty", "attr_set", "volume_box" ],
			# eOperation: Divide 3, Negate 4, Modulo 9
			"variants": { "divide": { "operation": 3 }, "negate": { "operation": 4 }, "modulo": { "operation": 9 } },
		},
		"partition": { "settings": { "attribute_name": "i_attr" } },
		"reduce": { "settings": { "in_name": "f_attr", "out_prefix": "reduced_" } },
		"sort": { "settings": { "sort_by": "f_attr" } },
		"load_data_table": {
			"settings": { "table_path": DATA_DIR.path_join("conformance_table.csv") },
			"note": "reads tests/executor/conformance/data/conformance_table.csv",
		},
		"load_pcg_data_asset": {
			"settings": { "asset_path": DATA_DIR.path_join("conformance_asset.json") },
			"note": "reads tests/executor/conformance/data/conformance_asset.json",
		},
		"output": { "note": "graph boundary: has no output port, it only forwards its input to the evaluator" },
		"assets": { "note": "no assets configured: emits an empty Data" },

		# --- Main-thread nodes: scene inputs, graphs, assets, variables -------------
		"mesh_sampler": { "primary": [ "scene_meshes", "empty", "points" ] },
		"sample_mesh": { "primary": [ "scene_meshes", "empty", "points" ] },
		"point_from_mesh": { "primary": [ "scene_meshes", "empty", "points" ] },
		"split_splines": { "primary": [ "scene_paths", "empty", "points", "spline" ] },
		"subdivide_segment": { "primary": [ "scene_paths", "empty", "points", "spline" ] },
		"sample_spline": { "extra_cases": [ [ "scene_paths", "" ] ] },
		"create_surface_from_spline": { "extra_cases": [ [ "scene_paths", "" ] ] },
		"clip_paths": { "secondary": [ "scene_paths", "empty", "points_b" ] },
		"texture_sampler": { "settings": { "texture": func(): return _texture() } },
		"sample_terrain_layers": { "settings": { "layers": func(): return _terrain_layers() } },
		"get_variable": {
			"settings": { "variable_name": "conformance_var" },
			"variables": func(): return { "conformance_var": Fixtures.points(Fixtures.POINT_COUNT) },
		},
		"get_property_from_object_path": {
			"settings": {
				"object_paths": PackedStringArray([ "ConformanceMesh", "ConformancePath" ]),
				"property_paths": func(): return _string_names([ "position", "name" ]),
			},
		},
		"create_points": { "settings": { "points": func(): return _point_entries() } },
		"loop": {
			"settings": {
				"graph": func(): return _passthrough_graph(),
				"item_input_name": "item",
				"output_attribute_name": "result",
			},
		},
		"subgraph": { "settings": { "graph": func(): return _passthrough_graph() } },
		"load_alembic_file": {
			"settings": { "asset_path": STOCK_ASSET },
			"note": "samples a stock demo asset (kaykit torch)",
		},
		"points_from_imported_scene": {
			"settings": { "asset_path": STOCK_ASSET },
			"note": "samples a stock demo asset (kaykit torch)",
		},
		"input": { "note": "graph boundary: fed by the evaluator from the owner's args; covered by the evaluator suites" },
		"navigation_region_sampler": { "note": "no NavigationRegion3D in the fixture scene: empty-output path only" },
		"points_from_gridmap": { "note": "no GridMap in the fixture scene: empty-output path only" },
		"points_from_tilemap": { "note": "no TileMap in the fixture scene: empty-output path only" },
		"point_from_player_pawn": { "note": "no camera or player group in the fixture scene: error path only" },
		"physics_overlap_query": { "note": "headless physics space is never stepped: queries see no bodies" },
		"physics_shape_sweep": { "note": "headless physics space is never stepped: queries see no bodies" },
		"ray_cast": { "note": "headless physics space is never stepped: queries see no bodies" },
		"projection": { "note": "physics mode (default): headless physics space is never stepped" },
		"compute_kernel": { "note": "no RenderingDevice headless: error path only" },

		# Scene mutators: they spawn into the fixture owner, which is freed after the template.
		"spawn_meshes": { "note": "spawns MultiMeshInstance3D under the fixture owner" },
		"spawn_nodes": { "note": "spawns OmniLight3D under the fixture owner" },
		"spawn_scenes": { "settings": { "scene": func(): return _packed_scene() }, "note": "spawns a packed Node3D under the fixture owner" },
		"spawn_spline_mesh": { "primary": [ "scene_paths", "spline", "empty", "points" ], "settings": { "mesh": func(): return Fixtures.shared_mesh() } },
		"apply_on_actor": { "primary": [ "scene_meshes", "empty", "points" ] },
		"create_spline": {},
		"create_target_node": {},
		"debug": { "owner": "none", "note": "owner-less: the debug draw side effect needs the editor" },
	}

# Body graph for loop and subgraph: input "item" -> output "result".
static func _passthrough_graph() -> FlowGraphResource:
	return TestGraph.new() \
		.in_param("item", FlowData.DataType.Vector) \
		.node("in_item", "input_item", { "name": "item", "data_type": FlowData.DataType.Vector }) \
		.node("out", "output", { "name": "result" }) \
		.link("in_item", 0, "out", 0) \
		.build()

static var _shared_scene : PackedScene = null

static func _packed_scene() -> PackedScene:
	if _shared_scene == null:
		var root := Node3D.new()
		root.name = "ConformanceSpawned"
		var child := Node3D.new()
		child.name = "Child"
		root.add_child(child)
		child.owner = root
		_shared_scene = PackedScene.new()
		_shared_scene.pack(root)
		root.free()
	return _shared_scene

static func _grammar_modules() -> Array:
	var modules : Array[FlowUserResourceData] = []
	for def in [ [ "A", 1.0 ], [ "B", 0.5 ] ]:
		var entry = GrammarModuleResource.new()
		entry.symbol = def[0]
		entry.size = def[1]
		entry.weight = 1.0
		modules.append(entry)
	return modules

static var _shared_texture : ImageTexture = null

# One 4x4 gradient texture per process (identity matters for the cache key).
static func _texture() -> Texture2D:
	if _shared_texture == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		for y in range(4):
			for x in range(4):
				image.set_pixel(x, y, Color(x / 3.0, y / 3.0, 0.5, 1.0))
		_shared_texture = ImageTexture.create_from_image(image)
	return _shared_texture

static func _terrain_layers() -> Array:
	var layer := TerrainLayerEntry.new()
	layer.layer_name = "grass"
	layer.texture = _texture()
	var layers : Array[TerrainLayerEntry] = [ layer ]
	return layers

static func _point_entries() -> Array:
	var entries : Array[FlowPointEntry] = []
	for i in range(3):
		var entry := FlowPointEntry.new()
		entry.position = Vector3(i * 2.0, 0.0, 1.0)
		entry.density = 0.5 + 0.25 * i
		entry.seed = 10 + i
		entries.append(entry)
	return entries

static func _string_names(names : Array) -> Array:
	var result : Array[StringName] = []
	for n in names:
		result.append(StringName(n))
	return result
