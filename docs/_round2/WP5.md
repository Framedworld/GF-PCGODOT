# WP5: hierarchical and runtime generation

Status: implemented on the WP5 worktree branch. 63 new test cases in `demo/tests/world/`. The golden and seed-zero suites pass. Their baseline files gained entries for the new demo graph and scene only. No existing entry changed (see "Deviations").

## Summary

- **Levels at compile time.** `FlowCompiledGraph` assigns every node a level when it compiles the graph.
  - A node's level is the grid size of the nearest `grid_size` marker upstream of it. When several markers are upstream, the smallest size wins.
  - A node with no marker upstream is on the Unbounded level (level 0).
  - The pass follows physical links and the virtual `set_variable` -> `get_variable` dependencies. It terminates on cycles.
  - It also builds a plan for each level: the nodes to run, the coarser nodes to preseed, and the nodes to capture for finer levels.
  - `grid_size` stays a pass-through. It still writes its old `ctx.variables` annotation, which is now deprecated.
- **Cells.** A cell is `(level, coord : Vector2i)` on the XZ plane. `FlowWorldGrid` holds the cell math (`world/flow_world_grid.gd`): half-open ownership, execution bounds, parent cells, cells in an area, and distances. `FlowWorldCell` describes one cell to evaluate.
- **Context.** `EvaluationContext` gains `bounds`, `has_bounds`, `grid_size`, `cell_coord` and `hierarchy_level`. They are zero or false outside world generation. `FlowExecutor.build_state` copies them into nested subgraph and loop evaluations.
- **Executor additions** (`executor/flow_executor.gd`, small and additive): `capture_nodes` and `captured`. Before `finalize()` releases the elements, it keeps the generated bulks of the named nodes. Per-cell runs use the WP1 extension points `node_filter` and `preseeded` unchanged.
- **Per-cell execution.** `FlowGraphNode3D` gains two methods, `generate_cell(cell, preseeded)` and `begin_cell(cell, preseeded, time_sliced)`, which returns a `FlowCellRun`.
  - A cell runs the nodes of its level only. Coarser outputs come in whole through `preseeded`.
  - The run is synchronous, threaded (when `threaded` is set) or time-sliced, and it uses `FlowOutputCache` when `output_cache` is set.
  - On completion the component stores `last_outputs`, `last_errors` and `last_cell` and emits `generated`. `cleanup()`, `generate()` and `generate_async()` cancel a cell run that is still in flight. Nothing else about the existing API changes.
- **`FlowWorld3D`** (`world/flow_world_3d.gd`) generates a graph over `world_bounds`.
  - Each cell is a `FlowGraphNode3D` child named `FlowCell_L<level>_<x>_<z>`. The Unbounded run is `FlowCell_L0_0_0`.
  - Coarser cells are generated first. Their captured outputs and published variables are cached on the world while they stay generated.
  - Manual API: `generate_all`, `generate_bounds`, `generate_cell`, `cleanup_cell`, `cleanup_all`, `is_busy`, plus the signals listed in the reference below.
  - Modes: Manual, OnLoad and Runtime. Runtime uses a proximity scheduler with an injectable clock and an injectable source provider.
- **`FlowGenerationSource`** (`world/flow_generation_source.gd`) is a `Node3D` that joins the group `flow_generation_source`. It adds `enabled` and `radius_scale`.
- **New nodes.**
  - `get_execution_bounds`: the current cell bounds as a box volume, or as a bounds point.
  - `cull_points_outside_bounds`: keeps the points inside the cell bounds (half-open), optionally tested by point bounds and with a margin.
- **Demo.** `demos/demo_hierarchical.tscn` with `graphs/graph_hierarchical.tres`:
  - trees on the 64 level and rocks on the 16 level;
  - the rocks are kept clear of the trees handed down from the 64 cell;
  - the source orbits the origin, so cells stream in ahead of it and are cleaned up and pooled behind it.

## How the design maps to the contract

