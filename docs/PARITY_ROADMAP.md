# UE PCG Parity Roadmap

The honest gap list. [COMING_FROM_UNREAL_PCG.md](COMING_FROM_UNREAL_PCG.md) documents what translates today; this file documents what does **not**, why, and the intended design for each gap. Items are roughly ordered by how often a UE tutorial trips over them.

If a tutorial step depends on one of these, the node dictionary marks it **roadmap** and (where one exists) names a workaround.

---

## Implementation status (2026-10)

Two passes have landed. The first (2026-06) added groundwork for every item below. Parity round 2 ([PARITY_ROUND2.md](PARITY_ROUND2.md), package notes in [`_round2/`](_round2/)) rebuilt the executor and added spatial data, the spawner family, extended attribute types and the missing point nodes (wave A), then hierarchical and runtime generation, terrain adapters, loop modes, editor support for the new types and shapes, a node conformance harness and a stabilization pass (wave B). Everything new ships behind optional streams, opt-in flags or new nodes. No existing golden or seed-zero baseline entry changed in round 2 (wave B only added entries for the new hierarchical demo), so existing `.tres` graphs and demos produce the same output; the intended output changes of wave B (set-operation broadphase extents, imported scene transforms, the bounds-box default for points against shapes) change no baselined output and are listed in [DEPRECATIONS.md](DEPRECATIONS.md). A review and performance pass (wave C) followed; see [Wave C hardening](#wave-c-hardening-2026-10). Per-item notes from the first pass live in [`_roadmap_notes/`](_roadmap_notes/).

| Roadmap item | Status | What landed |
|---|---|---|
| Executor architecture (stateless elements, compiled graph) | **Implemented** (round 2) | `FlowNodeBase` is a `RefCounted` element and `FlowNodeWidget` is its editor `GraphNode`; `FlowCompiledGraph` parses a graph once; `FlowExecutor` runs synchronous, time-sliced and threaded modes |
| Threaded execution | **Implemented, opt-in** (round 2) | `FlowGraphNode3D.threaded`; pure elements run on `WorkerThreadPool`, scene, physics, rendering and variable nodes stay on the main thread; output identical to sequential (`FlowNodeTraits`) |
| Output caching (`FPCGGraphCache`) | **Implemented, opt-in** (round 2) | `FlowGraphNode3D.output_cache`; `FlowOutputCache` keyed by settings, seed and input content, LRU, returns copies |
| Node conformance harness | **Implemented** (round 2) | `demo/tests/executor/conformance/`: every registered template checked for input mutation, determinism, worker-thread and cache-hit equivalence; 167 templates, 2244 fixture cases, no failure |
| Hierarchical generation (Grid Size) | **Implemented** (round 2) | Compile-time levels from `grid_size` markers; `FlowWorld3D` cells (one `FlowGraphNode3D` each) with coarse-to-fine data flow; `get_execution_bounds`, `cull_points_outside_bounds`; `grid_fill_bounds.world_anchored` |
| Async / proximity runtime generation | **Implemented** (round 2) | Time-sliced `generate_async()`; `FlowWorld3D` Runtime mode: generation sources, per-level radii, cleanup hysteresis, coarse-first then nearest priority, frame budget, concurrent cells, component pool; OnLoad and Manual modes |
| Landscape data, paint layers, terrain plugins | **Implemented** (round 2; plugin adapters unverified) | `FlowTerrainAdapter` for HeightMapShape3D, heightmap Image with splat images, MeshInstance3D, and Terrain3D / HTerrain by duck typing (tested against fakes only); `get_surface_data` Terrain source with method-based auto-detection; layer weights written by Surface Sampler; `sample_terrain_layers` TerrainAdapter mode |
| Loop and subgraph parity | **Implemented** (round 2) | `loop` iteration modes (Points, Entries, Partitions, Chunks), per-iteration runtime params, key-derived seeds, Merge / Collection output, feedback in every mode; `get_loop_index` LoopIteration source, `get_loop_key`; dynamic subgraphs (`graph_attribute`) on `loop` and `subgraph` |
| Editor integration | **Implemented** (round 2; visual check pending) | Port colours, graph parameters and runtime inputs for every attribute type; Data Inspector columns for every type and shape summaries; viewport debug draw of shapes and point bounds; ports rebuilt when a mode setting changes. See [MANUAL_EDITOR_CHECK.md](MANUAL_EDITOR_CHECK.md) |
| Spatial data type lattice | **Implemented** (round 2) | `FlowSpatial` shapes on `Data.shape` (spline, polygon / mesh / heightfield surfaces, box / sphere / mesh / points volumes, composites); Get Spline / Surface / Volume Data, To Point, Get Bounds; shape-aware samplers, set operations, Projection and Create Surface From *; `filter_data_by_type` by shape |
| Attribute types | **Implemented** (round 2) | `DataType` Vector2, Vector4, Transform, Int64, Double; `$Position`-style selector aliases; 14 attribute-family nodes (`attribute_cast`, `compare_op`, `copy_attribute`, `merge_attributes`, `gather`, the op family, ...) |
| Spawner parity | **Implemented** (round 2) | `FlowMeshSpawnEntry` descriptors (render settings, custom data, collision) and selectors on `spawn_meshes`; `spawn_spline_mesh`; `property_overrides`; `create_target_node` + `spawn_parent_attribute`; opt-in instance pooling (`reuse_instances`) |
| Point and geometry node coverage | **Implemented** (round 2) | Apply Scale To Bounds, Split Points, Reset Point Center, Find Convex Hull 2D, Discard Points On Irregular Surface, Create Points, Filter Data By Index, Get Attribute From Point Index, Get Property From Object Path, Runtime Quality Branch / Select, Bounds From Mesh, `weighted_point_sampler` |
| Per-point BoundsMin/Max + Steepness | **Implemented** | Optional `bounds_min`/`bounds_max`/`steepness` streams; `bounds_modifier` PerPointBounds mode; `Data.getEffectiveBounds()`/`getEffectiveSteepness()`; round 2 adds `apply_scale_to_bounds`, `reset_point_center`, `bounds_from_mesh` |
| Density-aware Difference / Self-Pruning | **Implemented** | `density_function` setting (Binary default / Minimum / Multiply / Subtract) attenuates density instead of hard-removing; round 2 extends it to points against shapes (tested over each point's bounds box, `overlap_mode`) and shape composites |
| Quaternion rotation model | **Implemented** | `DataType.Quaternion`, optional `rotation_quat` stream (wins over Euler), `rotator_op` node; round 2 adds Transform attributes and `make/break_transform_attribute`, `transform_op` |
| Attribute domains (`@Data`) | **Implemented** | `Data.data_attrs` + `@data.<name>` selector; `add_attribute` domain toggle; `partition` stamps per-data key |
| Subdivide Segment | **Implemented** | `subdivide_segment` node |
| Shape grammar | **Implemented** | `grammar_expand` node (UE grammar subset) + `GrammarModuleResourceData` table |
| GPU execution | **Implemented (escape hatch)** | `compute_kernel` node wrapping a user GLSL compute shader via `RenderingDevice` |
| Hardening: node-instance leak | **Done** | Elements are `RefCounted` and dropped after every run (round 2); before that, instances were pooled and freed after evaluation |
| Hardening: editor/runtime topo sort | **Done** | Unified post-order sort with cycle detection; since round 2 the editor runs each node through the same `FlowExecutor.execute_element` as the runtime |
| Hardening: primitive graph-input args | **Done** | `FlowData.Data.writeValue` typed-feed in `_coerce_input_data` |
| Hardening: stream-length invariants | **Done** | `registerStream` warns on non-broadcast length mismatch; since round 2 it also checks the container against the declared type |

---

## Wave C hardening (2026-10)

Wave C (WP13) was an adversarial review of the round-2 code by reviewers who had not written it, plus a performance pass. Each reviewer wrote a failing headless test before every fix; the notes are [`_round2/WP13-R1.md`](_round2/WP13-R1.md) to [`WP13-R5.md`](_round2/WP13-R5.md) and [`WP13-P1.md`](_round2/WP13-P1.md).

| Reviewer | Area | Bugs fixed |
|---|---|---|
| R1 | Executor, evaluator, widget, editor dock evaluation | 8 |
| R2 | Spatial shapes, terrain adapters, shape-aware nodes | 11 |
| R3 | `FlowWorld3D`, cell levels, runtime scheduler | 11 |
| R4 | Spawners, pooling, generated-content ownership | 12 |
| R5 | Attribute types, WP4a / WP4b nodes, `loop`, `subgraph` | 15 |
| **Total** | | **57** |

After the merge the full suite has 2659 cases, 0 failures and 1 orphan, the pre-existing one in `tests/nodes/surface_sampler_test.gd`. No golden baseline entry changed. Three seed-zero entries changed for spawned-node names only (R4). The performance pass (P1) changed no output: it was checked byte for byte (see *Execution and performance* below).

**Behaviour you may notice.** The rows are in [DEPRECATIONS.md](DEPRECATIONS.md) section 2; most fixes only replace a wrong result, an error spam or a hang.
- **Editor and executor (R1).** The dock preview uses the component's `seed`, `overrides` and `params`, as `generate()` does. Nodes added, pasted or restored by undo / redo run at the next dock evaluation. A component removed from the tree during `generate_async()` suspends its run and finishes it when it re-enters. Ten more nodes run one at a time in threaded mode (`LOGGING_TEMPLATES`). A subgraph containing `create_points` and a `clip_points_by_polygon` with `polygon_node_path` now re-run after scene edits.
- **Spatial and terrain (R2).** Merged volume and spline data keep their steepness falloff (union by maximum). `to_point` samples merged splines along their curves. A shape united with an empty point set stays the shape. `BoundsBox` agrees with `PointCenter` on XY / YZ polygon surfaces and tilted heightfields. Level nearest-point projections beside a mesh face up. Spline tubes under a non-uniform scale measure world distance. Terrain3D snapshots with unequal spacings no longer overshoot the terrain. `get_surface_data` rejects `image_cell_size <= 0`. The samplers report the cap error instead of hanging on huge or non-finite bounds.
- **World (R3).** A forced `generate_cell` uses the world's current settings. Runtime mode caps a finite radius at `MAX_RUNTIME_CELLS_PER_LEVEL` cells per level and source. `queue_bounds` after OnLoad went idle generates again. Switching to Runtime after `_ready` starts the scheduler. Runtime mode cleans up the cells of a level removed by a graph edit. A cancelled cell that is wanted again is regenerated instead of being marked Generated with empty outputs. Cell queries normalise the Unbounded coordinate. Freed entries from a source provider are skipped.
- **Spawners (R4).** A spawner fed several bulks, or inside a loop or repeated subgraph, keeps every bulk and iteration. Taken names become `<name>_<k>` instead of colliding auto-names. Content under a spawn parent or target container that is no longer used is removed on the next generation. A missing `%Unique` override target is reported instead of writing into the level. Copies of a component (`duplicate()`, the editor's Duplicate) clean up their copied content. Pooled MultiMeshInstance3Ds are reset. A mesh without surfaces gets no collider. These checks cost time: the second generation of `graph_dungeon_stress_test` (1817 scene instances) went from about 570 to about 650–690 ms.
- **Attributes and loops (R5).** `compare_op` compares integers exactly. A fractional constant against an integer attribute stays fractional. `copy_attribute`, `expression`, `filter` and loop Merge now produce output on inputs that used to raise a script error: broadcast streams, and attribute types that differ between iterations. Loop Merge expands broadcast streams. Partitions keep Int64 and Double values. Missing quaternions default to identity in `copy_attribute` and `merge_attributes`. Inverting a singular transform uses a zero reciprocal scale, as Unreal's `FTransform::Inverse` does. A self-recursive graph leaves an error in `last_errors` (`FlowExecutor.MAX_EVAL_DEPTH = 20`). NaN partition keys sort last. The `attribute_string_op` Format no longer expands tokens inside values.

**Known, not fixed.** The reviewers' suspected issues, deduplicated against *Remaining gaps* below.
- **Executor and editor.**
  - `expression` is not serialized in threaded mode: a bad evaluation raises an engine error on a worker thread. It is the most expensive pure node, so it was left out of `LOGGING_TEMPLATES`.
  - `print()` traces (`settings.trace`) of pure nodes reach Loggers from workers. This is a debug-only path.
  - `FlowOutputCache.max_entries < 0` hangs the eviction loop.
  - The per-script settings property lists (`FlowOutputCache._settings_props`, `FlowExecutor._resource_props`) are never cleared. After an editor hot reload that adds a settings property, the cache key and the settings replay miss it until the graph data or the registry changes.
  - A custom main-thread node that calls `FlowNodeIO.evaluate()` in threaded mode puts its nested errors out of order in `last_errors`. No stock node does this.
  - `cleanup()` during an async run finishes the run first and never emits `generated`, so code awaiting `generated` after `generate_async()` then `cleanup()` waits forever.
- **Spatial and terrain.**
  - Shapes are immutable only by convention. Public packed arrays and objects (`polygon`, `heights`, `curve`, `vertices`, `FlowSurfaceLayers.grids`, ...) are shared by reference. No code in the repository writes them.
  - The bounds of XY / YZ polygon surfaces and tilted heightfields are their outline. A composite such as Intersection(XY polygon, a volume off its plane) therefore has empty bounds and samples nothing.
  - Under a scaled `Path3D`, spline `to_points` intervals and `spline_length` are in curve units.
  - Splat weights from float images (`FlowSurfaceLayers.from_images`, Textures-mode `sample_terrain_layers`) are not clamped to 0..1.
  - `merge` drops `Data.shape` and tags without a warning. The attribute `filter` sends a shape-only Data to both of its outputs.
  - A union of N shapes costs O(N) per density query.
  - The HTerrain fingerprint reads splat texels without decompressing the image. `FlowHeightfieldSurface` used directly still clamps a cell size of 0 or less to 1e-6.
- **World.**
  - Generated cells are kept as they are after a run-time change of the graph (when the levels stay the same), `seed`, `params`, `overrides` or `world_bounds`, and finer cells use their stale coarse data. Call `cleanup_all()` after such a change. A shrinking `world_bounds` can leave cells outside it alive.
  - An idle runtime tick costs about 15 µs per known cell: about 20 ms for 1325 cells with the demo graph, against the 4 ms default budget. Each cell that starts scans every record.
  - Pooled cell components keep the signal connections a user added. User calls to `generate()` or `cleanup()` on a cell component that the world is generating leave the cell Generated with empty outputs.
  - Float keys in `generation_radius` (`16.0`) are ignored silently, and a radius of −INF selects the whole world.
  - A `FlowWorld3D` that is not at the identity transform is unsupported and gives no warning. Freeing the world without `cleanup_all()` leaves content spawned outside it.
  - At extreme coordinates, `coord_of` and `get_cell_at` wrap beyond |p / size| > 2^31. At cell size 1, ownership fails beyond about 1.6e7.
  - `grid_fill_bounds` `world_anchored` gives the same points through cells only below `max_points`.
  - Two documented signal behaviours can surprise: `all_generated` also fires after a busy period that only cleaned up, and a cancelled run emits `cell_cleaned_up` without `cell_generated`.
- **Spawners.**
  - Reusing a pooled MultiMeshInstance3D or segment frees every `StaticBody3D` child, including one a user added by hand.
  - Pool keys of unsaved resources (`#<instance id>`) can match across sessions. Not reproduced.
  - After a scene reload, two components that share a parent and use the same spawner node names can free each other's saved content when only one of them regenerates. `cleanup()` after a reload does not find content outside the component's subtree; the next `generate()` clears it.
  - `segments_for_spline` can mis-segment a curve that passes through one of its own earlier control points.
  - A NaN mesh-entry weight (only possible from code) sends every pick to the last positive entry. A NaN float coerced to an int property gives INT64_MIN.
- **Attributes and loops.**
  - `get_loop_key` truncates Int64 and Double keys.
  - The depth guard stops self-recursion, but a self-referencing loop with N iterations per level runs about N^20 nested evaluations first.
  - Zero quaternions can still come from `attribute_cast` (Vector4 to Quaternion) or a zero Vector4 stream, and `make_transform_attribute` then builds a NaN basis. `break_transform_attribute` and `lerp_transform` log engine errors on a zero-scale basis.
  - With NaN values, `attribute_select` (Min, Max, Median) may depend on the input order.
  - `Data.size()` reads the first registered stream, so a Data whose first stream is a broadcast stream reports 1 point.
  - `attribute_set_to_point` with `transform_attribute_name` leaves a stale `rotation_quat`.
  - Selector alias edges: `create_points` accepts `$Density`, `first("$Density")` does not fall back to a per-data `density`, and `@Source` on `$Index` creates a stream named `Index`.
  - `compare_op` AnyComponent with `!=` means "no component equal". This was not checked against Unreal.
  - `split_points` and `weighted_point_sampler` refuse Int64 and Double attributes.
  - The `expression` result container takes the type of the first point's result.

---

## Remaining gaps

The honest list after both waves of round 2, collected from the package notes ([`_round2/`](_round2/)) and checked against the code.

**Hierarchical and runtime generation**
- Cells are not saved or streamed as level data: there is no World Partition equivalent. `FlowWorld3D` creates its cell components at run time (or from the inspector's Generate All button) and never saves them.
- No editor-viewport generation source: in the editor nothing generates on its own; use Generate All, or run the scene.
- Grid sizes cannot be overridden at run time: levels come from the saved `cell_size` of each `grid_size` marker when the graph compiles, so overrides and `$param` bindings of `cell_size` are not seen.
- Markers inside subgraphs are pass-throughs: a subgraph node runs on its own level and its inner graph runs whole within that cell.
- A finer cell sees only the coarser cell that contains it (as in Unreal), so a fine point near a coarse cell's edge can miss a coarse point just across it.
- `grid_fill_bounds` (unless `world_anchored`), `sample_points` and the count and point-input modes of `surface_sampler` are not world-aligned, so they give different points through cells than in one piece.
- The scheduler was verified with an injected clock and fake sources plus a 1500-frame headless run of the demo. Frame times with heavy graphs, and cameras or players as sources in a real game loop, were not measured. Time slicing is per node, so one heavy node can overrun `frame_budget_ms`.

**Execution and performance**
- No GPU execution of the graph. `compute_kernel` is the escape hatch, as Custom HLSL is in UE; there was no GPU in the build container to verify a compute path.
- Per-point hot loops are GDScript. The native extension covers the spatial queries (`GDKdTree`, `GDRTree`) and stream sorting (`GDStreamUtils`); moving `getTransformsStream`, `transform`, `filteredStream`, `merge` and `attribute_filter_range` loops into it is not done ([PCG_SYSTEM_REVIEW.md](PCG_SYSTEM_REVIEW.md), P3). The wave C performance pass ([`_round2/WP13-P1.md`](_round2/WP13-P1.md)) made 14 GDScript hot paths faster with byte-identical output. Typical speedups from 1k to 100k points: `expression` 4 to 7 times; `attribute_filter_range` / `density_filter` and `point_offsets` about 4 times; `filter` and `sample_points` about 3 times; `difference` about 2 times; `transform` / `transform_points` 1.6 to 2 times; `grid` 1.3 to 1.4 times. The per-case table and the native candidates, with how to gate them, are in that note. Two new scripts in `demo/tests/perf/` support this work; they are scripts, not tests. `node_benchmark.gd` times 25 node cases, 12 data-layer primitives and the executor phases at 1k, 10k and 100k points (`FLOW_NB_FINGERPRINT=1` prints an exact output hash per case). `exact_fingerprint.gd` prints a SHA-256 of the raw output bytes and logged messages of every golden graph and node, which catches last-bit changes that the golden suite's 1/1000 rounding hides.
- Time slicing is per node, not inside a node: one heavy node still costs one frame.
- Threaded mode is limited by GDScript. Anything that touches the scene tree, physics or rendering, spawns, or reads graph variables or runtime params stays on the main thread. Graphs of many small nodes do not get faster (object allocation contends in the engine); compute-bound independent branches do (about 2.9 times on 4 cores in the round-2 benchmark). Group tasks are submitted at high priority, because low-priority `WorkerThreadPool` tasks get only about 30% of the pool's threads.
- Threaded mode and script Loggers: errors printed outside `setError` reach every `OS.add_logger` Logger on the worker thread. The nodes known to log that way run one at a time (`FlowNodeTraits.LOGGING_TEMPLATES`), which is a mitigation, not a fix: an unforeseen engine error from another pure node still reaches Loggers concurrently.
- Without the output cache, repeat evaluation is about 3.1 to 3.2 times faster than before round 2; the 5 times target was met only with `output_cache` on. The rest of the time is spent in node bodies (per-point GDScript loops, `Data` copies). After the wave C performance pass, the 47-node scenario of `executor_benchmark.gd` (scenario A, sequential) went from about 12.7 to about 9.4 ms per evaluation, and the subgraph scenario B from 50.6–55.9 to 37.6–38.7 ms. The node bodies went from 8.4 to 5.8 ms, while the executor's build and finalize phases barely moved.
- The output cache keys resources referenced from settings by identity: after editing a Curve or Mesh in place, call `FlowOutputCache.clear()`. Data fingerprints are 32-bit hashes plus sizes, so a collision is possible in principle (none was observed on the golden set).
- The conformance harness is evidence, not proof: a worker batch runs three copies of one element, not every interleaving or pairs of different templates; the static scan is a regular-expression heuristic that does not follow calls into helper classes; the executor prewarms Curves and Gradients but not Meshes before a threaded batch.

**Spatial data and terrain**
- Points against a shape use an axis-aligned bounds box (point rotation is ignored, Unreal tests the rotated box), and the overlap is exact only for axis-aligned boxes and spheres; other shapes are tested at 15 fixed samples and can miss a small shape inside a large point box.
- Surfaces are sampled along the world vertical (heightfields along their local Y). Vertical walls (XY / YZ polygon surfaces) can be projected onto and density-tested, but the surface sampler finds no hits on them.
- Convex collision shapes become the box of their points in `get_volume_data`; capsules and cylinders are meshed.
- The Terrain3D and HTerrain adapters were tested only against fakes of the plugin APIs, never against the real plugins, alone or with both installed in one project. Unchecked assumptions: where a Terrain3D region starts, the meaning of the control map's blend value, HTerrain's cell-space height argument and fallback transform, and its splat channel constant. Terrain3D without readable regions needs explicit `terrain_bounds`.
- Terrain layer lookups take the nearest-lower texel (no filtering); Terrain3D layers are snapshotted at vertex spacing in `to_surface()`. A union composite exposes one operand's layers, not the layers of the operand that was hit. An HTerrain snapshot reads every cell (about 263 000 calls for a 513² terrain).
- No pin colour per spatial kind; spline and surface outputs reuse the NodePath and NodeMesh colours.

**Attribute types**
- `math_op`, `sort`, `reduce`, `attribute_filter_range`, `attribute_noise`, `mutate_seed`, `point_neighborhood`, `texture_sampler`, `sample_terrain_layers` and `compute_kernel` reject the new types with an "unsupported type" error; cast first with `attribute_cast`, or use `vector_op` / `trig_op`.
- `scan_nodes` and `get_property_from_object_path` still skip Vector2, Vector4, Quaternion and Transform3D metas and properties (kept for output compatibility).
- Exposed node settings of type `int` or `float` are Int or Float ports, never Int64 or Double: GDScript properties carry no 64-bit distinction.
- `partition` keys Double values by their string form, so values that differ only after about 14 significant digits share a partition.
- Transform attributes compose as rotation times scale (`make_transform_attribute`, `transform_op`), while the point transform helpers use scale then rotation; the two agree for uniform scale only.
- No `$Transform` virtual selector (use `make_transform_attribute` with its defaults), no `@LastCreated`, no swizzles (`$Position.ZYX`).
- `merge_attributes` and `gather` follow Unreal's documented behaviour as reconstructed from memory, not checked against the engine.

**Spawners**
- `FlowMeshSpawnEntry` has one material override (no per-slot overrides), no per-instance LOD or world-position-offset settings, and packs at most four custom-data floats.
- `spawn_spline_mesh` has no per-point roll or scale interpolation from spline attributes and does not carry blend shapes. On composite spline data it spawns every spline part whole: the other operand of an intersection or difference does not clip the meshes.
- Instance pooling reuses content across repeated `generate()` calls only; `regenerate()` and `cleanup()` free everything.
- `cleanup()` no longer finds content stamped by hand with a `{component: id}` dictionary outside the component's subtree without `tagFlowContent` or `flowOwnerMeta` (no stock code does that).
- Headless tests cannot read back per-instance MultiMesh transforms, colours or custom data (the dummy renderer keeps none).

**Nodes and loops**
- Discard Points On Irregular Surface measures the input point cloud (neighbours inside each point's X/Z footprint), not physics traces against the world.
- Get Property From Object Path reads object paths from its settings, not from an input attribute, and does not extract structs or object references.
- Proxy has no node. Named reroutes are `set_variable` / `get_variable`; the search popup does not find them by the Unreal names.
- `loop` has one feedback parameter (Unreal allows several feedback pins). Points, Partitions and Chunks iterate per input entry; only Entries spans all entries of the pin. Index keys in Chunks and Entries mode shift when an earlier iteration is removed (use `key_attribute` in Entries mode for stable seeds). `subgraph` has no skip or stop policy for an unusable dynamic graph.
- Choosing `Invalid` (999) as a `data_type` in an inspector drop-down still raises script errors in nodes that index `DataType.keys()` with it (`add_attribute.getTitle`, for instance).

**Authoring tools**
- No Validate action (unconnected required inputs, unreachable nodes, output name collisions, stream-type conflicts, missing subgraph resources), no "Run with…" panel for seed, inputs and runtime params, and no public `FlowEditorPlugin.open_graph` ([PCG_SYSTEM_REVIEW.md](PCG_SYSTEM_REVIEW.md), P2).

**Editor (not verified visually)**
- Headless runs use the dummy renderer and no editor, so the dock's mouse interaction, drawing, inspector and undo wiring, hot reload, the 3D debug draw (point cubes, shape lines, bounds boxes), the Data Inspector table, port colours, the graph-parameter editor, the loop inspector options, `FlowWorld3D`'s inspector buttons and the hierarchical demo were tested through their data only. [MANUAL_EDITOR_CHECK.md](MANUAL_EDITOR_CHECK.md) is the 40-minute check list for a human with the editor.
- A link dropped by a port rebuild (a mode setting turned off) is not restored by undoing the setting change.

---

## Executor architecture, threading and caching

**Implemented in round 2.** Unreal splits a node into settings, a stateless element and a compiled task graph. Here: `NodeSettings` resources hold the settings; `FlowNodeBase` is the element, a `RefCounted` created fresh for every run (node scripts still `extends FlowNodeBase`); `FlowNodeWidget` is the `GraphNode` the editor shows, and nodes that build UI implement optional `widget_*` hooks. `FlowCompiledGraph.for_graph(graph)` parses a graph once and keeps the result on the graph until `graph.data` or the node registry changes. `FlowExecutor` is the only executor, with synchronous, time-sliced and threaded modes and two hooks for hierarchical generation (`node_filter`, `preseeded`). `FlowNodeTraits` marks each template main-thread and/or cacheable. Threaded mode (`FlowGraphNode3D.threaded`) and the output cache (`FlowGraphNode3D.output_cache`, `FlowOutputCache`) are off by default and produce the same output as the plain run. In threaded mode the templates known to print errors outside `setError` (`FlowNodeTraits.LOGGING_TEMPLATES`) run one at a time, and `FlowNodeTraits.resolve` warns once when a `meta_node` flag contradicts the template's table row. The node conformance harness (`demo/tests/executor/conformance/`) runs every registered template through `FlowExecutor.execute_node` and fails on input mutation, non-determinism, a worker-thread result that differs from the main-thread one, or a cache hit that differs from a fresh run.

**Remaining gaps:** see *Execution and performance* above.

## Per-point BoundsMin/BoundsMax + Steepness

**Implemented.** Optional `bounds_min` / `bounds_max` Vector streams and a `steepness` Float stream are canonical attributes. When they are absent, consumers derive bounds from `size` as before, so existing graphs are untouched. `bounds_modifier` has a PerPointBounds mode, `Data.getEffectiveBounds()` / `getEffectiveSteepness()` resolve them, and the size-to-bounds generators write unit scale plus explicit bounds (`legacy_scale_from_extent` restores the old output). Round 2 adds `apply_scale_to_bounds`, `reset_point_center`, `split_points` and `bounds_from_mesh`.

**Remaining gaps:** points against spatial shapes are tested with an axis-aligned bounds box, ignoring point rotation (see *Spatial data and terrain*).

## Per-point bounds in Difference / Self Pruning

**Implemented.** `difference` and `self_pruning` read `bounds_min`/`bounds_max` and steepness when present, and `difference` has a `density_function` setting (`Binary`, the default and the old behaviour, `Minimum`, `Multiply`, `Subtract`) that attenuates density instead of dropping points. Since round 2 the same density functions combine points with spatial shapes and shapes with each other.

## Quaternion rotation model

**Implemented.** `DataType.Quaternion` and the optional `rotation_quat` stream, which wins over the Euler `rotation` when present; `rotator_op` provides Combine / Invert / Lerp / RotateAroundAxis on either representation. Euler degrees stay the default authoring representation. Round 2 adds Transform-typed attributes (`Array[Transform3D]`) with `make_transform_attribute`, `break_transform_attribute` and `transform_op`, so Make/Break Transform Attribute and Transform Op now translate.

**Remaining gaps:** the scale/rotation order mismatch for non-uniform scale (see *Attribute types* above).

## Hierarchical generation (Grid Size)

**Implemented in round 2.** `FlowWorld3D` generates a graph over a world in cells. Nodes downstream of a `grid_size` marker run once per cell of its size (the smallest marker wins), and the rest run once (Unbounded). `FlowCompiledGraph` computes the levels from the topology. Coarser cells are generated first, and their outputs are handed whole to the finer cells they contain. Each cell is its own `FlowGraphNode3D` (`FlowCell_L<size>_<x>_<z>`), so spawned content, cleanup and ownership work per cell; `cleanup()` is scoped to the component's own content, so cleaning one of many cells stays cheap. `get_execution_bounds` and `cull_points_outside_bounds` give graphs the cell bounds (half-open on X and Z). World-aligned samplers (Surface Sampler on surface data with a Bounding Shape, Volume Sampler and To Point on volumes, `grid_fill_bounds` with `world_anchored`) give the same points through cells as in one piece; the demo is `demos/demo_hierarchical.tscn`.

**Remaining gaps:** see *Hierarchical and runtime generation* above.

## Async / proximity runtime generation

**Implemented in round 2.** Time-sliced generation: `FlowGraphNode3D.async_generation` with `frame_budget_ms`, or `FlowNodeIO.begin_evaluation` driven by `step(budget_ms)`, both on `FlowExecutor`. Proximity generation: `FlowWorld3D.generation_mode = Runtime` queues the cells within each level's `generation_radius` of the generation sources (the group `flow_generation_source`, `FlowGenerationSource` nodes, `sources`), coarse levels first and then nearest, runs them time-sliced within `frame_budget_ms` and `max_concurrent_cells`, cleans up cells beyond radius × `cleanup_radius_multiplier` and pools their components. `OnLoad` queues every cell when the game starts; `Manual` is the synchronous API (`generate_all`, `generate_bounds`, `generate_cell`, `cleanup_cell`, `cleanup_all`).

**Remaining gaps:** see *Hierarchical and runtime generation* above.

## Loops and dynamic subgraphs

**Implemented in round 2.** `loop.iteration_mode` iterates per point (the default, as before), per data entry (Unreal's Loop), per attribute partition or per chunk of points. Every iteration gets `iteration_index`, `iteration_count` and `iteration_key` as runtime params (plus per-data attributes in Entries and Partitions mode), and its seed derives from the graph seed and the key, so removing a partition leaves the others unchanged. `output_mode = Collection` emits one entry per iteration. Feedback works in every mode. `get_loop_index` gains a LoopIteration source and `get_loop_key` returns the key. `loop` and `subgraph` take `graph_attribute` to pick the graph per iteration or per entry, resolved through the compiled-graph cache.

**Remaining gaps:** see *Nodes and loops* above.

## Editor integration

**Implemented in round 2.** Port colours, slot types, graph parameter types and runtime input coercion cover Vector2, Vector4, Quaternion, Transform, Int64 and Double. The Data Inspector has columns, numeric sorting and a text filter for every type, and a summary table for shape-only Data. The viewport debug draw shows splines, box and sphere wireframes, surfaces as draped grids, composites with an operation marker and per-point bounds boxes. Node widgets rebuild their ports when a mode setting changes the layout, and drop the links into removed ports. Everything below the pixels is tested headless; the pixels need [MANUAL_EDITOR_CHECK.md](MANUAL_EDITOR_CHECK.md).

**Remaining gaps:** see *Editor (not verified visually)* above.

## GPU execution

**Gap.** UE 5.5+ fuses GPU-flagged nodes (Custom HLSL, GPU spawner/copy/transform/partition...) into compute graphs operating on point buffers, including GPU-resident instancing with no CPU readback. Everything here is CPU GDScript plus a native C++ GDExtension for KdTree/RTree queries.

**Design.** Not planned as node-graph-on-GPU. The pragmatic path: (a) keep moving per-point hot loops (transform, noise, filtering) into the existing GDExtension, which already gives order-of-magnitude wins without changing semantics; (b) where massive counts genuinely matter, the `compute_kernel` node wraps a user-supplied `.glsl` compute shader via `RenderingDevice`, with declared stream bindings in and out — an escape hatch equivalent to Custom HLSL rather than a transparent "Execute on GPU" flag. There is no GPU in the build container, so a compute path could not be verified in round 2. Honest assessment: lowest priority; tutorial parity almost never needs it.

## Spatial data type lattice

**Implemented in round 2.** A Data carries point streams, a spatial shape (`Data.shape`, a `FlowSpatial`), or both. Shapes are splines (`FlowSplineShape`), surfaces (`FlowPolygonSurface`, `FlowMeshSurface`, `FlowHeightfieldSurface`), volumes (`FlowBoxVolume`, `FlowSphereVolume`, `FlowMeshVolume`, `FlowPointsVolume`) and composites (`FlowCompositeShape`: Union, Intersection, Difference with the Binary / Minimum / Multiply / Subtract density functions). Every shape answers `get_bounds`, `sample_density` (steepness-aware where it has a falloff), `project` (surfaces) and `to_points`. `Data.kind` follows the shape, so `filter_data_by_type` classifies by it.

The algebra works before sampling, as in Unreal. Intersect a landscape with a volume or a closed-spline surface, subtract a road spline, then sample: `get_surface_data → intersection(get_volume_data) → surface_sampler`. Points still work everywhere: a point set against a shape is filtered or density-attenuated by the shape's density over each point's bounds box (`overlap_mode = BoundsBox`, the default; exact for axis-aligned boxes and spheres, 15 fixed samples otherwise) or at its centre (`PointCenter`), and a shape minus points treats the points as box volumes. Shapes are immutable value objects that copy their source geometry when they are created, so cached results never change under scene edits and queries are thread-safe.

**Remaining gaps:** see *Spatial data and terrain* above.

## Shape grammar nodes

**Implemented.** `grammar_expand` expands a grammar string (the documented UE subset: sequences, `[symbol,behavior]` tuples, repetition `*` / `:N`, weighted choice `{}`) against a module table (`GrammarModuleResourceData`: symbol, size, weight) into one fitted point per module, ready for `match_and_set` / `spawn_meshes`. `subdivide_segment` provides the geometric substrate.

## Landscape data and paint layers

**Implemented in round 2 (plugin adapters unverified).** `FlowTerrainAdapter` (`terrain/`) reads heights, normals and paint-layer weights from a `HeightMapShape3D`, a heightmap image with optional splat images, a terrain `MeshInstance3D`, and, by duck typing, Terrain3D and HTerrain nodes, and builds an immutable surface shape that carries the layer weights. `get_surface_data` with `source = Terrain` uses it, with an explicit `terrain_node_path` or auto-detection of the one terrain plugin node in the scene by its methods. Surface Sampler and To Point write one `layer_<name>` weight per paint layer on terrain surfaces. `sample_terrain_layers` reads mask textures (the default) or, with `layer_source = TerrainAdapter`, a terrain's layers; filter downstream with `density_filter` or `attribute_filter_range`.

**Remaining gaps:** the Terrain3D and HTerrain adapters were tested against fakes only; see *Spatial data and terrain* above.

## Subdivide Segment

**Implemented.** `subdivide_segment` slices spline or two-point spans into sized sub-segments by module lengths or a target count, with stretch / clip / pad-end fitting, and emits one oriented point per sub-segment with `length`, `segment_index`, `t_start` and `t_end`. Floor stacking is expressible with `duplicate_point` and a Y offset (≈ Duplicate Cross-Section).

## Attribute domains (`@Data` / `@Points` / `@Elements`)

**Implemented.** `Data.data_attrs` holds per-data attributes next to `tags`, surviving `duplicate()` / `filter()`; the `@data.<name>` selector reads them broadcast and writes them in `registerStream`. `add_attribute` has a domain toggle and `partition` stamps its key as a per-data attribute.

**Remaining gap:** `@Elements` has no equivalent.

---

## Engine-hardening notes (not UE features, but parity blockers)

**All four items below are resolved.**

- ~~**Runtime evaluator leaks node instances per evaluation**~~ → **Fixed**, then made moot in round 2: elements are `RefCounted` and released after every run, including inside `loop` and `subgraph` evaluations.
- ~~**Primitive graph-input args crash the runtime feed**~~ → **Fixed.** `_coerce_input_data` wraps supported primitives (float/int/bool/String/Vector3/Color, and since round 2 Vector2/Vector2i/Vector4/Quaternion/Transform3D, typed by the graph parameter for Int64 and Double) into a single-entry `FlowData.Data` before feeding the graph, so `FlowGraphNode3D.execute()` with raw scalar args no longer crashes.
- ~~**Editor and runtime evaluators differ**~~ → **Fixed.** Both share `build_execution_order` — a unified post-order topological sort with cycle detection and `on_stack` recursion guard, plus `_stabilize_consumer_input_order` / `_stabilize_variable_execution_order` for diamond and set-variable edge cases. Since round 2 the editor also executes each node through `FlowExecutor.execute_element`, the runtime's code path.
- ~~**Stream-length invariants are unchecked**~~ → **Fixed.** `registerStream` emits a `print_verbose` warning when a non-broadcast stream's length mismatches existing streams, making length corruption debuggable without breaking production graphs.
