# WP3: spawner parity

Notes for the coordinator: summary, settings reference, and the rows to merge
into `docs/COMING_FROM_UNREAL_PCG.md`, `nodes_reference.md` and
`docs/DEPRECATIONS.md`.

## Summary

The spawners now cover what Unreal's spawner family exposes:

- **Mesh descriptors.** `FlowMeshSpawnEntry` (a `Resource`, saved as a sub-resource
  of the graph `.tres`) holds mesh, name, weight, material override, cast shadow,
  visibility range (begin, end, both margins, fade mode), render layers, GI mode,
  per-instance custom data from attributes, and collision (mode, body layout,
  layer, mask). `spawn_meshes.mesh_entries` uses them. When the list is empty, the node
  runs today's code path unchanged.
- **Selectors.** Entries are picked by weight (seeded per point from `$Seed`, or
  from the point position when there is no seed), by attribute index, by attribute
  name (a String attribute, or a Resource attribute holding the mesh), or by
  cycling through the point index. The pick is deterministic, and a point keeps its pick when other
  points are added or removed.
- **Grouping.** Points whose entries share every render, custom-data and collision
  setting go into one `MultiMeshInstance3D` per spawn parent.
- **Collision.** Four modes: none, box from bounds, convex, trimesh. Each has a physics
  layer and mask, and is built either as one shared body per MultiMesh or as one
  body per instance (see below).
- **`spawn_spline_mesh`** (new node). Bends a mesh along every segment of a
  `Path3D` spline, or of a spline shape through a duck-typed hook. Each segment is a
  `MeshInstance3D` whose bent `ArrayMesh` is cached. Settings cover the forward axis, tangent handling,
  up vector, scale along and across, segmentation (per control point or tiled), and per-segment
  entry selection with entry materials and collision.
- **Attribute-driven spawn.** `spawn_scenes`, `spawn_nodes` and `apply_on_actor` gain
  `property_overrides` (attribute name → property path). Paths can be nested
  properties, child paths and `%Unique` names. Values are type-coerced and applied
  after instancing.
