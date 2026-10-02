# UE PCG Parity Roadmap

The honest gap list. [COMING_FROM_UNREAL_PCG.md](COMING_FROM_UNREAL_PCG.md) documents what translates today; this file documents what does **not**, why, and the intended design for each gap. Items are roughly ordered by how often a UE tutorial trips over them.

If a tutorial step depends on one of these, the node dictionary marks it **roadmap** and (where one exists) names a workaround.

---

## Implementation status (2026-10)

Two passes have landed. The first (2026-06) added groundwork for every item below. Parity round 2 ([PARITY_ROUND2.md](PARITY_ROUND2.md), package notes in [`_round2/`](_round2/)) rebuilt the executor and added spatial data, the spawner family, extended attribute types and the missing point nodes. Everything new ships behind optional streams, opt-in flags or new nodes: the golden and seed-zero baselines did not change in round 2, so existing `.tres` graphs and demos produce the same output. Per-item notes from the first pass live in [`_roadmap_notes/`](_roadmap_notes/).

| Roadmap item | Status | What landed |
|---|---|---|
| Executor architecture (stateless elements, compiled graph) | **Implemented** (round 2) | `FlowNodeBase` is a `RefCounted` element and `FlowNodeWidget` is its editor `GraphNode`; `FlowCompiledGraph` parses a graph once; `FlowExecutor` runs synchronous, time-sliced and threaded modes |
| Threaded execution | **Implemented, opt-in** (round 2) | `FlowGraphNode3D.threaded`; pure elements run on `WorkerThreadPool`, scene, physics, rendering and variable nodes stay on the main thread; output identical to sequential (`FlowNodeTraits`) |
| Output caching (`FPCGGraphCache`) | **Implemented, opt-in** (round 2) | `FlowGraphNode3D.output_cache`; `FlowOutputCache` keyed by settings, seed and input content, LRU, returns copies |
| Spatial data type lattice | **Implemented** (round 2) | `FlowSpatial` shapes on `Data.shape` (spline, polygon / mesh / heightfield surfaces, box / sphere / mesh / points volumes, composites); Get Spline / Surface / Volume Data, To Point, Get Bounds; shape-aware samplers, set operations, Projection and Create Surface From *; `filter_data_by_type` by shape |
| Attribute types | **Implemented** (round 2) | `DataType` Vector2, Vector4, Transform, Int64, Double; `$Position`-style selector aliases; 14 attribute-family nodes (`attribute_cast`, `compare_op`, `copy_attribute`, `merge_attributes`, `gather`, the op family, ...) |
| Spawner parity | **Implemented** (round 2) | `FlowMeshSpawnEntry` descriptors (render settings, custom data, collision) and selectors on `spawn_meshes`; `spawn_spline_mesh`; `property_overrides`; `create_target_node` + `spawn_parent_attribute`; opt-in instance pooling (`reuse_instances`) |
| Point and geometry node coverage | **Implemented** (round 2) | Apply Scale To Bounds, Split Points, Reset Point Center, Find Convex Hull 2D, Discard Points On Irregular Surface, Create Points, Filter Data By Index, Get Attribute From Point Index, Get Property From Object Path, Runtime Quality Branch / Select, Bounds From Mesh, `weighted_point_sampler` |
| Per-point BoundsMin/Max + Steepness | **Implemented** | Optional `bounds_min`/`bounds_max`/`steepness` streams; `bounds_modifier` PerPointBounds mode; `Data.getEffectiveBounds()`/`getEffectiveSteepness()`; round 2 adds `apply_scale_to_bounds`, `reset_point_center`, `bounds_from_mesh` |
| Density-aware Difference / Self-Pruning | **Implemented** | `density_function` setting (Binary default / Minimum / Multiply / Subtract) attenuates density instead of hard-removing; round 2 extends it to points against shapes and shape composites |
| Quaternion rotation model | **Implemented** | `DataType.Quaternion`, optional `rotation_quat` stream (wins over Euler), `rotator_op` node; round 2 adds Transform attributes and `make/break_transform_attribute`, `transform_op` |
| Attribute domains (`@Data`) | **Implemented** | `Data.data_attrs` + `@data.<name>` selector; `add_attribute` domain toggle; `partition` stamps per-data key |
| Subdivide Segment | **Implemented** | `subdivide_segment` node |
| Shape grammar | **Implemented** | `grammar_expand` node (UE grammar subset) + `GrammarModuleResourceData` table |
| Landscape paint-layer sampling | **Partial** | `sample_terrain_layers` (generic mask-texture path); `get_surface_data` gives height-field surfaces from meshes, `HeightMapShape3D` or a heightmap image; terrain-plugin adapters (Terrain3D, HTerrain) still deferred |
| GPU execution | **Implemented (escape hatch)** | `compute_kernel` node wrapping a user GLSL compute shader via `RenderingDevice` |
| Hierarchical generation (Grid Size) | **Foundation** | `grid_size` declaration node; `FlowExecutor` has the `node_filter` and `preseeded` hooks per-cell execution needs; per-cell partition *execution* still deferred |
| Async / proximity runtime | **Partial** | Time-sliced generation (`FlowGraphNode3D.async_generation`, `begin_evaluation`) runs on `FlowExecutor`; proximity scheduling around generation sources still deferred |
| Hardening: node-instance leak | **Done** | Elements are `RefCounted` and dropped after every run (round 2); before that, instances were pooled and freed after evaluation |
| Hardening: editor/runtime topo sort | **Done** | Unified post-order sort with cycle detection; since round 2 the editor runs each node through the same `FlowExecutor.execute_element` as the runtime |
| Hardening: primitive graph-input args | **Done** | `FlowData.Data.writeValue` typed-feed in `_coerce_input_data` |
| Hardening: stream-length invariants | **Done** | `registerStream` warns on non-broadcast length mismatch; since round 2 it also checks the container against the declared type |

