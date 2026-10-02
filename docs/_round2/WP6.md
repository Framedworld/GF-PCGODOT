# WP6: spatial follow-ups and terrain adapters (round 2 notes for the coordinator)

## Summary

Two pieces of work, both opt-in or new in this branch, so every existing graph
produces the same output (golden and seed-zero suites unchanged, no
regeneration).

1. **Overlap mode for points against spatial data.** `difference`,
   `intersection` and `union` gain `overlap_mode : PointCenter | BoundsBox`
   (default `BoundsBox`). With `BoundsBox` a point is its bounds box, as in
   Unreal's point-versus-volume test: a large point whose centre is outside a
   shape but whose bounds reach into it is now removed (Binary) or attenuated
   (Minimum / Multiply / Subtract), the way point-versus-point `difference`
   already treats overlapping boxes. `PointCenter` reproduces the WP2 output
   exactly (checked against a frozen copy of the WP2 script). Two point inputs
   are not affected by the setting.
2. **Terrain adapters.** A new `terrain/` directory with `FlowTerrainAdapter`
   (base) and adapters for `HeightMapShape3D`, a heightmap `Image` (with
   optional splat images), `MeshInstance3D`, and, by duck typing, the Terrain3D
   and HTerrain plugins. Each adapter answers heights, normals and paint-layer
   weights and builds an immutable surface shape (`to_surface()`) that carries
   the layer weights (`FlowSurfaceLayers`).
   - `get_surface_data` gains `source = Terrain`: an explicit
     `terrain_node_path`, or auto-detection of the single terrain plugin node in
     the scene (or in `group_name`) by its **methods**, not its class name.
     Ambiguity and absence are reported with clear errors.
   - `surface_sampler` writes one weight attribute per paint layer
     (`layer_<name>`) when it samples a terrain surface, as Unreal writes
     landscape layer weights onto sampled points.
   - `sample_terrain_layers` gains `layer_source = TerrainAdapter`: it reads the
     weights from a terrain through its adapter instead of mask textures.

**The Terrain3D and HTerrain adapters were first tested only against fakes; a
later real-plugin run found one bug and then passed.** The build container has
no plugin, so the package shipped with fake classes that implement the methods
listed below. A later run against the real plugins (Terrain3D v1.0.2-stable and HTerrain 1.8.1 (master), unmodified, Godot 4.7.1 on Windows) found that the
HTerrain snapshot called `get_height_at` with two ints where the real
`HTerrainData.get_height_at` takes one `Vector2i`; every snapshot cell raised a
script error and `get_surface_data` returned no surface. That is fixed, and the
fake now has the real signature, so the contract test fails on the old call.
After the fix both adapters sampled correct heights and layer weights in that
run (Terrain3D: 3249 points, no wrong weights; HTerrain: 828 points uncentered
and 3290 centered with a map scale and node offset, no wrong weights), and a
scene holding both plugins reports the ambiguity as designed. Not covered: other
plugin versions, Linux and macOS, and performance on large terrains.

## 1. Overlap mode

### Semantics

For each point the shape is evaluated over the point's **world bounds box**:
`position + bounds_min .. position + bounds_max` when both streams exist,
otherwise `position ± size / 2` (`BoundsOverlapUtil.world_aabbs`, the same box
point-versus-point `difference` uses; rotation is ignored there too).

`FlowSpatial.box_overlap(box_min, box_max) -> Vector2(peak, coverage)`:

- `peak`: the highest shape density over the box (0 means no overlap).
- `coverage`: the mean shape density over the box, at most `peak`.

How it is computed:

| Shape | peak | coverage |
|---|---|---|
| `FlowBoxVolume` with an axis-aligned basis (any scale, axis permutation or mirroring) | **exact**: falloff of the Chebyshev distance of the nearest point of the box (separable per axis) | **exact** for a hard box (steepness 1): the overlapped volume fraction, which is `BoundsOverlapUtil.penetration_ratio`. Soft box: the sample set, capped by the peak. |
| `FlowSphereVolume` with uniform scale (any rotation) | **exact**: falloff at the point of the box nearest to the centre | sample set, capped by the peak (box-sphere volume has no simple closed form) |
| everything else (rotated boxes, ellipsoids, mesh volumes, surfaces, splines, points volumes, composites) | max over the sample set | mean over the sample set |

