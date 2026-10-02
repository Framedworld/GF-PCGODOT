# Flow Nodes Editor — developer notes

The addon ships 167 node templates (`nodes/*.gd` without the `*_settings.gd`
resources); [doc/nodes_reference.md](doc/nodes_reference.md) lists them all and
`node_templates.csv` at the repository root is the template/title index.

## Architecture

| Directory / file | Role |
|---|---|
| `node.gd` (`FlowNodeBase`) | Runtime element, a `RefCounted`. Every node script extends it. Fresh elements are created for every run; never `free()` one. The optional UI hooks (`widget_init`, `widget_ready`, `widget_gui_input`, `widget_exit_tree`, `widget_refresh`, `widget_draw`, `widget_script`) are documented at the top of the file. |
| `executor/flow_node_widget.gd` (`FlowNodeWidget`) | The editor's `GraphNode` for one element: ports, theming, tooltips, error text, debug draw, exec-time badge. It forwards the members the editor uses (`settings`, `deps`, `dirty`, `generated_bulks`, ...) to its element. |
| `executor/flow_compiled_graph.gd` (`FlowCompiledGraph`) | `for_graph(graph)` parses a `FlowGraphResource` once and keeps the result on the graph (`_flow_compiled`) until `graph.data` or the node registry changes. |
| `executor/flow_executor.gd` (`FlowExecutor`) | The only executor: `SYNCHRONOUS`, `TIME_SLICED` (`step(budget_ms)`) and `THREADED` modes, plus the `node_filter` and `preseeded` hooks. `FlowNodeIO.evaluate_graph`, `begin_evaluation` and `evaluate_graph_snapshot` wrap it; the editor dock runs single nodes through `FlowExecutor.execute_element`. |
| `executor/flow_node_traits.gd` (`FlowNodeTraits`) | `[main_thread, cacheable]` per stock template. `meta_node["pure"]` and `meta_node["main_thread"]` override the table; unknown templates are main-thread and not cacheable. `tests/executor/flow_node_traits_test.gd` fails when a stock template has no row. |
| `executor/flow_output_cache.gd` (`FlowOutputCache`) | Process-wide LRU cache of pure-node outputs (`max_entries`, `clear()`, `hits`, `misses`). |
| `spatial/` | `FlowSpatial` and the shapes carried on `FlowData.Data.shape` (splines, surfaces, volumes, composites), `FlowSurfaceLayers` (paint-layer weights on a surface), plus `FlowSpatialSources` for the Get * Data nodes. |
| `terrain/` | `FlowTerrainAdapter` and its adapters: `HeightMapShape3D`, heightmap `Image` (with `FlowTerrainSplatLayer` splat images), `MeshInstance3D`, and Terrain3D / HTerrain by duck typing. The two plugin adapters call only methods they check with `has_method`, and were tested against fakes (`tests/terrain/support/fake_terrain_plugins.gd`), not the real plugins. |
| `world/` | Hierarchical and runtime generation: `FlowWorld3D` (cells, scheduler, pool, manual API), `FlowGenerationSource`, `FlowWorldGrid` (cell math, half-open ownership), `FlowWorldCell` (one cell to evaluate) and `FlowCellRun` (a time-sliced cell run). Levels are computed by `FlowCompiledGraph` (`node_levels`, `level_plan`). |
| `visualization/` | The Data Inspector's `TableView`, its pure model `FlowDataTableModel` (columns, cell text, sort keys, filter for every type, shape summaries), and `FlowDebugShapes`, the pure line builder behind the viewport debug draw of shapes and point bounds. |
| `spawn/` | `FlowMeshSpawnEntry`, `FlowSpawnUtil`, `FlowSpawnPool`, `FlowSplineBend`, `FlowInstancedCollision3D`. |
| `attributes/` | `FlowAttributeOps`, shared by the attribute-type nodes (kept outside `nodes/` so the editor does not list it as a template). |

**Threading and caching** are options on `FlowGraphNode3D` (`threaded`, `output_cache`),
both off by default. `FlowNodeIO.make_context` turns them into the context metas
`FlowExecutor.THREADED_META` and `FlowExecutor.OUTPUT_CACHE_META`, which nested subgraph
and loop evaluations inherit. In threaded mode, main-thread elements run on the calling
thread in sequential order and never overlap pool tasks; errors are buffered per
element and appended in sequential order, so `last_errors` matches a plain run. Both
modes reproduce the plain run's output exactly. `FlowWorld3D` has the same two options
and passes them to every cell component; its time-sliced scheduler keeps each cell's
top level sequential, as `generate_async` does, so `threaded` applies to its synchronous
manual API and to nested subgraph and loop evaluations.

