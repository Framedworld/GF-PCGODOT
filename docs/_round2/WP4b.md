# WP4b: point and geometry node coverage

Package notes for the coordinator: what WP4b added, and the rows to merge into the shared docs. Every change is a new node. No existing node, test, or golden or seed-zero baseline changed.

## Summary

Thirteen new node templates, each with a settings class and a GdUnit4 suite:

| Template | Unreal node | Kind |
|---|---|---|
| `apply_scale_to_bounds` | Apply Scale To Bounds | required |
| `split_points` | Split Points | required |
| `find_convex_hull_2d` | Find Convex Hull 2D | required |
| `discard_points_on_irregular_surface` | Discard Points On Irregular Surface | required |
| `create_points` | Create Points | required |
| `filter_data_by_index` | Filter Data By Index | required |
| `get_attribute_from_point_index` | Get Attribute From Point Index | required |
| `get_property_from_object_path` | Get Property From Object Path | required |
| `runtime_quality_branch` | Runtime Quality Branch | required |
| `runtime_quality_select` | Runtime Quality Select | required |
| `weighted_point_sampler` | (none; weighted pick of N points) | required |
| `reset_point_center` | Reset Point Center | extra (cheap, testable, not in the dictionary) |
| `bounds_from_mesh` | Bounds From Mesh | extra (cheap, testable, not in the dictionary) |

Point Match And Set is already listed as 1:1 (`match_and_set`), so it was not redone.

### Conventions every new node follows

