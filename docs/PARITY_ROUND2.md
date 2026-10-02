# Parity Round 2: Unreal PCG architecture parity

Goal: bring the addon's architecture and feature set close to Unreal PCG. Not a port, but the same shape: settings, stateless elements, a compiled task graph with caching and parallel execution, typed spatial data, hierarchical and runtime generation, and a full spawner and node vocabulary.

This document is the binding contract for every agent in the round. Where it names a class, method or file, use exactly that. Anything it does not mention keeps today's behaviour.

## Unreal concept map

| Unreal | Here, today | Here, after this round |
|---|---|---|
| `UPCGSettings` | `NodeSettings` resource | unchanged |
| `UPCGNode` (topology) | `FlowNodeBase`, a `GraphNode` Control that is also the executor | graph topology lives in `FlowCompiledGraph`; the editor widget is `FlowNodeWidget` |
| `IPCGElement` (stateless executor) | the same Control | `FlowNodeBase`, now a `RefCounted` element; node scripts keep `extends FlowNodeBase` |
| `FPCGGraphCompiler` + `FPCGGraphExecutor` | per-evaluation parse, topological sort, sequential run | `FlowCompiledGraph` cached per graph, `FlowExecutor` with sync, time-sliced and threaded modes |
| `FPCGGraphCache` (CRC of settings and inputs) | none | `FlowOutputCache`, opt-in |
| `UPCGSpatialData` (spline, surface, volume, composite) | everything is a point stream | `FlowSpatial` shapes carried on `Data.shape` |
| attribute types (vector2, vector4, transform, int64, double) | bool, int, float, vector3, string, resource, node, color, quaternion | extended `DataType` |
| `UPCGComponent` + partition actors + runtime gen scheduler | `FlowGraphNode3D` | wave B: `FlowWorld3D`, grid cells, generation sources |

## Rules for every agent

1. **Base.** First run `git fetch origin claude/pcg-system-review-4tpca9 && git reset --hard origin/claude/pcg-system-review-4tpca9` in your worktree. Your worktree may have been created from an older commit.
2. **Back-compat.** All new behaviour defaults to today's output. The golden suite (`demo/tests/golden`) and the seed-zero suite (`demo/tests/runtime/seed_zero_backcompat_test.gd`) must pass **without regeneration** unless your work package says otherwise. If you believe a baseline must change, stop and say why in your report instead of regenerating.
3. **File ownership.** Edit only the files your work package owns, plus new files. New files go in the directories named below. If you must touch another package's file, make the smallest possible change and list it in your report.
4. **Shared docs are read-only for you.** Do not edit `README.md`, `docs/COMING_FROM_UNREAL_PCG.md`, `docs/PARITY_ROADMAP.md`, `docs/DEPRECATIONS.md`, `demo/addons/flow_nodes_editor/doc/nodes_reference.md` or `node_templates.csv`. Write `docs/_round2/<package>.md` with: a summary, the dictionary rows to add (same table format as `COMING_FROM_UNREAL_PCG.md`), nodes_reference rows, and DEPRECATIONS rows for any output change. The coordinator merges these.
5. **Tests.** New GdUnit4 suites for everything you add, in new files under `demo/tests/`. Do not edit existing tests unless the behaviour change is intended and listed in your report.
6. **Never commit** `demo/reports/`, `.godot/`, the Linux `.so`, or your local `flow.gdextension` edit.
7. **No model identifiers** in code, docs or commit bodies. Use the attribution trailer from your own session instructions on every commit.
8. **Report** with: worktree path, branch, base commit, commit SHAs, per-requirement what changed, exact test commands with counts, every deviation from this document, everything left undone.

## Environment

- Godot 4.6 is `godot`; 4.7.1 is `godot47`. Run from `demo/`:
  `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests` (or a narrower `-a res://tests/<dir or file>`).
  Current baseline: 2182 cases, 0 failures, 2 skipped, 1 orphan that exits 101.
  Import check: `godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"` must print nothing.
