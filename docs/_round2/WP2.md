# WP2: spatial data (round 2 notes for the coordinator)

## Summary

Point streams are no longer the only thing a wire can carry. A `FlowData.Data`
can now hold a **spatial shape** on `Data.shape` (typed `FlowSpatial`): a spline,
a surface, a volume, or a set operation of two shapes. Shapes are deferred
descriptions. Nothing is sampled until a sampler or To Point asks for points, so
the Unreal algebra works: intersect a landscape with a volume or a closed spline,
subtract a road spline from a forest surface, and only then scatter.

- **Shapes** live in `demo/addons/flow_nodes_editor/spatial/`. They are immutable
  value objects. Constructors copy the source geometry (Curve3D, mesh triangles,
  height samples) and build every acceleration structure up front. Queries are
  pure reads, so they are safe on worker threads, and a scene edit after
  generation cannot change a cached result. `content_hash()` covers geometry,
  transform and parameters.
- **Sources:** `get_spline_data`, `get_surface_data`, `get_volume_data`. Also
  `make_bounds` (output_mode = Shape) and `get_bounds` (Shape mode).
- **Concrete sampling:** `to_point`, plus the extended samplers `surface_sampler`,
  `volume_sampler` and `sample_spline`.
- **Algebra:** `difference`, `intersection`, `union`. Shape with shape gives a
  composite. Points with a shape are filtered or have their density attenuated,
  using the same `density_function` setting (Binary / Minimum / Multiply / Subtract).
- **Projection:** `projection_mode = Surface` projects points onto surface data.
- **Surfaces from outlines:** `create_surface_from_spline` and
  `create_surface_from_polygon` gain `output_mode = Shape`.
- **Classification:** `filter_data_by_type` classifies by the shape and gains the
  SurfaceData, VolumeData and SpatialData targets.

**Back-compat.** Every new behaviour is opt-in. The output for point, `Path3D` and
mesh-node inputs with default settings is byte-identical to the pre-WP2 nodes.
`tests/spatial/spatial_legacy_paths_test.gd` runs frozen copies of the nine
pre-WP2 node scripts (`tests/spatial/legacy/`, base `17c4524`) against the
current ones and compares every bulk, stream, tag, attribute and error text.
The golden and seed-zero suites pass without regeneration. New input ports
appear only when their mode is turned on (`projection_mode = Surface`,
`use_bounding_shape`), so links saved to parameter ports keep their indices.

## Class diagram in words

- `FlowSpatial` (`RefCounted`, abstract). Members: `steepness`, `_hash`.
  - Virtual methods: `get_kind`, `get_bounds`, `sample_density`, `project`,
    `project_vertical` (surfaces), `to_points`, `content_hash`, `get_type_name`
    and `union_leaves`.
  - Static helpers: `falloff(t, steepness)`, `combine_density(op, fn, a, b)`,
    `make_points_data(...)`, `sample_surface(shape, settings, errors)`,
    `sample_volume(shape, settings, errors)`, `closest_point_on_triangle`,
    `transform_normal`, `cell_seed`.
  - Constants: `DENSITY_BINARY`, `DENSITY_MINIMUM`, `DENSITY_MULTIPLY` and
    `DENSITY_SUBTRACT` (0..3, equal to `DifferenceNodeSettings.eDensityFunction`),
    and `enum Op { Union, Intersection, Difference }`.
- `FlowSplineShape` extends `FlowSpatial` (kind Spline).
  - Fields: a duplicated, pre-baked `curve`, `transform`, `closed` and `half_width`.
  - As a density it is a tube of radius `half_width` with a steepness falloff.
  - `to_points` samples along the curve.
  - Builder: `from_path(Path3D)`, which uses the world transform.
- `FlowPolygonSurface` extends `FlowSpatial` (kind Surface).
  - Fields: a closed `polygon` on the local XZ plane, `transform`, `height` and
    `vertical_tolerance`.
  - Point-in-polygon tests are accelerated with Z bands.
  - Builders: `from_world_points(points, plane)` and `plane_basis(plane)`
    (plane is XZ, XY or YZ).