> **Warning: script Loggers and threaded mode.** Errors and warnings that do not go
> through a node's `setError` (a `push_error` from a `FlowData` helper such as
> `cloneStream` or `findStream`, a `push_warning`, or an engine error) are raised on the
> `WorkerThreadPool` thread that runs the node. Godot calls every registered script
> `Logger` (`OS.add_logger`) on the raising thread, so with `threaded` on, a Logger can be
> called from several threads at once. A Logger that is not thread-safe (one that appends
> to an Array or writes a file without a `Mutex`) can then corrupt memory and crash the
> process. The addon cannot make third-party Loggers thread-safe. To reduce the exposure,
> threaded mode runs the nodes known to log this way (`FlowNodeTraits.LOGGING_TEMPLATES`,
> or `meta_node["logs"] = true`) one at a time on the calling thread instead of in a
> concurrent batch, but any pure node can still print an unforeseen engine error from a
> worker. Keep `threaded` off, or make your Loggers thread-safe, when you register one.

A node script that should be threadable or cacheable must not write into an input
`Data` (duplicate it first), must not touch the scene tree, physics, rendering,
`ctx.owner`, `ctx.variables` or `ctx.runtime_params`, must guard any static cache with a
`Mutex`, and declares `"pure": true` in its `meta_node`. A new stock node also needs a
row in `FlowNodeTraits.TABLE`, and an entry in `SCENE_DEPENDENT_TEMPLATES` (`node.gd`)
if it reads the scene.

## Testing

From `demo/`, with the GDExtension binary for your platform in `bin/`:

```bash
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"   # must print nothing
godot --headless --path . -s res://tests/perf/executor_benchmark.gd             # benchmark script, not a test
godot --headless --path . -s res://tests/perf/node_benchmark.gd                 # per-node timings at 1k/10k/100k points
godot --headless --path . -s res://tests/perf/exact_fingerprint.gd              # exact output hashes of every golden graph
```

The benchmark numbers and the method behind them (interleaved before and after runs, exact fingerprints) are in
[`docs/_round2/WP13-P1.md`](../../../docs/_round2/WP13-P1.md).

`tests/executor/conformance/` is the node conformance harness: it runs every registered
template with default settings on synthetic inputs and fails on input mutation,
non-determinism, a worker-thread result that differs from the main-thread one (threadable
templates) or a cache hit that differs from a fresh run (cacheable templates). A new node
is covered once it has its `FlowNodeTraits.TABLE` row; if its defaults only reach an error
path, add a row with working settings or fixtures to
`tests/executor/conformance/conformance_overrides.gd`. The per-template report:

```bash
godot --headless --path . -s res://tests/executor/conformance/tools/conformance_report.gd
```

`tests/world/` covers hierarchical generation (levels, cell math, partition invariance of
the world-aligned samplers, the scheduler with an injected clock and fake sources),
`tests/terrain/` the terrain adapters, and `tests/editor/` the editor through a headless
dock. What none of them can see (drawing, mouse, the inspector, undo, the 3D viewport) is
in [docs/MANUAL_EDITOR_CHECK.md](../../../docs/MANUAL_EDITOR_CHECK.md).

The golden suite (`tests/golden`) and the seed-zero suite
(`tests/runtime/seed_zero_backcompat_test.gd`) must pass without regenerating their
baselines unless an output change is intended and listed in `docs/DEPRECATIONS.md`.
`tests/executor/executor_modes_golden_test.gd` checks that threaded and cached runs
reproduce the golden baseline, and `tests/editor/editor_smoke_harness_test.gd` runs every
golden graph through the editor dock headless and compares it with the runtime.

## Project node directories

Stock nodes live in `nodes/`. Project nodes should live outside the addon so the
addon folder can be replaced on upgrade. `FlowNodeRegistry` resolves a template
`foo` to the first `<dir>/foo.gd` found in:

1. `res://addons/flow_nodes_editor/nodes` (stock; cannot be shadowed),
2. the project setting `flow_nodes/node_directories` (a `PackedStringArray` of
   `res://` directories, shown under **Project Settings → Flow Nodes**; the plugin
   registers it with its empty default when enabled, so `project.godot` only changes
   once you add a directory),
