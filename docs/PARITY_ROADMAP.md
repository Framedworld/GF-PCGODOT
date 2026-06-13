# UE PCG Parity Roadmap

The honest gap list. [COMING_FROM_UNREAL_PCG.md](COMING_FROM_UNREAL_PCG.md) documents what translates today; this file documents what does **not**, why, and the intended design for each gap. Items are roughly ordered by how often a UE tutorial trips over them.

If a tutorial step depends on one of these, the node dictionary marks it **roadmap** and (where one exists) names a workaround.

---

## Implementation status (2026-06)

A first pass has landed groundwork for every item below. Each ships behind
optional streams / opt-in flags / new nodes, so existing `.tres` graphs and
demos are byte-for-byte unchanged. Per-item implementation notes live in
[`_roadmap_notes/`](_roadmap_notes/). The design sections that follow remain the
reference for the *full* intent; "Partial" / "Foundation" mark where only part
of that intent shipped.

| Roadmap item | Status | What landed |
|---|---|---|
| Per-point BoundsMin/Max + Steepness | **Implemented** | Optional `bounds_min`/`bounds_max`/`steepness` streams; `bounds_modifier` PerPointBounds mode; `Data.getEffectiveBounds()`/`getEffectiveSteepness()` |
| Density-aware Difference / Self-Pruning | **Implemented** | `density_function` setting (Binary default / Minimum / Multiply / Subtract) attenuates density instead of hard-removing |
| Quaternion rotation model | **Implemented** | `DataType.Quaternion`, optional `rotation_quat` stream (wins over Euler), `rotator_op` node |
| Attribute domains (`@Data`) | **Implemented** | `Data.data_attrs` + `@data.<name>` selector; `add_attribute` domain toggle; `partition` stamps per-data key |
| Spatial data type lattice | **Partial** | Lightweight `kind` marker; `filter_data_by_type` honest when set. Full typed algebra still out of scope |
| Subdivide Segment | **Implemented** | `subdivide_segment` node |
| Shape grammar | **Implemented** | `grammar_expand` node (UE grammar subset) + `GrammarModuleResourceData` table |
| Landscape paint-layer sampling | **Partial** | `sample_terrain_layers` (generic mask-texture path); terrain-plugin auto-detect deferred |
| GPU execution | **Implemented (escape hatch)** | `compute_kernel` node wrapping a user GLSL compute shader via `RenderingDevice` |
| Hierarchical generation (Grid Size) | **Foundation** | `grid_size` declaration node; per-cell partition *execution* still deferred |
| Async / proximity runtime | **Foundation** | Opt-in resumable, time-sliced evaluator (`begin_evaluation`/`GraphEvaluation.step`) + primitive graph-input fix; proximity scheduling deferred |
| Hardening: node-instance leak | **Done** | Instances pooled/freed after evaluation |
| Hardening: editor/runtime topo sort | **Done** | Unified post-order sort with cycle detection |
| Hardening: primitive graph-input args | **Done** | `FlowData.Data.writeValue` typed-feed in `_coerce_input_data` |
| Hardening: stream-length invariants | **Done** | `registerStream` warns on non-broadcast length mismatch |

---

## Per-point BoundsMin/BoundsMax + Steepness

