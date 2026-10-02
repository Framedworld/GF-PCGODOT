# Coming From Unreal PCG

A translation guide for Unreal Engine PCG users. The goal of this addon is that you can follow a UE PCG tutorial inside Godot with minimal mental translation: the hotkeys match, the search popup understands UE node names, and the core per-point invariants (density, seed) work the way UE taught you.

This guide covers:

1. [5-minute orientation](#5-minute-orientation) — where everything lives
2. [Hotkeys](#hotkeys) — UE keys vs. here
3. [Concept dictionary](#concept-dictionary) — `$Density`, `$Seed`, selectors, attribute sets, tags
4. [The node dictionary](#the-node-dictionary) — every UE PCG node and its equivalent here
5. [Architecture: how Unreal's PCG model maps here](#architecture-how-unreals-pcg-model-maps-here) — elements and the executor, caching and threading, the conformance harness, hierarchical and runtime generation, spatial data, terrain adapters, loops, spawners, attribute types
6. [Overrides and bindings](#overrides-and-bindings) — override pins, graph parameter overrides, bound settings
7. [Translated tutorials](#translated-tutorials) — three classic UE recipes, node by node
8. [Runtime: the PCG Component API](#runtime-the-pcg-component-api) — Generate/Cleanup/Seed from script

For things that genuinely do not translate yet, see [PARITY_ROADMAP.md](PARITY_ROADMAP.md) — we would rather tell you up front than have you discover it at step 7 of a tutorial.

---

## 5-Minute Orientation

| In Unreal PCG | Here |
|---|---|
| **PCG Component** (on an actor) | **`FlowGraphNode3D`** — a Node3D you add to your scene. It holds a reference to a graph and evaluates it, with the component API (`generate()`, `cleanup()`, `regenerate()`, `seed`, `generated` signal) — see [Runtime: the PCG Component API](#runtime-the-pcg-component-api). |
| **Partitioned PCG Component** (hierarchical generation, runtime generation) | **`FlowWorld3D`** — a Node3D that generates one graph over `world_bounds` in grid cells, one `FlowGraphNode3D` child per generated cell, on demand, on load or around generation sources at runtime. See [Hierarchical and runtime generation](#hierarchical-and-runtime-generation). |
| **PCG Volume** | The `FlowGraphNode3D`'s place in the scene. There is no special volume actor — source nodes (`get_surface_data`, `get_spline_data`, `get_volume_data`, `scan_meshes`, `scan_splines`, `scan_nodes`) read the surrounding scene directly, and generator nodes (`grid`, `grid_fill_bounds`, `make_bounds`) define their own regions. Any `CollisionShape3D`, `Area3D` or CSG node can serve as a volume through `get_volume_data`. |
| **PCG Graph asset** (`.uasset`) | **`FlowGraphResource`** saved as a `.tres` file (or embedded directly in the scene). Subgraphs are also `.tres` graphs. |
| **Graph editor tab** | The **Data Flow** bottom panel. Select a `FlowGraphNode3D` and the panel appears at the bottom of the Godot editor, with the graph canvas, a sidebar inspector on the right, and the data table below. |
| **Details panel** | The **sidebar inspector** on the right of the Data Flow panel. Select a node and its settings appear there (not in Godot's main Inspector dock). |
| **Generate / Force Regenerate button** | **Automatic**. Editing any setting or wire dirties the affected nodes and re-evaluates them. Press **R** to force re-evaluation of selected nodes. At runtime, the graph runs once on `_ready()` (`generate_on_ready`, ≈ GenerationTrigger "Generate On Load") and `regenerate()` re-triggers it. |
| **Attributes table (Inspect)** | The **Data Inspector** — press **A** on a node. One row per point, one column per attribute (vectors, colours, quaternions and transforms split into component columns), with filtering on the displayed text and click-to-sort columns; clicking a row highlights that point in the 3D viewport. Spatial data with no points (splines, surfaces, volumes, composites) shows a summary row per shape and per composite operand: class, kind, bounds, details. |
| **Debug cube rendering** | Press **D** on a node — points draw as instanced cubes in the viewport, tinted by density (or another attribute) on a grayscale ramp. Spatial data draws as lines: spline curves, box and sphere wireframes, polygon outlines, draped grids on heightfield and mesh surfaces, composites as their parts with an operation marker; points with `bounds_min`/`bounds_max` also get a wire box per point (in the default `EXTENDS` debug mode). |
| **Level actors** | Scene nodes. `MeshInstance3D` ≈ Static Mesh Component, `Path3D` ≈ Spline Component, `PackedScene` ≈ Blueprint/actor template. |
| **ISM/HISM instances** | `MultiMeshInstance3D` (what `spawn_meshes` emits — one per unique mesh, or with `mesh_entries` one per mesh and render settings group). |

**First session:** open the `demo/` project in Godot 4.6+, open any `demos/demo_*.tscn` scene, click the `FlowGraphNode3D`, and the Data Flow panel opens with the graph. Right-click the canvas and type a UE node name — the search popup knows the UE vocabulary ("Static Mesh Spawner", "Surface Sampler", "Transform Points", ...) via aliases.

---

## Hotkeys

The debug trio you already know — **D / A / E** — works identically. The rest:

| Action | Unreal PCG | Here |
|---|---|---|
| Toggle debug rendering on node | `D` | `D` (hovered node first, else selection) |
| Clear debug on **all** nodes | — | `Alt+D` |
| Inspect node output (attribute table) | `A` | `A` |
| Enable / disable (bypass) node | `E` | `E` (disabled = dimmed, passes input 0 → output 0) |
| Open node search | Right-click canvas | Right-click canvas (also `Shift+A`) |
| Context-sensitive node search | Drag wire into empty space | Same — popup is filtered to compatible nodes and auto-connects |
| Break a wire | `Alt+Click` | `Alt+Click` or `Ctrl+Click` on the wire |
| Insert reroute on a wire | Double-click wire | Double-click wire (inserts a `Reroute` dot node) |
| Comment box around selection | `C` | `C` |
| Zoom to fit | `F` / `Home` | `F` or `Home` |
| Re-generate | Generate button | Automatic on edit; `R` re-evaluates selected nodes |
| Trace node execution to console | — | `T` |
| Delete selection | `Delete` | `Delete` or `X` |
| Copy / Cut / Paste / Duplicate | `Ctrl+C/X/V/D` | Same (selection serializes as JSON on the OS clipboard — pasteable across editor instances) |
| Undo / Redo | `Ctrl+Z` / `Ctrl+Y` | `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` |
| Collapse selection into subgraph | Right-click → Collapse | Right-click → **Collapse Selected to Subgraph** |

---

## Concept Dictionary

The data model is a **column store**: each pin carries `Data` objects, and a `Data` is a set of named **streams** (typed arrays, one element per point). UE's "point properties vs. metadata attributes" split does not exist — everything is a stream, addressed by name.

| Unreal | Here | Notes |
|---|---|---|
| `$Density` | `density` stream | Float, **0..1**, soft existence probability — same semantics as UE. Samplers initialize it to 1.0 on their outputs; density-consuming nodes treat a *missing* density stream as constant 1.0; nodes that write it clamp to 0..1. |
| `$Seed` | `seed` stream | Int, per-point, derived from the point's position when a sampler creates it. Stochastic nodes (`transform_points`, `match_and_set`, `attribute_noise`, `select_points`, ...) prefer the point seed (combined with the node's seed) when the stream is present, so regenerating with the same seeds is fully deterministic and points keep their randomness when neighbors change. `mutate_seed` re-rolls it, exactly like UE. |
| `$Position` | `position` (alias `$Position`) | Vector3 stream. `$Position` works as a selector anywhere a stream name is asked (see [selector aliases](#selector-aliases)). |
| `$Position.X` | `position.x` / `$Position.X` | Component selectors work on any Vector, Vector2, Vector4, Quaternion or Color stream: `.x/.y/.z/.w` and `.r/.g/.b/.a`, case-insensitive. No swizzles (`$Position.ZYX` has no equivalent). |
| `$Rotation` | `rotation` (alias `$Rotation`) | Vector3 **Euler degrees** by default. Yaw is the **Y** component (Godot is Y-up). Convenience aliases: `Yaw` → `rotation.y`, `Pitch` → `rotation.x`, `Roll` → `rotation.z`. An optional Quaternion stream `rotation_quat` wins over `rotation` when present (`rotator_op` writes either). |
| `$Scale` | `size` (alias `$Scale`) | Vector3. When a point has no `bounds_min`/`bounds_max` streams, `size` is both its scale and its extent (bounds ±size/2), which is how older graphs work. With the bounds streams present, `size` is a pure scale, as in UE. |
| `$BoundsMin` / `$BoundsMax` | `bounds_min` / `bounds_max` (aliases `$BoundsMin` / `$BoundsMax`) | Optional per-point Vector3 streams in the point's local space. Consumers (`difference`, `self_pruning`, `sample_points` / `volume_sampler`, `get_bounds`, the round-2 point nodes) fall back to ±`size`/2 when they are absent; the debug cubes still draw `size`. `bounds_modifier` writes them (PerPointBounds mode, the default); `apply_scale_to_bounds`, `reset_point_center`, `split_points` and `bounds_from_mesh` work on them. |
| `$Steepness` | `steepness` (alias `$Steepness`) | Optional Float stream, 1.0 (hard edge) when absent. Shapes the density falloff of point volumes in `difference` / `self_pruning` and of spatial shapes. |
| `$Color` | `color` (alias `$Color`) | A Color stream conventionally named `color`; `spawn_meshes` reads it for per-instance vertex colors. |
| `@Last` | `@last` | "The last stream written by the upstream node" — same idea, same place you'd use it (filter inputs default to it). |
| `@Source`, `@LastCreated` | `@Source` on the outputs of the attribute-op nodes; `@LastCreated` not supported | `@Source` (the default output of `attribute_cast`, `copy_attribute`, `attribute_select`, ...) writes back to the node's input attribute. Older nodes still need an explicit output name. |
| **Attribute types** (bool, int32, int64, float, double, vector2/3/4, quat, rotator, transform, string, soft object path) | Bool, Int, Int64, Float, Double, Vector2, Vector, Vector4, Quaternion, Transform, String, Color, Resource, NodeMesh/NodePath | Rotators are Euler-degree Vector streams. `attribute_cast` converts between types with explicit loss rules. See [Attribute types](#attribute-types). Graph parameters (the `FlowGraphNode3D` inputs) can be any of Bool, Int, Int64, Float, Double, Vector2, Vector, Vector4, Quaternion, Color, Transform, String and Resource; raw Godot values of those types are accepted in `args` and `generate(inputs)`. |
| **Point bounds** (Scale vs BoundsMin/BoundsMax, Steepness) | `size` + optional `bounds_min` / `bounds_max` / `steepness` | `Data.getEffectiveBounds()` and `getEffectiveSteepness()` resolve them with the fallbacks above. A point tested against a spatial shape in Difference / Intersection / Union is its bounds box by default (`overlap_mode = BoundsBox`), as in Unreal, but the box is axis-aligned: point rotation is ignored (see [Spatial data](#spatial-data)). |
| `@Data` / `@Points` / `@Elements` domains (5.6+) | `@data.<name>` (per-data); per-point is default | Per-data attributes now exist: write one with `add_attribute` in PerData mode (or the `@data.<name>` selector), read it back broadcast via `@data.<name>`. `partition` stamps its key as a per-data attribute. `@Points` is the default per-point domain; `@Elements` has no equivalent yet. |
| **Attribute Set** | a `Data` with no point streams | A single-row `Data` is the equivalent of UE's single-entry attribute set. Convert with `point_to_attribute_set` / `attribute_set_to_point`. The `assets` node is the idiomatic way to author a weighted table for `match_and_set`. |
| **Tags** | `Data.tags` | Per-data string tags, exactly like UE: `add_tags` / `delete_tags` / `replace_tags` to mutate, `filter_data_by_tag` to route. |
| **Spatial data types** (Surface, Volume, Spline, Primitive, composite algebra) | `Data.shape` (a `FlowSpatial`) | Get Spline / Surface / Volume Data produce shapes (no points). Difference, Intersection and Union combine them into composites without sampling. Surface Sampler, Volume Sampler, Spline Sampler and To Point make them concrete, and Projection projects onto them. Pins carry points and shapes alike; `filter_data_by_type` tells them apart. Points against a shape use the point's bounds box by default (`overlap_mode = BoundsBox`). Point data still works everywhere, and the older `node`-stream sources (`scan_splines`, `scan_meshes`) keep working. See [Spatial data](#spatial-data). |
| **Landscape data and layer weights** | terrain surface data (`get_surface_data`, `source = Terrain`) through a `FlowTerrainAdapter` | Height, normals and paint-layer weights of a `HeightMapShape3D`, a heightmap image with splat images, a terrain `MeshInstance3D`, or a Terrain3D / HTerrain node (duck typed; the suite uses fakes of their APIs, and a manual run against Terrain3D v1.0.2 and HTerrain 1.8.1 on Windows passed). Surface Sampler writes one `layer_<name>` weight per paint layer onto the points it samples. See [Terrain adapters](#terrain-adapters). |
| **Execution / actor bounds** in a partitioned graph | `EvaluationContext.bounds` / `has_bounds` / `grid_size` / `cell_coord` / `hierarchy_level` | Set for every cell `FlowWorld3D` generates and inherited by subgraphs and loops; zero or false elsewhere. Read them with `get_execution_bounds`; `cull_points_outside_bounds` applies them. |
| **Execution model** (`UPCGSettings` / `IPCGElement` / graph compiler / graph executor) | `NodeSettings` / `FlowNodeBase` element / `FlowCompiledGraph` / `FlowExecutor` | Node scripts are stateless-per-run `RefCounted` elements; the editor shows them through `FlowNodeWidget`. The graph is parsed once and cached. See [Execution model](#execution-model). |
| **Caching** (`FPCGGraphCache`) and **multithreaded execution** | `FlowGraphNode3D.output_cache`, `FlowGraphNode3D.threaded` | Both opt-in and off by default; output is identical to a plain run. Nodes that touch the scene, physics, rendering or graph variables always run on the main thread and are never cached. A conformance harness checks every stock template for input mutation, determinism, thread and cache equivalence. See [Caching and threading](#caching-and-threading). |
| **Multi-data on a pin** | "bulks" | A pin can carry several `Data` objects; the Data Inspector has a selector to page through them, and `loop` iterates them in `Entries` mode (its other modes run once per entry). |
| **Loop over a collection of data** | `loop` with `iteration_mode = Entries` | One iteration per data entry (bulk) on the Stream pin. `output_mode = Collection` emits one entry per iteration, so a downstream node runs once per iteration. See [Loops and dynamic subgraphs](#loops-and-dynamic-subgraphs). |
| **Loop index / loop data attributes** | runtime params `iteration_index`, `iteration_count`, `iteration_key` | Plus the iteration data's per-data attributes in Entries and Partitions mode. Read them with `$param` bindings, `get_loop_index` (`source = LoopIteration`) or `get_loop_key`. |
| — (bonus) | `index`, `front` / `up` / `right` | Virtual streams: per-point index, and direction vectors derived from `rotation`. |

> **Gotcha:** a `.` inside an attribute name is always interpreted as component access (`foo.x` reads component X of stream `foo`). Don't put dots in attribute names.

---

## The Node Dictionary

Status legend — **1:1**: drop-in equivalent, settings map directly. **partial**: covers the common tutorial use, with caveats noted. **roadmap**: no equivalent yet, see [PARITY_ROADMAP.md](PARITY_ROADMAP.md).

Search for any name in the **UE node** column inside the add-node popup — the UE names are registered as search aliases.

### Input / Output & Get Data

| UE node | Here | Status | Notes |
|---|---|---|---|
| Input | `input` | 1:1 | Exposes graph parameters as output ports. |
| Output | `output` | 1:1 | Graph/subgraph output terminal. |
| Get Actor Data | `scan_nodes` (alias `points_from_scene`) | 1:1 | One point per matching scene node; filter by group (≈ tag) or class; can import node properties/metadata as attributes. |
| Get Actor Data (self, Get Bounds mode; a partition actor's bounds) | `get_execution_bounds` | partial | The bounds the graph runs in: the current `FlowWorld3D` cell intersected with the world bounds (a partition actor's bounds), the world bounds on the Unbounded level, or the `fallback_bounds` setting (a 100 m box by default) outside `FlowWorld3D` — there is no PCG volume actor whose bounds it could read. Outputs a box volume (`output_mode = Shape`, for set operations and the samplers' Bounding Shape pin) or one bounds point (`Points`), with `@data` attributes `bounds_min`, `bounds_max`, `grid_size`, `cell_x`, `cell_z`, `hierarchy_level`, `has_bounds`. Its optional Dependency pin only orders execution: `grid_size → get_execution_bounds` makes it run per cell. |
| Get Landscape Data | `get_surface_data` (legacy: `scan_meshes`) | partial | Godot has no landscape actor. `get_surface_data` turns terrain `MeshInstance3D` nodes, `HeightMapShape3D` collision shapes or a heightmap `Image` into surface data with height-field semantics (vertical projection, normals, footprint density); `surface_sampler` then samples it UE-style (see [forest tutorial](#tutorial-1--forest-quick-start)). With `source = Terrain` it reads a terrain plugin node through a terrain adapter: Terrain3D and HTerrain are detected by their methods (unmodified plugin classes work), or named with `terrain_node_path`; more than one candidate is reported as ambiguous. The surface carries the terrain's paint-layer weights, so Surface Sampler writes `layer_<name>` on every point. **The Terrain3D and HTerrain adapters are tested against fakes in the suite and were checked by hand against the real plugins (Terrain3D v1.0.2-stable, HTerrain 1.8.1 master, Godot 4.7.1, Windows); other versions and platforms are unchecked.** `scan_meshes` still emits the old `node`/`mesh` streams. See [Terrain adapters](#terrain-adapters). |
| Landscape layer weights (sampling a landscape writes layer weights) | `surface_sampler` / `to_point` on terrain surface data, or `sample_terrain_layers` | partial | Terrain surfaces (Get Surface Data with the Terrain source, or a heightmap image with splat layers) write one Float weight per layer, `layer_<name>`, onto sampled points (`write_terrain_layers`, on by default). `sample_terrain_layers` writes the same kind of weights onto any points, from mask textures (`layer_source = Textures`, the default) or from a terrain adapter (`TerrainAdapter`: Terrain3D control map, HTerrain splat maps, splat images on HeightMapShape3D, mesh or image terrains). Lookups take the nearest-lower texel (no filtering), and Terrain3D layers are snapshotted at vertex spacing for the surface. Filter with `density_filter` / `attribute_filter_range`. |
| Get Spline Data | `get_spline_data` (legacy: `scan_splines`) | 1:1 | Collects `Path3D` nodes (by group, or the whole scene) as spline data: a copied curve and world transform per Data, the way Unreal returns one spline data per spline component. `output_mode = Merged` returns one Data holding the union, by maximum density as in Unreal, so `tube_steepness` still softens merged tubes. Feeds Spline Sampler, To Point, Create Surface From Spline, Spawn Spline Mesh (per-spline output) and the set operations, where the spline acts as a tube of `tube_half_width` with a `tube_steepness` falloff. `scan_splines` still emits the old `node` stream of `Path3D`s. |
| Get Volume Data | `get_volume_data` | partial | Volume data from `CollisionShape3D` nodes (also the shapes inside an `Area3D` or physics body), CSG roots, and mesh bounds or closed meshes. Box and sphere shapes are exact and honour `steepness`; capsules and cylinders are meshed; a convex shape becomes the box of its points. `output_mode = Merged` (the default) unites the sources by maximum density, so `steepness` also softens merged sources. |
| Get Primitive Data | `get_volume_data` (mesh references: `scan_meshes`) | partial | Primitive components' collision as volume data, as above. `scan_meshes` still gives meshes with their `mesh` resources as streams. |
| Get Texture Data | `texture_sampler` | partial | Samples a texture *at existing points* (UV or world XZ) instead of producing surface data — reorder your chain: points first, then texture sample, then `density_filter`. |
| Get PCG Component Data | `FlowGraphNode3D.last_outputs` (script side) | partial | No in-graph node; read another component's outputs from script and feed them as graph inputs, or use a `subgraph` to share generation logic. |
| Get Actor Property | `scan_nodes` (import_properties), or `get_property_from_object_path` | partial | Property paths (incl. sub-resources like `mesh:size`) import as attributes. |
| Get Property From Object Path | `get_property_from_object_path` | partial | Object paths come from the settings (node paths relative to the owner or its scene root, `%Unique`, `/root/...`, or `res://` / `uid://` / `user://` resources), not from an input attribute. Properties use the `scan_nodes` `import_properties` syntax (`mesh:size`) and typing; one attribute-set row per object, with an `object_path` column. No struct or object-reference extraction. |
| Load Data Table | `load_data_table` | 1:1 | CSV/TSV rows → typed attribute streams. |
| Data Table Row To Attribute Set | `data_table_row_to_attribute_set` | 1:1 | By index or key match. |
| Load PCG Data Asset | `load_pcg_data_asset` | 1:1 | JSON / Resource-backed point data. |
| Load Alembic File | `load_alembic_file` | 1:1 | |
| — (bonus) | `points_from_imported_scene` | Godot-only | Loads a `PackedScene` or `Mesh` resource file and emits one point per `MeshInstance3D` found inside it, placed by the mesh's transform accumulated from the scene root (root included, as `global_transform` would give under an identity parent): position is the mesh AABB centre under that transform, rotation is its rotation, size is the AABB size times its scale. No scene-tree involvement — the scene is instantiated off-screen and freed immediately. Optionally exports the `Mesh` resource, source name, or file path as attributes. |

### Samplers

| UE node | Here | Status | Notes |
|---|---|---|---|
| Surface Sampler | `surface_sampler` | partial | On surface data (`get_surface_data`, composites) it follows Unreal's model: points per square meter (default 0.1), point extents, looseness, apply density, point steepness, a world-anchored grid with per-cell seeds, and an optional Bounding Shape pin (`use_bounding_shape`). Points land on the surface and get its `normal`. Caveat: surfaces are sampled along the world vertical, so vertical walls get no points. On point inputs or a scanned `node` mesh stream it keeps the old behaviour: `num_points` per input region (a count, not a density), `density` = 1.0 and per-point `seed`, then `projection` to drape onto uneven ground. |
| Spline Sampler | `sample_spline` | 1:1 | Distance mode (`uniform_interval`), random samples, segment centers (with look-at rotation — the fence trick), and **interior fill** of closed splines (grid / random / Poisson) with a distance-to-border attribute. Accepts spline data (`get_spline_data`) as well as the `node` stream of `Path3D`s, with identical output. |
| Mesh Sampler | `sample_mesh` (alias `mesh_sampler`) | 1:1 | Area-weighted random, one-per-vertex, or face centers; rotations from triangle normals; optional hard-edge rejection. |
| Volume Sampler | `volume_sampler` | 1:1 | On volume data (`get_volume_data`, composites, splines) it samples a voxel grid of `voxel_size` and keeps the voxels where the density is above 0. On point inputs, a regular 3D grid inside each input point's oriented volume, as before. |
| Texture Sampler | `texture_sampler` | 1:1 | Writes a Color attribute and/or scalar channel per point. |
| Copy Points | `copy_points` (alias `copy`) | 1:1 | Source-to-targets transform composition; also a LinearCopies mode ≈ Duplicate Point. |
| Select Points | `select_points` | 1:1 | Seeded random keep-ratio, optional weight attribute. |
| — (bonus) | `sample_points` (aliases: Point Subdivision, Blue Noise) | Godot-only | Subdivides each input point's volume into sub-points using **Uniform Grid**, **Quasi-Random** (golden-ratio 2D or 3D), or **Blue-Noise 2D** distributions. A point's `size` stream drives the sampling volume; output points carry density=1.0 and per-point seeds. Use it to scatter inside bounds without a separate source mesh. |
| — (bonus) | `navigation_region_sampler` | Godot-only | Samples `NavigationRegion3D` navmesh data into points. **Polygons** mode emits one point per navmesh polygon (position = centroid, with `normal` and `area` attributes); **Vertices** mode emits one point per navmesh vertex. Useful for AI spawn / placement that stays on walkable surfaces. |

### Spatial

| UE node | Here | Status | Notes |
|---|---|---|---|
| Difference | `difference` | partial | One node covers Difference both ways, Intersection, Union and Symmetric Difference via its `operation` setting. Shape with shape gives a composite that is sampled later (for example "landscape minus the road spline" before scattering). Points with a shape are filtered (`density_function` Binary, the default) or density-attenuated (Minimum / Multiply / Subtract) by the shape's density. Points with points use the RTree path with per-point bounds and steepness. Points against a shape follow `overlap_mode`: with `BoundsBox` (the default) a point is its bounds box, as Unreal treats point-versus-volume — a large point whose bounds reach into a volume is removed (Binary) or attenuated by the covered fraction shaped by its steepness. `PointCenter` tests the centre only. **Caveats:** the point box is axis-aligned (point rotation is ignored, Unreal tests the rotated box), and the overlap is exact only for axis-aligned boxes and spheres; other shapes are tested at 15 fixed samples (centre, 8 corners, 6 face centres), so a small shape inside a large point box can be missed. |
| Union | `union` (or `difference`, operation = Union) | partial | Shape with shape gives a union composite. The density functions map to Unreal's: Binary is 1 where either side has density, Minimum is max(a, b), Multiply is a+b-ab, Subtract is the clamped sum. Points with a shape fold the density, with the same `overlap_mode` and caveats as Difference; points with points merge as before. |
| Intersection / Inner Intersection | `intersection` (or `difference`, operation = Intersection) | partial | Shape with shape gives a composite: surface ∩ volume or surface ∩ surface samples only the overlap, before any points exist. Points with a shape keep the points whose bounds overlap it (Binary, `overlap_mode = BoundsBox`) or fold the density; same caveats as Difference. No N-way inner variant: chain the nodes. |
| Projection | `projection` | partial | Physics mode (the default) projects points onto colliders along a direction. `projection_mode = Surface` projects onto surface data wired to the Projection Target pin, with no physics and no owner. Both write `normal`, can align the rotation to it (`align_to_normal`), and Surface mode multiplies the density (`project_density`). No per-property projection toggles (scale, colour) or attribute merging. |
| To Point / Make Concrete | `to_point` | 1:1 | Samples a spline along its curve, a surface on the surface-sampler grid, and a volume on a voxel grid. A composite is sampled as a surface or a volume according to its kind, except a union made only of splines (`get_spline_data` Merged): each spline is sampled along its curve and the results are concatenated, as Unreal's To Point does for a union. Point data passes through. |
| Merge Points | `merge` (alias `merge_points`) | 1:1 | Multi-input concatenation with stream-union semantics. |
| Create Points | `create_points` | 1:1 | Hand-authored list of `FlowPointEntry` points: transform, bounds, density, steepness, seed (0 = derived from position) and extra attributes; World or Local (owner-relative) space. A 1×1×1 `grid` still works for a single generated point. |
| Create Points Grid | `grid`, `grid_fill_bounds` | 1:1 | `grid_fill_bounds` fills the bounds of upstream points. Its cells are centred on each box by default; `world_anchored = true` puts them on world multiples of `cell_size`, so adjacent boxes and `FlowWorld3D` cells share one grid (partition-invariant). |
| Create Spline | `create_spline` | 1:1 | Builds a `Path3D` through input points. |
| Create Surface From Spline | `create_surface_from_spline` | 1:1 | `output_mode = Shape` outputs real surface data: a polygon surface per closed spline (on the XZ, XY or YZ plane), with area and perimeter. Intersect it with a landscape, sample it, or use it as a cutter. Accepts `Path3D` streams or spline data. Points mode (the default) keeps the old bounds-point output; `sample_spline`'s interior fill is another way to scatter inside a closed spline. |
| Spatial Noise | `noise` | 1:1 | FastNoiseLite: Value/Perlin/Simplex/Cellular + fractal options; writes any attribute (default `density`), Override or Add. |
| Distance | `distance` | 1:1 | KD-tree nearest distance to a second input, optional normalization by `max_distance`. |
| Normal To Density | `normal_to_density` | 1:1 | Slope masking: density from dot(normal, reference direction) with offset/strength and Set/Min/Max/Add/Multiply combine. Reads the `normal` stream, falling back to the rotation's up vector. |
| Mutate Seed | `mutate_seed` | 1:1 | Position-stable per-point seed re-derivation. |
| Point Neighborhood | `point_neighborhood` | 1:1 | Radius-averaged values. |
| Point From Mesh | `point_from_mesh` | 1:1 | One point carrying a mesh's bounds. |
| Get Bounds | `get_bounds` | 1:1 | Bounds of a shape or of the points' effective bounds, as one bounds point (with `@data.bounds_min/max`) or a box volume (`output_mode = Shape`). `combine_points` still collapses a set to one bounds point. |
| Get Points Count | `get_points_count` | 1:1 | |
| Cull Points Outside Actor Bounds | `cull_points_outside_bounds` | partial | Keeps the points inside the current `FlowWorld3D` cell. X and Z are half-open (min ≤ p < max), so adjacent cells never both keep a point; this is the HiGen de-duplication step. `margin` is UE's Bounds Expansion; `use_point_bounds` keeps the points whose bounds box overlaps the cell. Outside `FlowWorld3D` there is no actor bounds to cull to and it passes its input through: to cull a plain graph to a box, use `intersection` with `get_execution_bounds` (its `fallback_bounds`) or `make_bounds` in Shape mode (`overlap_mode = PointCenter` to test centres), or `clip_points_by_polygon`. |
| Find Convex Hull 2D | `find_convex_hull_2d` | 1:1 | Hull of each input on the X/Z plane (Godot is Y-up). Hull points keep every attribute, in counter-clockwise X/Z order from the smallest x; `hull_index` order attribute for closed splines, optional collinear points and explicit loop closing. |
| Attribute Set To Point | `attribute_set_to_point` | 1:1 | |
| World Ray Hit Query | `ray_cast` (also `physics_shape_sweep`) | 1:1 | Per-point physics raycast with hit position/normal/rotation/collider outputs. |
| World Volumetric Query | `physics_overlap_query` | 1:1 | |
| Spatial Data Bounds To Point | `get_bounds` (or `combine_points` for points) | 1:1 | |
| Bounds From Mesh | `bounds_from_mesh` | 1:1 | Sets `bounds_min`/`bounds_max` from a mesh's local AABB: a settings mesh or a per-point Mesh attribute (falling back to the settings mesh). |
| — (bonus) | `split_splines` | Godot-only | Converts each spline segment between baked samples into a **segment-center point** oriented along the segment (Z-forward). Outputs `start`/`end` world positions, `segment_index`, `spline_index`, and optionally the source `Path3D` reference. Where `sample_spline` gives you uniformly spaced points *along* a spline, `split_splines` gives you one point *per segment* — handy for placing walls between corridor waypoints. |
| — (bonus) | `create_surface_from_polygon` | Godot-only | Creates an AABB bounds point from ordered polygon point streams, or with `output_mode = Shape` a polygon surface. Related to `create_surface_from_spline` but takes explicit point data instead of a `Path3D`. Outputs `area` (shoelace formula), `perimeter`, and `point_count` attributes. Supports a `group_attribute` to produce one surface per group. |
| — (bonus) | `grid_boundary` | Godot-only | Given a set of **filled grid cells** (position stream snapped to a cell grid), emits the exposed **edge** and **corner** points — the faces that have no filled neighbor. Each edge point is sized and rotated to span one cell face; corner points sit at exposed vertices. Three output pins: Edges, Corners, All. Perfect for building walls around a dungeon room layout. |
| — (bonus) | `grid_connect_points` | Godot-only | Connects ordered points with **orthogonal grid-cell paths** on the XZ plane (Manhattan / L-shaped corridors). Walk axis order is configurable (X-then-Z or Z-then-X). Outputs one cell point per step; optionally tags each path segment with a `path_index` attribute. Pairs with `grid_boundary` for dungeon corridor + wall generation. |

### Point Ops

| UE node | Here | Status | Notes |
|---|---|---|---|
| Transform Points | `transform_points` (alias `transform`) | 1:1 | Random offset/rotation/scale ranges, local-space rotation toggle, uniform-scale toggle. Per-point seeded when the `seed` stream exists. |
| Bounds Modifier | `bounds_modifier` | partial | Set / Add / Multiply a min/max box into the per-point `bounds_min`/`bounds_max` streams (`output_mode = PerPointBounds`, the default; asymmetric boxes are kept) or, in SymmetricSize mode, an extent into `size`. The mode set is not UE's. |
| Extents Modifier | `bounds_modifier` | partial | Same node, same caveat. |
| Apply Scale to Bounds | `apply_scale_to_bounds` | 1:1 | Multiplies `bounds_min`/`bounds_max` by the scale (`size`) per axis, keeping asymmetric bounds (a negative scale swaps min and max), then resets `size` to 1 (`reset_scale`). Points without bounds streams get ±size/2, so their world box is unchanged. |
| Duplicate Point | `duplicate_point` (also `point_offsets`, `copy` LinearCopies) | 1:1 | N copies along a world or local offset. |
| Split Points | `split_points` | 1:1 | Before Split / After Split pins; axis X/Y/Z (Unreal's Z is Godot's Y, the default) and 0..1 position, or a per-point position attribute. KeepTransform (Unreal) changes bounds only; Recenter also moves each half to its box center. Optional side and fraction attributes and an attribute-inheritance toggle. |
| Reset Point Center | `reset_point_center` | 1:1 | Moves the pivot to a normalized location inside the bounds (0.5 = center) and offsets `bounds_min`/`bounds_max` so the box stays in place. |
| Combine Points | `combine_points` | 1:1 | |
| Build Rotation From Up Vector | `build_rotation_from_up` | 1:1 | Aligns a chosen axis to a normal/up attribute. |

### Filters

| UE node | Here | Status | Notes |
|---|---|---|---|
| Density Filter | `density_filter` | 1:1 | Same pins (In Filter / Outside Filter), lower/upper bound + invert. Missing density = 1.0. |
| Point Filter | `filter` | 1:1 | Attribute vs. attribute/constant comparison, True/False outputs. |
| Point Filter Range | `point_filter_range` | 1:1 | |
| Attribute Filter / Attribute Filter Range | `attribute_filter_range` | 1:1 | Inside/Outside split by numeric range or string set. |
| Filter Data By Tag | `filter_data_by_tag` | partial | Any-match (OR) only; no match-all toggle. |
| Filter Data By Type | `filter_data_by_type` | 1:1 | Classifies spatial data by its shape (Spline / Surface / Volume, plus a SpatialData "any shape" target). Point data and attribute sets keep the previous classification (`Data.kind`, then stream heuristics). |
| Filter Data By Attribute | `filter_data_by_attribute` | 1:1 | Routes by attribute presence. |
| Filter Data by Index | `filter_data_by_index` | 1:1 | Routes whole data entries by their index on the pin (In Filter / Outside Filter), or points in Points mode. Syntax `0, 2:5, -1, -2:` (end-exclusive ranges, negative from the end), invert. `sequence_sample` remains for start/count/step strides. |
| Filter Attributes by Name | `remove_attribute` | 1:1 | Keep/remove listed streams. |
| Self Pruning | `self_pruning` | 1:1 | Native RTree bounds-overlap pruning (large-to-small) + a grid-cell dedupe mode. Overlap uses the effective bounds (`bounds_min`/`bounds_max`, else ±`size`/2); `density_function` attenuates instead of removing. |
| Discard Points on Irregular Surface | `discard_points_on_irregular_surface` | partial | The "surface" is the input point cloud: neighbours are the input points inside each point's X/Z bounds footprint (scalable with `footprint_scale`), not physics traces. Height std-dev / plane-fit residual / max deviation and max normal angle thresholds; Kept and Discarded pins; optional metric attributes. Native GDRTree neighbour queries with a GDScript fallback (identical results). |
| — (bonus) | `weighted_point_sampler` | Godot-only | Picks N points with probability proportional to a weight attribute, with or without replacement, per-point seeded (stable under reordering, follows the graph seed). Repeated picks get mutated seeds; Not Selected pin with the rest. Unlike `select_points` (keep ratio), it takes an exact count and can sample with replacement. |
| Difference (simple) | `substract` | partial | Older RTree subtraction node: removes points from A that overlap points from B (or keeps only the overlap in Intersection mode). Superseded by `difference` which has more modes and the same native acceleration — prefer `difference` in new graphs. |

### Density

| UE node | Here | Status | Notes |
|---|---|---|---|
| Density Remap | `density_remap` | 1:1 | Linear in-range → out-range, optional clamp. |
| Curve Remap Density | `curve_remap_density` | 1:1 | Remap through a Godot `Curve` resource. |
| Distance to Density | `distance_to_density` (or `distance` + `density_remap`) | 1:1 | |
| Density Noise | `attribute_noise` (targets `density` by default) | 1:1 | Exactly the UE 5.3+ story: Density Noise *is* Attribute Noise pointed at density. Set/Min/Max/Add/Multiply modes, per-point seeded, clamps when targeting density. |
| — (bonus) | `remap` | Godot-only | Remaps **any float attribute** through a Godot `Curve` resource. Unlike `density_remap` (linear in/out range) and `curve_remap_density` (always writes to density), `remap` lets you curve-shape any attribute by name. Set `Out Name` to `@in_name` to overwrite the source attribute in place. |

### Attributes / Metadata

| UE node | Here | Status | Notes |
|---|---|---|---|
| Add Attribute / Create Attribute | `add_attribute` | 1:1 | Constant-filled stream; creates a one-row attribute set if unwired. |
| Copy Attribute / Transfer Attribute | `copy_attribute` | 1:1 | Target and Source pins. ByIndex (equal counts, or one source entry broadcast), ByMatchAttribute (first source entry with an equal key; Int and Int64 keys compare as integers), NearestPoint (by position, optional max distance; native KD-tree). Copies one attribute (`@Source` keeps its name) or all attributes (point transform streams only on request). Types are preserved; unmatched points keep their existing value or the type default; optional matched flag. |
| Attribute Cast | `attribute_cast` | 1:1 | Any numeric, vector, Color, Quaternion, Transform or String attribute to another type, with explicit loss rules (see [Attribute types](#attribute-types)). The default `@Source` output retypes the attribute in place; canonical attributes keep their types. |
| Attribute Remove Duplicates | `attribute_remove_duplicates` | 1:1 | Keeps the first entry of every distinct value combination of the listed attributes (any type, exact comparison). |
| Attribute Rename | `attribute_rename` | 1:1 | |
| Delete Attributes | `remove_attribute` | 1:1 | |
| Attribute Noise | `attribute_noise` | 1:1 | Per-point seeded randomization of any attribute (also see `attribute_random` for the simple uniform case and `noise` for spatially-coherent noise). |
| — | `attribute_random` | bonus | Fills any attribute with **uniform random values** (float or int, min/max range). Simpler than `attribute_noise` — no noise type, no spatial coherence, just a flat random draw. Uses the point `seed` stream when present for per-point stability. Also supports a `use_index_as_value` mode to write sequential indices (0, 1, 2, …) into any attribute. |
| Attribute Partition | `partition` | 1:1 | One output data per unique value. |
| Attribute Select | `attribute_select` | 1:1 | Min, Max or Median of an attribute; vectors by X/Y/Z/W, length or a custom axis; strings lexicographically. Out: a one-entry attribute set (value + index); Point: the selected entry. Ties keep the first entry. `reduce` still gives Average/Min/Max reductions. |
| Attribute String Op | `attribute_string_op` | 1:1 | Append, Prepend, Replace, ToUpper, ToLower, Contains, StartsWith, EndsWith (Bool), Format (`{0}` `{1}` `{2}` `{index}` `{attribute}`), Length (Int), Trim, Substring. Non-String operands convert to text. `expression` remains for anything else. |
| Match And Set Attributes | `match_and_set` (+ `assets` for the table) | 1:1 | The weighted-pick-from-table workhorse: random-weighted or key-matched row copy. `assets` is the idiomatic table source (≈ spawner mesh entries as data). |
| Point Match and Set | `match_and_set` | 1:1 | |
| Merge Attributes | `merge_attributes` | partial | Merges every data on the pin into one attribute set. Append: union of attributes, entries concatenated, numeric clashes promoted (Int and Float give Float, Int and Int64 give Int64, Int64 and Float give Double), other clashes fail. ByIndex: columns side by side. Tags and `@data` attributes merge. The behaviour was reconstructed from Unreal's documentation, not checked against the engine. |
| Sort Attributes / Sort Points | `sort` | 1:1 | |
| Break Vector Attribute | `decompose_vector` | 1:1 | Vector, Vector2, Vector4, Quaternion and Color inputs (the fourth component goes to `w_attribute`). Also free via selectors: `position.x`, `uv.y`, `v4.w` work anywhere a stream name is asked. |
| Make Vector Attribute | `compose_vector` / `make_vector` | 1:1 | `compose_vector` has `output_type` (Vector, Vector2, Vector4) and a W component; Int64/Double components accepted. |
| Break/Make Transform Attribute | `break_transform_attribute` / `make_transform_attribute` | 1:1 | Transform attribute type (`Array[Transform3D]`). Make: translation + rotation (Euler degrees, or a Quaternion / Vector4) + scale, composed as UE does (scale, rotate, translate). Break: translation, Euler rotation, optional quaternion, scale. The defaults turn the point transform into an attribute and back. |
| Get Attribute from Point Index | `get_attribute_from_point_index` | 1:1 | Index (negative from the end) and any selector as input attribute. Outputs a one-row attribute set, the single point, and the input with the value as `@data.<name>`. |
| Point To Attribute Set | `point_to_attribute_set` | 1:1 | |
| Maths Op | `math_op` | 1:1 | Attribute-or-constant operands, result to named stream. |
| Boolean Op | `boolean` | 1:1 | And/Or/Not/Xor plus extras. |
| Bitwise Op | `bitwise_op` | 1:1 | And, Or, Xor, Not, ShiftLeft, ShiftRight on Bool/Int/Int64, computed in 64 bits; Int64 if either operand is Int64, else Int (low 32 bits); `output_type` forces one. |
| Compare Op | `compare_op` | 1:1 | == != > >= < <= into a Bool attribute. Integers compare exactly (Int64 too), reals within a tolerance for ==/!=, strings lexicographically (optional case folding), vectors per component (all / any) or by length, transforms and objects for equality only. `filter` still routes points by the same comparisons. |
| Trig Op | `trig_op` | 1:1 | Sin, Cos, Tan, Asin, Acos, Atan, Atan2, DegToRad, RadToDeg (radians). Int64/Double give Double; vectors work per component. |
| Vector Op | `vector_op` | 1:1 | Dot, Cross, Normalize, Length, LengthSquared, Distance, DistanceSquared, Reflect, Project, Lerp, RotateAroundAxis (degrees), Angle (degrees), ComponentMin/Max on Vector2, Vector, Vector4. Add/sub/mul/div stay on `math_op`. |
| Rotator Op | `rotator_op` | 1:1 | Combine / Invert / Lerp / RotateAroundAxis on the Euler `rotation` or the `rotation_quat` stream. |
| Transform Op | `transform_op` | 1:1 | Compose (apply A then B, UE order), Invert, Lerp (slerped rotation), TransformPosition, InverseTransformPosition, TransformDirection, plus ApplyToPoints (moves every point by a transform attribute). `expression` remains the escape hatch for any other per-point formula. |
| Reduce Op | `reduce` | 1:1 | Average/Min/Max across entries. |
| — (bonus) | `size` (node) | Godot-only | Returns the **point count** of the input as a single-entry Int attribute. Useful when you need the count as data to drive downstream expressions or graph inputs rather than as a debug display. (For the display use, `get_points_count` is the right choice.) |

### Spawners

| UE node | Here | Status | Notes |
|---|---|---|---|
| Static Mesh Spawner | `spawn_meshes` | partial | `mesh_entries` (`FlowMeshSpawnEntry`, ≈ mesh entries and instance descriptors): mesh, weight, material override, cast shadow, visibility range (≈ cull distances) with fade, render layers, GI mode, per-instance custom data from attributes (≈ instance packer), collision (none, box from bounds, convex, trimesh; layer and mask; one shared body per MultiMesh or one body per instance). Selectors: weighted (per-point `$Seed`), by attribute index, by attribute name or mesh resource (≈ MeshSelectorByAttribute), cycling. One `MultiMeshInstance3D` per render group and spawn parent. The legacy `mesh` / `mesh_variants` / `mesh_attribute` / `mesh_selector_attribute` path and per-instance colors keep working. Optional instance pooling (`reuse_instances`). Not there: per-slot material overrides, per-instance LOD and world-position-offset settings, writing the mesh bounds back to the points (use `bounds_from_mesh`). |
| Static Mesh Spawner: mesh entry descriptor fields | `FlowMeshSpawnEntry` | partial | `mesh`, `entry_name`, `weight`, `material_override` (one override, not per-slot), `cast_shadow`, `visibility_range_*` (≈ cull distance), `render_layers`, `gi_mode`, `custom_data_attributes` (up to 4 floats), `collision_mode` / `collision_bodies` / `collision_layer` / `collision_mask`. No per-instance LOD or WPO settings (Godot has no direct equivalent). |
| Spawn Spline Mesh | `spawn_spline_mesh` | partial | One `MeshInstance3D` per spline segment with a bent `ArrayMesh` (Godot has no spline mesh component), cached per mesh and segment. Forward axis, curve or linear tangents, curve or world up, start/end cross-section scale, per-control-point or tiled segmentation, per-segment entry selection, entry materials and collision. No per-point roll/scale interpolation from spline attributes; blend shapes are not carried. Input: a `Path3D` `node` stream or spline data. A composite (`get_spline_data` with `output_mode = Merged`, or a set operation) spawns every spline part, depth first in merge order (union and intersection: both operands; difference: the first operand only); the other operand does not clip the meshes, each part is spawned whole. |
| Spawn Actor | `spawn_scenes` (scenes) / `spawn_nodes` (raw nodes) | 1:1 | Instantiates a `PackedScene` (or a class/script) per point. `property_overrides` ≈ Spawn Actor property overrides: attribute → property path, nested (`position:x`), child (`Child/Light:light_energy`), `%Unique` names, type coercion, applied after instancing. `assign_attributes` kept. Optional `spawn_parent_attribute` and instance pooling (`reuse_instances`). |
| Spawn Actor: property overrides | `property_overrides` on `spawn_scenes`, `spawn_nodes`, `apply_on_actor` | 1:1 | See above. Values come per point, from a broadcast stream or a per-data attribute. Writes to a shared sub-resource are shared (make it `resource_local_to_scene`). |
| Create Target Actor | `create_target_node` (+ `spawn_parent_attribute` on spawners) | partial | A named `Node3D` container (not an actor template class) with groups and an owner policy (follow the component's `transient_output`, or always transient). Reused across regenerations and freed by `cleanup()`. Outputs `@data.target`; spawners parent under it with `spawn_parent_attribute`, which also accepts per-point parents. |
| — (component reuse) | `reuse_instances` on spawners (`FlowSpawnPool`) | Godot-only | Reuses MultiMeshInstance3Ds, scene roots, nodes and spline segments of the same component and node across `generate()` runs when mesh, material, scene or class match. Off by default. `regenerate()` and `cleanup()` free everything. |
| Point from Player Pawn | `point_from_player_pawn` | 1:1 | |
| Apply On Actor | `apply_on_actor` | 1:1 | Writes attributes/transforms onto existing scene nodes; `property_overrides` resolve from the target node itself. |

### Control Flow, Subgraph & Loop

| UE node | Here | Status | Notes |
|---|---|---|---|
| Branch | `branch` | 1:1 | Bool routing (static or attribute-driven). |
| Switch | `switch` | 1:1 | |
| Select | `select` | 1:1 | |
| Select (Multi) | `select_multi` | 1:1 | |
| Runtime Quality Branch / Select | `runtime_quality_branch` / `runtime_quality_select` | 1:1 | Levels Low 0, Medium 1, High 2, Epic 3, Cinematic 4, with Default plus per-level pins enabled by `use_*_pin`. The level comes from the runtime parameter `quality` (int, level name or numeric string), else the project setting `flow_nodes/quality_level` (default 0), with a per-node `quality_override` for previews. Select runs once per bulk of its Default pin, like `select`. |
| Proxy | — | roadmap | |
| Gather | `gather` | partial | Collects every data wired into In onto one pin, in wire order, without concatenating (that is `merge`). The Dependency Only pin only orders execution. Reconstructed from Unreal's documentation, not checked against the engine. |
| Subgraph | `subgraph` | 1:1 | Nested `.tres` graphs, dynamic pins from graph params, per-instance override pins (≈ graph parameter overrides), collapse-selection-to-subgraph. |
| Subgraph (dynamic graph override) | `subgraph.graph_attribute`, `loop.graph_attribute` | partial | A String resource path or a `FlowGraphResource` attribute picks the graph per input entry (subgraph, from its extra `Graph` pin) or per iteration (loop). The node's `graph` is the default and defines its pins; a resolved graph's inputs and outputs are matched by name. Graphs are loaded with `ResourceLoader` and run through the compiled-graph cache. An unusable graph is an error naming the entry or iteration; `loop.on_graph_error` skips that iteration or stops. |
| Loop | `loop` | partial | `iteration_mode`: `Entries` is Unreal's Loop (one iteration per data entry on the Stream pin); `Points` (the default, the historical behaviour) runs once per point, `Partitions` once per distinct attribute value in ascending order, `Chunks` once per `chunk_size` points — the last three once per input entry. Iterations get `iteration_index`, `iteration_count` and `iteration_key` (plus the per-data attributes in Entries and Partitions mode) as runtime params, usable from `$param` bindings. The iteration seed is `derive_seed(graph seed, key_seed(iteration_key))`, so removing a partition does not reshuffle the others. `output_mode`: `Merge` (default) concatenates, `Collection` emits one output entry per iteration. |
| Loop (feedback pins) | `loop.feedback_param_name` | partial | One feedback parameter (Unreal allows several feedback pins), threaded through the iterations in every mode. In Collection mode each output entry carries the feedback value after its iteration. |
| Partition then Loop | `loop` in `Partitions` mode, or `partition` → `loop` in `Entries` mode | 1:1 | |
| Get Loop Index | `get_loop_index` with `source = LoopIteration` | 1:1 | The enclosing loop's iteration index in every mode (plus `start_index`), written to every incoming point or as a one-value Data. The default `source = Points` is the historical per-point enumeration (closer to `$Index`). |
| — (bonus) | `get_loop_key` | Godot-only | The current iteration's key: the point, entry or chunk index, the entry's `key_attribute` value, or the partition value, typed like the key. |
| Set Variable / Get Variable | `set_variable` / `get_variable` | 1:1 | Named in-graph data channels: `set_variable` stores its input under a named key in the evaluation context and passes the data through unchanged; `get_variable` reads the stored data by name. Wire color matches across paired nodes. Use these to share data between distant parts of a complex graph without long cross-canvas wires — exactly like UE PCG's Variable nodes added in 5.4. |

### Hierarchical / GPU

| UE node | Here | Status | Notes |
|---|---|---|---|
| Grid Size (HiGen) | `grid_size` + `FlowWorld3D` | partial | Nodes downstream of a marker run once per cell of its power-of-two `cell_size` when a `FlowWorld3D` generates the graph. Under several markers the smallest size wins, and nodes with no marker upstream run once for the whole world (Unbounded). Coarser results are handed whole to the finer cells they contain. Levels come from the graph topology when it compiles, so overrides and `$param` bindings of `cell_size` are not seen; a marker inside a subgraph is a pass-through (the subgraph runs whole within its own level). Outside `FlowWorld3D` the marker is a pass-through. |
| Hierarchical Generation (partitioned component, partition actors) | `FlowWorld3D` | partial | One `FlowGraphNode3D` child per generated cell (`FlowCell_L<size>_<x>_<z>`; `FlowCell_L0_0_0` for the Unbounded run), coarse levels first. Spawners spawn into the cell, so cleaning a cell up frees exactly its content. Cells are created at run time (or from the inspector's Generate All button), never saved into the scene and not streamed as level data. See [Hierarchical and runtime generation](#hierarchical-and-runtime-generation). |
| Custom HLSL / all GPU nodes | `compute_kernel` | partial | Escape-hatch node runs a user-supplied GLSL compute shader over point streams via `RenderingDevice` (declared in/out stream bindings), with graceful CPU fallback. Not a transparent "Execute on GPU" flag; the native GDExtension (KdTree/RTree) still covers the hot paths. |

### Generic / Tags / Debug

| UE node | Here | Status | Notes |
|---|---|---|---|
| Add / Delete / Replace Tags | `add_tags` / `delete_tags` / `replace_tags` | 1:1 | Also available as a single combined node: `tags_mutate` ("Tags") — select Add / Remove / Replace via its `operation` setting. |
| Get Data Count | `get_data_count` | 1:1 | |
| Get Entries Count | `get_entries_count` | 1:1 | |
| Debug | `debug` (or just press `D`) | 1:1 | |
| Print String | `print_string` | 1:1 | |
| Sanity Check Point Data | `sanity_check` | 1:1 | |
| Add Comment | `C` key | 1:1 | |
| Reroute | `reroute` (double-click a wire) | 1:1 | |
| Named Reroute Declaration | `set_variable` | partial | Declares a named, wire-free channel: `variable_name` is the reroute name, the title reads "Set: name", and its ports take the `node_color` setting, which the matching Get nodes share. The data passes through, so it can sit inline. A name is not scoped: it is visible to the whole graph, and nested subgraph and loop evaluations inherit the variables. The search popup does not find it by the Unreal name. |
| Named Reroute Usage | `get_variable` | partial | Reads the channel declared by the `set_variable` of the same name anywhere in the same graph; pick the name from the node's drop-down. The executor orders usages after their declaration, also in threaded mode. Clicking either node flashes its counterparts. |
| Execute Blueprint | `expression` / write a node script | partial | `expression` = per-point GDScript with streams bound by name. Full custom nodes are a single `.gd` file extending `FlowNodeBase` — substantially less ceremony than a `UPCGBlueprintElement`. |

Nodes here with **no UE counterpart** (you get them for free): `weighted_point_sampler` (exact-count weighted pick), `relax` (Lloyd relaxation), `snap_to_grid`, `clip_points_by_polygon` / `clip_paths` / `polygon_operation` (spline-polygon clipping), `random_color`, `sequence_sample`, `points_from_gridmap` / `points_from_tilemap` / `points_from_imported_scene` (Godot-native data sources), `navigation_region_sampler` (navmesh → points), `sample_points` (subdivision with blue-noise / quasi-random), `split_splines` (spline-segment-center points), `create_surface_from_polygon` (polygon → AABB point), `grid_boundary` / `grid_connect_points` (grid-cell topology helpers), `set_variable` / `get_variable` (named wire-free data channels), `attribute_random` (simple uniform random attribute), `remap` (curve remap any float attribute), `tags_mutate` (combined add/remove/replace tags), `size` (point count as data), `get_loop_key` (the loop iteration's key), the `dungeon_*` generator family, and `expression`.

**New roadmap-parity nodes** (see [PARITY_ROADMAP.md](PARITY_ROADMAP.md#implementation-status-2026-10)): `rotator_op` (Combine/Invert/Lerp/RotateAroundAxis on Euler or quaternion rotations), `subdivide_segment` (slice splines/segments into sized, oriented sub-segments), `grammar_expand` (UE-style shape-grammar expansion into placeable modules), `sample_terrain_layers` (paint layers from mask textures or, since round 2, a terrain adapter), `compute_kernel` (GLSL compute-shader escape hatch), and `grid_size` (the HiGen marker; `FlowWorld3D` executes it per cell since round 2). Density-aware set ops live on `difference`/`self_pruning` via their `density_function` setting, and per-point `bounds_min`/`bounds_max`/`steepness` streams are honored when present.

**Parity round 2** (see [PARITY_ROADMAP.md](PARITY_ROADMAP.md#implementation-status-2026-10)) added the spatial-data nodes (`get_spline_data`, `get_surface_data`, `get_volume_data`, `to_point`, `get_bounds`), the attribute-type family (`attribute_cast`, `compare_op`, `copy_attribute`, `merge_attributes`, `gather`, the op nodes, ...), the spawner family (`spawn_spline_mesh`, `create_target_node`, mesh entries, property overrides) and the point nodes (`apply_scale_to_bounds`, `split_points`, `create_points`, `filter_data_by_index`, ...). Its second wave added hierarchical and runtime generation (`FlowWorld3D`, `get_execution_bounds`, `cull_points_outside_bounds`), terrain adapters, loop iteration modes with `get_loop_key` and dynamic subgraphs, the editor support for the new types and shapes, and a conformance harness over every node. The next section explains the architecture behind them.

---

## Architecture: how Unreal's PCG model maps here

Unreal splits PCG into settings, stateless elements, a compiled task graph with a cache, typed spatial data, partitioned and runtime generation and a spawner family. Since parity round 2 the addon has the same shape. You do not need any of this to follow a tutorial, but it explains what the nodes above do with your data.

### Execution model

| Unreal | Here | Notes |
|---|---|---|
| `UPCGSettings` | `NodeSettings` resource (`<template>_settings.gd`) | What the sidebar inspector edits and the graph `.tres` saves. Overrides and bindings are applied to a fresh copy per run, never to the saved one. |
| `UPCGNode` / node widget | `FlowNodeWidget` (a `GraphNode`) | Shows one node in the editor: ports, colours, error text, the execution-time badge. Node scripts that need custom UI implement optional `widget_*` hooks (listed at the top of `node.gd`). |
| `IPCGElement` | `FlowNodeBase`, a `RefCounted` element | Node scripts `extends FlowNodeBase` and implement `execute(ctx)`. The executor creates fresh elements for every run and drops them afterwards; there is nothing to `free()`. |
| `FPCGGraphCompiler` | `FlowCompiledGraph.for_graph(graph)` | Parses the graph once (node descriptors, links, execution order, migrated data, hierarchy levels) and keeps the result on the graph until `graph.data` or the node registry changes. |
| `FPCGGraphExecutor` | `FlowExecutor` | One executor, three modes: synchronous (`generate()`, `FlowNodeIO.evaluate`), time-sliced (`generate_async()` / `async_generation`, `FlowNodeIO.begin_evaluation`) and threaded (`threaded`). The editor dock runs each node through the same `FlowExecutor.execute_element`. |
| `IPCGElement::CanExecuteOnlyOnMainThread` / `IsCacheable` | `FlowNodeTraits` (`main_thread`, `cacheable`) | A central table for every stock template, overridable with `meta_node["main_thread"]` / `meta_node["pure"]`. Unknown third-party templates default to main thread and not cacheable, which is always safe. |

Writing a node: one `.gd` file that `extends FlowNodeBase`, a settings resource, and a `meta_node` dictionary (title, category, aliases, ins/outs). Read inputs with `get_input` / `require_input`, write outputs with `set_output`, and never modify an input `Data` in place (duplicate it first): a cached or threaded run hands the same input to several consumers. If your node is a pure function of its settings, seed and inputs, add `"pure": true` to `meta_node` so threaded mode and the cache can use it.

### Caching and threading

Both are **opt-in** on `FlowGraphNode3D` and off by default. With either on, the outputs, errors and spawned nodes are identical to a plain run (checked over the whole golden set).

- **`output_cache = true`** (≈ `FPCGGraphCache`). A cacheable node's outputs are stored in `FlowOutputCache`, keyed by the template, every settings value after overrides and bindings, the effective seed and the content hash of every input. A hit returns copies. The cache is process-wide and bounded (`FlowOutputCache.max_entries`, 1024 by default, least recently used first); `FlowOutputCache.hits` / `misses` count it. Resources referenced from settings are keyed by identity, so after editing a Curve or Mesh in place call `FlowOutputCache.clear()`.
- **`threaded = true`**. Independent nodes that the traits mark thread-safe run on `WorkerThreadPool` threads. Nodes that touch the scene tree, physics or rendering, spawn, read graph variables or runtime parameters, or run a nested graph stay on the main thread, in their sequential order, and never run while pool tasks do. It pays off on compute-heavy independent branches (about 2.9 times faster on 4 cores in the round-2 benchmark); graphs made of many small nodes do not get faster. **Warning:** errors a node prints outside its own `setError` (a `push_error` from a `FlowData` helper, a `push_warning`, an engine error) are raised on the worker thread, and Godot calls every script `Logger` (`OS.add_logger`) on the raising thread. A Logger that is not thread-safe can corrupt memory and crash the process. The nodes known to log that way (`FlowNodeTraits.LOGGING_TEMPLATES`, or `meta_node["logs"] = true`) run one at a time on the calling thread, but any pure node can still print an unforeseen engine error from a worker: keep `threaded` off, or make your Loggers thread-safe, when you register one.
- **`async_generation = true`** (time-sliced, `frame_budget_ms`) spreads one evaluation over frames, node by node. With it the top-level graph is never threaded; nested subgraph and loop evaluations still follow `threaded`.

Owner-less runs (`FlowNodeIO.evaluate`) take these options from the context: `ctx.set_meta(FlowExecutor.THREADED_META, true)` or `ctx.set_meta(FlowExecutor.OUTPUT_CACHE_META, true)` on a context from `FlowNodeIO.make_context`, then `FlowNodeIO.evaluate_collecting_errors(graph, inputs, ctx)` (returns `{outputs, errors}`).

**Conformance harness** (≈ contract tests for `IPCGElement::IsCacheable` / `CanExecuteOnlyOnMainThread`). `demo/tests/executor/conformance/` drives every registered template through `FlowExecutor.execute_node` with synthetic inputs (points with every canonical stream and one attribute of every type, empty and single-point Data, attribute sets, tagged Data, one Data per shape class, and a second input where the node has one). It fails the build when a node mutates an input, gives two different results for the same input, gives a different result on a worker thread than on the main thread (threadable templates), or a different result on a cache hit (cacheable templates), and when a node raises a script error. A static scan reports scene, physics, rendering and context accesses in threadable templates. New nodes are covered automatically once they have a traits row. On this branch it covers 167 templates and 2244 fixture cases with no failure; `godot --headless --path . -s res://tests/executor/conformance/tools/conformance_report.gd` prints the per-template table. A pass is evidence, not proof: a worker batch runs three copies of the same element, not every interleaving.

### Hierarchical and runtime generation

`FlowWorld3D` (`world/flow_world_3d.gd`) is the partitioned component: it generates one graph over `world_bounds` in cells, as Unreal's hierarchical generation does with partition actors.

| Unreal | Here |
|---|---|
| Grid Size node, HiGen levels | `grid_size` marker. A node's level is the `cell_size` of the nearest marker upstream of it; under several markers the smallest wins; a node with no marker upstream is on the **Unbounded** level (0) and runs once for the world. `FlowCompiledGraph` computes the levels from the topology (links and `set_variable` → `get_variable` dependencies) when it compiles the graph. Sizes are powers of two. |
| Partition actor (one per grid cell) | A `FlowGraphNode3D` child named `FlowCell_L<size>_<x>_<z>` (the Unbounded run is `FlowCell_L0_0_0`), run through `FlowGraphNode3D.generate_cell`. It evaluates only its level's nodes; spawners spawn into it, so `cleanup_cell` frees exactly that cell's content. Cell components are always `transient_output` and are never saved. |
| Partition actor bounds | The cell box `AABB(Vector3(x*size, world_min_y, z*size), Vector3(size, world_height, size))` intersected with `world_bounds` on XZ. Ownership is half-open on X and Z (`min <= p < max`) and closed on Y, so adjacent cells never both own a point. Graphs read it through `get_execution_bounds` and `EvaluationContext.bounds` / `has_bounds` / `grid_size` / `cell_coord` / `hierarchy_level`. |
| Larger grids feeding smaller ones | Coarser cells generate first. The outputs a finer cell consumes are handed in **whole** from the coarser cell that contains it (or from the Unbounded run), not culled to the finer cell, and are cached on the world while that coarser cell stays generated. Graph variables published by coarser cells are seeded into the cell's context. |
| Runtime generation, generation sources, per-grid radii | `generation_mode = Runtime`: every frame, cells within each level's `generation_radius` (grid size → radius; 0 is Unbounded) of a generation source are queued, coarser levels first and then nearest, and generated time-sliced within `frame_budget_ms` and `max_concurrent_cells`. A finite radius that covers more than `MAX_RUNTIME_CELLS_PER_LEVEL` (16384) cells of a level is limited to the 127 × 127 cells nearest the source, with a warning. Cells beyond radius × `cleanup_radius_multiplier` (1.1) of every source are cleaned up. Sources are the members of the group `flow_generation_source` (a `FlowGenerationSource` node joins it and adds `enabled` and `radius_scale`) plus `FlowWorld3D.sources`. |
| Generate on load / on demand | `generation_mode = OnLoad` queues every cell when the game starts. `Manual` (the default) does nothing on its own; `generate_all()`, `generate_bounds(aabb)`, `generate_cell(level, coord)`, `cleanup_cell`, `cleanup_all` are synchronous. The inspector has Generate All and Cleanup All buttons; nothing else runs in the editor. |
| Partition actor reuse | Cleaned-up cell components go to a pool (`cell_pool_size`, 32) and are reused with names and state reset. |
| `OnPCGGraphGenerated` per partition | Signals `cell_generated(level, coord)`, `cell_cleaned_up(level, coord)`, `all_generated`; each cell component also emits `generated`. |

Level ids are grid sizes in world units (0 for Unbounded), so they stay stable when markers are added or removed. Every cell gets the world `seed` unchanged, so position-hashed randomness is continuous across cell edges; graphs that want per-cell variation read `cell_x` / `cell_z` from `get_execution_bounds`. A source node (no input) has no marker upstream, so it runs once on the Unbounded level; to run it per cell, wire `grid_size (no input) → get_execution_bounds` and use the bounds, for example on the surface sampler's Bounding Shape pin.

**Partition invariance.** A graph `grid_size → get_execution_bounds → sampler → cull_points_outside_bounds` generated through cells gives the same points as the same graph run in one piece and culled to the world bounds, but only for world-aligned samplers. The tests pin both lists, so a sampler that changes alignment fails them.

| Sampler (configuration) | World-aligned |
|---|---|
| `surface_sampler` on surface data, points per square meter, Bounding Shape = execution bounds | yes: candidates sit on a world-anchored grid with per-grid-cell seeds |
| `volume_sampler` on volume data (for example `intersection(make_bounds Shape, execution bounds)`) | yes: voxel centres on a world-anchored grid |
| `to_point` on the execution-bounds box | yes: the same voxel grid |
| `grid_fill_bounds` with `world_anchored = true` | yes: cells on world multiples of `cell_size` |
| An Unbounded generator handed whole to the cells (`grid → grid_size → cull`) | yes, trivially; every cell holds the whole input, which costs memory |
| `surface_sampler` in count mode (`num_points`), or on point inputs | no: `num_points` random points per cell or per input region |
| `grid_fill_bounds` (default) | no: cells centred on each input box |
| `sample_points` (uniform grid, quasi-random, blue noise) | no: subdivides each input point's own box, and the sequences restart per box |

Add `cull_points_outside_bounds` before anything that consumes neighbours across cells. As in Unreal, a finer cell sees only the coarser cell that contains it, so a fine point near a coarse cell's edge can miss a coarse point just across it.

Differences from Unreal: cells are not saved or streamed as level data (no World Partition equivalent); the scheduler measures distance on the XZ footprint; a grid level without a radius entry uses one cell size and the Unbounded level 256 units (this addon's defaults); a coarser cell is kept while finer cells need it, and manual or OnLoad cells are never cleaned up by the scheduler; time slicing is per node, so one heavy node can overrun `frame_budget_ms`. `threaded` applies to the synchronous manual API; time-sliced runs keep each cell's top level sequential. The scheduler was verified with an injected clock and fake sources plus a 1500-frame headless run of `demos/demo_hierarchical.tscn`; frame times with heavy graphs, and cameras or players as sources in a real game loop, were not measured.

### Spatial data

A wire carries `FlowData.Data` objects. A `Data` holds point streams, a spatial shape (`Data.shape`, a `FlowSpatial`), or both; a shape-bearing Data may have no points at all. Shapes are deferred descriptions: nothing is sampled until a sampler or To Point asks for points, so the Unreal algebra works (intersect a landscape with a volume, subtract a road spline, then scatter).

| Unreal | Here |
|---|---|
| Spline data | `FlowSplineShape` (a copied `Curve3D` and world transform; as a density, a tube of `tube_half_width`, measured in world space also under a non-uniform scale) |
| Landscape / surface data | `FlowHeightfieldSurface` (`HeightMapShape3D`, heightmap `Image`, or a terrain plugin snapshot; NaN heights are holes), `FlowMeshSurface` (triangles with an XZ acceleration grid), `FlowPolygonSurface` (a closed polygon, from Create Surface From Spline / Polygon) |
| Landscape layer weights on the surface | `FlowSurfaceLayers`, attached to a terrain surface by its adapter (`FlowSpatial.get_layers()`); composites expose their surface operand's layers |
| Volume / primitive data | `FlowBoxVolume`, `FlowSphereVolume`, `FlowMeshVolume` (closed mesh, parity inside test), `FlowPointsVolume` (points seen as boxes, used when points are a composite operand) |
| Composite (union / intersection / difference) data | `FlowCompositeShape`, built by `difference` / `intersection` / `union` from two shapes |

Every shape answers `get_bounds()`, `sample_density(world_pos)` (0..1, with a steepness falloff on boxes, spheres, spline tubes and point volumes), `project(world_pos)` (surfaces), `to_points()` and `content_hash()`. `Data.kind` follows the shape, so `filter_data_by_type` and the pins classify it. Shapes copy their source geometry when they are created, so they are immutable: a scene edit after generation cannot change a cached result, and queries are safe on worker threads.

Set operations combine densities with the `density_function` setting. `a` is the density of A (or of the point), `b` the density of B (or of the shape); results are clamped to 0..1:

| Operation | Binary (default) | Minimum | Multiply | Subtract |
|---|---|---|---|---|
| Difference | b > 0 ? 0 : a | min(a, 1-b) | a(1-b) | a-b |
| Intersection | b > 0 ? a : 0 | min(a, b) | ab | a-(1-b) |
| Union | a > 0 or b > 0 ? 1 : 0 | max(a, b) | a+b-ab | min(a+b, 1) |

Points against a shape: Binary filters the points (Difference drops the points where the shape has density, Intersection keeps them); the other functions keep every point and fold the density, so add a `density_filter` before a spawner. Which density stands for a point depends on `overlap_mode`:

- **`BoundsBox`** (the default, as Unreal treats point-versus-volume): the shape is evaluated over the point's world bounds box (`position + bounds_min .. position + bounds_max`, else `position ± size / 2`; axis-aligned, point rotation ignored). The box gives a peak density and a mean coverage, exact for axis-aligned boxes (and the coverage for hard boxes) and for spheres, from 15 fixed samples (centre, 8 corners, 6 face centres) for every other shape. A hard point (steepness 1) uses the peak: any overlap counts fully, so Binary removes or keeps it. A softer point scales the peak by the covered fraction shaped by its steepness, the same rule point-versus-point `difference` uses. Against a hard axis-aligned box the result equals point-versus-point `difference` against one point with that box.
- **`PointCenter`**: the shape's density at the point's position (the first round-2 behaviour).

The setting applies only when the points are what is kept or filtered and the other input is a shape; shape with shape, a shape minus points (the points become box volumes) and points with points ignore it.

Surface sampling follows Unreal's Surface Sampler: candidates on a world-anchored XZ grid with cell size 1/sqrt(points per m²), per-cell seeded jitter (`looseness`), a vertical projection onto the surface weighted by its density, and bounds of ±`point_extents`. Because the grid is anchored to the world, points stay put when the sampled region grows or shrinks. Surfaces are sampled along the vertical only.

### Terrain adapters

Godot has no landscape actor; terrains are `HeightMapShape3D` collision, heightmap images, meshes or plugin nodes. A `FlowTerrainAdapter` (`terrain/`) gives all of them one read interface — `get_bounds()`, `get_height(x, z)`, `get_normal(x, z)`, `get_layer_names()`, `get_layer_weight(name, x, z)` and `to_surface()`, which builds an immutable surface shape carrying the layer weights. Heights and normals beyond the terrain are clamped onto its edge.

| Adapter | Source | Paint layers | Surface |
|---|---|---|---|
| `FlowHeightMapShapeTerrainAdapter` | `HeightMapShape3D` in a `CollisionShape3D` | splat images | the height grid |
| `FlowImageTerrainAdapter` | heightmap `Image` (cell size, height scale, transform) | splat images (`FlowTerrainSplatLayer`: an image or texture channel, or luminance) | the height grid |
| `FlowMeshTerrainAdapter` | `MeshInstance3D` | splat images over the mesh bounds | the mesh surface |
| `FlowTerrain3DAdapter` | a Terrain3D node, by duck typing (`data.get_height`, `data.get_normal`, `data.get_texture_id`, region queries) | the control map | a height snapshot at the vertex spacing (capped by `terrain_max_resolution`) |
| `FlowHTerrainAdapter` | an HTerrain node, by duck typing (`get_data()`, `get_interpolated_height_at`, `get_resolution`, splat maps) | splat maps, four layers per map | a height snapshot in cell space |

`get_surface_data` with `source = Terrain` uses them: it takes `terrain_node_path`, or finds the single terrain plugin node in the scene (or in `group_name`) by its methods, not its class name, and reports none or several found as an error. The output carries the `@data` attributes `source`, `terrain_type` and `terrain_layers`. `surface_sampler` (and `to_point`) then write one `layer_<name>` Float stream per paint layer at each sample (`write_terrain_layers`, `terrain_layer_prefix`); `sample_terrain_layers` with `layer_source = TerrainAdapter` reads the same weights for any points. Built-in sources (`HeightMapShape3D`, meshes) are never auto-detected; use the Scene source or name them by path.

**The Terrain3D and HTerrain adapters were checked against the real plugins once** (Terrain3D v1.0.2-stable and HTerrain 1.8.1 (master), unmodified, Godot 4.7.1 on Windows); the suite itself still uses fake classes that implement the methods the adapters call. The real run found one HTerrain bug (the height snapshot called `get_height_at` with the wrong arguments), now fixed. In that run both adapters gave correct heights and layer weights, and a scene with both plugins reports the ambiguity. Other plugin versions, Linux and macOS are unchecked. Every call is guarded, so a wrong assumption gives wrong values, not a crash. Check against your plugin version before relying on it.

### Loops and dynamic subgraphs

`loop` runs a graph once per iteration of its Stream input:

| `iteration_mode` | One iteration is | `iteration_key` |
|---|---|---|
| `Points` (default) | one point, once per input entry (the historical behaviour) | the point index |
| `Entries` | one data entry of the pin, all entries together (Unreal's Loop) | the entry index, or the entry's `key_attribute` value |
| `Partitions` | the points with one value of `partition_attribute`, in ascending key order | the value |
| `Chunks` | `chunk_size` consecutive points | the chunk index |

Each iteration's evaluation gets the runtime params `iteration_index`, `iteration_count` and `iteration_key`, plus the iteration data's per-data attributes in Entries and Partitions mode; they work in `$param` bindings and are inherited by nested subgraphs. The iteration seed is `0` when the graph seed is 0 (each body node keeps its own `random_seed`, as before), else `FlowNodeBase.derive_seed(seed, key_seed(iteration_key))`, where `key_seed` is the key itself for an int key. Point-mode seeds are therefore unchanged, and partition seeds depend only on the partition value. `output_mode = Collection` emits one output entry per iteration instead of one merged Data. `feedback_param_name` threads one value through the iterations in every mode. `get_loop_index` (`source = LoopIteration`) and `get_loop_key` read the index and key inside the body.

`graph_attribute` on `loop` and `subgraph` names the graph per iteration or per entry (a String path or a Graph attribute); the node's `graph` stays the default and defines the pins. A 100-iteration loop over a 20-node body costs about 2.9 ms per iteration on the build container, about 4 times less than before round 2, because the body is compiled once.

### Spawners and generated content

| Unreal | Here |
|---|---|
| Static Mesh Spawner + mesh entries | `spawn_meshes` with `mesh_entries`, an array of `FlowMeshSpawnEntry` resources saved inside the graph: mesh, weight, material override, cast shadow, visibility range (≈ cull distance) with fade, render layers, GI mode, custom data attributes, collision |
| Mesh selectors | `entry_selection`: Weighted (seeded per point from `$Seed`, else the position, so a point keeps its pick when others are added), AttributeIndex, AttributeName (a String attribute, or a Resource attribute holding the mesh), Cycle |
| Instance packer / custom data | `custom_data_attributes`: Float, Int and Bool fill one channel, Vector three, Color and Quaternion four, up to four channels (`INSTANCE_CUSTOM` in the shader) |
| ISM component per mesh | one `MultiMeshInstance3D` per group of points whose entries share every render, custom-data and collision setting, per spawn parent |
| Collision on instances | `collision_mode` None / BoxFromBounds / Convex / Trimesh with layer and mask. `collision_bodies = PerMultiMesh` (default) builds one `StaticBody3D` (`FlowInstancedCollision3D`) per MultiMesh with one shape owner per instance; `PerInstance` builds a body per instance |
| Spline Mesh component | `spawn_spline_mesh`: one `MeshInstance3D` per spline segment with a bent `ArrayMesh`, cached by mesh and segment |
| Spawn Actor property overrides | `property_overrides` on `spawn_scenes`, `spawn_nodes`, `apply_on_actor`: attribute name → property path (`light_energy`, `position:x`, `Child/Light:light_energy`, `%Unique:prop`), coerced to the property's type |
| Create Target Actor | `create_target_node` + `spawn_parent_attribute` on every spawner (per point, broadcast, or `@data.<name>`) |
| Component and instance reuse | `reuse_instances` on spawners (`FlowSpawnPool`), off by default |

Everything a spawner creates carries `flow_owner` meta naming the component and the node, so `cleanup()` frees exactly this component's output, `transient_output` keeps it out of the saved scene, and two components sharing a parent never delete each other's nodes. Stock spawners tag their content with `FlowNodeBase.tagFlowContent(node, ctx)`, which also records it on the component, so `cleanup()` only visits the component's own subtree and the spawn parents it recorded (about 40 times faster for 200 sibling cells than a scan of the whole parent). A custom spawner should call `tagFlowContent` too; one that sets `flowOwnerMeta(ctx)` itself still works, at the cost of the old full scan. Without an owner (owner-less `FlowNodeIO.evaluate`), spawners report "needs an owner node" and pass their input through. Spawners always run on the main thread.

### Attribute types

| DataType | Container | Notes |
|---|---|---|
| Bool, Int, Float, Vector, String | `PackedByteArray`, `PackedInt32Array`, `PackedFloat32Array`, `PackedVector3Array`, `PackedStringArray` | Vector is always 3 components. |
| Color, Quaternion | `PackedColorArray`, `PackedVector4Array` | `PackedVector4Array` infers as Quaternion. |
| Resource, NodeMesh, NodePath | `Array` | Object references (meshes, scene nodes). |
| Vector2, Vector4 | `PackedVector2Array`, `PackedVector4Array` | Register a Vector4 stream with an explicit type; inference picks Quaternion. |
| Transform | typed `Array[Transform3D]` | Built with `make_transform_attribute`, split with `break_transform_attribute`, combined with `transform_op`. |
| Int64, Double | `PackedInt64Array`, `PackedFloat64Array` | For ids and large or precise values. Canonical attributes keep their types (`density` stays Float). |

`registerStream` refuses a container that does not match the declared type when either side is one of the extended types (Vector2, Vector4, Transform, Int64, Double). The older nodes `math_op`, `sort`, `reduce`, `attribute_filter_range`, `attribute_noise` and a few others reject the extended types with an "unsupported type" error: cast first with `attribute_cast`, or use `vector_op` / `trig_op`.

#### Selector aliases

Every place that asks for a stream name accepts these UE-style aliases, case-insensitive, with components (`$Position.X`, `$Scale.y`). They only add names: a stream literally named `$Something` still wins, and every older selector resolves as before. The `expression` node maps them too.

| Alias | Stream | Notes |
|---|---|---|
| `$Position` | `position` | |
| `$Rotation` | `rotation` | Euler degrees |
| `$Scale` | `size` | UE's Scale is this addon's `size` |
| `$Density` | `density` | |
| `$Seed` | `seed` | |
| `$BoundsMin` / `$BoundsMax` | `bounds_min` / `bounds_max` | |
| `$Steepness` | `steepness` | |
| `$Color` | `color` | the conventional colour stream name |
| `$Index` | `index` | virtual per-point index |
| `@Source` | the node's input attribute | the default output of the round-2 attribute nodes: writes back to (and for a cast, retypes) the input attribute |

#### Attribute Cast loss rules

| From → to | Rule |
|---|---|
| Float / Double → Int / Int64 | `float_to_int`: Truncate toward zero (default, as UE), Round (halves away from zero), Floor, Ceil. NaN becomes 0; values beyond the 64-bit range clamp. |
| Int64 (or a converted real) → Int | `int_overflow`: Wrap keeps the low 32 bits (default) or Clamp. |
| Double → Float, Int / Int64 → Float | Rounded to 32-bit precision. |
| any number → Bool | `value != 0`; Bool → a number is 0/1. |
| number → Vector2 / Vector / Vector4 / Color | Broadcast to every component (Color alpha 1). Number → Quaternion or Transform is refused. |
| vector → wider vector | Pads with 0 (a Color's alpha with 1). Narrower: drops trailing components. |
| vector → number | Refused by default (as UE); `vector_to_scalar` = First Component or Length allows it. |
| Vector ↔ Quaternion | Euler degrees conversion (the point rotation model). Vector4 or Color ↔ Quaternion reinterprets the components. |
| Vector / Quaternion → Transform; Transform → Vector / Quaternion | Translation-only or rotation-only transform; translation or rotation. |
| anything → String; String → number, vector or Transform | `str()`; parsed (`"x,y,z"` or a Godot literal such as `Vector3(1, 2, 3)`), and an unparsable string fails the node. |
| Resource / NodeMesh / NodePath | Only to String, or between the three object types. |

---

## Overrides and bindings

UE lets a node setting come from somewhere other than its details panel: an **override pin** ("Override by pin"), a **graph parameter** read with `Get Graph Parameter` or bound to the setting, or a per-component **graph parameter override** on the `UPCGComponent`. Here the same needs are covered by three mechanisms, applied in this order (highest wins):

| Priority | Here | UE equivalent | Where it is set |
|---|---|---|---|
| 1 | **Wired parameter port** | Override pin | Show a node's parameter ports (the expand toggle on the node) and wire a one-element `Data` into one. Read at execute time by `getSettingValue`, so it beats everything below. |
| 2 | **Per-instance override** | Graph parameter overrides on the component | `FlowGraphNode3D.overrides`, or `EvaluationContext.overrides` when you call `FlowNodeIO.evaluate_graph` yourself. |
| 3 | **`$param` binding** | Setting bound to a graph parameter | `bindings` in a node's **Common Settings**. |
| 4 | The value saved in the graph | The details-panel value | The node inspector. |

**Overrides** are a Dictionary keyed `"<node_name>/<property>"` (or `"<node_name>/<dict_property>/<key>"`, see *Dictionary entries* below):

```gdscript
$Forest.overrides = {
    "scatter/num_points": 200,                     # every graph in this evaluation
    "style_room_default:roomflt/min_value": 2.0,   # only inside style_room_default.tres
}
$Forest.execute()
```

An unprefixed key applies to a node of that name in the top graph *and* in every subgraph/loop graph it runs. Prefix the key with a graph file's basename (`"<basename>:"`) to target that subgraph only. The graph resource itself is never modified, so one graph can back many differently-tuned instances. A key that matches no node setting logs one warning per evaluation.

**Bindings** map a setting to a parameter by name, `"property_name" -> "param_name"` (the leading `$` is optional):

```gdscript
# in the node's Common Settings > bindings
{ "min_value": "$room_min", "random_seed": "$room_seed" }
```

The parameter is looked up in the graph's **inputs** first (the `args` of the `FlowGraphNode3D`, or what a `subgraph`/`loop` node feeds in), then in the **runtime params**, then in **flow variables** (`set_variable`). A `Data` value contributes its first element (stream named after the parameter, a `@data.<name>` attribute, or its only stream). Ints and floats convert into each other; a value of an incompatible type is ignored with a warning. When the parameter is absent the saved value is used silently, so a bound graph still runs in the editor and without arguments. Bindings are applied in the editor too, on a scratch copy of the settings: the Data Inspector shows the bound result while the inspector keeps showing (and saving) the authored value.

**Dictionary entries.** A setting name may also address one entry of a Dictionary-typed setting as `"<dict_property>/<key>"`. The main use is an **Expression** node, whose parameters live in its `args` Dictionary:

```gdscript
# Expression node, Common Settings > bindings
{ "args/theme": "$theme" }
# or, on an Expression node only, the bare args key (it must already exist in args)
{ "theme": "$theme" }

# per-instance override of the same entry: "<node_name>/<dict_property>/<key>"
$Forest.overrides = { "wall_expr/args/theme": 2 }
```

The value is coerced to the type of the entry it replaces (int and float convert into each other; an incompatible value is ignored with a warning), and the Dictionary is replaced by an updated copy, so the authored one is never changed. A bare name that is neither a setting nor (on an Expression node) an existing `args` key still logs the "binds unknown setting" warning, and a `"<property>/<key>"` whose property is not a Dictionary is unknown too.

Compared with UE: overrides and bindings are resolved once per node per evaluation, not per point; for a per-point value keep using an attribute selector (`@last`, `density`, ...) or wire a stream into the parameter port.

---

## Translated Tutorials

Three canonical UE recipes, translated node-for-node. All three assume the demo project is open and you have a `FlowGraphNode3D` selected with the Data Flow panel showing.

### Tutorial 1 — Forest quick-start

> **UE original** (Epic's PCG quick-start): `Get Landscape Data → Surface Sampler → Transform Points → Static Mesh Spawner` — scatter trees with random yaw and scale.

**Here:** `scan_meshes → surface_sampler → transform_points → spawn_meshes`

1. **Scene setup.** You need ground: any `MeshInstance3D` (a large `PlaneMesh` works). Add it to a node group named `terrain` (Node panel → Groups) — groups are this engine's actor tags.
2. **`scan_meshes`** — right-click the canvas, type "Get Landscape Data" (the alias finds Scan Meshes). Set:
   - `group_name` = `terrain` (leave empty to scan all meshes under the scene root)
3. **`surface_sampler`** — drag a wire off `scan_meshes` into empty space and type "Surface Sampler". Set:
   - `num_points` = `400` — note this is a **count**, not UE's points-per-square-meter; scale it with your terrain size
   - `point_size` = `(1, 1, 1)`
   - Press **D** on the node: you should see a field of cubes. The sampler also initialized `density` (all 1.0) and a per-point `seed` — press **A** and check the columns.
   - *Terrain not flat?* Insert a **`projection`** node ("Projection") after the sampler to drop points onto the actual surface along `-Y`; enable its rotation-from-normal option if you want trees to tilt with the slope (it also writes the `normal` stream — useful for Tutorial 2).
4. **`transform_points`** — type "Transform Points". UE's quick-start uses absolute Z rotation 0–360 and scale 0.5–1.2:
   - `rotation_min` = `(0, 0, 0)`, `rotation_max` = `(0, 360, 0)` — **yaw is Y here** (Godot is Y-up; UE's Z-yaw becomes Y-yaw)
   - `scale_min` = `(0.5, 0.5, 0.5)`, `scale_max` = `(1.2, 1.2, 1.2)`, `uniform_scale` = on
   - Randomness is per-point-seeded: re-running the graph, or adding more points, keeps each existing tree's rotation/scale stable — same guarantee UE gives you.
5. **`spawn_meshes`** — type "Static Mesh Spawner". Set:
   - `mesh` = your tree mesh — or fill `mesh_variants` + `mesh_variant_weights` (e.g. two trees + a rock at weights 1.0 / 1.0 / 0.3) and enable `randomize_mesh_variants`: that's UE's weighted mesh-entry list
   - Output is one `MultiMeshInstance3D` per unique mesh (≈ ISM components).

The graph re-evaluates as you tweak; there is no Generate button to press.

**UE-exact variant (surface data).** `get_surface_data → surface_sampler → transform_points → spawn_meshes`. Type "Get Landscape Data" (the popup lists Scan Meshes and Get Surface Data for it) and pick `get_surface_data`; set its `group_name` = `terrain` (a `CollisionShape3D` holding a `HeightMapShape3D` in that group works too). On surface data, `surface_sampler` reads `points_per_square_meter` (UE's default 0.1) instead of `num_points`, places the points on the surface itself (no `projection` step) and writes `normal`. To keep trees off a road, add `get_spline_data` (group of your road `Path3D`) and wire it as input B of a `difference` node between the sampler and the spawner: with the default Binary `density_function`, points inside the road tube (`tube_half_width`) are removed. For a soft edge, lower `tube_steepness`, set `density_function = Subtract` and add a `density_filter` before the spawner (spawners place every point, whatever its density). You can also subtract the spline from the surface *before* sampling: wire `get_surface_data` as A and `get_spline_data` as B of the `difference`, then sample its output.

### Tutorial 2 — Density-noise clumping (slope-aware)

> **UE original** (the standard "natural clusters" chain): `Surface Sampler → Normal To Density → Attribute Noise (a.k.a. Density Noise) → Density Filter → Transform Points → Static Mesh Spawner`.

**Here:** identical shape — `surface_sampler → normal_to_density → attribute_noise → density_filter → transform_points → spawn_meshes`

1. Start from Tutorial 1's `scan_meshes → surface_sampler` (with `projection` in between if your ground is uneven — projection writes the `normal` stream that step 2 wants).
2. **`normal_to_density`** — type "Normal To Density". Set:
   - `normal_to_compare` = `(0, 1, 0)` (up), `offset` = `0.0`, `strength` = `1.0`, `density_mode` = `Set`
   - density becomes `clamp(dot(normal, up) + offset, 0, 1) ^ strength` — flat ground ≈ 1, steep slopes → 0. If there is no `normal` stream it derives one from each point's rotation.
3. **`attribute_noise`** — type "Density Noise" or "Attribute Noise" (both aliases hit it). Set:
   - `target_attribute` = `density`, `mode` = `Multiply`, `noise_min` = `0.0`, `noise_max` = `1.0`, `clamp_result` = on
   - This is per-point-seeded random noise, multiplying the slope mask. For *spatially coherent* clumps (UE's "CellSize ~5000" trick), use the **`noise`** node instead ("Spatial Noise"): `out_name` = `density`, `mode` = `Add` or `Override`, `in_scale` ≈ `0.02`, noise_type Perlin — bigger features = smaller `in_scale`.
   - Press **D** here: the debug cubes tint grayscale by density (0 = black, 1 = white), the same read UE gives you.
4. **`density_filter`** — type "Density Filter". Set:
   - `lower_bound` = `0.5`, `upper_bound` = `1.0`
   - **In Filter** carries the survivors; **Outside Filter** carries the rejects (wire it to a second spawner for "grass where trees aren't"-style layering).
5. Finish with `transform_points → spawn_meshes` exactly as in Tutorial 1.

For the **two-layer biome** variant: run the rock chain through `bounds_modifier` (inflate `size`) → `self_pruning` ("Self Pruning") before spawning, then feed the rock points into a `difference` node ("Difference") as input B with the grass points as input A — grass is removed where rocks stand, UE-style.

### Tutorial 3 — Spline fence

> **UE original** (Procedural Minds): `Get Spline Data → Spline Sampler (Mode=Distance, spacing = mesh length) → Transform Points → Static Mesh Spawner`.

**Here:** `scan_splines → sample_spline → transform_points → spawn_meshes`

1. **Scene setup.** Add a `Path3D` and draw your fence line with the curve editor. Put it in a node group named `fence`.
2. **`scan_splines`** — type "Get Spline Data". Set:
   - `group_name` = `fence`
   - Output is a `node` stream of `Path3D`s (plus their `Curve3D`s as a `curve` stream) — the spline travels down the wire as data, like UE spline data.
3. **`sample_spline`** — type "Spline Sampler". Set:
   - `sampling_mode` = `Uniform`, `uniform_interval` = your fence segment length (e.g. `2.0`) — this is UE's Distance mode with spacing = mesh length
   - `adjust_to_borders` = on, so the run starts/ends exactly at the spline ends
   - **The fence trick:** enable `sample_segments_centers` — you get one point *between* each pair of samples, rotated to look down the segment. Spawn your rail/wall mesh on those; spawn posts on the regular samples from a second `sample_spline` without it. Two branches, two spawners, one spline.
   - Each sample carries a `distance` attribute (distance along/to the spline) for any falloff you want later.
4. **`transform_points`** — small `offset_min`/`offset_max` jitter or yaw variation if you want a worn look; set `rotation_local_space` = on so jitter composes with the spline orientation. Or skip it for a clean fence.
5. **`spawn_meshes`** — fence mesh in `mesh`; segment meshes stretch best when your mesh is authored to exactly `uniform_interval` length.

`get_spline_data` (the search finds it under "Get Spline Data" too) collects the same `Path3D`s as spline data instead of a `node` stream; `sample_spline` gives identical output for either.

**Spline exclusion (the road-through-forest follow-up):** sample the road spline, inflate the samples with `bounds_modifier`, and wire them as input B of a `difference` node spliced before the forest spawner — identical topology to the UE recipe. Or wire the road's `get_spline_data` straight into input B: the spline acts as a tube of `tube_half_width`, no sampling needed. **Interior scatter** ("garden inside a closed spline"): `sample_spline` with `fill_curve` = on fills the closed polygon (grid, random, or Poisson) — no separate Interior mode node needed.

---

## Runtime: the PCG Component API

| Unreal (`UPCGComponent`) | Here (`FlowGraphNode3D`) |
|---|---|
| `Generate()` | `generate(inputs := {}, extra_params := {}) -> Dictionary` — synchronous, returns the graph outputs (`name -> FlowData.Data`). `generate_async()` is the time-sliced variant. |
| `Cleanup()` | `cleanup()` — frees only the nodes this component spawned (spawned roots carry `flow_owner = {component, node}` meta), so two components sharing a spawn parent never delete each other's output. |
| `Regenerate` / Force Regenerate | `regenerate()` = `cleanup()` + `generate()`. |
| `Seed` | `seed` — 0 keeps each node's own `random_seed` (legacy, bit-identical); any other value derives every node's seed as `FlowNodeBase.derive_seed(seed, random_seed)`, so the same graph gives different, reproducible results per component. Subgraphs inherit the seed; a loop iteration gets `derive_seed(seed, key_seed(iteration_key))`, the same value as before for point and chunk indices, and stable per partition value. |
| `OnGraphGenerated` delegate | `generated(outputs)` signal, plus `last_outputs`. `cleaned_up` fires after `cleanup()`. |
| Graph parameter overrides | `args` (graph input values), `params` (runtime parameters), `overrides` (`"node_name/property" -> value`). |
| Generation Trigger | `generate_on_ready` (on load) or call `generate()` yourself. |
| Generated components are transient | `transient_output = true` — spawned nodes get no owner, so they are never saved into the `.tscn`. |
| Time-sliced generation | `async_generation = true` with `frame_budget_ms` (or call `generate_async()`), node by node across frames. |
| Graph cache (`FPCGGraphCache`) | `output_cache = true` (off by default); `FlowOutputCache.clear()`, `hits`, `misses`. See [Caching and threading](#caching-and-threading). |
| Multithreaded execution | `threaded = true` (off by default); main-thread nodes keep their order, output is identical. |
| Errors of the last run | `last_errors` (`[{node, template, message}, ...]`), also `FlowNodeIO.last_errors` after `FlowNodeIO.evaluate`. |

For a partitioned component use `FlowWorld3D` (see [Hierarchical and runtime generation](#hierarchical-and-runtime-generation)):

| Unreal | Here (`FlowWorld3D`) |
|---|---|
| Generation Trigger: Generate At Runtime, runtime generation scheduler | `generation_mode = Runtime`: cells within each grid level's `generation_radius` of a generation source are queued (coarse levels first, then nearest) and generated time-sliced within `frame_budget_ms` and `max_concurrent_cells`; cells beyond radius × `cleanup_radius_multiplier` (1.1) are cleaned up and their components pooled (`cell_pool_size`). |
| Generation Trigger: Generate On Load | `generation_mode = OnLoad` queues every cell, generated over the following frames. |
| Generate / Cleanup on a partitioned component | `generate_all()`, `generate_bounds(aabb)`, `generate_cell(level, coord)`, `cleanup_cell(level, coord)`, `cleanup_all()`, all synchronous; `is_busy()`. |
| `UPCGGenerationSource` (players, cameras) | Any `Node3D` in the group `flow_generation_source`, a `FlowGenerationSource` node (`enabled`, `radius_scale`), or `FlowWorld3D.sources`. There is no editor-viewport source. |
| Generation radii per grid (`FPCGRuntimeGenerationRadii`) | `generation_radius` (grid size → radius, 0 = Unbounded) and `cleanup_radius_multiplier`. |
| `OnPCGGraphGenerated` per partition / cleanup | `cell_generated(level, coord)`, `cell_cleaned_up(level, coord)`, `all_generated`; queries `get_cell_outputs`, `get_cell_errors`, `get_cell_component`, `get_cell_state`. |

Without a component (UE's "execute a graph from code"), evaluate a graph resource directly:

```gdscript
var outputs := FlowNodeIO.evaluate(graph, { "width": 12 }, 1234, { "difficulty": 2 })
var count = outputs["rooms"].first("count")        # element 0 of a stream, or an @data attribute
var tiles = outputs["rooms"].container("tile")     # the packed array, or null
```

`evaluate(graph, inputs, seed, params, owner := null, overrides := {})` needs no node in the scene; spawners, scene scanners and `apply_on_actor` then report "needs an owner node" and pass their input through. Pass any `Node3D` as `owner` to let them spawn under it. `FlowData.Data.scalar(name, value)` wraps a single value for an input, and `output` nodes carry tags, `@data` attributes and `kind` across graph boundaries.

---

## When something doesn't translate

Check [PARITY_ROADMAP.md](PARITY_ROADMAP.md#remaining-gaps). The main things UE has that this addon does not yet: GPU execution beyond the `compute_kernel` escape hatch, partition cells saved and streamed as level data (World Partition), an editor-viewport generation source, grid sizes overridable at run time and markers that take effect inside subgraphs, a Proxy node, and verification of the Terrain3D and HTerrain adapters beyond one Windows run (other plugin versions and platforms). Each entry there explains the gap and, where there is one, the planned design.