3. directories added at runtime with `FlowNodeRegistry.register_node_directory()`.

The setting is re-read whenever it changes, so the add-node menu refreshes after an
edit in Project Settings, and exported games need no startup code. Node category,
colour and search terms come only from the node's `meta_node` (`"category"`,
`"aliases"`); there are no per-project tables in the addon.

## Graph format versions and migrations

`FlowGraphResource.data` carries `"version"` (`FlowGraphMigrations.CURRENT_VERSION`,
currently `2`; data without the key counts as `1`). `FlowGraphMigrations.migrate(data)`
upgrades older data and is called in exactly these places:

| Where | What happens to the resource |
|---|---|
| `FlowNodeIO.loadFromResource` / `loadFromResourceWithProgress` (editor load, through `migrate_resource_for_editor`) | `resource.data` is replaced by the upgraded copy and the graph is marked dirty, so the next save writes the current version |
| `FlowCompiledGraph.compile` (every `FlowNodeIO` evaluation, including nested subgraphs and loops in the editor; once per change of `graph.data`) | nothing — the upgraded copy is kept on the compiled graph only |
| `FlowNodeIO.create_nodes_from_dict` / `create_nodes_from_dict_with_progress` (clipboard paste and editor load) | pasted JSON is upgraded before nodes are created |

`migrate()` returns the same dictionary when there is nothing to do, so current
graphs pay no copy. It also replaces templates listed in
`FlowNodeRegistry.template_aliases` (old name → new name) when the old script no
longer exists.

### How to add a migration

Do this whenever you rename or remove a settings property of a stock node, or change
what a stored value means.

1. Bump `CURRENT_VERSION` in `flow_graph_migrations.gd` (for example `2` → `3`).
2. Add an entry for the new version to `MIGRATIONS`, keyed by the node template's
   **current** name:

   ```gdscript
   static var MIGRATIONS : Dictionary = {
       2: {},
       3: {
           # rename a settings key; the value is kept
           "distance": { "in_nameA": "source_attribute" },
           # transform a value: called when the old key is present; mutate the
           # dictionary in place or return a replacement
           "grid": { "count": _split_grid_count },
           # "*" as the template applies to every node, "*" as the key always runs
           "*": { "legacy_debug": "debug_enabled" },
       },
   }

   static func _split_grid_count(settings: Dictionary) -> Dictionary:
       settings["x"] = settings["count"]
       settings["z"] = settings["count"]
       settings.erase("count")
       return settings
   ```

   A rename never overwrites a value already stored under the new key. Migrations
   run in version order, so a graph saved at version 1 receives every step.
3. If a template was renamed, keep the old graphs loading by adding
   `"old_template": "new_template"` to `FlowNodeRegistry.STOCK_TEMPLATE_ALIASES`
   (projects add their own to `FlowNodeRegistry.template_aliases`).
4. Add a test in `demo/tests/flow_nodes_editor/FlowGraphMigrationsTest.gd`: a
   dictionary at the previous version migrates and evaluates, and one at the new
   version is returned untouched.
5. List the change in `docs/DEPRECATIONS.md`.

Never edit `.tres` graphs by hand to "migrate" them; open and save them in the editor
(or run `FlowGraphMigrations.migrate` over `resource.data` in a tool script and save
with `ResourceSaver`).

## TODO

- [ ] Demos
	- [X] Wall of rocks, picking a random point on the top
	- [X] Path with random subscene, filter by attribute with rotations
	- [X] Sample surface of a mesh, create flowers or similar in the horizontal ground
	- [X] Mark an area with a spline, have a path remove all flowers
		- [X] Change density based on the distance to the spline contour
	- [X] Bridge