- `FlowTriangleGrid` (`RefCounted`) is a world-space triangle soup with an XZ grid
  in CSR layout. It keeps per-cell height ranges and offers `vertical_hit`,
  `count_crossings_above` (parity), `nearest` (ring walk with exact lower bounds)
  and `count_column_candidates`.
- `FlowMeshSurface` extends `FlowSpatial` (kind Surface).
  - Has-a `FlowTriangleGrid`.
  - `project` returns the vertical hit nearest to the point's height, otherwise
    the nearest point on the mesh. `project_vertical` returns the top-most hit.
  - Builders: `from_meshes` and `from_mesh_instances`.
- `FlowHeightfieldSurface` extends `FlowSpatial` (kind Surface).
  - Fields: `heights`, `width`, `depth`, `cell_size`, `origin`, `transform` and
    `vertical_tolerance`.
  - Heights are bilinear. Queries index the grid directly, in O(1).
  - Builders: `from_heightmap_shape(HeightMapShape3D, xform)` and
    `from_image(Image, cell, height_scale, xform, centered)`.
- `FlowBoxVolume` and `FlowSphereVolume` extend `FlowSpatial` (kind Volume).
  - Each is an oriented box or sphere (an ellipsoid when the transform scales it)
    with a steepness falloff.
  - Builders: `from_aabb` and `at`.
- `FlowMeshVolume` extends `FlowSpatial` (kind Volume). It has a
  `FlowTriangleGrid` and uses the parity inside test, so density is binary.
- `FlowPointsVolume` extends `FlowSpatial` (kind Volume).
  - It is point data seen as a volume: per-point world boxes from the effective
    bounds, each point's steepness and density, and a hash grid.
  - It is used when points must be a composite operand, for example "surface
    minus these points".
- `FlowCompositeShape` extends `FlowSpatial`.
  - Fields: `op`, `a`, `b` and `density_function`, all evaluated lazily.
  - Builder: `union_of(shapes)`.
  - Kind: Difference takes A's kind. Intersection is a Surface if either operand
    is a surface. Union is a Surface only when both operands are. Splines count
    as volumes.
- `FlowSpatialSources` (`RefCounted`, static) holds the scene collection,
  fingerprint and volume builders shared by the Get * Data nodes.
- `FlowData.Data.shape : FlowSpatial`.
  - The setter makes `kind` follow `shape.get_kind()`. Setting the shape to null
    leaves `kind` alone.
  - `copy_meta_from` copies the shape, then copies `kind` from the source
    verbatim. `content_hash` mixes in the shape's type name and hash.
  - New helpers: `Data.from_shape(shape)` (a Data with no points) and
    `has_shape()`.

## Semantics

**Density functions** (`FlowSpatial.combine_density`). `a` is the density of A
(or of the point) and `b` is the density of B (or of the shape):

| op | Binary | Minimum | Multiply | Subtract |
|---|---|---|---|---|
| Difference | b > 0 ? 0 : a | min(a, 1-b) | a(1-b) | a-b |
| Intersection | b > 0 ? a : 0 | min(a, b) | ab | a-(1-b) |
| Union | a > 0 or b > 0 ? 1 : 0 | max(a, b) | a+b-ab | min(a+b, 1) |

The Difference row is exactly `BoundsOverlapUtil.fold_density`, which the point
path of `difference` already uses. Intersection is the "complement of B" form of
that row, and Union is its dual. A test checks the table and the equality with
`fold_density`.

**Steepness** is honoured wherever a shape has a falloff: boxes, spheres, the
spline tube and points volumes. Steepness 1 is a hard edge. A lower value keeps
a core of density 1 of relative size `steepness` and then ramps linearly to 0 at
the boundary, as in Unreal. Mesh volumes and surfaces are binary.

**Surfaces as densities.** A surface's density is 1 inside its footprint: the
polygon outline, the heightfield grid, or the area a mesh covers along the
vertical. With `vertical_tolerance <= 0` (the default) the footprint extends
over the whole column. With a positive tolerance, density is limited to points
within that distance of the surface. This is what makes
Intersection(landscape, closed-spline surface) sample the landscape inside the
spline.

**Surface sampling** (`FlowSpatial.sample_surface`). This is the Unreal Surface
Sampler model.
- Candidates sit on an XZ grid anchored to world space, with cell size
  1/sqrt(points per m^2).
