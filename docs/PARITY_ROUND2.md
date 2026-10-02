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
  Current baseline: 1741 cases, 0 failures, 2 skipped, 1 orphan that exits 101.
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

## Wave B (after WP1 and WP2 merge; designs for context)

- **Hierarchical and runtime generation.** `FlowWorld3D` node owning one or more graphs with a grid-size ladder. `grid_size` nodes assign downstream nodes to a level. Cells are power-of-two `FlowGraphNode3D` children, each evaluating its level with `ctx` carrying cell bounds, grid size and cell coordinate; coarser results are passed to finer cells through `FlowExecutor.preseeded`. `cull_points_outside_bounds` node. Generation sources are nodes in group `flow_generation_source`. Per-level generate and cleanup radii, distance priority, a per-frame budget using time-sliced execution, cell pooling and per-cell containers.
- **Terrain adapters.** `FlowTerrainAdapter` interface with adapters for `HeightMapShape3D`, heightmap `Image`, `MeshInstance3D`, and duck-typed Terrain3D and HTerrain nodes (contract-tested with fakes), feeding `get_surface_data` and `sample_terrain_layers`.
- **Loop and subgraph parity.** Loop over a collection of Data (bulks), over partitions of an attribute, or over chunks; per-iteration runtime parameters, seeds keyed by iteration key; dynamic subgraph chosen by an attribute; loop-carried feedback kept.

## Merge order and gates

Merge WP1 first (largest blast radius), then WP2, WP4a, WP3, WP4b. After every merge: full suite, import check, golden and seed-zero suites unchanged. The coordinator merges the `docs/_round2/` notes into the shared docs at the end.

## Honest scope limits

- GPU execution is not part of this round. There is no GPU in the build container, so a compute path could not be verified. `compute_kernel` stays the escape hatch.
- Threaded execution is limited by GDScript: anything touching the scene tree, physics or rendering stays on the main thread.
- Time slicing is per node, not inside a node.