- **`create_target_node`** (new node, Unreal's Create Target Actor). Creates or reuses a
  named `Node3D` container (groups, owner policy) and outputs a reference to it.
  Spawners parent their content under it through the new `spawn_parent_attribute`
  setting, which takes a per-point stream, a broadcast stream or `@data.<name>`.
- **Pooling.** `FlowSpawnPool` plus `reuse_instances : bool = false` on
  `spawn_meshes`, `spawn_scenes`, `spawn_nodes` and `spawn_spline_mesh`.
  MultiMeshInstance3Ds, scene roots, spawned nodes and segment meshes are reused
  across generations of the same component and node.
- The dead `_exit_tree` stubs in `spawn_meshes.gd` and `spawn_scenes.gd` are removed.

Back-compat: with no new setting touched, the three existing spawners produce
the same nodes as before: names, counts, child order, classes, properties and
`flow_owner` meta, with no extra meta. This was checked two ways:

- `tests/spawn/spawner_defaults_test.gd`.
- A temporary differential suite. It ran the pre-WP3 scripts and the new scripts
  side by side on 20 default-settings configurations: variants, random variants,
  selectors, mesh attribute, colours, spawn parent path, clear off, assign
  attributes, and the error cases. Every snapshot and error string matched. The
  suite was deleted afterwards because it embedded copies of the old scripts.

The existing spawner tests pass unmodified.

## New files

| File | Purpose |
|---|---|
| `addons/flow_nodes_editor/spawn/flow_mesh_spawn_entry.gd` | `FlowMeshSpawnEntry` descriptor resource |
| `addons/flow_nodes_editor/spawn/flow_spawn_util.gd` | `FlowSpawnUtil`: entry selection, grouping keys, render settings, custom data, collision, spawn parents, property overrides and coercion, ownership helpers |
| `addons/flow_nodes_editor/spawn/flow_instanced_collision_3d.gd` | `FlowInstancedCollision3D`: shared collision body (one node, one shape owner per instance), serialisable |
| `addons/flow_nodes_editor/spawn/flow_spawn_pool.gd` | `FlowSpawnPool` |
| `addons/flow_nodes_editor/spawn/flow_spline_bend.gd` | `FlowSplineBend`: pure bend math, mesh bending, bounded LRU cache |
| `addons/flow_nodes_editor/nodes/spawn_spline_mesh.gd` (+ `_settings.gd`) | Spawn Spline Mesh node |
| `addons/flow_nodes_editor/nodes/create_target_node.gd` (+ `_settings.gd`) | Create Target Node node |
| `tests/spawn/*.gd` | 7 suites, 92 cases, plus `spawn_test_support.gd` |

## Settings reference

### `FlowMeshSpawnEntry`

| Field | Default | Meaning |
|---|---|---|
| `mesh` | null | Mesh of the entry. An entry without a mesh spawns nothing (a weighted "empty" choice). |
| `entry_name` | "" | Name matched by Attribute Name selection. Empty: the mesh's `resource_name`, then its file basename. |
| `weight` | 1.0 | Weighted selection weight. 0 never picks the entry. All zero: equal weights. |
| `material_override` | null | `GeometryInstance3D.material_override`. When null and the points carry colours, the vertex-colour material that Spawn Meshes has always used is applied. |
| `cast_shadow` | On | `GeometryInstance3D.cast_shadow` |
| `visibility_range_begin`, `_begin_margin`, `_end`, `_end_margin` | 0 | Visibility range and fade/hysteresis margins |
| `visibility_range_fade_mode` | Disabled | Fade mode |
| `render_layers` | 1 | `VisualInstance3D.layers` |
| `gi_mode` | Static | `GeometryInstance3D.gi_mode` |
| `custom_data_attributes` | [] | Attributes packed into MultiMesh custom data (`INSTANCE_CUSTOM`), in order. Float, Int and Bool fill one channel, Vector three, Color and Quaternion four. Channels past the fourth are dropped and unused ones are 0. Non-empty sets `use_custom_data`. |
| `collision_mode` | None | None, BoxFromBounds (box sized to the mesh AABB, offset to its centre), Convex (`Mesh.create_convex_shape`), Trimesh (`Mesh.create_trimesh_shape`, static only) |
| `collision_bodies` | PerMultiMesh | PerMultiMesh or PerInstance (see Collision) |
| `collision_layer`, `collision_mask` | 1, 1 | Physics layer and mask of the generated bodies |

### `spawn_meshes` (new settings, after the existing ones)

| Setting | Default | Meaning |
|---|---|---|
| `mesh_entries` | [] | Descriptors. Non-empty: they are the mesh source, and `mesh`, `mesh_attribute`, `mesh_variants`, `mesh_variant_weights`, `mesh_selector_attribute` and `randomize_mesh_variants` are ignored. Colours (`use_vertex_colors`/`color_attribute`) still apply. |
| `entry_selection` | Weighted | Weighted, AttributeIndex (Int/Float/Bool attribute, clamped), AttributeName (String attribute matched to `get_match_name()`, or Resource attribute matched to the mesh; unmatched points are skipped and reported), Cycle (point index modulo entry count) |
| `entry_attribute` | "" | Attribute read by the two attribute selections. A per-data attribute also works. |
| `spawn_parent_attribute` | "" | Spawn parent per point or per data (see Create Target Node) |
| `reuse_instances` | false | Pooling |

Grouping key: `(mesh, material_override, cast_shadow, the five visibility
fields, render_layers, gi_mode, custom_data_attributes, collision_mode,
collision_bodies, collision_layer, collision_mask)` plus the spawn parent. Two
distinct entry resources with identical values share one MultiMesh. In the entries path,
configuration errors (selector, colour or custom-data attributes) are reported
before anything is cleared, so a bad edit keeps the previous output on screen.

### `spawn_spline_mesh` (new, category Spawner, aliases "Spline Mesh Spawner", "Spawn Spline Mesh")

| Setting | Default | Meaning |
|---|---|---|
| `mesh` | unit cube | Mesh when `mesh_entries` is empty |
| `mesh_entries` | [] | Per-segment descriptors. Material, shadow, visibility, layers, GI and collision apply; custom data does not. |
| `segment_selection` | Cycle | Cycle (segment index) or Weighted (seeded by node seed, spline index, segment index) |
| `forward_axis` | Z | Mesh axis laid along the spline (X, Y, Z) |
| `segmentation` | ControlPoints | ControlPoints: one segment per pair of control points, plus the closing one on a closed curve. TileMesh: `round(length / (mesh length × scale_along))` equal segments, at least one. |
| `scale_along` | 1.0 | TileMesh tile length multiplier |
| `scale_across_start`, `scale_across_end` | (1, 1) | Cross-section (side, up) scale, interpolated along each segment (Unreal's start/end scale) |
| `tangent_mode` | Curve | Curve: follow the baked cubic curve. Linear: straight chord per segment. |
| `up_mode` | CurveUp | CurveUp: Curve3D up vectors with tilt, or world up when `up_vector_enabled` is off. WorldUp: world +Y re-orthogonalised. |
| `spline_attribute` | "node" | Stream of `Path3D` nodes (what `scan_splines` and `create_spline` emit) |
| `spawn_parent_path`, `spawn_parent_attribute` | "" | Spawn parent (the attribute is read once, as element 0 or the per-data value) |
| `clear_previous_instances` | true | Clear this node's segments first |
| `reuse_instances` | false | Pooling |

Output: the input, passed through. Each segment is a `MeshInstance3D` named
`SplineMesh_%04d`, placed at the spline's transform relative to the spawn parent.
It carries `flow_owner` meta and a `spline_segment` meta `{spline, segment, from, to}`.

Bend model (`FlowSplineBend`, pure functions): the mesh extent `[f_min, f_max]` on
the forward axis maps linearly onto the baked arc-length offsets
`[from_offset, to_offset]`. The other two axes are placed in the curve frame
`(side, up)` at that offset, scaled by `lerp(scale_start, scale_end, t)`. The
local-to-frame mapping is a proper rotation for each axis choice, so a straight
segment changes the mesh only by stretching it along the forward axis and moving it.
Normals and tangents are transformed with the same frame (inverse scale for normals).
Bent meshes are cached in a bounded LRU (256 entries) keyed by mesh identity (path or
instance id, plus AABB and surface count), curve content hash (points, handles,
tilts, bake interval, up vectors, closed), offsets and options.
`FlowSplineBend.clear_cache()` empties it. Blend shapes are not carried over.

**Segment extraction hook (for WP2 spline shapes).**
`spawn_spline_mesh.extract_segments(in_data, tile_length)` is the only function
that produces segments: `Array` of `{curve, from_offset, to_offset, transform,
spline_index, segment_index}`. It uses `extract_splines(in_data)`, which already
accepts `in_data.shape` duck-typed through `splines_from_shape(shape)`: an object with
`get_kind() == Kind.Spline` (or no `get_kind`) exposing a `Curve3D` via `get_curve()`
or a `curve` property, and optionally a `Transform3D` via `get_transform()` or a
`transform` property. If `FlowSplineShape` uses other member names, change only
`splines_from_shape`.

### `create_target_node` (new, category Spawner, alias "Create Target Actor")

| Setting | Default | Meaning |
|---|---|---|
| `node_name` | "FlowTarget" | Container name. An existing container of the same component, node and name (`flow_target_name` meta) is reused, so content parented under it and pooling survive regeneration. |
| `parent_path` | "" | Parent of the container, relative to the owner |
| `groups` | [] | Persistent groups added to the container |
| `owner_policy` | FollowComponent | FollowComponent: saved with the scene unless the component has `transient_output`. Transient: never saved. |
| `attribute_name` | "target" | Name of the output reference |

Output: with the input connected, the input's streams (shared, like a
pass-through) plus the per-data attribute `@data.<attribute_name>` (a NodePath-typed
reference). Unconnected: an attribute set with a one-element `<attribute_name>`
NodePath stream and the same per-data attribute. Typical chain:
`points → create_target_node → spawn_meshes (spawn_parent_attribute = "@data.target")`.
The container carries `flow_owner` meta, so `FlowGraphNode3D.cleanup()` frees it
together with everything spawned under it. The node is not `is_final`: it runs when
something consumes it.

### `spawn_parent_attribute` (spawn_meshes, spawn_scenes, spawn_nodes, spawn_spline_mesh)

The attribute (per point, broadcast, or `@data.<name>`) holds a `Node3D` reference
or a NodePath/String relative to the owner. Points whose value does not resolve
spawn under the default parent (`spawn_parent_path` or the owner), and the count is
reported through `setError`. A missing attribute is an error and nothing is
spawned. Clearing and pooling cover every referenced parent plus the default one.

### `property_overrides` (spawn_scenes, spawn_nodes, apply_on_actor)

`Dictionary`: point attribute name → property path. Paths are applied after
`add_child` (so after `_ready`) and after `assign_attributes`:

| Path | Target |
|---|---|
| `light_energy` | property of the instance root |
| `position:x`, `:position:x` | nested property of the root. A plain first name that is a root property is read as a property path, and a leading `:` forces the root. |
| `Child/Light:light_energy` | property of a descendant |
| `%Mesh:material_override:albedo_color` | unique-name lookup (scoped to the instance's own scene), nested property |

Values come per point, from a broadcast stream, or from a per-data attribute. Coercion
to the current property type: int/float/bool convert between each other (float →
int truncates); a scalar fills a vector or a grey Color; Vector3 ↔ Color; Vector3 →
Vector2 keeps (x, y); Vector3 → Vector3i/Vector2i rounds; a Quaternion attribute
(Vector4) → Quaternion or Basis; a Vector3 Euler rotation (degrees, like
`rotation`) → Quaternion or Basis; anything → String, StringName or NodePath; an
unset (`null`) property takes the value as is. Unresolved paths and impossible
conversions are reported once through `setError` (first message plus "(and N
more)"), and spawning continues. A missing attribute is reported and skipped. An
attribute whose size is neither 1 nor the point count is an error and nothing is
spawned. Caveat: a nested path through a shared sub-resource (for example a material
that is not `resource_local_to_scene`) writes the shared resource. In
`apply_on_actor`, paths resolve from the target actor itself, not from
`target_child_path`.

## Collision: how many bodies and why

| `collision_bodies` | Nodes per MultiMesh | Shapes |
|---|---|---|
| PerMultiMesh (default) | **1** `FlowInstancedCollision3D` (a `StaticBody3D`) as child of the `MultiMeshInstance3D` | One shape owner per instance, all sharing **one** `Shape3D` (one per mesh and mode per run). No node per instance. The body stores `shape` and `instance_transforms` as exported properties and rebuilds its shape owners when they change or when a saved scene loads, so collision baked into a scene by the editor works at runtime. A hit's shape index maps to the instance with `shape_owner_index(shape_find_owner(idx))`. |
| PerInstance | **2 per instance**: `StaticBody3D` `Collision_%04d` plus `CollisionShape3D` `Shape` | Same shared `Shape3D`. Use this only when gameplay needs one collider object per instance (per-instance signals, removal, `get_collider()` identity). |

Bodies are children of the MultiMesh (or segment) instance, so the regular clear
step and `cleanup()` remove them with it. They get the scene owner like their
parent. Scaled instance transforms are passed through as shape transforms; Jolt and
Godot Physics both accept that for box, convex and concave shapes.

Performance: 20 000 instances with shared box collision produce 2 nodes (1 MMI and
1 body) and take about 130 ms in the headless test run. The dummy renderer stores no
instance data, so this measures node and shape work only, not GPU upload.

## Instance pooling (`reuse_instances`, off by default)

- The scene tree is the pool. Elements are created fresh per run, so at the start of
  a run the spawner collects its previous content from the spawn parents. It uses the
  same match as the clear step: `flow_owner` `{component, node}`, legacy String
  metas and stale component ids. It hands out matching nodes while spawning, then
  detaches and frees whatever is left.
- Match keys are stored as `flow_pool_key` meta, only when pooling is on:
  - MultiMesh: mesh, colour flag, and in the entries path the full grouping key
    (material, shadow, visibility, layers, GI, custom data, collision).
  - Scene: the PackedScene.
  - Node: the class or script.
  - Spline segment: the entry key.
  Content without a key (spawned with pooling off) is never reused, only freed, so turning pooling
  on is always safe.
- Counts: a reused MultiMesh resizes its instance buffer in place, and the same
  `MultiMesh` resource is kept. Scenes, nodes and segments reuse up to the needed count per key.
  Excess nodes are removed, and missing ones are created fresh and tagged. A mesh,
  material, scene or class change finds no match, so it creates fresh nodes and
  frees the old ones.
- A reused node gets its transform, canonical name (`Scene_%04d`, ...), fresh
  `flow_owner` meta (stale ids are refreshed), scene owner (cleared if the
  component has turned `transient_output` on), assigned attributes and property
  overrides re-applied. Other runtime state of a reused scene instance is kept. A
  reused MultiMesh rebuilds its collision bodies.
- Scope: pooling applies when `clear_previous_instances` is on, across repeated
  `generate()` calls and editor re-evaluations. `regenerate()` and `cleanup()` free all
  generated content (FlowGraphNode3D is unchanged), so nothing is left to reuse after them.

## Ownership, owner-less, threading

- Everything spawned (MMIs, bodies, scene roots, nodes, segment meshes, target
  containers) follows `docs/RUNTIME_API_P0.md` §5: `flow_owner` `{component,
  node}` on the subtree root, `transient_output` respected, stale ids and legacy
  metas cleaned.
- Owner-less: every spawner and `create_target_node` calls `handleMissingOwner`. It
  reports the documented error and passes input 0 through. In an owner-less editor
  preview they stay silent and pass the input through.
- The new nodes declare `"main_thread": true` in `meta_node` for WP1's
  `FlowNodeTraits`. The existing spawners are `is_final`, so the trait defaults already
  make them main-thread. All spawner code uses only the existing element API
  (`setError`, `require_input`, `set_output`, `effective_seed`, `handleMissingOwner`,
  `flowOwnerMeta`, `isOwnFlowContent`, `removeOwnFlowContent`, `assignSpawnOwner`,
  `editor_mark_scene_unsaved`). The `spawn/` helpers take the element untyped so that
  they never load `node.gd`.

## Headless verification limits

The dummy RenderingServer keeps no MultiMesh instance data, so the tests cannot read
back per-instance transforms, colours or custom data. They assert values only when
read-back works (`multimesh_readback_supported()`, false headless). They always
assert instance counts, meshes, `use_colors`/`use_custom_data`, materials,
GeometryInstance properties, node names, transforms, meta, collision shapes and
shape-owner transforms. The bend math is checked numerically on vertex positions
and is independent of the renderer.

## Dictionary rows (`COMING_FROM_UNREAL_PCG.md`, Spawners table)

Replace the Static Mesh Spawner, Spawn Actor and Create Target Actor rows. Add the others.

| UE node | Here | Status | Notes |
|---|---|---|---|
| Static Mesh Spawner | `spawn_meshes` | 1:1 | One `MultiMeshInstance3D` per render group. `mesh_entries` (`FlowMeshSpawnEntry`) ≈ mesh entries / instance descriptors: mesh, weight, material override, cast shadow, visibility range (cull distances) with fade, render layers, GI mode, per-instance custom data from attributes (≈ custom data packing), collision (none, box from bounds, convex, trimesh; layer and mask; one shared body per MultiMesh or one body per instance). Selectors: weighted (per-point `$Seed`), by attribute index, by attribute name or mesh (≈ MeshSelectorByAttribute), cycling. Legacy `mesh` / `mesh_variants` / `mesh_attribute` keep working. Optional instance pooling (`reuse_instances`). |
| Static Mesh Spawner: mesh entry descriptor fields | `FlowMeshSpawnEntry` | partial | `mesh`, `weight`, `material_override` (one override, not per-slot overrides), `cast_shadow`, `visibility_range_*` (≈ cull distance), `render_layers`, `gi_mode`, `custom_data_attributes` (up to 4 floats), `collision_mode`/`_bodies`/`_layer`/`_mask`. No per-instance LOD or WPO settings (Godot has no direct equivalent). |
| Spawn Spline Mesh | `spawn_spline_mesh` | partial | One `MeshInstance3D` per spline segment with a bent `ArrayMesh` (Godot has no spline mesh component), cached per mesh and segment. Forward axis, curve or linear tangents, curve or world up, start/end cross-section scale, per-control-point or tiled segmentation, per-segment entry selection, entry materials and collision. No per-point roll/scale interpolation from spline attributes. Input is `Path3D` nodes today, plus spline shapes through the segment hook. |
| Spawn Actor | `spawn_scenes` (scenes) / `spawn_nodes` (raw nodes) | 1:1 | Instantiates a `PackedScene` (or a class/script) per point. `property_overrides` ≈ Spawn Actor property overrides: attribute → property path, nested (`position:x`), child (`Child:prop`), `%Unique` names, type coercion, applied after instancing. `assign_attributes` kept. Optional instance pooling (`reuse_instances`). |
| Spawn Actor: property overrides | `property_overrides` on `spawn_scenes`, `spawn_nodes`, `apply_on_actor` | 1:1 | See above. Writes to a shared sub-resource are shared (make it `resource_local_to_scene`). |
| Create Target Actor | `create_target_node` (+ `spawn_parent_attribute` on spawners) | 1:1 | Named `Node3D` container with groups and an owner policy (follow the component's `transient_output`, or always transient). Reused across regenerations and freed by `cleanup()`. Outputs `@data.target`. Spawners parent under it with `spawn_parent_attribute`, which also accepts per-point parents. |
| Instance pooling (component reuse) | `reuse_instances` on spawners (`FlowSpawnPool`) | Godot-only | Reuses MultiMeshInstance3Ds, scene roots, nodes and spline segments of the same component and node across `generate()` runs when mesh, material, scene or class match. Off by default. |

## nodes_reference rows

Spawner rows (the file lists spawners under Assets):

| Node | Script File | Description |
| --- | --- | --- |
| **Spawn Meshes** | [spawn_meshes.gd](../nodes/spawn_meshes.gd) | Spawns a Mesh Instance on each point, applying the translation, rotation and scale. The instanced mesh can be specified by point if a stream contains the mesh resource to be spawned. The generates meshes are MultiMeshInstance3D. Mesh entries (FlowMeshSpawnEntry) add per-entry weight, material, shadows, visibility range, layers, GI, custom data and collision. |
| **Spawn Scenes** | [spawn_scenes.gd](../nodes/spawn_scenes.gd) | Similar to spawn meshes but a full scene is instantiated on each node. A set of properties can be transfered from the nodes to each instanced scene. property_overrides maps point attributes to (nested) property paths of the instance. |
| **Spawn Nodes** | [spawn_nodes.gd](../nodes/spawn_nodes.gd) | Dynamically instantiates a raw Godot class or custom script node on each point. Properties can be transferred from point attributes to node properties. property_overrides maps point attributes to (nested) property paths of the node. |
| **Spawn Spline Mesh** | [spawn_spline_mesh.gd](../nodes/spawn_spline_mesh.gd) | Deforms a mesh along each segment of the input splines (Path3D nodes or spline shapes). One MeshInstance3D per segment, with a bent ArrayMesh cached per mesh and segment. Settings: forward axis, tangent and up handling, scale along/across, per-segment mesh entries. |
| **Create Target Node** | [create_target_node.gd](../nodes/create_target_node.gd) | Creates a named Node3D container (groups, owner policy) and outputs a reference to it. Spawners parent their content under it through spawn_parent_attribute (e.g. "@data.target"). |
| **Apply On Actor** | [apply_on_actor.gd](../nodes/apply_on_actor.gd) | Applies point attributes and optional transforms onto existing scene nodes. property_overrides maps point attributes to (nested) property paths of each target. |

## DEPRECATIONS rows

None. No default output changes, no symbol is removed or renamed, and existing
tests and baselines are unchanged. The removed `_exit_tree` stubs were empty.

## Changes outside the owned files

None. All edits are to the owned spawner files, the new `spawn/` directory, new
node files and new tests. `node.gd`, `flow_nodes_io.gd`, `flow_node.gd` and the editor are
untouched.