---

## Remaining gaps

The honest list after round 2, collected from the package notes and the round plan. Items marked *wave B* are planned in [PARITY_ROUND2.md](PARITY_ROUND2.md#wave-b-wp1-to-wp4b-are-merged-this-is-the-next-round).

**Execution and performance**
- Hierarchical generation runs nothing per cell yet: `grid_size` only declares a cell size, and a `FlowGraphNode3D` evaluates its whole graph once (*wave B*: `FlowWorld3D`, cells, levels).
- No proximity generation around players or cameras; time-sliced generation is the only runtime scheduling (*wave B*).
- Time slicing is per node, not inside a node: one heavy node still costs one frame.
- Threaded mode is limited by GDScript. Anything that touches the scene tree, physics or rendering, spawns, or reads graph variables or runtime params stays on the main thread. Graphs of many small nodes do not get faster (object allocation contends in the engine); compute-bound independent branches do (about 2.9 times on 4 cores in the round-2 benchmark). Group tasks are submitted at high priority, because low-priority `WorkerThreadPool` tasks get only about 30% of the pool's threads.
- Without the output cache, repeat evaluation is about 3.1 to 3.2 times faster than before round 2; the 5 times target was met only with `output_cache` on. The rest of the time is spent in node bodies (per-point GDScript loops, `Data` copies).
- The output cache keys resources referenced from settings by identity: after editing a Curve or Mesh in place, call `FlowOutputCache.clear()`. Data fingerprints are 32-bit hashes plus sizes, so a collision is possible in principle (none was observed on the golden set).
- The 34 nodes added in round 2 have traits from a central table and their own meta flags, but no generic conformance check yet (input mutation, determinism, thread and cache equivalence) (*wave B*).
- No GPU execution of the graph. `compute_kernel` is the escape hatch, as Custom HLSL is in UE.

**Spatial data**
- A point tested against a shape (Difference, Intersection, Union, the surface sampler's bounding shape) uses the shape's density at the point's position, not the overlap of the point's bounds box with the shape as in Unreal (*wave B*: `overlap_mode`).
- Surfaces are sampled along the world vertical (heightfields along their local Y). Vertical walls (XY / YZ polygon surfaces) can be projected onto and density-tested, but the surface sampler finds no hits on them.
- Convex collision shapes become the box of their points in `get_volume_data`; capsules and cylinders are meshed.
- No terrain-plugin adapters: Terrain3D and HTerrain data must be fed as meshes, `HeightMapShape3D` or images (*wave B*).
- No pin colour per spatial kind; spline and surface outputs reuse the NodePath and NodeMesh colours. The Data Inspector and debug draw do not show shapes: a shape-only Data shows zero rows (*wave B*).

**Attribute types**
- The editor does not know the new types yet: no port colours, typed setting ports or graph parameters of type Vector2, Vector4, Transform, Int64 or Double; raw `Vector2`/`Transform3D` runtime inputs are refused (wrap them in a `FlowData.Data`); the Data Inspector shows them through a generic `str()` column without per-component columns, sorting or filtering (*wave B*).
- `math_op`, `sort`, `reduce`, `attribute_filter_range`, `attribute_noise`, `mutate_seed`, `point_neighborhood`, `texture_sampler`, `sample_terrain_layers` and `compute_kernel` reject the new types with an "unsupported type" error; cast first with `attribute_cast`, or use `vector_op` / `trig_op`.
- `partition` keys Double values by their string form, so values that differ only after about 14 significant digits share a partition.
- Transform attributes compose as rotation times scale (`make_transform_attribute`, `transform_op`), while the point transform helpers use scale then rotation; the two agree for uniform scale only.
- No `$Transform` virtual selector (use `make_transform_attribute` with its defaults), no `@LastCreated`, no swizzles (`$Position.ZYX`).
- `merge_attributes` and `gather` follow Unreal's documented behaviour as reconstructed from memory, not checked against the engine.

**Spawners**
- `FlowMeshSpawnEntry` has one material override (no per-slot overrides), no per-instance LOD or world-position-offset settings, and packs at most four custom-data floats.
- `spawn_spline_mesh` has no per-point roll or scale interpolation from spline attributes, does not carry blend shapes, and takes one spline shape per Data: a merged spline union from `get_spline_data` (`output_mode = Merged`) is not accepted, use `PerSpline`.
- Instance pooling reuses content across repeated `generate()` calls only; `regenerate()` and `cleanup()` free everything.
- Headless tests cannot read back per-instance MultiMesh transforms, colours or custom data (the dummy renderer keeps none).

**Nodes**
- Discard Points On Irregular Surface measures the input point cloud (neighbours inside each point's X/Z footprint), not physics traces against the world.
- Get Property From Object Path reads object paths from its settings, not from an input attribute, and does not extract structs or object references.
- The `flow_nodes/quality_level` project setting is registered when a Runtime Quality node is first instantiated (the editor's add-node scan does this), not by the plugin at startup.
- Proxy and Named Reroute Declaration have no node (`set_variable` / `get_variable` cover named reroutes).
- `loop` runs its graph once per point of the input (once per point of each data entry): no per-entry, partition or chunk modes, no per-iteration key parameters, no graph chosen per iteration (*wave B*).

**Editor (not verified headless)**
- The editor half of the element/widget split was tested through a headless harness. Mouse interaction, drawing (reroute ports, exec-time badges), the inspector and undo wiring, filesystem hot reload, the 3D debug draw and the data-inspector UI still need a manual check in the editor.

---

## Executor architecture, threading and caching

**Implemented in round 2.** Unreal splits a node into settings, a stateless element and a compiled task graph. Here: `NodeSettings` resources hold the settings; `FlowNodeBase` is the element, a `RefCounted` created fresh for every run (node scripts still `extends FlowNodeBase`); `FlowNodeWidget` is the `GraphNode` the editor shows, and nodes that build UI implement optional `widget_*` hooks. `FlowCompiledGraph.for_graph(graph)` parses a graph once and keeps the result on the graph until `graph.data` or the node registry changes. `FlowExecutor` is the only executor, with synchronous, time-sliced and threaded modes and two hooks for hierarchical generation (`node_filter`, `preseeded`). `FlowNodeTraits` marks each template main-thread and/or cacheable. Threaded mode (`FlowGraphNode3D.threaded`) and the output cache (`FlowGraphNode3D.output_cache`, `FlowOutputCache`) are off by default and produce the same output as the plain run.

**Remaining gaps:** see *Execution and performance* above.

## Per-point BoundsMin/BoundsMax + Steepness

**Implemented.** Optional `bounds_min` / `bounds_max` Vector streams and a `steepness` Float stream are canonical attributes. When they are absent, consumers derive bounds from `size` as before, so existing graphs are untouched. `bounds_modifier` has a PerPointBounds mode, `Data.getEffectiveBounds()` / `getEffectiveSteepness()` resolve them, and the size-to-bounds generators write unit scale plus explicit bounds (`legacy_scale_from_extent` restores the old output). Round 2 adds `apply_scale_to_bounds`, `reset_point_center`, `split_points` and `bounds_from_mesh`.

**Remaining gaps:** points against spatial shapes use the point center, not the bounds box (see *Spatial data*).

## Per-point bounds in Difference / Self Pruning

**Implemented.** `difference` and `self_pruning` read `bounds_min`/`bounds_max` and steepness when present, and `difference` has a `density_function` setting (`Binary`, the default and the old behaviour, `Minimum`, `Multiply`, `Subtract`) that attenuates density instead of dropping points. Since round 2 the same density functions combine points with spatial shapes and shapes with each other.

## Quaternion rotation model

**Implemented.** `DataType.Quaternion` and the optional `rotation_quat` stream, which wins over the Euler `rotation` when present; `rotator_op` provides Combine / Invert / Lerp / RotateAroundAxis on either representation. Euler degrees stay the default authoring representation. Round 2 adds Transform-typed attributes (`Array[Transform3D]`) with `make_transform_attribute`, `break_transform_attribute` and `transform_op`, so Make/Break Transform Attribute and Transform Op now translate.

**Remaining gaps:** the scale/rotation order mismatch for non-uniform scale (see *Attribute types* above).

## Hierarchical generation (Grid Size)

**Gap.** UE's HiGen partitions the world into power-of-two grid cells, executes graph sections at different grid sizes (large grids first, results consumed by smaller ones), outputs into separately streamable actors, and dedupes across cells with Cull Points Outside Actor Bounds. Here the `grid_size` node only declares a cell size; a `FlowGraphNode3D` evaluates its whole graph over the whole scene, once.

**Design.** Planned as wave B of round 2 (WP5): levels computed from topology in `FlowCompiledGraph`, a `FlowWorld3D` node that generates cells as `FlowGraphNode3D` children through `FlowExecutor`'s `node_filter` and `preseeded` hooks, coarser levels computed once and passed in whole, `get_execution_bounds` and `cull_points_outside_bounds` nodes, and a runtime scheduler around generation sources. See [PARITY_ROUND2.md](PARITY_ROUND2.md#wp5-hierarchical-and-runtime-generation-agent-b1).

## Async / proximity runtime generation

**Partial.** Time-sliced generation is in: `FlowGraphNode3D.async_generation` with `frame_budget_ms`, or `FlowNodeIO.begin_evaluation` driven by `step(budget_ms)`, both on `FlowExecutor`. Instances are released after every run, primitive graph inputs are wrapped, and the recursion guard is active.

**Gap.** UE's runtime mode generates and cleans up in proximity to generation sources (players, cameras) with per-grid radii. Here generation runs when you call `generate()` / `generate_async()` (or on `_ready`). Proximity scheduling depends on the hierarchical cells above and is part of the same wave B package.

## GPU execution

**Gap.** UE 5.5+ fuses GPU-flagged nodes (Custom HLSL, GPU spawner/copy/transform/partition...) into compute graphs operating on point buffers, including GPU-resident instancing with no CPU readback. Everything here is CPU GDScript plus a native C++ GDExtension for KdTree/RTree queries.

**Design.** Not planned as node-graph-on-GPU. The pragmatic path: (a) keep moving per-point hot loops (transform, noise, filtering) into the existing GDExtension, which already gives order-of-magnitude wins without changing semantics; (b) where massive counts genuinely matter, the `compute_kernel` node wraps a user-supplied `.glsl` compute shader via `RenderingDevice`, with declared stream bindings in and out — an escape hatch equivalent to Custom HLSL rather than a transparent "Execute on GPU" flag. There is no GPU in the build container, so a compute path could not be verified in round 2. Honest assessment: lowest priority; tutorial parity almost never needs it.

## Spatial data type lattice

**Implemented in round 2.** A Data carries point streams, a spatial shape (`Data.shape`, a `FlowSpatial`), or both. Shapes are splines (`FlowSplineShape`), surfaces (`FlowPolygonSurface`, `FlowMeshSurface`, `FlowHeightfieldSurface`), volumes (`FlowBoxVolume`, `FlowSphereVolume`, `FlowMeshVolume`, `FlowPointsVolume`) and composites (`FlowCompositeShape`: Union, Intersection, Difference with the Binary / Minimum / Multiply / Subtract density functions). Every shape answers `get_bounds`, `sample_density` (steepness-aware where it has a falloff), `project` (surfaces) and `to_points`. `Data.kind` follows the shape, so `filter_data_by_type` classifies by it.

The algebra works before sampling, as in Unreal. Intersect a landscape with a volume or a closed-spline surface, subtract a road spline, then sample: `get_surface_data → intersection(get_volume_data) → surface_sampler`. Points still work everywhere: a point set against a shape is filtered or density-attenuated by the shape's density, and a shape minus points treats the points as box volumes. Shapes are immutable value objects that copy their source geometry when they are created, so cached results never change under scene edits and queries are thread-safe.

**Remaining gaps:** see *Spatial data* above.

## Shape grammar nodes

**Implemented.** `grammar_expand` expands a grammar string (the documented UE subset: sequences, `[symbol,behavior]` tuples, repetition `*` / `:N`, weighted choice `{}`) against a module table (`GrammarModuleResourceData`: symbol, size, weight) into one fitted point per module, ready for `match_and_set` / `spawn_meshes`. `subdivide_segment` provides the geometric substrate.

## Landscape paint-layer sampling

**Partial.** `sample_terrain_layers` accepts N user-assigned mask textures with a world-to-UV mapping and writes one `layer_<name>` Float stream per layer (0..1); filter downstream with `density_filter` or `attribute_filter_range`. Since round 2, `get_surface_data` turns terrain meshes, `HeightMapShape3D` collision shapes or a heightmap image into a height-field surface.

**Gap.** Godot terrain is plugin territory (Terrain3D, HTerrain). Reading their height and splat/control maps directly needs adapters; they are planned as wave B (`FlowTerrainAdapter`, WP6).

## Subdivide Segment

**Implemented.** `subdivide_segment` slices spline or two-point spans into sized sub-segments by module lengths or a target count, with stretch / clip / pad-end fitting, and emits one oriented point per sub-segment with `length`, `segment_index`, `t_start` and `t_end`. Floor stacking is expressible with `duplicate_point` and a Y offset (≈ Duplicate Cross-Section).

## Attribute domains (`@Data` / `@Points` / `@Elements`)

**Implemented.** `Data.data_attrs` holds per-data attributes next to `tags`, surviving `duplicate()` / `filter()`; the `@data.<name>` selector reads them broadcast and writes them in `registerStream`. `add_attribute` has a domain toggle and `partition` stamps its key as a per-data attribute.

**Remaining gap:** `@Elements` has no equivalent.

---

## Engine-hardening notes (not UE features, but parity blockers)

**All four items below are resolved.**

- ~~**Runtime evaluator leaks node instances per evaluation**~~ → **Fixed**, then made moot in round 2: elements are `RefCounted` and released after every run, including inside `loop` and `subgraph` evaluations.
- ~~**Primitive graph-input args crash the runtime feed**~~ → **Fixed.** `_coerce_input_data` wraps supported primitives (float/int/bool/String/Vector3/Color) into a single-entry `FlowData.Data` before feeding the graph, so `FlowGraphNode3D.execute()` with raw scalar args no longer crashes.
- ~~**Editor and runtime evaluators differ**~~ → **Fixed.** Both share `build_execution_order` — a unified post-order topological sort with cycle detection and `on_stack` recursion guard, plus `_stabilize_consumer_input_order` / `_stabilize_variable_execution_order` for diamond and set-variable edge cases. Since round 2 the editor also executes each node through `FlowExecutor.execute_element`, the runtime's code path.
- ~~**Stream-length invariants are unchecked**~~ → **Fixed.** `registerStream` emits a `print_verbose` warning when a non-broadcast stream's length mismatches existing streams, making length corruption debuggable without breaking production graphs.
