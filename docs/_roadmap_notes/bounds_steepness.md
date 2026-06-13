# Implementation notes: Per-point BoundsMin/BoundsMax + Steepness, and per-point bounds in Difference / Self Pruning

Covers the two PARITY_ROADMAP items:
- "Per-point BoundsMin/BoundsMax + Steepness"
- "Per-point bounds in Difference / Self Pruning"

## Backward-compatibility contract

The new canonical streams (`bounds_min`, `bounds_max`, `steepness`) are **optional**.
When they are absent, every code path resolves bounds symmetrically from the existing
`size` stream exactly as before, and steepness defaults to `1.0` (binary box / hard
edge). All new node settings default to their legacy values. As a result existing
`.tres` graphs and demos are byte-for-byte unchanged.

## flow_data.gd

New canonical stream constants (next to `AttrNormal`):

- `AttrBoundsMin : StringName = &"bounds_min"` — Vector, per-point LOCAL min corner.
- `AttrBoundsMax : StringName = &"bounds_max"` — Vector, per-point LOCAL max corner.
- `AttrSteepness : StringName = &"steepness"` — Float 0..1, point-volume edge hardness.

New `class Data` helpers:

- `getEffectiveBounds() -> Dictionary` → `{ "min": PackedVector3Array, "max": PackedVector3Array }`,
  one entry per point, in LOCAL space (relative to each point's position).
  - If BOTH `bounds_min` and `bounds_max` streams exist, they are used directly
    (asymmetric bounds preserved; length-1 broadcast honored via `bcast_idx`).
  - Otherwise derived symmetrically from `size`: `min = -size*0.5`, `max = +size*0.5`
    (identical to the native RTree's `center ± size*0.5`). Missing `size` → `Vector3.ONE`.
- `getEffectiveSteepness() -> PackedFloat32Array` → one clamped (0..1) value per point.
  Absent stream → all `1.0` (binary, hard edge). Broadcast honored.

## bounds_modifier (node + settings)

`bounds_modifier_settings.gd` gains:

- `enum eOutput { SymmetricSize, PerPointBounds }`
- `@export var output_mode : eOutput = eOutput.SymmetricSize` (legacy default).

`bounds_modifier.gd`:

- `SymmetricSize` (default) — unchanged: collapses `|max-min|` into the `size` stream
  via the existing Set / Add / Multiply modes.
- `PerPointBounds` — writes per-point asymmetric `bounds_min`/`bounds_max` streams and
  leaves `size` untouched. Set replaces bounds with the literal min/max; Add and
  Multiply combine with the current effective bounds (resolved via
  `getEffectiveBounds()`, so they work whether or not bounds already exist).
  Implemented in helper `_write_per_point_bounds()`.

## difference (node + settings)

`difference_settings.gd` gains:

- `enum eDensityFunction { Binary, Minimum, Multiply, Subtract }`
- `@export var density_function : eDensityFunction = eDensityFunction.Binary`
  (legacy default). `exposeParam()` only surfaces it for `A_Minus_B` / `B_Minus_A`.

`difference.gd`:

- `Binary` (default) — unchanged hard-removal (`filter(a_only)` / `filter(b_only)`).
- Non-Binary on the subtractive ops — KEEPS every point; for the broadphase-flagged
  overlap indices it runs a narrowphase against the cutter boxes, computes a per-point
  overlap factor, shapes it by the kept point's steepness, and folds it into `density`.
  Culling is left to a downstream `density_filter`. Implemented in `_attenuate_difference()`.
- The native GDRTree broadphase is unchanged; only the resolution step changed.

Density folds (factor in 0..1):
- `Minimum`  → `density = min(density, 1 - factor)`
- `Multiply` → `density = density * (1 - factor)`
- `Subtract` → `density = density - factor` (clamped to 0)

## self_pruning (node + settings)

`self_pruning_settings.gd` gains the same `eDensityFunction` enum and
`density_function` export (default `Binary`); only exposed in `BoundsOverlap` mode.

`self_pruning.gd`:

- The native `self_prune` broadphase is fed `prune_centers` / `prune_sizes`. When no
  bounds streams exist these equal the original `posA` / `szA` (byte-for-byte identical
  inputs). When bounds streams ARE present, they are honored by converting effective
  per-point bounds into an equivalent center-offset + extent for the unchanged native
  call (UE parity: "reads bounds_min/bounds_max when present, falling back to size").
- `Binary` (default) — unchanged: `filter(keep_indices)`.
- Non-Binary — KEEPS every point; pruned points (complement of the survivor keep-list)
  have their density attenuated by their strongest interpenetration with any survivor
  box, shaped by steepness. Implemented in `_attenuate_self_prune()`.

## Shared helper: bounds_overlap_util.gd (new file)

`demo/addons/flow_nodes_editor/nodes/bounds_overlap_util.gd` — `class_name BoundsOverlapUtil`,
`extends Object`, static-only. Holds the overlap math shared by difference / self_pruning:

- `world_aabbs(data, positions)` — per-point world AABB min/max (uses `getEffectiveBounds`).
- `penetration_ratio(a_min,a_max,b_min,b_max)` — fraction of box A inside box B (0..1),
  product of per-axis overlap fractions; robust to zero-extent axes.
- `shape_factor(ratio, steepness)` — steepness=1 → binary (any overlap = 1.0);
  steepness<1 → power-ramp falloff (steepness 0 ≈ linear ratio).
- `fold_density(density, factor, fn, fn_min, fn_mul, fn_sub)` — applies the density function.

Note: this file lives in the `nodes/` dir, which the editor's node scanner walks. It is
not a `FlowNodeBase`, so the scanner instantiates it, sees it is not a node, frees it, and
skips it with a one-time `Skipping non-FlowNode script` warning (the same graceful path the
scanner already uses). It is never added to the node palette.

## Files changed

- `demo/addons/flow_nodes_editor/flow_data.gd` (constants + helpers)
- `demo/addons/flow_nodes_editor/nodes/bounds_modifier.gd`
- `demo/addons/flow_nodes_editor/nodes/bounds_modifier_settings.gd`
- `demo/addons/flow_nodes_editor/nodes/difference.gd`
- `demo/addons/flow_nodes_editor/nodes/difference_settings.gd`
- `demo/addons/flow_nodes_editor/nodes/self_pruning.gd`
- `demo/addons/flow_nodes_editor/nodes/self_pruning_settings.gd`
- `demo/addons/flow_nodes_editor/nodes/bounds_overlap_util.gd` (new)
- `docs/_roadmap_notes/bounds_steepness.md` (this file, new)

## Risks / assumptions

- No Godot binary is available, so nothing was run. Syntax was reviewed by hand against
  the existing nodes' conventions (typed arrays, StringName stream names, `bcast_idx`).
- The non-Binary narrowphase is O(kept_overlap × cutter_count) / O(pruned × survivors).
  It only runs on the broadphase-flagged subset and only in non-default modes, so the
  default (Binary) path keeps the native broadphase's full performance.
- `getEffectiveBounds()` returns bounds in LOCAL space; consumers add `position` to get
  world boxes. The symmetric fallback reproduces the native `center ± size*0.5` boxes.
- The `bounds_overlap_util.gd` scanner warning is cosmetic; documented above.
- `steepness` shaping (`shape_factor`) is a chosen power-ramp; it is monotonic and
  satisfies the endpoints (1 = binary, 0 = linear) but is not tuned against a specific UE
  reference curve.