The **sample set** is fixed and deterministic: the box centre, its 8 corners and
its 6 face centres (`FlowSpatial.box_sample_points`, 15 positions). There is a
cheap XZ broad phase against `get_bounds()`. There is none on Y, because
surfaces are densities over their whole column when `vertical_tolerance <= 0`.

The two values become one overlap density with the point's steepness
(`FlowSpatial.overlap_factor`; the steepness comes from the `steepness` stream,
1 when absent):

```
steepness >= 1 :  s = peak
steepness <  1 :  s = peak * BoundsOverlapUtil.shape_factor(coverage / peak, steepness)
```

Against a hard shape (peak 1 wherever it overlaps) this is exactly the
point-versus-point rule: a hard point counts any overlap as a full hit, and a
softer point is attenuated by the covered fraction. Against a soft shape the
peak scales the result, and for a vanishing point box it tends to the density
at the centre, which is the PointCenter value.

Then the WP2 table applies with `s` in place of the centre density:

- **Binary** uses `peak > 0` (any overlap). Difference drops the point,
  Intersection keeps it, and Union sets the density to 1. Point-versus-point
  Binary also ignores steepness.
- **Minimum / Multiply / Subtract** fold `s` with
  `FlowSpatial.combine_density(op, fn, density, s)`. For a difference this is
  `BoundsOverlapUtil.fold_density`.

**Equivalence test.** For a hard, axis-aligned box volume, `BoundsBox` gives
the same kept points and the same densities (1e-5) as point-versus-point
`difference` against a single point with that box. The test covers every
density function, mixed sizes and steepness, and asymmetric
`bounds_min`/`bounds_max` (`overlap_mode_test.gd`).

**Exactly touching.** Shape densities are inclusive at the boundary, so a box
that only touches a hard box face has `peak = 1`. Point-versus-point overlap is
strict. The two paths differ only in that measure-zero case.

### Setting

| Template | New setting | Default | Notes |
|---|---|---|---|
| `difference`, `intersection`, `union` | `overlap_mode` (`PointCenter`, `BoundsBox`) | `BoundsBox` | Applies only when one input carries a shape and the other carries points. Shape-with-shape composites, shape-minus-points (points become a `FlowPointsVolume`) and point-versus-point are unchanged. |

`difference.points_vs_shape(points, shape, op, fn, overlap_mode = PointCenter)`
keeps its old signature through the default, so a direct caller of the static
helper gets the WP2 result.

## 2. Terrain adapters

### Contract (`terrain/flow_terrain_adapter.gd`)

```gdscript
class_name FlowTerrainAdapter extends RefCounted
func get_bounds() -> AABB
func get_height(x, z) -> float          # beyond the terrain: clamped onto its edge; NaN only over a hole
func get_normal(x, z) -> Vector3        # same clamping; never NaN (finite differences as a fallback)
func get_layer_names() -> PackedStringArray
func get_layer_weight(name, x, z) -> float   # 0..1, 0 for an unknown layer
func to_surface() -> FlowSpatial        # FlowHeightfieldSurface or FlowMeshSurface, with layers attached
func get_sample_spacing() -> float      # snapshot grid spacing
func fingerprint() -> int               # cheap probe, for scene fingerprints
static func for_node(node, options) -> FlowTerrainAdapter     # or null
static func detect(owner, explicit_path, group_name, options) -> { adapter, node, error }
static func is_terrain3d(node) / is_hterrain(node) / is_terrain_plugin_node(node)
```

Adapter options are `vertical_tolerance`, `max_resolution` (snapshot samples
per axis, default 1024), `layer_names` (renames the adapter's own layers in
order), `splat_layers` (extra `FlowTerrainSplatLayer` image layers over the
footprint) and `bounds` (explicit extent).

**Edge handling.**
- Heights: `get_height` clamps `(x, z)` onto the footprint. Heightfield-based
  adapters clamp in the grid's own frame, which can be rotated or scaled
  (`FlowHeightfieldSurface.clamped_hit`).
- Normals at and beyond edges come from one-sided differences over the real
  distance between the clamped neighbours, so a slope is never halved. The
  edge-cell gradient is used for grids.