- Each cell has its own seeded jitter (`looseness`, `point_extents`), so points
  stay put when the sampled region grows or shrinks.
- Each candidate goes through `project_vertical`, and the hit is weighted by the
  shape's density. Composites fold their operands in at the hit.
- Points get density (when `apply_density`), seed, normal, steepness
  (`point_steepness`), bounds of ±`point_extents` and `size = point_size`.
- Count mode draws `num_points` random hits instead.
- `max_candidates` caps runaway settings and reports an error.

**Volume sampling** (`FlowSpatial.sample_volume`) places voxel centres on a
world-anchored grid of `voxel_size` and keeps those where the density is above 0.
The boundary is inclusive.

**Points against a shape** (`difference`). The result is points, as in Unreal's
"inferred" output for point sources.
- Binary: Difference drops the points where the shape's density is above 0, and
  Intersection keeps them. Union sets density to 1 where the point or the shape
  has density.
- The other three functions keep every point and fold the density.
- When the side that is kept is a shape and the cutter is points, the points
  become a `FlowPointsVolume` and the result is a composite.
- SymmetricDifference of points and a shape returns only the points minus the
  shape.

**Acceleration (benchmarked).** Build container, Godot 4.6 headless:
- 1000 vertical projections take 11 ms on 200 triangles, 12.5 ms on 20 000 and
  13.4 ms on 180 000. The largest number of triangles a single query tested was
  8, 18 and 18.
- 200 off-footprint nearest-point projections on 20 000 triangles take about
  3 ms, against 24 s before the ring bound included the distance to the grid.
- A 1025 x 1025 heightfield answers 1000 queries in about 4 ms.
- Polygons with 1000 edges test fewer than 100 edges per query.
- `flow_spatial_shapes_test.gd` asserts these scaling properties.

## Node settings

### New nodes

| Template | Settings | Output |
|---|---|---|
| `get_spline_data` | `group_name`, `required_meta_bool`, `recursive`, `output_mode` (PerSpline / Merged), `tube_half_width` (1.0), `tube_steepness` (1.0) | One Data per Path3D, each a `FlowSplineShape` with no points and the `@data` attributes `spline_length`, `spline_closed` and `source`. Merged gives one Data holding the union, plus `spline_count`. Meta: `scans_scene`. |
| `get_surface_data` | `source` (Scene / HeightmapImage), `group_name`, `required_meta_bool`, `recursive`, `include_meshes`, `include_heightmap_shapes`, `output_mode` (PerSource / Merged, default Merged), `heightmap_image`, `heightmap_texture`, `image_cell_size`, `image_height_scale`, `image_transform`, `image_centered`, `vertical_tolerance` (-1 means the whole column) | A `FlowMeshSurface` per MeshInstance3D (Merged: one mesh surface for all meshes), a `FlowHeightfieldSurface` per HeightMapShape3D, or one built from an image. Meta: `scans_scene`. HeightmapImage mode needs no scene. |
| `get_volume_data` | `group_name`, `required_meta_bool`, `recursive`, `include_collision_shapes`, `include_csg`, `include_meshes` (off), `mesh_volume` (Bounds / ClosedMesh), `output_mode` (PerVolume / Merged, default Merged), `steepness` | Volumes from CollisionShape3D: Box and Sphere exactly, Capsule and Cylinder as meshes, Concave from its faces, Convex as the box of its points. Group members that are Area3D or physics bodies contribute their collision shapes. CSG roots: a plain CSGBox3D or CSGSphere3D exactly, otherwise the baked mesh (or the AABB until the mesh exists). Meta: `scans_scene`. |
| `to_point` | `spline_interval`, `points_per_square_meter`, `point_extents`, `looseness`, `point_steepness`, `voxel_size`, `apply_density`, `keep_zero_density`, `max_candidates`, `random_seed` | The default concrete sampling of the shape, with tags and `@data` attributes kept. Points without a shape pass through. |
| `get_bounds` | `output_mode` (Points / Shape), `steepness` | One point per input: the box centre with bounds of ±half the box size and `@data.bounds_min/max` (world corners), taken from the shape or from the points' effective bounds. Shape mode outputs a `FlowBoxVolume` instead. |