**Gap.** A UE point carries Scale *and* a separate BoundsMin/BoundsMax pair plus Steepness (the hardness of the point's volume, 1 = binary box, lower = falloff ramp). Here, the `size` stream is simultaneously scale and bounds: `bounds_modifier` collapses min/max into a symmetric extent written into `size`, and any recipe that scales a mesh while keeping collision bounds fixed (or vice versa) cannot be expressed. Steepness does not exist at all, so density falloff at point edges during sampling/projection/difference is always hard.

**Design.** Add optional `bounds_min` / `bounds_max` Vector streams and a `steepness` Float stream as recognized canonical attributes (constants in `flow_data.gd`, same pattern as `density`/`seed`). Consumers resolve them lazily: when absent, derive bounds from `size` exactly as today, so existing graphs are untouched. `bounds_modifier` gains a "write per-point bounds" mode preserving asymmetric min/max; `spawn_meshes` keeps using `size` for instance scale. Steepness feeds a falloff factor in the density-aware versions of Difference/Projection (below).

## Per-point bounds in Difference / Self Pruning

**Gap.** `difference` and `self_pruning` compute overlap from position + `size` AABBs and **hard-remove** points. UE defines set operations as *density function* combinations — a point overlapped by a Difference input can survive with attenuated density (and Steepness shapes the attenuation ramp), and Union/Intersection have selectable density functions (max/add/multiply/min). Tutorials that "soften the road edge" with density-based difference produce a binary cut here.

**Design.** Once per-point bounds/steepness exist, give `difference` a `density_function` setting (`Binary` — today's behavior and the default — `Minimum`, `Multiply`, `Subtract`): instead of dropping overlapped points, compute a per-point overlap factor from box interpenetration shaped by steepness, fold it into the `density` stream, and let an explicit downstream `density_filter` do the culling. `self_pruning` reads `bounds_min`/`bounds_max` when present, falling back to `size`. The RTree native path stays the broadphase; only the resolution step changes.

## Quaternion rotation model

**Gap.** Rotation here is a Vector3 of **Euler degrees** end to end (`eulerToBasis`/`basisToEuler` round-trips), and there are no Quaternion/Rotator/Transform attribute types. UE stores a quaternion in `FTransform`; its Rotator Op / Transform Op node families (combine, invert, lerp, axis rotations) and anything sensitive to gimbal lock or rotation interpolation diverge or can't be expressed. Make/Break Transform Attribute have no equivalent.

**Design.** Add a `Quaternion` attribute data type (PackedFloat32Array ×4 or PackedVector4Array container) alongside the existing types, plus `rotation_quat` as an optional canonical stream that, when present, wins over `rotation` in `getTransformsStream()`. Euler stays the default authoring/UI representation (it is friendlier in an inspector); a `rotator_op` node provides Combine/Invert/Lerp/RotateAroundAxis on either representation, converting through Basis internally. Full Transform-typed attributes are a non-goal until a concrete recipe needs them — compose/decompose nodes cover the rest.

## Hierarchical generation (Grid Size)

**Gap.** UE's HiGen partitions the world into power-of-two grid cells, executes graph sections at different grid sizes (large grids first, results consumed by smaller ones), outputs into separately streamable actors, and dedupes across cells with Cull Points Outside Actor Bounds. There is no equivalent: a `FlowGraphNode3D` evaluates its whole graph over the whole scene, once.

**Design.** Not a single node — an evaluation-scheduler feature. Plan: a `grid_size` declaration node that tags its downstream subgraph with a cell size; `FlowGraphNode3D` gains an optional partition mode that iterates cells (bounds supplied per cell through the existing graph-parameter mechanism, the same plumbing `subgraph` override pins use), evaluates per cell, and parents spawned output under one container node per cell for visibility/streaming control. Parent-grid results are memoized per eval and exposed to child cells as inputs. Honest assessment: large, and gated on the async runtime work below — synchronous per-cell evaluation would multiply the current one-shot cost.

## Async / proximity runtime generation

**Gap.** UE's runtime mode generates and cleans up in proximity to generation sources (players/cameras) with per-grid radii, time-sliced async execution, and component/mesh pooling. Here, runtime generation is one synchronous `evaluate_graph()` on the main thread in `_ready()`, re-triggerable manually via `execute()` — fine for load-time generation, a frame-spike machine for anything live. (The runtime evaluator also has known hardening issues — node-instance leaks per evaluation, primitive-arg input feeding — that are prerequisites to any scheduling work.)

**Design.** Three stages. (1) Hardening: pool/free node instances after evaluation, fix the primitive-args input path, activate the existing recursion guard. (2) Time-slicing: `evaluate_graph` already topo-sorts into an execution list; turn the eval loop into a resumable iterator driven from `_process` with a per-frame millisecond budget (node granularity is enough — the heavy nodes are native-accelerated). (3) Proximity: a `generation_source` marker node + radius settings on `FlowGraphNode3D`, regenerating/cleaning per partition cell as sources move — explicitly dependent on the HiGen partitioning above.

## GPU execution

**Gap.** UE 5.5+ fuses GPU-flagged nodes (Custom HLSL, GPU spawner/copy/transform/partition...) into compute graphs operating on point buffers, including GPU-resident instancing with no CPU readback. Everything here is CPU GDScript plus a native C++ GDExtension for KdTree/RTree queries.

**Design.** Not planned as node-graph-on-GPU. The pragmatic path: (a) keep moving per-point hot loops (transform, noise, filtering) into the existing GDExtension, which already gives order-of-magnitude wins without changing semantics; (b) where massive counts genuinely matter, a dedicated `compute_kernel` node wrapping a user-supplied `.glsl` compute shader via `RenderingDevice`, with declared stream bindings in and out — an escape hatch equivalent to Custom HLSL rather than a transparent "Execute on GPU" flag. Honest assessment: lowest priority; tutorial parity almost never needs it.

## Spatial data type lattice

**Gap.** UE data is typed — Points, Splines, Surfaces, Volumes, Primitive, Composite — with implicit collapse to points and an algebra over the richer types (intersect a surface with a volume *before* sampling, project onto surface data, type-colored pins, Filter Data By Type). Here everything on a wire is point streams; splines and meshes ride along as `node`/`mesh` reference streams, and `filter_data_by_type` classifies heuristically (a NodePath stream literally named `node` means "spline"). The sampling nodes cover the common *uses*, but the algebra does not exist: you sample first, then do set ops on points.

**Design.** Introduce a lightweight `kind` marker on `FlowData.Data` (`points | spline | surface | volume | attr_set`) set by source nodes and respected by `filter_data_by_type` — killing the heuristic, enabling honest pin tinting, with zero `.tres` breakage (absent = points). Surface/volume stay *descriptions* (bounds + reference geometry) that samplers consume; a true implicit-geometry algebra (composite data, deferred sampling) is explicitly out of scope — the point-first model is this addon's identity, and per-point density set-ops (above) recover most of what the algebra buys in practice.

## Shape grammar nodes

**Gap.** UE 5.4+ ships grammar-driven generation (Subdivide Spline / Subdivide Segment consuming a grammar string like `{[A,P]:2,[BL,P]:1}*`, module attribute tables, Duplicate Cross-Section) powering the official fence and building tutorials. Nothing here parses grammars; the dungeon node family and `match_and_set` are the closest spiritual relatives.

**Design.** Two nodes. `subdivide_segment` (below) provides the geometric substrate. Then a `grammar_expand` node: input = segment/spline points with a length attribute; settings = grammar string + a module table (reusing the `assets` resource pattern: symbol → mesh, size, weight); output = one point per expanded module with `symbol`, `module_index`, and fitted transforms, ready for `match_and_set`/`spawn_meshes`. Target the documented UE grammar subset (sequences, `[symbol,behavior]` tuples, repetition `*` / `:N`, weighted choice `{}`); priorities and nested grammars later. This unlocks translating Epic's fence-generator tutorial 1:1.

## Landscape paint-layer sampling

**Gap.** UE's Get Landscape Data exposes paint-layer weights as point attributes ("spawn only on the Grass layer" = Surface Sampler → filter on layer weight). Godot has no landscape actor or paint layers; `scan_meshes` provides geometry only, and `texture_sampler` samples explicit textures, not terrain splat maps.

**Design.** Godot terrain is plugin territory (Terrain3D, HTerrain), so: a `sample_terrain_layers` node that (a) detects known terrain plugin nodes and reads their splat/control maps, or (b) generically accepts N user-assigned mask textures + a world-to-UV mapping, writing one `layer_<name>` Float stream per layer (0..1). Downstream is then pure existing parity: `density_filter` or `attribute_filter_range` on the layer attribute. The generic path (b) ships first — it also covers the "texture-driven placement" tutorial family with explicit masks.

## Subdivide Segment

**Gap.** UE's Subdivide Segment slices a segment/spline span into typed sub-segments by module sizes (the backbone of grammar fences and per-floor building loops, with Duplicate Cross-Section stacking floors). `sample_spline` places points at fixed intervals but doesn't emit sized *segments*, and `split_splines` only approximates Subdivide Spline.

**Design.** A `subdivide_segment` node: input = spline data (or two-point segments); settings = module length list or a target count, fit mode (stretch / clip / pad-ends — matching UE's flex behaviors); output = one point per sub-segment at its center, oriented along the segment, with `length`, `segment_index`, `t_start`/`t_end` attributes. Floor stacking is already expressible (`duplicate_point` with a Y offset ≈ Duplicate Cross-Section), so this node alone unlocks the modular-building tutorial chain.

## Attribute domains (`@Data` / `@Points` / `@Elements`)

**Gap.** UE 5.6 introduced attribute domains: the same data can carry per-point attributes and per-data attributes, addressed via `@Data.` / `@Points.` selector prefixes. Here every stream is per-point (broadcast rules let a 1-length stream act constant-ish, but it is not a distinct domain — `Data.tags` is the only true per-data metadata).

**Design.** Add a `data_attrs: Dictionary` alongside `tags` on `FlowData.Data`, surviving `duplicate()`/`filter()`, plus selector support for a `@data.name` prefix in `findStream()` (returning a synthetic broadcast stream) and in `registerStream()` (writing the dictionary). `add_attribute` gains a domain toggle; `partition` stamps its partition key as a data attribute on each output. Low urgency — `@Data` barely appears in tutorials yet — but cheap, and it removes the "1-length stream as fake constant" idiom.

---

## Engine-hardening notes (not UE features, but parity blockers)

These are correctness items from the core-engine review that gate the roadmap above, listed so the roadmap stays honest:

- **Runtime evaluator leaks node instances per evaluation** (worst inside `loop`, which re-evaluates its subgraph per element). Fix precedes any async/HiGen work.
- **Primitive graph-input args crash the runtime feed** of `FlowGraphNode3D.execute()`; `Data`-typed inputs work. Fix makes "runs in exported game" unconditional.
- **Editor and runtime evaluators differ**: the runtime path has the correct post-order topological sort with cycle detection; the editor path still uses a pre-order walk that misorders diamonds and can recurse on cycles. Unify on the runtime ordering.
- **Stream-length invariants are unchecked** — a mismatched stream silently corrupts downstream filtering. Cheap validation in `registerStream` plus the shared broadcast-read helper closes it.