- Native library: copy `/home/user/GF-PCGODOT/demo/addons/flow_nodes_editor/bin/libflow.linux.template_debug.x86_64.so` into your worktree's `demo/addons/flow_nodes_editor/bin/` and add `linux.x86_64 = "res://addons/flow_nodes_editor/bin/libflow.linux.template_debug.x86_64.so"` under `[libraries]` in `flow.gdextension`. Revert that edit before committing.
- Loading a node script before `flow_data.gd` can fail with a class cycle; existing tests preload `flow_data.gd` first. Do the same.

## Work packages

### WP1: executor architecture (agent A1)

Owns: `node.gd`, `flow_nodes_io.gd`, `flow_node.gd`, `flow_variable_eval.gd`, `node_draw_debug.gd`, `connectors_row.gd`, `flow_graph_edit.gd`, `flow_editor.gd`, `data_inspector.gd`, `plugin.gd`, and the widget-facing hooks of `nodes/input.gd`, `output.gd`, `reroute.gd`, `loop.gd`, `subgraph.gd`, `get_variable.gd`, `set_variable.gd`, `grid_size.gd`, `add_attribute.gd`, `sample_points.gd` (UI parts only). New files go in `demo/addons/flow_nodes_editor/executor/`.

Requirements:

1. **Element and widget split.** `FlowNodeBase` becomes `extends RefCounted` and is the runtime element. The roughly 110 pure-logic node scripts keep `extends FlowNodeBase` and must need no edits. New `class_name FlowNodeWidget extends GraphNode` owns one `element : FlowNodeBase` and hosts all UI: ports, connector rows, theming, tooltips, debug draw, error text, execution-time badge, slot types and colours. The widget exposes the member names the editor already uses (`settings`, `node_template`, `deps`, `dependants`, `dirty`, `generated_bulks`, `inputs`, `err`, `args_ports_by_name`, `show_disconnected_inputs`, `eval_id`, `scene_fingerprint`, and so on) by delegation, so `flow_editor.gd` changes are mostly retyping `FlowNodeBase` to `FlowNodeWidget`.
2. **Element UI hooks.** Nodes that build UI (input, output, loop, subgraph, reroute, variables and the few others) implement optional hooks the widget calls: `widget_init(widget)`, `widget_ready(widget)`, `widget_gui_input(widget, event)`, `widget_exit_tree(widget)`, `widget_refresh(widget)`. Document them at the top of `node.gd`.
3. **`FlowCompiledGraph`** (`RefCounted`). Built from a `FlowGraphResource`: instance descriptors (template, name, saved settings), links, execution order, finals, input and output nodes, the migrated graph data. `FlowCompiledGraph.for_graph(graph)` returns a cached instance keyed by the graph object and invalidated when `graph.data` changes (hash or version, not by reference alone). The compile step replaces the per-evaluation parse in `_build_evaluation_state`. Elements are still created fresh per run; settings resources are fresh per run (overrides and bindings mutate them), ideally by duplicating a prototype.
4. **`FlowExecutor`** (`RefCounted`). One implementation of the three modes: synchronous, time-sliced (what `GraphEvaluation.step` does today) and threaded. `GraphEvaluation` and `begin_evaluation` remain as thin compatibility wrappers. Extension points for wave B: `node_filter : Callable(element) -> bool` (skip nodes) and `preseeded : Dictionary` (node name to prepared bulks).
5. **`FlowNodeTraits`** (static table in `executor/flow_node_traits.gd`). Per template: `main_thread` (touches the scene tree, physics, rendering, spawns nodes) and `cacheable` (pure function of settings, seed and inputs). `meta_node` may override with `"main_thread"` and `"pure"`. Derive defaults from existing meta flags (`scans_scene`, `queries_physics`, `is_final`) and a central table, so **no node script needs editing**. Unknown templates default to main-thread and not cacheable, so third-party nodes stay safe.
6. **Threaded mode.** `FlowGraphNode3D.threaded : bool = false`. When on, independent ready elements run on `WorkerThreadPool`; main-thread elements run on the main thread; variables (`set_variable`/`get_variable`) keep their dependency order. Results must be **identical** to sequential. Audit pure nodes for shared mutable state (static caches such as the data-asset cache need a `Mutex`). Mode must be fully optional and off by default.
7. **`FlowOutputCache`.** `FlowGraphNode3D.output_cache : bool = false`. A cacheable element's outputs are stored keyed by a hash of template, settings values (after overrides and bindings), effective seed and the `Data.content_hash()` of every input. Return copies (`duplicate()`), never shared objects, because consumers may mutate. Bounded size with LRU eviction, `FlowOutputCache.clear()`, hit and miss counters. A graph run with the cache on must produce byte-identical output to the cache off.
8. **Editor parity.** The editor keeps per-node dirty tracking, scene fingerprints, debug draw and the inspector. Add an **editor smoke harness** test that instantiates `flow_editor.tscn` in a headless SceneTree, loads every demo graph, runs the editor's evaluation path, and compares per-node stream hashes with `FlowNodeIO.evaluate_graph_snapshot`. Both paths must agree with the golden baseline.
9. **Public API unchanged.** `FlowNodeIO.evaluate_graph`, `evaluate`, `make_context`, `begin_evaluation`, `evaluate_graph_snapshot`, `FlowGraphNode3D.generate*`, `last_errors` keep their signatures and results.