### Extended nodes (defaults leave the output unchanged)

| Template | New settings | Behaviour |
|---|---|---|
| `surface_sampler` | `shape_sampling` (PointsPerSquareMeter / Count), `points_per_square_meter` (0.1), `point_extents` (1,1,1), `looseness` (1), `apply_density_to_points` (on), `point_steepness` (0.5), `keep_zero_density_points`, `align_to_normal`, `use_bounding_shape` (off), `max_candidates` | A shape-bearing input samples the surface itself, including composites. `use_bounding_shape` adds a "Bounding Shape" input (a shape, or points used as boxes) that restricts sampling. On point inputs it filters the samples and scales their density. |
| `volume_sampler` | `voxel_size` (1,1,1), `apply_density_to_points`, `max_candidates` | A shape-bearing input is sampled on a voxel grid. Point inputs use the Sample Points path as before. |
| `sample_spline` | none | Accepts a `FlowSplineShape`, or a union of them, as input. Every mode (uniform, random, segment centres, fill) works and matches the Path3D path output for output. The sampler works on a private curve copy. Empty spline data (kind Spline with no `node` stream) gives an empty output without an error. |
| `difference`, `intersection`, `union` | none (`density_function` is now shown for every operation) | Spatial path as described above. |
| `projection` | `projection_mode` (Physics / Surface), `project_density` (on) | Surface mode adds a "Projection Target" input (surface data, or a scan_meshes `node` stream) and needs neither physics nor an owner. A hit moves the point and writes the normal. With `align_to_normal` it also sets the rotation, and with `project_density` it multiplies the density. A miss, or a hit of density 0, is kept unless `discard_misses`. `direction`, `collision_mask` and `ray_length` apply to Physics mode only. |
| `create_surface_from_spline` | `output_mode` (Points / Shape), `merge_shapes` | Shape mode outputs a `FlowPolygonSurface` per outline, with `@data` area and perimeter. It also accepts spline data in both modes. |
| `create_surface_from_polygon` | `output_mode` (Points / Shape), `merge_shapes` | Shape mode outputs a polygon surface per group. |
| `make_bounds` | `output_mode` (Points / Shape), `steepness` | Shape mode outputs a `FlowBoxVolume` with no points. |
| `filter_data_by_type` | `target_type` gains SurfaceData, VolumeData and SpatialData (appended) | A Data with a shape is classified by that shape. A union made only of splines counts as SplineData. |

`scan_splines` and `scan_meshes` are unchanged and keep working. Every consumer
still accepts their `node` streams.

## Dictionary rows for COMING_FROM_UNREAL_PCG.md

These replace the existing rows of the same UE node.

### Input / Output & Get Data

| UE node | Here | Status | Notes |
|---|---|---|---|
| Get Spline Data | `get_spline_data` (legacy: `scan_splines`) | 1:1 | Collects Path3D nodes (by group, or the whole scene) as spline data: a copied curve and world transform per Data, the way Unreal returns one spline data per spline component. `Merged` returns one Data with the union. Feeds Spline Sampler, To Point, Create Surface From Spline and the set operations, where the spline acts as a tube of `tube_half_width` with a `tube_steepness` falloff. `scan_splines` still emits the old `node` stream. |
| Get Landscape Data | `get_surface_data` (legacy: `scan_meshes`) | 1:1 | Surface data from terrain MeshInstance3D nodes, HeightMapShape3D collision shapes or a heightmap Image, with real height-field semantics: vertical projection, normals, footprint density. Paint layers: `sample_terrain_layers`. Terrain3D / HTerrain adapters are wave B. |
| Get Volume Data / Get Primitive Data | `get_volume_data` | 1:1 | Volume data from CollisionShape3D nodes (also the shapes inside an Area3D or physics body), CSG roots and mesh bounds or closed meshes. Box and sphere edges honour `steepness`. |
| Get Bounds / Spatial Data Bounds To Point | `get_bounds` | 1:1 | Bounds of a shape or of points, as a bounds point or a box volume. |

### Samplers