- The tests cover every adapter beyond each side and at corners.

**Layers.** `FlowSurfaceLayers` (in `spatial/`) is an immutable set of float
weight grids, attached to a surface through `attach_layers()` and read with
`FlowSpatial.get_layers()`.
- Composites expose the surface operand's layers. For a union that is A's
  layers, or B's when A has none.
- The lookup is the **Sample Terrain Layers convention**: uv =
  `(x - min) / (max - min)` (after an optional world-to-layer transform),
  clamped to 0..1, then the nearest-lower texel `floor(uv * (size - 1))`. A test
  compares `FlowSurfaceLayers` and the image adapter with `sample_terrain_layers`
  on 202 random positions inside and outside the rectangle, and the values are
  bit-equal.
- Splat images keep their own resolution.
- Live plugin layers (Terrain3D) are snapshotted on the same lattice as the
  heights.

**Holes.** `FlowHeightfieldSurface` now treats NaN heights as holes. A cell
touching a NaN sample misses in projection and density, and the bounds ignore
NaN. Terrain3D reports NaN over holes and outside its regions.

### Adapters

| Adapter | Source | Heights | Layers | `to_surface()` |
|---|---|---|---|---|
| `FlowHeightMapShapeTerrainAdapter` | `HeightMapShape3D` + transform (`from_collision_shape`) | the grid, as Godot physics lays it out (centred, one unit per cell) | splat images only | the grid itself (same content hash as `FlowHeightfieldSurface.from_heightmap_shape`) |
| `FlowImageTerrainAdapter` | heightmap `Image`, cell, height scale, transform, centred | same as `FlowHeightfieldSurface.from_image` | splat images (`FlowTerrainSplatLayer`: image or texture, channel R / G / B / A / luminance) | the grid itself |
| `FlowMeshTerrainAdapter` | `MeshInstance3D` or meshes + transforms | top-most vertical hit; nearest point of the mesh when the clamped vertical misses | splat images over the mesh bounds | the `FlowMeshSurface` |
| `FlowTerrain3DAdapter` | a Terrain3D-like node (duck typed) | live `data.get_height` | control map (`get_texture_id`) | heightfield snapshot at `vertex_spacing` (capped by `max_resolution`) with layer snapshot |
| `FlowHTerrainAdapter` | an HTerrain-like node (duck typed) | live `get_interpolated_height_at` in cell space | splat maps, four layers per map | heightfield snapshot in cell space, placed by the internal transform, splat images kept as they are |

### Plugin APIs the adapters call (checked against the real plugins on Windows; the fakes follow them)

Every call is guarded with `has_method` or an `in` property check. Neither
adapter names a plugin class, so both load without the plugins and work with
unmodified plugin classes. The fakes in
`demo/tests/terrain/support/fake_terrain_plugins.gd` implement exactly these
members.

**Terrain3D** (TokisanGames; the API as I recall it from **Terrain3D 1.0**,
with the 0.9 `storage` name accepted):

| Member | Use |
|---|---|
| `terrain.data` property (pre-1.0: `terrain.storage`) | the data object. Detection requires that it has `get_height` and `get_normal`. |
| `data.get_height(Vector3) -> float` | world height; NaN over holes and outside regions |
| `data.get_normal(Vector3) -> Vector3` | world normal; a non-finite result falls back to finite differences |
| `data.get_texture_id(Vector3) -> Vector3` | control map: (base id, overlay id, blend 0..1). A texture id weighs `(1 - blend)` as base plus `blend` as overlay. |
| `data.get_region_locations() -> Array[Vector2i]` | bounds. A region is assumed to span `location * region_size * vertex_spacing` up to the next location, starting at the location rather than centred on it. |
| `data.get_height_range() -> Vector2` | Y extent of the bounds |
| `terrain.region_size` property | vertices per region side |
| `terrain.vertex_spacing` property (pre-1.0: `mesh_vertex_spacing`) | XZ spacing (1.0 when absent) |
| `terrain.assets.get_texture_count()`, `assets.get_texture(id)`, `asset.get_name()` | layer names. Without them, the texture ids found on a 32 × 32 probe lattice name the layers `texture_<id>`. |

