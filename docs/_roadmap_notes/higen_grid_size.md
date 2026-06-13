# HiGen Grid Size — Implementation Notes

Roadmap item: **Hierarchical generation (Grid Size)** (see `docs/PARITY_ROADMAP.md`).

This note documents what was shipped as the "tractable first piece", the
annotation mechanism, and the exact integration steps a later worktree must
take to wire up full partition execution.

---

## What was shipped

Two new files — no edits to any existing file:

| File | Role |
|---|---|
| `demo/addons/flow_nodes_editor/nodes/grid_size_settings.gd` | `GridSizeNodeSettings` resource — exports `label` (String) and `cell_size` (float, auto-snapped to nearest power-of-two). Declares the reserved context key constant `CTX_KEY`. |
| `demo/addons/flow_nodes_editor/nodes/grid_size.gd` | `grid_size` node — category "Control Flow", aliases ["Grid Size", "HiGen", "Partition"]. Pass-through (In → Out, data unchanged). Side-effect: writes `cell_size` onto `ctx.variables` under the reserved key. |

The node is auto-discovered by the registry filename scan (no registry edit
needed). It evaluates to a no-op from the graph output's perspective — data
passes through exactly as with a reroute node.

---

## Annotation mechanism

### Key

```
GridSizeNodeSettings.CTX_KEY  ==  "__grid_size__cell_size"
```

This constant lives in `grid_size_settings.gd` so any future code that needs
the key can `preload` the settings script rather than hardcoding a string.

### Written by

`grid_size.gd`, in `execute()`:

```gdscript
ctx.variables[GridSizeSettings.CTX_KEY] = cell_size   # float, power-of-two
```

`ctx` is `FlowData.EvaluationContext`.  `ctx.variables` is a plain `Dictionary`
(already exists on the class; no field additions required).

### Read by (future code)

```gdscript
var declared_cell_size: float = ctx.variables.get(
    GridSizeNodeSettings.CTX_KEY, 0.0
)
if declared_cell_size > 0.0:
    # partition mode is active
```

`0.0` as default means "no grid_size node present → whole-scene evaluation as
today".

### Forward-compatibility notes

- The key prefix `__grid_size__` is reserved namespace. No other node should
  write to `ctx.variables` with this prefix.
- If stacked grid_size nodes are ever supported (coarse-then-fine), the key
  could be extended to `__grid_size__<label>__cell_size` and the scheduler
  collects all matching keys. The current single-key design is sufficient for
  the initial single-tier case and does not block the extension.
- Because `ctx.variables` is a Dictionary (not a typed resource field), no
  changes to `flow_data.gd` were required and existing graphs are fully
  unaffected.

---

## FlowGraphNode3D integration steps (deferred — another worktree)

**Do NOT touch these files in the grid_size node worktree.**  This section is
a precise handoff spec for the scheduler worktree.

### Files to modify

- `demo/addons/flow_nodes_editor/flow_node.gd` — `FlowGraphNode3D` class
  (which is actually in `flow_node.gd`; see the `class_name FlowGraphNode3D`
  declaration at the top of that file).

### New exports to add to FlowGraphNode3D

```gdscript
## When enabled, evaluate_graph runs once per partition cell instead of once
## over the whole scene.  Requires at least one grid_size node in the graph.
@export var partition_mode: bool = false

## Axis-aligned bounding box over which cells are generated.  If zero-size,
## falls back to the scene's root node AABB or a configurable world_bounds.
@export var world_bounds: AABB = AABB()
```

### Changes to `execute()` in FlowGraphNode3D

Replace the single `FlowNodeIOClass.evaluate_graph(...)` call with:

```gdscript
func execute() -> void:
    if not graph:
        push_warning("FlowGraphNode3D: no graph resource assigned")
        return

    # --- Phase 1: dry run to discover declared cell_size --------------------
    # Run evaluation once (or inspect the graph without evaluating) to find
    # any grid_size annotation.  The cheap approach: do one full evaluation
    # into a scratch context, then read the key.
    var probe_ctx = _make_ctx()
    FlowNodeIOClass.evaluate_graph(graph, args if args != null else {}, probe_ctx, {}, 0)
    var declared_cell_size: float = probe_ctx.variables.get(
        _GRID_SIZE_CTX_KEY, 0.0          # constant defined below
    )

    if not partition_mode or declared_cell_size <= 0.0:
        # Non-partitioned path — identical to today's behaviour.
        # Re-use probe_ctx result (spawners already ran) or run fresh:
        _apply_outputs_from_ctx(probe_ctx)   # (new helper — see below)
        return

    # --- Phase 2: per-cell evaluation ---------------------------------------
    var effective_bounds := _resolve_world_bounds()
    var cell := declared_cell_size
    var x_cells := int(ceil(effective_bounds.size.x / cell))
    var z_cells := int(ceil(effective_bounds.size.z / cell))

    for xi in range(x_cells):
        for zi in range(z_cells):
            var cell_origin := effective_bounds.position + Vector3(xi * cell, 0.0, zi * cell)
            var cell_aabb := AABB(cell_origin, Vector3(cell, effective_bounds.size.y, cell))

            # Inject the cell bounds into the graph as runtime_params so that
            # nodes that read bounds (scan_meshes, grid_fill_bounds, etc.) can
            # be parameterised by cell without any node-side changes.
            var cell_args := (args if args != null else {}).duplicate()
            cell_args["__higen_cell_bounds__"] = cell_aabb

            var cell_ctx := _make_ctx()
            cell_ctx.runtime_params["__higen_cell_bounds__"] = cell_aabb
            FlowNodeIOClass.evaluate_graph(graph, cell_args, cell_ctx, {}, 0)

            # Parent spawned output under a per-cell container node for
            # visibility / streaming control.
            _reparent_spawned_to_cell_container(cell_ctx, xi, zi)

# Constant mirroring GridSizeNodeSettings.CTX_KEY (import the script or duplicate):
const _GRID_SIZE_CTX_KEY := "__grid_size__cell_size"
```

### New helpers needed in FlowGraphNode3D

`_make_ctx()` — factors out the ctx construction already in `execute()`:
```gdscript
func _make_ctx() -> FlowData.EvaluationContext:
    var ctx = load("res://addons/flow_nodes_editor/flow_data.gd").EvaluationContext.new()
    ctx.owner = self
    ctx.eval_id = 0
    ctx.gedit_nodes_by_name = {}
    ctx.runtime_params = {}
    return ctx
```

`_resolve_world_bounds()` — returns the effective AABB for partitioning:
```gdscript
func _resolve_world_bounds() -> AABB:
    if world_bounds.size.length() > 0.0:
        return world_bounds
    # Fallback: encompass all direct children that are VisualInstance3D.
    var b := AABB()
    for child in get_children():
        if child is VisualInstance3D:
            b = b.merge(child.get_aabb())
    if b.size.length() == 0.0:
        push_warning("FlowGraphNode3D partition_mode: could not determine world_bounds; using 1024x1024 default")
        b = AABB(Vector3(-512, -128, -512), Vector3(1024, 256, 1024))
    return b
```

`_reparent_spawned_to_cell_container(ctx, xi, zi)` — creates/finds a
`Node3D` child named `cell_%d_%d % [xi, zi]` and re-parents any nodes that
were spawned by this cell's evaluation under it.  Exact implementation
depends on how spawn_meshes / spawn_nodes track their output nodes (they
currently parent to `ctx.owner`).

### Prerequisite: evaluator leak fix

The roadmap hardening notes flag that node instances leak per evaluation
inside `loop` and other re-entrant paths.  Per-cell evaluation multiplies
the evaluation count by (x_cells × z_cells), which will multiply the leak
proportionally.  **The evaluator leak fix is a prerequisite to enabling
partition_mode** — do not ship partition_mode behind a user-visible export
until the leak is fixed.

---

## Status

Full partition execution (Phase 2 above) is **deferred**.  The `grid_size`
node declaration is complete and safe to ship.  Graphs with the node evaluate
identically to graphs without it; the annotation is inert until FlowGraphNode3D
partition_mode is implemented.