| UE node | Here | Status | Notes |
|---|---|---|---|
| Surface Sampler | `surface_sampler` | 1:1 | On surface data (Get Surface Data, composites) it follows Unreal's model: points per square meter, point extents, looseness, apply density, point steepness, a world-anchored grid with per-cell seeds, and an optional Bounding Shape pin (`use_bounding_shape`). Point inputs keep the old behaviour (`num_points` per input region). |
| Volume Sampler | `volume_sampler` | 1:1 | On volume data (Get Volume Data, composites, splines) it samples a voxel grid of `voxel_size` and keeps the voxels where density is above 0. Point inputs subdivide each point's volume as before. |
| Spline Sampler | `sample_spline` | 1:1 | Accepts spline data (Get Spline Data) as well as the `node` stream of Path3Ds, with identical output. |

### Spatial

| UE node | Here | Status | Notes |
|---|---|---|---|
| To Point / Make Concrete | `to_point` | 1:1 | Samples a spline along its curve, a surface on the surface-sampler grid, and a volume on a voxel grid. A composite is sampled as a surface or a volume according to its kind. Point data passes through. |
| Difference | `difference` | 1:1 | Shape with shape gives a composite that is sampled later (for example "landscape minus the road spline" before scattering). Points with a shape are filtered (Binary) or density-attenuated (Minimum / Multiply / Subtract) by the shape's density, with steepness falloff. Points with points use the RTree path with per-point bounds and steepness. |
| Intersection / Inner Intersection | `intersection` (or `difference`, operation = Intersection) | 1:1 | Shape with shape gives a composite: surface ∩ volume or surface ∩ surface samples only the overlap, before any points exist. Points with a shape keep the points inside (Binary) or fold the density. There is still no N-way inner variant: chain the nodes. |
| Union | `union` (or `difference`, operation = Union) | 1:1 | Shape with shape gives a union composite. The density functions map to Unreal's: Binary is 1 where either side has density, Minimum is max(a, b), Multiply is a+b-ab and Subtract is the clamped sum. Points with a shape fold the density. Points with points merge as before. |
| Projection | `projection` | 1:1 | `projection_mode = Surface` projects points onto surface data wired to the Projection Target pin. It writes the normal, can align the rotation and multiplies the density. Physics mode, the default, raycasts colliders as before. |
| Create Surface From Spline | `create_surface_from_spline` | 1:1 | `output_mode = Shape` outputs real surface data (a polygon surface per closed spline, with area and perimeter). Intersect it with a landscape, sample it, or use it as a cutter. Accepts Path3D streams or spline data. Points mode keeps the bounds-point output. |

### Filters

| UE node | Here | Status | Notes |
|---|---|---|---|
| Filter Data By Type | `filter_data_by_type` | 1:1 | Classifies spatial data by its shape (Spline / Surface / Volume, plus a SpatialData "any shape" target). Point data and attribute sets keep the previous classification. |

### Concept dictionary row (replace "Spatial data types")

| Unreal | Here | Notes |
|---|---|---|
| **Spatial data types** (Surface, Volume, Spline, Primitive, composite algebra) | `Data.shape` (a `FlowSpatial`) | Get Spline / Surface / Volume Data produce shapes (no points). Difference, Intersection and Union combine them into composites without sampling. Surface Sampler, Volume Sampler, Spline Sampler and To Point make them concrete, and Projection projects onto them. Pins carry points and shapes alike. `filter_data_by_type` tells them apart. Point data still works everywhere, and points with a shape attenuate by the shape's density. |

### Tutorial 1 addendum (Forest quick-start)