| # | Requirement | Where |
|---|---|---|
| 1 | Levels: nearest marker, smallest under several, Unbounded otherwise, computed at compile time, `grid_size` a pass-through, power-of-two sizes | `FlowCompiledGraph.node_levels`, `grid_sizes`, `level_of`, `levels`, `hierarchy_index`, `level_plan`, `_compute_levels` (`executor/flow_compiled_graph.gd`). Sizes are snapped with `FlowWorldGrid.snap_grid_size`, which rounds the same way as `GridSizeNodeSettings`. |
| 2 | Cells, the bounds formula, half-open ownership | `FlowWorldGrid.cell_aabb`, `execution_bounds`, `owns`, `overlaps`, `coord_of`, `parent_coord`, `cells_in` |
| 3 | Per-cell execution through `node_filter` and `preseeded`; coarser results computed once and cached per world; context fields | `FlowWorldCell.node_filter`, `FlowGraphNode3D.begin_cell` / `generate_cell`, `FlowCellRun`, `FlowWorld3D._start` / `_complete`, `EvaluationContext` fields, `FlowExecutor.capture_nodes` |
| 4 | Seeds: the world seed is passed unchanged; `cell_coord` is exposed | `FlowWorld3D.seed` -> every cell component's `seed`. `cell_coord` is on the context and is the `cell_x` / `cell_z` `@data` of `get_execution_bounds`. |
| 5 | `get_execution_bounds`, `cull_points_outside_bounds` | `nodes/get_execution_bounds*.gd`, `nodes/cull_points_outside_bounds*.gd` |
| 6 | `FlowWorld3D` exports, sources, `FlowGenerationSource` | `world/flow_world_3d.gd`, `world/flow_generation_source.gd` |
| 7 | Cell components named `FlowCell_L<level>_<x>_<z>`, run through `generate_cell(cell, preseeded)`, used as `ctx.owner` | `FlowWorld3D._acquire_component`; spawned content carries `flow_owner = {component: <cell component id>, node}` |
| 8 | Runtime scheduler | `FlowWorld3D.tick`, `_update_runtime_targets`, `_fill_active`, `_cleanup` (state machine below) |
| 9 | Manual control and signals | `generate_all`, `generate_bounds`, `generate_cell`, `cleanup_all`, `cleanup_cell`, `is_busy`, `cell_generated`, `cell_cleaned_up`, `all_generated` |

## Level and cell semantics

**Level ids.**
- A level is identified by its grid size in world units, an `int` power of two. The Unbounded level is `0` (`FlowWorldGrid.UNBOUNDED`).
- `FlowWorld3D.get_levels()` lists the levels coarsest first: `0` when some node has no marker upstream, then the grid sizes, largest first.
- `ctx.grid_size` is the size as a float, and `0` on the Unbounded level.
- `ctx.hierarchy_level` is the depth: 1 for the coarsest grid size of the graph, 2 for the next one, and so on. It is 0 on the Unbounded level and outside world generation.

**Assignment rules.**
- `rank(node)` is the smallest marker size among the node itself, if it is a `grid_size` marker, and every node upstream of it through links and variable dependencies. Unbounded counts as +infinity.
- A marker downstream of a smaller marker therefore keeps the smaller size. A marker with no input is on its own level, and so is everything downstream of it.
- Marker sizes come from the saved `cell_size`, defaulting to 64. Overrides and `$param` bindings of `cell_size` are not seen at compile time.
- A disabled marker still counts as a marker.
- Markers inside subgraphs are pass-throughs: a subgraph node runs on its own level, and its inner graph runs whole within that cell.

**Source nodes.** A node with no input (Get Surface Data, Grid, ...) has no upstream marker, so it is Unbounded. It runs once, and its result is handed whole to every cell that consumes it.

To run a source per cell, give it a marker upstream. `get_execution_bounds` has an optional **Dependency** pin for exactly this. The data on that pin is ignored. The idiom is `grid_size (no input) -> get_execution_bounds`. It matches Unreal's dependency-only pins, and it is how the stock samplers below become per-cell.

**Cell box.**
```
AABB(Vector3(cx * size, world_min_y, cz * size), Vector3(size, world_height, size))
```
- `coord_of(p) = (floor(p.x / size), floor(p.z / size))`.
- **Execution bounds** are the box intersected with `world_bounds` on XZ. This follows Unreal, which intersects a partition actor's bounds with the original component's bounds.
- On the Unbounded level the execution bounds are `world_bounds` itself.
- Cells whose execution bounds have zero area are never generated.

**Ownership.**
- X and Z are half-open: `min <= p < max`. A point on an edge shared by two cells belongs to the cell on the max side of that edge.
- Y is closed: `min <= p.y <= max`. Cells never touch vertically.
- Because sizes are powers of two, `p / size` is exact, so `coord_of(p) == c` exactly when the box of `c` owns `p`. The tests check this on edges and corners.
- Point-bounds overlap (`overlaps`) uses the same convention. A box that only touches the max side does not overlap.