Acceptance:
- Full suite, golden and seed-zero suites pass with **no baseline changes**.
- The editor smoke harness passes.
- `demo/tests/perf/executor_benchmark.gd` (a script, not a test) prints before and after wall time for: a 47-node graph evaluated 200 times; the same graph as a subgraph called four times in one evaluation. Target: repeat evaluation at least 5 times faster than the pre-round code, measured and reported honestly.
- Threaded mode on a graph with independent branches gives identical stream hashes to sequential, run over the whole golden set.
- Output cache on gives identical hashes to off over the golden set, with a non-zero hit count on a graph evaluated twice.

### WP2: spatial data (agent A2)

Owns: new directory `demo/addons/flow_nodes_editor/spatial/`; `flow_data.gd` regions for `shape` typing and spatial helpers only; nodes `surface_sampler`, `volume_sampler`, `sample_spline`, `create_surface_from_polygon`, `create_surface_from_spline`, `projection`, `difference`, `intersection`, `union`, `filter_data_by_type`, `scan_splines`, `scan_meshes`, `make_bounds`; new node files. Do not edit editor files.

Contract:

```gdscript
class_name FlowSpatial extends RefCounted     # abstract, immutable value object
func get_kind() -> int                         # FlowData.Kind.Spline / Surface / Volume (composites report Surface or Volume)
func get_bounds() -> AABB                      # world space
func sample_density(world_pos : Vector3) -> float          # 0..1, steepness-aware where the shape has a falloff
func project(world_pos : Vector3) -> Dictionary            # {} or {position, normal, density}; surfaces only
func to_points(settings : Dictionary = {}) -> FlowData.Data  # default concrete sampling ("To Point")
func content_hash() -> int
```

Concrete shapes (each in its own file): `FlowSplineShape` (copy of a `Curve3D` plus `Transform3D`, closed flag), `FlowPolygonSurface` (closed XZ polygon with transform and optional height), `FlowMeshSurface` (triangles with an acceleration grid; `project` is nearest or vertical hit), `FlowHeightfieldSurface` (float grid, cell size, origin; builders from `HeightMapShape3D` and from a heightmap `Image`), `FlowBoxVolume`, `FlowSphereVolume`, `FlowMeshVolume` (inside test), `FlowCompositeShape` (`Union`, `Intersection`, `Difference` of two shapes, density combined by the same density functions `difference` already offers).