UE-exact chain: `get_surface_data → surface_sampler → transform_points → spawn_meshes`.
Put the terrain MeshInstance3D (or a HeightMapShape3D collision shape) in group
`terrain` and set `get_surface_data.group_name = terrain`. On surface data,
`surface_sampler` reads `points_per_square_meter` (UE's default 0.1) instead of
`num_points`, places points on the surface (no projection step needed) and
writes `normal`. To keep trees off a road, wire
`get_spline_data → difference` (input B, `density_function = Subtract`) between
the sampler and the spawner, or subtract the spline from the surface *before*
sampling.

## nodes_reference.md rows

Spatial section:

| Node | Script File | Description |
| --- | --- | --- |
| **Get Bounds** | [get_bounds.gd](../nodes/get_bounds.gd) | World bounds of a spatial shape or of a point set, as one bounds point or a box volume shape. |
| **To Point** | [to_point.gd](../nodes/to_point.gd) | Converts spatial data (spline, surface, volume, composite) to points with its default sampling; point data passes through. |
| **Difference** | [difference.gd](../nodes/difference.gd) | Set operations between point sets (position/size overlap) or spatial shapes: shape with shape gives a composite, points with a shape are filtered or density-attenuated. |
| **Projection** | [projection.gd](../nodes/projection.gd) | Projects points onto physics colliders (default) or onto surface data (Surface mode), writing the normal and optionally the rotation and density. |
| **Make Bounds** | [make_bounds.gd](../nodes/make_bounds.gd) | Generates a single bounding point at center with size, or (Shape mode) a box volume shape. |

Generators (or a new "Input" section next to Scan Meshes / Scan Splines):

| Node | Script File | Description |
| --- | --- | --- |
| **Get Spline Data** | [get_spline_data.gd](../nodes/get_spline_data.gd) | Collects Path3D nodes as spline data (copied curve + transform per Data, or one merged union). |
| **Get Surface Data** | [get_surface_data.gd](../nodes/get_surface_data.gd) | Surface data from MeshInstance3D nodes, HeightMapShape3D collision shapes or a heightmap image (Get Landscape Data). |
| **Get Volume Data** | [get_volume_data.gd](../nodes/get_volume_data.gd) | Volume data from collision shapes (also inside Area3D / bodies), CSG roots or mesh bounds. |

Row updates:

| Node | Script File | Description |
| --- | --- | --- |
| **Surface Sampler** | [surface_sampler.gd](../nodes/surface_sampler.gd) | Samples points inside the bounds of the input points, or on surface data (points per square meter, looseness, density, optional bounding shape). |
| **Volume Sampler** | [volume_sampler.gd](../nodes/volume_sampler.gd) | Samples points inside incoming point volumes, or on a voxel grid inside volume data. |
| **Sample Spline** | [sample_spline.gd](../nodes/sample_spline.gd) | Samples points along Path3D curves or spline data (uniform, random, segment centres) or fills the closed XZ polygon (grid, random, Poisson). |
| **Create Surface From Spline** | [create_surface_from_spline.gd](../nodes/create_surface_from_spline.gd) | Creates one bounds-style surface point from each Path3D polygon/spline, or (Shape mode) a polygon surface. |
| **Create Surface From Polygon** | [create_surface_from_polygon.gd](../nodes/create_surface_from_polygon.gd) | Creates bounds-style surface points from ordered polygon point streams, or (Shape mode) polygon surfaces. |
| **Filter Data By Type** | [filter_data_by_type.gd](../nodes/filter_data_by_type.gd) | Separates data by type: point, spline, surface, volume, any spatial, attribute set. |

## node_templates.csv rows

```
"get_bounds","Get Bounds"
"get_spline_data","Get Spline Data"
"get_surface_data","Get Surface Data"
"get_volume_data","Get Volume Data"
"to_point","To Point"
```

## DEPRECATIONS.md rows

No output changes for existing graphs: golden and seed-zero baselines are
unchanged, and the legacy-path test compares the pre-WP2 node scripts output for
output. API-level rows:

| Symbol | Status | Replacement | Since |
|---|---|---|---|
| `FlowData.Data.shape` | **Typed** `FlowSpatial` (was untyped, always null in stock code). Assigning any other object is now a script error. Setting a shape also sets `kind` to `shape.get_kind()`. | Extend `FlowSpatial` (override `get_kind`, `get_bounds`, `sample_density`, `content_hash`, ...). | WP2 |
| `filter_data_by_type` `eTargetType` | Three values appended (SurfaceData = 3, VolumeData = 4, SpatialData = 5). Saved values 0..2 keep their meaning. | — | WP2 |
| `difference` inspector | `density_function` is shown for every operation, because Intersection, Union and Symmetric Difference use it with spatial inputs. Point-only behaviour is unchanged. | — | WP2 |

## Roadmap section text (replaces "Spatial data type lattice")

Status table row:

| Roadmap item | Status | What landed |
|---|---|---|
| Spatial data type lattice | **Implemented** | `FlowSpatial` shapes on `Data.shape` (spline, polygon / mesh / heightfield surfaces, box / sphere / mesh / points volumes, composites); Get Spline / Surface / Volume Data, To Point, Get Bounds; shape-aware samplers, set operations, Projection and Create Surface From *; `filter_data_by_type` by shape |

Section:

> ## Spatial data type lattice
>
> **Landed.** A Data carries point streams, a spatial shape (`Data.shape`, a
> `FlowSpatial`), or both. Shapes are splines (`FlowSplineShape`), surfaces
> (`FlowPolygonSurface`, `FlowMeshSurface`, `FlowHeightfieldSurface`), volumes
> (`FlowBoxVolume`, `FlowSphereVolume`, `FlowMeshVolume`, `FlowPointsVolume`) and
> composites (`FlowCompositeShape`: Union, Intersection, Difference with the
> Binary / Minimum / Multiply / Subtract density functions). Every shape answers
> `get_bounds`, `sample_density` (steepness-aware where it has a falloff),
> `project` (surfaces) and `to_points`. `Data.kind` follows the shape, so pins and
> `filter_data_by_type` classify honestly.
>
> The algebra works before sampling, as in Unreal. Intersect a landscape with a
> volume or a closed-spline surface, subtract a road spline, then sample:
> `get_surface_data → intersection(get_volume_data) → surface_sampler`. Points
> still work everywhere. A point set against a shape is filtered or
> density-attenuated by the shape's density, and a shape minus points treats the
> points as box volumes.
>
> Shapes are immutable value objects. They copy their source geometry at
> creation, so cached results never change under scene edits and queries are
> thread safe. Mesh surfaces and volumes use an XZ triangle grid and heightfields
> index directly, so a query costs the same on 200 or 180 000 triangles.
>
> **Remaining gaps.**
> - There are no typed pin colours per spatial kind yet. Spline and surface
>   outputs reuse the NodePath and NodeMesh colours.
> - The Data Inspector and debug draw do not visualise shapes; a shape-only Data
>   shows zero rows.
> - Terrain3D / HTerrain adapters are a wave B item; they will feed
>   `get_surface_data`.
> - Surfaces are sampled along the world vertical, or along the local Y axis for
>   heightfields. Vertical walls (XY / YZ polygon surfaces) can be projected onto
>   and density-tested, but the surface sampler finds no hits on them.
> - Convex collision shapes become the box of their points.
> - Unreal's per-point bounds-vs-shape overlap is approximated by the density at
>   the point's position.

## Requests for other packages (not done here: files I do not own)

- **WP1 (`node.gd`)**: add `get_spline_data`, `get_surface_data` and
  `get_volume_data` to `SCENE_DEPENDENT_TEMPLATES`. Until then, a scene edit does
  not re-run a subgraph or loop whose nested graph uses them; the top-level
  nodes already fingerprint correctly through `scans_scene` and their
  `computeSceneFingerprint` override.
- **WP1 (`FlowNodeTraits`)**: `to_point`, `get_bounds` and the set operations
  (`difference`, `intersection`, `union`) are pure functions of settings, seed
  and inputs. Shapes are immutable and `content_hash` covers them, so these
  nodes can be marked `cacheable` and run off the main thread. The samplers stay
  as they are today: `surface_sampler` still reads live MeshInstance3D
  transforms from a legacy `node` stream. The `get_*_data` nodes are
  `scans_scene`, so they run on the main thread.
- **WP1 (widget)**: `surface_sampler.getMeta()` and `projection.getMeta()` depend
  on settings (`use_bounding_shape`, `projection_mode`), like `output` and
  `sample_points`. Both nodes call `initFromScript` from `onPropChanged`,
  guarded with `has_method`. After the split, the widget must rebuild ports when
  those settings change.
- **WP1 (`data_inspector.gd`, `node_draw_debug.gd`)**: show the type name and
  bounds of `Data.shape`, and draw shape bounds.
- **WP3 (`spawn_spline_mesh`)**: can take a `FlowSplineShape`
  (`shape.curve`, `shape.transform`) as well as Path3D nodes.