- [X] Match & Set is not taking into account the weight attr
- [ ] Verify the HTerrain and Terrain3D adapters (`terrain/`) against the real plugins (they were tested against fakes only)
- [ ] Subgraphs / Loops?
- [X] Sample spline along N random positions
- [X] Discard points too close to hard edges of a mesh
- [X] Add noise to position <-- Improve noise
- [X] Spline sampling interior in non grid pattern
- [X] Allow to filter rows in the inspector
- [X] Support for virtual streams like front, up, right from rotation.
- [X] Support for Vector4/Color/PackedVector4Array -> Read SubAttributes / MathNode / SetAttribute / Use in Debug if exists
- [X] undo/redo
- [X] Test random colors for each node -> Graph Editor Settings
- [X] add_attribute, if output is single stream with a type, set the color. Maybe make it generic
- [X] Allow the popup menu to have sections. Custom SubGraphs/Resources/Folders maybe
- [X] Transform. Allow rotation to be in local space
- [X] The inspected flag is saved, but it's now never restored
- [X] Support for multiple data in stream evaluation?
	- [X] Debug
	- [X] Generic Loop
	- [X] Node to group <-- Merge
	- [X] Node to split by condition/field <-- Partition
- [X] Allow meta to define input requirements. Single vs Multiple/Accepted Types/Required
- [X] Hightlight the node being evaluated rather than the connections
- [X] Do not update what it's not dirty
- [X] Introduce the mesh/spline data type
	- [X] Nodes of type Curve/Mesh
	- [X] Node to gather
	- [X] Node to create
	- [X] Node to sample (the current one)
- [X] Allow to bypass a node
- [X] There is bug where transforms seems to be updating the input
- [X] Math Node. Should hide inputs when not needed. Like Abs
- [X] Volume Sample in 3D
- [X] Remap node
- [X] Add expressions node
- [X] weighted sampling
- [X] support for @last?
- [X] Get N property as a independent value. Get first, get last, etc.
- [X] Sampling mesh
- [X] Allow the grid to have an offset/rotation or it's useless
- [X] scan nodes, filter by class_name
- [X] scan nodes, option to resize to node limits
- [X] Support for copy/paste/clone
- [X] Resource properties are correctly imported as Resources in the scan node
- [X] Promote input pin to graph input
- [X] Custom inputs values in the pcg node 3d, not in the resource
- [X] Generate reduction of metrics. Avg, Min, Max, etc of a numeric stream
- [X] Copy with offset N times. Export attribute
- [X] Show performance numbers somewhere
- [X] Merge node
- [X] if condition is null/emtpy
- [X] drop some streams
- [X] Ctrl+C will not add a comment. Only if pressing C alone
- [X] E will toggle the data inspector but also make data_visualization visible in the editor
- [X] Distance to curve
- [X] Sort a stream by some condition
	- [X] Floats
	- [X] Ints
	- [X] Strings
	- [X] How does it behave with multiple streams
- [X] add_attribute, input is optional
- [X] Math Node. Should be easier to add a constant +float/+int/-vector at least. Use make_vector for vector
- [X] Improve self prunning so more objects are kept
- [X] No need to regenerate the menu every time
- [X] Hightlight the selector row from the inspector in the 3D
- [X] Make vector from float's, maybe autopromote float -> vector3 
- [X] Allow the inspector to show all outputs/inputs
- [X] nodes to filter A/B
- [X] Math Node. Accept a stream feeding a single size element -> Promote it
- [X] Confirm if we are using PackedStringArray for streams of type Strings
- [X] Confirm I can set values of the generated instances
- [X] spatial operations
	- [X] A minus B
	- [X] A intersection B
- [X] Remove self intersections
- [X] When changing scene, the registered nodes should be removed
- [X] Confirm I can use Index as part of the streams
- [X] Spline region - Spline path
- [X] Node to scan nodes 
- [X] Read meta into the attributes
- [X] Read properties from list
- [X] store sizes
- [X] display density/color in debug
- [X] input nodes are not restored correctly
- [X] support for bools
- [X] Move isFinal to getMeta
- [X] Spawn PackedScene
- [X] store rotations
- [x] read-write sub-streams
	- [x] vector3 -> .x, .y, .z
	- [x] basis   -> yaw, pitch, roll
- [x] Choose mesh to spawn
- [x] Stream to ref mesh instance
- [x] Multic Constant as Arg vs Attribute input
	- [x] Conditional UI
- [X] Aggregate MultiInstanceMesh per mesh in spawn meshes
- [x] dispay substreams
- [x] node transform with ranges in local space
- [x] save graph into scene node 
- [x] dependencies/dirty chains
- [X] node add density
- [X] update data_view on each refresh
- [X] node operate
- [X] create custom stream
- [x] spline sampling
- [x] support for prev
- [X] Dynamic title
- [X] update while changing the scene
- [X] Block auto-update