`FlowData.Data.shape` is typed `FlowSpatial` (the placeholder exists; keep `copy_meta_from` and `content_hash` consistent). A shape-bearing Data may have zero points. `Data.kind` follows `shape.get_kind()` when a shape is set.

Behaviour:
- **Sources.** New nodes `get_spline_data` (from `Path3D` nodes, replaces the scene-node `node` stream for shape-aware consumers while `scan_splines` keeps working), `get_surface_data` (from `MeshInstance3D`s, `HeightMapShape3D`, heightmap `Image`), `get_volume_data` (from `CollisionShape3D`, `Area3D`, CSG, mesh bounds), `to_point` (concrete sampling of any shape), `get_bounds` additions for shapes.
- **Consumers.** `sample_spline`, `surface_sampler`, `volume_sampler` accept shape-bearing Data in addition to today's inputs. Sampling a surface within a volume or another surface (composite) must work **before** points exist.
- **Set operations.** `difference`, `intersection`, `union`: shape with shape gives a composite; points with shape attenuate or filter points by `sample_density`, using the same `density_function` setting.
- **Projection.** `projection` gains a surface-projection mode against a shape input. Physics mode stays the default.
- **`create_surface_from_*`** gain `output_mode : Points | Shape` (default Points, today's output).
- **`filter_data_by_type`** classifies by `Data.shape` when present.
- Shapes cross the graph boundary through `copy_meta_from` already; verify with a subgraph test.

### WP3: spawner parity (agent A3)

Owns: `nodes/spawn_meshes*.gd`, `spawn_scenes*.gd`, `spawn_nodes*.gd`, `apply_on_actor*.gd`, new spawner nodes and a new `spawn/` directory.

- **Mesh descriptor.** A `FlowMeshSpawnEntry` resource (mesh, weight, material override, cast shadow, visibility range begin and end with fade, render layers, GI mode, per-instance custom data from attributes, collision) used by `spawn_meshes` in addition to today's `mesh` and `mesh_variants`, which keep working unchanged. Collision modes: none, box from bounds, convex, trimesh; physics layer and mask; a generated `StaticBody3D` per instance or per MultiMesh cell.
- **Selectors.** Weighted random, by attribute (index or name), by index cycling, all driven by the per-point seed, matching what Unreal's mesh selectors expose.
- **`spawn_spline_mesh`.** Deforms a mesh along each segment of a spline shape or `Path3D` (Godot has no spline-mesh component, so generate a bent `ArrayMesh` per segment, cached by mesh and segment hash). Settings: forward axis, tangent handling, scale along and across, per-segment mesh selection.
- **Attribute-driven spawn.** `spawn_scenes` and `spawn_nodes` gain `property_overrides` (point attribute name to node property path, including nested paths and `%unique` names) applied after instancing, with type coercion.
- **`create_target_node`.** Creates a named `Node3D` container (group, optional owner policy), outputs a reference stream that spawners can use as their parent through a `spawn_parent_attribute` setting. Unreal's Create Target Actor.
- **Pooling.** A `FlowSpawnPool` that reuses `MultiMeshInstance3D` and spawned scene roots across regenerations of the same component and node when mesh, material and count class match, instead of free and recreate. Off by default (`FlowGraphNode3D` stays untouched; the setting lives on the spawner nodes as `reuse_instances : bool = false`). Cleanup semantics from `docs/RUNTIME_API_P0.md` (`flow_owner` meta `{component, node}`, `transient_output`, stale ids) must be preserved.
- All spawners keep working owner-less with the documented error. They are main-thread elements.

### WP4a: attribute types and type-dependent nodes (agent A4a)

Owns: `flow_data.gd` regions for `DataType`, `newContainerOfType`, `writeValue`, `filteredStream`, `cloneStream`, `_inferContainerType` and the canonical-type table only; new node files; `visualization/table_view.gd` only if new types do not display.

- **New `DataType` values**, appended before `Invalid = 999`: `Vector2 = 10` (`PackedVector2Array`), `Vector4 = 11` (`PackedVector4Array`), `Transform = 12` (typed `Array` of `Transform3D`), `Int64 = 13` (`PackedInt64Array`), `Double = 14` (`PackedFloat64Array`). `PackedVector4Array` already infers to `Quaternion`; `Vector4` must always be registered with an explicit type, and inference stays as is.
- Every `match` over `DataType` in `flow_data.gd` and in the nodes you ship must handle the new values; add a test that walks all `DataType` values through container creation, write, filter, clone, duplicate and merge.
- **Nodes** (new files): `attribute_cast` (any numeric or vector type to another, with explicit loss rules), `make_transform_attribute`, `break_transform_attribute`, `copy_attribute` (transfer attributes between two inputs by index, match attribute, or nearest point), `attribute_string_op`, `bitwise_op`, `compare_op` (dedicated node with the Unreal operator set, outputs a bool attribute), `merge_attributes`, `gather` (UE semantics, distinct from `merge`), `vector_op`, `transform_op`, `trig_op`, plus any other attribute-family node from the Unreal 5.5 to 5.7 node list that is missing and cheap. Audit and extend `add_attribute`, `attribute_rename`, `remove_attribute`, `merge`, `partition`, `filter`, `compose_vector`, `decompose_vector`, `expression` for the new types where it is natural.
- Selector syntax additions in `findStream`: `$Position`, `$Density`, `$Seed`, `$Rotation`, `$Scale`, `$BoundsMin`, `$BoundsMax`, `$Steepness`, `$Color` as aliases for the canonical streams, and `@Source` where a source attribute exists. Aliases only add names.

### WP4b: point and geometry node coverage (agent A4b)

Owns: new node files and their settings only.

`apply_scale_to_bounds`, `split_points`, `find_convex_hull_2d`, `discard_points_on_irregular_surface`, `create_points` (explicit point list with transforms and attributes), `filter_data_by_index`, `get_attribute_from_point_index`, `get_property_from_object_path` (read a property from a node or resource path, with the same `import_properties` semantics as `scan_nodes`), `runtime_quality_branch` and `runtime_quality_select` (quality level from `ctx.runtime_params["quality"]`, then the `flow_nodes/quality_level` project setting, default 0), `weighted_point_sampler`, `point_match_and_set` equivalents if the dictionary lists one as missing, and any other high-value point-family node from the Unreal 5.5 to 5.7 list that is missing here. Do not add attribute-type nodes (WP4a) or spatial-data nodes (WP2). Do not implement named reroutes (editor work).

## Wave B (WP1 to WP4b are merged; this is the next round)

Everything in the rules and environment sections above still applies, with these updates:

- Baseline is now **2182 cases, 0 failures, 2 skipped, 1 orphan (exit 101)**.
- Node scripts are `RefCounted` **elements** now. Never call `free()` on them in tests; type helpers as `FlowNodeBase`. Editor widgets are `FlowNodeWidget`.
- Every new node needs a row in `executor/flow_node_traits.gd` (`[main_thread, cacheable]`; the traits test fails otherwise) and, if it reads the scene, an entry in `SCENE_DEPENDENT_TEMPLATES` in `node.gd`. These two central edits are allowed for every package; keep them to your own rows.
- `docs/_round2/WP1.md` to `WP4b.md` describe what is already in. Read the ones that touch your area.

### WP5: hierarchical and runtime generation (agent B1)

Owns: new directory `demo/addons/flow_nodes_editor/world/`; `nodes/grid_size*.gd`; `flow_node.gd` (`FlowGraphNode3D`); `EvaluationContext` fields in `flow_data.gd`; small additions to `executor/flow_executor.gd`; new nodes `get_execution_bounds` and `cull_points_outside_bounds`.

Semantics (match Unreal's hierarchical generation):

1. **Levels.** A node's level is the grid size set by the nearest `grid_size` node upstream of it (the node is downstream of the marker). A node downstream of several markers takes the **smallest** grid size. Nodes with no marker upstream are on the **Unbounded** level, executed once for the whole world. Levels are computed at compile time from topology (add this to `FlowCompiledGraph`), not through `ctx.variables`; `grid_size` stays a pass-through node. Cell sizes are powers of two.
2. **Cells.** A cell is `(level, coord : Vector2i)` on the XZ plane. Its bounds are `AABB(Vector3(cx*size, world_min_y, cz*size), Vector3(size, world_height, size))`. Bounds are half-open on the min side so adjacent cells never both own a point.
3. **Per-cell execution.** A cell evaluates only the nodes of its level, using `FlowExecutor` with `node_filter` and `preseeded`. Outputs of coarser levels that its nodes consume are passed in whole, from the coarse cell containing it (or the Unbounded run). Coarser results are computed once and cached per world. `EvaluationContext` gains `bounds : AABB`, `has_bounds : bool`, `grid_size : float`, `cell_coord : Vector2i`, `hierarchy_level : int`; they are 0 or false outside world generation.
4. **Seeds.** The world seed is passed unchanged to every cell, so position-hashed randomness is continuous across cell edges. `cell_coord` is exposed for graphs that want variation.
5. **Nodes.** `get_execution_bounds` outputs the current cell bounds as a box volume shape (and as a one-point bounds Data when `output_mode = Points`), or the world bounds outside world generation. `cull_points_outside_bounds` keeps points whose position is inside the current cell bounds (half-open), with a setting for using point bounds instead of centers and a margin; outside world generation it is a pass-through.
6. **`FlowWorld3D`** (`Node3D`). Exports: `graph`, `seed`, `params`, `overrides`, `world_bounds : AABB`, `generation_mode : Manual | OnLoad | Runtime`, per-level `generation_radius` and a `cleanup_radius_multiplier` (default 1.1), `frame_budget_ms`, `max_concurrent_cells`, `threaded`, `output_cache`, `cell_pool_size`. Generation sources are nodes in group `flow_generation_source`, plus an optional explicit `sources : Array[NodePath]`; a `FlowGenerationSource` helper node adds a per-source radius scale.
7. **Cell components.** Each generated cell is a `FlowGraphNode3D` child (container named `FlowCell_L<level>_<x>_<z>`) executed through a new `FlowGraphNode3D.generate_cell(cell, preseeded)`; spawners use it as `ctx.owner`, so existing cleanup, ownership and `transient_output` semantics apply per cell.
8. **Runtime scheduler.** Each frame: collect source positions, find cells within each level's generation radius, queue by (coarse level first, then distance), run with the frame budget on time-sliced execution, respect `max_concurrent_cells`, and clean up cells beyond the cleanup radius. Cell states: Queued, Generating, Generated, CleaningUp. Cleaned cells go to a bounded pool and are reused.
9. **Manual control.** `generate_all()`, `generate_bounds(aabb)`, `generate_cell(level, coord)`, `cleanup_all()`, `cleanup_cell(level, coord)`, `is_busy()`, signals `cell_generated(level, coord)`, `cell_cleaned_up(level, coord)`, `all_generated`.

Required tests: level assignment on diamond and multi-marker graphs; cell bounds and half-open ownership; **partition invariance**: a world-aligned scatter graph generated through cells equals the same graph generated monolithically after culling (state which stock samplers are world-aligned and which are not, and document it); parent-to-child data flow; cell order independence; scheduler with fake sources moving across cells (generation, cleanup radius, pooling, budget respected via an injected clock); manual API; owner-less and cleanup semantics; threaded and cached modes give identical results. Headless-safe throughout.

### WP6: spatial follow-ups and terrain adapters (agent B2)

Owns: `spatial/`, new `terrain/` directory, nodes `difference`, `intersection`, `union`, `get_surface_data`, `sample_terrain_layers`, `surface_sampler` (terrain input only).

1. **Overlap mode for points against a shape.** `overlap_mode : PointCenter | BoundsBox`. `BoundsBox` evaluates the shape over each point's bounds box (a fixed sample set: center, 8 corners, face centers; or exact for boxes and spheres) and combines to one density; this is how Unreal treats point-versus-volume. The point-against-point behaviour is unchanged. Default `BoundsBox`; this feature is new in the branch, so no legacy to preserve, but keep `PointCenter` selectable.
2. **`FlowTerrainAdapter`** (`RefCounted` base): `get_bounds()`, `get_height(x, z)`, `get_normal(x, z)`, `get_layer_names()`, `get_layer_weight(name, x, z)`, `to_surface() -> FlowSpatial`. Adapters: `HeightMapShape3D`, heightmap `Image` with optional splat images per layer, `MeshInstance3D`, and duck-typed Terrain3D and HTerrain adapters that call only documented methods (`data.get_height(Vector3)`, `data.get_normal(Vector3)`, control map queries for Terrain3D; `get_data()`, `get_interpolated_height_at(Vector3)`, `get_heightmap_aabb()`, splat image access for HTerrain). Contract-test the duck-typed ones against fake classes that implement exactly those methods, and say plainly that they were not run against the real plugins.
3. `get_surface_data` takes a terrain adapter source (auto-detect a terrain node by method names, or an explicit node path); `sample_terrain_layers` can read layer weights from an adapter in addition to textures. Existing behaviour is unchanged by default.

### WP7: editor integration (agent B3)

Owns: `data_inspector.gd`, `node_draw_debug.gd`, `executor/flow_node_widget.gd`, `graph_input_parameter*.gd`, `flow_graph_parameters_editor.gd`, `visualization/*`, the type mappings in `node.gd`, `flow_editor.gd` (only where needed). Cannot verify visually in this container; write tests for everything that is not pixels, and list what needs a manual editor check.

1. **Types everywhere.** Port colours, slot types, `newStream` callable path, graph parameter types and the `getFlowDataTypeFromObject` mapping cover Vector2, Vector4, Transform, Int64, Double and Quaternion; `_coerce_input_data` accepts raw Vector2 and Transform3D runtime inputs.
2. **Data inspector.** Rows and columns for the new types (per-component columns for vectors, sorting, text filter without script errors), a summary row for shape-only Data (kind, bounds, point count 0, shape class), and a fix for the `cell_contents` property bug WP4a found.
3. **Viewport debug draw.** In addition to point cubes: spline polylines, box and sphere wireframes, mesh and heightfield surfaces as a sampled grid outline, composites as their parts with a combining indicator; per-point bounds boxes when `bounds_min/max` exist. Drawing code is separated from data preparation so the preparation is testable.
4. **Widget behaviour.** Rebuild ports when `use_bounding_shape`, `projection_mode`, `output_mode` and similar mode settings change (the nodes override `getMeta`); the widget test must cover each node listed in `docs/_round2/WP2.md` and `WP3.md`.
5. **Named reroutes** are covered by `set_variable` and `get_variable`; add dictionary rows, no new node.
6. Update the editor smoke harness if needed so it still covers every registered template.

### WP8: loop and subgraph parity (agent B4)

Owns: `nodes/loop*.gd`, `nodes/subgraph*.gd`, `nodes/get_loop_index.gd`, new loop-related nodes, small helpers in `flow_nodes_io.gd` (keep them minimal and additive).

1. **`loop` iteration modes** (new `iteration_mode`, default `Points` = today's behaviour): `Points`, `Entries` (each Data entry of the input pin, Unreal's collection loop), `Partitions` (group points by an attribute value, sorted by key), `Chunks` (N points per iteration).
2. **Per-iteration runtime parameters** passed to the loop graph: `iteration_index`, `iteration_count`, `iteration_key`, and the partition's per-data attributes; available through bindings and `runtime_params`.
3. **Seeds.** Iteration seed derived from the loop's graph seed and the iteration **key** (not only the index) so adding or removing a partition does not reshuffle the others; document the formula.
4. **Output handling.** `output_mode : Merge | Collection`: merge concatenates as today; collection emits one bulk per iteration so a downstream node runs per entry.
5. **Dynamic subgraph.** `subgraph` and `loop` accept `graph_attribute` (a String or Resource attribute naming the graph for each iteration or partition); graphs are resolved through the compiled-graph cache.
6. **Feedback** (`feedback_param_name`) keeps working in every mode. Recursion guard and error log behaviour unchanged. `get_loop_index` returns the index in every mode and a new `get_loop_key`.
7. Keep editor hooks working through `widget_*` hooks. Performance check: a 100-iteration loop over a 20-node graph is much cheaper than before because of the compiled graph; report the measurement.

### WP9: purity and thread-safety harness (agent B5)

Owns: new tests under `demo/tests/executor/`, and `executor/flow_node_traits.gd` rows. **Do not edit node scripts.** If a node violates a rule, mark it non-cacheable or main-thread in the traits table and report it.

Build a generic **node conformance harness**. For every registered template with default settings and synthetic standard inputs (point Data with common streams, density, seed and a few attributes; empty Data; single-point Data; Data with a shape; a second input where the node declares one), execute the element and check:

1. **No input mutation**: `content_hash` of every input is unchanged after execution.
2. **Determinism**: two executions give equal output content hashes.
3. **Thread equivalence**: for templates the traits table marks threadable, execution on a worker thread equals execution on the main thread.
4. **Cache equivalence**: for templates marked cacheable, a cache hit equals a fresh run, including errors.
5. **Traits consistency**: scripts that call `get_tree`, `ctx.owner`, `ctx.variables`, `ctx.runtime_params`, `RenderingServer`, `PhysicsServer3D` or `ResourceLoader` outside a guard are not marked threadable; report any that are.
Skip, with the reason recorded, nodes that error on synthetic input by design. Produce a report table of every template, its traits, and each check's result in `docs/_round2/WP9.md`. This is the safety net that makes the opt-in threaded and cached modes trustworthy for the 34 nodes added after the executor audit.

### WP10: shared documentation merge for wave A (agent B6)

Docs only; no code. Read `docs/_round2/WP1.md`, `WP2.md`, `WP3.md`, `WP4a.md`, `WP4b.md` and apply their notes to the shared documents, verifying every claim against the code on the branch (read the node files; do not trust the notes blindly):

1. `docs/COMING_FROM_UNREAL_PCG.md`: new and changed dictionary rows, the concept table (spatial data, attribute types, Bounds, Execution model, caching and threading), selector alias table, new sections for the executor model, spatial data, spawners, and attribute types. Remove or update statements that are now false (for example the "no typed spatial lattice" row).
2. `docs/PARITY_ROADMAP.md`: update the status table and replace the sections that are now implemented with short "Implemented" descriptions plus the remaining gaps; add the honest remaining-gap list from the planning notes.
3. `docs/DEPRECATIONS.md`: add the rows from the notes.
4. `demo/addons/flow_nodes_editor/doc/nodes_reference.md`: rows for every new node, with source links. If a generator script exists for this file, use it.
5. `node_templates.csv`: regenerate from the registry so it matches `nodes/` exactly.
6. `README.md` and `demo/addons/flow_nodes_editor/README.md`: feature list, node count (compute it), architecture section, threading and caching options, testing section.
Do not touch `docs/_round2/*`. Do not edit code. Report every statement you changed or removed because it was wrong.

## Merge order and gates

Merge WP1 first (largest blast radius), then WP2, WP4a, WP3, WP4b. After every merge: full suite, import check, golden and seed-zero suites unchanged. The coordinator merges the `docs/_round2/` notes into the shared docs at the end.

## Honest scope limits

- GPU execution is not part of this round. There is no GPU in the build container, so a compute path could not be verified. `compute_kernel` stays the escape hatch.
- Threaded execution is limited by GDScript: anything touching the scene tree, physics or rendering stays on the main thread.
- Time slicing is per node, not inside a node.