If the regions cannot be read, set `terrain_bounds` (get_surface_data) or the
`bounds` option. Without either, the adapter reports an error.

**HTerrain** (Zylann's godot_heightmap_plugin; the API as I recall it from
**1.7.x for Godot 4**):

| Member | Use |
|---|---|
| `terrain.get_data() -> HTerrainData` | detection: the returned object must have `get_interpolated_height_at` and `get_resolution`. A node that is Terrain3D-like is never taken as HTerrain, even though Terrain3D's `data` property also has a `get_data` getter. |
| `terrain.get_internal_transform() -> Transform3D` | cell space to world. Fallback when absent: the node transform scaled by the `map_scale` property, shifted by `(resolution - 1) / 2` cells when `centered` is true. **The fallback layout is an assumption.** |
| `data.get_resolution() -> int` | samples per side |
| `data.get_interpolated_height_at(Vector3) -> float` | raw height at a fractional cell position (x, z are cell coordinates); live `get_height` and normals |
| `data.get_height_at(int, int) -> float` | snapshot (falls back to `get_interpolated_height_at`) |
| `data.get_map_count(int) -> int`, `data.get_image(int, int) -> Image` | splat maps (`CHANNEL_SPLAT`, read from the data script's constants, 2 by default). Four layers per map in R, G, B, A, named `texture_<map*4+channel>`. |

The contract named `get_heightmap_aabb()`. **I did not call it**, because I
could not confirm that it exists. The bounds come from the height snapshot
instead (see Deviations).

### Auto-detection

`FlowTerrainAdapter.detect(owner, path, group, options)` works in three cases:

- **With `terrain_node_path`:** that node must be a Terrain3D-like or
  HTerrain-like node, a `CollisionShape3D` with a `HeightMapShape3D`, or a
  `MeshInstance3D`. Otherwise the error says what was expected.
- **Without a path:** it scans the scene root's descendants, or the members of
  `group_name` and their descendants, for plugin terrains recognised by their
  methods. It skips nodes generated by a flow graph (`flow_owner` meta).
  - None found: the error says what the scan looked for and suggests
    `terrain_node_path` or the Scene source.
  - More than one: the error starts with `ambiguous terrain: N terrain nodes
    found (<paths>)` and asks for a path or group.
- **Built-in sources** (`HeightMapShape3D`, meshes) are never auto-detected.
  They stay on the Scene source, or can be named by path.

### Node settings

| Template | New settings (defaults keep today's output) | Behaviour |
|---|---|---|
| `get_surface_data` | `source` gains `Terrain` (appended, = 2). Terrain group: `terrain_node_path`, `terrain_bounds` (empty = auto), `terrain_max_resolution` (1024), `terrain_layer_names`, `terrain_splat_layers` (also shown for HeightmapImage). `group_name` scopes auto-detection. | One Data with the adapter's surface and the `@data` attributes `source` (node path), `terrain_type` (Terrain3D / HTerrain / HeightMapShape3D / Mesh) and `terrain_layers` (comma-separated names). Errors emit an empty Surface Data. HeightmapImage with splat layers goes through `FlowImageTerrainAdapter`; without them the code path is the WP2 one, byte for byte. The scene fingerprint covers the terrain path, transform and a 9 × 9 probe of heights and weights (HTerrain: live heights and splat texels, no snapshot). |
| `surface_sampler` | `write_terrain_layers` (on), `terrain_layer_prefix` (`layer_`) | On a surface with layers, each sample gets one Float stream per layer, read at the sample's XZ. A bounding shape keeps the terrain's layers. Surfaces without layers (every WP2 shape) are untouched. `to_point` gets the same streams through `FlowSpatial.sample_surface` (`write_layers`, `layer_prefix`). |
| `sample_terrain_layers` | `layer_source` (`Textures`, `TerrainAdapter`; default `Textures`), `terrain_node_path`, `terrain_group_name`, `terrain_layers` (subset, empty = all), `terrain_layer_names`, `terrain_splat_layers` | TerrainAdapter writes `stream_prefix + name` per layer from `adapter.get_layer_weight` at each point's XZ. An unknown layer or a missing or ambiguous terrain is an error. Textures mode is unchanged and stays scene independent. TerrainAdapter mode fingerprints the terrain. |

New resource: `FlowTerrainSplatLayer` (`layer_name`, `image`, `texture`,
`channel`).

Traits and scene dependency:
- No template was added, so there are no new `FlowNodeTraits` rows. The
  touched nodes are already main-thread and not cacheable.
- `sample_terrain_layers` was added to `SCENE_DEPENDENT_TEMPLATES`, because its
  TerrainAdapter mode reads the scene. A subgraph that uses it now re-runs on a
  scene edit, which is conservative. Its own fingerprint stays
  `SCENE_INDEPENDENT` in Textures mode.

## Dictionary rows for COMING_FROM_UNREAL_PCG.md

These replace the existing rows of the same UE node.

| UE node | Here | Status | Notes |
|---|---|---|---|
| Get Landscape Data | `get_surface_data` (legacy: `scan_meshes`) | 1:1 | Surface data with height-field semantics from terrain `MeshInstance3D`s, `HeightMapShape3D` collision shapes, a heightmap Image, or, with `source = Terrain`, a terrain plugin node through a terrain adapter. Terrain3D and HTerrain are detected by their methods (unmodified plugin classes work), or named with `terrain_node_path`; ambiguity is reported. The surface carries the terrain's paint-layer weights, so Surface Sampler writes `layer_<name>` on every point. The plugin adapters are tested against fakes in the suite and were checked once against the real plugins (Terrain3D v1.0.2-stable and HTerrain 1.8.1 (master), unmodified, Godot 4.7.1 on Windows). |
| Landscape layer weights (sampling a landscape writes layer weights; Get Landscape Data layer settings) | `surface_sampler` / `to_point` on terrain surface data, or `sample_terrain_layers` | 1:1 | Terrain surfaces (Get Surface Data, Terrain source, or a heightmap image with splat layers) write one Float weight per layer, `layer_<name>`, onto sampled points. `sample_terrain_layers` reads the same weights for any points, from mask textures (`layer_source = Textures`) or from a terrain adapter (`TerrainAdapter`): Terrain3D control map, HTerrain splat maps, splat images on HeightMapShape3D, mesh or image terrains. Filter with `density_filter` / `attribute_filter_range`. |
| Difference | `difference` | 1:1 | As in WP2, plus `overlap_mode`. With `BoundsBox` (the default) a point tested against spatial data is its bounds box, not its centre: a large point whose bounds reach into a volume is removed (Binary) or attenuated by the covered fraction shaped by its steepness, as Unreal treats point-versus-volume and as point-versus-point already did here. The result is exact for axis-aligned boxes and spheres; other shapes are tested at 15 fixed samples. `PointCenter` keeps the centre test. |
| Intersection / Inner Intersection | `intersection` (or `difference`, operation = Intersection) | 1:1 | Same `overlap_mode`. With BoundsBox a point is kept if its bounds overlap the shape. |
| Union | `union` (or `difference`, operation = Union) | 1:1 | Same `overlap_mode` for points with a shape. |

Concept row addition (Spatial data types): "Points against a shape use the
point's bounds box by default (`overlap_mode = BoundsBox`)."

Remove from the "things UE has that this addon does not yet" list: "landscape
paint layers".

## nodes_reference.md rows

| Node | Script File | Description |
| --- | --- | --- |
| **Get Surface Data** | [get_surface_data.gd](../nodes/get_surface_data.gd) | Surface data from MeshInstance3D nodes, HeightMapShape3D collision shapes, a heightmap image, or a terrain (Terrain3D / HTerrain auto-detected, or by path) with its paint-layer weights (Get Landscape Data). |
| **Sample Terrain Layers** | [sample_terrain_layers.gd](../nodes/sample_terrain_layers.gd) | Writes one weight stream per paint layer, from mask textures or from a terrain adapter (Terrain3D control map, HTerrain splat maps, splat images). |
| **Surface Sampler** | [surface_sampler.gd](../nodes/surface_sampler.gd) | Samples points inside the bounds of the input points, or on surface data (points per square meter, looseness, density, optional bounding shape); writes terrain layer weights on terrain surfaces. |
| **Difference** | [difference.gd](../nodes/difference.gd) | Set operations between point sets (position/size overlap) or spatial shapes: shape with shape gives a composite; points with a shape are filtered or density-attenuated, testing each point's bounds box (default) or centre. |

## node_templates.csv rows

None. No template was added.

## DEPRECATIONS.md rows

| Symbol | Status | Replacement | Since |
|---|---|---|---|
| `difference` / `intersection` / `union`, points with a shape | **Output change against the WP2 branch state** (never released): the default `overlap_mode = BoundsBox` tests each point's bounds box. Points near a shape's edge, or large points, are now removed or attenuated where WP2 kept them. | Set `overlap_mode = PointCenter` for the WP2 result (byte-identical, tested). | WP6 |
| `get_surface_data` `eSource` | `Terrain = 2` appended; saved values 0 and 1 keep their meaning. | — | WP6 |
| `FlowHeightfieldSurface` | NaN heights are holes (projection and density miss around them; bounds ignore them). Grids without NaN are unchanged. | — | WP6 |
| `FlowSpatial` | New virtuals `box_overlap(min, max)` and `get_layers()`. A third-party shape inherits the sample-set `box_overlap` and no layers. | Override `box_overlap` for an exact overlap. | WP6 |
| `sample_terrain_layers` in `FlowNodeBase.SCENE_DEPENDENT_TEMPLATES` | A subgraph or loop body containing it is re-run after scene edits (conservative), because its TerrainAdapter mode reads the scene. Output is unchanged. | — | WP6 |

## Roadmap text

The status table row "Landscape paint layers / terrain plugins" becomes
**Implemented**, with this description: "Terrain adapters
(`FlowTerrainAdapter`: HeightMapShape3D, heightmap Image with splat images,
MeshInstance3D, Terrain3D and HTerrain by duck typing); `get_surface_data`
Terrain source with method-based auto-detection; layer weights on terrain
surfaces written by Surface Sampler; `sample_terrain_layers` TerrainAdapter
mode."

In the spatial section, replace "Unreal's per-point bounds-vs-shape overlap is
approximated by the density at the point's position" with "Points against a
shape use the point's bounds box (`overlap_mode = BoundsBox`): exact for
axis-aligned boxes and spheres, 15 fixed samples otherwise."

## Deviations from the contract

- **HTerrain `get_heightmap_aabb()` is not called.** The contract lists it, but
  I could not confirm that the plugin has it, and the rule is to call only
  methods known to exist. The bounds come from the height snapshot (`HTerrainData`
  `get_resolution` + `get_height_at` / `get_interpolated_height_at`) and the
  internal transform. `get_height_at(int, int)`,
  `get_map_count(int)`, `get_image(int, int)` and `get_internal_transform()` were
  added to the list of used members, each guarded with a fallback.
- **Terrain3D control map** is read through `data.get_texture_id(Vector3)` only
  (not `get_control*`), and region extents through `get_region_locations()`,
  `get_height_range()` and the `region_size` / `vertex_spacing` properties.
- **The `surface_sampler` "terrain input" work** is implemented in
  `FlowSpatial.sample_surface` (spatial/, owned). The sampler only passes two
  settings, so `to_point` gets the layer streams too.
- **Overlap combination.** The guidance said to combine "sample densities with
  the node's density function". The samples are reduced to (peak, coverage),
  then folded with the point's steepness into one overlap density, and that
  density goes through the node's density function. This is what makes the
  result equal to point-versus-point for hard boxes. Binary uses the peak.

## Limits

- **Plugins not verified.** The Terrain3D and HTerrain adapters were written
  from my recollection of the plugin APIs (Terrain3D 1.0, godot_heightmap_plugin
  1.7.x) and tested only against fakes. The following are assumptions that the
  fakes cannot check:
  - Terrain3D region origin: a region starts at `location * region_size *
    vertex_spacing`.
  - The meaning of the blend component of `get_texture_id`.
  - HTerrain's cell-space argument to `get_interpolated_height_at`.
  - The HTerrain fallback transform used when `get_internal_transform` is
    missing.
  - HTerrain's splat channel constant.
  If one is wrong, the adapter reads wrong values. It does not crash, because
  every call is guarded.
- **Point bounds ignore rotation**, exactly as point-versus-point does
  (`BoundsOverlapUtil.world_aabbs`). Unreal tests the rotated point box.
- **Sample-set overlap** (rotated boxes, ellipsoids, meshes, splines,
  surfaces, composites) can miss a small shape that lies entirely inside a
  large point box between the 15 samples. Boxes and spheres are exact for the
  peak, so this does not happen with them. Coverage for soft boxes and for
  spheres also comes from the sample set.
- **Cost.** BoundsBox costs 15 density queries per point for non-exact shapes.
  Axis-aligned boxes and spheres cost about one.
- **Layer resolution.**
  - Terrain3D layers are snapshotted on the height lattice (`vertex_spacing`,
    capped by `max_resolution`). Detail finer than a vertex is lost in
    `to_surface()`, but live `get_layer_weight` in `sample_terrain_layers` is
    exact.
  - Lookups are nearest-lower texel (the Sample Terrain Layers convention), not
    filtered.
- **Union layers.** A union composite exposes A's layers (else B's). Weights
  are not routed per hit to the operand that was hit.
- **HTerrain snapshot.** It reads every cell (`get_height_at`): about 263 000
  calls for a 513² terrain. Above `terrain_max_resolution` it subsamples and
  may drop the last partial row of cells.
- **Terrain3D without regions** (or an older API) needs explicit
  `terrain_bounds`.
- **Holes** are supported for heightfield snapshots (NaN). Mesh terrains have
  no holes concept beyond gaps in the mesh.

## Tests

New suites:
- `demo/tests/spatial/overlap_mode_test.gd`: 12 cases. These cover:
  - the motivating case;
  - equivalence with point-versus-point;
  - bounds streams versus size;
  - steepness;
  - PointCenter against the frozen WP2 script (9 shapes × 5 operations × 4
    density functions × 2 input orders);
  - the exact box and sphere paths and the sample set;
  - the surface column;
  - `overlap_factor`.
- `demo/tests/terrain/terrain_adapters_test.gd`: 17 cases. These cover every
  adapter: heights, edge clamping, normals at edges and holes, layers,
  `to_surface`, `max_resolution`, renaming, the legacy Terrain3D `storage` with
  explicit bounds, the HTerrain fallback transform, `FlowSurfaceLayers`,
  composites, detection and ambiguity, and generated nodes being skipped.
- `demo/tests/terrain/terrain_nodes_test.gd`: 12 cases.
  - `get_surface_data` Terrain source: auto-detection, path, ambiguity, errors,
    ownerless use, splat layers, fingerprint.
  - HeightmapImage unchanged without splat layers.
  - `surface_sampler` layer streams and bounding shape.
  - `sample_terrain_layers` TerrainAdapter mode and fingerprint.
  - `SCENE_DEPENDENT_TEMPLATES`.
- `demo/tests/terrain/support/fake_terrain_plugins.gd`: fakes for both plugins.
- `demo/tests/spatial/legacy/legacy_difference_wp2.gd`: frozen copy of the WP2
  `difference.gd` (base `45f78b3`).

Results (Godot 4.6, run from `demo/`):
- `godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://tests`
  gives 2223 cases (the 2182 baseline plus 41), 0 failures, 2 skipped and
  1 orphan. The orphan is the existing one in `surface_sampler_test`, and the
  run exits 101 as on the baseline. Golden and seed-zero pass unchanged,
  without regeneration.
- `-a res://tests/terrain -a res://tests/spatial` gives 124 cases with 0
  failures on both `godot` (4.6) and `godot47` (4.7.1).
- The import check prints nothing.

Existing tests edited, an intended change: in
`demo/tests/spatial/spatial_consumer_nodes_test.gd`, the `_diff` helper gained
an optional overlap-mode argument. Three tests that assert point-centre
densities now pass `PointCenter` explicitly:
`test_points_minus_shape_binary_and_density_functions`,
`test_points_intersect_and_union_shape` and
`test_forest_minus_road_spline_soft_edge`. Their expected values did not
change.

## Files touched outside WP6 ownership

- `demo/addons/flow_nodes_editor/node.gd`: one entry in
  `SCENE_DEPENDENT_TEMPLATES` (`sample_terrain_layers`). The central edit is
  allowed.
- `demo/tests/spatial/spatial_consumer_nodes_test.gd`: as listed above.