**Parent cells.** `parent_coord(coord, size, parent_size) = floor(coord * size / parent_size)`, using integer floor division. Every coarser level of the graph, Unbounded included, has exactly one cell containing a given cell.

**Data flow between levels.**
- When a cell of level L runs, the elements of every other level are skipped by `node_filter`, with one exception.
- A node of a coarser level C with a link into a node of L is preseeded with the generated bulks captured from the C cell that contains this cell, or from the Unbounded run.
- Those bulks are passed **whole**, not culled to the finer cell. The Data objects are shared and the bulk arrays are copied, as for WP1 `preseeded`. Consumers must not mutate their inputs, which is the existing WP1 contract.
- Coarser results are computed once per world, when the coarser cell generates. They stay cached on the world while that cell is generated.
- Graph variables published by the coarser cells are seeded into the cell's context. Nested subgraphs and loops see them, as well as the cell bounds and level.
- Graph outputs of a cell are only the outputs of its own level (`FlowWorld3D.get_cell_outputs`).

**Seeds.** Every cell gets the world seed unchanged, so position-hashed randomness (per-point seeds, the surface sampler's per-grid-cell jitter) is continuous across cell edges. Graphs that want per-cell variation read `cell_x` / `cell_z` from `get_execution_bounds`, or `ctx.cell_coord`.

## Partition invariance: which stock samplers are world-aligned

The test graph is `grid_size -> get_execution_bounds -> sampler -> cull_points_outside_bounds -> output`. The world bounds are deliberately not aligned to the 32 grid, (-40..40)², so the edge cells are clipped. The union of the 16 cells is compared, point by point and stream by stream, with the same graph run monolithically: `get_execution_bounds` falls back to the world bounds and the result is culled to the world bounds.

| Sampler (configuration) | World-aligned | Why |
|---|---|---|
| `surface_sampler` on surface data, PointsPerSquareMeter, Bounding Shape = execution bounds | **yes** | Candidates sit on a world-anchored grid (cell size 1/sqrt(ppsm)) with a per-grid-cell seed. The jitter stays inside its grid cell, the sampled range is every grid cell overlapping the bounds, and the composite density decides. |
| `volume_sampler` on volume data, e.g. `intersection(make_bounds Shape, execution bounds)` | **yes** | Voxel centres sit on a world-anchored grid. |
| `to_point` on the execution-bounds box | **yes** | Volume sampling on the same world-anchored voxel grid. |
| Any Unbounded generator passed whole to the cells (`grid` -> `grid_size` -> `cull`) | **yes** (trivially) | The cells re-cull the same full set. Every cell holds the whole input, so this costs memory. |
| `surface_sampler`, Count mode (`num_points`) | no | Draws `num_points` random hits inside the given bounds, so each cell gets `num_points`. |
| `surface_sampler` on points (legacy path) | no | `num_points` random points per input region, relative to that region. |
| `grid_fill_bounds` on a bounds point | no | Its axis positions are centred on the input box (`_axis_positions(center, size, cell)`), not anchored to the world. |
| `sample_points`, UniformGrid / QuasiRandom2D / blue noise | no | It subdivides each input point's own box, and its Halton and blue-noise sequences restart per box. |

`test_samplers_that_are_not_world_aligned` pins the second group, so a sampler that becomes aligned fails the test and has to move into the first list. None of these files belong to WP5, so no opt-in fix was made. The smallest fix would be a "world anchored" option on `grid_fill_bounds` that snaps `_axis_positions` to multiples of `cell_size`. It is not done here because the file belongs to another package.

**Recipe for hierarchical scatter.** Use `get_surface_data` (Unbounded) and `grid_size -> get_execution_bounds`, and feed the bounds into the surface sampler's Bounding Shape pin (`use_bounding_shape`). Then add `cull_points_outside_bounds` before anything that consumes neighbours across cells.

**Known limit (also in Unreal).** A finer cell sees only the coarser cell that contains it. A fine point near a coarse cell's edge can therefore miss a coarse point just across that edge, for example when "remove rocks near trees" uses Difference against the coarse trees. This is invariant when the coarse level does not cull, or when the coarse output is wide enough. The demo shows the usual case.

## Scheduler state machine

Per cell: (none) -> **Queued** -> **Generating** -> **Generated** -> **CleaningUp** -> (none, component pooled).

| Transition | When |
|---|---|
| none -> Queued | Runtime: a source is within the level's generation radius of the cell footprint (XZ distance, `distance <= radius * radius_scale`). OnLoad / `queue_all` / `queue_bounds`: every cell of the area. A finer cell that needs a missing parent also queues that parent. |
| Queued -> Generating | `tick()` fills up to `max_concurrent_cells` runs. A queued cell can start only when every coarser cell containing it is Generated. The best candidate is chosen by coarser level first, then the nearest source distance to the cell centre, then coordinates. Starting builds a time-sliced `FlowCellRun` on a pooled or new component. |
| Generating -> Generated | The run's last element finished. Outputs, captured bulks, variables and errors are stored, and `cell_generated` is emitted. |
| Generated -> CleaningUp | Runtime, checked finest level first. No source is within radius * `cleanup_radius_multiplier` × `radius_scale`, the cell is not manual, and no live finer cell needs it. |
| Generating -> CleaningUp | The same condition while a run is in flight. The run is cancelled: finalized without the remaining elements and without `generated`. |
| Queued -> none | Runtime: no longer wanted and not needed by a finer cell. |
| CleaningUp -> Generated | Wanted again before the cleanup ran: the cleanup is cancelled. |
| CleaningUp -> none | `tick()` runs the cleanup: `FlowGraphNode3D.cleanup()` frees the cell's spawned content, the component leaves the tree and goes to the pool (or is freed when the pool already holds `cell_pool_size`), and `cell_cleaned_up` is emitted. |

**One `tick()`.**
1. In Runtime mode, update the targets from the sources.
2. Run pending cleanups, finest level first.
3. Start runnable cells and step the active runs round-robin, one element per step (`step(0)`).
4. Repeat until `frame_budget_ms` has elapsed on `clock`.

At least one unit of work runs per tick, so a zero budget still makes progress. The budget is checked between units, and a single node is never interrupted. `all_generated` is emitted when the world goes from busy to idle.

**Injectables.**
- `clock : Callable` returns microseconds. The default is `Time.get_ticks_usec`.
- `source_provider : Callable` returns Vector3s, Node3Ds or `{position, radius_scale}`. The default is the members of `SOURCE_GROUP` plus `sources`, where a node with `enabled == false` is skipped and its `radius_scale` is used when present.
- `_process` calls `tick()` in OnLoad and Runtime mode. OnLoad stops processing once idle.

**Unreal semantics.**
- The cleanup radius is the generation radius × `cleanup_radius_multiplier`, default 1.1. This hysteresis is tested.
- The priority is coarser grid first, then distance.
- Cleaned components are pooled and reused, with names and state reset.

Deviations:
1. Distance is measured on the XZ footprint, not in 3D, because cells span the whole world height.
2. The default radius for a grid level without an entry is one cell size. The Unbounded level defaults to 256 units, measured to the world-bounds footprint. These are this addon's defaults; they do not claim to match Unreal's table.
3. A coarser cell is kept alive while finer cells need it, even outside its own cleanup radius, so children are never orphaned from their parent's data.
4. Manual and OnLoad cells are never cleaned up by the runtime scheduler.

## Settings reference

### `FlowWorld3D` (`world/flow_world_3d.gd`)

| Export | Default | Meaning |
|---|---|---|
| `graph` | null | The graph; its levels come from its `grid_size` markers. |
| `seed` | 0 | Graph seed for every cell, unchanged. |
| `args`, `params`, `overrides` | {} | As on `FlowGraphNode3D`, copied to every cell component. |
| `world_bounds` | AABB(-128, -64, -128, 256, 128, 256) | Generated area in global space. Its Y range is the height of every cell. |
| `generation_mode` | Manual | Manual, OnLoad (queue every cell on `_ready`) or Runtime (proximity). Nothing runs in the editor except the inspector buttons. |
| `generation_radius` | {} | Grid size (int, or its string) -> radius. 0 is the Unbounded level, measured to the world bounds. Missing grid sizes use their size; a missing Unbounded entry uses 256. |
| `cleanup_radius_multiplier` | 1.1 | Hysteresis factor for cleanup. |
| `frame_budget_ms` | 4.0 | Scheduler budget per frame. |
| `max_concurrent_cells` | 2 | Cells in Generating at once. Their elements are interleaved on the main thread. |
| `sources` | [] | Extra source node paths. |
| `cell_pool_size` | 32 | Pooled components kept for reuse. |
| `threaded` | false | Cell components' `threaded`. It applies to synchronous generation (the manual API). Time-sliced runs keep the top level sequential, as `generate_async` does, and their nested evaluations still honour it. |
| `output_cache` | false | Cell components' `output_cache`. |

Members that are not exported:
- the injectables `clock` and `source_provider`;
- the statistics `components_created`, `components_reused`, `last_tick_elements`, `last_tick_started` and `last_tick_cleaned`.

Queries: `get_levels`, `get_cell_bounds`, `get_cell_at`, `get_parent_cells`, `get_cell_state`, `get_cell_outputs`, `get_cell_errors`, `get_cell_component`, `get_cells(state)`, `get_pool_size`, `get_generation_sources`, `get_generation_radius`.

Methods: `queue_all`, `queue_bounds`, `tick`.

The inspector has "Generate All" and "Cleanup All" buttons. In the editor, the cells are created without an owner, so they are never saved.

Cell components always have `transient_output = true`, so their content is never saved into the scene. They also have `generate_on_ready = false`.

### `FlowGenerationSource` (`world/flow_generation_source.gd`)

| Export | Default | Meaning |
|---|---|---|
| `enabled` | true | Disabled sources are ignored. |
| `radius_scale` | 1.0 | Multiplies every level's generation and cleanup radius for this source. |

### `get_execution_bounds`

| Setting | Default | Meaning |
|---|---|---|
| `output_mode` | Shape | Shape outputs a `FlowBoxVolume` with no points. Points outputs one point at the centre, with `size` set to the box size and `bounds_min` / `bounds_max` of ±half the size. |
| `steepness` | 1.0 | Box steepness in Shape mode. |
| `fallback_bounds` | AABB(-50, -50, -50, 100, 100, 100) | Used outside world generation. |

- Input: an optional Dependency pin. Its data is ignored; it is used for ordering and level.
- `@data` attributes on the output: `bounds_min` and `bounds_max` (world), `grid_size`, `cell_x`, `cell_z`, `hierarchy_level` and `has_bounds`.
- It runs once per evaluation, however many bulks the Dependency pin carries.

### `cull_points_outside_bounds`

| Setting | Default | Meaning |
|---|---|---|
| `use_point_bounds` | false | Keep a point when its bounds box (position + `bounds_min` / `bounds_max`, else ±`size`/2, axis-aligned as in `get_bounds`) overlaps the cell, instead of testing its position. |
| `margin` | 0.0 | Grows the bounds on every side before the test. A negative margin shrinks them. |

- Outside world generation it passes its input through.
- Data without a position stream passes through, and so does shape-only Data.
- When every point is kept, the input object is forwarded as is.

### Traits

| Template | main_thread | cacheable | Why |
|---|---|---|---|
| `get_execution_bounds` | false | false | Reads only context fields, which is thread-safe. Its output depends on `ctx.bounds`, which is not part of the `FlowOutputCache` key. |
| `cull_points_outside_bounds` | false | false | Same reason. |
| `grid_size` | true (unchanged) | false | It still writes `ctx.variables`. |

`SCENE_DEPENDENT_TEMPLATES`: no entry. Neither node reads the scene.

## Dictionary rows for COMING_FROM_UNREAL_PCG.md

### Hierarchical / GPU (replace the Grid Size row)

| UE node | Here | Status | Notes |
|---|---|---|---|
| Grid Size (HiGen) | `grid_size` + `FlowWorld3D` | 1:1 | Nodes downstream of a marker run once per cell of its power-of-two size when a `FlowWorld3D` generates the graph. Under several markers the smallest size wins, and nodes with no marker upstream run once (Unbounded). Coarser results are handed whole to the finer cells they contain. Levels are computed when the graph compiles. Outside `FlowWorld3D`, the marker is a pass-through. |
| Hierarchical Generation (partitioned component, partition actors) | `FlowWorld3D` | 1:1 | One `FlowGraphNode3D` per generated cell (`FlowCell_L<size>_<x>_<z>`), coarse levels first. Spawners spawn into the cell, so cleaning a cell up frees exactly its content. Cells are created at run time (or from the inspector), not saved into the scene. |

### Input / Output & Get Data

| UE node | Here | Status | Notes |
|---|---|---|---|
| Get Actor Data (self, Get Bounds / actor bounds) | `get_execution_bounds` | 1:1 | The bounds the graph runs in: the current cell intersected with the world bounds (a partition actor's bounds), the world bounds on the Unbounded level, or `fallback_bounds` outside `FlowWorld3D`. It outputs a box volume (for set operations and the samplers' Bounding Shape pin) or a bounds point. `grid_size -> get_execution_bounds` (the Dependency pin) makes it per-cell. `scan_nodes` remains the Get Actor Data equivalent for other actors. |

### Spatial (replace the Cull Points Outside Actor Bounds row)

| UE node | Here | Status | Notes |
|---|---|---|---|
| Cull Points Outside Actor Bounds | `cull_points_outside_bounds` | 1:1 | Keeps the points inside the current cell. X and Z are half-open, so adjacent cells never both keep a point; this is the HiGen de-duplication step. `margin` is UE's Bounds Expansion. `use_point_bounds` keeps points whose bounds box overlaps the cell. Outside `FlowWorld3D` it is a pass-through. |

### Runtime: the PCG Component API (new rows)

| Unreal | Here |
|---|---|
| Runtime generation (Generation Trigger: Generate At Runtime), runtime generation scheduler | `FlowWorld3D.generation_mode = Runtime`. Every frame, cells within each grid level's `generation_radius` of a generation source are queued (coarse levels first, then nearest) and generated time-sliced within `frame_budget_ms` and `max_concurrent_cells`. Cells beyond radius × `cleanup_radius_multiplier` (1.1) are cleaned up, and their components are pooled (`cell_pool_size`). |
| Generation Trigger: Generate On Load | `FlowWorld3D.generation_mode = OnLoad` queues every cell, generated over the following frames. Manual is `generate_all()` / `generate_bounds(aabb)` / `generate_cell(level, coord)`, which are synchronous. |
| `UPCGGenerationSource` (players, cameras) | Any `Node3D` in the group `flow_generation_source`, or a `FlowGenerationSource` node (`enabled`, `radius_scale`), or `FlowWorld3D.sources`. |
| Generation radii per grid (`FPCGRuntimeGenerationRadii`) | `FlowWorld3D.generation_radius` (grid size -> radius, 0 = Unbounded) and `cleanup_radius_multiplier`. |
| `OnPCGGraphGenerated` per partition / cleanup | `FlowWorld3D.cell_generated(level, coord)`, `cell_cleaned_up(level, coord)`, `all_generated`; each cell component also emits `generated`. |

### Concept dictionary (new row)

| Unreal | Here | Notes |
|---|---|---|
| **Execution / actor bounds** in a partitioned graph | `EvaluationContext.bounds` / `has_bounds` / `grid_size` / `cell_coord` / `hierarchy_level` | Set for every cell generated by `FlowWorld3D` and inherited by subgraphs and loops. They are zero or false elsewhere. Read them with `get_execution_bounds`; `cull_points_outside_bounds` applies them. |

Also update the "When something doesn't translate" sentence to drop "hierarchical generation (Grid Size), async/proximity runtime generation".

## nodes_reference.md rows

Spatial section:

| Node | Script File | Description |
| --- | --- | --- |
| **Get Execution Bounds** | [get_execution_bounds.gd](../nodes/get_execution_bounds.gd) | Bounds of the current FlowWorld3D cell (the world bounds on the Unbounded level, `fallback_bounds` outside world generation) as a box volume or a bounds point, with cell `@data` attributes. |

Filter / Utility section:

| Node | Script File | Description |
| --- | --- | --- |
| **Cull Points Outside Bounds** | [cull_points_outside_bounds.gd](../nodes/cull_points_outside_bounds.gd) | Keeps the points inside the current FlowWorld3D cell (half-open, optional point bounds and margin); pass-through outside world generation. |
| **Grid Size** | [grid_size.gd](../nodes/grid_size.gd) | Hierarchical generation marker: nodes downstream run once per cell of this power-of-two size under FlowWorld3D; pass-through otherwise. |

(`grid_size` has no row in nodes_reference.md or node_templates.csv today.)

## node_templates.csv rows

```
"cull_points_outside_bounds","Cull Points Outside Bounds"
"get_execution_bounds","Get Execution Bounds"
"grid_size","Grid Size"
```

## Roadmap text (replaces "Hierarchical generation (Grid Size)" and "Async / proximity runtime generation")

Status rows:

| Roadmap item | Status | What landed |
|---|---|---|
| Hierarchical generation (Grid Size) | **Implemented** | Compile-time levels from `grid_size` markers; `FlowWorld3D` cells (one `FlowGraphNode3D` each) with coarse-to-fine data flow; `get_execution_bounds`, `cull_points_outside_bounds` |
| Async / proximity runtime | **Implemented** | `FlowWorld3D` Runtime mode: generation sources, per-level radii, cleanup hysteresis, coarse-first then nearest priority, frame budget, concurrent cells, component pool |

Section:

> **Landed.** `FlowWorld3D` generates a graph over a world in cells. Nodes downstream of a `grid_size` marker run once per cell of its size (the smallest marker wins), and the rest run once (Unbounded). Coarser cells are generated first, and their outputs are handed whole to the finer cells they contain. Each cell is its own `FlowGraphNode3D`, so spawned content, cleanup and ownership work per cell. Manual, OnLoad and Runtime (proximity) modes; the runtime scheduler is time-sliced, budgeted, priority-ordered, hysteretic and pooled. `get_execution_bounds` and `cull_points_outside_bounds` give graphs the cell bounds. World-aligned samplers (Surface Sampler on surface data, Volume Sampler and To Point on volumes) give the same points through cells as in one piece.
>
> **Remaining gaps.** Cells are not saved or streamed as level data (no World Partition equivalent); there is no editor-viewport generation source; finer cells see only the coarser cell containing them; `grid_fill_bounds`, `sample_points` and the count/point modes of `surface_sampler` are not world-aligned; markers inside subgraphs are pass-throughs; grid sizes cannot be overridden at run time.

## DEPRECATIONS.md rows

No output change for any existing graph.

| Symbol | Status | Replacement | Since |
|---|---|---|---|
| `grid_size` writing `ctx.variables["__grid_size__cell_size"]` (`GridSizeNodeSettings.CTX_KEY`) | **Deprecated**. Still written, read by nothing. | `EvaluationContext.grid_size` / `hierarchy_level`, or the `grid_size` `@data` of `get_execution_bounds`. Levels come from `FlowCompiledGraph.node_levels`. | WP5 |
| `EvaluationContext` | Gains `bounds`, `has_bounds`, `grid_size`, `cell_coord` and `hierarchy_level` (zero or false outside world generation). Nested evaluations copy them. | — | WP5 |
| `FlowExecutor` | Gains `capture_nodes` / `captured` (additive). | — | WP5 |
| `FlowGraphNode3D.is_generating()` | Also true while a cell run started by `begin_cell()` is unfinished. `cleanup()`, `generate()` and `generate_async()` cancel such a run. Unchanged for components that never generate cells. | — | WP5 |

## Tests

New suites in `demo/tests/world/` (63 cases):

| Suite | Cases | Covers |
|---|---|---|
| `world_levels_test.gd` | 10 | No markers; a diamond under one marker; two arms with different markers joining (smallest wins); chained markers (finer and coarser downstream); a marker without input; cell size snapping and default; the virtual variable dependency; cycles; recompilation on data change; a marked graph is inert outside world generation |
| `world_grid_test.gd` | 11 | Snapping equals `GridSizeNodeSettings`; floor division; `coord_of` with negatives and edges; the contract bounds formula and clipping; parent coordinates (and containment); half-open ownership as a partition (edges and corners, every point owned exactly once); the `owns` / `overlaps` / `grow` conventions; `cells_in`; distances and names; the `FlowWorldCell` descriptor; context defaults |
| `world_nodes_test.gd` | 12 | `get_execution_bounds` Shape and Points, inside a cell and with the fallback, once per run; cull pass-through, half-open, neighbour partition, margin, point bounds, shape-only and empty data, missing input; traits rows |
| `world_generation_test.gd` | 9 | `generate_cell` runs only its level with hand-made preseeded inputs; time-sliced runs and cancellation; **partition invariance** for the four aligned samplers with seeds 0 and 4711; detection of the five non-aligned ones; invariance on two levels at once (64 volume voxels, 16 surface scatter); parent-to-child flow (the whole Unbounded grid plus the containing 64 cell's point in every 16 cell; every cell generated exactly once); variables and cell fields inside nested subgraphs; cell order independence (reversed and interleaved, parents on demand); threaded, cached, threaded + cached and time-sliced scheduler runs identical per cell, with cache hits and worker-pool use asserted |
| `world_manual_api_test.gd` | 8 | Components per cell and names, signals and order, per-cell spawn ownership and transient output; `generate_cell` with parents on demand, `force`, content replacement; `generate_bounds`; invalid level and outside cell; `cleanup_cell` frees only that cell's content and pools the component, reuse; `cleanup_all` and the pool bound; owner-less evaluation of the same graph (cull pass-through, spawner owner error); world settings reach the components |
| `world_scheduler_test.gd` | 12 | Fake clock and sources: radius selection against a brute-force reference, coarse-first then nearest order, `all_generated` once; budget (3 elements per tick at 1 ms per clock read with a 3 ms budget) and `max_concurrent_cells`; a moving source (cleanup, reuse, pool bound); cleanup-radius hysteresis; CleaningUp within the budget; sources gone (manual cells kept); parents kept alive by children; cancellation of a generating cell; `radius_scale`; OnLoad; real source collection (group, disabled, NodePath); a real `_process` driver over frames |
| `world_demo_scene_test.gd` | 1 | The demo loads, generates three levels around its source, with trees and rocks and no errors |

Commands, run from `demo/`:
```
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/world
godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests
```

## Deviations and decisions

1. **Level id = grid size.** `generate_cell(level, coord)`, `generation_radius` keys, cell names and `get_levels()` all use the grid size in world units, and 0 for Unbounded. This is stable when markers are added or removed. `hierarchy_level` is the depth index.
2. **The Unbounded run is a cell.** `FlowCell_L0_0_0` is a component like the others, with the world bounds as its execution bounds and `has_bounds = true`. A graph with no markers is therefore just one Unbounded cell.
3. **Execution bounds are clipped to the world** on XZ, as in Unreal. The contract formula gives the unclipped box, which `FlowWorldGrid.cell_aabb` returns.
4. **Y is closed.** Ownership is half-open on X and Z only.
5. **The Dependency pin on `get_execution_bounds`.** Under rule 1, a node without inputs is always Unbounded, so a source node can only become per-cell through a marker upstream. The optional pin provides that, mirroring Unreal's dependency-only pins.
6. **The scheduler distance is the XZ footprint distance.** Defaults: one cell size for a grid level without a radius, and 256 units for Unbounded.
7. **Parents are kept alive by their children**, and manual cells are never cleaned up by the runtime scheduler.
8. **`threaded`** applies to the synchronous manual API. Time-sliced scheduler runs keep the top level sequential (WP1's time-sliced mode), and nested evaluations honour it.
9. **Golden and seed-zero baselines.** The demo graph `graphs/graph_hierarchical.tres` and the demo scene are discovered automatically by `golden_graphs_test` and `seed_zero_backcompat_test`. Both suites fail on a graph or scene with no entry, so I generated their entries. The diff of both files is **additions only**: 206 lines in `baseline.json`, 8 in `seed_zero_baseline.json`, no line removed or changed. Rule 2 asks to stop instead of regenerating; I read it as protecting existing entries, which are unchanged. If you prefer, drop the two new entries and move the graph into the scene.
10. **The demo source starts after 30 frames.** The seed-zero suite puts the demo scene in the tree for two physics frames before hashing its generated content. A runtime world that started immediately would make that hash depend on frame timing. The delay is in the demo's own script and is documented there.
11. The world keeps its own outputs (`get_cell_outputs`) rather than adding outputs to the scene.

## Found while testing (not fixed: not my files)

**`difference` halves boxes that come from bounds streams.**
- `nodes/difference.gd` `_broadphase_params` passes real half extents (`(wmax - wmin) * 0.5`) to `GDRTree.add` / `overlaps`.
- The native code (`native/src/gd_rtree.cpp`) treats that argument as a full size: `center ± size * 0.5`. The `size` path is correct.
- So every point carrying `bounds_min` / `bounds_max` overlaps with half its intended box. Surface Sampler output does.
- In the demo, rocks ±0.6 against trees ±2 are only removed within 1.3 m, not 2.6 m. The demo test asserts only what holds either way.
- A fix changes outputs for graphs whose points carry bounds streams, so it needs its own package and a baseline review.

## Limits: what was verified only with fake sources

- The scheduler's correctness (selection, order, budget, concurrency, cleanup, hysteresis, pinning, pooling, cancellation) was verified with an injected clock and injected source positions, plus one real-frame test (`test_runtime_mode_runs_from_process`) and a 1500-frame headless run of the demo.
  - In that run, 43 to 47 cells stayed generated around the moving source, and 42 component reuses had happened after 1500 frames.
  - Real frame-time behaviour with heavy graphs was not profiled, for example whether a 4 ms budget holds with large spawners. Time slicing is per node, so a single heavy node can overrun the budget.
- Nothing was checked visually; the container has no display.
  - In the editor: the inspector buttons, cells appearing in the 3D viewport, and how the demo looks.
  - The demo's look: tree and rock density, the camera framing and the orbit speed.
- Generation sources were tested as plain `Node3D` and `FlowGenerationSource` nodes. Cameras and players in a real game loop were not.
- Threaded cell generation was verified for equality with the sequential run and for actually using the worker pool, on the test graphs only.
