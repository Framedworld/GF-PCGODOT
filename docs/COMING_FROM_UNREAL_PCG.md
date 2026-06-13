# Coming From Unreal PCG

A translation guide for Unreal Engine PCG users. The goal of this addon is that you can follow a UE PCG tutorial inside Godot with minimal mental translation: the hotkeys match, the search popup understands UE node names, and the core per-point invariants (density, seed) work the way UE taught you.

This guide covers:

1. [5-minute orientation](#5-minute-orientation) — where everything lives
2. [Hotkeys](#hotkeys) — UE keys vs. here
3. [Concept dictionary](#concept-dictionary) — `$Density`, `$Seed`, selectors, attribute sets, tags
4. [The node dictionary](#the-node-dictionary) — every UE PCG node and its equivalent here
5. [Translated tutorials](#translated-tutorials) — three classic UE recipes, node by node

For things that genuinely do not translate yet, see [PARITY_ROADMAP.md](PARITY_ROADMAP.md) — we would rather tell you up front than have you discover it at step 7 of a tutorial.

---

## 5-Minute Orientation

| In Unreal PCG | Here |
|---|---|
| **PCG Component** (on an actor) | **`FlowGraphNode3D`** — a Node3D you add to your scene. It holds a reference to a graph and evaluates it. |
| **PCG Volume** | The `FlowGraphNode3D`'s place in the scene. There is no special volume actor — source nodes (`scan_meshes`, `scan_splines`, `scan_nodes`) read the surrounding scene directly, and generator nodes (`grid`, `grid_fill_bounds`, `make_bounds`) define their own regions. |
| **PCG Graph asset** (`.uasset`) | **`FlowGraphResource`** saved as a `.tres` file (or embedded directly in the scene). Subgraphs are also `.tres` graphs. |
| **Graph editor tab** | The **Data Flow** bottom panel. Select a `FlowGraphNode3D` and the panel appears at the bottom of the Godot editor, with the graph canvas, a sidebar inspector on the right, and the data table below. |
| **Details panel** | The **sidebar inspector** on the right of the Data Flow panel. Select a node and its settings appear there (not in Godot's main Inspector dock). |
| **Generate / Force Regenerate button** | **Automatic**. Editing any setting or wire dirties the affected nodes and re-evaluates them. Press **R** to force re-evaluation of selected nodes. At runtime, the graph runs once on `_ready()` and you can call `$FlowGraphNode3D.execute()` to re-trigger. |
| **Attributes table (Inspect)** | The **Data Inspector** — press **A** on a node. One row per point, one column per attribute, with filtering, and clicking a row highlights that point in the 3D viewport. |
| **Debug cube rendering** | Press **D** on a node — points draw as instanced cubes in the viewport, tinted by density (or another attribute) on a grayscale ramp. |
| **Level actors** | Scene nodes. `MeshInstance3D` ≈ Static Mesh Component, `Path3D` ≈ Spline Component, `PackedScene` ≈ Blueprint/actor template. |
| **ISM/HISM instances** | `MultiMeshInstance3D` (what `spawn_meshes` emits — one per unique mesh). |

**First session:** open the `demo/` project in Godot 4.4+, open any `demos/demo_*.tscn` scene, click the `FlowGraphNode3D`, and the Data Flow panel opens with the graph. Right-click the canvas and type a UE node name — the search popup knows the UE vocabulary ("Static Mesh Spawner", "Surface Sampler", "Transform Points", ...) via aliases.

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
| `$Position` | `position` | Vector3 stream. |
| `$Position.X` | `position.x` | Component selectors work on any Vector/Color stream: `.x/.y/.z/.w` and `.r/.g/.b/.a`, case-insensitive. No swizzles (`$Position.ZYX` has no equivalent). |
| `$Rotation` | `rotation` | Vector3 **Euler degrees** — not a quaternion (see [roadmap](PARITY_ROADMAP.md#quaternion-rotation-model)). Yaw is the **Y** component (Godot is Y-up). Convenience aliases: `Yaw` → `rotation.y`, `Pitch` → `rotation.x`, `Roll` → `rotation.z`. |
| `$Scale` | `size` | Vector3. **Caution:** `size` doubles as the point's bounds — `difference`, `self_pruning`, `bounds_modifier`, and the debug cubes all read it. UE's separate Scale-vs-Bounds distinction is a [roadmap item](PARITY_ROADMAP.md#per-point-boundsminboundsmax--steepness). |
| `$BoundsMin` / `$BoundsMax` | — | No per-point bounds pair; `size` is the extent. `bounds_modifier` collapses min/max settings into an extent written to `size`. Roadmap. |
| `$Steepness` | — | Does not exist. Roadmap. |
| `$Color` | a `Color`-typed stream | Conventionally named `color`; `spawn_meshes` reads it for per-instance vertex colors. |
| `@Last` | `@last` | "The last stream written by the upstream node" — same idea, same place you'd use it (filter inputs default to it). |
| `@Source`, `@LastCreated` | — | Not supported; name your output attribute explicitly. |
| `@Data` / `@Points` / `@Elements` domains (5.6+) | `@data.<name>` (per-data); per-point is default | Per-data attributes now exist: write one with `add_attribute` in PerData mode (or the `@data.<name>` selector), read it back broadcast via `@data.<name>`. `partition` stamps its key as a per-data attribute. `@Points` is the default per-point domain; `@Elements` has no equivalent yet. |
| **Attribute Set** | a `Data` with no point streams | A single-row `Data` is the equivalent of UE's single-entry attribute set. Convert with `point_to_attribute_set` / `attribute_set_to_point`. The `assets` node is the idiomatic way to author a weighted table for `match_and_set`. |
| **Tags** | `Data.tags` | Per-data string tags, exactly like UE: `add_tags` / `delete_tags` / `replace_tags` to mutate, `filter_data_by_tag` to route. |
| **Spatial data types** (Surface, Volume, Spline, Primitive, composite algebra) | Point streams + dedicated nodes | There is no typed spatial lattice. Splines travel as a `node` stream of `Path3D`s (from `scan_splines`), meshes as a `node`/`mesh` stream (from `scan_meshes`), and you sample them explicitly (`sample_spline`, `sample_mesh`, `surface_sampler`). "To Point" / "Make Concrete" are unnecessary — everything already is points. See [roadmap](PARITY_ROADMAP.md#spatial-data-type-lattice). |
| **Multi-data on a pin** | "bulks" | A pin can carry several `Data` objects; the Data Inspector has a selector to page through them, and `loop` iterates them. |
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
| Get Landscape Data | `scan_meshes` (+ `sample_terrain_layers`) | partial | Godot has no landscape actor. Scan your terrain `MeshInstance3D`(s), then sample (see [forest tutorial](#tutorial-1--forest-quick-start)). No height-field semantics. Paint-layer weights now have a generic equivalent: `sample_terrain_layers` reads N user-assigned mask textures (world-XZ or UV) and writes a `layer_<name>` Float stream per layer, then filter with `density_filter`/`attribute_filter_range`. Terrain-plugin splat auto-detection is still roadmap. |
| Get Spline Data | `scan_splines` | 1:1 | Collects `Path3D` nodes (by group or scene scan) as a `node` stream. |
| Get Volume Data | `make_bounds` / `scan_nodes` (size_to_bounds) | partial | No volume actor type; a bounds point + `volume_sampler` covers the sampling use. |
| Get Primitive Data | `scan_meshes` | 1:1 | Meshes with their `mesh` resources as streams. |
| Get Texture Data | `texture_sampler` | partial | Samples a texture *at existing points* (UV or world XZ) instead of producing surface data — reorder your chain: points first, then texture sample, then `density_filter`. |
| Get PCG Component Data | — | roadmap | Use a `subgraph` to share generation logic instead. |
| Get Actor Property | `scan_nodes` (import_properties) | partial | Property paths (incl. sub-resources like `mesh:size`) import as attributes. |
| Get Property From Object Path | — | roadmap | |
| Load Data Table | `load_data_table` | 1:1 | CSV/TSV rows → typed attribute streams. |
| Data Table Row To Attribute Set | `data_table_row_to_attribute_set` | 1:1 | By index or key match. |
| Load PCG Data Asset | `load_pcg_data_asset` | 1:1 | JSON / Resource-backed point data. |
| Load Alembic File | `load_alembic_file` | 1:1 | |
| — (bonus) | `points_from_imported_scene` | Godot-only | Loads a `PackedScene` or `Mesh` resource file and emits one point per `MeshInstance3D` found inside it (uses mesh AABB for position/size). No scene-tree involvement — the scene is instantiated off-screen and freed immediately. Optionally exports the `Mesh` resource, source name, or file path as attributes. |

### Samplers

| UE node | Here | Status | Notes |
|---|---|---|---|
| Surface Sampler | `surface_sampler` | partial | Scatters points across the input's bounds. Uses a point count (`num_points`) rather than UE's points-per-square-meter; no Looseness. Initializes `density` = 1.0 and per-point `seed`. For uneven terrain, follow with `projection` to drape points onto the geometry. |
| Spline Sampler | `sample_spline` | 1:1 | Distance mode (`uniform_interval`), random samples, segment centers (with look-at rotation — the fence trick), and **interior fill** of closed splines (grid / random / Poisson) with a distance-to-border attribute. |
| Mesh Sampler | `sample_mesh` (alias `mesh_sampler`) | 1:1 | Area-weighted random, one-per-vertex, or face centers; rotations from triangle normals; optional hard-edge rejection. |
| Volume Sampler | `volume_sampler` | 1:1 | Regular 3D grid inside each input point's oriented volume. |
| Texture Sampler | `texture_sampler` | 1:1 | Writes a Color attribute and/or scalar channel per point. |
| Copy Points | `copy_points` (alias `copy`) | 1:1 | Source-to-targets transform composition; also a LinearCopies mode ≈ Duplicate Point. |
| Select Points | `select_points` | 1:1 | Seeded random keep-ratio, optional weight attribute. |
| — (bonus) | `sample_points` (aliases: Point Subdivision, Blue Noise) | Godot-only | Subdivides each input point's volume into sub-points using **Uniform Grid**, **Quasi-Random** (golden-ratio 2D or 3D), or **Blue-Noise 2D** distributions. A point's `size` stream drives the sampling volume; output points carry density=1.0 and per-point seeds. Use it to scatter inside bounds without a separate source mesh. |
| — (bonus) | `navigation_region_sampler` | Godot-only | Samples `NavigationRegion3D` navmesh data into points. **Polygons** mode emits one point per navmesh polygon (position = centroid, with `normal` and `area` attributes); **Vertices** mode emits one point per navmesh vertex. Useful for AI spawn / placement that stays on walkable surfaces. |

### Spatial

| UE node | Here | Status | Notes |
|---|---|---|---|
| Difference | `difference` | partial | RTree-accelerated AABB set ops (overlap = position+size boxes). One node covers Difference both ways, Intersection, Union, and Symmetric Difference via its `operation` setting. **Caveat:** hard point removal, no density-attenuation mode, and overlap uses `size` (no per-point bounds/steepness — roadmap). |
| Union | `union` | partial | Point-merge union; no Max/Add density function. |
| Intersection / Inner Intersection | `intersection` | partial | Outer intersection of A against B; no N-way inner variant. |
| Projection | `projection` | 1:1 | Projects points onto physics geometry along a direction; can inherit rotation from the surface normal and writes the `normal` stream. |
| To Point / Make Concrete | — | n/a | Unnecessary — every pin already carries concrete points. |
| Merge Points | `merge` (alias `merge_points`) | 1:1 | Multi-input concatenation with stream-union semantics. |
| Create Points | `grid` (or `add_attribute` + `attribute_set_to_point`) | partial | No hand-authored point-list editor; a 1×1×1 `grid` makes a single point. |
| Create Points Grid | `grid`, `grid_fill_bounds` | 1:1 | `grid_fill_bounds` fills the bounds of upstream points. |
| Create Spline | `create_spline` | 1:1 | Builds a `Path3D` through input points. |
| Create Surface From Spline | `create_surface_from_spline` | partial | Emits a bounds point + area/perimeter attributes, not true surface data; pair with `sample_spline`'s interior-fill mode for "scatter inside a closed spline". |
| Spatial Noise | `noise` | 1:1 | FastNoiseLite: Value/Perlin/Simplex/Cellular + fractal options; writes any attribute (default `density`), Override or Add. |
| Distance | `distance` | 1:1 | KD-tree nearest distance to a second input, optional normalization by `max_distance`. |
| Normal To Density | `normal_to_density` | 1:1 | Slope masking: density from dot(normal, reference direction) with offset/strength and Set/Min/Max/Add/Multiply combine. Reads the `normal` stream, falling back to the rotation's up vector. |
| Mutate Seed | `mutate_seed` | 1:1 | Position-stable per-point seed re-derivation. |
| Point Neighborhood | `point_neighborhood` | 1:1 | Radius-averaged values. |
| Point From Mesh | `point_from_mesh` | 1:1 | One point carrying a mesh's bounds. |
| Get Bounds | `make_bounds` / `combine_points` | partial | `combine_points` collapses a set to one bounds point. |
| Get Points Count | `get_points_count` | 1:1 | |
| Cull Points Outside Actor Bounds | `clip_points_by_polygon` / `intersection` | partial | The HiGen-dedupe use case doesn't apply (no HiGen yet). |
| Find Convex Hull 2D | — | roadmap | |
| Attribute Set To Point | `attribute_set_to_point` | 1:1 | |
| World Ray Hit Query | `ray_cast` (also `physics_shape_sweep`) | 1:1 | Per-point physics raycast with hit position/normal/rotation/collider outputs. |
| World Volumetric Query | `physics_overlap_query` | 1:1 | |
| Spatial Data Bounds To Point | `combine_points` | 1:1 | |
| — (bonus) | `split_splines` | Godot-only | Converts each spline segment between baked samples into a **segment-center point** oriented along the segment (Z-forward). Outputs `start`/`end` world positions, `segment_index`, `spline_index`, and optionally the source `Path3D` reference. Where `sample_spline` gives you uniformly spaced points *along* a spline, `split_splines` gives you one point *per segment* — handy for placing walls between corridor waypoints. |
| — (bonus) | `create_surface_from_polygon` | Godot-only | Creates an AABB bounds point from ordered polygon point streams. Related to `create_surface_from_spline` but takes explicit point data instead of a `Path3D`. Outputs `area` (shoelace formula), `perimeter`, and `point_count` attributes. Supports a `group_attribute` to produce one surface per group. |
| — (bonus) | `grid_boundary` | Godot-only | Given a set of **filled grid cells** (position stream snapped to a cell grid), emits the exposed **edge** and **corner** points — the faces that have no filled neighbor. Each edge point is sized and rotated to span one cell face; corner points sit at exposed vertices. Three output pins: Edges, Corners, All. Perfect for building walls around a dungeon room layout. |
| — (bonus) | `grid_connect_points` | Godot-only | Connects ordered points with **orthogonal grid-cell paths** on the XZ plane (Manhattan / L-shaped corridors). Walk axis order is configurable (X-then-Z or Z-then-X). Outputs one cell point per step; optionally tags each path segment with a `path_index` attribute. Pairs with `grid_boundary` for dungeon corridor + wall generation. |

### Point Ops

| UE node | Here | Status | Notes |
|---|---|---|---|
| Transform Points | `transform_points` (alias `transform`) | 1:1 | Random offset/rotation/scale ranges, local-space rotation toggle, uniform-scale toggle. Per-point seeded when the `seed` stream exists. |
| Bounds Modifier | `bounds_modifier` | partial | Set/Add/Multiply an extent into `size`. Asymmetric min/max collapses to a symmetric extent (no per-point bounds offset — roadmap). |
| Extents Modifier | `bounds_modifier` | partial | Same node, same caveat. |
| Apply Scale to Bounds | — | roadmap | Requires the scale/bounds split. |
| Duplicate Point | `duplicate_point` (also `point_offsets`, `copy` LinearCopies) | 1:1 | N copies along a world or local offset. |
| Split Points | — | roadmap | |
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
| Filter Data By Type | `filter_data_by_type` | partial | Heuristic classification (point / spline / attribute-set) — there is no real type lattice. |
| Filter Data By Attribute | `filter_data_by_attribute` | 1:1 | Routes by attribute presence. |
| Filter Data by Index | `sequence_sample` | partial | |
| Filter Attributes by Name | `remove_attribute` | 1:1 | Keep/remove listed streams. |
| Self Pruning | `self_pruning` | 1:1 | Native RTree bounds-overlap pruning (large-to-small) + a grid-cell dedupe mode. Overlap uses `size` as bounds. |
| Discard Points on Irregular Surface | — | roadmap | Compose `ray_cast` probes + `point_neighborhood` + `density_filter` meanwhile. |
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
| Copy Attribute / Transfer Attribute | — | roadmap | Workarounds: `expression` (one-liner copy), or `match_and_set` from a second input. |
| Attribute Rename | `attribute_rename` | 1:1 | |
| Delete Attributes | `remove_attribute` | 1:1 | |
| Attribute Noise | `attribute_noise` | 1:1 | Per-point seeded randomization of any attribute (also see `attribute_random` for the simple uniform case and `noise` for spatially-coherent noise). |
| — | `attribute_random` | bonus | Fills any attribute with **uniform random values** (float or int, min/max range). Simpler than `attribute_noise` — no noise type, no spatial coherence, just a flat random draw. Uses the point `seed` stream when present for per-point stability. Also supports a `use_index_as_value` mode to write sequential indices (0, 1, 2, …) into any attribute. |
| Attribute Partition | `partition` | 1:1 | One output data per unique value. |
| Attribute Select | `reduce` | partial | Average/Min/Max reductions; no median, no per-axis select. |
| Attribute String Op | `expression` | partial | Any GDScript string expression per point. |
| Match And Set Attributes | `match_and_set` (+ `assets` for the table) | 1:1 | The weighted-pick-from-table workhorse: random-weighted or key-matched row copy. `assets` is the idiomatic table source (≈ spawner mesh entries as data). |
| Point Match and Set | `match_and_set` | 1:1 | |
| Merge Attributes | `merge` | partial | |
| Sort Attributes / Sort Points | `sort` | 1:1 | |
| Break Vector Attribute | `decompose_vector` | 1:1 | Also free via selectors: `position.x` works anywhere a stream name is asked. |
| Make Vector Attribute | `compose_vector` / `make_vector` | 1:1 | |
| Break/Make Transform Attribute | — | roadmap | No Transform-typed attributes (Euler rotation model). |
| Get Attribute from Point Index | `sequence_sample` + `point_to_attribute_set` | partial | |
| Point To Attribute Set | `point_to_attribute_set` | 1:1 | |
| Maths Op | `math_op` | 1:1 | Attribute-or-constant operands, result to named stream. |
| Boolean Op | `boolean` | 1:1 | And/Or/Not/Xor plus extras. |
| Bitwise Op | `expression` | partial | GDScript `&`, `|`, `^`, `~` in an expression. |
| Compare Op | `filter` / `expression` | partial | `filter` routes instead of writing a bool attribute; use `expression` to materialize the bool. |
| Trig / Vector / Rotator / Transform Op | `expression` (+ `compose_vector`/`decompose_vector`, `build_rotation_from_up`) | partial | `expression` evaluates arbitrary GDScript per point with all streams bound by name — it is the escape hatch for the whole op-family zoo. Rotator/Transform composition is limited by the Euler model. |
| Reduce Op | `reduce` | 1:1 | Average/Min/Max across entries. |
| — (bonus) | `size` (node) | Godot-only | Returns the **point count** of the input as a single-entry Int attribute. Useful when you need the count as data to drive downstream expressions or graph inputs rather than as a debug display. (For the display use, `get_points_count` is the right choice.) |

### Spawners

| UE node | Here | Status | Notes |
|---|---|---|---|
| Static Mesh Spawner | `spawn_meshes` | 1:1 | One `MultiMeshInstance3D` per unique mesh; weighted mesh variants (≈ mesh entries), by-attribute mesh selection (`mesh_selector_attribute` ≈ MeshSelectorByAttribute), per-point mesh resources, per-instance colors. |
| Spawn Actor | `spawn_scenes` (scenes) / `spawn_nodes` (raw nodes) | 1:1 | Instantiates a `PackedScene` per point with property assignment from attributes (≈ property overrides). |
| Create Target Actor | `spawn_parent_path` setting on spawners | partial | |
| Point from Player Pawn | `point_from_player_pawn` | 1:1 | |
| Apply On Actor | `apply_on_actor` | 1:1 | Writes attributes/transforms onto existing scene nodes. |

### Control Flow, Subgraph & Loop

| UE node | Here | Status | Notes |
|---|---|---|---|
| Branch | `branch` | 1:1 | Bool routing (static or attribute-driven). |
| Switch | `switch` | 1:1 | |
| Select | `select` | 1:1 | |
| Select (Multi) | `select_multi` | 1:1 | |
| Runtime Quality Branch / Select | — | roadmap | No quality scalability system. |
| Proxy | — | roadmap | |
| Gather | `merge` | partial | Merge is the sync/collect point. |
| Subgraph | `subgraph` | 1:1 | Nested `.tres` graphs, dynamic pins from graph params, per-instance override pins (≈ graph parameter overrides), collapse-selection-to-subgraph. |
| Loop | `loop` | 1:1 | Runs a subgraph per data/entry, with a sequential feedback parameter. |
| Get Loop Index | `get_loop_index` | 1:1 | |
| Set Variable / Get Variable | `set_variable` / `get_variable` | 1:1 | Named in-graph data channels: `set_variable` stores its input under a named key in the evaluation context and passes the data through unchanged; `get_variable` reads the stored data by name. Wire color matches across paired nodes. Use these to share data between distant parts of a complex graph without long cross-canvas wires — exactly like UE PCG's Variable nodes added in 5.4. |

### Hierarchical / GPU

| UE node | Here | Status | Notes |
|---|---|---|---|
| Grid Size (HiGen) | `grid_size` | partial | Declaration node landed — it tags its downstream section with a power-of-two cell size. Per-cell partition *execution* on `FlowGraphNode3D` is still deferred ([roadmap](PARITY_ROADMAP.md#hierarchical-generation-grid-size)). |
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
| Named Reroute Declaration | — | roadmap | |
| Execute Blueprint | `expression` / write a node script | partial | `expression` = per-point GDScript with streams bound by name. Full custom nodes are a single `.gd` file extending `FlowNodeBase` — substantially less ceremony than a `UPCGBlueprintElement`. |

Nodes here with **no UE counterpart** (you get them for free): `relax` (Lloyd relaxation), `snap_to_grid`, `clip_points_by_polygon` / `clip_paths` / `polygon_operation` (spline-polygon clipping), `random_color`, `sequence_sample`, `points_from_gridmap` / `points_from_tilemap` / `points_from_imported_scene` (Godot-native data sources), `navigation_region_sampler` (navmesh → points), `sample_points` (subdivision with blue-noise / quasi-random), `split_splines` (spline-segment-center points), `create_surface_from_polygon` (polygon → AABB point), `grid_boundary` / `grid_connect_points` (grid-cell topology helpers), `set_variable` / `get_variable` (named wire-free data channels), `attribute_random` (simple uniform random attribute), `remap` (curve remap any float attribute), `tags_mutate` (combined add/remove/replace tags), `size` (point count as data), the `dungeon_*` generator family, and `expression`.

**New roadmap-parity nodes** (see [PARITY_ROADMAP.md](PARITY_ROADMAP.md#implementation-status-2026-06)): `rotator_op` (Combine/Invert/Lerp/RotateAroundAxis on Euler or quaternion rotations), `subdivide_segment` (slice splines/segments into sized, oriented sub-segments), `grammar_expand` (UE-style shape-grammar expansion into placeable modules), `sample_terrain_layers` (mask-texture paint layers), `compute_kernel` (GLSL compute-shader escape hatch), and `grid_size` (HiGen cell-size declaration). Density-aware set ops live on `difference`/`self_pruning` via their `density_function` setting, and per-point `bounds_min`/`bounds_max`/`steepness` streams are honored when present.

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

**Spline exclusion (the road-through-forest follow-up):** sample the road spline, inflate the samples with `bounds_modifier`, and wire them as input B of a `difference` node spliced before the forest spawner — identical topology to the UE recipe. **Interior scatter** ("garden inside a closed spline"): `sample_spline` with `fill_curve` = on fills the closed polygon (grid, random, or Poisson) — no separate Interior mode node needed.

---

## When something doesn't translate

Check [PARITY_ROADMAP.md](PARITY_ROADMAP.md). The honest list of things UE has that this addon does not yet: hierarchical generation (Grid Size), async/proximity runtime generation, GPU nodes, per-point BoundsMin/Max + Steepness, quaternion rotations, the typed spatial-data lattice, shape grammar, landscape paint layers, Subdivide Segment, and attribute domains. Each entry there explains the gap and the planned design.