- `extends FlowNodeBase` (`get_property_from_object_path` extends `scan_nodes.gd` to reuse its property-path reader). The nodes use only the existing helper API: `require_input`, `getSettingValue`, `set_output`, `setError`, `effective_seed`, `FlowData.resolve_seed`/`point_seed`, `getEffectiveBounds` and `reportMissingOwner`. `filter_data_by_index` also reads `num_generated_bulks`/`num_connected_bulks`, as `density_filter` and `merge` already do.
- `meta_node` declares the title, a tooltip, aliases (the exact Unreal name plus synonyms), the category and the ins/outs. It also declares the WP1 trait overrides: `"pure": true, "main_thread": false` on the pure point operations, `"pure": false` on the quality nodes, and `"main_thread": true, "pure": false, "scans_scene": true` on `get_property_from_object_path`. `create_points` and `filter_data_by_index` declare no traits and keep the safe defaults: `create_points` can read the owner transform, and `filter_data_by_index` depends on bulk position.
- Every settings export has a `##` doc comment. Attribute-name settings are registered through `_get_attribute_selector_props`.
- Errors: a missing input reports "Input 'In' not connected" (an owner-less editor preview stays silent). Missing required streams and attributes are named in the error.
- Determinism: every random draw derives from `FlowData.resolve_seed` (the point's seed stream, else its position) mixed with `effective_seed()`. Orderings that the output depends on (hull order, neighbourhood sums, with-replacement draws) use a canonical position/seed order, so results do not change when the input points are reordered.

### Bounds and scale model used here

These nodes follow the addon's existing model (`Data.getEffectiveBounds`, `BoundsOverlapUtil.world_aabbs`):

- With explicit `bounds_min`/`bounds_max` streams, those streams are the point's local bounds and `size` is a pure scale.
- Without them, `size` is both the scale and the extent: the implicit unscaled bounds are (-0.5, 0.5), and the world box is the position ± size/2.
- World boxes are axis-aligned around the position. Nodes that move a pivot (`split_points` Recenter, `reset_point_center`) apply the offset in the point's rotated frame, without scale. That matches how explicit bounds are read everywhere else.

### Per-node behaviour

- **apply_scale_to_bounds**: `bounds = bounds * size`, taken per axis. A negative scale swaps min and max. `size` is reset to (1, 1, 1); `reset_scale` turns that off. Points with no bounds streams get bounds ±size/2, so their world box does not change. A missing `size` counts as scale 1.
- **split_points**: cuts the effective bounds along `split_axis` (X, Y or Z; default Y, which is Godot's up and Unreal's Z) at `split_position`, or per point from `split_position_attribute`. It has two outputs, "Before Split" and "After Split".
  - KeepTransform (the default) matches Unreal: transforms stay as they are and only the bounds streams change.
  - Recenter moves each half to the centre of its box. Points with explicit bounds get symmetric bounds. Points with no bounds streams keep that model: `size` on the split axis is multiplied by the half's fraction.
  - Optional `side_attribute` (0 or 1) and `fraction_attribute`. When `inherit_attributes` is off, only the point properties are kept.
- **find_convex_hull_2d**: builds one hull per input Data with Andrew's monotone chain, using X/Z. The output is the hull points with all their attributes, ordered counter-clockwise in X/Z (positive shoelace area on (x, z)), starting at the smallest x and then the smallest z.
  - `order_attribute` (default `hull_index`) gives the order for a closed spline. `repeat_first_point` closes the loop explicitly. `include_collinear` keeps edge points.
  - Points that share an X/Z position collapse to the one with the lowest y. Fewer than three distinct X/Z positions give a degenerate hull: the distinct points.
- **discard_points_on_irregular_surface**: a point's neighbourhood is every input point inside its X/Z bounds footprint. The footprint is scaled by `footprint_scale` and has a minimum width of `min_footprint_extent`.
  - Height metric: StdDev (the default, as asked), PlaneResidual (a smooth slope passes) or MaxDeviation, compared with `max_height_deviation`.
  - Normal test: the largest angle between the point's normal and a neighbour's, compared with `max_normal_angle`. Normals come from the `normal` attribute, else the up vector of `rotation_quat`/`rotation`, else +Y.
  - Points with fewer than `min_neighbors` neighbours are kept unless `keep_isolated` is off. Optional metric attributes. Outputs: Kept, Discarded.
  - Neighbour queries use the native `GDRTree` when it is loaded (Auto mode: 64 or more points), else a pure-GDScript uniform grid. `GDKdTree` only answers nearest-neighbour queries, so it cannot serve the footprint query. A test checks that both backends give identical output.
- **create_points**: an explicit list of `FlowPointEntry` resources. Each entry has position, rotation (Euler degrees), scale, bounds_min/bounds_max, density, steepness, seed and an `attributes` dictionary.
  - Seed 0 is derived from the final world position and the node seed. Any other value is written unchanged.
  - Attributes: the union of all names. A missing value gets the type's default. Int and Float values of one name merge into Float. Other type conflicts, and canonical names, are errors.
  - World or Local coordinate space; Local uses the owner's transform and falls back to world space when there is no owner. `write_bounds` turns the bounds and steepness streams off.
- **filter_data_by_index**: DataEntries mode (the default, Unreal's behaviour) routes each whole bulk by its index on the input pin to "In Filter" or "Outside Filter"; the other pin gets an empty Data, as in `filter_data_by_tag`. Points mode splits each Data's points instead.
  - Syntax: `0, 2:5, -1, :3, -2:`. Ranges exclude their end, and negative values count from the end. Indices out of range are ignored; malformed tokens are an error. `invert` swaps the outputs.
- **get_attribute_from_point_index**: reads `input_attribute` (any selector: `@last`, `position.y`, `Yaw`, `@data.x`) at `index`; a negative index counts from the end. There are three outputs: a one-row attribute set (Kind AttrSet), the single point, and the input with the value stored as `@data.<output_attribute>`. The default output name comes from the input name (`position.y` becomes `position_y`). An index out of range, a missing attribute, or a canonical output name of the wrong type is an error.
- **get_property_from_object_path**: `object_paths` are node paths (relative to the owner, then the owner's scene root; `%Unique` and `/root/...` work) or resource paths (`res://`, `uid://`, `user://`). `property_paths` use Scan Nodes' `import_properties` syntax and typing.
  - The output is an attribute set with one row per resolved object, plus an `object_path` column.
  - An unresolved object is an error and its row is skipped. A property that no object has is an error. A node path with no owner reports the documented owner error; resource paths still load.
  - Scene fingerprint: the resolved nodes and the property values.
- **runtime_quality_branch / runtime_quality_select**: quality levels are Low 0, Medium 1, High 2, Epic 3, Cinematic 4.
  - The level comes from `quality_override` (-1 means off), then `ctx.runtime_params["quality"]` (an int, a float, a numeric string, a level name, or a one-value Data), then the project setting `flow_nodes/quality_level`, then 0.
  - Branch has the outputs Default, Low, Medium, High, Epic and Cinematic. The data goes to the current level's pin when that pin's `use_*_pin` is on, otherwise to Default. The other pins get the schema with zero rows.
  - Select has the same six inputs and forwards one of them. An enabled pin with nothing connected gives an empty output.
- **weighted_point_sampler**: picks `count` points, with probability proportional to `weight_attribute` (uniform when the attribute is empty or every weight is 0; weight 0 is never picked).
  - Without replacement it uses Efraimidis-Spirakis keys drawn from the per-point resolved seed. With replacement, cumulative weights in canonical order are walked by an RNG seeded with `effective_seed()`.
  - Copies picked more than once get mutated seeds (on by default). Optional `sample_index_attribute`. The "Not Selected" output holds the complement, in input order.
- **reset_point_center** (extra): moves the pivot to a normalized location in the bounds (0.5 is the centre) and shifts the bounds the other way. The box stays in place, and explicit bounds are always written.
- **bounds_from_mesh** (extra): sets bounds_min/bounds_max from a mesh's local AABB. The mesh is the settings `mesh`, or a per-point Mesh resource attribute that falls back to `mesh`. Points with no mesh keep their bounds.

### New project setting

| Setting | Type | Default | Registered by | Meaning |
|---|---|---|---|---|
| `flow_nodes/quality_level` | int, enum hint `Low,Medium,High,Epic,Cinematic` | 0 (Low) | `runtime_quality_branch.gd` `ensure_project_setting()`, called the first time either quality node is instantiated (same pattern as `FlowNodeRegistry.ensure_project_setting`; the default is not written to project.godot) | Quality level the Runtime Quality nodes use when the evaluation has no `quality` runtime parameter. |

### Requests for other packages (not done here: those files are owned by WP1)

- `node.gd` `SCENE_DEPENDENT_TEMPLATES`: add `get_property_from_object_path`, so nested subgraphs and loops that contain it re-run after a scene edit. At the top level the node already reports a scene fingerprint through `scans_scene` plus its own `computeSceneFingerprint`.
- `FlowNodeTraits` central table: honour the `pure`/`main_thread` meta flags listed above. `create_points` is main-thread in Local space (it reads the owner transform). `filter_data_by_index` in DataEntries mode depends on the bulk's position on the pin, so its cache key must include the bulk index; keep it non-cacheable unless the cache keys per element run.
- Plugin startup could call `RuntimeQualityBranch.ensure_project_setting()` (preload `nodes/runtime_quality_branch.gd`), so the setting appears before any quality node is used.

## Dictionary rows (`docs/COMING_FROM_UNREAL_PCG.md`)

Rows that replace existing rows. Each sits under the section given in the comment.

```
<!-- Input / Output & Get Data: replaces the "Get Property From Object Path | — | roadmap" row -->
| Get Property From Object Path | `get_property_from_object_path` | partial | Object paths come from the settings (node paths relative to the owner or its scene root, `%Unique`, `/root/...`, or `res://`/`uid://` resources), not from an input attribute. Properties use the `scan_nodes` `import_properties` syntax (`mesh:size`) and typing; one attribute-set row per object, with an `object_path` column. No struct or object-reference extraction. |
<!-- Spatial: replaces "Create Points | `grid` (or ...) | partial" -->
| Create Points | `create_points` | 1:1 | Hand-authored list of `FlowPointEntry` points: transform, bounds, density, steepness, seed (0 = derived from position) and extra attributes; World or Local (owner-relative) space. A 1×1×1 `grid` still works for a single generated point. |
<!-- Spatial: replaces "Find Convex Hull 2D | — | roadmap" -->
| Find Convex Hull 2D | `find_convex_hull_2d` | 1:1 | Hull of each input on the X/Z plane (Godot is Y-up). Hull points keep every attribute, in counter-clockwise X/Z order from the smallest x; `hull_index` order attribute for closed splines, optional collinear points and explicit loop closing. |
<!-- Point Ops: replaces "Apply Scale to Bounds | — | roadmap" -->
| Apply Scale to Bounds | `apply_scale_to_bounds` | 1:1 | Multiplies `bounds_min`/`bounds_max` by the scale (`size`) per axis, keeping asymmetric bounds (negative scale swaps min/max), then resets `size` to 1. Points without bounds streams get ±size/2, so their world box is unchanged. |
<!-- Point Ops: replaces "Split Points | — | roadmap" -->
| Split Points | `split_points` | 1:1 | Before Split / After Split pins; axis X/Y/Z (Unreal's Z is Godot's Y, the default) and 0..1 position, or a per-point position attribute. KeepTransform (Unreal) changes bounds only; Recenter also moves each half to its box center. Optional side and fraction attributes and an attribute-inheritance toggle. |
<!-- Filters: replaces "Filter Data by Index | `sequence_sample` | partial" -->
| Filter Data by Index | `filter_data_by_index` | 1:1 | Routes whole data entries by their index on the pin (In Filter / Outside Filter), or points in Points mode. Syntax `0, 2:5, -1, -2:` (end-exclusive ranges, negative from the end), invert. `sequence_sample` remains for start/count/step strides. |
<!-- Filters: replaces "Discard Points on Irregular Surface | — | roadmap" -->
| Discard Points on Irregular Surface | `discard_points_on_irregular_surface` | partial | The "surface" is the input point cloud: neighbours are the points inside each point's X/Z bounds footprint (scalable), not physics traces. Height std-dev / plane-fit residual / max deviation and max normal angle thresholds; Kept and Discarded pins; optional metric attributes. Native GDRTree neighbour queries with a GDScript fallback (identical results). |
<!-- Attributes / Metadata: replaces "Get Attribute from Point Index | `sequence_sample` + `point_to_attribute_set` | partial" -->
| Get Attribute from Point Index | `get_attribute_from_point_index` | 1:1 | Index (negative from the end) and any selector as input attribute. Outputs a one-row attribute set, the single point, and the input with the value as `@data.<name>`. |
<!-- Control Flow, Subgraph & Loop: replaces "Runtime Quality Branch / Select | — | roadmap" -->
| Runtime Quality Branch / Select | `runtime_quality_branch` / `runtime_quality_select` | 1:1 | Levels Low 0, Medium 1, High 2, Epic 3, Cinematic 4, with Default plus per-level pins enabled by `use_*_pin`. The level comes from the runtime parameter `quality` (int or level name), else the project setting `flow_nodes/quality_level` (default 0), with a per-node `quality_override` for previews. Select runs once per bulk of its Default pin, like `select`. |
```

New rows:

```
<!-- Point Ops -->
| Reset Point Center | `reset_point_center` | 1:1 | Moves the pivot to a normalized location inside the bounds (0.5 = center) and offsets `bounds_min`/`bounds_max` so the box stays in place. |
<!-- Spatial -->
| Bounds From Mesh | `bounds_from_mesh` | 1:1 | Sets `bounds_min`/`bounds_max` from a mesh's local AABB: a settings mesh or a per-point Mesh attribute (falling back to the settings mesh). |
<!-- Filters -->
| — (bonus) | `weighted_point_sampler` | Godot-only | Picks N points with probability proportional to a weight attribute, with or without replacement, per-point seeded (stable under reordering, follows the graph seed). Repeated picks get mutated seeds; Not Selected pin with the rest. Unlike `select_points` (keep ratio), it takes an exact count and can sample with replacement. |
```

## nodes_reference rows (`demo/addons/flow_nodes_editor/doc/nodes_reference.md`)

```
<!-- 📂 Attributes -->
| **Get Attribute From Point Index** | [get_attribute_from_point_index.gd](../nodes/get_attribute_from_point_index.gd) | Reads one point's attribute (negative index counts from the end) into a one-row attribute set, the single point, and a per-data attribute on the input. |
| **Get Property From Object Path** | [get_property_from_object_path.gd](../nodes/get_property_from_object_path.gd) | Reads properties of named scene nodes or resources (Scan Nodes property syntax) into an attribute set, one row per object. |
<!-- 📂 Generators -->
| **Create Points** | [create_points.gd](../nodes/create_points.gd) | Creates an explicit list of points (transform, bounds, density, steepness, seed, extra attributes) in world or owner-local space. |
<!-- 📂 Spatial -->
| **Apply Scale To Bounds** | [apply_scale_to_bounds.gd](../nodes/apply_scale_to_bounds.gd) | Multiplies each point's bounds by its scale and resets the scale to one. |
| **Bounds From Mesh** | [bounds_from_mesh.gd](../nodes/bounds_from_mesh.gd) | Sets point bounds from a mesh's local AABB (settings mesh or per-point Mesh attribute). |
| **Find Convex Hull 2D** | [find_convex_hull_2d.gd](../nodes/find_convex_hull_2d.gd) | Keeps the points on the X/Z convex hull of each input, in counter-clockwise order, with a hull index attribute. |
| **Reset Point Center** | [reset_point_center.gd](../nodes/reset_point_center.gd) | Moves each point's pivot to a normalized location inside its bounds without moving the bounds box. |
| **Split Points** | [split_points.gd](../nodes/split_points.gd) | Splits every point in two along a bounds axis at a ratio (Before Split / After Split), keeping the transform or recentering each half. |
<!-- 📂 Utility -->
| **Discard Points On Irregular Surface** | [discard_points_on_irregular_surface.gd](../nodes/discard_points_on_irregular_surface.gd) | Splits points into Kept and Discarded by the height irregularity and normal spread of the points inside their bounds footprint. |
| **Filter Data By Index** | [filter_data_by_index.gd](../nodes/filter_data_by_index.gd) | Routes whole data entries, or the points of each entry, by index lists and ranges (In Filter / Outside Filter). |
| **Runtime Quality Branch** | [runtime_quality_branch.gd](../nodes/runtime_quality_branch.gd) | Routes the input to the pin of the current quality level (runtime parameter `quality`, else the `flow_nodes/quality_level` project setting) or to Default. |
| **Runtime Quality Select** | [runtime_quality_select.gd](../nodes/runtime_quality_select.gd) | Forwards the input of the current quality level, or the Default input. |
| **Weighted Point Sampler** | [weighted_point_sampler.gd](../nodes/weighted_point_sampler.gd) | Picks N points proportionally to a weight attribute, with or without replacement, per-point seeded. |
```

## node_templates.csv rows

```
"apply_scale_to_bounds","Apply Scale To Bounds"
"bounds_from_mesh","Bounds From Mesh"
"create_points","Create Points"
"discard_points_on_irregular_surface","Discard Points On Irregular Surface"
"filter_data_by_index","Filter Data By Index"
"find_convex_hull_2d","Find Convex Hull 2D"
"get_attribute_from_point_index","Get Attribute From Point Index"
"get_property_from_object_path","Get Property From Object Path"
"reset_point_center","Reset Point Center"
"runtime_quality_branch","Runtime Quality Branch"
"runtime_quality_select","Runtime Quality Select"
"split_points","Split Points"
"weighted_point_sampler","Weighted Point Sampler"
```

## DEPRECATIONS rows

None. No existing output changes; every change is a new template.

## Tests

Run from `demo/`:

- The new suites (12 files, 116 cases, 0 failures, 0 orphans) pass on Godot 4.6 (`godot`) and 4.7.1 (`godot47`):
  `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests/nodes/<template>_test.gd`
- Full suite: `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests` gives 1857 cases (the 1741 baseline plus 116), 0 failures, 2 skipped and 1 orphan. The orphan is the existing one in `surface_sampler_test`, and the run exits 101 as on the baseline. The golden and seed-zero suites pass unchanged.
- Import check: `godot --headless --path . --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"` prints nothing.

## Files

- Nodes and settings (`demo/addons/flow_nodes_editor/nodes/`): `<template>.gd` and `<template>_settings.gd` for each template above. `create_points` also has `create_points_point_settings.gd` (`class_name FlowPointEntry`). The `_settings` suffix keeps the entry resource out of the editor's node scan.
- Tests (`demo/tests/nodes/`): `<template>_test.gd` for each template (`runtime_quality_test.gd` covers both quality nodes), plus the shared harness `support/point_node_harness.gd`. The harness disposes nodes only when they are not `RefCounted`, so the suites keep working after the WP1 element split.
